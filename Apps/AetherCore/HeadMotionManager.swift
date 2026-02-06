import Foundation
import CoreMotion
import Combine
import os.log
import IOKit
import AppKit
import CoreGraphics
import ApplicationServices
import SwiftUI
import Carbon
import Carbon.HIToolbox
import MediaPlayer

class HeadMotionManager: ObservableObject {
    static let shared = HeadMotionManager()

    static let pttDownNotification = Notification.Name("AetherPTTDown")
    static let pttUpNotification = Notification.Name("AetherPTTUp")
    
    private init() {
        setupHotkeys()
        setupAirPodsCommands()
        startStabilityTimer()
    }
    
    private var isHotkeyRegistered: Bool = false
    private var stabilityTimer: Timer?
    
    private let motionManager = CMHeadphoneMotionManager()
    private let log = OSLog(subsystem: "com.7fei.Aether", category: "MotionManager")
    
    @Published var isTracking: Bool = false
    @Published var attitudeText: String = "No Data"
    
    // Experience Optimization Constants
    private let deadzone: Double = 0.005  // Ignore movements smaller than ~0.3 degrees
    private let accelerationPower: Double = 1.5 // 1.0 is linear, >1.0 is exponential
    
    // Dwell Click State
    @Published var isDwellClickEnabled: Bool = true
    private var dwellStartTime: Date?
    private var lastDwellPos: CGPoint = .zero
    private let dwellRadius: CGFloat = 15.0 // More forgiving radius
    private let dwellDuration: TimeInterval = 0.8 // Seconds
    private let movementThreshold: CGFloat = 2.0 // Min movement to reset timer during dwell
    
    // Dynamic Range Calibration
    @Published var calibrationStatus: String = "Normal"
    private var minYaw: Double = -0.3
    private var maxYaw: Double = 0.3
    private var minPitch: Double = -0.2
    private var maxPitch: Double = 0.2
    private var isCalibratingRange: Bool = false
    
    // Smoothing
    private var currentX: CGFloat = 0
    private var currentY: CGFloat = 0
    private let smoothing: CGFloat = 0.5 // Responsive but steady
    
    private var baseYaw: Double = 0
    private var basePitch: Double = 0
    private var isCalibrated: Bool = false
    
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var isAirPodsStreamActive: Bool = false

    // Push-to-talk (voice) hotkey state (to prevent auto-repeat keyDown spam)
    private var isPTTPressed: Bool = false
    
    // Store aggregate desktop dimensions
    private var desktopFrame: NSRect = .zero
    
    // UI Overlay
    private var dwellOverlay: DwellOverlayWindow? = nil
    
    // Attention Awareness
    @Published var isLookingAtScreen: Bool = true
    private let attentionThresholdYaw: Double = 0.65 // ~37 degrees (0.65 radians)
    private var lastAttentionCheckTime: Date = Date()
    private var attentionHysteresisBuffer: Int = 0 
    
    // Remote Command Targets
    private var playTarget: Any?
    private var pauseTarget: Any?
    private var toggleTarget: Any?
    private var nextTrackTarget: Any?
    private var prevTrackTarget: Any?
    
    func startTracking() {
        guard !isTracking else { return }
        
        // Initial state check
        if !motionManager.isDeviceMotionAvailable {
            attitudeText = "Waiting for AirPods..."
            os_log("Waiting for AirPods Connection", log: log)
        }
        
        // Find aggregate frame of all screens
        var aggregate = NSRect.zero
        let screens = NSScreen.screens
        for screen in screens {
            aggregate = aggregate.union(screen.frame)
            os_log("Screen found: %@", log: log, String(describing: screen.frame))
        }
        self.desktopFrame = aggregate
        
        self.calibrationStatus = "Calibrating..."
        self.isCalibrated = false
        self.isAirPodsStreamActive = false
        
        // Reset attention state
        self.isLookingAtScreen = true
        self.enableAirPodsCommands()
        
        motionManager.startDeviceMotionUpdates(to: .main) { [weak self] motion, error in
            guard let self = self, let attitude = motion?.attitude else { 
                if error != nil {
                    DispatchQueue.main.async { self?.attitudeText = "AirPods Error" }
                }
                return 
            }
            
            if !self.isAirPodsStreamActive {
                self.isAirPodsStreamActive = true
                os_log("AirPods Stream Detected", log: self.log)
                DispatchQueue.main.async { self.attitudeText = "Tracking..." }
            }
            
            // Baseline (Center)
            if !self.isCalibrated {
                self.baseYaw = attitude.yaw
                self.basePitch = attitude.pitch
                self.isCalibrated = true
                self.isCalibratingRange = true
                self.minYaw = -0.3; self.maxYaw = 0.3
                self.minPitch = -0.2; self.maxPitch = 0.2
                
                self.currentX = self.desktopFrame.midX
                self.currentY = self.desktopFrame.midY
                return
            }
            
            let offYaw = attitude.yaw - self.baseYaw
            let offPitch = attitude.pitch - self.basePitch
            
            // Attention Check (Gaze-based Context Switching)
            self.updateAttentionState(yaw: offYaw)
            
            if self.isCalibratingRange {
                self.minYaw = min(self.minYaw, offYaw)
                self.maxYaw = max(self.maxYaw, offYaw)
                self.minPitch = min(self.minPitch, offPitch)
                self.maxPitch = max(self.maxPitch, offPitch)
            }
            
            // Only move cursor if looking at screen
            guard self.isLookingAtScreen else {
                 DispatchQueue.main.async {
                     if self.attitudeText != "Away" { self.attitudeText = "Away" }
                 }
                 return 
            }
            
            let rangeX = max(0.1, self.maxYaw - self.minYaw)
            let rangeY = max(0.1, self.maxPitch - self.minPitch)
            let midYaw = (self.minYaw + self.maxYaw) / 2.0
            let midPitch = (self.minPitch + self.maxPitch) / 2.0
            
            let rawNormX = (offYaw - midYaw) / rangeX
            let rawNormY = (offPitch - midPitch) / rangeY
            
            func applyDeadzoneAndAccel(_ val: Double) -> Double {
                let absVal = abs(val)
                if absVal < deadzone { return 0 }
                let scaled = (absVal - deadzone) / (0.5 - deadzone)
                return pow(scaled, accelerationPower) * 0.5 * (val > 0 ? 1 : -1)
            }
            
            let normX = max(-0.5, min(0.5, applyDeadzoneAndAccel(rawNormX)))
            let normY = max(-0.5, min(0.5, applyDeadzoneAndAccel(rawNormY)))
            
            let rawTargetX = self.desktopFrame.midX - (CGFloat(normX) * self.desktopFrame.width)
            let rawTargetY = self.desktopFrame.midY + (CGFloat(normY) * self.desktopFrame.height)
            
            self.currentX = (self.currentX * (1 - smoothing)) + (rawTargetX * smoothing)
            self.currentY = (self.currentY * (1 - smoothing)) + (rawTargetY * smoothing)
            
            let targetX = max(self.desktopFrame.minX, min(self.desktopFrame.maxX, self.currentX))
            let targetY = max(self.desktopFrame.minY, min(self.desktopFrame.maxY, self.currentY))
            
            self.moveToAbsolutePosition(x: targetX, y: targetY)
            self.attitudeText = String(format: "Y: %.2f, P: %.2f", attitude.yaw, attitude.pitch)
        }
        
        isTracking = true
        os_log("Aether: Started tracking", log: log)
        
        DispatchQueue.main.async {
            self.dwellOverlay = DwellOverlayWindow()
        }
    }
    
    func stopTracking() {
        guard isTracking else { return }
        motionManager.stopDeviceMotionUpdates()
        disableAirPodsCommands() // Clean up commands
        
        DispatchQueue.main.async {
            self.dwellOverlay?.orderOut(nil)
            self.dwellOverlay = nil
        }
        isTracking = false
        isCalibrated = false
        isCalibratingRange = false
        isAirPodsStreamActive = false
        isLookingAtScreen = false
        os_log("Aether: Stopped tracking", log: log)
    }
    
    // ... toggleTracking, public wrappers, etc. (unchanged) ...
    
    func toggleTracking() {
        if isTracking {
            stopTracking()
        } else {
            startTracking()
        }
    }

    // Public wrappers for external controllers (e.g., voice commands)
    func clickLeft() { triggerMouseClick(at: CGPoint(x: currentX, y: currentY), button: .left) }
    func clickRight() { triggerMouseClick(at: CGPoint(x: currentX, y: currentY), button: .right) }
    func doubleClick() { triggerMouseClick(at: CGPoint(x: currentX, y: currentY), button: .left, doubleClick: true) }

    func recenter() {
        guard isTracking else { return }
        // Force re-calibration on next motion sample.
        isCalibrated = false
        isCalibratingRange = true
        calibrationStatus = "Calibrating..."
        dwellStartTime = nil
    }
    
    func finishCalibration() {
        isCalibratingRange = false
        calibrationStatus = "Normal"
        os_log("Aether: Calibration Finished", log: log)
    }
    
    private func updateAttentionState(yaw: Double) {
        let isCurrentlyLooking = abs(yaw) < attentionThresholdYaw
        
        // Simple debouncing/hysteresis
        if isCurrentlyLooking != isLookingAtScreen {
            attentionHysteresisBuffer += 1
            if attentionHysteresisBuffer > 10 { // Approx 0.1-0.2s at 60Hz
                isLookingAtScreen = isCurrentlyLooking
                attentionHysteresisBuffer = 0
                
                if isLookingAtScreen {
                    os_log("Attention: Regained (Commands Enabled)", log: log)
                    enableAirPodsCommands()
                    // Optional: Play subtle feedback sound
                } else {
                    os_log("Attention: Lost (Commands Disabled)", log: log)
                    disableAirPodsCommands()
                    // Optional: Play subtle feedback sound
                    
                    // Clear dwell state when looking away
                    DispatchQueue.main.async {
                        self.dwellStartTime = nil
                        self.dwellOverlay?.update(progress: 0, position: .zero, isClicking: false)
                    }
                }
            }
        } else {
            attentionHysteresisBuffer = 0
        }
    }

    private func enableAirPodsCommands() {
        let commandCenter = MPRemoteCommandCenter.shared()
        
        // Bind Play/Pause -> Left Click
        playTarget = commandCenter.playCommand.addTarget { [weak self] _ in
            self?.handleClickCommand()
             return .success
        }
        pauseTarget = commandCenter.pauseCommand.addTarget { [weak self] _ in
            self?.handleClickCommand()
             return .success
        }
        toggleTarget = commandCenter.togglePlayPauseCommand.addTarget { [weak self] _ in
            self?.handleClickCommand()
             return .success
        }
        commandCenter.playCommand.isEnabled = true
        commandCenter.pauseCommand.isEnabled = true
        commandCenter.togglePlayPauseCommand.isEnabled = true
        
        // Bind Next Track -> Right Click
        nextTrackTarget = commandCenter.nextTrackCommand.addTarget { [weak self] _ in
            guard let self = self, self.isTracking, self.isLookingAtScreen else { return .commandFailed }
            os_log("AirPods: Double Press -> Right Click", log: self.log)
            DispatchQueue.main.async { self.triggerMouseClick(at: CGPoint(x: self.currentX, y: self.currentY), button: .right) }
            return .success
        }
        commandCenter.nextTrackCommand.isEnabled = true
        
        // Bind Previous Track -> Double Click
        prevTrackTarget = commandCenter.previousTrackCommand.addTarget { [weak self] _ in
            guard let self = self, self.isTracking, self.isLookingAtScreen else { return .commandFailed }
            os_log("AirPods: Triple Press -> Double Click", log: self.log)
            DispatchQueue.main.async { self.triggerMouseClick(at: CGPoint(x: self.currentX, y: self.currentY), doubleClick: true) }
            return .success
        }
        commandCenter.previousTrackCommand.isEnabled = true
    }
    
    private func disableAirPodsCommands() {
        let commandCenter = MPRemoteCommandCenter.shared()
        
        if let target = playTarget { commandCenter.playCommand.removeTarget(target) }
        if let target = pauseTarget { commandCenter.pauseCommand.removeTarget(target) }
        if let target = toggleTarget { commandCenter.togglePlayPauseCommand.removeTarget(target) }
        if let target = nextTrackTarget { commandCenter.nextTrackCommand.removeTarget(target) }
        if let target = prevTrackTarget { commandCenter.previousTrackCommand.removeTarget(target) }
        
        playTarget = nil
        pauseTarget = nil
        toggleTarget = nil
        nextTrackTarget = nil
        prevTrackTarget = nil
        
        // We do NOT set isEnabled = false, because that would disable the command system-wide 
        // if we were the only registered target? No, actually setting isEnabled=false tells iOS/macOS 
        // "I don't handle this", which passes it to the next app (Music).
        // So yes, we SHOULD set them to false or nil behavior to let others handle it.
        // Actually, removing targets is enough for other apps to take over if we are not the "Now Playing" app.
        // But to be safe and explicit:
        // commandCenter.playCommand.isEnabled = false // Let system handle it
    }
    
    private func handleClickCommand() {
        guard isTracking, isLookingAtScreen else { return }
        os_log("AirPods: Single Press -> Left Click", log: log)
        DispatchQueue.main.async { self.triggerMouseClick(at: CGPoint(x: self.currentX, y: self.currentY)) }
    }
    
    // ... triggerMouseClick (unchanged) ...
    
    private func triggerMouseClick(at point: CGPoint, button: CGMouseButton = .left, doubleClick: Bool = false) {
        let maxY = desktopFrame == .zero ? NSScreen.screens.reduce(CGFloat(0)) { max($0, $1.frame.maxY) } : desktopFrame.maxY
        let cgPoint = CGPoint(x: point.x, y: maxY - point.y)
        
        let mouseTypeDown: CGEventType = (button == .left) ? .leftMouseDown : .rightMouseDown
        let mouseTypeUp: CGEventType = (button == .left) ? .leftMouseUp : .rightMouseUp
        
        let source = CGEventSource(stateID: .combinedSessionState)
        
        if doubleClick {
            let events = [
                CGEvent(mouseEventSource: source, mouseType: mouseTypeDown, mouseCursorPosition: cgPoint, mouseButton: button),
                CGEvent(mouseEventSource: source, mouseType: mouseTypeUp, mouseCursorPosition: cgPoint, mouseButton: button),
                CGEvent(mouseEventSource: source, mouseType: mouseTypeDown, mouseCursorPosition: cgPoint, mouseButton: button),
                CGEvent(mouseEventSource: source, mouseType: mouseTypeUp, mouseCursorPosition: cgPoint, mouseButton: button)
            ]
            for (idx, event) in events.enumerated() {
                event?.setIntegerValueField(.mouseEventClickState, value: Int64((idx / 2) + 1))
                event?.post(tap: .cghidEventTap)
            }
        } else {
            let mouseDown = CGEvent(mouseEventSource: source, mouseType: mouseTypeDown, mouseCursorPosition: cgPoint, mouseButton: button)
            let mouseUp = CGEvent(mouseEventSource: source, mouseType: mouseTypeUp, mouseCursorPosition: cgPoint, mouseButton: button)
            mouseDown?.setIntegerValueField(.mouseEventClickState, value: 1)
            mouseUp?.setIntegerValueField(.mouseEventClickState, value: 1)
            mouseDown?.post(tap: .cghidEventTap)
            mouseUp?.post(tap: .cghidEventTap)
        }
    }
    
    private func moveToAbsolutePosition(x: CGFloat, y: CGFloat) {
        let maxY = desktopFrame == .zero ? NSScreen.screens.reduce(CGFloat(0)) { max($0, $1.frame.maxY) } : desktopFrame.maxY
        let cgPoint = CGPoint(x: x, y: maxY - y)
        CGWarpMouseCursorPosition(cgPoint)
        if let event = CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: cgPoint, mouseButton: .left) {
            event.post(tap: .cgSessionEventTap)
        }
        handleDwellClick(at: CGPoint(x: x, y: y))
    }
    
    private func handleDwellClick(at point: CGPoint) {
        // Dwell only works if looking at screen
        guard isDwellClickEnabled && !isCalibratingRange && isTracking && isLookingAtScreen else { return }
        
        let dist = sqrt(pow(point.x - lastDwellPos.x, 2) + pow(point.y - lastDwellPos.y, 2))
        DispatchQueue.main.async {
            if dist < self.dwellRadius {
                if let start = self.dwellStartTime {
                    let duration = Date().timeIntervalSince(start)
                    let progress = min(1.0, duration / self.dwellDuration)
                    self.dwellOverlay?.update(progress: progress, position: point, isClicking: progress >= 1.0)
                    if duration >= self.dwellDuration {
                        self.triggerMouseClick(at: point)
                        self.dwellStartTime = nil
                    }
                } else {
                    self.dwellStartTime = Date()
                }
            } else {
                self.dwellStartTime = nil
                self.lastDwellPos = point
                self.dwellOverlay?.update(progress: 0, position: point, isClicking: false)
            }
        }
    }
}

// MARK: - Overlay Components
struct DwellProgressView: View {
    var progress: Double
    var isClicking: Bool
    var body: some View {
        ZStack {
            Circle().stroke(Color.white.opacity(0.3), lineWidth: 4).frame(width: 32, height: 32).background(Circle().fill(Color.black.opacity(0.2)))
            Circle().trim(from: 0, to: CGFloat(progress)).stroke(isClicking ? Color.orange : Color.white, style: StrokeStyle(lineWidth: 4, lineCap: .round)).frame(width: 32, height: 32).rotationEffect(.degrees(-90))
        }.animation(.linear(duration: 0.1), value: progress)
    }
}

class DwellOverlayWindow: NSPanel {
    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 40, height: 40), styleMask: [.nonactivatingPanel, .borderless], backing: .buffered, defer: false)
        self.level = .mainMenu + 1
        self.isFloatingPanel = true
        self.backgroundColor = .clear
        self.ignoresMouseEvents = true
        self.contentView = NSHostingView(rootView: DwellProgressView(progress: 0, isClicking: false))
    }
    func update(progress: Double, position: CGPoint, isClicking: Bool) {
        self.setFrameOrigin(CGPoint(x: position.x - 20, y: position.y - 20))
        self.contentView = NSHostingView(rootView: DwellProgressView(progress: progress, isClicking: isClicking))
        if progress > 0 || isClicking { self.orderFront(nil) } else { self.orderOut(nil) }
    }
}
