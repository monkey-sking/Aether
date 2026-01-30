import SwiftUI
import SystemExtensions

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
    
    private var extensionManager = SystemExtensionManager.shared
    private var motionManager = HeadMotionManager.shared
    
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
    }
}
