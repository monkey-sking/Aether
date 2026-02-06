import SwiftUI
import SystemExtensions

@MainActor
class AppState: ObservableObject {
    @Published var driverStatus: String = "Idle"
    @Published var isMotionTracking: Bool = false
    @Published var attitudeData: String = "No Data"
    
    @Published var calibrationStatus: String = "Normal"
    @Published var isDwellClickEnabled: Bool = true {
        didSet {
            motionManager.isDwellClickEnabled = isDwellClickEnabled
        }
    }

    @Published var voiceStatus: String = "Idle"
    @Published var lastVoiceTranscript: String = ""
    @Published var isAlwaysListeningEnabled: Bool = false {
        didSet { speechManager.isAlwaysListeningEnabled = isAlwaysListeningEnabled }
    }
    @Published var isLLMEnhancementEnabled: Bool = false {
        didSet { speechManager.isLLMEnhancementEnabled = isLLMEnhancementEnabled }
    }
    
    private var extensionManager = SystemExtensionManager.shared
    private var motionManager = HeadMotionManager.shared
    private var speechManager = SpeechManager()
    private var permissions = PermissionsManager()

    private var windowController: NSWindowController?
    
    init() {
        extensionManager.$status
            .assign(to: &$driverStatus)
        
        motionManager.$isTracking
            .assign(to: &$isMotionTracking)
            
        motionManager.$attitudeText
            .assign(to: &$attitudeData)
            
        motionManager.$calibrationStatus
            .assign(to: &$calibrationStatus)
            
        self.isDwellClickEnabled = motionManager.isDwellClickEnabled

        speechManager.$status
            .assign(to: &$voiceStatus)
        speechManager.$lastTranscript
            .assign(to: &$lastVoiceTranscript)

        speechManager.onIntent = { [weak self] intent in
            guard let self else { return }
            DispatchQueue.main.async {
                self.applyVoiceIntent(intent)
            }
        }
    }
    
    func activateDriver() {
        extensionManager.activate(identifier: kAetherDriverBundleID)
    }
    
    func finishCalibration() {
        motionManager.finishCalibration()
    }
    
    func toggleMotionTracking() {
        if isMotionTracking {
            motionManager.stopTracking()
        } else {
            motionManager.startTracking()
        }
    }

    private func applyVoiceIntent(_ intent: VoiceIntent) {
        switch intent {
        case .clickLeft:
            motionManager.clickLeft()
        case .clickRight:
            motionManager.clickRight()
        case .doubleClick:
            motionManager.doubleClick()
        case .startPointer:
            motionManager.startTracking()
        case .stopPointer:
            motionManager.stopTracking()
        case .recenter:
            motionManager.recenter()
        case .setDwell(let enabled):
            isDwellClickEnabled = enabled
        case .undo:
            speechManager.undoLastInjection()
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

    func showMainWindow() {
        // In SwiftUI, windows may already exist; this is a best-effort helper from menu bar.
        if let window = NSApp.windows.first(where: { $0.isVisible }) {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        NSApp.activate(ignoringOtherApps: true)
    }
}

@main
struct AetherApp: App {
    @StateObject private var appState = AppState()
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .frame(minWidth: 400, minHeight: 600)
        }
        AetherMenuBar()
            .environmentObject(appState)
    }
}
