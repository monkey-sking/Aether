import SwiftUI
import SystemExtensions
import Combine
import AVFoundation
import Speech

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

    var onIntent: ((VoiceIntent) -> Void)? {
        get { manager.onIntent }
        set { manager.onIntent = newValue }
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
    }

    func setAlwaysListeningEnabled(_ enabled: Bool) {
        manager.isAlwaysListeningEnabled = enabled
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
    @Published var driverStatus: String = "Idle"
    @Published var driverState: SystemExtensionActivationState = .idle
    @Published var isMotionTracking: Bool = false
    @Published var attitudeData: String = "No Data"
    @Published var pointerOutputPath: String = OutputRouting.shared.pointerOutputPath
    @Published var textOutputPath: String = OutputRouting.shared.textOutputPath
    @Published var forceDriverOnly: Bool = UserDefaults.standard.bool(forKey: "forceDriverOnly") {
        didSet {
            UserDefaults.standard.set(forceDriverOnly, forKey: "forceDriverOnly")
            OutputRouting.shared.forceDriverOnly = forceDriverOnly
        }
    }
    
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
    @Published var isAlwaysListeningEnabled: Bool = UserDefaults.standard.bool(forKey: "isAlwaysListeningEnabled") {
        didSet {
            UserDefaults.standard.set(isAlwaysListeningEnabled, forKey: "isAlwaysListeningEnabled")
            guard oldValue != isAlwaysListeningEnabled else { return }

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

            voiceService.setAlwaysListeningEnabled(isAlwaysListeningEnabled)
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
    @Published var preferInputMethodCaret: Bool = UserDefaults.standard.object(forKey: "preferInputMethodCaret") as? Bool ?? false {
        didSet {
            UserDefaults.standard.set(preferInputMethodCaret, forKey: "preferInputMethodCaret")
        }
    }
    @Published var caretEngineCompareEnabled: Bool = UserDefaults.standard.object(forKey: "caretEngineCompareEnabled") as? Bool ?? false {
        didSet {
            UserDefaults.standard.set(caretEngineCompareEnabled, forKey: "caretEngineCompareEnabled")
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
    private let motionService = MotionService()
    private let voiceService = VoiceService()
    private let permissions = PermissionsService()
    let connectionLock = ConnectionLockService.shared

    private var windowController: NSWindowController?
    private var cancellables = Set<AnyCancellable>()
    private var isMutatingAlwaysListening = false
    
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
            .assign(to: &$calibrationStatus)
            
        motionService.isDwellClickEnabled = self.isDwellClickEnabled
        
        // Restore OutputRouting state from persisted value
        OutputRouting.shared.forceDriverOnly = self.forceDriverOnly
        
        // Restore VoiceService state from persisted values (Safe restoration)
        // [Hotfix] Only enable if already authorized, otherwise wait for user interaction to avoid TCC crash.
        let micAuth = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        let speechAuth = SFSpeechRecognizer.authorizationStatus() == .authorized
        
        if self.isAlwaysListeningEnabled && micAuth && speechAuth {
            voiceService.setAlwaysListeningEnabled(true)
        } else if self.isAlwaysListeningEnabled {
            // If saved as true but not authorized, we MUST set to false to avoid crash, 
            // but we don't overwrite UserDefaults yet to let user fix permissions.
            self.isAlwaysListeningEnabled = false
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

        OutputRouting.shared.$pointerOutputPath
            .receive(on: DispatchQueue.main)
            .assign(to: &$pointerOutputPath)

        OutputRouting.shared.$textOutputPath
            .receive(on: DispatchQueue.main)
            .assign(to: &$textOutputPath)


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

            isAlwaysListeningEnabled = enabled
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
        WindowGroup {
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

// MARK: - Visual Backend
struct EffectView: NSViewRepresentable {
    var material: NSVisualEffectView.Material
    var blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}

// MARK: - Notification Names


extension Notification.Name {
    static let toggleConnectionLock = Notification.Name("AetherToggleConnectionLock")
}
