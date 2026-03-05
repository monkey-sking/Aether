import Foundation
import AVFoundation
import Speech
import AppKit
import os
import ApplicationServices
import Combine
import CoreAudio
import IOKit

struct AudioInputDevice: Identifiable, Hashable {
    let id: AudioDeviceID
    let name: String
    let uid: String
    let iconName: String
    static let defaultSystem = AudioInputDevice(id: 0, name: String(localized: "settings.default_device"), uid: "SystemDefault", iconName: "mic.slash")
}

struct UtteranceExecutionGuard {
    private var seenOrder: [String] = []
    private var seenSet: Set<String> = []
    private let maxHistory: Int
    init(maxHistory: Int = 64) { self.maxHistory = max(8, maxHistory) }
    mutating func shouldExecute(sessionGeneration: Int, utteranceID: Int) -> Bool {
        guard utteranceID > 0 else { return true }
        let key = "\(sessionGeneration)#\(utteranceID)"
        if seenSet.contains(key) { return false }
        seenSet.insert(key)
        seenOrder.append(key)
        while seenOrder.count > maxHistory { let r = seenOrder.removeFirst(); seenSet.remove(r) }
        return true
    }
    mutating func reset() { seenOrder.removeAll(); seenSet.removeAll() }
}

@MainActor
final class SpeechManager: ObservableObject {
    private let log = GlobalLogger.speech

    // MARK: - Intent Pipeline (unchanged)
    private struct IntentJob: Sendable {
        let seq: Int; let intent: VoiceIntent; let localeIdentifier: String
        let llmEnhancementEnabled: Bool; let originSessionGeneration: Int; let utteranceID: Int
        let sessionTypingMode: Bool; let streamedTextSnapshot: String; let screenTypedCount: Int
        let targetPID: pid_t?; let targetBundleID: String?; let targetElementFingerprint: String?
    }
    private struct ProcessedJob: Sendable {
        let seq: Int; let intent: VoiceIntent; let localeIdentifier: String
        let originSessionGeneration: Int; let utteranceID: Int
        let sessionTypingMode: Bool; let streamedTextSnapshot: String; let screenTypedCount: Int
        let targetPID: pid_t?; let targetBundleID: String?; let targetElementFingerprint: String?
        let diagnostics: String?
    }
    private actor IntentPipeline {
        private var nextSeq: Int = 0; private var expectedSeq: Int = 0
        private var readyBySeq: [Int: ProcessedJob] = [:]
        func allocateSeq() -> Int { let s = nextSeq; nextSeq += 1; return s }
        func submit(_ job: ProcessedJob) -> [ProcessedJob] {
            readyBySeq[job.seq] = job
            var out: [ProcessedJob] = []
            while let j = readyBySeq.removeValue(forKey: expectedSeq) { out.append(j); expectedSeq += 1 }
            return out
        }
    }

    // MARK: - Published Properties (all preserved)
    @Published var status: String = "Idle"
    @Published var lastTranscript: String = ""
    @Published var lastError: String = ""
    @Published private(set) var accessibilityTrustedSnapshot: Bool = false
    @Published var availableInputDevices: [AudioInputDevice] = []
    @Published var selectedInputDeviceID: AudioDeviceID = 0 {
        didSet {
            if oldValue != selectedInputDeviceID {
                let active = audioCapture.isRunning || recognitionSession.isRunning || isAlwaysListeningEnabled
                if active { scheduleEngineRestart(reason: "input-device-selection") }
            }
        }
    }
    @Published var isPTTEnabled: Bool = UserDefaults.standard.object(forKey: "isPTTEnabled") as? Bool ?? true {
        didSet { UserDefaults.standard.set(isPTTEnabled, forKey: "isPTTEnabled"); syncRecognitionState() }
    }
    @Published var activeLocale: Locale = Locale(identifier: "zh-CN") {
        didSet {
            if oldValue.identifier != activeLocale.identifier {
                if isAlwaysListeningEnabled { startContinuous() }
            }
        }
    }
    @Published var isAlwaysListeningEnabled: Bool = UserDefaults.standard.bool(forKey: "isAlwaysListeningEnabled") {
        didSet { UserDefaults.standard.set(isAlwaysListeningEnabled, forKey: "isAlwaysListeningEnabled"); syncRecognitionState() }
    }
    @Published var isDirectCommandEnabled: Bool = false
    @Published var isWakeWordEnabled: Bool = UserDefaults.standard.object(forKey: "isWakeWordEnabled") as? Bool ?? true {
        didSet { UserDefaults.standard.set(isWakeWordEnabled, forKey: "isWakeWordEnabled"); syncRecognitionState() }
    }
    @Published var isGazeWakeEnabled: Bool = UserDefaults.standard.object(forKey: "isGazeWakeEnabled") as? Bool ?? true {
        didSet { UserDefaults.standard.set(isGazeWakeEnabled, forKey: "isGazeWakeEnabled") }
    }
    @Published var isLLMEnhancementEnabled: Bool = false
    @Published var isAutoPunctuationEnabled: Bool = UserDefaults.standard.object(forKey: "isAutoPunctuationEnabled") as? Bool ?? true {
        didSet { UserDefaults.standard.set(isAutoPunctuationEnabled, forKey: "isAutoPunctuationEnabled") }
    }
    @Published var isDictating: Bool = false
    @Published var lastWakeTime: Date?

    // MARK: - Sub-modules
    private let audioCapture = AudioCaptureSession()
    private let recognitionSession = RecognitionSession()
    private let wakeWordDetector = WakeWordDetector()
    private let eosDetector = EOSDetector()
    private let dictationHandler: DictationHandler
    private let commandHandler = CommandHandler()
    private let injector = TextInjector()

    // MARK: - Internal State
    var onIntent: ((VoiceIntent) -> Void)?
    var llmProvider: LLMProvider?
    var explicitLocaleIdentifier: String? {
        get { UserDefaults.standard.string(forKey: "speechLocaleIdentifier") }
        set { UserDefaults.standard.set(newValue, forKey: "speechLocaleIdentifier"); refreshLocale() }
    }
    var lastNonEnglishLocaleIdentifier: String {
        get { UserDefaults.standard.string(forKey: "lastNonEnglishLocaleIdentifier") ?? "zh-CN" }
        set { UserDefaults.standard.set(newValue, forKey: "lastNonEnglishLocaleIdentifier") }
    }

    private var lastLoggedHUDIcon: String?
    private var lastLoggedAirPodSide: AirPodSide = .none
    private var isPTTHeld: Bool = false
    private var wasAwake: Bool = false
    private var isStopping: Bool = false
    private var sessionGeneration: Int = 0
    private var activeUtteranceID: Int = 0
    private var nextUtteranceID: Int = 1
    private var sessionTypingMode: Bool = false
    private var sessionTargetPID: pid_t?
    private var sessionTargetBundleID: String?
    private var sessionTargetElementFingerprint: String?
    private var didLogSessionTargetMismatch: Bool = false
    private var lastFocusToastAt: Date = .distantPast
    private var hudOverrideUntil: Date = .distantPast
    private var hudOverrideMode: HUDMode = .command
    private var hudOverrideMessage: String = ""
    private var hudOverrideIcon: String = "info.circle"
    private var isUtteranceActive: Bool = false
    private var cachedTypingMode: Bool = false
    private var lastTypingCheckAt: Date = .distantPast
    private var lastChangeAt: Date?
    private var lastStableText: String = ""
    private var continuousTimer: Timer?
    private var stopTimer: Timer?
    private var finalizationWorkItem: DispatchWorkItem?
    private var pendingEngineRestartWorkItem: DispatchWorkItem?
    private var lastEngineRestartAt: Date = .distantPast
    private let engineRestartDebounce: TimeInterval = 0.55
    private let engineRestartMinInterval: TimeInterval = 1.5
    private var continuousRecoveryGraceUntil: Date = .distantPast
    private var lastContinuousStartAt: Date = .distantPast
    private var cancellables = Set<AnyCancellable>()
    private let intentPipeline = IntentPipeline()
    private var utteranceExecutionGuard = UtteranceExecutionGuard(maxHistory: 128)
    private var lastHandledSessionGeneration: Int = -1
    private var lastHandledUtteranceID: Int = -1
    private var lastHandledTranscript: String = ""
    private var lastHandledAt: Date = .distantPast
    // Mic progress tracking (kept for HUD ring)
    private var micProgressTimer: Timer?
    private var segmentStartedAt: Date = .distantPast
    private var segmentDurationSec: TimeInterval = 0
    private var isMicProgressPausedForTarget: Bool = false
    private var micProgressLockedPID: pid_t?
    private var micProgressSilentTicks: Int = 0
    private var latestVoiceActivity: Bool = false
    private var latestVoiceRMS: Float = 0
    private var micProgressActiveTicks: Int = 0
    private var sessionStartedAt: Date = .distantPast
    private var didRecordFirstPartialForSession: Bool = false
    private var lastAdaptiveTextCount: Int = 0
    private var lastAdaptiveSampleAt: Date = .distantPast

    private struct RuntimeSpeechMetrics {
        var sessions: Int = 0
        var utterances: Int = 0
        var commands: Int = 0
        var dictations: Int = 0
        var unknowns: Int = 0
        var engineRestarts: Int = 0
        var lowConfidenceCommandDowngrades: Int = 0
        var recoverableErrors: Int = 0
        var fatalErrors: Int = 0
        var firstPartialSamples: Int = 0
        var firstPartialLatencyTotalMs: Double = 0

        var firstPartialLatencyAvgMs: Double {
            guard firstPartialSamples > 0 else { return 0 }
            return firstPartialLatencyTotalMs / Double(firstPartialSamples)
        }
    }

    private var metrics = RuntimeSpeechMetrics()

    // MARK: - Computed Properties (preserved)
    private typealias RecognitionControlMode = HeadMotionManager.RecognitionControlMode

    private var recognitionControlMode: RecognitionControlMode {
        HeadMotionManager.shared.effectiveRecognitionControlMode
    }

    private var hudRecognitionControlMode: HUDRecognitionControlMode {
        recognitionControlMode.hudMode
    }

    private func recognitionTaskHint() -> SFSpeechRecognitionTaskHint {
        switch recognitionControlMode {
        case .command:
            return .confirmation
        case .dictation:
            return .dictation
        case .auto:
            return sessionTypingMode ? .dictation : .unspecified
        }
    }

    private func shouldPreferOnDeviceRecognition() -> Bool {
        let preferOnDevice = UserDefaults.standard.object(forKey: "preferOnDeviceRecognition") as? Bool ?? true
        if !preferOnDevice { return false }
        // Command mode benefits from lowest latency and deterministic behavior.
        if recognitionControlMode == .command { return true }
        let preferForDictation = UserDefaults.standard.object(forKey: "preferOnDeviceForDictation") as? Bool ?? false
        return preferForDictation
    }

    private var isAwake: Bool {
        if isGazeWakeEnabled && HeadMotionManager.shared.isTracking && HeadMotionManager.shared.isLookingAtScreen { return true }
        guard let last = lastWakeTime else { return false }
        return Date().timeIntervalSince(last) < alwaysListeningWakeWindowSeconds()
    }
    private func alwaysListeningWakeWindowSeconds() -> TimeInterval {
        let v = UserDefaults.standard.object(forKey: "alwaysListeningWakeWindowSeconds") as? Double ?? 4.0
        return min(max(v, 2.0), 30.0)
    }
    private func maxRecordingSegmentSeconds() -> TimeInterval {
        let v = UserDefaults.standard.object(forKey: "maxRecordingSegmentSeconds") as? Double ?? 32.0
        return min(max(v, 10.0), 120.0)
    }

    var currentInputDeviceIcon: String {
        let realHardware = availableInputDevices.filter { $0.id != 0 }
        if realHardware.isEmpty { return "mic.slash.fill" }
        var deviceIDToUse = selectedInputDeviceID
        if deviceIDToUse == 0 {
            var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultInputDevice, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
            var size = UInt32(MemoryLayout<AudioDeviceID>.size)
            AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &deviceIDToUse)
        }
        if let matched = availableInputDevices.first(where: { $0.id == deviceIDToUse }) {
            let lowerName = matched.name.lowercased()
            let isAP = lowerName.contains("airpods") || matched.iconName.contains("airpod")
            guard isAP else { return matched.iconName }
            let side = AirPodsDetector.shared.currentSide()
            if side == .none { return matched.iconName }
            let base = matched.iconName
            switch side {
            case .left: return base == "airpodsmax" ? "airpodsmax" : base == "airpodspro" ? "airpodspro.left" : "airpod.gen3.left"
            case .right: return base == "airpodsmax" ? "airpodsmax" : base == "airpodspro" ? "airpodspro.right" : "airpod.gen3.right"
            case .both: return base == "airpodsmax" ? "airpodsmax" : base == "airpodspro" ? "airpodspro" : "airpod.gen3"
            case .none: return matched.iconName
            }
        }
        if selectedInputDeviceID != 0, let sel = availableInputDevices.first(where: { $0.id == selectedInputDeviceID }) { return sel.iconName }
        if let any = availableInputDevices.first(where: { $0.id != 0 }) { return any.iconName }
        return AudioInputDevice.defaultSystem.iconName
    }

    private func hudInputIcon() -> String {
        let icon = currentInputDeviceIcon
        let side = AirPodsDetector.shared.currentSide()
        if icon != lastLoggedHUDIcon || side != lastLoggedAirPodSide {
            var deviceIDToUse = selectedInputDeviceID
            if deviceIDToUse == 0 {
                var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultInputDevice, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
                var size = UInt32(MemoryLayout<AudioDeviceID>.size)
                AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &deviceIDToUse)
            }
            let activeName = availableInputDevices.first(where: { $0.id == deviceIDToUse })?.name ?? "unknown"
            GlobalLogger.speech.info("[HUD Icon] icon=\(icon), side=\(side.rawValue), selectedID=\(selectedInputDeviceID), activeID=\(deviceIDToUse), activeName=\(activeName)")
            lastLoggedHUDIcon = icon
            lastLoggedAirPodSide = side
        }
        return icon
    }

    // MARK: - Init
    init() {
        self.dictationHandler = DictationHandler(injector: injector)
        GlobalLogger.lifecycle.info("SpeechManager Initialized")
        refreshInputDevices()
        DispatchQueue.main.async { [weak self] in self?.refreshContinuousHUD() }
        _ = AirPodsDetector.shared.currentSide()
        NotificationCenter.default.addObserver(self, selector: #selector(pttDown), name: HeadMotionManager.pttDownNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(pttUp), name: HeadMotionManager.pttUpNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(toggleLanguage), name: Notification.Name("AetherToggleLanguage"), object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleAirPodsChange), name: .AirPodsStateChanged, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleRecognitionControlModeChanged), name: HeadMotionManager.recognitionControlModeChangedNotification, object: nil)
        refreshLocale()
        DispatchQueue.main.async { [weak self] in self?.syncRecognitionState() }
        setupAudioDeviceListeners()

        // Wire sub-module callbacks
        audioCapture.onBuffer = { [weak self] buffer in self?.recognitionSession.append(buffer) }
        audioCapture.onVoiceActivityChanged = { [weak self] active, rms in
            guard let self else { return }
            self.latestVoiceActivity = active
            self.latestVoiceRMS = rms
            self.eosDetector.noteVoiceActivity(active)
        }
        eosDetector.onEndOfSpeech = { [weak self] in self?.handleEOS() }
        eosDetector.onSegmentTimeout = { [weak self] in self?.handleSegmentTimeout() }
        recognitionSession.onPartial = { [weak self] text in self?.handlePartial(text) }
        recognitionSession.onFinal = { [weak self] text in self?.handleFinalResult(text) }
        recognitionSession.onError = { [weak self] error, isRecoverable in self?.handleRecognitionError(error, isRecoverable: isRecoverable) }
        commandHandler.onIntent = { [weak self] intent in self?.onIntent?(intent) }

        HeadMotionManager.shared.$isLookingAtScreen.removeDuplicates().receive(on: DispatchQueue.main).sink { [weak self] isLooking in
            if isLooking && HeadMotionManager.shared.isTracking { self?.playWakeSound() }
        }.store(in: &cancellables)
    }

    @objc private func handleAirPodsChange() { refreshContinuousHUD() }
    @objc private func handleRecognitionControlModeChanged() {
        switch recognitionControlMode {
        case .command:
            sessionTypingMode = false
        case .dictation:
            sessionTypingMode = true
        case .auto:
            sessionTypingMode = isTypingMode
        }

        // Dictation UI mode should track active capture state, not just a persisted mode preference.
        let isCaptureActive = recognitionSession.isRunning || isStopping
        isDictating = isCaptureActive && sessionTypingMode

        // Avoid overriding manual mode-switch toasts when there is no active voice HUD lifecycle.
        let shouldRefreshHUD = isAlwaysListeningEnabled || isWakeWordEnabled || isCaptureActive
        if shouldRefreshHUD {
            refreshContinuousHUD(isDictating: isDictating)
        }
    }

    // MARK: - Locale
    private func refreshLocale() {
        if let id = explicitLocaleIdentifier, !id.isEmpty, id != "system" {
            activeLocale = Locale(identifier: id)
            if !id.starts(with: "en") { lastNonEnglishLocaleIdentifier = id }
        } else {
            activeLocale = Locale.current
            let sysId = activeLocale.identifier
            if !sysId.starts(with: "en") { lastNonEnglishLocaleIdentifier = sysId }
        }
        os_log("Locale refreshed: %{public}@", log: log, type: .info, activeLocale.identifier)
    }

    @objc func toggleLanguage() {
        if activeLocale.identifier.starts(with: "en") {
            explicitLocaleIdentifier = lastNonEnglishLocaleIdentifier
        } else {
            lastNonEnglishLocaleIdentifier = activeLocale.identifier
            explicitLocaleIdentifier = "en-US"
        }
        status = "Language: \(activeLocale.identifier)"
        let hud = HUDManager.shared
        hud.update(
            mode: hud.state.mode,
            message: hud.state.message,
            language: activeLocale.identifier,
            recognitionControlMode: hudRecognitionControlMode,
            inputDeviceIcon: hudInputIcon()
        )
        if recognitionSession.isRunning {
            stopAndFinalize()
            startOnce()
        }
    }

    // MARK: - Permissions
    func requestPermissions() {
        SFSpeechRecognizer.requestAuthorization { [weak self] auth in
            DispatchQueue.main.async {
                guard let self else { return }
                switch auth {
                case .authorized: self.status = "Speech Authorized"
                case .denied: self.status = "Speech Denied"
                case .restricted: self.status = "Speech Restricted"
                case .notDetermined: self.status = "Speech Not Determined"
                @unknown default: self.status = "Speech Unknown"
                }
            }
        }
        AVCaptureDevice.requestAccess(for: .audio) { _ in }
    }

    private func missingVoicePermissionHint() -> (message: String, icon: String)? {
        if AVCaptureDevice.authorizationStatus(for: .audio) != .authorized {
            return (activeLocale.identifier.starts(with: "zh") ? "请先授予麦克风权限" : "Grant Microphone permission first.", "mic.slash.fill")
        }
        if SFSpeechRecognizer.authorizationStatus() != .authorized {
            return (activeLocale.identifier.starts(with: "zh") ? "请先授予语音识别权限" : "Grant Speech Recognition permission first.", "waveform.badge.exclamationmark")
        }
        return nil
    }

    private func setStatus(_ key: String) { self.status = NSLocalizedString(key, comment: "") }

    // MARK: - State Sync
    private func syncRecognitionState() {
        let anyActive = isAlwaysListeningEnabled || isWakeWordEnabled || isPTTEnabled
        if !anyActive {
            resetHUDTransientState(); stopAndFinalize(); stopAudioCapture(); HUDManager.shared.hide()
        } else {
            if isAlwaysListeningEnabled || isWakeWordEnabled {
                if missingVoicePermissionHint() != nil { stopAndFinalize(); stopAudioCapture(); refreshContinuousHUD() }
                else { startContinuous() }
            } else { resetHUDTransientState(); refreshContinuousHUD() }
        }
    }

    // MARK: - Core Session Lifecycle

    func startOnce() {
        isStopping = false
        activeUtteranceID = 0

        stopTimer?.invalidate(); stopTimer = nil
        recognitionSession.cancel()

        if let hint = missingVoicePermissionHint() {
            setHUDOverride(mode: .command, message: hint.message, icon: hint.icon, duration: 1.4)
            refreshContinuousHUD(); return
        }

        // Start audio capture
        audioCapture.selectedDeviceID = selectedInputDeviceID
        do { try audioCapture.start() } catch {
            status = NSLocalizedString("speech.error", comment: ""); lastError = error.localizedDescription
            if isAlwaysListeningEnabled { refreshContinuousHUD(); scheduleContinuousRecovery(delay: 0.8) }
            else { showPTTUnavailableHUD() }
            return
        }

        sessionGeneration += 1
        let gen = sessionGeneration
        sessionStartedAt = Date()
        didRecordFirstPartialForSession = false
        lastAdaptiveTextCount = 0
        lastAdaptiveSampleAt = .distantPast
        metrics.sessions += 1
        lockSessionInputTarget()
        dictationHandler.reset(targetPID: sessionTargetPID)
        dictationHandler.llmProvider = llmProvider
        dictationHandler.isLLMEnhancementEnabled = isLLMEnhancementEnabled

        if isWakeWordEnabled && !isAwake && !isDirectCommandEnabled { sessionTypingMode = false }
        else { sessionTypingMode = isTypingMode }
        isDictating = sessionTypingMode

        // Start recognition
        do {
            let contextual = buildDynamicContextualStrings()
            try recognitionSession.start(
                locale: activeLocale,
                autoPunctuation: isAutoPunctuationEnabled,
                contextualStrings: contextual,
                prebuffered: audioCapture.drainRingBuffer(),
                taskHint: recognitionTaskHint(),
                preferOnDevice: shouldPreferOnDeviceRecognition()
            )
        } catch {
            status = NSLocalizedString("speech.unavailable", comment: ""); lastError = "Speech recognizer unavailable"; return
        }

        // Start EOS detection
        eosDetector.trailingSilenceMs = UserDefaults.standard.object(forKey: "trailingSilenceMs") as? Double ?? 900
        eosDetector.minUtteranceMs = UserDefaults.standard.object(forKey: "minUtteranceMs") as? Double ?? 450
        eosDetector.maxUtteranceMs = UserDefaults.standard.object(forKey: "maxUtteranceMs") as? Double ?? 15000
        eosDetector.maxSegmentSec = maxRecordingSegmentSeconds()
        eosDetector.start()

        lastTranscript = ""; lastError = ""
        status = NSLocalizedString("speech.listening", comment: "") + " (\(activeLocale.identifier.starts(with: "zh") ? "中" : "En"))"
        startMicProgressUI(durationSec: maxRecordingSegmentSeconds(), generation: gen)
        refreshContinuousHUD(isDictating: isDictating)
    }

    // MARK: - Recognition Callbacks

    private func handlePartial(_ rawText: String) {
        guard sessionGeneration > 0 else { return }
        var text = rawText

        // Wake word detection & stripping
        if isWakeWordEnabled && !isDirectCommandEnabled {
            let result = wakeWordDetector.process(text)
            if result.wakeDetected {
                if !isAwake {
                    lastWakeTime = Date(); playWakeSound()
                    if isAlwaysListeningEnabled && isWakeWordEnabled && !isDirectCommandEnabled { rearmInputTarget(reason: "wake-word") }
                }
                text = result.payload
            }
        }

        text = normalizeRecognizedText(text)
        let prev = lastTranscript
        let now = Date()
        if text != prev {
            lastTranscript = text; lastChangeAt = now
            if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                if activeUtteranceID == 0 { activeUtteranceID = nextUtteranceID; nextUtteranceID += 1 }
                eosDetector.noteUtteranceStarted()
                eosDetector.noteTranscriptChanged()
                noteFirstPartialIfNeeded(at: now)
                applyAdaptiveEOS(with: text, at: now)
            }
        }

        let hasPayload = !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if hasPayload && !isUtteranceActive {
            isUtteranceActive = true
            if activeUtteranceID == 0 { activeUtteranceID = nextUtteranceID; nextUtteranceID += 1 }
            if isAlwaysListeningEnabled && isDirectCommandEnabled { rearmInputTarget(reason: "direct-utterance-start") }
        }
        if !hasPayload && isUtteranceActive { isUtteranceActive = false }

        let liveTyping = throttledTypingMode()
        let canType = isAwake || isDirectCommandEnabled || !isAlwaysListeningEnabled
        switch recognitionControlMode {
        case .command:
            sessionTypingMode = false
        case .dictation:
            sessionTypingMode = canType
        case .auto:
            sessionTypingMode = (sessionTypingMode || liveTyping) && canType
        }
        isDictating = sessionTypingMode

        if text.count > 2 && isAwake { lastWakeTime = Date() }
        if (!isStopping || isAlwaysListeningEnabled) { refreshContinuousHUD(isDictating: isDictating) }
        else if isStopping { refreshContinuousHUD() }

        // Dispatch to handler
        if sessionTypingMode {
            dictationHandler.onPartial(text)
        } else {
            commandHandler.onPartial(text)
        }
    }

    private func handleFinalResult(_ text: String) {
        os_log("isFinal received: '%{public}@'", log: log, type: .info, text)
        finalizationWorkItem?.cancel(); finalizationWorkItem = nil
        eosDetector.noteUtteranceEnded()
        if isStopping {
            handleTranscript(text, utteranceID: activeUtteranceID)
            if !isAlwaysListeningEnabled { stopAudioCapture(); refreshContinuousHUD() }
        }
    }

    private func handleRecognitionError(_ error: Error, isRecoverable: Bool) {
        if isRecoverable {
            metrics.recoverableErrors += 1
            os_log("Recognition recoverable error: %{public}@", log: log, type: .info, error.localizedDescription)
            if isAlwaysListeningEnabled {
                cleanup(); refreshContinuousHUD(); scheduleContinuousRecovery(delay: 0.12)
            } else { stopAndFinalize() }
        } else {
            metrics.fatalErrors += 1
            status = NSLocalizedString("speech.error", comment: ""); lastError = error.localizedDescription
            stopAndFinalize(); scheduleContinuousRecovery(delay: 0.4)
        }
        maybeLogRuntimeMetrics(force: false)
    }

    // MARK: - EOS Callbacks
    private func handleEOS() {
        guard !isStopping else { return }
        let isStandby = isAlwaysListeningEnabled && isWakeWordEnabled && !isAwake && !isDirectCommandEnabled && !sessionTypingMode
        if isStandby { return }
        os_log("EOS detected, finalizing", log: log, type: .info)
        isStopping = true
        refreshContinuousHUD(isDictating: false)
        stopAndFinalize(keepHUDVisible: true)
    }

    private func handleSegmentTimeout() {
        guard recognitionSession.isRunning, !isStopping else { return }
        let isStandby = isAlwaysListeningEnabled && isWakeWordEnabled && !isAwake && !isDirectCommandEnabled && !sessionTypingMode
        if isStandby { eosDetector.start(); return }
        let shouldContinue = isPTTHeld || isAlwaysListeningEnabled
        os_log("Segment timeout. shouldContinue=%d", log: log, type: .info, shouldContinue)
        isStopping = true
        refreshContinuousHUD(isDictating: false)
        stopMicProgressUI(keepVisible: shouldContinue)
        stopAndFinalize(keepHUDVisible: shouldContinue)
        guard shouldContinue else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) { [weak self] in
            guard let self, !self.recognitionSession.isRunning, !self.isStopping else { return }
            self.startOnce()
        }
    }

    // MARK: - PTT
    @objc private func pttDown() {
        isPTTHeld = true
        guard isPTTEnabled else { return }
        if isAlwaysListeningEnabled {
            lastWakeTime = Date(); playWakeSound(); refreshContinuousHUD(isDictating: isDictating)
            if !recognitionSession.isRunning { startOnce() }
            return
        }
        if !availableInputDevices.contains(where: { $0.id != 0 }) { showPTTUnavailableHUD() }
        startOnce()
    }

    @objc private func pttUp() {
        isPTTHeld = false
        guard !isAlwaysListeningEnabled else { return }
        guard recognitionSession.isRunning else { isStopping = false; HUDManager.shared.hide(); return }
        isStopping = true; refreshContinuousHUD()
        stopTimer?.invalidate()
        stopTimer = Timer.scheduledTimer(withTimeInterval: 0.6, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.stopAndFinalize() }
        }
    }

    // MARK: - Stop & Finalize
    func stopAndFinalize(keepHUDVisible: Bool = false) {
        if !keepHUDVisible { clearHUDOverride() }
        stopMicProgressUI(keepVisible: keepHUDVisible)
        eosDetector.stop()
        if !keepHUDVisible {
            if isAlwaysListeningEnabled { refreshContinuousHUD(isDictating: false) } else { HUDManager.shared.hide() }
        }
        guard recognitionSession.isRunning else {
            resetHUDTransientState()
            if !keepHUDVisible { if isAlwaysListeningEnabled { refreshContinuousHUD() } else { HUDManager.shared.hide() } }
            return
        }
        let genToFinalize = sessionGeneration
        let fallbackTranscript = lastTranscript
        recognitionSession.finish()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self, self.sessionGeneration == genToFinalize else { return }
            self.recognitionSession.cancel()
            let textToUse = self.lastTranscript.isEmpty ? fallbackTranscript : self.lastTranscript
            self.handleTranscript(textToUse, utteranceID: self.activeUtteranceID)
            self.isStopping = false
            if !self.isAlwaysListeningEnabled { self.stopAudioCapture(); if !keepHUDVisible { HUDManager.shared.hide() } }
            else { if !keepHUDVisible { self.refreshContinuousHUD() } }
        }
        finalizationWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: workItem)
    }

    private func stopAudioCapture() {
        audioCapture.stop()
    }

    func teardownEngine() {
        isStopping = false
        eosDetector.stop()
        recognitionSession.cancel()
        audioCapture.stop()
    }

    private func cleanup() {
        recognitionSession.cancel()
        eosDetector.stop()
        stopTimer?.invalidate(); stopTimer = nil
        isStopping = false; isDictating = false; sessionTypingMode = false
        activeUtteranceID = 0; sessionTargetPID = nil; sessionTargetBundleID = nil
        sessionTargetElementFingerprint = nil; didLogSessionTargetMismatch = false
        isUtteranceActive = false
    }

    private func resetHUDTransientState() {
        isStopping = false; isDictating = false; sessionTypingMode = false
        activeUtteranceID = 0; sessionTargetPID = nil; sessionTargetBundleID = nil
        sessionTargetElementFingerprint = nil; didLogSessionTargetMismatch = false
        isUtteranceActive = false; lastTranscript = ""; lastChangeAt = nil; lastStableText = ""
    }

    // MARK: - Continuous Mode
    private func startContinuous() {
        let now = Date()
        if now.timeIntervalSince(lastContinuousStartAt) < 0.8 { return }
        lastContinuousStartAt = now
        startOnce()
        continuousTimer?.invalidate()
        if isAlwaysListeningEnabled {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in self?.refreshContinuousHUD() }
            continuousTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.tickContinuous() }
            }
        }
    }

    private func stopContinuous() {
        continuousTimer?.invalidate(); continuousTimer = nil
        stopAndFinalize(); teardownEngine()
    }

    private func tickContinuous() {
        guard isAlwaysListeningEnabled else { return }
        let currentlyAwake = isAwake
        if currentlyAwake != wasAwake {
            wasAwake = currentlyAwake; refreshContinuousHUD()
            if currentlyAwake {
                if isWakeWordEnabled && !isDirectCommandEnabled { rearmInputTarget(reason: "wake-window-open") }
                startMicProgressUI(durationSec: maxRecordingSegmentSeconds(), generation: sessionGeneration)
            }
        }
        let isWakeGated = isAlwaysListeningEnabled && isWakeWordEnabled && !isDirectCommandEnabled
        if isWakeGated && !currentlyAwake {
            if micProgressTimer != nil || HUDManager.shared.state.isMicProgressVisible { stopMicProgressUI(keepVisible: false) }
        }

        // Health check
        if !recognitionSession.isRunning || !audioCapture.isRunning {
            if Date() < continuousRecoveryGraceUntil { return }
            if !audioCapture.isRunning {
                if pendingEngineRestartWorkItem == nil { scheduleEngineRestart(reason: "continuous-health-check-engine-down") }
                return
            }
            scheduleContinuousRecovery(delay: 0.12); return
        }

        // Utterance boundary detection (1s silence)
        guard let lastChange = lastChangeAt, !lastTranscript.isEmpty else { return }
        if Date().timeIntervalSince(lastChange) < 1.0 { return }
        if lastStableText == lastTranscript { return }
        lastStableText = lastTranscript
        let text = lastTranscript
        lastTranscript = ""; lastChangeAt = nil; isUtteranceActive = false
        handleTranscript(text, utteranceID: activeUtteranceID)
        cleanup()
        if isAlwaysListeningEnabled { startOnce() }
    }

    private func scheduleContinuousRecovery(delay: TimeInterval = 0.25) {
        guard isAlwaysListeningEnabled else { return }
        continuousRecoveryGraceUntil = Date().addingTimeInterval(delay + 0.6)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, self.isAlwaysListeningEnabled, !self.recognitionSession.isRunning else { return }
            self.startOnce()
        }
    }

    func undoLastInjection() { injector.undoPasteIfRecent() }
    func updateAccessibilityTrusted(_ trusted: Bool) { accessibilityTrustedSnapshot = trusted }
    private func playWakeSound() { NSSound(named: "Tink")?.play() }

    // MARK: - handleTranscript (unified finalization)
    private func handleTranscript(_ transcript: String, utteranceID: Int? = nil) {
        let trimmed = normalizeRecognizedText(transcript).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let candidateUtteranceID = utteranceID ?? activeUtteranceID
        let now = Date()
        if candidateUtteranceID > 0, sessionGeneration == lastHandledSessionGeneration,
           candidateUtteranceID == lastHandledUtteranceID, trimmed == lastHandledTranscript,
           now.timeIntervalSince(lastHandledAt) < 2.0 { return }

        var textToRoute = trimmed
        var wakeWordDetected = false

        if isDirectCommandEnabled {
            let wakeResult = wakeWordDetector.process(trimmed)
            if isWakeWordEnabled && wakeResult.wakeDetected {
                textToRoute = wakeResult.payload; wakeWordDetected = true; playWakeSound()
            } else { textToRoute = trimmed }
        } else if isAlwaysListeningEnabled {
            let wakeResult = wakeWordDetector.process(trimmed)
            if isAwake {
                if wakeResult.wakeDetected { textToRoute = wakeResult.payload; wakeWordDetected = true; playWakeSound() }
                else { textToRoute = trimmed }
            } else {
                if wakeResult.wakeDetected { textToRoute = wakeResult.payload; wakeWordDetected = true; playWakeSound(); lastWakeTime = Date() }
                else { return }
            }
        }

        let typingContext: Bool
        switch recognitionControlMode {
        case .command:
            typingContext = false
        case .dictation:
            typingContext = true
        case .auto:
            typingContext = sessionTypingMode || isTypingMode
        }
        if typingContext != sessionTypingMode { sessionTypingMode = typingContext; isDictating = typingContext }

        let motion = HeadMotionManager.shared
        let posture = motion.currentPostureBias
        var routingBias: VoiceCommandRouter.RoutingBias = .neutral
        var blockDictationWithoutInput = false

        switch motion.effectiveRecognitionControlMode {
        case .command:
            routingBias = .forceCommand
        case .dictation:
            if typingContext {
                routingBias = .forceDictation
            } else {
                routingBias = .forceCommand
                blockDictationWithoutInput = true
            }
        case .auto:
            switch posture {
            case .tiltRight: routingBias = .forceCommand
            case .tiltLeft, .lookLow: routingBias = .forceDictation
            case .neutral: routingBias = typingContext ? .dictationPreferred : .commandPreferred
            }
        }

        let router = VoiceCommandRouter()
        let decision = router.routeDetailed(transcript: textToRoute, bias: routingBias)
        var intent = decision.intent

        if recognitionControlMode == .command, case .dictation(let payload) = intent {
            intent = .unknown(payload)
        }

        if decision.confidence == .low,
           !typingContext,
           isCommandIntent(intent) {
            metrics.lowConfidenceCommandDowngrades += 1
            intent = .unknown(textToRoute)
        }

        if blockDictationWithoutInput, case .dictation(let p) = intent { intent = .unknown(p) }
        if !isAlwaysListeningEnabled,
           recognitionControlMode != .command,
           !blockDictationWithoutInput,
           case .unknown = intent,
           !textToRoute.isEmpty,
           typingContext {
            intent = .dictation(textToRoute)
        }

        noteIntentMetrics(intent)

        if wakeWordDetected { lastWakeTime = Date() }
        else if case .unknown = intent { /* don't extend */ }
        else { lastWakeTime = Date() }

        var resolvedUID = utteranceID ?? activeUtteranceID
        if resolvedUID <= 0 { resolvedUID = nextUtteranceID; nextUtteranceID += 1; activeUtteranceID = resolvedUID }
        lastHandledSessionGeneration = sessionGeneration; lastHandledUtteranceID = resolvedUID
        lastHandledTranscript = trimmed; lastHandledAt = now

        enqueueIntentForParallelExecution(intent, typingContext: typingContext, utteranceID: resolvedUID, originSessionGeneration: sessionGeneration)
    }

    private func enqueueIntentForParallelExecution(_ intent: VoiceIntent, typingContext: Bool, utteranceID: Int, originSessionGeneration: Int) {
        let localeID = activeLocale.identifier
        let fallback: FocusedInputSnapshot? = typingContext && (sessionTargetPID == nil || sessionTargetPID == 0) ? currentFocusedInputSnapshot() : nil
        let pid = typingContext ? (sessionTargetPID ?? fallback?.pid) : nil
        let bid = typingContext ? (sessionTargetBundleID ?? fallback?.bundleID) : nil
        let fp = typingContext ? (sessionTargetElementFingerprint ?? fallback?.elementFingerprint) : nil
        let job = IntentJob(seq: -1, intent: intent, localeIdentifier: localeID, llmEnhancementEnabled: isLLMEnhancementEnabled,
                            originSessionGeneration: originSessionGeneration, utteranceID: utteranceID, sessionTypingMode: typingContext,
                            streamedTextSnapshot: dictationHandler.screenTypedText, screenTypedCount: dictationHandler.screenTypedText.count,
                            targetPID: pid, targetBundleID: bid, targetElementFingerprint: fp)
        Task { [weak self] in
            guard let self else { return }
            let seq = await self.intentPipeline.allocateSeq()
            let seeded = IntentJob(seq: seq, intent: job.intent, localeIdentifier: job.localeIdentifier, llmEnhancementEnabled: job.llmEnhancementEnabled,
                                   originSessionGeneration: job.originSessionGeneration, utteranceID: job.utteranceID, sessionTypingMode: job.sessionTypingMode,
                                   streamedTextSnapshot: job.streamedTextSnapshot, screenTypedCount: job.screenTypedCount,
                                   targetPID: job.targetPID, targetBundleID: job.targetBundleID, targetElementFingerprint: job.targetElementFingerprint)
            Task.detached(priority: .userInitiated) { [weak self] in
                guard let self else { return }
                let processed = await self.processIntentJob(seeded)
                let ready = await self.intentPipeline.submit(processed)
                for r in ready { await MainActor.run { [weak self] in self?.applyProcessedJob(r) } }
            }
        }
    }

    private func processIntentJob(_ job: IntentJob) async -> ProcessedJob {
        if case .dictation(let text) = job.intent, job.llmEnhancementEnabled, job.sessionTypingMode, let llmProvider {
            do {
                let enhanced = try await llmProvider.enhanceDictation(text)
                let finalText = enhanced.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? text : enhanced
                return ProcessedJob(seq: job.seq, intent: .dictation(finalText), localeIdentifier: job.localeIdentifier,
                                    originSessionGeneration: job.originSessionGeneration, utteranceID: job.utteranceID,
                                    sessionTypingMode: job.sessionTypingMode, streamedTextSnapshot: job.streamedTextSnapshot,
                                    screenTypedCount: job.screenTypedCount, targetPID: job.targetPID,
                                    targetBundleID: job.targetBundleID, targetElementFingerprint: job.targetElementFingerprint, diagnostics: "llm=ok")
            } catch { /* fallthrough */ }
        }
        return ProcessedJob(seq: job.seq, intent: job.intent, localeIdentifier: job.localeIdentifier,
                            originSessionGeneration: job.originSessionGeneration, utteranceID: job.utteranceID,
                            sessionTypingMode: job.sessionTypingMode, streamedTextSnapshot: job.streamedTextSnapshot,
                            screenTypedCount: job.screenTypedCount, targetPID: job.targetPID,
                            targetBundleID: job.targetBundleID, targetElementFingerprint: job.targetElementFingerprint, diagnostics: nil)
    }

    private func applyProcessedJob(_ job: ProcessedJob) {
        guard utteranceExecutionGuard.shouldExecute(sessionGeneration: job.originSessionGeneration, utteranceID: job.utteranceID) else { return }
        switch job.intent {
        case .undo: injector.undoPasteIfRecent(); status = NSLocalizedString("speech.undo", comment: "")
        case .paste: AutomationOutputs.shared.pasteFromClipboard(); status = "Pasted (Cmd+V)"
        case .dictation(let text):
            guard isJobInputTargetValidForInjection(job) else { status = NSLocalizedString("speech.done", comment: ""); return }
            let hasStreamed = job.screenTypedCount > 0 || !job.streamedTextSnapshot.isEmpty
            if job.sessionTypingMode || hasStreamed {
                // Use DictationHandler's diff-based correction instead of old TypingFinalizationPlanner
                // The handler already applied corrections during streaming; final sync is done here
                if text == job.streamedTextSnapshot {
                    // Already fully synced by streaming
                } else if text.hasPrefix(job.streamedTextSnapshot) {
                    let suffix = String(text.dropFirst(job.streamedTextSnapshot.count))
                    if !suffix.isEmpty { injector.type(suffix, targetPID: job.targetPID) }
                } else {
                    // Diff correction: find common prefix, backspace, type remainder
                    let commonLen = commonPrefixLen(job.streamedTextSnapshot, text)
                    let toDelete = job.streamedTextSnapshot.count - commonLen
                    let toType = String(text.dropFirst(commonLen))
                    if toDelete > 0 { injector.deleteBackward(count: toDelete, targetPID: job.targetPID) }
                    if !toType.isEmpty { injector.type(toType, targetPID: job.targetPID) }
                }
                status = NSLocalizedString("speech.typed", comment: "")
            } else {
                injector.type(text, targetPID: job.targetPID)
                status = NSLocalizedString("speech.typed", comment: "")
            }
        default: onIntent?(job.intent); status = NSLocalizedString("speech.done", comment: "")
        }
    }

    private func commonPrefixLen(_ a: String, _ b: String) -> Int {
        var count = 0; var ai = a.startIndex; var bi = b.startIndex
        while ai < a.endIndex && bi < b.endIndex { if a[ai] != b[bi] { break }; count += 1; ai = a.index(after: ai); bi = b.index(after: bi) }
        return count
    }

    private func noteFirstPartialIfNeeded(at now: Date) {
        guard !didRecordFirstPartialForSession else { return }
        guard sessionStartedAt != .distantPast else { return }
        didRecordFirstPartialForSession = true
        let latency = max(0, now.timeIntervalSince(sessionStartedAt) * 1000.0)
        metrics.firstPartialSamples += 1
        metrics.firstPartialLatencyTotalMs += latency
        maybeLogRuntimeMetrics(force: false)
    }

    private func applyAdaptiveEOS(with text: String, at now: Date) {
        guard UserDefaults.standard.object(forKey: "adaptiveEOSTuningEnabled") as? Bool ?? true else { return }
        guard !text.isEmpty else { return }

        if lastAdaptiveSampleAt == .distantPast {
            lastAdaptiveSampleAt = now
            lastAdaptiveTextCount = text.count
            return
        }

        let dt = now.timeIntervalSince(lastAdaptiveSampleAt)
        guard dt >= 0.08 else { return }
        let deltaChars = max(0, text.count - lastAdaptiveTextCount)
        lastAdaptiveSampleAt = now
        lastAdaptiveTextCount = text.count
        guard deltaChars > 0 else { return }

        let cps = Double(deltaChars) / dt
        var targetTrailingMs: Double
        switch cps {
        case 0..<3:
            targetTrailingMs = 1050
        case 3..<7:
            targetTrailingMs = 900
        case 7..<12:
            targetTrailingMs = 760
        case 12..<18:
            targetTrailingMs = 650
        default:
            targetTrailingMs = 560
        }

        switch recognitionControlMode {
        case .command:
            targetTrailingMs = min(targetTrailingMs, 700)
        case .dictation:
            targetTrailingMs = max(targetTrailingMs, 760)
        case .auto:
            break
        }

        targetTrailingMs = min(max(targetTrailingMs, 450), 1400)
        eosDetector.trailingSilenceMs = eosDetector.trailingSilenceMs * 0.65 + targetTrailingMs * 0.35
    }

    private func isCommandIntent(_ intent: VoiceIntent) -> Bool {
        switch intent {
        case .dictation, .unknown:
            return false
        default:
            return true
        }
    }

    private func noteIntentMetrics(_ intent: VoiceIntent) {
        metrics.utterances += 1
        switch intent {
        case .dictation:
            metrics.dictations += 1
        case .unknown:
            metrics.unknowns += 1
        default:
            metrics.commands += 1
        }
        maybeLogRuntimeMetrics(force: false)
    }

    private func maybeLogRuntimeMetrics(force: Bool) {
        if !force, metrics.utterances == 0 { return }
        if !force, metrics.utterances % 10 != 0 { return }
        let avgFirstPartial = Int(metrics.firstPartialLatencyAvgMs.rounded())
        GlobalLogger.speech.info(
            "[Metrics] sessions=\(metrics.sessions) utterances=\(metrics.utterances) commands=\(metrics.commands) dictation=\(metrics.dictations) unknown=\(metrics.unknowns) firstPartialAvgMs=\(avgFirstPartial) engineRestarts=\(metrics.engineRestarts) lowConfDrops=\(metrics.lowConfidenceCommandDowngrades) recoverableErr=\(metrics.recoverableErrors) fatalErr=\(metrics.fatalErrors)"
        )
    }

    private func buildDynamicContextualStrings() -> [String] {
        var ordered: [String] = []
        var seen = Set<String>()

        func add(_ token: String) {
            guard let normalized = normalizeContextualToken(token) else { return }
            let key = normalized.lowercased()
            guard !seen.contains(key) else { return }
            seen.insert(key)
            ordered.append(normalized)
        }

        let staticSeeds = [
            "点击", "双击", "向下", "向上", "右键",
            "Click", "Double Click", "Scroll Down", "Scroll Up", "Right Click",
            "GitHub", "git", "repo", "repository", "issue", "pull request", "PR",
            "commit", "branch", "merge", "rebase", "checkout", "clone", "push", "pull",
            "origin", "main", "develop", "release"
        ]
        staticSeeds.forEach(add)

        let frontApp = NSWorkspace.shared.frontmostApplication
        if let appName = frontApp?.localizedName {
            tokenizeContextualString(appName).forEach(add)
        }
        if let bundleID = frontApp?.bundleIdentifier {
            tokenizeContextualString(bundleID).forEach(add)
        }

        for group in activeGroupsForCurrentContext() {
            tokenizeContextualString(group.name).forEach(add)
            for rule in replacementRules(for: group) {
                tokenizeContextualString(rule.from).forEach(add)
                tokenizeContextualString(rule.to).forEach(add)
            }
        }

        if !lastTranscript.isEmpty {
            tokenizeContextualString(lastTranscript).forEach(add)
        }

        if ordered.count > 160 {
            ordered = Array(ordered.prefix(160))
        }
        return ordered
    }

    private func tokenizeContextualString(_ raw: String) -> [String] {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        var out: [String] = [trimmed]
        let splitSet = CharacterSet(charactersIn: " ,./_:-+@()[]{}<>|\\\t\n")
        let parts = trimmed
            .components(separatedBy: splitSet)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        out.append(contentsOf: parts)
        return out
    }

    private func normalizeContextualToken(_ token: String) -> String? {
        let t = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return nil }
        guard t.count <= 32 else { return nil }
        if t.count == 1 {
            let isAscii = t.unicodeScalars.allSatisfy { $0.isASCII }
            if isAscii { return nil }
        }
        return t
    }

    // MARK: - HUD Management
    private func setHUDOverride(mode: HUDMode, message: String, icon: String, duration: TimeInterval) {
        hudOverrideMode = mode; hudOverrideMessage = message; hudOverrideIcon = icon
        hudOverrideUntil = Date().addingTimeInterval(max(0.2, duration))
    }
    private func clearHUDOverride() { hudOverrideUntil = .distantPast; hudOverrideMessage = ""; hudOverrideIcon = "info.circle" }

    private func refreshContinuousHUD(isDictating: Bool = false) {
        let controlMode = hudRecognitionControlMode
        if !isStopping && Date() < hudOverrideUntil {
            HUDManager.shared.update(mode: hudOverrideMode, message: hudOverrideMessage, language: activeLocale.identifier, recognitionControlMode: controlMode, inputDeviceIcon: hudOverrideIcon); return
        }
        if (isAlwaysListeningEnabled || isWakeWordEnabled), let hint = missingVoicePermissionHint() {
            HUDManager.shared.update(mode: .command, message: hint.message, language: activeLocale.identifier, recognitionControlMode: controlMode, inputDeviceIcon: hint.icon); return
        }
        let isContinuousActive = isAlwaysListeningEnabled
        let isSessionActive = recognitionSession.isRunning || isStopping || isDictating
        if !isContinuousActive && !isSessionActive { clearHUDOverride(); HUDManager.shared.hide(); return }

        let realHardware = availableInputDevices.filter { $0.id != 0 }
        if realHardware.isEmpty {
            HUDManager.shared.update(mode: .listening, message: activeLocale.identifier.starts(with: "zh") ? "未检测到麦克风" : "No Microphone Detected", language: activeLocale.identifier, recognitionControlMode: controlMode, inputDeviceIcon: hudInputIcon()); return
        }

        let isWakeGated = isAlwaysListeningEnabled && isWakeWordEnabled && !isDirectCommandEnabled
        let mode: HUDMode; var message = ""
        if isWakeGated && !isAwake && !isStopping && !isDictating && lastTranscript.isEmpty { mode = .standby }
        else if isDictating { mode = .dictation }
        else if isStopping { mode = .processing }
        else if !lastTranscript.isEmpty { mode = .command; message = lastTranscript }
        else { mode = .listening }
        HUDManager.shared.update(mode: mode, message: message, language: activeLocale.identifier, recognitionControlMode: controlMode, inputDeviceIcon: hudInputIcon())
    }

    private func showPTTUnavailableHUD() {
        HUDManager.shared.update(mode: .listening, message: activeLocale.identifier.starts(with: "zh") ? "未检测到麦克风" : "No Microphone Detected", language: activeLocale.identifier, recognitionControlMode: hudRecognitionControlMode, inputDeviceIcon: hudInputIcon())
    }

    // MARK: - Mic Progress Ring
    private func startMicProgressUI(durationSec: TimeInterval, generation gen: Int) {
        micProgressTimer?.invalidate()
        segmentStartedAt = .distantPast
        segmentDurationSec = max(durationSec, 0.1)
        micProgressLockedPID = sessionTargetPID; isMicProgressPausedForTarget = false
        micProgressSilentTicks = 0
        micProgressActiveTicks = 0
        latestVoiceActivity = false
        latestVoiceRMS = 0
        HUDManager.shared.updateMicProgress(progress: 0.0, visible: false)
        micProgressTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                guard self.sessionGeneration == gen, !self.isMicProgressPausedForTarget else { return }
                let baseThreshold = Float(UserDefaults.standard.object(forKey: "micProgressVADThreshold") as? Double ?? 0.07)
                let ringThreshold = min(max(baseThreshold + 0.08, 0.14), 0.35)
                let isVoiceActive = self.latestVoiceActivity && self.latestVoiceRMS >= ringThreshold

                if isVoiceActive {
                    self.micProgressSilentTicks = 0
                    self.micProgressActiveTicks += 1
                    guard self.micProgressActiveTicks >= 3 else { return }
                    if self.segmentStartedAt == .distantPast {
                        self.segmentStartedAt = Date()
                        HUDManager.shared.updateMicProgress(progress: 0.0, visible: true)
                        return
                    }
                    let elapsed = Date().timeIntervalSince(self.segmentStartedAt)
                    let progress = CGFloat(min(max(elapsed / self.segmentDurationSec, 0.0), 1.0))
                    HUDManager.shared.updateMicProgress(progress: progress, visible: true)
                    return
                }

                self.micProgressSilentTicks += 1
                if self.micProgressSilentTicks >= 3 {
                    self.micProgressActiveTicks = 0
                    self.segmentStartedAt = .distantPast
                    HUDManager.shared.updateMicProgress(progress: 0.0, visible: false)
                }
            }
        }
    }

    private func stopMicProgressUI(keepVisible: Bool) {
        micProgressTimer?.invalidate(); micProgressTimer = nil
        micProgressSilentTicks = 0
        micProgressActiveTicks = 0
        latestVoiceActivity = false
        latestVoiceRMS = 0
        let wasPaused = isMicProgressPausedForTarget; isMicProgressPausedForTarget = false; micProgressLockedPID = nil
        HUDManager.shared.updateMicProgress(progress: keepVisible ? (wasPaused ? 0.0 : 1.0) : 0.0, visible: keepVisible)
    }

    // MARK: - Engine Restart
    private func scheduleEngineRestart(reason: String, debounce: TimeInterval? = nil) {
        let wait = debounce ?? engineRestartDebounce
        pendingEngineRestartWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }; self.pendingEngineRestartWorkItem = nil; self.performEngineRestart(reason: reason)
        }
        pendingEngineRestartWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + wait, execute: work)
    }

    private func performEngineRestart(reason: String) {
        let elapsed = Date().timeIntervalSince(lastEngineRestartAt)
        if elapsed < engineRestartMinInterval { scheduleEngineRestart(reason: "\(reason)-throttled", debounce: engineRestartMinInterval - elapsed); return }
        metrics.engineRestarts += 1
        stopAndFinalize()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            guard let self else { return }
            if self.isAlwaysListeningEnabled { self.startOnce() }
            self.lastEngineRestartAt = Date()
            self.maybeLogRuntimeMetrics(force: false)
        }
    }

    // MARK: - Device Management
    func refreshInputDevices() {
        var devices: [AudioInputDevice] = [.defaultSystem]
        var propAddr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var dataSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &propAddr, 0, nil, &dataSize) == noErr else { return }
        let count = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var ids = [AudioDeviceID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &propAddr, 0, nil, &dataSize, &ids) == noErr else { return }
        for id in ids {
            var name = "Unknown Device"; var nameSize = UInt32(MemoryLayout<CFString>.size)
            var nameAddr = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyDeviceNameCFString, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
            var nameRef: CFString?
            if AudioObjectGetPropertyData(id, &nameAddr, 0, nil, &nameSize, &nameRef) == noErr, let n = nameRef { name = n as String }
            var addr = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreamConfiguration, mScope: kAudioDevicePropertyScopeInput, mElement: 0)
            var size: UInt32 = 0; AudioObjectGetPropertyDataSize(id, &addr, 0, nil, &size)
            if size > 0 {
                let bufferList = UnsafeMutablePointer<AudioBufferList>.allocate(capacity: Int(size)); defer { bufferList.deallocate() }
                AudioObjectGetPropertyData(id, &addr, 0, nil, &size, bufferList)
                let channels = UnsafeMutableAudioBufferListPointer(bufferList).reduce(0) { $0 + Int($1.mNumberChannels) }
                if channels > 0 {
                    var uid = "\(id)"; var uidSize = UInt32(MemoryLayout<CFString>.size)
                    var uidAddr = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyDeviceUID, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
                    var uidRef: CFString?
                    if AudioObjectGetPropertyData(id, &uidAddr, 0, nil, &uidSize, &uidRef) == noErr, let u = uidRef { uid = u as String }
                    var icon = "mic.fill"; let ln = name.lowercased()
                    if ln.contains("airpods") { icon = "airpods"; if ln.contains("pro") { icon = "airpodspro" }; if ln.contains("max") { icon = "airpodsmax" } }
                    else if ln.contains("studio display") { icon = "monitor" }
                    else if ln.contains("external") { icon = "mic.badge.plus" }
                    else if ln.contains("macbook") || ln.contains("built-in") { icon = "laptopcomputer" }
                    devices.append(AudioInputDevice(id: id, name: name, uid: uid, iconName: icon))
                }
            }
        }
        DispatchQueue.main.async { self.availableInputDevices = devices; self.refreshContinuousHUD() }
    }

    private func setupAudioDeviceListeners() {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultInputDevice, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            DispatchQueue.main.async { guard let self else { return }
                self.refreshInputDevices()
                if self.selectedInputDeviceID == 0 {
                    let hud = HUDManager.shared
                    hud.update(
                        mode: hud.state.mode,
                        message: hud.state.message,
                        language: hud.state.language,
                        recognitionControlMode: self.hudRecognitionControlMode,
                        inputDeviceIcon: self.hudInputIcon()
                    )
                }
                let active = self.audioCapture.isRunning || self.recognitionSession.isRunning || self.isAlwaysListeningEnabled
                if active { self.scheduleEngineRestart(reason: "default-input-device-changed") }
            }
        }
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, nil, block)
    }

    // MARK: - Focus / Typing Detection (preserved from original)
    private var isTypingMode: Bool {
        switch recognitionControlMode {
        case .command:
            return false
        case .dictation:
            return true
        case .auto:
            break
        }

        if HUDManager.shared.lastKnownTypingState() { return true }
        func isAXEditable(_ el: AXUIElement) -> Bool {
            var v: CFTypeRef?; guard AXUIElementCopyAttributeValue(el, "AXEditable" as CFString, &v) == .success else { return false }
            return (v as? Bool) == true || (v as? NSNumber)?.boolValue == true
        }
        func hasInsertionCtx(_ el: AXUIElement) -> Bool {
            var v: CFTypeRef?
            if AXUIElementCopyAttributeValue(el, kAXSelectedTextRangeAttribute as CFString, &v) == .success,
               let raw = v,
               CFGetTypeID(raw) == AXValueGetTypeID() {
                let ax = raw as! AXValue
                if AXValueGetType(ax) == .cfRange {
                    var range = CFRange()
                    if AXValueGetValue(ax, .cfRange, &range) {
                        if range.length == 0 { return true }
                    } else {
                        return true
                    }
                } else {
                    return true
                }
            }
            if AXUIElementCopyAttributeValue(el, "AXSelectedTextMarkerRange" as CFString, &v) == .success { return true }
            return false
        }
        func hasEditableChild(_ el: AXUIElement, depth: Int = 4) -> Bool {
            if depth <= 0 { return false }
            var cr: CFTypeRef?; guard AXUIElementCopyAttributeValue(el, kAXChildrenAttribute as CFString, &cr) == .success, let ch = cr as? [AXUIElement] else { return false }
            let direct = [kAXTextFieldRole as String, "AXSearchField", "AXComboBox", "AXHTMLTextInput"]
            let cond = [kAXTextAreaRole as String, "AXWebArea", "AXStaticText"]
            for c in ch {
                var rr: CFTypeRef?; let role = (AXUIElementCopyAttributeValue(c, kAXRoleAttribute as CFString, &rr) == .success) ? (rr as? String ?? "") : ""
                if direct.contains(role) { return true }
                if cond.contains(role), (isAXEditable(c) || hasInsertionCtx(c)) { return true }
                if hasInsertionCtx(c) { return true }
                if hasEditableChild(c, depth: depth - 1) { return true }
            }
            return false
        }
        let sw = AXUIElementCreateSystemWide(); var fe: AnyObject?
        if AXUIElementCopyAttributeValue(sw, kAXFocusedUIElementAttribute as CFString, &fe) == .success, let er = fe {
            let ax = er as! AXUIElement; var rr: AnyObject?; var role = ""
            if AXUIElementCopyAttributeValue(ax, kAXRoleAttribute as CFString, &rr) == .success, let v = rr as? String { role = v }
            var pid: pid_t = 0; AXUIElementGetPid(ax, &pid)
            if let app = NSRunningApplication(processIdentifier: pid), let bid = app.bundleIdentifier {
                let appName = app.localizedName?.lowercased() ?? ""
                if bid.contains("apple.siri") || bid == "com.apple.Spotlight" || appName.contains("siri") { return true }
                let terminals = ["com.apple.Terminal","com.googlecode.iterm2","com.github.wez.wezterm","dev.warp.Warp-Stable"]
                let direct = [kAXTextFieldRole as String, "AXSearchField", "AXComboBox", "AXHTMLTextInput"]
                let cond = [kAXTextAreaRole as String, "AXWebArea", "AXStaticText"]
                let editable = isAXEditable(ax); let hasIns = hasInsertionCtx(ax)
                if direct.contains(role) { return true }
                if cond.contains(role) {
                    if role == "AXWebArea" { return editable || hasIns }
                    if role == kAXTextAreaRole as String { return hasIns }
                    return editable || hasIns
                }
                if ["AXGroup","AXScrollArea","AXSplitGroup","AXRadioButton","AXButton"].contains(role), hasEditableChild(ax) { return true }
                if terminals.contains(bid) { return editable || hasIns }
                if editable || hasIns {
                    if role == "AXWebArea" { return editable && hasIns }
                    if role == kAXTextAreaRole as String { return hasIns }
                    return true
                }
            }
        }
        return HUDManager.shared.lastKnownTypingState()
    }

    private func throttledTypingMode(interval: TimeInterval = 0.12) -> Bool {
        let now = Date()
        if now.timeIntervalSince(lastTypingCheckAt) < interval { return cachedTypingMode }
        cachedTypingMode = isTypingMode; lastTypingCheckAt = now; return cachedTypingMode
    }

    // MARK: - Focus Snapshots
    private struct FocusedInputSnapshot { let pid: pid_t; let bundleID: String?; let elementFingerprint: String? }

    private func axStringAttribute(_ el: AXUIElement, _ attr: CFString) -> String? {
        var v: CFTypeRef?; guard AXUIElementCopyAttributeValue(el, attr, &v) == .success, let r = v as? String else { return nil }
        return r.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    private func axCGPointAttribute(_ el: AXUIElement, _ attr: CFString) -> CGPoint? {
        var v: CFTypeRef?; guard AXUIElementCopyAttributeValue(el, attr, &v) == .success, let r = v, CFGetTypeID(r) == AXValueGetTypeID() else { return nil }
        let a = r as! AXValue; guard AXValueGetType(a) == .cgPoint else { return nil }; var p = CGPoint.zero; return AXValueGetValue(a, .cgPoint, &p) ? p : nil
    }
    private func axCGSizeAttribute(_ el: AXUIElement, _ attr: CFString) -> CGSize? {
        var v: CFTypeRef?; guard AXUIElementCopyAttributeValue(el, attr, &v) == .success, let r = v, CFGetTypeID(r) == AXValueGetTypeID() else { return nil }
        let a = r as! AXValue; guard AXValueGetType(a) == .cgSize else { return nil }; var s = CGSize.zero; return AXValueGetValue(a, .cgSize, &s) ? s : nil
    }
    private func sanitizeFP(_ raw: String?, fallback: String = "-") -> String {
        guard let raw, !raw.isEmpty else { return fallback }
        return raw.replacingOccurrences(of: "|", with: "/").replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespacesAndNewlines)
    }
    private func makeElementFingerprint(_ el: AXUIElement) -> String {
        let role = sanitizeFP(axStringAttribute(el, kAXRoleAttribute as CFString), fallback: "?")
        let sub = sanitizeFP(axStringAttribute(el, kAXSubroleAttribute as CFString))
        let id = sanitizeFP(axStringAttribute(el, "AXIdentifier" as CFString))
        let title = sanitizeFP(axStringAttribute(el, kAXTitleAttribute as CFString))
        let ph = sanitizeFP(axStringAttribute(el, "AXPlaceholderValue" as CFString))
        let pos = axCGPointAttribute(el, kAXPositionAttribute as CFString).map { "\(Int($0.x.rounded()))x\(Int($0.y.rounded()))" } ?? "-"
        let size = axCGSizeAttribute(el, kAXSizeAttribute as CFString).map { "\(Int($0.width.rounded()))x\(Int($0.height.rounded()))" } ?? "-"
        var wt = "-"; var wr: CFTypeRef?
        if AXUIElementCopyAttributeValue(el, kAXWindowAttribute as CFString, &wr) == .success, let w = wr, CFGetTypeID(w) == AXUIElementGetTypeID() {
            wt = sanitizeFP(axStringAttribute(w as! AXUIElement, kAXTitleAttribute as CFString))
        }
        return [role, sub, id, title, ph, wt, pos, size].joined(separator: "|")
    }
    private func currentFocusedInputSnapshot() -> FocusedInputSnapshot? {
        let sw = AXUIElementCreateSystemWide(); var fe: CFTypeRef?
        guard AXUIElementCopyAttributeValue(sw, kAXFocusedUIElementAttribute as CFString, &fe) == .success, let r = fe, CFGetTypeID(r) == AXUIElementGetTypeID() else { return nil }
        let el = r as! AXUIElement; var pid: pid_t = 0; AXUIElementGetPid(el, &pid); guard pid > 0 else { return nil }
        return FocusedInputSnapshot(pid: pid, bundleID: NSRunningApplication(processIdentifier: pid)?.bundleIdentifier, elementFingerprint: makeElementFingerprint(el))
    }
    private func lockSessionInputTarget() {
        let snap = currentFocusedInputSnapshot()
        sessionTargetPID = snap?.pid; sessionTargetBundleID = snap?.bundleID
        sessionTargetElementFingerprint = snap?.elementFingerprint; didLogSessionTargetMismatch = false
    }
    private func rearmInputTarget(reason: String) {
        lockSessionInputTarget(); micProgressLockedPID = sessionTargetPID; isMicProgressPausedForTarget = false
        segmentStartedAt = .distantPast
        micProgressSilentTicks = 0
        micProgressActiveTicks = 0
        latestVoiceActivity = false
        latestVoiceRMS = 0
        HUDManager.shared.updateMicProgress(progress: 0.0, visible: false)
        dictationHandler.reset(targetPID: sessionTargetPID)
    }

    // MARK: - Injection Target Validation
    private func isJobInputTargetValidForInjection(_ job: ProcessedJob) -> Bool {
        let trusted = accessibilityTrustedSnapshot || AXIsProcessTrusted()
        if accessibilityTrustedSnapshot != trusted { accessibilityTrustedSnapshot = trusted }
        if !trusted { return false }
        if job.sessionTypingMode && (job.targetPID == nil || job.targetPID == 0) { return true }
        guard let tp = job.targetPID, tp > 0 else { return true }
        guard let front = NSWorkspace.shared.frontmostApplication else { return false }
        let matches = front.processIdentifier == tp || (job.targetBundleID.map { front.bundleIdentifier == $0 } ?? false)
        guard matches else { return false }
        return true
    }

    // MARK: - Speech Term Corrections (preserved)
    private struct SpeechTermGroup: Codable { var id: String; var name: String; var isEnabled: Bool; var applyToAllApps: Bool; var appList: String; var rulesText: String }
    private struct SpeechReplacementRule { let from: String; let to: String; let requiresCommandLike: Bool }
    private func shouldEnableSpeechTermCorrection() -> Bool {
        if UserDefaults.standard.object(forKey: "speechTermCorrectionEnabled") != nil { return UserDefaults.standard.bool(forKey: "speechTermCorrectionEnabled") }
        if UserDefaults.standard.object(forKey: "speechFixDevTerms") == nil { return true }
        return UserDefaults.standard.bool(forKey: "speechFixDevTerms")
    }
    private func groupAppWhitelist(_ raw: String) -> [String] { raw.components(separatedBy: CharacterSet(charactersIn: ",\n")).map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }.filter { !$0.isEmpty } }
    private func loadSpeechTermGroups() -> [SpeechTermGroup] {
        if let data = UserDefaults.standard.data(forKey: "speechTermGroupsV2"), let g = try? JSONDecoder().decode([SpeechTermGroup].self, from: data) { return g }; return []
    }
    private func currentContextBundleIDs() -> [String] {
        [(sessionTargetBundleID ?? "").lowercased(), (NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "").lowercased()].filter { !$0.isEmpty }
    }
    private func activeGroupsForCurrentContext() -> [SpeechTermGroup] {
        let gs = loadSpeechTermGroups(); guard !gs.isEmpty else { return [] }; let bs = currentContextBundleIDs()
        return gs.filter { g in guard g.isEnabled else { return false }; if g.applyToAllApps { return true }; guard !bs.isEmpty else { return false }
            let wl = groupAppWhitelist(g.appList); guard !wl.isEmpty else { return false }; return bs.contains { b in wl.contains(where: { b.contains($0) }) } }
    }
    private func isGitHubCommandLikePhrase(_ text: String) -> Bool {
        let s = text.lowercased()
        let zh = ["提交","分支","仓库","代码","拉取","推送","合并","变基","开pr","issue","代码库"]
        let en = ["git","repo","repository","branch","commit","push","pull","merge","rebase","pr","issue","github"]
        if zh.contains(where: { s.contains($0) }) { return true }; if en.contains(where: { s.contains($0) }) { return true }
        return ["打开","去","到","看","搜","查","open","go to","search","check"].contains(where: { s.contains($0) })
    }
    private func replacementRules(from raw: String) -> [SpeechReplacementRule] {
        raw.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty && !$0.hasPrefix("#") }
            .compactMap { line in let p = line.components(separatedBy: "=>").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                guard p.count >= 2, !p[0].isEmpty, !p[1].isEmpty else { return nil }
                return SpeechReplacementRule(from: p[0], to: p[1], requiresCommandLike: p.count >= 3 && p[2].lowercased().contains("cmd")) }
    }
    private func replacementRules(for g: SpeechTermGroup) -> [SpeechReplacementRule] { replacementRules(from: g.rulesText) }
    private func normalizeRecognizedText(_ raw: String) -> String {
        let corrected = applyContextualSpeechCorrections(raw)
        return deduplicateRepeatedTailPhrase(corrected)
    }
    private func deduplicateRepeatedTailPhrase(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 8 else { return trimmed }

        var chars = Array(trimmed)
        var changed = false

        repeat {
            changed = false
            let maxUnit = min(16, chars.count / 2)
            guard maxUnit >= 3 else { break }

            for unitLen in stride(from: maxUnit, through: 3, by: -1) {
                let start = chars.count - unitLen
                let prevStart = start - unitLen
                guard prevStart >= 0 else { continue }

                let prev = chars[prevStart..<start]
                let tail = chars[start..<chars.count]
                guard prev.elementsEqual(tail) else { continue }

                let segment = String(prev)
                let hasWhitespace = segment.unicodeScalars.contains { CharacterSet.whitespacesAndNewlines.contains($0) }
                let hasLetterOrDigit = segment.unicodeScalars.contains { CharacterSet.alphanumerics.contains($0) }
                let hasCJK = segment.unicodeScalars.contains { (0x4E00...0x9FFF).contains(Int($0.value)) }
                guard !hasWhitespace, hasLetterOrDigit || hasCJK else { continue }

                chars.removeSubrange(start..<chars.count)
                changed = true
                break
            }
        } while changed

        return String(chars)
    }
    private func applyContextualSpeechCorrections(_ raw: String) -> String {
        guard shouldEnableSpeechTermCorrection(), raw.count <= 120 else { return raw }
        let gs = activeGroupsForCurrentContext()
        if gs.isEmpty {
            guard raw.contains("后果") else { return raw }
            let wl = groupAppWhitelist(UserDefaults.standard.string(forKey: "speechFixDevTermsWhitelist") ?? "")
            if wl.isEmpty { return raw }; let bs = currentContextBundleIDs()
            guard bs.contains(where: { b in wl.contains(where: { b.contains($0) }) }) else { return raw }
            guard isGitHubCommandLikePhrase(raw) else { return raw }
            return raw.replacingOccurrences(of: "后果", with: "GitHub")
        }
        var c = raw
        for g in gs { for r in replacementRules(for: g) { guard c.contains(r.from) else { continue }
            if r.requiresCommandLike && !isGitHubCommandLikePhrase(c) { continue }; c = c.replacingOccurrences(of: r.from, with: r.to) } }
        return c
    }
}

// MARK: - Global Logger (Merged)

enum GlobalLogger {
    private static let subsystem = "com.7fei.Aether"

    static let speech = OSLog(subsystem: subsystem, category: "Speech")
    static let lifecycle = OSLog(subsystem: subsystem, category: "Lifecycle")
    static let input = OSLog(subsystem: subsystem, category: "Input")
    static let motion = OSLog(subsystem: subsystem, category: "Motion")
    static let router = OSLog(subsystem: subsystem, category: "Router")

    static func log(_ message: String, log: OSLog, type: OSLogType = .default) {
        let category: String
        if log === speech { category = "Speech" }
        else if log === lifecycle { category = "Lifecycle" }
        else if log === input { category = "Input" }
        else if log === motion { category = "Motion" }
        else if log === router { category = "Router" }
        else { category = "Aether" }

        let formatted = "\(Date()) [\(category)] \(message)\n"
        fputs(formatted, stderr)
        os_log("%{public}@", log: log, type: type, message)
    }
}

extension OSLog {
    func info(_ message: String) {
        GlobalLogger.log(message, log: self, type: .info)
    }
    func error(_ message: String) {
        GlobalLogger.log(message, log: self, type: .error)
    }
    func debug(_ message: String) {
        GlobalLogger.log(message, log: self, type: .debug)
    }
}
