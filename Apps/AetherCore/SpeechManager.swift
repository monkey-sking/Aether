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

enum VoiceIntent: Equatable {
    case clickLeft
    case clickRight
    case doubleClick
    case startPointer
    case stopPointer
    case recenter
    case setDwell(Bool)
    case scroll(Int, Int) // dx, dy
    case scrollToWeb(String) // "top", "bottom"
    case dragStart
    case dragEnd
    case undo
    case paste
    case lockConnection
    case unlockConnection
    case dictation(String)
    case unknown(String)
}

extension VoiceIntent: Sendable {}

final class VoiceCommandRouter {
    func route(transcript raw: String, isTypingMode: Bool = false) -> VoiceIntent {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .unknown(raw) }

        // Normalize: lowercase, remove common filler spaces.
        // We keep 'trimmed' for dictation content.
        let s = trimmed.lowercased().replacingOccurrences(of: " ", with: "")

        // --- Context-Aware Routing ---
        
        // 1. Force Command Mode: "指令", "Command"
        // e.g. "指令 点击" -> "点击" logic
        // We don't strip prefix yet for simplicity in matching, but we should probably bypass dictation check.
        let isForceCommand = s.hasPrefix("指令") || s.hasPrefix("command")

        // 2. Force Dictation Mode: "输入", "Type"
        // Already handled by existing check, but let's be explicit.
        let isForceDictation = s.hasPrefix("输入") || s.hasPrefix("Input") || s.hasPrefix("type") || s.hasPrefix("写")
        
        // 3. Typing Mode Default
        if isTypingMode && !isForceCommand {
            // In text field: default to dictation unless user said "Command..."
            // But we might want to check for "Input..." prefix to strip it?
            // Existing logic handles "Input..." stripping. 
            // Here, if just "Hello World", we return .dictation("Hello World")
            if !isForceDictation {
                return .dictation(trimmed)
            }
        }

        if s.contains("撤销") || s == "undo" || s.contains("撤回") {
            return .undo
        }
        if s.contains("粘贴") || s.contains("paste") {
            return .paste
        }
        if s.contains("锁定") || s.contains("lockairpods") || s.contains("lock") {
            return .lockConnection
        }
        if s.contains("解锁") || s.contains("unlockairpods") || s.contains("unlock") {
            return .unlockConnection
        }
        if s.contains("停止") || s.contains("暂停控制") || s == "stop" || s.contains("stop") {
            return .stopPointer
        }
        if s.contains("开始") || s.contains("继续") || s.contains("start") {
            return .startPointer
        }
        if s.contains("校准") || s.contains("居中") || s.contains("重置") || s.contains("recenter") {
            return .recenter
        }
        if s.contains("打开悬停") || s.contains("开启悬停") || s.contains("dwellon") {
            return .setDwell(true)
        }
        if s.contains("关闭悬停") || s.contains("关掉悬停") || s.contains("dwelloff") {
            return .setDwell(false)
        }

        if s.contains("右键") || s.contains("rightclick") || s.contains("context") {
            return .clickRight
        }
        if s.contains("双击") || s.contains("doubleclick") {
            return .doubleClick
        }
        if s.contains("点击") || s.contains("click") || s.contains("单击") {
            return .clickLeft
        }

        // Scroll / Drag
        if s.contains("向上") || s.contains("up") || s.contains("上滚") { return .scroll(0, -300) }
        if s.contains("向下") || s.contains("down") || s.contains("下滚") { return .scroll(0, 300) }
        if s.contains("到顶") || s.contains("top") { return .scrollToWeb("top") }
        if s.contains("到底") || s.contains("bottom") { return .scrollToWeb("bottom") }
        
        if s.contains("拖") || s.contains("drag") || s.contains("抓住") { return .dragStart }
        if s.contains("放") || s.contains("drop") || s.contains("松开") { return .dragEnd }

        if s.contains("写") || s.contains("input") || s.contains("type") || s.contains("输入") {
            // "type hello world" -> "hello world"
            let start = trimmed.index(trimmed.startIndex, offsetBy: 2)
            return .dictation(String(trimmed[start...]).trimmingCharacters(in: .whitespacesAndNewlines))
        }

        // --- Pinyin Fallback (for Homophones) ---
        // Solves "右键" (You Jian) vs "邮件" (You Jian)
        let py = trimmed.pinyin
        
        if py.contains("youjian") || py.contains("rightclick") { return .clickRight }
        if py.contains("zuo") && (py.contains("hua") || py.contains("yi")) { 
            // "左滑" (zuo hua), "左移" (zuo yi) -> maybe invalid? 
            // Let's stick to known commands.
        }
        
        // Check Pinyin for core commands if exact match failed
        if py.contains("dianji") || py.contains("danji") { return .clickLeft } // 点击/单击
        if py.contains("shuangji") { return .doubleClick } // 双击
        if py.contains("xiangshang") || py.contains("shanggun") { return .scroll(0, -300) } // 向上/上滚
        if py.contains("xiangxia") || py.contains("xiagun") { return .scroll(0, 300) } // 向下/下滚
        
        // Default fallback: treat as dictation for MVP (better UX than "unknown").
        return .dictation(trimmed)
    }
}

// MARK: - Pinyin Helper
extension String {
    var pinyin: String {
        // "你好" -> "nǐ hǎo" -> "ni hao" -> "nihao"
        return self
            .applyingTransform(.toLatin, reverse: false)?
            .applyingTransform(.stripDiacritics, reverse: false)?
            .lowercased()
            .replacingOccurrences(of: " ", with: "") ?? self.lowercased()
    }
}

protocol LLMProvider {
    func enhanceDictation(_ text: String) async throws -> String
    func interpretCommand(_ text: String) async throws -> VoiceIntent
}

// Minimal OpenAI-compatible provider (optional). For MVP we keep it behind a toggle.
final class OpenAICompatibleProvider: LLMProvider {
    struct Config {
        var endpoint: URL
        var apiKey: String
        var model: String
    }

    private let config: Config

    init(config: Config) {
        self.config = config
    }

    func enhanceDictation(_ text: String) async throws -> String {
        // Very small prompt; callers should handle timeouts and fallback.
        let prompt = "Add punctuation and fix obvious dictation errors. Keep meaning. Output only the corrected text.\\n\\nText:\\n\\(text)"
        return try await call(prompt: prompt)
    }

    func interpretCommand(_ text: String) async throws -> VoiceIntent {
        // For now, return unknown; command routing is handled locally for speed/reliability.
        _ = text
        return .unknown(text)
    }

    private func call(prompt: String) async throws -> String {
        var req = URLRequest(url: config.endpoint)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \\(config.apiKey)", forHTTPHeaderField: "Authorization")

        // OpenAI-compatible shape (chat/completions). We keep it generic.
        let body: [String: Any] = [
            "model": config.model,
            "messages": [
                ["role": "system", "content": "You are a helpful assistant."],
                ["role": "user", "content": prompt],
            ],
            "temperature": 0.2,
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, _) = try await URLSession.shared.data(for: req)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let choices = json?["choices"] as? [[String: Any]]
        let msg = choices?.first?["message"] as? [String: Any]
        let content = msg?["content"] as? String
        return content?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }
}

final class TextInjector {
    private(set) var lastInjectedAt: Date?

    func paste(_ text: String) {
        AutomationOutputs.shared.pasteText(text)
        lastInjectedAt = Date()
    }

    func type(_ text: String) {
        // [Fix] Use keystroke simulation instead of clipboard paste
        AutomationOutputs.shared.typeText(text)
        lastInjectedAt = Date()
    }

    func undoPasteIfRecent(maxAgeSeconds: TimeInterval = 20) {
        guard let at = lastInjectedAt, Date().timeIntervalSince(at) <= maxAgeSeconds else { return }
        AutomationOutputs.shared.undo()
    }
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
        // [Debug] Disable Gaze Wake to test Wake Word Timeout
        /*if isGazeWakeEnabled && HeadMotionManager.shared.isTracking && HeadMotionManager.shared.isLookingAtScreen {
            return true
        }*/

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
              let focusedElement else {
            return nil
        }
        let element = focusedElement as! AXUIElement
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

        // Target semantics: focus change immediately pauses and resets the ring (still visible).
        isMicProgressPausedForTarget = true
        HUDManager.shared.updateMicProgress(progress: 0.0, visible: true)
        setHUDOverride(
            mode: .command,
            message: activeLocale.identifier.starts(with: "zh")
                ? "检测到焦点切换，已暂停输入，需要重新触发"
                : "Focus changed. Input paused. Trigger again.",
            icon: "exclamationmark.triangle.fill",
            duration: 1.6
        )
        os_log("Mic progress paused due to focus change. lockedPID=%d currentPID=%d", log: log, type: .info, lockedPID, currentPID)
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
        guard let lockedPID = sessionTargetPID else { return true }
        guard let currentPID = currentFocusedPID() else { return false }
        let matches = currentPID == lockedPID
        if !matches && !didLogSessionTargetMismatch {
            os_log("Typing target changed. lockedPID=%d currentPID=%d. Skip injection for this session.",
                   log: log, type: .info, lockedPID, currentPID)
            showInputTargetChangedHUD()
            didLogSessionTargetMismatch = true
        }
        return matches
    }

    private func showInputTargetChangedHUD() {
        let message = activeLocale.identifier.starts(with: "zh")
            ? "检测到焦点切换，本次语音未继续输入"
            : "Focus changed. Dictation skipped for this utterance."
        setHUDOverride(mode: .command, message: message, icon: "exclamationmark.triangle.fill", duration: 1.6)
        HUDManager.shared.update(mode: .command, message: message, language: activeLocale.identifier, inputDeviceIcon: "exclamationmark.triangle.fill")
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
        
        if result == .success, let element = focusedElement {
            let axElement = element as! AXUIElement
            
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
        request.contextualStrings = ["点击", "双击", "向下", "向上", "右键", "Click", "Double Click", "Scroll Down", "Scroll Up", "Right Click"]

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
        
        // Type everything from screenTypedCount onward
        let newChars = currentChars[screenTypedCount...]
        let newText = String(newChars)
        AutomationOutputs.shared.typeText(newText)
        
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
        guard let lockedPID = job.targetPID else { return true }
        guard let currentPID = currentFocusedPID() else { return false }
        let matches = currentPID == lockedPID
        if !matches {
            let now = Date()
            if now.timeIntervalSince(lastFocusToastAt) > 1.2 {
                lastFocusToastAt = now
                showInputTargetChangedHUD()
            }
        }
        return matches
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
                    AutomationOutputs.shared.backspace(count: job.screenTypedCount)
                }
                if !text.isEmpty {
                    injector.type(text)
                }
                status = NSLocalizedString("speech.typed", comment: "")
            } else {
                injector.type(text)
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
            guard isSessionInputTargetValidForInjection() else {
                status = NSLocalizedString("speech.done", comment: "")
                return
            }
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
                    AutomationOutputs.shared.backspace(count: screenTypedCount)
                }
                
                if !text.isEmpty {
                    injector.type(text)
                }
                
                self.status = NSLocalizedString("speech.typed", comment: "")
            } else {
                os_log("[DEBUG] Not in typing mode, typing full text", log: log, type: .info)
                injector.type(text)
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

// MARK: - AirPods Detection Utility

extension Notification.Name {
    static let AirPodsStateChanged = Notification.Name("AirPodsStateChanged")
}

enum AirPodSide: String {
    case both
    case left
    case right
    case none
}

final class AirPodsDetector {
    static let shared = AirPodsDetector()
    
    private init() {
        startPolling()
    }
    
    private var pollingTimer: Timer?
    
    private func startPolling() {
        // Polling in background to keep UI icon responsive.
        pollingTimer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { [weak self] _ in
            _ = self?.currentSide()
        }
        // Ensure it runs even if UI is busy
        RunLoop.main.add(pollingTimer!, forMode: .common)
    }
    
    private var lastState: AirPodSide = .none
    private var pendingTarget: AirPodSide?
    private var pendingSince: Date = .distantPast
    private let startupAt: Date = Date()
    private var startupSawBothHint = false
    private var recentRegistrySamples: [(time: Date, side: AirPodSide)] = []
    private var recentPlcmSamples: [(time: Date, side: AirPodSide)] = []
    private var lastPlcmLine: String = ""
    private var lastPlcmPollAt: Date = .distantPast
    private let evidenceWindowShort: TimeInterval = 2.0
    private let evidenceWindowLong: TimeInterval = 2.0
    private let registryUnionWindow: TimeInterval = 0.85
    private let plcmPollInterval: TimeInterval = 0.6
    private let startupGuardWindow: TimeInterval = 4.0
    private let upToBothDelay: TimeInterval = 0.3
    private let bothToSingleDelay: TimeInterval = 0.6
    private let singleToNoneDelay: TimeInterval = 1.2
    private let sideSwitchDelay: TimeInterval = 0.15
    private let singleOverrideWindow: TimeInterval = 1.0
    private let singleSideLockWindow: TimeInterval = 0.7
    private let fastBothBlockWindow: TimeInterval = 1.0
    private var singleOverrideUntil: Date = .distantPast
    private var singleOverrideSide: AirPodSide = .none
    private var singleSideLockUntil: Date = .distantPast
    private var f1FastBlockedUntil: Date = .distantPast
    private let verboseDecisionLogs = false
    
    // Logger (Reverted to NSLog for stability)
    private func logDebug(_ message: String) {
        let lower = message.lowercased()
        let isTransition = message.hasPrefix("State Transition(")
        let isError = lower.contains("failed") || lower.contains("error")
        if !verboseDecisionLogs && !isTransition && !isError {
            return
        }
        let logStr = "\(Date()): \(message)\n"
        NSLog("[AirPodsDetector] %@", message)
        if let data = logStr.data(using: .utf8) {
            let tracePath = "/tmp/aether_decision_trace.txt"
            if !FileManager.default.fileExists(atPath: tracePath) {
                FileManager.default.createFile(atPath: tracePath, contents: nil)
            }
            if let fileHandle = FileHandle(forWritingAtPath: tracePath) {
                fileHandle.seekToEndOfFile()
                fileHandle.write(data)
                try? fileHandle.close()
            }
        }
    }
    
    // V9.0: Registry Presence Check
    // "Active/In-Ear" AirPods appear in IORegistry. "Idle/On-Desk" ones do not.
    private static func checkRegistryPresence(leftSerial: String?, rightSerial: String?) -> AirPodSide? {
        guard leftSerial != nil || rightSerial != nil else { return nil }
        
        let task = Process()
        task.launchPath = "/usr/sbin/ioreg"
        task.arguments = ["-k", "SerialNumber", "-l"] // Only list entries with SerialNumbers
        
        let pipe = Pipe()
        task.standardOutput = pipe
        
        do {
            try task.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            guard let output = String(data: data, encoding: .utf8) else { return nil }
            let normalizedOutput = output.lowercased()
            
            let isLeftPresent: Bool = {
                if let l = leftSerial?.lowercased(), normalizedOutput.contains(l) { return true }
                return false
            }()
            
            let isRightPresent: Bool = {
                if let r = rightSerial?.lowercased(), normalizedOutput.contains(r) { return true }
                return false
            }()
            
            // Definitive logic from explicit serial matches.
            if isLeftPresent && isRightPresent { return .both }
            if isLeftPresent { return .left }
            if isRightPresent { return .right }
            
            // Serial exists but neither side is present in IORegistry.
            return .none
            
        } catch {
            return nil
        }
    }

    private var isRefreshingFast = false
    private var isRefreshingSlow = false
    private let fastInterval: TimeInterval = 0.4
    private let slowInterval: TimeInterval = 30.0
    private var lastFastTime: Date = .distantPast
    private var lastSlowTime: Date = .distantPast
    
    // Cache
    private var cachedLeftSerial: String?
    private var cachedRightSerial: String?

    private static func normalizedSerial(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let cleaned = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
            .filter { $0.isLetter || $0.isNumber }
        return cleaned.isEmpty ? nil : cleaned
    }

    private func pruneRegistrySamples(now: Date) {
        recentRegistrySamples.removeAll { now.timeIntervalSince($0.time) > evidenceWindowLong }
        recentPlcmSamples.removeAll { now.timeIntervalSince($0.time) > evidenceWindowLong }
    }

    private func recordRegistrySample(_ side: AirPodSide, now: Date) {
        guard side == .left || side == .right || side == .both || side == .none else { return }
        recentRegistrySamples.append((time: now, side: side))
        pruneRegistrySamples(now: now)
    }

    private func recordPlcmSample(_ side: AirPodSide, now: Date) {
        guard side == .left || side == .right || side == .both else { return }
        recentPlcmSamples.append((time: now, side: side))
        pruneRegistrySamples(now: now)
    }

    private func count(_ samples: [(time: Date, side: AirPodSide)], within window: TimeInterval, side: AirPodSide, now: Date) -> Int {
        samples.reduce(0) { partial, sample in
            guard now.timeIntervalSince(sample.time) <= window else { return partial }
            return sample.side == side ? partial + 1 : partial
        }
    }

    private func has(_ samples: [(time: Date, side: AirPodSide)], within window: TimeInterval, side: AirPodSide, now: Date) -> Bool {
        samples.contains { now.timeIntervalSince($0.time) <= window && $0.side == side }
    }

    private func strongestSingleSide(now: Date) -> AirPodSide? {
        let leftScore =
            count(recentRegistrySamples, within: evidenceWindowShort, side: .left, now: now) +
            count(recentPlcmSamples, within: evidenceWindowShort, side: .left, now: now) * 2
        let rightScore =
            count(recentRegistrySamples, within: evidenceWindowShort, side: .right, now: now) +
            count(recentPlcmSamples, within: evidenceWindowShort, side: .right, now: now) * 2
        if leftScore == rightScore { return nil }
        return leftScore > rightScore ? .left : .right
    }

    private func deriveTargetState(now: Date) -> (state: AirPodSide, rule: String, bothEvidence: Bool) {
        pruneRegistrySamples(now: now)

        let regLeftShort = count(recentRegistrySamples, within: evidenceWindowShort, side: .left, now: now)
        let regRightShort = count(recentRegistrySamples, within: evidenceWindowShort, side: .right, now: now)
        let plcmLeftShort = count(recentPlcmSamples, within: evidenceWindowShort, side: .left, now: now)
        let plcmRightShort = count(recentPlcmSamples, within: evidenceWindowShort, side: .right, now: now)
        let hasRegLeftUnion = has(recentRegistrySamples, within: registryUnionWindow, side: .left, now: now)
        let hasRegRightUnion = has(recentRegistrySamples, within: registryUnionWindow, side: .right, now: now)
        let hasRegBothShort = has(recentRegistrySamples, within: evidenceWindowShort, side: .both, now: now)
        let regBothCountShort = count(recentRegistrySamples, within: evidenceWindowShort, side: .both, now: now)
        let plcmBothCountShort = count(recentPlcmSamples, within: evidenceWindowShort, side: .both, now: now)
        let plcmBothStrong = plcmBothCountShort >= 2
        let mixedBoth = plcmBothCountShort >= 1 && (hasRegBothShort || (hasRegLeftUnion && hasRegRightUnion))
        let registryBothStrong = regBothCountShort >= 2 || (regLeftShort >= 2 && regRightShort >= 2)
        let bothEvidence = plcmBothStrong || mixedBoth || registryBothStrong

        if now < singleOverrideUntil && (singleOverrideSide == .left || singleOverrideSide == .right) {
            let canBreakSingleOverride = plcmBothCountShort >= 2 || (plcmBothCountShort >= 1 && now >= f1FastBlockedUntil)
            if canBreakSingleOverride {
                singleOverrideUntil = .distantPast
                singleOverrideSide = .none
            } else {
                // R0 is allowed to keep same-side or move from none/both to single,
                // but side-to-side flips should come from explicit Plcm single evidence only.
                if (lastState == .left || lastState == .right) && singleOverrideSide != lastState {
                    return (lastState, "R0-side-flip-blocked", false)
                }
                return (singleOverrideSide, "R0-single-override", false)
            }
        }
        if bothEvidence {
            startupSawBothHint = true
            return (.both, "R1-both-evidence", true)
        }

        let leftSignal = regLeftShort >= 2 || plcmLeftShort >= 1
        let rightSignal = regRightShort >= 2 || plcmRightShort >= 1

        if leftSignal != rightSignal {
            let candidate: AirPodSide = leftSignal ? .left : .right
            if lastState == .both {
                let candidateStrength = candidate == .left
                    ? (regLeftShort + plcmLeftShort * 2)
                    : (regRightShort + plcmRightShort * 2)
                let oppositeStrength = candidate == .left
                    ? (regRightShort + plcmRightShort * 2)
                    : (regLeftShort + plcmLeftShort * 2)

                // When currently in BOTH, require stronger one-sided proof and no opposite-side freshness.
                if oppositeStrength > 0 {
                    return (.both, "R2c-hold-both-opposite-signal", false)
                }
                if candidateStrength < 4 {
                    return (.both, "R2d-hold-both-weak-single", false)
                }
            }
            return (candidate, "R2-single-evidence", false)
        }

        if let strong = strongestSingleSide(now: now), leftSignal || rightSignal {
            return (strong, "R2b-single-score", false)
        }

        let latestRegistryAt = recentRegistrySamples.last?.time ?? .distantPast
        let latestPlcmAt = recentPlcmSamples.last?.time ?? .distantPast
        let quietFor = min(now.timeIntervalSince(latestRegistryAt), now.timeIntervalSince(latestPlcmAt))
        if quietFor >= singleToNoneDelay {
            return (.none, "R3-quiet-none", false)
        }

        return (lastState, "R4-hold", false)
    }

    private enum PlcmSample {
        case both(line: String)
        case single(side: AirPodSide, line: String)
    }

    private static func fetchLatestPlcmSample() -> PlcmSample? {
        let task = Process()
        task.launchPath = "/usr/bin/log"
        task.arguments = [
            "show",
            "--last", "12s",
            "--style", "compact",
            "--predicate", "process == \"bluetoothd\" AND eventMessage CONTAINS \"Plcm\""
        ]

        let pipe = Pipe()
        task.standardOutput = pipe
        do {
            try task.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            guard let output = String(data: data, encoding: .utf8), !output.isEmpty else { return nil }
            let lines = output.components(separatedBy: .newlines)
            for line in lines.reversed() {
                let lower = line.lowercased()
                guard lower.contains("plcm") else { continue }
                if lower.contains("p inear") && lower.contains("s inear") {
                    return .both(line: line)
                }
                if lower.contains("p inear") || lower.contains("s inear") {
                    if lower.contains("prim left") {
                        return .single(side: .left, line: line)
                    }
                    if lower.contains("prim right") {
                        return .single(side: .right, line: line)
                    }
                }
            }
        } catch {
            return nil
        }
        return nil
    }

    private func updateBothStateFromBluetoothLog() {
        let now = Date()
        if now.timeIntervalSince(lastPlcmPollAt) < plcmPollInterval { return }
        lastPlcmPollAt = now

        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self = self else { return }
            let sample = Self.fetchLatestPlcmSample()
            DispatchQueue.main.async {
                guard let sample else { return }
                switch sample {
                case .both(let line):
                    guard line != self.lastPlcmLine else { return }
                    self.lastPlcmLine = line
                    let now = Date()
                    self.recordPlcmSample(.both, now: now)
                    self.observeState(.both, source: "bluetoothd-plcm", authoritative: true)
                case .single(let side, let line):
                    guard line != self.lastPlcmLine else { return }
                    self.lastPlcmLine = line
                    let now = Date()
                    self.recordPlcmSample(side, now: now)
                    self.singleOverrideSide = side
                    self.singleOverrideUntil = now.addingTimeInterval(self.singleOverrideWindow)
                    self.observeState(side, source: "bluetoothd-plcm-single", authoritative: true)
                }
            }
        }
    }
    
    // Non-blocking accessor
    func currentSide() -> AirPodSide {
        let now = Date()
        
        // 1. Trigger Fast Check (ioreg)
        if !isRefreshingFast && now.timeIntervalSince(lastFastTime) > fastInterval {
            refreshFast()
        }
        
        // 2. Trigger Slow Check (system_profiler)
        if !isRefreshingSlow && now.timeIntervalSince(lastSlowTime) > slowInterval {
            refreshSlow()
        }
        
        return lastState
    }
    
    private func refreshFast() {
        guard !isRefreshingFast else { return }
        isRefreshingFast = true
        
        // Use cached serials for the fast check
        let lSer = cachedLeftSerial
        let rSer = cachedRightSerial
        
        DispatchQueue.global(qos: .userInteractive).async { [weak self] in
            guard let self = self else { return }
            let registrySide = Self.checkRegistryPresence(leftSerial: lSer, rightSerial: rSer)

            DispatchQueue.main.async {
                if let registrySide {
                    self.recordRegistrySample(registrySide, now: Date())
                    self.observeState(registrySide, source: "registry", authoritative: false)
                }
                self.updateBothStateFromBluetoothLog()
                self.lastFastTime = Date()
                self.isRefreshingFast = false
            }
        }
    }
    
    private func refreshSlow() {
        guard !isRefreshingSlow else { return }
        isRefreshingSlow = true
        let cachedLeft = cachedLeftSerial
        let cachedRight = cachedRightSerial
        
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self = self else { return }
            var leftSerial: String?
            var rightSerial: String?
            var hasLeftBattery = false
            var hasRightBattery = false
            
            let profilerTask = Process()
            profilerTask.launchPath = "/usr/sbin/system_profiler"
            profilerTask.arguments = ["SPBluetoothDataType"]
            profilerTask.environment = [
                "LANG": "en_US.UTF-8",
                "LC_ALL": "en_US.UTF-8"
            ]
            let profilerPipe = Pipe()
            profilerTask.standardOutput = profilerPipe
            
            do {
                try profilerTask.run()
                let data = profilerPipe.fileHandleForReading.readDataToEndOfFile()
                if let output = String(data: data, encoding: .utf8) {
                    let sections = output.components(separatedBy: "Connected:")
                    for section in sections {
                        let lines = section.components(separatedBy: .newlines)
                        for line in lines {
                            if line.contains("Serial Number (Left):") {
                                leftSerial = Self.normalizedSerial(line.components(separatedBy: ":").last)
                            }
                            if line.contains("Serial Number (Right):") {
                                rightSerial = Self.normalizedSerial(line.components(separatedBy: ":").last)
                            }
                            if line.contains("Left Battery Level:") { hasLeftBattery = true }
                            if line.contains("Right Battery Level:") { hasRightBattery = true }
                        }
                    }
                }
                let mergedLeft = leftSerial ?? cachedLeft
                let mergedRight = rightSerial ?? cachedRight
                let registrySide = Self.checkRegistryPresence(leftSerial: mergedLeft, rightSerial: mergedRight)
                
                // Update Cache & State based on battery if registry is ambiguous
                DispatchQueue.main.async {
                    if let l = leftSerial { self.cachedLeftSerial = l }
                    if let r = rightSerial { self.cachedRightSerial = r }
                    self.logDebug("Profiler Cache Updated: L=\(self.cachedLeftSerial ?? "nil"), R=\(self.cachedRightSerial ?? "nil"), hasL=\(hasLeftBattery), hasR=\(hasRightBattery)")
                    self.updateBothStateFromBluetoothLog()

                    // Re-check registry immediately after refreshing serial cache.
                    if let registrySide {
                        self.recordRegistrySample(registrySide, now: Date())
                        self.observeState(registrySide, source: "registry-after-profiler", authoritative: false)
                    } else {
                        // Battery fields are weak signals: only trust one-sided hints.
                        if hasLeftBattery != hasRightBattery {
                            self.observeState(hasLeftBattery ? .left : .right, source: "battery-hint", authoritative: false)
                        } else if !hasLeftBattery && !hasRightBattery {
                            self.observeState(.none, source: "battery-empty", authoritative: false)
                        } else {
                            self.logDebug("Profiler battery state ambiguous; keeping last state")
                        }
                    }
                    self.lastSlowTime = Date()
                    self.isRefreshingSlow = false
                }
            } catch {
                DispatchQueue.main.async {
                    self.logDebug("Slow Profiler Failed")
                    self.lastSlowTime = Date()
                    self.isRefreshingSlow = false
                }
                return
            }
        }
    }
            
    
    private func observeState(_ observedState: AirPodSide, source: String, authoritative: Bool) {
        DispatchQueue.main.async {
            let now = Date()
            // Fast lane: authoritative Plcm BOTH should reflect almost immediately on HUD.
            if authoritative && source == "bluetoothd-plcm" && self.lastState != .both {
                let plcmBothStrongNow = self.count(self.recentPlcmSamples, within: 1.0, side: .both, now: now) >= 2
                if now < self.f1FastBlockedUntil && !plcmBothStrongNow {
                    self.logDebug("Rule F1-fast-plcm-both blocked until \(self.f1FastBlockedUntil)")
                    return
                }
                self.singleSideLockUntil = .distantPast
                self.applyState(.both, source: "\(source)|F1-fast")
                return
            }

            // Fast lane: authoritative Plcm single should win when BOTH is no longer fresh.
            if authoritative &&
                source == "bluetoothd-plcm-single" &&
                (observedState == .left || observedState == .right) {
                let recentPlcmBoth = self.has(self.recentPlcmSamples, within: 0.25, side: .both, now: now)
                let single: AirPodSide = observedState

                // From BOTH -> SINGLE: small guard, but do not get stuck in BOTH.
                if self.lastState == .both && !recentPlcmBoth {
                    if self.pendingTarget != single {
                        self.pendingTarget = single
                        self.pendingSince = now
                        self.logDebug("Pending \(single.rawValue) via F3-both-to-single-plcm wait=0.20s")
                        return
                    }
                    if now.timeIntervalSince(self.pendingSince) >= 0.20 {
                        self.singleOverrideSide = single
                        self.singleOverrideUntil = now.addingTimeInterval(self.singleOverrideWindow)
                        self.singleSideLockUntil = now.addingTimeInterval(self.singleSideLockWindow)
                        self.f1FastBlockedUntil = now.addingTimeInterval(self.fastBothBlockWindow)
                        self.applyState(single, source: "\(source)|F3-fast")
                        return
                    }
                }

                // From NONE -> SINGLE: keep tiny guard.
                if self.lastState == .none {
                    if self.pendingTarget != single {
                        self.pendingTarget = single
                        self.pendingSince = now
                        self.logDebug("Pending \(single.rawValue) via F2-fast-plcm-single wait=0.25s")
                        return
                    }
                    if now.timeIntervalSince(self.pendingSince) >= 0.20 {
                        self.singleSideLockUntil = now.addingTimeInterval(self.singleSideLockWindow)
                        self.f1FastBlockedUntil = now.addingTimeInterval(self.fastBothBlockWindow)
                        self.applyState(single, source: "\(source)|F2-fast")
                        return
                    }
                }
            }

            // Fallback using fused windows and hysteresis.
            let resolved = self.deriveTargetState(now: now)
            let target = resolved.state

            if now.timeIntervalSince(self.startupAt) <= self.startupGuardWindow &&
                (target == .left || target == .right) &&
                self.startupSawBothHint {
                self.logDebug("Rule S0-startup-guard hold single=\(target.rawValue) src=\(source)")
                return
            }

            if target == self.lastState {
                self.pendingTarget = nil
                return
            }

            if now < self.singleSideLockUntil &&
                (self.lastState == .left || self.lastState == .right) &&
                (target == .left || target == .right) &&
                target != self.lastState {
                let allowAuthoritativeFlip = authoritative &&
                    source == "bluetoothd-plcm-single" &&
                    observedState == target
                if !allowAuthoritativeFlip {
                    self.logDebug("Rule L1-side-lock hold \(self.lastState.rawValue), reject \(target.rawValue) from \(source)")
                    return
                }
            }

            var requiredDelay = self.sideSwitchDelay
            if target == .both {
                requiredDelay = self.upToBothDelay
            } else if self.lastState == .both && (target == .left || target == .right) {
                requiredDelay = self.bothToSingleDelay
            } else if target == .none {
                requiredDelay = self.singleToNoneDelay
            } else if self.lastState == .none && (target == .left || target == .right) {
                requiredDelay = authoritative ? 0.4 : 0.6
            }

            if self.pendingTarget != target {
                self.pendingTarget = target
                self.pendingSince = now
                self.logDebug("Pending \(target.rawValue) via \(resolved.rule) from \(source), wait=\(String(format: "%.1f", requiredDelay))s")
                return
            }
            if now.timeIntervalSince(self.pendingSince) < requiredDelay {
                return
            }

            self.applyState(target, source: "\(source)|\(resolved.rule)")
        }
    }
    private func applyState(_ newState: AirPodSide, source: String) {
        DispatchQueue.main.async {
            if self.lastState != newState {
                self.logDebug("State Transition(\(source)): \(self.lastState) -> \(newState)")
                self.lastState = newState
                self.pendingTarget = nil
                if newState == .left || newState == .right {
                    self.singleSideLockUntil = Date().addingTimeInterval(self.singleSideLockWindow)
                    self.f1FastBlockedUntil = Date().addingTimeInterval(self.fastBothBlockWindow)
                } else if newState == .both {
                    self.singleSideLockUntil = .distantPast
                }
                // Proactively notify the system to refresh UI
                NotificationCenter.default.post(name: .AirPodsStateChanged, object: newState)
            }
        }
    }
}
