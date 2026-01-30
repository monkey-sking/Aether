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
    
    // Store aggregate desktop dimensions
    private var desktopFrame: NSRect = .zero
    
    // UI Overlay
    private var dwellOverlay: DwellOverlayWindow? = nil
    
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
            
            if self.isCalibratingRange {
                self.minYaw = min(self.minYaw, offYaw)
                self.maxYaw = max(self.maxYaw, offYaw)
                self.minPitch = min(self.minPitch, offPitch)
                self.maxPitch = max(self.maxPitch, offPitch)
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
        DispatchQueue.main.async {
            self.dwellOverlay?.orderOut(nil)
            self.dwellOverlay = nil
        }
        isTracking = false
        isCalibrated = false
        isCalibratingRange = false
        isAirPodsStreamActive = false
        os_log("Aether: Stopped tracking", log: log)
    }
    
    func toggleTracking() {
        if isTracking {
            stopTracking()
        } else {
            startTracking()
        }
    }
    
    func finishCalibration() {
        isCalibratingRange = false
        calibrationStatus = "Normal"
        os_log("Aether: Calibration Finished", log: log)
    }
    
    private func setupHotkeys() {
        let eventMask = (1 << CGEventType.keyDown.rawValue)
        
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(eventMask),
            callback: { (proxy, type, event, refcon) -> Unmanaged<CGEvent>? in
                guard let refcon = refcon else { return Unmanaged.passRetained(event) }
                let manager = Unmanaged<HeadMotionManager>.fromOpaque(refcon).takeUnretainedValue()
                
                let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
                let flags = event.flags
                
                // New Hotkey: Control + Option + S (Keycode 1)
                let isOptCtrl = flags.contains(.maskAlternate) && flags.contains(.maskControl)
                
                if isOptCtrl && keyCode == 1 {
                    os_log("Hotkey: Control+Option+S detected", log: manager.log)
                    DispatchQueue.main.async {
                        manager.toggleTracking()
                    }
                    return nil
                }
                return Unmanaged.passRetained(event)
            },
            userInfo: UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        ) else {
            os_log("Failed to create EventTap - Still waiting for permissions", log: log)
            return
        }
        
        self.eventTap = tap
        self.runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        
        os_log("Hotkey: Registered via EventTap", log: self.log)
        self.isHotkeyRegistered = true
    }
    
    private func startStabilityTimer() {
        stabilityTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            self?.checkStability()
        }
    }
    
    private func checkStability() {
        if !isHotkeyRegistered {
            setupHotkeys()
        }
        
        // Passive connection check
        if isTracking && !motionManager.isDeviceMotionAvailable {
            os_log("Stability: AirPods lost hardware availability", log: log)
            DispatchQueue.main.async {
                self.stopTracking()
                self.attitudeText = "AirPods Lost"
            }
        }
    }
    
    private func setupAirPodsCommands() {
        let commandCenter = MPRemoteCommandCenter.shared()
        
        let handlers = [commandCenter.playCommand, commandCenter.pauseCommand, commandCenter.togglePlayPauseCommand]
        for handler in handlers {
            handler.isEnabled = true
            handler.addTarget { [weak self] _ in
                guard let self = self, self.isTracking else { return .commandFailed }
                os_log("AirPods: Single Press -> Left Click", log: self.log)
                DispatchQueue.main.async { self.triggerMouseClick(at: CGPoint(x: self.currentX, y: self.currentY)) }
                return .success
            }
        }
        
        commandCenter.nextTrackCommand.isEnabled = true
        commandCenter.nextTrackCommand.addTarget { [weak self] _ in
            guard let self = self, self.isTracking else { return .commandFailed }
            os_log("AirPods: Double Press -> Right Click", log: self.log)
            DispatchQueue.main.async { self.triggerMouseClick(at: CGPoint(x: self.currentX, y: self.currentY), button: .right) }
            return .success
        }
        
        commandCenter.previousTrackCommand.isEnabled = true
        commandCenter.previousTrackCommand.addTarget { [weak self] _ in
            guard let self = self, self.isTracking else { return .commandFailed }
            os_log("AirPods: Triple Press -> Double Click", log: self.log)
            DispatchQueue.main.async { self.triggerMouseClick(at: CGPoint(x: self.currentX, y: self.currentY), doubleClick: true) }
            return .success
        }
    }
    
    private func triggerMouseClick(at point: CGPoint, button: CGMouseButton = .left, doubleClick: Bool = false) {
        guard let primaryScreen = NSScreen.screens.first else { return }
        let maxY = NSMaxY(primaryScreen.frame)
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
        guard let primaryScreen = NSScreen.screens.first else { return }
        let maxY = NSMaxY(primaryScreen.frame)
        let cgPoint = CGPoint(x: x, y: maxY - y)
        CGWarpMouseCursorPosition(cgPoint)
        if let event = CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: cgPoint, mouseButton: .left) {
            event.post(tap: .cgSessionEventTap)
        }
        handleDwellClick(at: CGPoint(x: x, y: y))
    }
    
    private func handleDwellClick(at point: CGPoint) {
        guard isDwellClickEnabled && !isCalibratingRange && isTracking else { return }
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
