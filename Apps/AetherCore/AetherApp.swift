import SwiftUI
import SystemExtensions
import Combine
import AVFoundation
import Speech
import Carbon
import UniformTypeIdentifiers

let kAetherDriverBundleID = "com.7fei.Aether.AetherDriver"

enum OnboardingStep: Equatable {
    case accessibility
    case microphone
    case speech
    case done
}

@MainActor
final class DriverService: ObservableObject {
    @Published private(set) var state: SystemExtensionActivationState = .idle

    private let manager: SystemExtensionManager
    private var cancellables = Set<AnyCancellable>()

    init(manager: SystemExtensionManager = .shared) {
        self.manager = manager

        manager.$state
            .receive(on: DispatchQueue.main)
            .assign(to: &$state)
    }

    var statusText: String {
        manager.statusText
    }

    func activate(identifier: String) {
        manager.activate(identifier: identifier)
    }
}

@MainActor
final class MotionService: ObservableObject {
    @Published private(set) var isTracking: Bool = false
    @Published private(set) var attitudeText: String = "No Data"
    @Published private(set) var calibrationStatus: String = "Normal"

    private let manager: HeadMotionManager
    private var cancellables = Set<AnyCancellable>()

    init(manager: HeadMotionManager = .shared) {
        self.manager = manager

        manager.$isTracking
            .receive(on: DispatchQueue.main)
            .assign(to: &$isTracking)

        manager.$attitudeText
            .receive(on: DispatchQueue.main)
            .assign(to: &$attitudeText)

        manager.$calibrationStatus
            .receive(on: DispatchQueue.main)
            .assign(to: &$calibrationStatus)
            
        manager.onError = { [weak self] errorMsg in
            DispatchQueue.main.async {
                self?.presentError(errorMsg)
            }
        }
    }
    
    @MainActor
    private func presentError(_ message: String) {
        let alert = NSAlert()
        alert.messageText = String(localized: "Motion Tracking Failed")
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    func setGlobalHotkeysEnabled(_ enabled: Bool) {
        manager.setGlobalHotkeysEnabled(enabled)
    }

    func recoverFromAccessibilityTrustChange(_ trusted: Bool, source: String = "permissions-refresh") {
        manager.recoverFromAccessibilityTrustChange(trusted: trusted, source: source)
    }

    func startTracking() { manager.startTracking() }
    func stopTracking() { manager.stopTracking() }
    func finishCalibration() { manager.finishCalibration() }
    func recenter() { manager.recenter() }

    func clickLeft() { manager.clickLeft() }
    func clickRight() { manager.clickRight() }
    func doubleClick() { manager.doubleClick() }
    
    func scroll(dx: Int, dy: Int) { manager.scroll(dx: dx, dy: dy) }
    func scrollToTop() { manager.scrollToTop() }
    func scrollToBottom() { manager.scrollToBottom() }
    func dragStart() { manager.dragStart() }
    func dragEnd() { manager.dragEnd() }
}

@MainActor
final class VoiceService: ObservableObject {
    @Published private(set) var status: String = "Idle"
    @Published private(set) var lastTranscript: String = ""
    @Published private(set) var lastError: String = ""
    @Published private(set) var lastWakeTime: Date?
    
    @Published var isAlwaysListeningEnabled: Bool = false
    @Published var isDirectCommandEnabled: Bool = false
    @Published var isPTTEnabled: Bool = true
    @Published var isWakeWordEnabled: Bool = true
    @Published var isGazeWakeEnabled: Bool = true
    @Published var isAutoPunctuationEnabled: Bool = true
    @Published var availableInputDevices: [AudioInputDevice] = []
    @Published var selectedInputDeviceID: AudioDeviceID = 0 {
        didSet {
            manager.selectedInputDeviceID = selectedInputDeviceID
        }
    }

    var onIntent: ((VoiceIntent) -> Void)? {
        get { manager.onIntent }
        set { manager.onIntent = newValue }
    }
    
    var explicitLocaleIdentifier: String? {
        get { manager.explicitLocaleIdentifier }
        set {
            objectWillChange.send()
            manager.explicitLocaleIdentifier = newValue
        }
    }

    private let manager: SpeechManager
    private var cancellables = Set<AnyCancellable>()

    convenience init() {
        self.init(manager: SpeechManager())
    }

    init(manager: SpeechManager) {
        self.manager = manager

        manager.$status
            .receive(on: DispatchQueue.main)
            .assign(to: &$status)

        manager.$lastTranscript
            .receive(on: DispatchQueue.main)
            .assign(to: &$lastTranscript)

        manager.$lastError
            .receive(on: DispatchQueue.main)
            .assign(to: &$lastError)
            
        manager.$lastWakeTime
            .receive(on: DispatchQueue.main)
            .assign(to: &$lastWakeTime)
            
        manager.$isAlwaysListeningEnabled
            .receive(on: DispatchQueue.main)
            .assign(to: &$isAlwaysListeningEnabled)
            
        manager.$isWakeWordEnabled
            .receive(on: DispatchQueue.main)
            .assign(to: &$isWakeWordEnabled)
            
        manager.$isGazeWakeEnabled
            .receive(on: DispatchQueue.main)
            .assign(to: &$isGazeWakeEnabled)
            
        manager.$availableInputDevices
            .receive(on: DispatchQueue.main)
            .assign(to: &$availableInputDevices)
            
        manager.$selectedInputDeviceID
            .receive(on: DispatchQueue.main)
            .assign(to: &$selectedInputDeviceID)
            
        manager.$isDirectCommandEnabled
            .receive(on: DispatchQueue.main)
            .assign(to: &$isDirectCommandEnabled)
            
        manager.$isAutoPunctuationEnabled
            .receive(on: DispatchQueue.main)
            .assign(to: &$isAutoPunctuationEnabled)
            
        manager.$isPTTEnabled
            .receive(on: DispatchQueue.main)
            .assign(to: &$isPTTEnabled)
    }

    func refreshInputDevices() {
        manager.refreshInputDevices()
    }

    func setAlwaysListeningEnabled(_ enabled: Bool) {
        manager.isAlwaysListeningEnabled = enabled
    }
    
    func setDirectCommandEnabled(_ enabled: Bool) {
        manager.isDirectCommandEnabled = enabled
    }
    
    func setPTTEnabled(_ enabled: Bool) {
        manager.isPTTEnabled = enabled
    }

    func setWakeWordEnabled(_ enabled: Bool) {
        manager.isWakeWordEnabled = enabled
    }

    func setGazeWakeEnabled(_ enabled: Bool) {
        manager.isGazeWakeEnabled = enabled
    }

    func setAutoPunctuationEnabled(_ enabled: Bool) {
        manager.isAutoPunctuationEnabled = enabled
    }


    func setLLMEnhancementEnabled(_ enabled: Bool) {
        manager.isLLMEnhancementEnabled = enabled
    }

    func setVoiceCommandOverrides(_ overrides: [VoiceCommandOverrideConfig]) {
        manager.setVoiceCommandOverrides(overrides)
    }

    func setVoiceLanguageTermsOverrides(_ overrides: [VoiceLanguageTermsOverrideConfig]) {
        manager.setVoiceLanguageTermsOverrides(overrides)
    }

    func setAccessibilityTrusted(_ trusted: Bool) {
        manager.updateAccessibilityTrusted(trusted)
    }

    func undoLastInjection() {
        manager.undoLastInjection()
    }
}

@MainActor
final class PermissionsService: ObservableObject {
    @Published private(set) var accessibilityTrusted: Bool = false
    @Published private(set) var microphoneAuthorized: Bool = false
    @Published private(set) var speechAuthorized: Bool = false

    private let manager: PermissionsManager
    private var cancellables = Set<AnyCancellable>()

    convenience init() {
        self.init(manager: PermissionsManager())
    }

    init(manager: PermissionsManager) {
        self.manager = manager

        manager.$accessibilityTrusted
            .receive(on: DispatchQueue.main)
            .assign(to: &$accessibilityTrusted)

        manager.$microphoneAuthorized
            .receive(on: DispatchQueue.main)
            .assign(to: &$microphoneAuthorized)

        manager.$speechAuthorized
            .receive(on: DispatchQueue.main)
            .assign(to: &$speechAuthorized)
    }

    func refresh() { manager.refresh() }
    @discardableResult
    func requestAccessibility() -> Bool { manager.requestAccessibility() }
    func requestMicrophone() { manager.requestMicrophone() }
    func requestSpeech() { manager.requestSpeech() }
    func openAccessibilityPrivacyPane() { manager.openAccessibilityPrivacyPane() }
    func openMicrophonePrivacyPane() { manager.openMicrophonePrivacyPane() }
    func openSpeechPrivacyPane() { manager.openSpeechPrivacyPane() }
}

@MainActor
class AppState: ObservableObject {
    struct VoiceLexiconBackup: Codable {
        var version: Int = 1
        var exportedAt: Date = Date()
        var commandOverrides: [VoiceCommandOverrideConfig]
        var languageTermsOverrides: [VoiceLanguageTermsOverrideConfig]
    }

    struct SpeechTermGroupConfig: Codable, Identifiable, Equatable {
        var id: String
        var name: String
        var isEnabled: Bool
        var applyToAllApps: Bool
        var appList: String
        var rulesText: String

        init(
            id: String = UUID().uuidString,
            name: String,
            isEnabled: Bool = true,
            applyToAllApps: Bool = false,
            appList: String = "",
            rulesText: String = ""
        ) {
            self.id = id
            self.name = name
            self.isEnabled = isEnabled
            self.applyToAllApps = applyToAllApps
            self.appList = appList
            self.rulesText = rulesText
        }
    }

    private static let speechTermGroupsStorageKey = "speechTermGroupsV2"
    private static let voiceCommandOverridesStorageKey = "voiceCommandOverridesV1"
    private static let voiceLanguageTermsOverridesStorageKey = "voiceLanguageTermsOverridesV1"

    private static func defaultSpeechTermGroups() -> [SpeechTermGroupConfig] {
        [
            SpeechTermGroupConfig(
                name: "通用组",
                isEnabled: true,
                applyToAllApps: true,
                appList: "",
                rulesText: "git hub=>GitHub"
            ),
            SpeechTermGroupConfig(
                name: "开发类",
                isEnabled: true,
                applyToAllApps: false,
                appList: "com.apple.Terminal,\ncom.apple.dt.Xcode,\ncom.microsoft.VSCode,\ncom.openai.codex,\ncom.openai.chatgpt",
                rulesText: "后果=>GitHub=>cmd"
            ),
            SpeechTermGroupConfig(
                name: "办公类",
                isEnabled: true,
                applyToAllApps: false,
                appList: "com.microsoft.Word,\ncom.microsoft.Excel,\ncom.microsoft.Powerpoint,\ncom.tencent.wework,\ncom.apple.mail",
                rulesText: "飞鼠=>飞书\n叮叮=>钉钉\n定定=>钉钉\n未信=>微信"
            ),
            SpeechTermGroupConfig(
                name: "写作类",
                isEnabled: true,
                applyToAllApps: false,
                appList: "com.apple.TextEdit,\ncom.apple.Notes,\ncom.coteditor.CotEditor,\ncom.sublimetext.4,\ncom.zed.Zed",
                rulesText: "逗好=>逗号\n句好=>句号"
            )
        ]
    }

    private static func loadSpeechTermGroups() -> [SpeechTermGroupConfig] {
        if let data = UserDefaults.standard.data(forKey: speechTermGroupsStorageKey),
           let groups = try? JSONDecoder().decode([SpeechTermGroupConfig].self, from: data),
           !groups.isEmpty {
            return groups
        }
        return defaultSpeechTermGroups()
    }

    private static func saveSpeechTermGroups(_ groups: [SpeechTermGroupConfig]) {
        if let data = try? JSONEncoder().encode(groups) {
            UserDefaults.standard.set(data, forKey: speechTermGroupsStorageKey)
        }
    }

    private static func loadVoiceCommandOverrides() -> [VoiceCommandOverrideConfig] {
        guard let data = UserDefaults.standard.data(forKey: voiceCommandOverridesStorageKey),
              let overrides = try? JSONDecoder().decode([VoiceCommandOverrideConfig].self, from: data) else {
            return []
        }
        return overrides
    }

    private static func saveVoiceCommandOverrides(_ overrides: [VoiceCommandOverrideConfig]) {
        if let data = try? JSONEncoder().encode(overrides) {
            UserDefaults.standard.set(data, forKey: voiceCommandOverridesStorageKey)
        }
    }

    private static func loadVoiceLanguageTermsOverrides() -> [VoiceLanguageTermsOverrideConfig] {
        guard let data = UserDefaults.standard.data(forKey: voiceLanguageTermsOverridesStorageKey),
              let overrides = try? JSONDecoder().decode([VoiceLanguageTermsOverrideConfig].self, from: data) else {
            return []
        }
        return overrides
    }

    private static func saveVoiceLanguageTermsOverrides(_ overrides: [VoiceLanguageTermsOverrideConfig]) {
        if let data = try? JSONEncoder().encode(overrides) {
            UserDefaults.standard.set(data, forKey: voiceLanguageTermsOverridesStorageKey)
        }
    }

    enum VoiceActivationMode: String, CaseIterable, Identifiable {
        case pushToTalk
        case wakeWord
        case handsFree
        
        var id: String { rawValue }
    }
    
    private static func loadActivationMode() -> VoiceActivationMode {
        if let raw = UserDefaults.standard.string(forKey: "voiceActivationMode"),
           let mode = VoiceActivationMode(rawValue: raw) {
            return mode
        }
        
        let always = UserDefaults.standard.bool(forKey: "isAlwaysListeningEnabled")
        let wake = UserDefaults.standard.object(forKey: "isWakeWordEnabled") as? Bool ?? true
        if always { return .handsFree }
        if wake { return .wakeWord }
        return .pushToTalk
    }

    private static let hotkeyModifierMask: UInt64 =
        CGEventFlags.maskControl.rawValue |
        CGEventFlags.maskAlternate.rawValue |
        CGEventFlags.maskShift.rawValue |
        CGEventFlags.maskCommand.rawValue |
        CGEventFlags.maskAlphaShift.rawValue

    private static let defaultPTTModifiers: UInt64 = CGEventFlags.maskAlternate.rawValue

    private static func sanitizeHotkeyModifiers(_ raw: UInt64) -> UInt64 {
        raw & hotkeyModifierMask
    }

    private static func loadPTTBinding() -> HotkeyBinding {
        let defaults = UserDefaults.standard
        let keyCode = (defaults.object(forKey: "voicePTTKeyCode") as? NSNumber)?.intValue ?? Int(kVK_Space)
        let rawModifiers = (defaults.object(forKey: "voicePTTModifiers") as? NSNumber)?.uint64Value ?? defaultPTTModifiers
        let modifiers = sanitizeHotkeyModifiers(rawModifiers)
        return HotkeyBinding(keyCode: keyCode, modifiers: modifiers)
    }
    
    @Published var driverStatus: String = "Idle"
    @Published var driverState: SystemExtensionActivationState = .idle
    @Published var isMotionTracking: Bool = false
    @Published var attitudeData: String = "No Data"
    
    @Published var calibrationStatus: String = "Normal"

    @Published var voiceStatus: String = "Idle"
    @Published var lastVoiceTranscript: String = ""
    @Published var lastVoiceError: String = ""
    @Published var lastVoiceWakeTime: Date?
    @Published var voiceActivationMode: VoiceActivationMode = AppState.loadActivationMode() {
        didSet {
            guard oldValue != voiceActivationMode else { return }
            UserDefaults.standard.set(voiceActivationMode.rawValue, forKey: "voiceActivationMode")
            applyVoiceActivationMode()
        }
    }
    
    // Voice Triggers
    @Published var isPTTEnabled: Bool = UserDefaults.standard.object(forKey: "isPTTEnabled") as? Bool ?? true {
        didSet { 
            UserDefaults.standard.set(isPTTEnabled, forKey: "isPTTEnabled")
            guard !isApplyingActivationMode else { return }
            voiceService.setPTTEnabled(isPTTEnabled)
            HeadMotionManager.shared.isPTTEnabled = isPTTEnabled
            
            // [Fix] Dynamically Register/Unregister Hotkey
            // If disabled, remove the binding so others can use it.
            if isPTTEnabled {
                HotkeyManager.shared.registerPTT(voicePTTBinding)
            } else {
                HotkeyManager.shared.unregisterPTT()
            }
        }
    }
    @Published var voicePTTBinding: HotkeyBinding = AppState.loadPTTBinding()
    
    @Published var isWakeWordEnabled: Bool = UserDefaults.standard.object(forKey: "isWakeWordEnabled") as? Bool ?? true {
        didSet { 
            UserDefaults.standard.set(isWakeWordEnabled, forKey: "isWakeWordEnabled")
            guard !isApplyingActivationMode else { return }
            updateContinuousListeningState()
        }
    }

    // Microphone State (Proxied from VoiceService)
    @Published var availableInputDevices: [AudioInputDevice] = []
    @Published var selectedInputDeviceID: AudioDeviceID = 0 {
        didSet {
            // Push to service
            if voiceService.selectedInputDeviceID != selectedInputDeviceID {
                voiceService.selectedInputDeviceID = selectedInputDeviceID
            }
        }
    }
    
    @Published var isAlwaysListeningEnabled: Bool = UserDefaults.standard.bool(forKey: "isAlwaysListeningEnabled") {
        didSet {
            UserDefaults.standard.set(isAlwaysListeningEnabled, forKey: "isAlwaysListeningEnabled")
            guard oldValue != isAlwaysListeningEnabled else { return }
            guard !isApplyingActivationMode else { return }

            if !isMutatingAlwaysListening, isAlwaysListeningEnabled {
                if !microphoneAuthorized {
                    setAlwaysListeningEnabledInternal(false)
                    permissions.requestMicrophone()
                    refreshPermissions()
                    return
                }
                if !speechAuthorized {
                    setAlwaysListeningEnabledInternal(false)
                    permissions.requestSpeech()
                    refreshPermissions()
                    return
                }
            }
            
            updateContinuousListeningState()
        }
    }
    private var isMutatingAlwaysListening = false
    private var isApplyingActivationMode = false
    private var lastVoiceReady: Bool = {
        let mic = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        let speech = SFSpeechRecognizer.authorizationStatus() == .authorized
        return mic && speech
    }()
    
    private func updateContinuousListeningState() {
        // 1. Microphone State: Should be ON if EITHER "Wake Word" OR "Always Listening" is enabled.
        let shouldListen = isAlwaysListeningEnabled || isWakeWordEnabled
        voiceService.setAlwaysListeningEnabled(shouldListen)
        
        // 2. Logic State: Direct Command Mode is ON only if "Always Listening" is ON.
        voiceService.isDirectCommandEnabled = isAlwaysListeningEnabled
        
        // 3. Logic State: Wake Word Mode is ON if "Wake Word" is ON.
        voiceService.isWakeWordEnabled = isWakeWordEnabled
    }
    
    private func applyVoiceActivationMode() {
        isApplyingActivationMode = true
        defer { isApplyingActivationMode = false }
        
        let requiresContinuousSession = voiceActivationMode != .pushToTalk
        let micAuthorizedNow = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        let speechAuthorizedNow = SFSpeechRecognizer.authorizationStatus() == .authorized
        if requiresContinuousSession {
            if !micAuthorizedNow {
                HUDManager.shared.showTemporary(
                    message: Locale.current.identifier.starts(with: "zh") ? "请先授予麦克风权限" : "Grant Microphone permission first.",
                    icon: "mic.slash.fill"
                )
                permissions.requestMicrophone()
                refreshPermissions()
                // Keep user's selected mode visible in UI.
                // Runtime engine state is gated by SpeechManager permission checks.
                isPTTEnabled = true
                isWakeWordEnabled = (voiceActivationMode == .wakeWord)
                setAlwaysListeningEnabledInternal(requiresContinuousSession)
                HeadMotionManager.shared.isPTTEnabled = true
                HotkeyManager.shared.registerPTT(voicePTTBinding)
                voiceService.setPTTEnabled(true)
                voiceService.setAlwaysListeningEnabled(requiresContinuousSession)
                voiceService.setDirectCommandEnabled(voiceActivationMode == .handsFree)
                voiceService.setWakeWordEnabled(voiceActivationMode == .wakeWord)
                return
            }
            if !speechAuthorizedNow {
                HUDManager.shared.showTemporary(
                    message: Locale.current.identifier.starts(with: "zh") ? "请先授予语音识别权限" : "Grant Speech Recognition permission first.",
                    icon: "waveform.badge.exclamationmark"
                )
                permissions.requestSpeech()
                refreshPermissions()
                // Keep user's selected mode visible in UI.
                // Runtime engine state is gated by SpeechManager permission checks.
                isPTTEnabled = true
                isWakeWordEnabled = (voiceActivationMode == .wakeWord)
                setAlwaysListeningEnabledInternal(requiresContinuousSession)
                HeadMotionManager.shared.isPTTEnabled = true
                HotkeyManager.shared.registerPTT(voicePTTBinding)
                voiceService.setPTTEnabled(true)
                voiceService.setAlwaysListeningEnabled(requiresContinuousSession)
                voiceService.setDirectCommandEnabled(voiceActivationMode == .handsFree)
                voiceService.setWakeWordEnabled(voiceActivationMode == .wakeWord)
                return
            }
        }
        
        isPTTEnabled = true
        isWakeWordEnabled = (voiceActivationMode == .wakeWord)
        isAlwaysListeningEnabled = requiresContinuousSession
        
        HeadMotionManager.shared.isPTTEnabled = true
        HotkeyManager.shared.registerPTT(voicePTTBinding)
        
        voiceService.setPTTEnabled(true)
        voiceService.setAlwaysListeningEnabled(requiresContinuousSession)
        voiceService.setDirectCommandEnabled(voiceActivationMode == .handsFree)
        voiceService.setWakeWordEnabled(voiceActivationMode == .wakeWord)
    }
    

    
    @Published var isGazeWakeEnabled: Bool = UserDefaults.standard.object(forKey: "isGazeWakeEnabled") as? Bool ?? true {
        didSet {
            UserDefaults.standard.set(isGazeWakeEnabled, forKey: "isGazeWakeEnabled")
            voiceService.setGazeWakeEnabled(isGazeWakeEnabled)
        }
    }
    
    @Published var isAutoPunctuationEnabled: Bool = UserDefaults.standard.object(forKey: "isAutoPunctuationEnabled") as? Bool ?? true {
        didSet {
            UserDefaults.standard.set(isAutoPunctuationEnabled, forKey: "isAutoPunctuationEnabled")
            voiceService.setAutoPunctuationEnabled(isAutoPunctuationEnabled)
        }
    }

    @Published var speechTermCorrectionEnabled: Bool = UserDefaults.standard.object(forKey: "speechTermCorrectionEnabled") as? Bool ?? true {
        didSet {
            UserDefaults.standard.set(speechTermCorrectionEnabled, forKey: "speechTermCorrectionEnabled")
        }
    }
    @Published var speechTermGroups: [SpeechTermGroupConfig] = AppState.loadSpeechTermGroups() {
        didSet {
            AppState.saveSpeechTermGroups(speechTermGroups)
        }
    }
    @Published var voiceCommandOverrides: [VoiceCommandOverrideConfig] = AppState.loadVoiceCommandOverrides() {
        didSet {
            AppState.saveVoiceCommandOverrides(voiceCommandOverrides)
            voiceService.setVoiceCommandOverrides(voiceCommandOverrides)
        }
    }
    @Published var voiceLanguageTermsOverrides: [VoiceLanguageTermsOverrideConfig] = AppState.loadVoiceLanguageTermsOverrides() {
        didSet {
            AppState.saveVoiceLanguageTermsOverrides(voiceLanguageTermsOverrides)
            voiceService.setVoiceLanguageTermsOverrides(voiceLanguageTermsOverrides)
        }
    }

    func addSpeechTermGroup() {
        speechTermGroups.append(
            SpeechTermGroupConfig(
                name: "新分组",
                isEnabled: true,
                applyToAllApps: false,
                appList: "",
                rulesText: ""
            )
        )
    }

    func removeSpeechTermGroup(id: String) {
        speechTermGroups.removeAll { $0.id == id }
        if speechTermGroups.isEmpty {
            speechTermGroups = AppState.defaultSpeechTermGroups()
        }
    }

    func effectiveCommandAliases(for preset: VoiceCommandPreset, localeIdentifier: String) -> [String] {
        VoiceCommandRouter.effectiveAliases(
            for: preset,
            localeIdentifier: localeIdentifier,
            overrides: voiceCommandOverrides
        )
    }

    func commandOverrideText(for preset: VoiceCommandPreset, localeIdentifier: String) -> String {
        guard let override = voiceCommandOverrides.first(where: {
            $0.localeIdentifier == localeIdentifier && $0.commandID == preset.rawValue
        }) else {
            return ""
        }
        return override.aliases.joined(separator: ", ")
    }

    func updateCommandOverrideText(_ raw: String, for preset: VoiceCommandPreset, localeIdentifier: String) {
        let aliases = raw
            .components(separatedBy: CharacterSet(charactersIn: ",\n"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        voiceCommandOverrides.removeAll {
            $0.localeIdentifier == localeIdentifier && $0.commandID == preset.rawValue
        }

        guard !aliases.isEmpty else { return }

        voiceCommandOverrides.append(
            VoiceCommandOverrideConfig(
                localeIdentifier: localeIdentifier,
                commandID: preset.rawValue,
                aliases: aliases
            )
        )
    }

    func resetCommandOverrides(for localeIdentifier: String) {
        voiceCommandOverrides.removeAll { $0.localeIdentifier == localeIdentifier }
    }

    func wakeWordOverrideText(for localeIdentifier: String) -> String {
        voiceLanguageTermsOverrides
            .first(where: { $0.localeIdentifier == localeIdentifier })?
            .wakeWords
            .joined(separator: ", ") ?? ""
    }

    func commandPrefixOverrideText(for localeIdentifier: String) -> String {
        voiceLanguageTermsOverrides
            .first(where: { $0.localeIdentifier == localeIdentifier })?
            .commandPrefixes
            .joined(separator: ", ") ?? ""
    }

    func dictationPrefixOverrideText(for localeIdentifier: String) -> String {
        voiceLanguageTermsOverrides
            .first(where: { $0.localeIdentifier == localeIdentifier })?
            .dictationPrefixes
            .joined(separator: ", ") ?? ""
    }

    func updateWakeWordOverrideText(_ raw: String, for localeIdentifier: String) {
        updateVoiceLanguageTermsOverride(for: localeIdentifier) { config in
            config.wakeWords = parseVoiceTermsText(raw)
        }
    }

    func updateCommandPrefixOverrideText(_ raw: String, for localeIdentifier: String) {
        updateVoiceLanguageTermsOverride(for: localeIdentifier) { config in
            config.commandPrefixes = parseVoiceTermsText(raw)
        }
    }

    func updateDictationPrefixOverrideText(_ raw: String, for localeIdentifier: String) {
        updateVoiceLanguageTermsOverride(for: localeIdentifier) { config in
            config.dictationPrefixes = parseVoiceTermsText(raw)
        }
    }

    func resetVoiceLanguageTermsOverrides(for localeIdentifier: String) {
        voiceLanguageTermsOverrides.removeAll { $0.localeIdentifier == localeIdentifier }
    }

    func exportVoiceLexicon() throws -> URL? {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = "AetherVoiceLexicon.json"
        panel.prompt = String(localized: "voice_lexicon.export")

        guard panel.runModal() == .OK, let url = panel.url else { return nil }

        let payload = VoiceLexiconBackup(
            commandOverrides: voiceCommandOverrides,
            languageTermsOverrides: voiceLanguageTermsOverrides
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(payload)
        try data.write(to: url, options: .atomic)
        return url
    }

    func importVoiceLexicon() throws -> URL? {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.prompt = String(localized: "voice_lexicon.import")

        guard panel.runModal() == .OK, let url = panel.url else { return nil }

        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let payload = try decoder.decode(VoiceLexiconBackup.self, from: data)
        voiceCommandOverrides = payload.commandOverrides
        voiceLanguageTermsOverrides = payload.languageTermsOverrides
        return url
    }

    private func parseVoiceTermsText(_ raw: String) -> [String] {
        raw
            .components(separatedBy: CharacterSet(charactersIn: ",\n"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func updateVoiceLanguageTermsOverride(
        for localeIdentifier: String,
        mutate: (inout VoiceLanguageTermsOverrideConfig) -> Void
    ) {
        var config = voiceLanguageTermsOverrides.first(where: { $0.localeIdentifier == localeIdentifier }) ??
            VoiceLanguageTermsOverrideConfig(
                localeIdentifier: localeIdentifier,
                wakeWords: [],
                commandPrefixes: [],
                dictationPrefixes: []
            )

        mutate(&config)

        voiceLanguageTermsOverrides.removeAll { $0.localeIdentifier == localeIdentifier }
        let hasAnyValues = !config.wakeWords.isEmpty || !config.commandPrefixes.isEmpty || !config.dictationPrefixes.isEmpty
        if hasAnyValues {
            voiceLanguageTermsOverrides.append(config)
        }
    }
    
    func updatePTTBinding(_ binding: HotkeyBinding) {
        let normalized = HotkeyBinding(
            keyCode: binding.keyCode,
            modifiers: Self.sanitizeHotkeyModifiers(binding.modifiers),
            mouseButton: binding.mouseButton
        )

        self.voicePTTBinding = normalized
        UserDefaults.standard.set(normalized.keyCode, forKey: "voicePTTKeyCode")
        UserDefaults.standard.set(normalized.modifiers, forKey: "voicePTTModifiers")
        
        // Update Hotkey Manager ONLY if enabled
        if isPTTEnabled {
            HotkeyManager.shared.registerPTT(normalized)
        }
    }
    
    @Published var alwaysListeningWakeWindowSeconds: Double = UserDefaults.standard.object(forKey: "alwaysListeningWakeWindowSeconds") as? Double ?? 8.0 {
        didSet {
            let clamped = min(max(alwaysListeningWakeWindowSeconds, 3.0), 30.0)
            if clamped != alwaysListeningWakeWindowSeconds {
                alwaysListeningWakeWindowSeconds = clamped
                return
            }
            UserDefaults.standard.set(clamped, forKey: "alwaysListeningWakeWindowSeconds")
        }
    }
    @Published var isLLMEnhancementEnabled: Bool = UserDefaults.standard.bool(forKey: "isLLMEnhancementEnabled") {
        didSet {
            UserDefaults.standard.set(isLLMEnhancementEnabled, forKey: "isLLMEnhancementEnabled")
            voiceService.setLLMEnhancementEnabled(isLLMEnhancementEnabled)
        }
    }

    @Published var onboardingStep: OnboardingStep = .done
    
    @Published var showDockIcon: Bool = UserDefaults.standard.object(forKey: "showDockIcon") as? Bool ?? true {
        didSet {
            UserDefaults.standard.set(showDockIcon, forKey: "showDockIcon")
            if showDockIcon {
                NSApp.setActivationPolicy(.regular)
                // When switching to regular, we might want to activate to show the dock icon explicitly immediately
                // But usually the system handles it.
            } else {
                NSApp.setActivationPolicy(.accessory)
            }
            
            // Re-activate app if needed to refresh UI state, though setActivationPolicy usually handles visibility
            if showDockIcon {
                NSApp.activate(ignoringOtherApps: true)
            }
        }
    }

    @Published var hudAutoHideSeconds: Double = UserDefaults.standard.object(forKey: "hudAutoHideSeconds") as? Double ?? 1.5 {
        didSet {
            let clamped = min(max(hudAutoHideSeconds, 0.5), 8.0)
            if clamped != hudAutoHideSeconds {
                hudAutoHideSeconds = clamped
                return
            }
            UserDefaults.standard.set(clamped, forKey: "hudAutoHideSeconds")
        }
    }
    
    private let driverService = DriverService()
    let motionService = MotionService()
    let voiceService = VoiceService()
    private let permissions = PermissionsService()
    let connectionLock = ConnectionLockService.shared

    private var windowController: NSWindowController?
    private var cancellables = Set<AnyCancellable>()
    private var hasShownAccessibilityHint: Bool = false
    private var hasRequestedAccessibilityPromptThisRun: Bool = false
    private var lastObservedAccessibilityTrusted: Bool?

    
    init() {
        driverService.$state
            .receive(on: DispatchQueue.main)
            .sink { [weak self] newState in
                guard let self else { return }
                self.driverState = newState
                self.driverStatus = self.driverService.statusText
            }
            .store(in: &cancellables)
        
        motionService.$isTracking
            .assign(to: &$isMotionTracking)
            
        motionService.$attitudeText
            .assign(to: &$attitudeData)
            
        motionService.$calibrationStatus
            .receive(on: DispatchQueue.main)
            .assign(to: &$calibrationStatus)
            
        // Voice Service Sync
        // Forward voiceService changes to AppState so SwiftUI views observing
        // appState (e.g. SettingsModules) react to nested property changes.
        voiceService.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)

        // Permissions Sync
        // Keep Settings permission rows in lockstep with runtime permission checks.
        // Without this bridge, AppState computed permission properties can appear stale in UI.
        permissions.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
        
        voiceService.$availableInputDevices
            .receive(on: DispatchQueue.main)
            .assign(to: &$availableInputDevices)
            
        voiceService.$selectedInputDeviceID
            .receive(on: DispatchQueue.main)
            .sink { [weak self] newVal in
                 guard let self else { return }
                 if self.selectedInputDeviceID != newVal {
                     self.selectedInputDeviceID = newVal
                 }
            }
            .store(in: &cancellables)
            

            
        voiceService.$isGazeWakeEnabled
            .receive(on: DispatchQueue.main)
            .assign(to: &$isGazeWakeEnabled)
            
        // Restore voice activation state after initial SwiftUI graph setup to avoid startup re-entrancy.
        DispatchQueue.main.async { [weak self] in
            self?.applyVoiceActivationMode()
        }
        
        voiceService.setLLMEnhancementEnabled(self.isLLMEnhancementEnabled)
        voiceService.setVoiceCommandOverrides(self.voiceCommandOverrides)
        voiceService.setVoiceLanguageTermsOverrides(self.voiceLanguageTermsOverrides)

        voiceService.$status
            .assign(to: &$voiceStatus)
        voiceService.$lastTranscript
            .assign(to: &$lastVoiceTranscript)
        voiceService.$lastError
            .assign(to: &$lastVoiceError)
        voiceService.$lastWakeTime
            .assign(to: &$lastVoiceWakeTime)


        voiceService.onIntent = { [weak self] intent in
            guard let self else { return }
            DispatchQueue.main.async {
                self.applyVoiceIntent(intent)
            }
        }

        permissions.$accessibilityTrusted
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                let live = AXIsProcessTrusted()
                self.motionService.setGlobalHotkeysEnabled(live)
                self.handleAccessibilityTrustTransitionIfNeeded(trusted: live, source: "permissions-publisher")
            }
            .store(in: &cancellables)

        Publishers.CombineLatest3(
            permissions.$accessibilityTrusted,
            permissions.$microphoneAuthorized,
            permissions.$speechAuthorized
        )
        .receive(on: DispatchQueue.main)
        .sink { [weak self] _, _, _ in
            guard let self = self else { return }
            // Single source of truth: use live system permission APIs for all runtime/UI decisions.
            let liveAX = AXIsProcessTrusted()
            let liveMic = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
            let liveSpeech = SFSpeechRecognizer.authorizationStatus() == .authorized
            let voiceReadyNow = liveMic && liveSpeech

            self.handleAccessibilityTrustTransitionIfNeeded(trusted: liveAX, source: "permissions-combine")
            self.voiceService.setAccessibilityTrusted(liveAX)
            self.onboardingStep = Self.deriveOnboardingStep(
                accessibilityTrusted: liveAX,
                microphoneAuthorized: liveMic,
                speechAuthorized: liveSpeech
            )

            // Missing Accessibility breaks AX focus/caret detection, so input mode won't switch.
            if !liveAX {
                if !self.hasShownAccessibilityHint {
                    self.hasShownAccessibilityHint = true
                    HUDManager.shared.showTemporary(
                        message: String(localized: "driver.error.need_accessibility"),
                        icon: "hand.raised.fill"
                    )
                }
                if !self.hasRequestedAccessibilityPromptThisRun {
                    self.hasRequestedAccessibilityPromptThisRun = true
                    self.permissions.requestAccessibility()
                }
            } else {
                self.hasShownAccessibilityHint = false
            }

            // Safety: if Always Listening is enabled but permissions got revoked, shut it off.
            // BUGFIX: Only reset if the app has actually initialized permissions. 
            // On startup, these values might be false temporarily before refresh() is called.
            if self.isAlwaysListeningEnabled && (!liveMic || !liveSpeech) {
                // If we are authorized but the published value is still false (race condition), don't reset.
                // Re-check synchronously to be absolutely sure.
                let micAuth = AVCaptureDevice.authorizationStatus(for: AVMediaType.audio) == .authorized
                let speechAuth = SFSpeechRecognizer.authorizationStatus() == .authorized
                
                if !micAuth || !speechAuth {
                    GlobalLogger.lifecycle.info("Permissons revoked, disabling Always Listening")
                    // Keep selected mode in UI and runtime mode flags aligned.
                    // SpeechManager will surface permission guidance and avoid capture start.
                    let requiresContinuous = self.voiceActivationMode != .pushToTalk
                    self.voiceService.setAlwaysListeningEnabled(requiresContinuous)
                    self.voiceService.setDirectCommandEnabled(self.voiceActivationMode == .handsFree)
                    self.voiceService.setWakeWordEnabled(self.voiceActivationMode == .wakeWord)
                }
            }

            // If user selected a non-PTT mode earlier but voice permissions were missing,
            // auto-apply that mode once permissions transition to ready.
            if self.voiceActivationMode != .pushToTalk,
               !self.lastVoiceReady,
               voiceReadyNow {
                self.applyVoiceActivationMode()
            }
            self.lastVoiceReady = voiceReadyNow
        }
        .store(in: &cancellables)

        // Connection Lock hotkey listener
        NotificationCenter.default.publisher(for: .toggleConnectionLock)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.connectionLock.toggle()
            }
            .store(in: &cancellables)

        // Refresh permissions when the app comes back to foreground (e.g. after changing System Settings).
        NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.refreshPermissions()
            }
            .store(in: &cancellables)

        // If Accessibility is missing, keep polling so UI/hotkeys/HUD state updates promptly after user grants it.
        Timer.publish(every: 1.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self else { return }
                let liveAX = AXIsProcessTrusted()
                let liveMic = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
                let liveSpeech = SFSpeechRecognizer.authorizationStatus() == .authorized
                if !liveAX || !liveMic || !liveSpeech {
                    self.refreshPermissions()
                }
            }
            .store(in: &cancellables)

        refreshPermissions()
    }

    private func handleAccessibilityTrustTransitionIfNeeded(trusted: Bool, source: String) {
        guard lastObservedAccessibilityTrusted != trusted else { return }
        lastObservedAccessibilityTrusted = trusted
        motionService.recoverFromAccessibilityTrustChange(trusted, source: source)
        if trusted {
            hasRequestedAccessibilityPromptThisRun = false
            hasShownAccessibilityHint = false
        }
    }

    private static func deriveOnboardingStep(
        accessibilityTrusted: Bool,
        microphoneAuthorized: Bool,
        speechAuthorized: Bool
    ) -> OnboardingStep {
        if !accessibilityTrusted { return .accessibility }
        if !microphoneAuthorized { return .microphone }
        if !speechAuthorized { return .speech }
        return .done
    }
    
    func activateDriver() {
        // Pre-flight Check 1: Permissions
        // Pre-flight Check 1: Permissions
        if !accessibilityTrusted {
            let msg = String(localized: "driver.error.need_accessibility")
            driverStatus = msg
            GlobalLogger.lifecycle.info("Driver activation blocked: Accessibility not trusted")
            
            let alert = NSAlert()
            alert.messageText = String(localized: "Activation Failed")
            alert.informativeText = msg
            alert.alertStyle = .warning
            alert.addButton(withTitle: "OK")
            alert.runModal()
            return
        }
        
        // Pre-flight Check 2: Motion Tracking Active (proves AirPods are connected)
        // This is the most reliable way to ensure AirPods are actually connected and working
        // Pre-flight Check 2: Motion Tracking Active (proves AirPods are connected)
        // This is the most reliable way to ensure AirPods are actually connected and working
        if !isMotionTracking {
            let msg = String(localized: "driver.error.start_tracking_first")
            driverStatus = msg
            GlobalLogger.lifecycle.info("Driver activation blocked: Motion tracking not started")
            
            let alert = NSAlert()
            alert.messageText = String(localized: "Activation Failed")
            alert.informativeText = msg
            alert.alertStyle = .warning
            alert.addButton(withTitle: "OK")
            alert.runModal()
            return
        }
        
        GlobalLogger.lifecycle.info("Pre-flight checks passed, activating driver")
        driverService.activate(identifier: kAetherDriverBundleID)
    }

    func openPrivacyAndSecurityPane() {
        // Best-effort: the system extension approval UI lives under Privacy & Security.
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security") else { return }
        NSWorkspace.shared.open(url)
    }
    
    func finishCalibration() {
        motionService.finishCalibration()
    }
    
    func toggleMotionTracking() {
        if isMotionTracking {
            motionService.stopTracking()
        } else {
            motionService.startTracking()
        }
    }

    private func applyVoiceIntent(_ intent: VoiceIntent) {
        switch intent {
        case .clickLeft:
            motionService.clickLeft()
        case .clickRight:
            motionService.clickRight()
        case .doubleClick:
            motionService.doubleClick()
        case .startPointer:
            motionService.startTracking()
        case .stopPointer:
            motionService.stopTracking()
        case .recenter:
            motionService.recenter()
        case .scroll(let dx, let dy):
            motionService.scroll(dx: dx, dy: dy)
        case .scrollToWeb(let edge):
            if edge == "top" { motionService.scrollToTop() }
            else { motionService.scrollToBottom() }
        case .dragStart:
            motionService.dragStart()
        case .dragEnd:
            motionService.dragEnd()
        case .undo:
            voiceService.undoLastInjection()
        case .paste:
            // Handled by SpeechManager
            break
        case .lockConnection:
            connectionLock.lock()
        case .unlockConnection:
            connectionLock.unlock()
        case .dictation:
            break
        case .unknown:
            break
        }
    }

    func refreshPermissions() { permissions.refresh() }
    func requestAccessibility() { permissions.requestAccessibility() }
    func requestMicrophone() { permissions.requestMicrophone() }
    func requestSpeech() { permissions.requestSpeech() }
    func openAccessibilityPane() { permissions.openAccessibilityPrivacyPane() }
    func openMicrophonePane() { permissions.openMicrophonePrivacyPane() }
    func openSpeechPane() { permissions.openSpeechPrivacyPane() }

    var accessibilityTrusted: Bool { AXIsProcessTrusted() }
    var microphoneAuthorized: Bool { AVCaptureDevice.authorizationStatus(for: .audio) == .authorized }
    var speechAuthorized: Bool { SFSpeechRecognizer.authorizationStatus() == .authorized }

    var microphoneAuthorizationStatus: AVAuthorizationStatus {
        AVCaptureDevice.authorizationStatus(for: .audio)
    }

    var speechAuthorizationStatus: SFSpeechRecognizerAuthorizationStatus {
        SFSpeechRecognizer.authorizationStatus()
    }

    var accessibilityStatusDetail: String {
        let live = AXIsProcessTrusted()
        return live
            ? "系统状态：已授权"
            : "系统状态：未授权"
    }

    var microphoneStatusDetail: String {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return "系统状态：已授权 (authorized)"
        case .denied:
            return "系统状态：已拒绝 (denied)"
        case .restricted:
            return "系统状态：受限 (restricted)"
        case .notDetermined:
            return "系统状态：未决定 (notDetermined)"
        @unknown default:
            return "系统状态：未知"
        }
    }

    var speechStatusDetail: String {
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized:
            return "系统状态：已授权 (authorized)"
        case .denied:
            return "系统状态：已拒绝 (denied)"
        case .restricted:
            return "系统状态：受限 (restricted)"
        case .notDetermined:
            return "系统状态：未决定 (notDetermined)"
        @unknown default:
            return "系统状态：未知"
        }
    }

    func setAlwaysListeningEnabled(_ enabled: Bool) {
        if enabled {
            if !microphoneAuthorized {
                permissions.requestMicrophone()
                refreshPermissions()
                return
            }
            if !speechAuthorized {
                permissions.requestSpeech()
                refreshPermissions()
                return
            }
        }
        voiceActivationMode = enabled ? .handsFree : .pushToTalk
    }

    func requestAccessibilityGuided() {
        if AXIsProcessTrusted() {
            refreshPermissions()
            return
        }
        // Accessibility already has a native prompt with "Open System Settings".
        // Do not open the pane immediately, otherwise users see two windows at once.
        let didShowSystemPrompt = permissions.requestAccessibility()
        if !didShowSystemPrompt {
            permissions.openAccessibilityPrivacyPane()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            self?.refreshPermissions()
        }
    }

    func requestMicrophoneGuided() {
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        switch status {
        case .authorized:
            refreshPermissions()
        case .notDetermined:
            // Important: do not jump to System Settings immediately.
            // Let the native TCC prompt appear first, otherwise it can be interrupted.
            permissions.requestMicrophone()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
                guard let self else { return }
                self.refreshPermissions()
                if !self.microphoneAuthorized {
                    self.permissions.openMicrophonePrivacyPane()
                }
            }
        case .denied, .restricted:
            // Recovery path for stale/broken TCC rows:
            // reset app microphone decision, then re-request to force macOS prompt and re-create list entry.
            Task { [weak self] in
                _ = await Self.resetTCCAsync(service: "Microphone")
                try? await Task.sleep(for: .milliseconds(200))
                guard let self else { return }
                self.permissions.requestMicrophone()
                try? await Task.sleep(for: .milliseconds(900))
                self.refreshPermissions()
                if !self.microphoneAuthorized {
                    self.permissions.openMicrophonePrivacyPane()
                }
            }
        @unknown default:
            permissions.openMicrophonePrivacyPane()
            refreshPermissions()
        }
    }

    func requestSpeechGuided() {
        let status = SFSpeechRecognizer.authorizationStatus()
        switch status {
        case .authorized:
            refreshPermissions()
        case .notDetermined:
            permissions.requestSpeech()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
                guard let self else { return }
                self.refreshPermissions()
                if !self.speechAuthorized {
                    self.permissions.openSpeechPrivacyPane()
                }
            }
        case .denied, .restricted:
            Task { [weak self] in
                _ = await Self.resetTCCAsync(service: "SpeechRecognition")
                try? await Task.sleep(for: .milliseconds(200))
                guard let self else { return }
                self.permissions.requestSpeech()
                try? await Task.sleep(for: .milliseconds(900))
                self.refreshPermissions()
                if !self.speechAuthorized {
                    self.permissions.openSpeechPrivacyPane()
                }
            }
        @unknown default:
            permissions.openSpeechPrivacyPane()
            refreshPermissions()
        }
    }

    nonisolated private static func resetTCCAsync(service: String) async -> Bool {
        await Task.detached(priority: .userInitiated) {
            resetTCC(service: service)
        }.value
    }

    nonisolated private static func resetTCC(service: String) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
        process.arguments = ["reset", service, "com.7fei.Aether"]
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }

    private func setAlwaysListeningEnabledInternal(_ enabled: Bool) {
        guard !isMutatingAlwaysListening else { return }
        isMutatingAlwaysListening = true
        isAlwaysListeningEnabled = enabled
        isMutatingAlwaysListening = false
    }

    func showMainWindow() {
        // Main window is now the Settings window
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

class AetherAppDelegate: NSObject, NSApplicationDelegate {
    private func isRunningFromReadOnlyDiskImage() -> Bool {
        let bundleURL = Bundle.main.bundleURL
        let keys: Set<URLResourceKey> = [
            .volumeIsReadOnlyKey,
            .volumeLocalizedFormatDescriptionKey
        ]
        guard let values = try? bundleURL.resourceValues(forKeys: keys) else { return false }
        guard values.volumeIsReadOnly == true else { return false }

        // Disk image volumes are read-only by default and report "Disk Image" format.
        let format = (values.volumeLocalizedFormatDescription ?? "").lowercased()
        if format.contains("disk image") || format.contains("dmg") || format.contains("磁盘映像") {
            return true
        }
        // Conservative fallback for localized format strings we don't recognize.
        return bundleURL.path.hasPrefix("/Volumes/")
    }

    private func enforceApplicationsInstallPathIfNeeded() {
        guard isRunningFromReadOnlyDiskImage() else { return }

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "请先安装到 Applications 再运行"
        alert.informativeText = "你正在从磁盘镜像运行 Aether。为避免辅助功能权限每次重置，请先拖到 Applications 后再打开。"
        alert.addButton(withTitle: "打开 Applications")
        alert.addButton(withTitle: "退出")
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            NSWorkspace.shared.open(URL(fileURLWithPath: "/Applications", isDirectory: true))
        }
        NSApp.terminate(nil)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Respect user's Dock visibility preference.
        let showDockIcon = UserDefaults.standard.object(forKey: "showDockIcon") as? Bool ?? true
        NSApp.setActivationPolicy(showDockIcon ? .regular : .accessory)
        if showDockIcon {
            NSApp.activate(ignoringOtherApps: true)
        }
        enforceApplicationsInstallPathIfNeeded()
    }
}

@main
struct AetherApp: App {
    @NSApplicationDelegateAdaptor(AetherAppDelegate.self) var appDelegate
    @StateObject private var appState = AppState()
    
    var body: some Scene {
        Window("Aether", id: "main") {
            AetherMainView()
                .environmentObject(appState)
        }
        .defaultSize(width: 1120, height: 760)
        .commands {
            SidebarCommands() // Enable View -> Show/Hide Sidebar
        }
        
        AetherMenuBar()
            .environmentObject(appState)
    }
}

// MARK: - Notification Names
extension Notification.Name {
    static let toggleConnectionLock = Notification.Name("AetherToggleConnectionLock")
}
