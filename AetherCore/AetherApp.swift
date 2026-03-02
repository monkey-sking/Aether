import SwiftUI
import SystemExtensions
import Combine
import AVFoundation
import Speech
import Carbon

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

    var isDwellClickEnabled: Bool {
        get { manager.isDwellClickEnabled }
        set { manager.isDwellClickEnabled = newValue }
    }

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
    func requestAccessibility() { manager.requestAccessibility() }
    func requestMicrophone() { manager.requestMicrophone() }
    func requestSpeech() { manager.requestSpeech() }
    func openAccessibilityPrivacyPane() { manager.openAccessibilityPrivacyPane() }
    func openMicrophonePrivacyPane() { manager.openMicrophonePrivacyPane() }
    func openSpeechPrivacyPane() { manager.openSpeechPrivacyPane() }
}

@MainActor
class AppState: ObservableObject {
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
    
    @Published var driverStatus: String = "Idle"
    @Published var driverState: SystemExtensionActivationState = .idle
    @Published var isMotionTracking: Bool = false
    @Published var attitudeData: String = "No Data"
    
    @Published var calibrationStatus: String = "Normal"
    @Published var isDwellClickEnabled: Bool = UserDefaults.standard.object(forKey: "isDwellClickEnabled_v3") as? Bool ?? false {
        didSet {
            UserDefaults.standard.set(isDwellClickEnabled, forKey: "isDwellClickEnabled_v3")
            motionService.isDwellClickEnabled = isDwellClickEnabled
        }
    }

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
    @Published var voicePTTBinding: HotkeyBinding = HotkeyBinding(
        keyCode: UserDefaults.standard.integer(forKey: "voicePTTKeyCode") == 0 ? Int(kVK_Space) : UserDefaults.standard.integer(forKey: "voicePTTKeyCode"),
        modifiers: UserDefaults.standard.integer(forKey: "voicePTTModifiers") == 0 ? 524576 : UInt64(UserDefaults.standard.integer(forKey: "voicePTTModifiers")) // Option+Space default
    )
    
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
                permissions.requestMicrophone()
                refreshPermissions()
                voiceActivationMode = .pushToTalk
                return
            }
            if !speechAuthorizedNow {
                permissions.requestSpeech()
                refreshPermissions()
                voiceActivationMode = .pushToTalk
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
    
    func updatePTTBinding(_ binding: HotkeyBinding) {
        self.voicePTTBinding = binding
        UserDefaults.standard.set(binding.keyCode, forKey: "voicePTTKeyCode")
        UserDefaults.standard.set(binding.modifiers, forKey: "voicePTTModifiers")
        
        // Update Hotkey Manager ONLY if enabled
        if isPTTEnabled {
            HotkeyManager.shared.registerPTT(binding)
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
            
        motionService.isDwellClickEnabled = self.isDwellClickEnabled
        
        // Restore voice activation state after initial SwiftUI graph setup to avoid startup re-entrancy.
        DispatchQueue.main.async { [weak self] in
            self?.applyVoiceActivationMode()
        }
        
        voiceService.setLLMEnhancementEnabled(self.isLLMEnhancementEnabled)

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
            .sink { trusted in
                self.motionService.setGlobalHotkeysEnabled(trusted)
            }
            .store(in: &cancellables)

        Publishers.CombineLatest3(
            permissions.$accessibilityTrusted,
            permissions.$microphoneAuthorized,
            permissions.$speechAuthorized
        )
        .receive(on: DispatchQueue.main)
        .sink { [weak self] accessibilityTrusted, microphoneAuthorized, speechAuthorized in
            guard let self = self else { return }
            self.onboardingStep = Self.deriveOnboardingStep(
                accessibilityTrusted: accessibilityTrusted,
                microphoneAuthorized: microphoneAuthorized,
                speechAuthorized: speechAuthorized
            )

            // Safety: if Always Listening is enabled but permissions got revoked, shut it off.
            // BUGFIX: Only reset if the app has actually initialized permissions. 
            // On startup, these values might be false temporarily before refresh() is called.
            if self.isAlwaysListeningEnabled && (!microphoneAuthorized || !speechAuthorized) {
                // If we are authorized but the published value is still false (race condition), don't reset.
                // Re-check synchronously to be absolutely sure.
                let micAuth = AVCaptureDevice.authorizationStatus(for: AVMediaType.audio) == .authorized
                let speechAuth = SFSpeechRecognizer.authorizationStatus() == .authorized
                
                if !micAuth || !speechAuth {
                    GlobalLogger.lifecycle.info("Permissons revoked, disabling Always Listening")
                    self.setAlwaysListeningEnabledInternal(false)
                    self.voiceActivationMode = .pushToTalk
                }
            }
        }
        .store(in: &cancellables)

        // Connection Lock hotkey listener
        NotificationCenter.default.publisher(for: .toggleConnectionLock)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.connectionLock.toggle()
            }
            .store(in: &cancellables)

        refreshPermissions()
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
        case .setDwell(let enabled):
            isDwellClickEnabled = enabled
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

    var accessibilityTrusted: Bool { permissions.accessibilityTrusted }
    var microphoneAuthorized: Bool { permissions.microphoneAuthorized }
    var speechAuthorized: Bool { permissions.speechAuthorized }

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
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Respect user's Dock visibility preference.
        let showDockIcon = UserDefaults.standard.object(forKey: "showDockIcon") as? Bool ?? true
        NSApp.setActivationPolicy(showDockIcon ? .regular : .accessory)
        if showDockIcon {
            NSApp.activate(ignoringOtherApps: true)
        }
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
        .windowStyle(.hiddenTitleBar)
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
