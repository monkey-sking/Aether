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
    private let log = GlobalLogger.speech

    // MARK: - Public API

    func start() throws {
        if let e = audioEngine, e.isRunning { return }

        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        setInputDevice(for: engine)

        if #available(macOS 10.15, *) {
            let enable = useVoiceProcessing || shouldAutoEnableVoiceProcessingIO()
            if enable {
                do {
                    try inputNode.setVoiceProcessingEnabled(true)
                    os_log("VoiceProcessingIO: on", log: log, type: .info)
                } catch {
                    os_log("VoiceProcessingIO set failed: %{public}@", log: log, type: .error, error.localizedDescription)
                }
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

            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.onVoiceActivityChanged?(isActive, rms)
                self.ringBuffer.append(mono)
                if self.ringBuffer.count > self.ringBufferCapacity {
                    self.ringBuffer.removeFirst()
                }
            }
        }

        audioEngine = engine
        engine.prepare()
        try engine.start()
        isRunning = true
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
        isRunning = false
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
        adaptiveVADThreshold = min(max(max(base, dynamic), 0.03), 0.35)

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

    private func setInputDevice(for engine: AVAudioEngine) {
        guard selectedDeviceID != 0 else { return }
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
            os_log("Failed to set input device %d: err=%d", log: log, type: .error, deviceID, err)
        }
    }

    private func shouldAutoEnableVoiceProcessingIO() -> Bool {
        guard UserDefaults.standard.object(forKey: "autoVoiceProcessingForSpeakers") as? Bool ?? true else { return false }

        func defaultDeviceID(_ selector: AudioObjectPropertySelector) -> AudioDeviceID? {
            var addr = AudioObjectPropertyAddress(
                mSelector: selector,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            var id: AudioDeviceID = 0
            var size = UInt32(MemoryLayout<AudioDeviceID>.size)
            return AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &id) == noErr && id != 0 ? id : nil
        }

        func deviceName(_ id: AudioDeviceID) -> String {
            var addr = AudioObjectPropertyAddress(
                mSelector: kAudioObjectPropertyName,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            var ref: CFString = "" as CFString
            var size = UInt32(MemoryLayout<CFString>.size)
            guard AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &ref) == noErr else { return "" }
            return ref as String
        }

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
}
