import Foundation
import AVFoundation
import CoreAudio
import AppKit
import os

/// Manages AVAudioEngine lifecycle and audio buffer delivery.
/// No business logic — only audio capture, downmix, RMS, and ring buffer.
@MainActor
final class AudioCaptureSession {

    // MARK: - Config
    var selectedDeviceID: AudioDeviceID = 0
    var useVoiceProcessing: Bool = false
    var allowAutomaticHeadsetVoiceProcessing: Bool = true
    var preferSystemManagedHeadsetRoute: Bool = false

    // MARK: - Callbacks
    /// Called on the audio thread for every buffer. Feed this to RecognitionSession.append().
    var onBuffer: ((AVAudioPCMBuffer) -> Void)?
    /// Called on main thread. isActive is VAD result; rmsLevel is scaled RMS.
    var onVoiceActivityChanged: ((Bool, Float) -> Void)?

    // MARK: - State
    private(set) var isRunning: Bool = false
    private var audioEngine: AVAudioEngine?
    private var ringBuffer: [AVAudioPCMBuffer] = []
    private let ringBufferCapacity = 10
    private var adaptiveNoiseFloor: Float = 0.0
    private var adaptiveVADThreshold: Float = 0.07
    private var lastVoiceActivity: Bool = false
    private var lastLoggedAdaptiveThreshold: Float = -1
    private var diagnosticsWindowUntil: Date = .distantPast
    private var diagnosticsLastLogAt: Date = .distantPast
    private var diagnosticsPeakRMS: Float = 0
    private var diagnosticsVoiceActiveCount: Int = 0
    private var diagnosticsBufferCount: Int = 0
    private var runningSelectedDeviceID: AudioDeviceID = 0
    private var runningSystemManagedRoute: Bool = false
    private let log = GlobalLogger.speech

    private struct BoundInputSnapshot {
        let currentDeviceID: AudioDeviceID
        let currentDeviceName: String
        let defaultInputID: AudioDeviceID
        let defaultInputName: String
        let defaultOutputID: AudioDeviceID
        let defaultOutputName: String
    }

    // MARK: - Public API

    func start() throws {
        let requestedName = deviceName(selectedDeviceID)
        if let e = audioEngine, e.isRunning {
            let configChanged =
                runningSelectedDeviceID != selectedDeviceID
                || runningSystemManagedRoute != preferSystemManagedHeadsetRoute
            if !configChanged {
                GlobalLogger.speech.info(
                    "AudioCaptureSession start skipped alreadyRunning selectedID=\(selectedDeviceID) systemManagedRoute=\(preferSystemManagedHeadsetRoute)"
                )
                return
            }
            GlobalLogger.speech.info(
                "AudioCaptureSession restarting for route change oldSelectedID=\(runningSelectedDeviceID) newSelectedID=\(selectedDeviceID) oldSystemManagedRoute=\(runningSystemManagedRoute) newSystemManagedRoute=\(preferSystemManagedHeadsetRoute)"
            )
            stop()
        }

        GlobalLogger.speech.info(
            "AudioCaptureSession start requested selectedID=\(selectedDeviceID) selectedName=\(requestedName) preferSystemManagedHeadsetRoute=\(preferSystemManagedHeadsetRoute)"
        )
        do {
            try startEngine(preferSystemManagedRoute: preferSystemManagedHeadsetRoute)
        } catch {
            let nsError = error as NSError
            let shouldFallbackToSystemManagedRoute =
                !preferSystemManagedHeadsetRoute
                && isHeadsetLikeInputName(requestedName)
                && (nsError.domain == "com.apple.coreaudio.avfaudio" || nsError.code == -10868)
            guard shouldFallbackToSystemManagedRoute else { throw error }

            GlobalLogger.speech.info(
                "AudioCaptureSession fallback to system-managed headset route selectedID=\(selectedDeviceID) selectedName=\(requestedName) domain=\(nsError.domain) code=\(nsError.code)"
            )
            stop()
            try startEngine(preferSystemManagedRoute: true)
        }
    }

    private func startEngine(preferSystemManagedRoute: Bool) throws {
        logMicrophoneMode(context: "before-start")
        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        setInputDevice(for: engine, preferSystemManagedRoute: preferSystemManagedRoute)

        if #available(macOS 10.15, *) {
            let enable = useVoiceProcessing || shouldAutoEnableVoiceProcessingIO()
            if enable {
                do {
                    try inputNode.setVoiceProcessingEnabled(true)
                    os_log("VoiceProcessingIO: on", log: log, type: .info)
                } catch {
                    os_log("VoiceProcessingIO set failed: %{public}@", log: log, type: .error, error.localizedDescription)
                }
            } else if allowAutomaticHeadsetVoiceProcessing && shouldEnableVoiceProcessingForHeadsetMicMode() {
                os_log(
                    "VoiceProcessingIO: skip headset mic-mode override to preserve AirPods microphone reliability",
                    log: log,
                    type: .info
                )
            } else {
                // Avoid explicitly forcing "off" on every engine start, which can
                // reset the user's current Mic Mode back to Standard in Control Center.
                os_log("VoiceProcessingIO: preserve system/default", log: log, type: .info)
            }
        }

        let fmt = inputNode.outputFormat(forBus: 0)
        if fmt.sampleRate == 0 {
            os_log("Error: Input Node Sample Rate is 0", log: log, type: .error)
        }

        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: nil) { [weak self] buffer, _ in
            guard let self else { return }
            let mono = self.downmixToMono(buffer)
            let rms = self.calculateRMS(mono)

            HUDManager.shared.updateAudioLevel(rms)
            self.onBuffer?(mono)

            let isActive = self.classifyVoiceActivity(rms: rms)
            self.logCaptureDiagnostics(rms: rms, isActive: isActive, format: mono.format)

            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.onVoiceActivityChanged?(isActive, rms)
                self.ringBuffer.append(mono)
                if self.ringBuffer.count > self.ringBufferCapacity {
                    self.ringBuffer.removeFirst()
                }
            }
        }

        engine.prepare()
        try engine.start()
        audioEngine = engine
        isRunning = true
        runningSelectedDeviceID = selectedDeviceID
        runningSystemManagedRoute = preferSystemManagedRoute
        resetCaptureDiagnostics()
        logRouteSnapshot(context: "after-start")
        logMicrophoneMode(context: "after-start")
        GlobalLogger.speech.info(
            "AudioCaptureSession started selectedID=\(selectedDeviceID) selectedName=\(deviceName(selectedDeviceID)) systemManagedRoute=\(preferSystemManagedRoute)"
        )
        os_log("AudioCaptureSession started.", log: log, type: .info)
    }

    func stop() {
        audioEngine?.stop()
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine = nil
        ringBuffer.removeAll()
        adaptiveNoiseFloor = 0
        adaptiveVADThreshold = Float(UserDefaults.standard.object(forKey: "micProgressVADThreshold") as? Double ?? 0.07)
        lastVoiceActivity = false
        lastLoggedAdaptiveThreshold = -1
        diagnosticsWindowUntil = .distantPast
        isRunning = false
        runningSelectedDeviceID = 0
        runningSystemManagedRoute = false
        logRouteSnapshot(context: "after-stop")
        logMicrophoneMode(context: "after-stop")
        os_log("AudioCaptureSession stopped.", log: log, type: .info)
    }

    /// Returns buffered audio for pre-buffering new recognition sessions.
    func drainRingBuffer() -> [AVAudioPCMBuffer] {
        return ringBuffer
    }

    // MARK: - Private

    private func downmixToMono(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer {
        let fmt = buffer.format
        guard fmt.channelCount > 1,
              let monoFmt = AVAudioFormat(commonFormat: fmt.commonFormat,
                                          sampleRate: fmt.sampleRate,
                                          channels: 1,
                                          interleaved: false),
              let mono = AVAudioPCMBuffer(pcmFormat: monoFmt, frameCapacity: buffer.frameCapacity)
        else { return buffer }

        mono.frameLength = buffer.frameLength
        if let src = buffer.floatChannelData?[0], let dst = mono.floatChannelData?[0] {
            memcpy(dst, src, Int(buffer.frameLength) * MemoryLayout<Float>.size)
        }
        return mono
    }

    private func calculateRMS(_ buffer: AVAudioPCMBuffer) -> Float {
        guard let data = buffer.floatChannelData?[0] else { return 0 }
        let count = Int(buffer.frameLength)
        guard count > 0 else { return 0 }
        let ptr = UnsafeBufferPointer(start: data, count: count)
        var sum: Float = 0
        for i in 0..<count { let s = ptr[i]; sum += s * s }
        // Non-linear scaling boosts responsiveness for quieter mics.
        return sqrt(sqrt(sum / Float(count)))
    }

    private func classifyVoiceActivity(rms: Float) -> Bool {
        let base = Float(UserDefaults.standard.object(forKey: "micProgressVADThreshold") as? Double ?? 0.07)
        let adaptiveEnabled = UserDefaults.standard.object(forKey: "adaptiveVADEnabled") as? Bool ?? true
        guard adaptiveEnabled else { return rms >= base }

        if adaptiveNoiseFloor <= 0 {
            adaptiveNoiseFloor = max(0.001, min(rms, base))
            adaptiveVADThreshold = base
        }

        // Update noise floor only when we are close to quiet baseline.
        let nearQuiet = rms <= max(adaptiveVADThreshold * 0.78, adaptiveNoiseFloor * 1.35)
        if nearQuiet {
            let alpha: Float = 0.08
            adaptiveNoiseFloor = max(0.001, adaptiveNoiseFloor * (1 - alpha) + rms * alpha)
        }

        let dynamic = adaptiveNoiseFloor * 2.2 + 0.01
        adaptiveVADThreshold = min(max(max(base, dynamic), 0.03), 0.85)

        // Hysteresis: once active, require slightly less energy to keep active.
        let threshold = lastVoiceActivity ? adaptiveVADThreshold * 0.86 : adaptiveVADThreshold
        let isActive = rms >= threshold
        lastVoiceActivity = isActive

        if abs(adaptiveVADThreshold - lastLoggedAdaptiveThreshold) > 0.015 {
            lastLoggedAdaptiveThreshold = adaptiveVADThreshold
            os_log("Adaptive VAD threshold=%.3f noiseFloor=%.3f rms=%.3f", log: log, type: .debug, adaptiveVADThreshold, adaptiveNoiseFloor, rms)
        }

        return isActive
    }

    private func setInputDevice(for engine: AVAudioEngine, preferSystemManagedRoute: Bool) {
        guard selectedDeviceID != 0 else { return }
        let selectedName = deviceName(selectedDeviceID)
        if preferSystemManagedRoute && shouldUseSystemManagedHeadsetRoute(selectedName: selectedName) {
            os_log(
                "AudioCaptureSession using system-managed headset route for input id=%d name=%{public}@",
                log: log,
                type: .info,
                selectedDeviceID,
                selectedName
            )
            return
        }
        guard let au = engine.inputNode.audioUnit else { return }
        var deviceID = selectedDeviceID
        let err = AudioUnitSetProperty(
            au,
            kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global,
            0,
            &deviceID,
            UInt32(MemoryLayout<AudioDeviceID>.size)
        )
        if err != noErr {
            GlobalLogger.speech.info(
                "AudioCaptureSession failed to bind requestedID=\(deviceID) requestedName=\(deviceName(deviceID)) err=\(err)"
            )
            os_log("Failed to set input device %d: err=%d", log: log, type: .error, deviceID, err)
        } else {
            let bound = currentBoundInputSnapshot(for: engine)
            GlobalLogger.speech.info(
                "AudioCaptureSession selected input device requestedID=\(deviceID) requestedName=\(deviceName(deviceID)) boundID=\(bound.currentDeviceID) boundName=\(bound.currentDeviceName)"
            )
            os_log(
                "AudioCaptureSession selected input device requestedID=%d requestedName=%{public}@ boundID=%d boundName=%{public}@",
                log: log,
                type: .info,
                deviceID,
                deviceName(deviceID),
                bound.currentDeviceID,
                bound.currentDeviceName
            )
        }
    }

    private func currentBoundInputSnapshot(for engine: AVAudioEngine) -> BoundInputSnapshot {
        let defaultInputID = defaultDeviceID(kAudioHardwarePropertyDefaultInputDevice) ?? 0
        let defaultOutputID = defaultDeviceID(kAudioHardwarePropertyDefaultOutputDevice) ?? 0
        guard let au = engine.inputNode.audioUnit else {
            return BoundInputSnapshot(
                currentDeviceID: 0,
                currentDeviceName: "",
                defaultInputID: defaultInputID,
                defaultInputName: deviceName(defaultInputID),
                defaultOutputID: defaultOutputID,
                defaultOutputName: deviceName(defaultOutputID)
            )
        }

        var currentID: AudioDeviceID = 0
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioUnitGetProperty(
            au,
            kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global,
            0,
            &currentID,
            &size
        )
        if status != noErr {
            os_log("AudioCaptureSession failed to read bound input device: err=%d", log: log, type: .error, status)
            currentID = 0
        }
        return BoundInputSnapshot(
            currentDeviceID: currentID,
            currentDeviceName: deviceName(currentID),
            defaultInputID: defaultInputID,
            defaultInputName: deviceName(defaultInputID),
            defaultOutputID: defaultOutputID,
            defaultOutputName: deviceName(defaultOutputID)
        )
    }

    private func shouldUseSystemManagedHeadsetRoute(selectedName: String) -> Bool {
        guard isHeadsetLikeInputName(selectedName) else { return false }

        let defaultInputID = defaultDeviceID(kAudioHardwarePropertyDefaultInputDevice) ?? 0
        let defaultOutputID = defaultDeviceID(kAudioHardwarePropertyDefaultOutputDevice) ?? 0
        let defaultInputName = deviceName(defaultInputID)
        let defaultOutputName = deviceName(defaultOutputID)

        let sameAsDefaultInput = normalizedDeviceName(defaultInputName) == normalizedDeviceName(selectedName)
        let outputIsHeadset = isHeadsetLikeInputName(defaultOutputName)

        return sameAsDefaultInput || outputIsHeadset
    }

    private func normalizedDeviceName(_ raw: String) -> String {
        raw
            .lowercased()
            .replacingOccurrences(of: "麦克风", with: "")
            .replacingOccurrences(of: "microphone", with: "")
            .replacingOccurrences(of: "(输入)", with: "")
            .replacingOccurrences(of: "(input)", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func isHeadsetLikeInputName(_ raw: String) -> Bool {
        let name = raw.lowercased()
        return name.contains("airpods")
            || name.contains("beats")
            || name.contains("headphone")
            || name.contains("earphone")
            || name.contains("bluetooth")
            || name.contains("耳机")
    }

    private func shouldAutoEnableVoiceProcessingIO() -> Bool {
        // Default ON for built-in mic + speaker playback. This is the most common
        // setup where video/audio playback leaks back into speech recognition.
        // Teams can still opt out via UserDefaults if needed.
        guard UserDefaults.standard.object(forKey: "autoVoiceProcessingForSpeakers") as? Bool ?? true else { return false }

        let inputID = selectedDeviceID != 0 ? selectedDeviceID : (defaultDeviceID(kAudioHardwarePropertyDefaultInputDevice) ?? 0)
        let outputID = defaultDeviceID(kAudioHardwarePropertyDefaultOutputDevice) ?? 0
        let inName = deviceName(inputID).lowercased()
        let outName = deviceName(outputID).lowercased()

        let isBuiltInMic = inName.contains("built-in") || inName.contains("internal") ||
                           inName.contains("macbook") || inName.contains("imac") || inName.contains("内建")
        let isHeadphones = outName.contains("airpods") || outName.contains("headphone") ||
                           outName.contains("earphone") || outName.contains("耳机")

        if isBuiltInMic && !isHeadphones {
            os_log("Auto VoiceProcessingIO: input='%{public}@' output='%{public}@' -> enabled",
                   log: log, type: .info, inName, outName)
            return true
        }
        return false
    }

    private func shouldEnableVoiceProcessingForHeadsetMicMode() -> Bool {
        // Headset / AirPods paths are kept on the native route. Forcing
        // VoiceProcessingIO or trying to mirror Control Center mic modes here
        // has repeatedly destabilized input capture after route changes.
        return false
    }

    private func defaultDeviceID(_ selector: AudioObjectPropertySelector) -> AudioDeviceID? {
        var addr = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var id: AudioDeviceID = 0
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        return AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &id) == noErr && id != 0 ? id : nil
    }

    private func deviceName(_ id: AudioDeviceID) -> String {
        guard id != 0 else { return "" }
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyName,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let ref = UnsafeMutablePointer<CFString?>.allocate(capacity: 1)
        ref.initialize(to: nil)
        defer {
            ref.deinitialize(count: 1)
            ref.deallocate()
        }
        var size = UInt32(MemoryLayout<CFString?>.size)
        guard AudioObjectGetPropertyData(id, &addr, 0, nil, &size, ref) == noErr,
              let resolved = ref.pointee else { return "" }
        return resolved as String
    }

    private func logMicrophoneMode(context: String) {
        guard #available(macOS 12.0, *) else { return }

        let preferred = AVCaptureDevice.preferredMicrophoneMode
        let active = AVCaptureDevice.activeMicrophoneMode
        os_log(
            "MicrophoneMode (%{public}@): preferred=%{public}@ active=%{public}@",
            log: log,
            type: .info,
            context,
            microphoneModeLabel(preferred),
            microphoneModeLabel(active)
        )
    }

    private func resetCaptureDiagnostics() {
        diagnosticsWindowUntil = Date().addingTimeInterval(8)
        diagnosticsLastLogAt = .distantPast
        diagnosticsPeakRMS = 0
        diagnosticsVoiceActiveCount = 0
        diagnosticsBufferCount = 0
    }

    private func logCaptureDiagnostics(rms: Float, isActive: Bool, format: AVAudioFormat) {
        let now = Date()
        guard now < diagnosticsWindowUntil else { return }

        diagnosticsPeakRMS = max(diagnosticsPeakRMS, rms)
        diagnosticsBufferCount += 1
        if isActive { diagnosticsVoiceActiveCount += 1 }

        guard now.timeIntervalSince(diagnosticsLastLogAt) >= 1.0 else { return }
        diagnosticsLastLogAt = now

        let bound = audioEngine.map(currentBoundInputSnapshot(for:)) ?? BoundInputSnapshot(
            currentDeviceID: 0,
            currentDeviceName: "",
            defaultInputID: defaultDeviceID(kAudioHardwarePropertyDefaultInputDevice) ?? 0,
            defaultInputName: deviceName(defaultDeviceID(kAudioHardwarePropertyDefaultInputDevice) ?? 0),
            defaultOutputID: defaultDeviceID(kAudioHardwarePropertyDefaultOutputDevice) ?? 0,
            defaultOutputName: deviceName(defaultDeviceID(kAudioHardwarePropertyDefaultOutputDevice) ?? 0)
        )
        os_log(
            "AudioCapture diag: selectedID=%d selectedName='%{public}@' boundID=%d boundName='%{public}@' defaultInputID=%d defaultInputName='%{public}@' peakRMS=%.3f activeBuffers=%d/%d sampleRate=%.1f channels=%d",
            log: log,
            type: .info,
            selectedDeviceID,
            deviceName(selectedDeviceID),
            bound.currentDeviceID,
            bound.currentDeviceName,
            bound.defaultInputID,
            bound.defaultInputName,
            diagnosticsPeakRMS,
            diagnosticsVoiceActiveCount,
            diagnosticsBufferCount,
            format.sampleRate,
            Int(format.channelCount)
        )
    }

    private func logRouteSnapshot(context: String) {
        let selectedID = selectedDeviceID
        let bound = audioEngine.map(currentBoundInputSnapshot(for:)) ?? BoundInputSnapshot(
            currentDeviceID: 0,
            currentDeviceName: "",
            defaultInputID: defaultDeviceID(kAudioHardwarePropertyDefaultInputDevice) ?? 0,
            defaultInputName: deviceName(defaultDeviceID(kAudioHardwarePropertyDefaultInputDevice) ?? 0),
            defaultOutputID: defaultDeviceID(kAudioHardwarePropertyDefaultOutputDevice) ?? 0,
            defaultOutputName: deviceName(defaultDeviceID(kAudioHardwarePropertyDefaultOutputDevice) ?? 0)
        )
        os_log(
            "AudioCapture route (%{public}@): selectedID=%d selectedName=%{public}@ boundInputID=%d boundInputName=%{public}@ defaultInputID=%d defaultInputName=%{public}@ defaultOutputID=%d defaultOutputName=%{public}@",
            log: log,
            type: .info,
            context,
            selectedID,
            deviceName(selectedID),
            bound.currentDeviceID,
            bound.currentDeviceName,
            bound.defaultInputID,
            bound.defaultInputName,
            bound.defaultOutputID,
            bound.defaultOutputName
        )
    }

    @available(macOS 12.0, *)
    private func microphoneModeLabel(_ mode: AVCaptureDevice.MicrophoneMode) -> String {
        switch mode {
        case .standard:
            return "standard"
        case .wideSpectrum:
            return "wideSpectrum"
        case .voiceIsolation:
            return "voiceIsolation"
        @unknown default:
            return "unknown"
        }
    }
}
