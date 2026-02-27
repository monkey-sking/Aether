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
@MainActor
final class SpeechManager: ObservableObject {
    private struct IntentJob: Sendable {
        let seq: Int
        let intent: VoiceIntent
        let localeIdentifier: String
        let llmEnhancementEnabled: Bool
        let sessionTypingMode: Bool
        let screenTypedCount: Int
        let targetPID: pid_t?
        let targetBundleID: String?
    }

    private struct ProcessedJob: Sendable {
        let seq: Int
        let intent: VoiceIntent
        let localeIdentifier: String
        let sessionTypingMode: Bool
        let screenTypedCount: Int
        let targetPID: pid_t?
        let targetBundleID: String?
        let diagnostics: String?
    }

    private actor IntentPipeline {
        private var nextSeq: Int = 0
        private var expectedSeq: Int = 0
        private var readyBySeq: [Int: ProcessedJob] = [:]

        func allocateSeq() -> Int {
            let s = nextSeq
            nextSeq += 1
            return s
        }

        func submit(_ job: ProcessedJob) -> [ProcessedJob] {
            readyBySeq[job.seq] = job
            var out: [ProcessedJob] = []
            while let j = readyBySeq.removeValue(forKey: expectedSeq) {
                out.append(j)
                expectedSeq += 1
            }
            return out
        }
    }

    @Published var status: String = "Idle"
    @Published var lastTranscript: String = ""
    @Published var lastError: String = ""
    
    // Microphone Management
    @Published var availableInputDevices: [AudioInputDevice] = []
    @Published var selectedInputDeviceID: AudioDeviceID = 0 { // 0 = System Default
        didSet {
            // Only restart if changed and capture path is active.
            if oldValue != selectedInputDeviceID {
                let captureActive = (audioEngine?.isRunning == true) || recognitionTask != nil || isAlwaysListeningEnabled
                if captureActive {
                    scheduleEngineRestart(reason: "input-device-selection")
                }
            }
        }
    }
    private var lastLoggedHUDIcon: String?
    private var lastLoggedAirPodSide: AirPodSide = .none
    
    // [Fix] Add missing isPTTEnabled property to SpeechManager so we can check it
    @Published var isPTTEnabled: Bool = UserDefaults.standard.object(forKey: "isPTTEnabled") as? Bool ?? true {
        didSet { 
            UserDefaults.standard.set(isPTTEnabled, forKey: "isPTTEnabled")
            syncRecognitionState()
        }
    }
    
    // --- New Features (Build 2170) ---

    @Published var activeLocale: Locale = Locale(identifier: "zh-CN") {
        didSet {
            // Re-initialize recognizer on locale change
            if oldValue.identifier != activeLocale.identifier {
                recognizer = SFSpeechRecognizer(locale: activeLocale)
                // [Fix] Restart session if locale changed
                if isAlwaysListeningEnabled {
                    startContinuous()
                }
            }
        }
    }
    
    // [Feature] Manual Language Selection
    // If nil, use system locale. If set, force specific locale.
    var explicitLocaleIdentifier: String? {
        get { UserDefaults.standard.string(forKey: "speechLocaleIdentifier") }
        set { 
            UserDefaults.standard.set(newValue, forKey: "speechLocaleIdentifier")
            refreshLocale()
        }
    }
    
    // [Feature] Smart Language Toggle
    // Remembers the last non-English locale to toggle back to from English.
    var lastNonEnglishLocaleIdentifier: String {
        get { UserDefaults.standard.string(forKey: "lastNonEnglishLocaleIdentifier") ?? "zh-CN" }
        set { UserDefaults.standard.set(newValue, forKey: "lastNonEnglishLocaleIdentifier") }
    }
    
    private func refreshLocale() {
        if let id = explicitLocaleIdentifier, !id.isEmpty, id != "system" {
            activeLocale = Locale(identifier: id)
            // [Smart Toggle] Update non-English memory if this is not English
            if !id.starts(with: "en") {
                lastNonEnglishLocaleIdentifier = id
            }
        } else {
            activeLocale = Locale.current
            let systemId = activeLocale.identifier
            if !systemId.starts(with: "en") {
                lastNonEnglishLocaleIdentifier = systemId
            }
        }
        os_log("Locale refreshed: %{public}@", log: log, type: .info, activeLocale.identifier)
    }
    
    var currentInputDeviceIcon: String {
        // [Priority 1] Physical Hardware check - if truly empty, return error state
        let realHardware = availableInputDevices.filter { $0.id != 0 }
        if realHardware.isEmpty {
            // Signal a diagnostic error state rather than a generic mic
            return "mic.slash.fill"
        }

        // [Priority 2] Current Selected/Default Audio Device
        var deviceIDToUse = selectedInputDeviceID
        if deviceIDToUse == 0 {
            var address = AudioObjectPropertyAddress(
                mSelector: kAudioHardwarePropertyDefaultInputDevice,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            var size = UInt32(MemoryLayout<AudioDeviceID>.size)
            AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &deviceIDToUse)
        }
        
        if let matchedDevice = availableInputDevices.first(where: { $0.id == deviceIDToUse }) {
            let lowerName = matchedDevice.name.lowercased()
            let isCurrentDeviceAirPods = lowerName.contains("airpods") || matchedDevice.iconName.contains("airpod")
            guard isCurrentDeviceAirPods else {
                return matchedDevice.iconName
            }

            let airpodSide = AirPodsDetector.shared.currentSide()
            if airpodSide == .none {
                return matchedDevice.iconName
            }

            let baseIcon = matchedDevice.iconName
            switch airpodSide {
            case .left:
                if baseIcon == "airpodsmax" { return "airpodsmax" }
                if baseIcon == "airpodspro" { return "airpodspro.left" }
                return "airpod.gen3.left"
            case .right:
                if baseIcon == "airpodsmax" { return "airpodsmax" }
                if baseIcon == "airpodspro" { return "airpodspro.right" }
                return "airpod.gen3.right"
            case .both:
                if baseIcon == "airpodsmax" { return "airpodsmax" }
                if baseIcon == "airpodspro" { return "airpodspro" }
                return "airpod.gen3"
            case .none:
                return matchedDevice.iconName
            }
        }
        
        // Fallback: use system default icon
        if selectedInputDeviceID != 0,
           let selected = availableInputDevices.first(where: { $0.id == selectedInputDeviceID }) {
            return selected.iconName
        }

        if let anyDefault = availableInputDevices.first(where: { $0.id != 0 }) {
            return anyDefault.iconName
        }
        
        return AudioInputDevice.defaultSystem.iconName
    }

    private func hudInputIcon() -> String {
        let icon = currentInputDeviceIcon
        let side = AirPodsDetector.shared.currentSide()
        if icon != lastLoggedHUDIcon || side != lastLoggedAirPodSide {
            var deviceIDToUse = selectedInputDeviceID
            if deviceIDToUse == 0 {
                var address = AudioObjectPropertyAddress(
                    mSelector: kAudioHardwarePropertyDefaultInputDevice,
                    mScope: kAudioObjectPropertyScopeGlobal,
                    mElement: kAudioObjectPropertyElementMain
                )
                var size = UInt32(MemoryLayout<AudioDeviceID>.size)
                AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &deviceIDToUse)
            }
            let activeName = availableInputDevices.first(where: { $0.id == deviceIDToUse })?.name ?? "unknown"
            GlobalLogger.speech.info("[HUD Icon] icon=\(icon), side=\(side.rawValue), selectedID=\(selectedInputDeviceID), activeID=\(deviceIDToUse), activeName=\(activeName)")
            let fileLog = "\(Date()): [HUD Icon] icon=\(icon), side=\(side.rawValue), selectedID=\(selectedInputDeviceID), activeID=\(deviceIDToUse), activeName=\(activeName)\n"
            if let data = fileLog.data(using: .utf8) {
                let tracePath = "/tmp/aether_hud_icon_trace.txt"
                if !FileManager.default.fileExists(atPath: tracePath) {
                    FileManager.default.createFile(atPath: tracePath, contents: nil)
                }
                if let fh = FileHandle(forWritingAtPath: tracePath) {
                    fh.seekToEndOfFile()
                    fh.write(data)
                    try? fh.close()
                }
            }
            lastLoggedHUDIcon = icon
            lastLoggedAirPodSide = side
        }
        return icon
    }

    @Published var isAlwaysListeningEnabled: Bool = UserDefaults.standard.bool(forKey: "isAlwaysListeningEnabled") {
        didSet {
            UserDefaults.standard.set(isAlwaysListeningEnabled, forKey: "isAlwaysListeningEnabled")
            syncRecognitionState()
        }
    }
    
    // New: Controls whether we execute commands DIRECTLY without a wake word.
    @Published var isDirectCommandEnabled: Bool = false

    @Published var isWakeWordEnabled: Bool = UserDefaults.standard.object(forKey: "isWakeWordEnabled") as? Bool ?? true {
        didSet { 
            UserDefaults.standard.set(isWakeWordEnabled, forKey: "isWakeWordEnabled") 
            syncRecognitionState()
        }
    }
    
    /// Global Silence Check: If all triggers are OFF, ensure HUD is hidden and engine is DOWN.
    private func syncRecognitionState() {
        let anyTriggerActive = isAlwaysListeningEnabled || isWakeWordEnabled || isPTTEnabled
        
        os_log("Syncing Recognition State: PTT=%d, Wake=%d, Continuous=%d -> AnyActive=%d", 
               log: log, type: .info, isPTTEnabled, isWakeWordEnabled, isAlwaysListeningEnabled, anyTriggerActive)
        
        if !anyTriggerActive {
            // All triggers are off -> Forced Silence
            resetHUDTransientState()
            stopAndFinalize()
            teardownEngine()
            HUDManager.shared.hide()
        } else {
            // At least one trigger is active.
            // If Continuous or Wake Word is enabled, we should be in startContinuous mode.
            if isAlwaysListeningEnabled || isWakeWordEnabled {
                startContinuous()
            } else {
                resetHUDTransientState()
                // [Fix] Ensure HUD refreshes (and potential hides) if switching to PTT-only mode
                refreshContinuousHUD()
            }
        }
    }

    @Published var isGazeWakeEnabled: Bool = UserDefaults.standard.object(forKey: "isGazeWakeEnabled") as? Bool ?? true {
        didSet { UserDefaults.standard.set(isGazeWakeEnabled, forKey: "isGazeWakeEnabled") }
    }
    @Published var isLLMEnhancementEnabled: Bool = false
    @Published var isAutoPunctuationEnabled: Bool = UserDefaults.standard.object(forKey: "isAutoPunctuationEnabled") as? Bool ?? true {
        didSet { UserDefaults.standard.set(isAutoPunctuationEnabled, forKey: "isAutoPunctuationEnabled") }
    }
    @Published var isDictating: Bool = false // For HUD Feedback

    private let router = VoiceCommandRouter()
    private let injector = TextInjector()
    
    // Internal States
    private var lastStreamedText: String = ""
    private var screenTypedCount: Int = 0  // Tracks actual chars typed on screen (grows monotonically)
    private var stopTimer: Timer?
    private var failsafeTimer: Timer?
    private var segmentTimer: Timer?
    private var micProgressTimer: Timer?
    private var segmentStartedAt: Date = .distantPast
    private var segmentDurationSec: TimeInterval = 0
    private var isMicProgressPausedForTarget: Bool = false
    private var micProgressLockedPID: pid_t?
    private var isPTTHeld: Bool = false
    private var wasAwake: Bool = false // Tracks previous wake state for UI updates
    private var lastSpeechAt: Date = .distantPast
    private var utteranceStartedAt: Date = .distantPast
    private var audioRingBuffer: [AVAudioPCMBuffer] = []
    private let ringBufferCapacity = 10 // ~0.5s at 1024 frames/buffer

    private var audioEngine: AVAudioEngine?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var finalizationWorkItem: DispatchWorkItem? // For cancellable delayed finalization
    private var pendingEngineRestartWorkItem: DispatchWorkItem?
    private var lastEngineRestartAt: Date = .distantPast
    private let engineRestartDebounce: TimeInterval = 0.55
    private let engineRestartMinInterval: TimeInterval = 1.5
    private var continuousRecoveryGraceUntil: Date = .distantPast
    
    // Recognizer (Updated on locale change)
    private var recognizer: SFSpeechRecognizer? = SFSpeechRecognizer(locale: Locale(identifier: "zh-CN"))

    private var continuousTimer: Timer?
    private var lastContinuousStartAt: Date = .distantPast
    private var isStopping: Bool = false // Prevent HUD flicker during trailing audio capture
    private var lastChangeAt: Date?
    private var lastStableText: String = ""
    private var sessionGeneration: Int = 0 
    private var sessionTypingMode: Bool = false
    private var sessionTargetPID: pid_t?
    private var sessionTargetBundleID: String?
    private var didLogSessionTargetMismatch: Bool = false
    private var lastFocusToastAt: Date = .distantPast
    private var hudOverrideUntil: Date = .distantPast
    private var hudOverrideMode: HUDMode = .command
    private var hudOverrideMessage: String = ""
    private var hudOverrideIcon: String = "info.circle"
    private var isUtteranceActive: Bool = false
    private var cachedTypingMode: Bool = false
    private var lastTypingCheckAt: Date = .distantPast
    @Published var lastWakeTime: Date? // For context-aware wake window & UI feedback
    private var cancellables = Set<AnyCancellable>()
    private let intentPipeline = IntentPipeline()

    private var isAwake: Bool {
        // Gaze Wake: if looking at screen AND tracking is active -> Awake
        // Note: HeadMotionManager is MainActor, ensure safe access.
        // Gaze Wake: if looking at screen AND tracking is active -> Awake
        if isGazeWakeEnabled && HeadMotionManager.shared.isTracking && HeadMotionManager.shared.isLookingAtScreen {
            return true
        }

        guard let last = lastWakeTime else { return false }
        return Date().timeIntervalSince(last) < alwaysListeningWakeWindowSeconds()
    }

    private func alwaysListeningWakeWindowSeconds() -> TimeInterval {
        let value = UserDefaults.standard.object(forKey: "alwaysListeningWakeWindowSeconds") as? Double ?? 4.0
        return min(max(value, 2.0), 30.0)
    }

    private func maxRecordingSegmentSeconds() -> TimeInterval {
        // Apple Speech streaming tasks can degrade/hang on long sessions.
        // Segmenting reduces failure rate for long dictation.
        let v = UserDefaults.standard.object(forKey: "maxRecordingSegmentSeconds") as? Double ?? 32.0
        return min(max(v, 10.0), 120.0)
    }

    private func scheduleSegmentTimer(forGeneration gen: Int) {
        segmentTimer?.invalidate()
        let maxSec = maxRecordingSegmentSeconds()
        segmentTimer = Timer.scheduledTimer(withTimeInterval: maxSec, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.handleSegmentTimeout(expectedGeneration: gen, maxSec: maxSec)
            }
        }
    }

    private func startMicProgressUI(durationSec: TimeInterval, generation gen: Int) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            guard self.sessionGeneration == gen else { return }

            self.micProgressTimer?.invalidate()
            self.micProgressTimer = nil

            self.segmentStartedAt = Date()
            self.segmentDurationSec = max(durationSec, 0.1)

            // Target semantics: lock ring to the current session target; if focus already changed, start paused.
            self.micProgressLockedPID = self.sessionTargetPID
            if let lockedPID = self.micProgressLockedPID,
               let currentPID = self.currentFocusedPID(),
               currentPID != lockedPID {
                self.isMicProgressPausedForTarget = true
            } else {
                self.isMicProgressPausedForTarget = false
            }

            HUDManager.shared.updateMicProgress(progress: 0.0, visible: true)
            self.micProgressTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
                guard let self else { return }
                guard self.sessionGeneration == gen else { return }
                self.pauseMicProgressForFocusChangeIfNeeded()
                guard !self.isMicProgressPausedForTarget else { return }
                Task { @MainActor in
                    self.maybeFinalizeOnTrailingSilence()
                }

                // Gate progress on "actual voice activity" to avoid the ring advancing during silence.
                // We use the HUD audio level as a cheap VAD proxy.
                let vadThreshold = UserDefaults.standard.object(forKey: "micProgressVADThreshold") as? Double ?? 0.07
                let level = Double(HUDManager.shared.state.audioLevel)
                let hasVoiceActivity = level >= vadThreshold
                if !hasVoiceActivity {
                    // Keep it visible but don't advance.
                    return
                }
                let elapsed = Date().timeIntervalSince(self.segmentStartedAt)
                let p = CGFloat(min(max(elapsed / self.segmentDurationSec, 0.0), 1.0))
                HUDManager.shared.updateMicProgress(progress: p, visible: true)
            }
        }
    }

    private func stopMicProgressUI(keepVisible: Bool) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.micProgressTimer?.invalidate()
            self.micProgressTimer = nil
            let wasPausedForTarget = self.isMicProgressPausedForTarget
            self.isMicProgressPausedForTarget = false
            self.micProgressLockedPID = nil
            if keepVisible {
                // If we paused due to focus change, keep the ring visible but reset to 0.
                // Otherwise, freezing at 100% gives a subtle "segment boundary" cue.
                HUDManager.shared.updateMicProgress(progress: wasPausedForTarget ? 0.0 : 1.0, visible: true)
            } else {
                HUDManager.shared.updateMicProgress(progress: 0.0, visible: false)
            }
        }
    }

    @MainActor
    private func handleSegmentTimeout(expectedGeneration gen: Int, maxSec: TimeInterval) {
        guard sessionGeneration == gen else { return }
        guard recognitionTask != nil else { return }
        guard !isStopping else { return }

        // Only segment active payload sessions. In wake-word standby we should not churn sessions.
        let isStandbyWakeWord = isAlwaysListeningEnabled && isWakeWordEnabled && !isAwake && !isDirectCommandEnabled && !sessionTypingMode
        if isStandbyWakeWord {
            scheduleSegmentTimer(forGeneration: gen)
            return
        }

        // If the user is still holding PTT (or we're in Always Listening), auto-restart capture.
        let shouldContinue = isPTTHeld || isAlwaysListeningEnabled

        os_log("Segment timeout: finalizing after %.0fs (gen %d).", log: GlobalLogger.speech, type: .info, maxSec, gen)
        // Mirror the PTT "trailing capture" UX: show ellipsis while we finalize the current segment.
        isStopping = true
        refreshContinuousHUD(isDictating: false)
        stopMicProgressUI(keepVisible: shouldContinue)
        stopAndFinalize(keepHUDVisible: shouldContinue)

        guard shouldContinue else { return }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) { [weak self] in
            guard let self else { return }
            // Avoid starting a new session if another already started.
            if self.recognitionTask == nil && !self.isStopping {
                self.startOnce()
            }
        }
    }

    private func currentFocusedPID() -> pid_t? {
        let systemWide = AXUIElementCreateSystemWide()
        var focusedElement: AnyObject?
        guard AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &focusedElement) == .success,
              let elementRef = focusedElement else {
            return nil
        }
        let element = elementRef as! AXUIElement
        var pid: pid_t = 0
        AXUIElementGetPid(element, &pid)
        return pid > 0 ? pid : nil
    }

    private func lockSessionInputTarget() {
        sessionTargetPID = currentFocusedPID()
        didLogSessionTargetMismatch = false
        if let pid = sessionTargetPID,
           let app = NSRunningApplication(processIdentifier: pid) {
            sessionTargetBundleID = app.bundleIdentifier
        } else {
            sessionTargetBundleID = nil
        }
    }

    private func rearmInputTarget(reason: String) {
        lockSessionInputTarget()
        micProgressLockedPID = sessionTargetPID
        isMicProgressPausedForTarget = false
        segmentStartedAt = Date()
        HUDManager.shared.updateMicProgress(progress: 0.0, visible: true)
        os_log("Re-armed input target (reason=%{public}@) lockedPID=%d", log: log, type: .info, reason, sessionTargetPID ?? -1)
    }

    private func pauseMicProgressForFocusChangeIfNeeded() {
        guard HUDManager.shared.state.isMicProgressVisible else { return }
        guard let lockedPID = micProgressLockedPID else { return }
        guard let currentPID = currentFocusedPID() else { return }
        guard currentPID != lockedPID else { return }
        guard !isMicProgressPausedForTarget else { return }

        // [Concurrency Update] Do NOT pause continuous dictation on focus change. 
        // We now allow speech to be captured while focus changes, and injection will 
        // handle background targeting.
        
        // Target semantics: focus change immediately pauses and resets the ring (still visible).
        // isMicProgressPausedForTarget = true
        // HUDManager.shared.updateMicProgress(progress: 0.0, visible: true)
        // setHUDOverride(
        //     mode: .command,
        //     message: activeLocale.identifier.starts(with: "zh")
        //         ? "检测到焦点切换，已暂停输入，需要重新触发"
        //         : "Focus changed. Input paused. Trigger again.",
        //     icon: "exclamationmark.triangle.fill",
        //     duration: 1.6
        // )
        os_log("Focus changed during dictation (lockedPID=%d currentPID=%d). Continuing capture.", log: log, type: .info, lockedPID, currentPID)
    }

    @MainActor
    private func maybeFinalizeOnTrailingSilence() {
        guard isAlwaysListeningEnabled else { return }
        guard recognitionTask != nil else { return }
        guard !isStopping else { return }
        guard !lastTranscript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        let now = Date()
        let trailingSilenceMs = UserDefaults.standard.object(forKey: "trailingSilenceMs") as? Double ?? 900.0
        let minUtteranceMs = UserDefaults.standard.object(forKey: "minUtteranceMs") as? Double ?? 450.0
        let maxUtteranceMs = UserDefaults.standard.object(forKey: "maxUtteranceMs") as? Double ?? 15000.0

        let startedAt = utteranceStartedAt == .distantPast ? now : utteranceStartedAt
        let utteranceAgeMs = now.timeIntervalSince(startedAt) * 1000.0
        let silenceAgeMs = now.timeIntervalSince(lastSpeechAt) * 1000.0

        // Don't EOS while we are in wake-gated standby.
        let isStandbyWakeWord = isAlwaysListeningEnabled && isWakeWordEnabled && !isAwake && !isDirectCommandEnabled && !sessionTypingMode
        if isStandbyWakeWord { return }

        if utteranceAgeMs >= maxUtteranceMs {
            os_log("EOS: max utterance reached (%.0fms). Finalizing.", log: log, type: .info, utteranceAgeMs)
        } else {
            guard utteranceAgeMs >= minUtteranceMs else { return }
            guard silenceAgeMs >= trailingSilenceMs else { return }
            os_log("EOS: trailing silence (%.0fms). Finalizing.", log: log, type: .info, silenceAgeMs)
        }

        isStopping = true
        refreshContinuousHUD(isDictating: false) // show ellipsis
        stopAndFinalize(keepHUDVisible: true)
    }

    private func isSessionInputTargetValidForInjection() -> Bool {
        // [Concurrency Update] Always return true. We support background injection now.
        return true
    }



    private struct SpeechTermGroup: Codable {
        var id: String
        var name: String
        var isEnabled: Bool
        var applyToAllApps: Bool
        var appList: String
        var rulesText: String
    }

    private struct SpeechReplacementRule {
        let from: String
        let to: String
        let requiresCommandLike: Bool
    }

    private func shouldEnableSpeechTermCorrection() -> Bool {
        if UserDefaults.standard.object(forKey: "speechTermCorrectionEnabled") != nil {
            return UserDefaults.standard.bool(forKey: "speechTermCorrectionEnabled")
        }
        // Compatibility fallback for previous dev-only switch.
        if UserDefaults.standard.object(forKey: "speechFixDevTerms") == nil { return true }
        return UserDefaults.standard.bool(forKey: "speechFixDevTerms")
    }

    private func groupAppWhitelist(_ raw: String) -> [String] {
        return raw
            .components(separatedBy: CharacterSet(charactersIn: ",\n"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }
    }

    private func loadSpeechTermGroups() -> [SpeechTermGroup] {
        if let data = UserDefaults.standard.data(forKey: "speechTermGroupsV2"),
           let groups = try? JSONDecoder().decode([SpeechTermGroup].self, from: data) {
            return groups
        }
        return []
    }

    private func currentContextBundleIDs() -> [String] {
        let target = (sessionTargetBundleID ?? "").lowercased()
        let frontmost = (NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "").lowercased()
        return [target, frontmost].filter { !$0.isEmpty }
    }

    private func activeGroupsForCurrentContext() -> [SpeechTermGroup] {
        let groups = loadSpeechTermGroups()
        guard !groups.isEmpty else { return [] }
        let bundles = currentContextBundleIDs()
        return groups.filter { group in
            guard group.isEnabled else { return false }
            if group.applyToAllApps { return true }
            guard !bundles.isEmpty else { return false }
            let whitelist = groupAppWhitelist(group.appList)
            guard !whitelist.isEmpty else { return false }
            return bundles.contains { b in whitelist.contains(where: { b.contains($0) }) }
        }
    }

    private func isGitHubCommandLikePhrase(_ text: String) -> Bool {
        let s = text.lowercased()
        let zhKeywords = ["提交", "分支", "仓库", "代码", "拉取", "推送", "合并", "变基", "开pr", "issue", "代码库"]
        let enKeywords = ["git", "repo", "repository", "branch", "commit", "push", "pull", "merge", "rebase", "pr", "issue", "github"]
        if zhKeywords.contains(where: { s.contains($0) }) { return true }
        if enKeywords.contains(where: { s.contains($0) }) { return true }
        let actionHints = ["打开", "去", "到", "看", "搜", "查", "open", "go to", "search", "check"]
        return actionHints.contains(where: { s.contains($0) })
    }

    private func replacementRules(from rawText: String) -> [SpeechReplacementRule] {
        rawText
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") }
            .compactMap { line in
                let parts = line.components(separatedBy: "=>").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                guard parts.count >= 2 else { return nil }
                let requiresCmd = (parts.count >= 3 && parts[2].lowercased().contains("cmd"))
                guard !parts[0].isEmpty, !parts[1].isEmpty else { return nil }
                return SpeechReplacementRule(from: parts[0], to: parts[1], requiresCommandLike: requiresCmd)
            }
    }

    private func applyLegacyFallbackCorrection(_ raw: String) -> String {
        guard shouldEnableSpeechTermCorrection() else { return raw }
        guard raw.contains("后果") else { return raw }
        let legacyWhitelist = UserDefaults.standard.string(forKey: "speechFixDevTermsWhitelist") ?? ""
        let targets = groupAppWhitelist(legacyWhitelist)
        if targets.isEmpty { return raw }
        let bundles = currentContextBundleIDs()
        guard bundles.contains(where: { b in targets.contains(where: { b.contains($0) }) }) else { return raw }
        if !isGitHubCommandLikePhrase(raw) { return raw }
        return raw.replacingOccurrences(of: "后果", with: "GitHub")
    }

    private func replacementRules(for group: SpeechTermGroup) -> [SpeechReplacementRule] {
        let rules = replacementRules(from: group.rulesText)
        if !rules.isEmpty {
            return rules
        }
        return []
    }

    private func applyContextualSpeechCorrections(_ raw: String) -> String {
        guard shouldEnableSpeechTermCorrection() else { return raw }
        guard raw.count <= 120 else { return raw }

        let groups = activeGroupsForCurrentContext()
        if groups.isEmpty {
            return applyLegacyFallbackCorrection(raw)
        }

        var corrected = raw
        for group in groups {
            for rule in replacementRules(for: group) {
                guard corrected.contains(rule.from) else { continue }
                if rule.requiresCommandLike && !isGitHubCommandLikePhrase(corrected) { continue }
                corrected = corrected.replacingOccurrences(of: rule.from, with: rule.to)
            }
        }

        if corrected != raw {
            os_log("Applied contextual correction: '%{public}@' -> '%{public}@'", log: log, type: .info, raw, corrected)
        }
        return corrected
    }

    private func setHUDOverride(mode: HUDMode, message: String, icon: String, duration: TimeInterval) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.hudOverrideMode = mode
            self.hudOverrideMessage = message
            self.hudOverrideIcon = icon
            self.hudOverrideUntil = Date().addingTimeInterval(max(0.2, duration))
        }
    }

    private func clearHUDOverride() {
        hudOverrideUntil = .distantPast
        hudOverrideMessage = ""
        hudOverrideIcon = "info.circle"
    }

    private func refreshContinuousHUD(isDictating: Bool = false) {
        // Ensure transient "toast" messages are readable; avoid being immediately overwritten by the 0.3s ticker.
        // Do not override the explicit `.processing` UX.
        if !isStopping && Date() < hudOverrideUntil {
            HUDManager.shared.update(mode: hudOverrideMode, message: hudOverrideMessage, language: activeLocale.identifier, inputDeviceIcon: hudOverrideIcon)
            return
        }

        // Real trigger topology:
        // - isAlwaysListeningEnabled: mic session for continuous recognition is active
        // - isDirectCommandEnabled: always-on direct command mode
        // - isWakeWordEnabled: wake gate enabled within continuous recognition
        let isContinuousSessionEnabled = isAlwaysListeningEnabled
        let isWakeGatedContinuous = isContinuousSessionEnabled && isWakeWordEnabled && !isDirectCommandEnabled
        
        // [Audit Fix] Central Visibility Guard
        // The HUD should only be visible if:
        // 1. Continuous mode (Always Listening or Wake Word) is enabled.
        // 2. OR an active session is running (PTT, Processing, or Dictating).
        let isContinuousActive = isContinuousSessionEnabled
        let isSessionActive = recognitionTask != nil || isStopping || isDictating
        
        if !isContinuousActive && !isSessionActive {
            clearHUDOverride()
            HUDManager.shared.hide()
            return
        }

        // [Mode Resolution] Determine exactly what the HUD should show
        let mode: HUDMode
        var message: String = ""
        let realHardware = availableInputDevices.filter { $0.id != 0 }
        let noMicMessage = activeLocale.identifier.starts(with: "zh") ? "未检测到麦克风" : "No Microphone Detected"

        // Rule 0: No microphone should never appear as standby (green dot).
        if realHardware.isEmpty {
            HUDManager.shared.update(
                mode: .listening,
                message: noMicMessage,
                language: activeLocale.identifier,
                inputDeviceIcon: hudInputIcon()
            )
            return
        }

        // Rule 1: Standby (Green Dot)
        // Occurs in continuous mode when we are NOT 'awake' and NOT in an active payload state.
        if isWakeGatedContinuous && !isAwake && !isStopping && !isDictating && lastTranscript.isEmpty {
            mode = .standby
        } 
        // Rule 2: Active Payload States
        else if isDictating {
            mode = .dictation
        } else if isStopping {
            mode = .processing
        } else if !lastTranscript.isEmpty {
            mode = .command
            message = lastTranscript
        } 
        // Rule 3: Listening (The fallback active state)
        else {
            mode = .listening
        }

        HUDManager.shared.update(mode: mode, message: message, language: activeLocale.identifier, inputDeviceIcon: hudInputIcon())
    }
    
    private func showPTTUnavailableHUD() {
        let message = activeLocale.identifier.starts(with: "zh") ? "未检测到麦克风" : "No Microphone Detected"
        HUDManager.shared.update(
            mode: .listening,
            message: message,
            language: activeLocale.identifier,
            inputDeviceIcon: hudInputIcon()
        )
    }

    private func scheduleContinuousRecovery(delay: TimeInterval = 0.25) {
        guard isAlwaysListeningEnabled else { return }
        continuousRecoveryGraceUntil = Date().addingTimeInterval(delay + 0.6)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self = self else { return }
            guard self.isAlwaysListeningEnabled else { return }
            if self.recognitionTask == nil {
                self.startOnce()
            }
        }
    }

    private func shouldUseVoiceProcessing() -> Bool {
        UserDefaults.standard.object(forKey: "useVoiceProcessingIO") as? Bool ?? false
    }

    private func shouldAutoEnableVoiceProcessingForSpeakers() -> Bool {
        // Default ON: fixes "external speakers leaking into mic" for built-in mic use.
        // Users can force-enable via `useVoiceProcessingIO` or disable auto via this key.
        if UserDefaults.standard.object(forKey: "autoVoiceProcessingForSpeakers") == nil { return true }
        return UserDefaults.standard.object(forKey: "autoVoiceProcessingForSpeakers") as? Bool ?? true
    }

    private func systemDefaultDeviceID(selector: AudioObjectPropertySelector) -> AudioDeviceID? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var deviceID: AudioDeviceID = 0
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &deviceID)
        guard status == noErr, deviceID != 0 else { return nil }
        return deviceID
    }

    private func audioDeviceName(_ id: AudioDeviceID) -> String? {
        var nameAddress = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyName,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var nameRef: CFString = "" as CFString
        var nameSize = UInt32(MemoryLayout<CFString>.size)
        let status = AudioObjectGetPropertyData(id, &nameAddress, 0, nil, &nameSize, &nameRef)
        guard status == noErr else { return nil }
        return nameRef as String
    }

    private func shouldAutoEnableVoiceProcessingIO() -> Bool {
        guard shouldAutoEnableVoiceProcessingForSpeakers() else { return false }

        let inputID: AudioDeviceID? = (selectedInputDeviceID != 0)
            ? selectedInputDeviceID
            : systemDefaultDeviceID(selector: kAudioHardwarePropertyDefaultInputDevice)
        let outputID: AudioDeviceID? = systemDefaultDeviceID(selector: kAudioHardwarePropertyDefaultOutputDevice)

        let inputName = inputID.flatMap { audioDeviceName($0) } ?? ""
        let outputName = outputID.flatMap { audioDeviceName($0) } ?? ""

        let inLower = inputName.lowercased()
        let outLower = outputName.lowercased()

        func looksLikeBuiltInMic(_ s: String) -> Bool {
            if s.contains("built-in") || s.contains("internal") || s.contains("macbook") || s.contains("imac") { return true }
            if s.contains("内建") || s.contains("内部") { return true }
            return false
        }

        func looksLikeHeadphones(_ s: String) -> Bool {
            if s.contains("airpods") { return true }
            if s.contains("headphone") || s.contains("earphone") || s.contains("earbud") || s.contains("buds") { return true }
            if s.contains("耳机") { return true }
            if s.contains("wh-") { return true }
            return false
        }

        // Only auto-enable AEC when using a built-in mic and output is likely speakers (not headphones).
        guard looksLikeBuiltInMic(inLower) else { return false }
        guard !looksLikeHeadphones(outLower) else { return false }

        os_log("Auto VoiceProcessingIO decision: input='%{public}@' output='%{public}@' -> enable", log: log, type: .info, inputName, outputName)
        return true
    }

    private var isTypingMode: Bool {
        if HUDManager.shared.lastKnownTypingState() {
            return true
        }

        func isAXEditable(_ element: AXUIElement) -> Bool {
            var editableValue: CFTypeRef?
            guard AXUIElementCopyAttributeValue(element, "AXEditable" as CFString, &editableValue) == .success else {
                return false
            }
            return (editableValue as? Bool) == true || (editableValue as? NSNumber)?.boolValue == true
        }

        func hasInsertionContext(_ element: AXUIElement) -> Bool {
            var selectedRangeValue: CFTypeRef?
            if AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &selectedRangeValue) == .success {
                return true
            }
            var markerRangeValue: CFTypeRef?
            if AXUIElementCopyAttributeValue(element, "AXSelectedTextMarkerRange" as CFString, &markerRangeValue) == .success {
                return true
            }
            return false
        }

        func hasEditableDescendant(_ element: AXUIElement, depth: Int = 4) -> Bool {
            if depth <= 0 { return false }
            var childrenRef: CFTypeRef?
            guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenRef) == .success,
                  let children = childrenRef as? [AXUIElement] else {
                return false
            }

            let directEditableRoles = [kAXTextFieldRole as String, "AXSearchField", "AXComboBox", "AXHTMLTextInput"]
            let conditionalRoles = [kAXTextAreaRole as String, "AXWebArea", "AXStaticText"]
            for child in children {
                var roleRef: CFTypeRef?
                let role = (AXUIElementCopyAttributeValue(child, kAXRoleAttribute as CFString, &roleRef) == .success) ? (roleRef as? String ?? "") : ""
                if directEditableRoles.contains(role) { return true }
                if conditionalRoles.contains(role), (isAXEditable(child) || hasInsertionContext(child)) { return true }
                if hasInsertionContext(child) { return true }
                if hasEditableDescendant(child, depth: depth - 1) { return true }
            }
            return false
        }

        // 1. Check System Wide Focus (Most Reliable)
        let systemWide = AXUIElementCreateSystemWide()
        var focusedElement: AnyObject?
        let result = AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &focusedElement)
        
        if result == .success, let elementRef = focusedElement {
            let axElement = elementRef as! AXUIElement
            
            // Check Role
            var role: AnyObject?
            var roleString = ""
            if AXUIElementCopyAttributeValue(axElement, kAXRoleAttribute as CFString, &role) == .success,
               let value = role as? String {
                roleString = value
            }
            
            // Check Owner PID -> Bundle ID (for Siri/Spotlight exceptions)
            var pid: pid_t = 0
            AXUIElementGetPid(axElement, &pid)
            if let app = NSRunningApplication(processIdentifier: pid),
               let bundleId = app.bundleIdentifier {
                let appName = app.localizedName?.lowercased() ?? ""
                let isSiriLike = bundleId.contains("apple.siri") || bundleId == "com.apple.Spotlight" || appName.contains("siri")
                if isSiriLike {
                    return true
                }

                let terminalIds = [
                    "com.apple.Terminal",
                    "com.googlecode.iterm2",
                    "com.github.wez.wezterm",
                    "dev.warp.Warp-Stable"
                ]
                let isTerminal = terminalIds.contains(bundleId)
                let directEditableRoles = [kAXTextFieldRole as String, "AXSearchField", "AXComboBox", "AXHTMLTextInput"]
                let conditionalRoles = [kAXTextAreaRole as String, "AXWebArea", "AXStaticText"]

                let isEditableFlag = isAXEditable(axElement)
                let hasInsertion = hasInsertionContext(axElement)

                if directEditableRoles.contains(roleString) {
                    return true
                }

                if conditionalRoles.contains(roleString) {
                    if roleString == "AXWebArea" {
                        // AXWebArea can expose stale marker/range data in web UIs.
                        // Relax to OR to support web-based inputs like Antigravity.
                        return isEditableFlag || hasInsertion
                    }
                    if roleString == kAXTextAreaRole as String {
                        return hasInsertion
                    }
                    return isEditableFlag || hasInsertion
                }

                if (roleString == "AXGroup" || roleString == "AXScrollArea" || roleString == "AXSplitGroup" || roleString == "AXRadioButton" || roleString == "AXButton"),
                   hasEditableDescendant(axElement) {
                    return true
                }

                if isTerminal {
                    return isEditableFlag || hasInsertion
                }

                if isEditableFlag || hasInsertion {
                    if roleString == "AXWebArea" {
                        return isEditableFlag && hasInsertion
                    }
                    if roleString == kAXTextAreaRole as String {
                        return hasInsertion
                    }
                    return true
                }
            }
        }
        
        return HUDManager.shared.lastKnownTypingState()
    }

    private func throttledTypingMode(interval: TimeInterval = 0.12) -> Bool {
        let now = Date()
        if now.timeIntervalSince(lastTypingCheckAt) < interval {
            return cachedTypingMode
        }
        let mode = isTypingMode
        cachedTypingMode = mode
        lastTypingCheckAt = now
        return mode
    }

    var onIntent: ((VoiceIntent) -> Void)?
    var llmProvider: LLMProvider?

    private let log = OSLog(subsystem: "com.7fei.Aether", category: "Speech")
    
    // Helper to use NSLocalizedString which handles dynamic strings better than String(localized:)
    private func setStatus(_ key: String) {
        self.status = NSLocalizedString(key, comment: "")
    }

    @objc func toggleLanguage() {
        if activeLocale.identifier.starts(with: "en") {
            // If current is English, toggle back to the last known non-English locale
            explicitLocaleIdentifier = lastNonEnglishLocaleIdentifier
        } else {
            // If current is NOT English (CN, JA, FR, etc), switch to English 
            // and ensure this is remembered as our "base" non-English language.
            lastNonEnglishLocaleIdentifier = activeLocale.identifier
            explicitLocaleIdentifier = "en-US"
        }
        status = "Language: \(activeLocale.identifier)"
        os_log("Switched Language to: %{public}@", log: log, type: .info, activeLocale.identifier)
        
        // Update HUD immediately to reflect the new language badge
        let hud = HUDManager.shared
        hud.update(mode: hud.state.mode, message: hud.state.message, language: activeLocale.identifier, inputDeviceIcon: hudInputIcon())
        
        // Restart session if running (streaming context)
        if recognitionTask != nil {
            stopAndFinalize()
            startOnce() // Restart immediately with new locale
        }
    }

    func startOnce() {
        isStopping = false
        // [Stability] Cancel any existing task/timer to prevent stale state
        stopTimer?.invalidate()
        stopTimer = nil
        
        if recognitionTask != nil {
            recognitionTask?.cancel()
            recognitionTask = nil
        }

        guard let recognizer, recognizer.isAvailable else {
            status = NSLocalizedString("speech.unavailable", comment: "")
            lastError = "Speech recognizer unavailable"
            os_log("Error: Speech recognizer unavailable", log: log, type: .error)
            return
        }

        // Ensure Persistent Audio Engine is running
        do {
            try setupAudioEngine()
        } catch {
            status = NSLocalizedString("speech.error", comment: "") // Generic error for engine
            lastError = error.localizedDescription
            
            // In PTT mode we should still show visible feedback while key is held.
            if isAlwaysListeningEnabled {
                refreshContinuousHUD()
                scheduleContinuousRecovery(delay: 0.8)
            } else {
                showPTTUnavailableHUD()
            }
            return
        }

        sessionGeneration += 1
        let currentGeneration = sessionGeneration
        lockSessionInputTarget()
        
        // Reset Streaming State
        lastStreamedText = ""  // [Fix] Clear here at session START, not in cleanup()
        screenTypedCount = 0  // Reset screen tracking
        // [Fix] Don't activate typing mode if we're waiting for wake word (Standby).
        // Otherwise the HUD jumps straight to Active/Dictation on startup.
        if isWakeWordEnabled && !isAwake && !isDirectCommandEnabled {
            sessionTypingMode = false
        } else {
            sessionTypingMode = isTypingMode // Snapshot at session start
        }
        isDictating = sessionTypingMode

        // [Stability] Segment long recordings to avoid SFSpeechRecognizer long-stream bugs.
        failsafeTimer?.invalidate()
        scheduleSegmentTimer(forGeneration: currentGeneration)
        startMicProgressUI(durationSec: maxRecordingSegmentSeconds(), generation: currentGeneration)

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        if #available(macOS 13, *) {
            request.addsPunctuation = isAutoPunctuationEnabled
        }
        // Important: Add contextual strings to improve specific command recognition
        request.contextualStrings = [
            // Pointer / UI ops
            "点击", "双击", "向下", "向上", "右键",
            "Click", "Double Click", "Scroll Down", "Scroll Up", "Right Click",
            // Dev / mixed-language proper nouns (helps zh locales keep common English terms)
            "GitHub", "github", "git", "repo", "repository", "issue", "pull request", "PR",
            "commit", "branch", "merge", "rebase", "checkout", "clone", "push", "pull", "origin", "main", "develop", "release"
        ]

        recognitionRequest = request
        lastTranscript = ""
        lastError = ""
        status = NSLocalizedString("speech.listening", comment: "") + " (\(activeLocale.identifier.starts(with: "zh") ? "中" : "En"))"
        os_log("Session Started (gen %d) Locale: %{public}@", log: log, type: .info, currentGeneration, activeLocale.identifier)
        
        // [Ring Buffer] Flush pre-buffered audio to catch the start of speech
        audioRingBuffer.forEach { recognitionRequest?.append($0) }
        
        // [HUD] Show immediate feedback
        refreshContinuousHUD(isDictating: isDictating)

        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }
            
            // [Streaming Dictation]
            // We process partial results for typing feedback
            if let result = result {
                DispatchQueue.main.async {
                    guard self.sessionGeneration == currentGeneration else { return }
                    var text = result.bestTranscription.formattedString
                    
                    // [Fix] Wake Word Leak: Strip Wake Phrases from the beginning
                    // Only applies if we are in Wake Word Mode (not Direct Command or PTT)
                    if self.isWakeWordEnabled && !self.isDirectCommandEnabled {
                        let lower = text.lowercased()
                        // [Fix] Require minimum length to avoid false wake from noise fragments
                        let isLongEnough = text.count >= 4
                        for phrase in ["hey aether", "hi aether", "aether", "艾瑟"] {
                            if isLongEnough && lower.starts(with: phrase) {
                                // [Fix] Real-time Wake Detection
                                // If we catch the wake word, WAKE UP immediately!
                                if !self.isAwake {
                                    self.lastWakeTime = Date()
                                    self.playWakeSound()
                                    // Target semantics: wake word is an explicit re-arm in wake-gated continuous mode.
                                    if self.isAlwaysListeningEnabled && self.isWakeWordEnabled && !self.isDirectCommandEnabled {
                                        self.rearmInputTarget(reason: "wake-word")
                                    }
                                }
                                
                                // Drop the phrase + standard space/punctuation if present
                                let dropCount = phrase.count
                                let suffix = text.dropFirst(dropCount).trimmingCharacters(in: .whitespacesAndNewlines)
                                text = suffix
                                break // Only strip one prefix
                            }
                        }
                    }

                    text = self.applyContextualSpeechCorrections(text)

                    // Only update "last change" timestamps when the text actually changes.
                    // Noise can cause repeated callbacks; refreshing timestamps here would prevent EOS detection.
                    let now = Date()
                    let prev = self.lastTranscript
                    if text != prev {
                        self.lastTranscript = text
                        self.lastChangeAt = now
                        if self.utteranceStartedAt == .distantPast && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            self.utteranceStartedAt = now
                        }
                    }

                    // Direct Command mode: treat "start of a new utterance" as an explicit re-arm for the current focus.
                    let hasPayload = !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    if hasPayload && !self.isUtteranceActive {
                        self.isUtteranceActive = true
                        if self.isAlwaysListeningEnabled && self.isDirectCommandEnabled {
                            self.rearmInputTarget(reason: "direct-utterance-start")
                        }
                    }
                    if !hasPayload && self.isUtteranceActive {
                        self.isUtteranceActive = false
                    }
                    let liveTyping = self.throttledTypingMode()
                    
                    // [Fix] Typing Guard: Allow typing if:
                    // 1. Awake (Wake Word mode active)
                    // 2. Direct Command (Always listening)
                    // 3. PTT (Manual activation - implied by !isAlwaysListeningEnabled)
                    let canType = self.isAwake || self.isDirectCommandEnabled || !self.isAlwaysListeningEnabled
                    self.sessionTypingMode = (self.sessionTypingMode || liveTyping) && canType
                    self.isDictating = self.sessionTypingMode
                    
                    // [UX Fix] Extend Wake Window logic
                    // Only extend if:
                    // 1. We have actual content (text not empty)
                    // 2. OR we just woke up (transition from !Awake -> Awake is handled by the initial wake, 
                    //    but here we handle continuous speech).
                    // If text is empty (just wake word stripped), DO NOT extend. This lets it timeout if user says nothing.
                    // [Fix] Only extend wake window if text is meaningful (>2 chars),
                    // preventing noise fragments from keeping the system awake forever.
                    if text.count > 2 && self.isAwake {
                        self.lastWakeTime = Date()
                    }
                    
                    // Update HUD with live transcript
                    // [UX] If we have text, show waveform (Dictation Mode) to avoid static text
                    // [Fix] Don't re-show HUD if stopping (PTT grace period) unless Always Listening
                    // [Fix] Don't re-show HUD if stopping (PTT grace period) unless Always Listening
                    // [Refinement] If isFinal, strictly DO NOT update HUD here (handled in isFinal block)
                    let isFinal = result.isFinal
                    
                    // [Fix] Unified HUD: Use single source of truth instead of inline computation.
                    // This prevents state divergence between refreshContinuousHUD and callback.
                    if (!self.isStopping || self.isAlwaysListeningEnabled) && !isFinal {
                        self.refreshContinuousHUD(isDictating: self.isDictating)
                    } else if self.isStopping && !isFinal {
                        // Keep Showing "Processing..." until final result
                        self.refreshContinuousHUD()
                    }
                    
                    // Handle Streaming Typing (if in typing mode)
                    // [DYNAMIC SYNC] Real-time corrections with stability guard
                    if self.sessionTypingMode && self.isSessionInputTargetValidForInjection() {
                        self.handleStreamingTyping(currentText: text)
                    }
                    
                    // [Zero-Latency Finalization] If engine confirms final result, trigger immediately
                    if result.isFinal {
                        os_log("isFinal detected, triggering immediate finalization", log: self.log, type: .info)
                        self.finalizationWorkItem?.cancel()
                        self.finalizationWorkItem = nil
                        
                        // Trigger finalization immediately
                        if self.isStopping {
                            self.handleTranscript(text)
                            if !self.isAlwaysListeningEnabled {
                                self.teardownEngine()
                                self.refreshContinuousHUD() // [Fix] Unified Hide
                            }
                        }
                    }
                }
            }
            
            if let error = error {
                DispatchQueue.main.async {
                    guard self.sessionGeneration == currentGeneration else { return }
                    
                    // Check if error is just "No speech" or "Cancelled"
                    let nsError = error as NSError
                    let isNoSpeechError = (nsError.domain == "kAFAssistantErrorDomain" && nsError.code == 203) 
                        || error.localizedDescription.contains("No speech detected")
                    let isCancelled = (nsError.domain == "kAFAssistantErrorDomain" && (nsError.code == 216 || nsError.code == 1700)) 
                        || (nsError.domain == "SFSpeechErrorDomain" && nsError.code == 10) // 10 = cancelled
                        || error.localizedDescription.contains("canceled")
                    
                    // Ignore cancellations (intentional stops)
                    if isCancelled {
                        self.stopAndFinalize()
                        return
                    }

                    // [No Speech Handling]
                    // If no speech is detected, we should NOT show an error in Continuous Mode.
                    // Instead, we just loop back (restart) silently.
                    if isNoSpeechError {
                        os_log("No Speech Detected (Timeout). Resetting...", log: self.log, type: .info)
                        if self.isAlwaysListeningEnabled {
                            self.teardownSession()
                            self.refreshContinuousHUD()
                            self.scheduleContinuousRecovery(delay: 0.12)
                        } else {
                            self.stopAndFinalize()
                        }
                        return
                    }

                    self.status = NSLocalizedString("speech.error", comment: "")
                    self.lastError = error.localizedDescription
                    os_log("Recognition Error: %{public}@", log: self.log, type: .error, error.localizedDescription)
                    self.stopAndFinalize()
                    self.scheduleContinuousRecovery(delay: 0.4)
                }
            }
        }
    }
    
    // [Streaming Logic - APPEND ONLY]
    private func handleStreamingTyping(currentText: String) {
        // APPEND-ONLY strategy: NEVER backspace during streaming.
        // - Text on screen only grows, never shrinks or changes
        // - screenTypedCount tracks exactly how many chars are on screen
        // - Final sync will clean-replace everything at once
        // This eliminates ALL backspace-related corruption during streaming.
        
        let currentChars = Array(currentText)
        
        // Only type new characters if engine output is longer than what's on screen
        guard currentChars.count > screenTypedCount else {
            // Engine shortened or same length - ignore, text on screen stays
            return
        }
        
        let newChars = currentChars[screenTypedCount...]
        let newText = String(newChars)
        AutomationOutputs.shared.typeText(newText, targetPID: sessionTargetPID)
        
        // Update tracking
        screenTypedCount = currentChars.count
        lastStreamedText = currentText  // Track engine output for final sync
        
        os_log("Stream Append: +'%{public}@' (screen: %d)", 
               log: log, type: .info, newText, screenTypedCount)
    }

    private func setupAudioEngine() throws {
        if let engine = audioEngine, engine.isRunning { return }
        

        
        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        
        // [Microphone Selection]
        // Set device BEFORE accessing format or installing tap
        setInputDeviceForEngine(engine)
        
        // Voice Processing (AEC/NS)
        // Auto-enable only in the "built-in mic + speakers" scenario to reduce feedback/echo pickup.
        // Users can force-enable via `useVoiceProcessingIO`. Auto can be disabled via `autoVoiceProcessingForSpeakers`.
        if #available(macOS 10.15, *) {
            let shouldEnable = shouldUseVoiceProcessing() || shouldAutoEnableVoiceProcessingIO()
            do {
                try inputNode.setVoiceProcessingEnabled(shouldEnable)
                os_log("Voice Processing IO %{public}@.", log: log, type: .info, shouldEnable ? "enabled" : "disabled")
            } catch {
                os_log("Failed to set Voice Processing IO=%{public}@ : %{public}@", log: log, type: .error, String(describing: shouldEnable), error.localizedDescription)
            }
        }

        let format = inputNode.outputFormat(forBus: 0)
        
        if format.sampleRate == 0 {
             os_log("Error: Input Node Sample Rate is 0", log: log, type: .error)
        } else {
             os_log("Input Format: %{public}@", log: log, type: .info, format.description)
        }
        
        // Remove existing tap if any (to be safe)
        inputNode.removeTap(onBus: 0)
        
        // Use NATIVE format for Tap (avoid Error -10875)
        // Manual downmix to Mono inside the block.
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: nil) { [weak self] buffer, _ in
             guard let self = self else { return }
             
             let format = buffer.format
             var monoBuffer = buffer
             
             // 1. Downmix to Mono if needed (for recognition engine and RMS consistency)
             if format.channelCount > 1 {
                 if let downmixed = AVAudioFormat(commonFormat: format.commonFormat, sampleRate: format.sampleRate, channels: 1, interleaved: false).flatMap({ AVAudioPCMBuffer(pcmFormat: $0, frameCapacity: buffer.frameCapacity) }) {
                     downmixed.frameLength = buffer.frameLength
                     if let srcData = buffer.floatChannelData?[0], let dstData = downmixed.floatChannelData?[0] {
                         memcpy(dstData, srcData, Int(buffer.frameLength) * MemoryLayout<Float>.size)
                     }
                     monoBuffer = downmixed
                 }
             }
             
             // 2. Calculate RMS from the mono signal
             var rms: Float = 0
             if let channelData = monoBuffer.floatChannelData?[0] {
                 let count = Int(monoBuffer.frameLength)
                 if count > 0 {
                     let channelDataPtr = UnsafeBufferPointer(start: channelData, count: count)
                     var sum: Float = 0
                     for i in 0..<count {
                         let sample = channelDataPtr[i]
                         sum += sample * sample
                     }
                     // Raw RMS
                     let rawRms = sqrt(sum / Float(count))
                     
                     // [Enhancement] Non-linear scaling (sqrt) to boost low-level audio
                     // This makes 'ordinary' mics feel much more responsive.
                     // Mapping: 0.01 -> 0.1, 0.04 -> 0.2, etc.
                     rms = sqrt(rawRms)
                 }
             }
             
             // 3. Update HUD with amplified level
             // Multiplier moved to HUDManager for centralized control.
             HUDManager.shared.updateAudioLevel(rms)

             // Track voice activity timestamps on main (used for EOS / progress gating).
             let vadThreshold = UserDefaults.standard.object(forKey: "micProgressVADThreshold") as? Double ?? 0.07
             let voiceActive = Double(rms) >= vadThreshold
             
             if Int.random(in: 0...100) == 0 {
                  os_log("Audio RMS: %.4f (scaled)", log: self.log, type: .debug, rms)
             }
             // 4. Send to recognition engine
             self.recognitionRequest?.append(monoBuffer)
             
             // 5. Update Ring Buffer (Main Thread)
             DispatchQueue.main.async { [weak self] in
                 guard let self = self else { return }
                 if voiceActive {
                     self.lastSpeechAt = Date()
                     if self.utteranceStartedAt == .distantPast {
                         self.utteranceStartedAt = self.lastSpeechAt
                     }
                 }
                 self.audioRingBuffer.append(monoBuffer)
                 if self.audioRingBuffer.count > self.ringBufferCapacity {
                     self.audioRingBuffer.removeFirst()
                 }
             }
        }
        
        audioEngine = engine
        engine.prepare()
        try engine.start()
        os_log("Persistent Audio Engine STARTED.", log: log, type: .info)
    }

    // MARK: - Audio Device Management
    
    func refreshInputDevices() {
        var devices: [AudioInputDevice] = [.defaultSystem]
        
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        var dataSize: UInt32 = 0
        let status = AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &propertyAddress, 0, nil, &dataSize)
        
        guard status == noErr else { return }
        
        let deviceCount = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var deviceIDs = [AudioDeviceID](repeating: 0, count: deviceCount)
        
        let status2 = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &propertyAddress, 0, nil, &dataSize, &deviceIDs)
        
        guard status2 == noErr else { return }
        
        for id in deviceIDs {
            // Get Name
            var name: String = "Unknown Device"
            var nameSize = UInt32(MemoryLayout<CFString>.size)
            var nameAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyDeviceNameCFString,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            var nameRef: CFString?
            
            if AudioObjectGetPropertyData(id, &nameAddress, 0, nil, &nameSize, &nameRef) == noErr,
               let cfName = nameRef {
                name = cfName as String
            }
            
            // Check if input channels > 0
            var scope = kAudioDevicePropertyScopeInput
            var address = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyStreamConfiguration,
                mScope: scope,
                mElement: 0
            )
            
            var size: UInt32 = 0
            AudioObjectGetPropertyDataSize(id, &address, 0, nil, &size)
            
            if size > 0 {
                let bufferList = UnsafeMutablePointer<AudioBufferList>.allocate(capacity: Int(size))
                defer { bufferList.deallocate() }
                
                AudioObjectGetPropertyData(id, &address, 0, nil, &size, bufferList)
                
                let buffers = UnsafeMutableAudioBufferListPointer(bufferList)
                let channelCount = buffers.reduce(0) { $0 + Int($1.mNumberChannels) }
                
                NSLog("[SpeechManager] Device Found: \(name) (ID: \(id)) - Input Channels: \(channelCount)")
                
                if channelCount > 0 {
                    // Get UID
                    var uid: String = "\(id)"
                    var uidSize = UInt32(MemoryLayout<CFString>.size)
                    var uidAddress = AudioObjectPropertyAddress(
                        mSelector: kAudioDevicePropertyDeviceUID,
                        mScope: kAudioObjectPropertyScopeGlobal,
                        mElement: kAudioObjectPropertyElementMain
                    )
                    var uidRef: CFString?
                    if AudioObjectGetPropertyData(id, &uidAddress, 0, nil, &uidSize, &uidRef) == noErr,
                       let cfUid = uidRef {
                        uid = cfUid as String
                    }
                    
                    // Improved Device Detection (AirPods, etc)
                    var iconName = "mic.fill"
                    let lowerName = name.lowercased()
                    
                    if lowerName.contains("airpods") {
                        iconName = "airpods"
                        if lowerName.contains("pro") { iconName = "airpodspro" }
                        if lowerName.contains("max") { iconName = "airpodsmax" }
                    } else if lowerName.contains("studio display") {
                        iconName = "monitor"
                    } else if lowerName.contains("external") {
                        iconName = "mic.badge.plus"
                    } else if lowerName.contains("macbook") || lowerName.contains("built-in") {
                        iconName = "laptopcomputer"
                    }
                    
                    devices.append(AudioInputDevice(id: id, name: name, uid: uid, iconName: iconName))
                }
            } else {
                 NSLog("[SpeechManager] Device Found: \(name) (ID: \(id)) - NO INPUT SCOPE DATA")
            }
        }
        
        DispatchQueue.main.async {
            self.availableInputDevices = devices
            self.refreshContinuousHUD() // [Fix] Immediately update HUD icon when device list refreshes
        }
    }
    
    private func scheduleEngineRestart(reason: String, debounce: TimeInterval? = nil) {
        let wait = debounce ?? engineRestartDebounce
        pendingEngineRestartWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.pendingEngineRestartWorkItem = nil
            self.performEngineRestart(reason: reason)
        }
        pendingEngineRestartWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + wait, execute: work)
    }

    private func performEngineRestart(reason: String) {
        let elapsed = Date().timeIntervalSince(lastEngineRestartAt)
        if elapsed < engineRestartMinInterval {
            let remaining = engineRestartMinInterval - elapsed
            scheduleEngineRestart(reason: "\(reason)-throttled", debounce: remaining)
            return
        }

        os_log("Restarting engine (reason=%{public}@)...", log: log, type: .default, reason)
        stopAndFinalize()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            guard let self else { return }
            if self.isAlwaysListeningEnabled {
                self.startOnce()
            }
            self.lastEngineRestartAt = Date()
        }
    }
    
    private func setInputDeviceForEngine(_ engine: AVAudioEngine) {
        guard selectedInputDeviceID != 0 else { return } // Use default
        
        let inputNode = engine.inputNode
        let audioUnit = inputNode.audioUnit
        
        guard let au = audioUnit else { return }
        
        var deviceID = selectedInputDeviceID
        let error = AudioUnitSetProperty(
            au,
            kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global,
            0,
            &deviceID,
            UInt32(MemoryLayout<AudioDeviceID>.size)
        )
        
        if error != noErr {
            os_log("Failed to set input device to ID %d: error %d", log: log, type: .error, deviceID, error)
        } else {
            os_log("Set input device to ID %d", log: log, type: .info, deviceID)
        }
    }

    func stopAndFinalize(keepHUDVisible: Bool = false) {
        if !keepHUDVisible {
            clearHUDOverride()
        }
        stopMicProgressUI(keepVisible: keepHUDVisible)
        if !keepHUDVisible {
            if isAlwaysListeningEnabled {
                refreshContinuousHUD(isDictating: false)
            } else {
                HUDManager.shared.hide()
            }
        }
        guard let task = recognitionTask else {
            // If there is no active task, we still must clear transient HUD-driving state.
            resetHUDTransientState()
            if !keepHUDVisible {
                if isAlwaysListeningEnabled {
                    refreshContinuousHUD()
                } else {
                    HUDManager.shared.hide()
                }
            }
            return
        }
        
        // [Fix] Don't cancel immediately. Use finish() to allow processing trailing audio.
        recognitionRequest?.endAudio()
        task.finish() 
        
        // We set a hard deadline. If finish() doesn't return IsFinal in X seconds, we force cancel.
        // But for UI responsiveness, we might want to capture current best transcript NOW if needed,
        // or just wait. The user wants the LAST bit of text.
        
        // Strategy:
        // 1. Mark stopping.
        // 2. Schedule a "Force Kill" timer to clean up if SFSpeechRecognizer hangs (common).
        // 3. DO NOT nil out task/request yet. Let the completion handler in `startOnce` fire one last time.
        
        // HOWEVER, our `startOnce` completion handler has a `sessionGeneration` check.
        // We need to keep `sessionGeneration` valid for a bit longer?
        // Actually, let's keep it simple: 
        // We wait for a short duration (e.g. 800ms) for the final result.
        // If it comes, `handleTranscript` is called by the binding logic? No, `handleTranscript` is called HERE.
        
        // NEW LOGIC:
        // We cannot block here. We need to be async.
        // But `stopAndFinalize` implies immediate action for the caller (like PTT Up).
        
        // Let's try a hybrid:
        // 1. Send finish().
        // 2. Wait async for the callback to verify "isFinal".
        // 3. Fallback: If we don't get a better result in 500ms, use what we have.
        
        let genToFinalize = sessionGeneration
        let fallbackTranscript = lastTranscript // Snapshot now just in case
        
        // Detach old task from "active" slot so new sessions can start
        // But keep a reference to it to cancel it later
        let oldTask = recognitionTask
        recognitionTask = nil // Detach
        recognitionRequest = nil

        // [Cancellable Finalization] Use DispatchWorkItem so isFinal can cancel it
        let workItem = DispatchWorkItem { [weak self, weak oldTask] in
            guard let self = self else { return }
            
            // [Fix] Generation Guard: If user started a NEW session, abort this legacy cleanup.
            guard self.sessionGeneration == genToFinalize else {
                os_log("Async Finalize Aborted: Generation changed (Old: %d, New: %d)", log: self.log, type: .info, genToFinalize, self.sessionGeneration)
                oldTask?.cancel()
                return
            }
            
            oldTask?.cancel()
            
            let finalTx = self.lastTranscript
            let textToUse = finalTx.isEmpty ? fallbackTranscript : finalTx
            
            self.status = "Processing…"
            os_log("Session Finalized (Fallback). Final: '%{public}@'", log: self.log, type: .default, textToUse)
            os_log("Session Finalized (Fallback). Final: '%{public}@'", log: self.log, type: .default, textToUse)
            self.handleTranscript(textToUse)
            
            self.isStopping = false // [FIX] Ensure processing state is reset
            
            // [Critical Fix] Ensure HUD hides on fallback (if not already hidden by isFinal)
            if !self.isAlwaysListeningEnabled {
                self.teardownEngine()
                if !keepHUDVisible {
                    HUDManager.shared.hide()
                }
            } else {
                if !keepHUDVisible {
                    self.refreshContinuousHUD() // Force refresh to Standby mode
                }
            }
        }
        
        finalizationWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: workItem)
    }
    
    // Explicit teardown if needed (e.g. app quit)
    func teardownEngine() {
        isStopping = false
        segmentTimer?.invalidate()
        segmentTimer = nil
        micProgressTimer?.invalidate()
        micProgressTimer = nil
        audioEngine?.stop()
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine = nil
    }



    init() {
        GlobalLogger.lifecycle.info("SpeechManager Initialized")
        refreshInputDevices()
        DispatchQueue.main.async { [weak self] in
            self?.refreshContinuousHUD() // [Fix] Populate icon after startup graph settles
        }
        
        // [New] Trigger AirPods Detector immediately on startup
        _ = AirPodsDetector.shared.currentSide()
        NotificationCenter.default.addObserver(self, selector: #selector(pttDown), name: HeadMotionManager.pttDownNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(pttUp), name: HeadMotionManager.pttUpNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(toggleLanguage), name: Notification.Name("AetherToggleLanguage"), object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleAirPodsChange), name: .AirPodsStateChanged, object: nil)
        
        // [Feature] Initialize Locale from UserDefaults
        refreshLocale()

        // [Fix] Startup State & Dependency
        // Delay trigger evaluation to the next run loop to avoid startup-time
        // re-entrant HUD layout while SwiftUI scene graph is still initializing.
        DispatchQueue.main.async { [weak self] in
            self?.syncRecognitionState()
        }

        // [Fix] Immediate refresh on system mic changes
        setupAudioDeviceListeners()

        // Gaze Wake Feedback
        HeadMotionManager.shared.$isLookingAtScreen
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isLooking in
                if isLooking && HeadMotionManager.shared.isTracking {
                    self?.playWakeSound()
                }
            }
            .store(in: &cancellables)
            
        
    }
    
    
    @objc private func handleAirPodsChange() {
        // Force HUD icon refresh when AirPods state changes
        refreshContinuousHUD()
    }

    private func setupAudioDeviceListeners() {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        let block: AudioObjectPropertyListenerBlock = { _, _ in
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                os_log("System Default Input Device CHANGED. Refreshing...", log: self.log, type: .info)
                self.refreshInputDevices()
                
                // If we are using system default (0), this changes our actual icon
                if self.selectedInputDeviceID == 0 {
                    let hud = HUDManager.shared
                    hud.update(
                        mode: hud.state.mode, 
                        message: hud.state.message, 
                        language: hud.state.language, 
                        inputDeviceIcon: self.hudInputIcon()
                    )
                }

                let captureActive = (self.audioEngine?.isRunning == true) || self.recognitionTask != nil || self.isAlwaysListeningEnabled
                if captureActive {
                    self.scheduleEngineRestart(reason: "default-input-device-changed")
                }
            }
        }
        
        // We use the listener block API for better Swift integration
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, nil, block)
    }        
        

    private func playWakeSound() {
        NSSound(named: "Tink")?.play()
    }

    func requestPermissions() {
        GlobalLogger.speech.info("Requesting Permissions")
        SFSpeechRecognizer.requestAuthorization { [weak self] auth in
            DispatchQueue.main.async {
                guard let self = self else { return }
                switch auth {
                case .authorized:
                    self.status = "Speech Authorized"
                    GlobalLogger.speech.info("Permission Granted: Authorized")
                case .denied:
                    self.status = "Speech Denied"
                    GlobalLogger.speech.error("Permission Denied")
                case .restricted:
                    self.status = "Speech Restricted"
                    GlobalLogger.speech.error("Permission Restricted")
                case .notDetermined:
                    self.status = "Speech Not Determined"
                    GlobalLogger.speech.info("Permission Not Determined")
                @unknown default:
                    self.status = "Speech Unknown"
                    GlobalLogger.speech.error("Permission Unknown")
                }
            }
        }
        AVCaptureDevice.requestAccess(for: .audio) { granted in
            GlobalLogger.speech.info("Microphone Permission: \(granted ? "Granted" : "Denied")")
        }
    }

    @objc private func pttDown() {
        GlobalLogger.input.info("PTT DOWN")
        isPTTHeld = true
        // [Fix] Enforce PTT enabled check
        // If the user unchecks "Push to Talk" in settings, this shortcut should do nothing.
        // Note: In "Always Listening" mode, PTT acts as a wake trigger, so we might want to allow it?
        // User said: "Shortcut mode unchecked, still triggers by shortcut -> bug".
        // So we should strictly respect isPTTEnabled UNLESS isAlwaysListeningEnabled is arguably a different feature?
        // Actually, if "Always Listening" is on, PTT is less relevant as a "mode" but acting as a "Wake" button.
        // However, if the user explicitly disabled PTT, they probably don't want the key to do anything.
        // Let's check `isPTTEnabled`.
        guard isPTTEnabled else { return }
        
        // [Continuous Mode] PTT acts as "Force Wake" / "Manual Wake"
        if isAlwaysListeningEnabled {
            os_log("PTT in Continuous Mode -> Manual Wake Triggered", log: log, type: .default)
            
            // 1. Activate Wake Window (Bypass Wake Word for 8s)
            lastWakeTime = Date()
            
            // 2. Feedback (Sound + HUD)
            playWakeSound()
             // Update HUD to remove "(Wake: Aether)" suffix and show active state
            refreshContinuousHUD(isDictating: isDictating)
            
            // [Fix] Ensure session is actually running!
            // If recognitionTask failed/timed out but we are legally "Always Listening",
            // PTT should restart it immediately.
            if recognitionTask == nil || recognitionTask!.state != .running {
                 os_log("PTT: Session dead in Continuous Mode -> Restarting", log: log, type: .default)
                 startOnce()
            }
            return

        }

        // [Standard Mode] Start Session
        let realHardware = availableInputDevices.contains { $0.id != 0 }
        if !realHardware {
            showPTTUnavailableHUD()
        }
        startOnce()
    }

    @objc private func pttUp() {
        GlobalLogger.input.info("PTT UP")
        isPTTHeld = false
        guard !isAlwaysListeningEnabled else { return } // PTT Release should NOT stop continuous mode
        
        // No active session: do not show ".processing" ellipsis.
        guard recognitionTask != nil else {
            isStopping = false
            HUDManager.shared.hide()
            return
        }
        
        isStopping = true
        refreshContinuousHUD() // Update to .processing state immediately
        
        // [Trailing Audio]
        // Delay stopping for 0.6s to catch the last syllable.
        // User reports "dropped last char".
        stopTimer?.invalidate()
        stopTimer = Timer.scheduledTimer(withTimeInterval: 0.6, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.stopAndFinalize()
            }
        }
    }

    private func startContinuous() {
        let now = Date()
        if now.timeIntervalSince(lastContinuousStartAt) < 0.8 {
            return
        }
        lastContinuousStartAt = now

        // Continuous mode: require a wake phrase to reduce accidental actions.
        status = NSLocalizedString("speech.listening", comment: "") + " (Wake: “Aether/艾瑟”)"
        os_log("Starting Continuous Mode (Wake Word Required)", log: log, type: .default)
        startOnce()
        continuousTimer?.invalidate()
        if isAlwaysListeningEnabled {
            // [Fix] Force HUD update on startup to reflect Standby/Active state immediately
            // Add slight delay to ensure HUDManager/Windows are ready
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.refreshContinuousHUD()
            }
            
            continuousTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    self?.tickContinuous()
                }
            }
        }
    }

    private func stopContinuous() {
        os_log("Stopping Continuous Mode", log: log, type: .default)
        continuousTimer?.invalidate()
        continuousTimer = nil
        stopAndFinalize()
        teardownEngine()
    }

    private func tickContinuous() {
        guard isAlwaysListeningEnabled else { return }
        
        // [Fix] Wake State Monitor - MUST be before transcript checks
        // Check if we transitioned from Awake -> Standby (Timeout) or vice versa
        let currentlyAwake = self.isAwake
        if currentlyAwake != wasAwake {
            wasAwake = currentlyAwake
            os_log("Wake State Changed: Awake=%{bool}d", log: log, type: .default, currentlyAwake)
            refreshContinuousHUD()

            // When using wake-gated continuous mode, reset the segment progress visual at the moment we wake.
            // In long standby periods we intentionally avoid segmenting, so any "progress" would be stale.
            if currentlyAwake {
                // Wake-gated mode: waking is an explicit "re-arm" for the current focus.
                if isWakeWordEnabled && !isDirectCommandEnabled {
                    rearmInputTarget(reason: "wake-window-open")
                }
                startMicProgressUI(durationSec: maxRecordingSegmentSeconds(), generation: sessionGeneration)
            }
        }

        // In wake-gated standby we don't segment, and we also don't need to tick the mic progress timer.
        // Stop it to reduce CPU usage and avoid showing a stale filled ring after waking.
        let isWakeGatedContinuous = isAlwaysListeningEnabled && isWakeWordEnabled && !isDirectCommandEnabled
        if isWakeGatedContinuous && !currentlyAwake {
            if micProgressTimer != nil || HUDManager.shared.state.isMicProgressVisible {
                stopMicProgressUI(keepVisible: false)
            }
        }

        // Target semantics: any focus change while the ring is active pauses and resets it.
        pauseMicProgressForFocusChangeIfNeeded()

        let taskState = recognitionTask?.state
        let taskRunning = taskState == .running || taskState == .starting
        let engineRunning = audioEngine?.isRunning == true
        if !taskRunning || !engineRunning {
            if Date() < continuousRecoveryGraceUntil {
                return
            }
            if !engineRunning {
                if pendingEngineRestartWorkItem == nil {
                    os_log("Continuous health-check failed. taskState=%{public}@ engineRunning=%{bool}d -> scheduling engine restart",
                           log: log, type: .error, String(describing: taskState), engineRunning)
                    scheduleEngineRestart(reason: "continuous-health-check-engine-down")
                }
                return
            }

            if taskState == nil || taskState == .finishing || taskState == .canceling || taskState == .completed {
                os_log("Continuous health-check task rollover. taskState=%{public}@ engineRunning=%{bool}d -> scheduling task recovery",
                       log: log, type: .info, String(describing: taskState), engineRunning)
                scheduleContinuousRecovery(delay: 0.12)
            }
            return
        }
        
        guard let lastChange = lastChangeAt else { return }
        guard !lastTranscript.isEmpty else { return }

        // If the transcript hasn't changed for a bit, treat it as an utterance boundary.
        if Date().timeIntervalSince(lastChange) < 1.0 { return }
        if lastStableText == lastTranscript { return }
        lastStableText = lastTranscript

        let text = lastTranscript
        lastTranscript = ""
        lastChangeAt = nil
        isUtteranceActive = false

        os_log("End of utterance detected: '%{public}@'", log: log, type: .default, text)

        // [Fix] Handle transcript BEFORE teardown so `sessionTypingMode` and `lastStreamedText` are valid.
        // Sync check needs state.
        handleTranscript(text)
        
        // Stop current session WITHOUT processing (we already handled it).
        teardownSession()
        
        if isAlwaysListeningEnabled {
            startOnce()
        }
    }

    /// Stops the audio engine and recognition task without processing the transcript.
    /// Used by `tickContinuous()` which handles transcript processing separately.
    private func teardownSession() {
        guard recognitionTask != nil else { return }
        os_log("Ending session (no-process)...", log: log, type: .info)
        // Only stop request/task
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        cleanup()
    }

    private func cleanup() {
        recognitionTask = nil
        recognitionRequest = nil
        stopTimer?.invalidate()
        stopTimer = nil
        failsafeTimer?.invalidate()
        failsafeTimer = nil
        isStopping = false
        isDictating = false
        sessionTypingMode = false
        sessionTargetPID = nil
        sessionTargetBundleID = nil
        didLogSessionTargetMismatch = false
        isUtteranceActive = false
        
        // [Fix] DON'T clear lastStreamedText here! handleTranscript needs it for differential sync.
        // It will be cleared at the START of the next session in startOnce().
        
        // Engine NOT cleared
    }
    
    private func resetHUDTransientState() {
        isStopping = false
        isDictating = false
        sessionTypingMode = false
        sessionTargetPID = nil
        sessionTargetBundleID = nil
        didLogSessionTargetMismatch = false
        isUtteranceActive = false
        lastTranscript = ""
        lastChangeAt = nil
        lastStableText = ""
    }

    private func handleTranscript(_ transcript: String) {
        let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { 
            os_log("Transcript empty, ignoring.", log: log, type: .debug)
            return 
        }

        var textToRoute = trimmed
        var wakeWordDetected = false



        // Check if we are in Direct Command Mode (and mic is running)
        // If isDirectCommandEnabled is true, we treat it as "Always Awake".
        if isDirectCommandEnabled {
            // ---------------------------------------------------------
            // MODE 3: ALWAYS LISTENING (Direct Command)
            // ---------------------------------------------------------
            
            let lower = trimmed.lowercased()
            // [Fix] Unify Wake Word Logic with recognitionTask
            // Use strict prefix matching instead of loose .contains
            let wakeEn = lower.hasPrefix("aether") || lower.hasPrefix("hey aether") || lower.hasPrefix("hi aether")
            let wakeZh = trimmed.hasPrefix("艾瑟") || trimmed.hasPrefix("Aether") // Handle mixed case/script
            let isWakeWord = wakeEn || wakeZh
            
            if isWakeWordEnabled && isWakeWord {
                textToRoute = stripWakeWord(from: trimmed)
                wakeWordDetected = true
                playWakeSound()
            } else {
                // Direct execution
                textToRoute = trimmed
            }
        } else if isAlwaysListeningEnabled {
            // ---------------------------------------------------------
            // MODE 2: WAKE WORD (Gated)
            // ---------------------------------------------------------
            // Mic is on, but Direct Command is OFF.
            // We rely solely on Wake Word or Active Window.
            
             // We rely solely on Wake Word or Active Window.
            
            let lower = trimmed.lowercased()
            // [Fix] Unify Wake Word Logic
            let wakeEn = lower.hasPrefix("aether") || lower.hasPrefix("hey aether") || lower.hasPrefix("hi aether")
            let wakeZh = trimmed.hasPrefix("艾瑟") || trimmed.hasPrefix("Aether")
            let isWakeWord = wakeEn || wakeZh
            
            let isAwakeWindow = isAwake
            
            if isAwakeWindow {
                // Windows is open.
                if isWakeWord {
                    textToRoute = stripWakeWord(from: trimmed)
                    wakeWordDetected = true
                    playWakeSound()
                } else {
                    textToRoute = trimmed
                }
            } else {
                // Window is closed. MUST hear wake word.
                if isWakeWord {
                    textToRoute = stripWakeWord(from: trimmed)
                    wakeWordDetected = true
                    playWakeSound()
                    lastWakeTime = Date() // Open window
                } else {
                    os_log("Ignored: Waiting for Wake Word. (Text: %{public}@)", log: log, type: .debug, trimmed)
                    return
                }
            }
        } else {
            // ---------------------------------------------------------
            // MODE 1: PTT ONLY
            // ---------------------------------------------------------
            // In PTT mode, we process the transcript directly without wake word detection.
            // The user explicitly triggered recording, so we should process whatever they said.
            textToRoute = trimmed
            os_log("PTT Mode: Processing transcript directly", log: log, type: .info)
        }
        
        let typingContext = sessionTypingMode || isTypingMode
        if typingContext {
            os_log("Context: Typing Mode Detected", log: log, type: .info)
        }

        let intent = router.route(transcript: textToRoute, isTypingMode: typingContext)
        
        // Update Wake Time
        if wakeWordDetected {
            lastWakeTime = Date()
        } else if case .unknown = intent {
            // If unknown command in wake window, do NOT extend window? 
            // Or maybe we do, to allow retries? 
            // Let's say we don't extend on unknown, to let it expire if it was just noise.
        } else {
            // Valid command executed -> extend wake window
            lastWakeTime = Date()
        }
        
        // Parallelize heavy work (LLM / typing injection) so we can start capturing the next utterance immediately.
        enqueueIntentForParallelExecution(intent, typingContext: typingContext)
    }

    private func enqueueIntentForParallelExecution(_ intent: VoiceIntent, typingContext: Bool) {
        // Capture all state that will be wiped/reset by the next session.
        let localeID = activeLocale.identifier
        let job = IntentJob(
            seq: -1, // filled below
            intent: intent,
            localeIdentifier: localeID,
            llmEnhancementEnabled: isLLMEnhancementEnabled,
            sessionTypingMode: typingContext ? sessionTypingMode : false,
            screenTypedCount: typingContext ? screenTypedCount : 0,
            targetPID: typingContext ? sessionTargetPID : nil,
            targetBundleID: typingContext ? sessionTargetBundleID : nil
        )

        Task { [weak self] in
            guard let self else { return }
            let seq = await self.intentPipeline.allocateSeq()
            let seeded = IntentJob(
                seq: seq,
                intent: job.intent,
                localeIdentifier: job.localeIdentifier,
                llmEnhancementEnabled: job.llmEnhancementEnabled,
                sessionTypingMode: job.sessionTypingMode,
                screenTypedCount: job.screenTypedCount,
                targetPID: job.targetPID,
                targetBundleID: job.targetBundleID
            )

            Task.detached(priority: .userInitiated) { [weak self] in
                guard let self else { return }
                let processed = await self.processIntentJob(seeded)
                let ready = await self.intentPipeline.submit(processed)
                for r in ready {
                    await MainActor.run { [weak self] in
                        self?.applyProcessedJob(r)
                    }
                }
            }
        }
    }

    private func processIntentJob(_ job: IntentJob) async -> ProcessedJob {
        // Heavy work off the capture loop. Keep execution deterministic by not touching mutable UI state.
        if case .dictation(let text) = job.intent, job.llmEnhancementEnabled, let llmProvider {
            do {
                let enhanced = try await llmProvider.enhanceDictation(text)
                let finalText = enhanced.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? text : enhanced
                return ProcessedJob(
                    seq: job.seq,
                    intent: .dictation(finalText),
                    localeIdentifier: job.localeIdentifier,
                    sessionTypingMode: job.sessionTypingMode,
                    screenTypedCount: job.screenTypedCount,
                    targetPID: job.targetPID,
                    targetBundleID: job.targetBundleID,
                    diagnostics: "llm=ok"
                )
            } catch {
                return ProcessedJob(
                    seq: job.seq,
                    intent: job.intent,
                    localeIdentifier: job.localeIdentifier,
                    sessionTypingMode: job.sessionTypingMode,
                    screenTypedCount: job.screenTypedCount,
                    targetPID: job.targetPID,
                    targetBundleID: job.targetBundleID,
                    diagnostics: "llm=failed(\(error.localizedDescription))"
                )
            }
        }

        return ProcessedJob(
            seq: job.seq,
            intent: job.intent,
            localeIdentifier: job.localeIdentifier,
            sessionTypingMode: job.sessionTypingMode,
            screenTypedCount: job.screenTypedCount,
            targetPID: job.targetPID,
            targetBundleID: job.targetBundleID,
            diagnostics: nil
        )
    }

    private func isJobInputTargetValidForInjection(_ job: ProcessedJob) -> Bool {
        // [Concurrency Update] Always allow injection, even if focus changed.
        // We will handle background injection inside AutomationOutputs.
        return true
    }

    private func applyProcessedJob(_ job: ProcessedJob) {
        // Note: execution is serialized by IntentPipeline drain order.
        switch job.intent {
        case .undo:
            injector.undoPasteIfRecent()
            status = NSLocalizedString("speech.undo", comment: "")
        case .paste:
            AutomationOutputs.shared.pasteFromClipboard()
            status = "Pasted (Cmd+V)"
        case .dictation(let text):
            guard isJobInputTargetValidForInjection(job) else {
                status = NSLocalizedString("speech.done", comment: "")
                return
            }

            if job.sessionTypingMode {
                if job.screenTypedCount > 0 {
                    AutomationOutputs.shared.backspace(count: job.screenTypedCount, targetPID: job.targetPID)
                }
                if !text.isEmpty {
                    injector.type(text, targetPID: job.targetPID)
                }
                status = NSLocalizedString("speech.typed", comment: "")
            } else {
                injector.type(text, targetPID: job.targetPID)
                status = NSLocalizedString("speech.typed", comment: "")
            }
        default:
            onIntent?(job.intent)
            status = NSLocalizedString("speech.done", comment: "")
        }
    }

    private func stripWakeWord(from text: String) -> String {
        var remainder = text
        // Simple heuristic stripping
        let prefixes = ["Aether", "Ether", "Hey Aether", "Hey", "Hi", "艾瑟", "以太", "掉色", "艾色", "嘿", "喂"]
        // Try longest prefix first? 
        // Or just checking ranges.
        // Simplified approach: find range of keywords.
        // Since we already know it matched, let's try to remove the first occurrence.
        
        for key in prefixes {
            if let range = remainder.range(of: key, options: [.caseInsensitive, .diacriticInsensitive]) {
                // Only if it's at the start or very close
                let nearStartLimit = remainder.index(remainder.startIndex, offsetBy: 5, limitedBy: remainder.endIndex) ?? remainder.endIndex
                if range.lowerBound < nearStartLimit {
                    remainder.removeSubrange(remainder.startIndex..<range.upperBound)
                    return remainder.trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }
        }
        return remainder
    }

    private func handleIntent(_ intent: VoiceIntent) {
        os_log("Routing Intent: %{public}@", log: log, type: .default, String(describing: intent))

        switch intent {
        case .undo:
            injector.undoPasteIfRecent()
            status = NSLocalizedString("speech.undo", comment: "")
        case .paste:
            AutomationOutputs.shared.pasteFromClipboard()
            status = "Pasted (Cmd+V)"
        case .dictation(let text):
            // [Concurrency Update] allow injection without checking valid target.
            // guard isSessionInputTargetValidForInjection() else {
            //     status = NSLocalizedString("speech.done", comment: "")
            //     return
            // }
            // If we were streaming, the text is already on screen.
            // But if streaming lagged or was cut off, we must reconcile the difference.
            
            os_log("[DEBUG] handleIntent dictation: text='%{public}@', sessionTypingMode=%d, lastStreamedText='%{public}@'", 
                   log: log, type: .info, text, sessionTypingMode, lastStreamedText)
            
            if sessionTypingMode {
                // [CLEAN REPLACE] Delete everything we typed, then type the final text.
                // This is the ONLY place backspaces happen - one clean operation at the end.
                // screenTypedCount is always accurate because streaming is append-only.
                
                os_log("Final Sync: Clean replace - deleting %d screen chars, typing final '%{public}@' (len:%d)",
                       log: log, type: .info, screenTypedCount, text, text.count)
                
                if screenTypedCount > 0 {
                    AutomationOutputs.shared.backspace(count: screenTypedCount, targetPID: sessionTargetPID)
                }
                
                if !text.isEmpty {
                    injector.type(text, targetPID: sessionTargetPID)
                }
                
                self.status = NSLocalizedString("speech.typed", comment: "")
            } else {
                os_log("[DEBUG] Not in typing mode, typing full text", log: log, type: .info)
                injector.type(text, targetPID: sessionTargetPID)
                self.status = NSLocalizedString("speech.typed", comment: "")
            }
        default:
            onIntent?(intent)
            self.status = NSLocalizedString("speech.done", comment: "")
        }
    }

    func undoLastInjection() {
        injector.undoPasteIfRecent()
    }
}

// MARK: - Global Logger (Merged)

enum GlobalLogger {
    private static let subsystem = "com.7fei.Aether"

    static let speech = OSLog(subsystem: subsystem, category: "Speech")
    static let lifecycle = OSLog(subsystem: subsystem, category: "Lifecycle")
    static let input = OSLog(subsystem: subsystem, category: "Input")

    static func log(_ message: String, log: OSLog, type: OSLogType = .default) {
        // Always print to stderr for immediate terminal feedback.
        // We use a simplified category extraction for the stderr print.
        let category: String
        if log === speech { category = "Speech" }
        else if log === lifecycle { category = "Lifecycle" }
        else if log === input { category = "Input" }
        else { category = "Aether" }

        let formatted = "\(Date()) [\(category)] \(message)\n"
        fputs(formatted, stderr)
        
        // Also log to system console
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

