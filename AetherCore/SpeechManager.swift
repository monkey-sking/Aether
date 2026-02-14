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
    @Published var status: String = "Idle"
    @Published var lastTranscript: String = ""
    @Published var lastError: String = ""
    
    // Microphone Management
    @Published var availableInputDevices: [AudioInputDevice] = []
    @Published var selectedInputDeviceID: AudioDeviceID = 0 { // 0 = System Default
        didSet {
            // Only restart if changed and engine is running
            if oldValue != selectedInputDeviceID {
                restartEngineForNewDevice()
            }
        }
    }
    
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

        let airpodSide = AirPodsDetector.shared.currentSide()
        
        // [Priority 2] AirPods in-ear detection
        if airpodSide != .none {
            let modelDevice = availableInputDevices.first(where: { $0.iconName.contains("airpod") })
            let baseIcon = modelDevice?.iconName ?? "airpodspro"
            
            switch airpodSide {
            case .left:
                if baseIcon == "airpodsmax" { return "airpodsmax" }
                return "airpod.gen3.left"
            case .right:
                if baseIcon == "airpodsmax" { return "airpodsmax" }
                return "airpod.gen3.right"
            case .both:
                if baseIcon == "airpodsmax" { return "airpodsmax" }
                return "airpod.gen3"
            case .none: break
            }
        }
        
        // [Priority 3] Current Selected/Default Audio Device
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
            return matchedDevice.iconName
        }
        
        return AudioInputDevice.defaultSystem.iconName
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
    private var wasAwake: Bool = false // Tracks previous wake state for UI updates
    private var audioRingBuffer: [AVAudioPCMBuffer] = []
    private let ringBufferCapacity = 10 // ~0.5s at 1024 frames/buffer

    private var audioEngine: AVAudioEngine?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var finalizationWorkItem: DispatchWorkItem? // For cancellable delayed finalization
    
    // Recognizer (Updated on locale change)
    private var recognizer: SFSpeechRecognizer? = SFSpeechRecognizer(locale: Locale(identifier: "zh-CN"))

    private var continuousTimer: Timer?
    private var isStopping: Bool = false // Prevent HUD flicker during trailing audio capture
    private var lastChangeAt: Date?
    private var lastStableText: String = ""
    private var sessionGeneration: Int = 0 
    private var sessionTypingMode: Bool = false
    private var cachedTypingMode: Bool = false
    private var lastTypingCheckAt: Date = .distantPast
    @Published var lastWakeTime: Date? // For context-aware wake window & UI feedback
    private var cancellables = Set<AnyCancellable>()

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

    private func refreshContinuousHUD(isDictating: Bool = false) {
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
                inputDeviceIcon: currentInputDeviceIcon
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

        HUDManager.shared.update(mode: mode, message: message, language: activeLocale.identifier, inputDeviceIcon: currentInputDeviceIcon)
    }
    
    private func showPTTUnavailableHUD() {
        let message = activeLocale.identifier.starts(with: "zh") ? "未检测到麦克风" : "No Microphone Detected"
        HUDManager.shared.update(
            mode: .listening,
            message: message,
            language: activeLocale.identifier,
            inputDeviceIcon: currentInputDeviceIcon
        )
    }

    private func scheduleContinuousRecovery(delay: TimeInterval = 0.25) {
        guard isAlwaysListeningEnabled else { return }
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
        hud.update(mode: hud.state.mode, message: hud.state.message, language: activeLocale.identifier, inputDeviceIcon: currentInputDeviceIcon)
        
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
            } else {
                showPTTUnavailableHUD()
            }
            return
        }

        sessionGeneration += 1
        let currentGeneration = sessionGeneration
        
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

        // [Stability] Reset Failsafe Timer (Stops recording after 60s max)
        failsafeTimer?.invalidate()
        failsafeTimer = Timer.scheduledTimer(withTimeInterval: 60.0, repeats: false) { [weak self] _ in
            os_log("Failsafe: Stopping session after 60s timeout.", log: GlobalLogger.speech, type: .error)
            Task { @MainActor in
                guard let self = self else { return }
                self.stopAndFinalize()
                self.scheduleContinuousRecovery()
            }
        }

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
                                }
                                
                                // Drop the phrase + standard space/punctuation if present
                                let dropCount = phrase.count
                                let suffix = text.dropFirst(dropCount).trimmingCharacters(in: .whitespacesAndNewlines)
                                text = suffix
                                break // Only strip one prefix
                            }
                        }
                    }

                    self.lastTranscript = text
                    self.lastChangeAt = Date()
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
                    if self.sessionTypingMode {
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
                        self.stopAndFinalize()
                        // If continuous mode is on, logic elsewhere (e.g. stopContinuous/startContinuous or manual restart) 
                        // might need to be triggered. 
                        // Actually, `stopAndFinalize` stops the engine.
                        // In `startContinuous`, we use a timer to restart? No, we use `continuousTimer` for TICKs.
                        // But if the engine errors out, we need to restart it if `isAlwaysListeningEnabled`.
                        
                        if self.isAlwaysListeningEnabled {
                             DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                 // Auto-restart for continuous listening
                                 self.startOnce()
                             }
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
        
        // Keep voice processing OFF by default to avoid ducking/volume attenuation
        // in other apps while Aether is active.
        if #available(macOS 10.15, *), shouldUseVoiceProcessing() {
            do {
                try inputNode.setVoiceProcessingEnabled(true)
                os_log("Voice Processing IO enabled (explicit).", log: log, type: .info)
            } catch {
                os_log("Failed to enable Voice Processing IO: %{public}@", log: log, type: .error, error.localizedDescription)
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
             
             if Int.random(in: 0...100) == 0 {
                  os_log("Audio RMS: %.4f (scaled)", log: self.log, type: .debug, rms)
             }
             // 4. Send to recognition engine
             self.recognitionRequest?.append(monoBuffer)
             
             // 5. Update Ring Buffer (Main Thread)
             DispatchQueue.main.async { [weak self] in
                 guard let self = self else { return }
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
    
    private func restartEngineForNewDevice() {
        os_log("Restarting engine for new device...", log: log, type: .default)
        stopAndFinalize()
        // Wait briefly for tear down
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
             if self.isAlwaysListeningEnabled {
                 self.startOnce()
             }
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

    func stopAndFinalize() {
        if isAlwaysListeningEnabled {
            refreshContinuousHUD(isDictating: false)
        } else {
            HUDManager.shared.hide()
        }
        guard let task = recognitionTask else {
            // If there is no active task, we still must clear transient HUD-driving state.
            resetHUDTransientState()
            if isAlwaysListeningEnabled {
                refreshContinuousHUD()
            } else {
                HUDManager.shared.hide()
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
                HUDManager.shared.hide()
            } else {
                self.refreshContinuousHUD() // Force refresh to Standby mode
            }
        }
        
        finalizationWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: workItem)
    }
    
    // Explicit teardown if needed (e.g. app quit)
    func teardownEngine() {
        isStopping = false
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
                        inputDeviceIcon: self.currentInputDeviceIcon
                    )
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
        
        // [Fix] DON'T clear lastStreamedText here! handleTranscript needs it for differential sync.
        // It will be cleared at the START of the next session in startOnce().
        
        // Engine NOT cleared
    }
    
    private func resetHUDTransientState() {
        isStopping = false
        isDictating = false
        sessionTypingMode = false
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
        
        handleIntent(intent)
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
        
        if case .dictation(let text) = intent, isLLMEnhancementEnabled, let llmProvider {
            Task {
                do {
                    let enhanced = try await llmProvider.enhanceDictation(text)
                    await MainActor.run {
                        self.injector.type(enhanced.isEmpty ? text : enhanced)
                        self.status = "Typed"
                    }
                } catch {
                    await MainActor.run {
                        self.injector.type(text)
                        self.status = "Typed (No LLM)"
                    }
                }
            }
            return
        }

        switch intent {
        case .undo:
            injector.undoPasteIfRecent()
            status = NSLocalizedString("speech.undo", comment: "")
        case .paste:
            AutomationOutputs.shared.pasteFromClipboard()
            status = "Pasted (Cmd+V)"
        case .dictation(let text):
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
        // Polling every 2 seconds in background
        pollingTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            _ = self?.currentSide()
        }
        // Ensure it runs even if UI is busy
        RunLoop.main.add(pollingTimer!, forMode: .common)
    }
    
    private var lastState: AirPodSide = .none
    private var lastStateTime: Date = .distantPast
    private let debounceInterval: TimeInterval = 0.5
    
    // Logger (Reverted to NSLog for stability)
    private func logDebug(_ message: String) {
        let logStr = "\(Date()): \(message)\n"
        NSLog("[AirPodsDetector] %@", message)
        if let data = logStr.data(using: .utf8) {
            if let fileHandle = FileHandle(forWritingAtPath: "/tmp/aether_decision_trace.txt") {
                fileHandle.seekToEndOfFile()
                fileHandle.write(data)
                try? fileHandle.close()
            } else {
                try? logStr.write(to: URL(fileURLWithPath: "/tmp/ioreg_trace.txt"), atomically: true, encoding: .utf8)
            }
        }
    }
    
    // V9.0: Registry Presence Check
    // "Active/In-Ear" AirPods appear in IORegistry. "Idle/On-Desk" ones do not.
    private func checkRegistryPresence(leftSerial: String?, rightSerial: String?) -> AirPodSide? {
        self.logDebug("Registry Check Start: L_Serial=\(leftSerial ?? "nil"), R_Serial=\(rightSerial ?? "nil")")
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
            
            let isLeftPresent: Bool = {
                if let l = leftSerial, output.contains(l) { return true }
                return false
            }()
            
            let isRightPresent: Bool = {
                if let r = rightSerial, output.contains(r) { return true }
                return false
            }()
            
            self.logDebug("Registry Check: OutputLen=\(output.count). L_Serial=\(leftSerial ?? "?") Found=\(isLeftPresent). R_Serial=\(rightSerial ?? "?") Found=\(isRightPresent)")
            
            // Definitive Logic:
            if isLeftPresent && isRightPresent { return .both } // [Fix] Priority check for Both
            if isLeftPresent { return .left }
            if isRightPresent { return .right }
            
            // If neither present, it might be a weird state, fall down to RSSI
            return nil
            
        } catch {
            return nil
        }
    }

    private var isRefreshingFast = false
    private var isRefreshingSlow = false
    private let fastInterval: TimeInterval = 0.5
    private let slowInterval: TimeInterval = 10.0
    private var lastFastTime: Date = .distantPast
    private var lastSlowTime: Date = .distantPast
    
    // Cache
    private var cachedLeftSerial: String?
    private var cachedRightSerial: String?
    
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
            
            if let registrySide = self.checkRegistryPresence(leftSerial: lSer, rightSerial: rSer) {
                // If registry is definitive, use it (Fast Path)
                self.updateState(registrySide)
            }
            
            DispatchQueue.main.async {
                self.lastFastTime = Date()
                self.isRefreshingFast = false
            }
        }
    }
    
    private func refreshSlow() {
        guard !isRefreshingSlow else { return }
        isRefreshingSlow = true
        
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self = self else { return }
            self.logDebug("Starting Slow Background Metadata Refresh...")
            
            var leftSerial: String?
            var rightSerial: String?
            var hasLeftBattery = false
            var hasRightBattery = false
            
            let profilerTask = Process()
            profilerTask.launchPath = "/usr/sbin/system_profiler"
            profilerTask.arguments = ["SPBluetoothDataType"]
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
                                leftSerial = line.components(separatedBy: ":").last?.trimmingCharacters(in: .whitespaces)
                            }
                            if line.contains("Serial Number (Right):") {
                                rightSerial = line.components(separatedBy: ":").last?.trimmingCharacters(in: .whitespaces)
                            }
                            if line.contains("Left Battery Level:") { hasLeftBattery = true }
                            if line.contains("Right Battery Level:") { hasRightBattery = true }
                        }
                    }
                }
                
                // Update Cache & State based on battery if registry is ambiguous
                if let l = leftSerial { self.cachedLeftSerial = l }
                if let r = rightSerial { self.cachedRightSerial = r }
                
                let inferredSide: AirPodSide
                if hasLeftBattery && hasRightBattery {
                    inferredSide = .both
                } else if hasLeftBattery {
                    inferredSide = .left
                } else if hasRightBattery {
                    inferredSide = .right
                } else {
                    inferredSide = .none
                }
                self.updateState(inferredSide)
            } catch {
                self.logDebug("Slow Profiler Failed")
            }
            
            DispatchQueue.main.async {
                self.lastSlowTime = Date()
                self.isRefreshingSlow = false
            }
        }
    }
            
    
    private func updateState(_ newState: AirPodSide) {
        DispatchQueue.main.async {
            if self.lastState != newState {
                self.logDebug("State Transition: \(self.lastState) -> \(newState)")
                self.lastState = newState
                self.lastStateTime = Date()
                // Proactively notify the system to refresh UI
                NotificationCenter.default.post(name: .AirPodsStateChanged, object: newState)
            }
        }
    }
    
}
