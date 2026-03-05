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
    static let recognitionControlModeChangedNotification = Notification.Name("AetherRecognitionControlModeChanged")
    private static let recognitionModeOverrideKey = "AetherRecognitionModeOverride"

    enum RecognitionControlMode: String, Sendable {
        case auto
        case command
        case dictation

        var hudMode: HUDRecognitionControlMode {
            switch self {
            case .auto:
                return .auto
            case .command:
                return .command
            case .dictation:
                return .dictation
            }
        }
    }
    
    enum PostureBias: String, Sendable {
        case neutral
        case tiltLeft   // Bias for Dictation
        case tiltRight  // Bias for Command
        case lookLow    // Bias for Dictation (optional, like reading a script)
    }

    private init() {
        // Hotkeys require Accessibility trust. Install the event tap only after permissions are granted.
        // Reset legacy persisted override. Manual mode switch is now focus-follow aware and temporary.
        if persistentRecognitionControlMode != .auto {
            persistentRecognitionControlMode = .auto
        }
        startStabilityTimer()
    }
    
    private var isHotkeyRegistered: Bool = false
    private var stabilityTimer: Timer?
    private var connectionTimer: Timer?
    private var lastDataTime: Date?
    var didLogEventTapKeyDebugHint: Bool = false
    
    private let motionManager = CMHeadphoneMotionManager()
    private let log = GlobalLogger.motion
    
    @Published var isTracking: Bool = false
    @Published var attitudeText: String = "No Data"
    
    // Callback for critical errors (to show UI alerts)
    var onError: ((String) -> Void)?

    // Debug Mode
    @Published var isDebugModeEnabled: Bool = UserDefaults.standard.bool(forKey: "isDebugModeEnabled") {
        didSet {
            UserDefaults.standard.set(isDebugModeEnabled, forKey: "isDebugModeEnabled")
        }
    }

    
    // [Fix] Respect PTT Toggle in Settings
    // If false, the shortcut (Command/Mode) will NOT trigger PTT logic or HUD.
    @Published var isPTTEnabled: Bool = UserDefaults.standard.object(forKey: "isPTTEnabled") as? Bool ?? true {
        didSet { UserDefaults.standard.set(isPTTEnabled, forKey: "isPTTEnabled") }
    }
    
    // Experience Optimization Constants
    private let deadzone: Double = 0.005  // Ignore movements smaller than ~0.3 degrees
    private let accelerationPower: Double = 1.5 // 1.0 is linear, >1.0 is exponential
    
    // Dwell Click State
    @Published var isDwellClickEnabled: Bool = false
    private var dwellStartTime: Date?
    private var lastDwellPos: CGPoint = .zero
    private let dwellRadius: CGFloat = 15.0 // More forgiving radius
    private let dwellDuration: TimeInterval = 0.8 // Seconds
    private let movementThreshold: CGFloat = 2.0 // Min movement to reset timer during dwell
    
    // Dynamic Range Calibration
    @Published var calibrationStatus: String = "Normal"
    
    // Real-time Data for UI Visualization
    @Published var currentHeadYaw: Double = 0.0
    @Published var currentHeadPitch: Double = 0.0
    @Published var currentVelocity: Double = 0.0
    
    private var minYaw: Double = -0.3
    private var maxYaw: Double = 0.3
    private var minPitch: Double = -0.2
    private var maxPitch: Double = 0.2
    private var isCalibratingRange: Bool = false
    
    @Published var currentPostureBias: PostureBias = .neutral
    // Temporary override, usually from AirPods squeeze during a PTT session.
    @Published var transientRecognitionControlMode: RecognitionControlMode? = nil
    private var transientModeAnchorTypingState: Bool?
    private var lastTransientModeSyncAt: Date = .distantPast
    private var transientModeObservedTypingState: Bool?
    private var transientModeObservedAt: Date = .distantPast
    // Persistent control mode selection. Defaults to auto (follow focus).
    @Published var persistentRecognitionControlMode: RecognitionControlMode = HeadMotionManager.loadRecognitionControlModeFromDefaults() {
        didSet { HeadMotionManager.saveRecognitionControlMode(persistentRecognitionControlMode) }
    }
    // Effective priority: session override > persistent selection.
    var effectiveRecognitionControlMode: RecognitionControlMode {
        transientRecognitionControlMode ?? persistentRecognitionControlMode
    }
    // Compatibility accessor for existing bool-based call sites.
    // nil = auto, true = force command, false = force dictation.
    var effectiveRecognitionModeOverride: Bool? {
        switch effectiveRecognitionControlMode {
        case .auto:
            return nil
        case .command:
            return true
        case .dictation:
            return false
        }
    }
    private let postureThresholdRoll: Double = 0.25 // ~14 degrees
    private let postureThresholdPitch: Double = 0.35 // ~20 degrees for "Low"
    
    // Smoothing
    private var currentX: CGFloat = 0
    private var currentY: CGFloat = 0
    private let smoothing: CGFloat = 0.5 // Responsive but steady
    
    // Tilt Scroll
    @Published var isTiltScrollEnabled: Bool = UserDefaults.standard.object(forKey: "isTiltScrollEnabled") as? Bool ?? true {
        didSet {
            UserDefaults.standard.set(isTiltScrollEnabled, forKey: "isTiltScrollEnabled")
        }
    }
    private let tiltScrollThreshold: Double = 0.25 // Radian (~15 degrees)
    private var lastScrollTime: Date = Date()
    
    private var baseYaw: Double = 0
    private var basePitch: Double = 0
    private var isCalibrated: Bool = false
    
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var isAirPodsStreamActive: Bool = false

    // PTT State Tracking (Support multiple input sources)
    private enum PTTSource: Hashable {
        case keyboard(Int)
        case mouse(Int)
    }
    private var activePTTSources: Set<PTTSource> = []
    private var isPTTPressed: Bool { !activePTTSources.isEmpty }
    
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

    // MARK: - Recognition Mode Override Persistence
    private static func loadRecognitionControlModeFromDefaults() -> RecognitionControlMode {
        guard UserDefaults.standard.object(forKey: recognitionModeOverrideKey) != nil else { return .auto }
        let raw = UserDefaults.standard.integer(forKey: recognitionModeOverrideKey)
        switch raw {
        case 1:
            return .command
        case 0:
            return .dictation
        default:
            return .auto
        }
    }

    private static func saveRecognitionControlMode(_ value: RecognitionControlMode) {
        switch value {
        case .command:
            UserDefaults.standard.set(1, forKey: recognitionModeOverrideKey)
        case .dictation:
            UserDefaults.standard.set(0, forKey: recognitionModeOverrideKey)
        case .auto:
            UserDefaults.standard.removeObject(forKey: recognitionModeOverrideKey)
        }
    }
    
    
    // Public API for checking AirPods availability
    // Note: isDeviceMotionAvailable only checks if the device SUPPORTS motion tracking,
    // not if AirPods are actually connected. We check if motion is currently active.
    var isAirPodsAvailable: Bool {
        // If already tracking, AirPods are definitely connected
        return motionManager.isDeviceMotionActive || isAirPodsStreamActive
    }
    
    func startTracking() {
        guard !isTracking else { return }
        
        // CRITICAL: Verify AirPods are actually available before starting
        // isDeviceMotionAvailable checks if the device SUPPORTS motion tracking
        // If it returns false, AirPods are definitely not connected
        if !motionManager.isDeviceMotionAvailable {
            let msg = String(localized: "motion.error.airpods_not_detected")
            attitudeText = "AirPods not connected"
            os_log("Cannot start tracking: AirPods not available", log: log, type: .error)
            HUDManager.shared.showTemporary(message: "❌ No AirPods Detected")
            onError?(msg)
            return // BLOCK tracking if AirPods not available
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
        
        // Start connection timeout timer (5 seconds)
        DispatchQueue.main.async {
            self.attitudeText = "Connecting..."
        }
        
        connectionTimer?.invalidate()
        connectionTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: false) { [weak self] _ in
            self?.handleConnectionTimeout()
        }
        
        motionManager.startDeviceMotionUpdates(to: .main) { [weak self] motion, error in
            guard let self = self else { return }
            
            if let error = error {
                DispatchQueue.main.async { self.attitudeText = "AirPods Error: \(error.localizedDescription)" }
                self.stopTrackingInternal() // Clean up
                return
            }
            
            guard let attitude = motion?.attitude else { return }
            
            // --- First Packet Connection Logic ---
            if !self.isTracking {
                // Safety: If connectionTimer is nil, we must have stopped manually.
                // Ignore this packet to prevent zombie tracking state.
                guard self.connectionTimer != nil else { return }
                
                // We received the first valid data packet! Connection successful.
                self.connectionTimer?.invalidate()
                self.connectionTimer = nil
                self.isTracking = true
                self.updateNowPlayingInfo()
                os_log("Aether: Connection Established (First Data Received)", log: self.log)
                
                // Reset lastDataTime to now
                self.lastDataTime = Date()
                
                DispatchQueue.main.async {
                    self.attitudeText = "Tracking..."
                    self.dwellOverlay = DwellOverlayWindow()
                }
            }
            // -------------------------------------
            
            if !self.isAirPodsStreamActive {
                self.isAirPodsStreamActive = true
                os_log("AirPods Stream Detected", log: self.log)
            }
            
            // Update Posture Bias based on Roll and Pitch
            self.updatePostureBias(attitude: attitude)
            
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
                self.maxPitch = max(self.maxPitch, offPitch)
            }
            
            // Heartbeat
            self.lastDataTime = Date()
            
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
            
            // Update UI visualization data
            DispatchQueue.main.async {
                self.currentHeadYaw = offYaw
                self.currentHeadPitch = offPitch
                // Simple velocity approximation based on distance from center (or delta if we tracked it)
                // For "Matrix" visual, magnitude of movement is often more interesting than derivative
                self.currentVelocity = sqrt(pow(offYaw, 2) + pow(offPitch, 2))
            }
            
            // Handle Tilt Scroll
            self.handleTiltScroll(pitch: offPitch)
        }
    }
    
    private func updatePostureBias(attitude: CMAttitude) {
        // We use Roll for Left/Right tilt
        // Roll: positive is Tilt Right, negative is Tilt Left (approx)
        let roll = attitude.roll
        let pitch = attitude.pitch - basePitch
        
        var newBias: PostureBias = .neutral
        
        if roll > postureThresholdRoll {
            newBias = .tiltRight
        } else if roll < -postureThresholdRoll {
            newBias = .tiltLeft
        } else if pitch > postureThresholdPitch {
            newBias = .lookLow
        }
        
        if newBias != currentPostureBias {
            DispatchQueue.main.async {
                self.currentPostureBias = newBias
                if self.isDebugModeEnabled {
                    os_log("Posture Bias Changed: %{public}@", log: self.log, type: .debug, newBias.rawValue)
                }
            }
        }
    }
    
    private func handleConnectionTimeout() {
        guard !isTracking else { return } // Already connected
        os_log("Aether: Connection Timeout - No data received", log: log, type: .error)
        
        let msg = String(localized: "motion.error.connection_timeout")
        HUDManager.shared.showTemporary(message: "❌ Connection Timeout")
        onError?(msg)
        
        stopTrackingInternal()
        
        DispatchQueue.main.async {
            self.attitudeText = "Connection Failed"
        }
    }
    
    func stopTracking() {
        stopTrackingInternal()
    }

    private func stopTrackingInternal() {
        connectionTimer?.invalidate()
        connectionTimer = nil
        
        motionManager.stopDeviceMotionUpdates()
        disableAirPodsCommands() // Clean up commands
        
        DispatchQueue.main.async {
            self.dwellOverlay?.orderOut(nil)
            self.dwellOverlay = nil
            // Don't overwrite "Connection Failed" if that was the reason
            if self.isTracking { 
                self.attitudeText = "Stopped" 
            }
            self.isTracking = false
        }
        
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
    func clickLeft() { 
        if isDebugModeEnabled { os_log("ACTION: Click Left", log: log, type: .debug) }
        triggerMouseClick(at: CGPoint(x: currentX, y: currentY), button: .left) 
    }
    func clickRight() { 
        if isDebugModeEnabled { os_log("ACTION: Click Right", log: log, type: .debug) }
        triggerMouseClick(at: CGPoint(x: currentX, y: currentY), button: .right) 
    }
    func doubleClick() { 
        if isDebugModeEnabled { os_log("ACTION: Double Click", log: log, type: .debug) }
        triggerMouseClick(at: CGPoint(x: currentX, y: currentY), button: .left, doubleClick: true) 
    }

    func scroll(dx: Int, dy: Int) {
        AutomationOutputs.shared.scroll(dx: dx, dy: dy)
        // No HUD for continuous scroll to avoid spam
    }

    func scrollToTop() {
        AutomationOutputs.shared.scroll(dx: 0, dy: -100000)
        HUDManager.shared.showTemporary(message: "⬆️ Scroll Top")
    }

    func scrollToBottom() {
        AutomationOutputs.shared.scroll(dx: 0, dy: 100000)
        HUDManager.shared.showTemporary(message: "⬇️ Scroll Bottom")
    }

    func dragStart() {
        // Use current cursor location (nil) to avoid coordinate flipping issues
        AutomationOutputs.shared.drag(start: true, at: nil)
        HUDManager.shared.showTemporary(message: "✊ Drag Start")
    }

    func dragEnd() {
        // Use current cursor location (nil) to avoid coordinate flipping issues
        AutomationOutputs.shared.drag(start: false, at: nil)
        HUDManager.shared.showTemporary(message: "🖐 Drag Drop")
    }

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
    
    private func handleTiltScroll(pitch: Double) {
        guard isTiltScrollEnabled else { return }
        
        var scrollDy: Int = 0
        let now = Date()
        let dt = now.timeIntervalSince(lastScrollTime)
        
        // Rate limit: Max 60Hz
        if dt < 0.016 { return } 
        lastScrollTime = now
        
        if pitch < -tiltScrollThreshold {
            // Looking UP -> Scroll DOWN? Or Scroll UP?
            // Convention: Head Up -> Page Up -> Scroll Content Down (dy > 0)
            // macOS Natural Scrolling: Swipe Down = Content Up.
            // Let's assume standard behavior:
            // Head Up (Negative Pitch) -> Scroll Up (dy > 0)
            
            let amount = pow((abs(pitch) - tiltScrollThreshold) * 10, 1.5)
            scrollDy = Int(amount * 5) 
        } else if pitch > tiltScrollThreshold {
            // Looking DOWN -> Scroll Down (dy < 0)
            let amount = pow((pitch - tiltScrollThreshold) * 10, 1.5)
            scrollDy = -Int(amount * 5)
        }
        
        if scrollDy != 0 {
            if isDebugModeEnabled {
                os_log("Tilt Scroll: Pitch %.3f -> dy %d", log: log, type: .debug, pitch, scrollDy)
            }
            AutomationOutputs.shared.scroll(dx: 0, dy: scrollDy)
        }
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
        
        updateNowPlayingInfo()
    }

    private func updateNowPlayingInfo() {
        var nowPlayingInfo = [String: Any]()
        nowPlayingInfo[MPMediaItemPropertyTitle] = "Aether Motion Control"
        nowPlayingInfo[MPMediaItemPropertyArtist] = "Head Tracking Active"
        nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackRate] = 1.0 // Appears as "Playing"
        
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
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

    @MainActor
    func toggleRecognitionInputControlMode(source: String = "hotkey", persist: Bool = true) {
        let currentlyTyping = HUDManager.shared.lastKnownTypingState()
        let currentResolvedMode = resolvedRecognitionControlMode(currentlyTyping: currentlyTyping)
        let nextMode: RecognitionControlMode = (currentResolvedMode == .command) ? .dictation : .command

        // Guard: dictation mode requires an actual text-input focus.
        // Control mode can always work without text field focus.
        if nextMode == .dictation && !currentlyTyping {
            let isChinese = Locale.current.identifier.hasPrefix("zh")
            let message = isChinese ? "未检测到输入框，已切换到控制模式" : "No input field. Switched to Control Mode"
            transientRecognitionControlMode = nil
            transientModeAnchorTypingState = nil
            transientModeObservedTypingState = nil
            transientModeObservedAt = .distantPast
            persistentRecognitionControlMode = .auto
            postRecognitionControlModeChanged(source: source)
            HUDManager.shared.showTemporary(
                message: message,
                recognitionControlMode: .command,
                duration: 1.1
            )
            os_log("Recognition Mode Toggle blocked (%{public}@, persist=%{public}@): no input focus",
                   log: log, type: .info, source, persist ? "yes" : "no")
            return
        }

        // Manual switch is temporary: keep auto as the persistent policy and apply a transient override.
        persistentRecognitionControlMode = .auto
        transientRecognitionControlMode = nextMode
        transientModeAnchorTypingState = currentlyTyping
        transientModeObservedTypingState = currentlyTyping
        transientModeObservedAt = Date()

        let isChinese = Locale.current.identifier.hasPrefix("zh")
        let isCommandMode = nextMode == .command
        let message = isCommandMode
            ? (isChinese ? "已切换到控制模式" : "Switched to Control Mode")
            : (isChinese ? "已切换到输入模式" : "Switched to Dictation Mode")
        postRecognitionControlModeChanged(source: source)
        HUDManager.shared.showTemporary(
            message: message,
            recognitionControlMode: nextMode.hudMode,
            duration: 1.2
        )
        os_log("Recognition Mode Override Toggled (%{public}@, persist=%{public}@): %{public}@",
               log: log, type: .info, source, persist ? "yes" : "no", isCommandMode ? "command" : "dictation")
    }

    private func postRecognitionControlModeChanged(source: String) {
        NotificationCenter.default.post(
            name: Self.recognitionControlModeChangedNotification,
            object: nil,
            userInfo: ["source": source]
        )
    }

    @MainActor
    private func exitDictationModeOnEscape(source: String = "escape-key") {
        let currentlyTyping = HUDManager.shared.lastKnownTypingState()
        let resolvedMode = resolvedRecognitionControlMode(currentlyTyping: currentlyTyping)
        guard resolvedMode == .dictation else { return }

        // Legacy expectation: pressing Esc should force control mode immediately.
        persistentRecognitionControlMode = .auto
        transientRecognitionControlMode = .command
        transientModeAnchorTypingState = currentlyTyping
        transientModeObservedTypingState = currentlyTyping
        transientModeObservedAt = Date()

        let isChinese = Locale.current.identifier.hasPrefix("zh")
        let message = isChinese ? "已退出输入模式" : "Exited Dictation Mode"
        postRecognitionControlModeChanged(source: source)
        HUDManager.shared.showTemporary(
            message: message,
            recognitionControlMode: .command,
            duration: 1.2
        )
        os_log("Recognition Mode escape exit (%{public}@): mode=%{public}@",
               log: log, type: .info, source, effectiveRecognitionControlMode.rawValue)
    }
    
    private func handleClickCommand() {
        // If PTT is active, Squeeze acts as a mode toggle/inverter
        if isPTTPressed {
            os_log("AirPods: Squeeze during PTT -> Toggle Recognition Mode", log: log)
            DispatchQueue.main.async {
                self.toggleRecognitionInputControlMode(source: "airpods-ptt-squeeze", persist: false)
                // Audio feedback for mode switch
                NSSound.beep()
            }
            return
        }

        guard isTracking, isLookingAtScreen else { return }

        // Normal operation: Single Press -> Left Click
        os_log("AirPods: Single Press -> Left Click", log: log)
        DispatchQueue.main.async { self.triggerMouseClick(at: CGPoint(x: self.currentX, y: self.currentY)) }
    }
    
    // ... triggerMouseClick (unchanged) ...
    
    private func triggerMouseClick(at point: CGPoint, button: CGMouseButton = .left, doubleClick: Bool = false) {
        if isDebugModeEnabled {
            os_log("Trigger Click (Request): (%.1f, %.1f) Button: %d", log: log, type: .debug, point.x, point.y, button.rawValue)
        }
        
        // Audio Feedback
        NSSound(named: "Tink")?.play()

        // Fix: Use current system cursor location to ensure accuracy.
        // Users expect click to happen where they see the cursor.
        // Coordinate conversion errors are bypassed this way.
        guard let currentCursor = CGEvent(source: nil)?.location else {
            os_log("Failed to get cursor location for click", log: log, type: .error)
            return
        }
        
        if isDebugModeEnabled {
             os_log("Trigger Click (Actual): (%.1f, %.1f)", log: log, type: .debug, currentCursor.x, currentCursor.y)
        }

        AutomationOutputs.shared.mouseClick(at: currentCursor, button: button, clickCount: doubleClick ? 2 : 1)
    }
    
    private func moveToAbsolutePosition(x: CGFloat, y: CGFloat) {
        let maxY = desktopFrame == .zero ? NSScreen.screens.reduce(CGFloat(0)) { max($0, $1.frame.maxY) } : desktopFrame.maxY
        AutomationOutputs.shared.moveCursor(to: CGPoint(x: x, y: y), desktopMaxY: maxY)
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

    @MainActor
    func setGlobalHotkeysEnabled(_ enabled: Bool) {
        if !Thread.isMainThread {
            DispatchQueue.main.async { [weak self] in
                self?.setGlobalHotkeysEnabled(enabled)
            }
            return
        }

        if enabled {
            installHotkeysIfPossible()
        } else {
            uninstallHotkeys()
        }
    }

    private func installHotkeysIfPossible() {
        if !Thread.isMainThread {
            DispatchQueue.main.async { [weak self] in self?.installHotkeysIfPossible() }
            return
        }

        guard !isHotkeyRegistered else { return }

        guard AXIsProcessTrusted() else {
            GlobalLogger.lifecycle.info("HeadMotionManager: Accessibility not trusted yet; skipping event tap install.")
            return
        }

        // Monitor global events for hotkeys (Shift+Ctrl+S for Emergency Stop, Ctrl+Opt+V for PTT)
        GlobalLogger.lifecycle.info("HeadMotionManager: Setting up hotkeys (Event Tap)...")
        
        let mask: CGEventMask =
            (1 << CGEventType.keyDown.rawValue) |
            (1 << CGEventType.keyUp.rawValue) |
            (1 << CGEventType.flagsChanged.rawValue) |
            (1 << CGEventType.leftMouseDown.rawValue) |
            (1 << CGEventType.rightMouseDown.rawValue) |
            (1 << CGEventType.otherMouseDown.rawValue) |
            (1 << CGEventType.otherMouseUp.rawValue)
        
        func callback(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent, refcon: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
            guard let refcon else { return Unmanaged.passUnretained(event) }
            let manager = Unmanaged<HeadMotionManager>.fromOpaque(refcon).takeUnretainedValue()

            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                if let tap = manager.eventTap {
                    CGEvent.tapEnable(tap: tap, enable: true)
                    GlobalLogger.lifecycle.error("HeadMotionManager: Event tap disabled (\(type.rawValue)); re-enabled.")
                } else {
                    GlobalLogger.lifecycle.error("HeadMotionManager: Event tap disabled (\(type.rawValue)); tap ref missing.")
                }
                return Unmanaged.passUnretained(event)
            }
            
            // Log every few events just to prove we are alive (throttled)
            // GlobalLogger.input.debug("Event Tap Callback: \(type.rawValue)")
            
            if type == .flagsChanged {
                // ... logic kept for reference ...
            }
            
            let flags = event.flags
            let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
            
            // Trace modifiers for debugging
            // if flags.contains(.maskControl) { GlobalLogger.input.debug("Modifier: Ctrl") }

            if type == .keyDown {
                if !manager.didLogEventTapKeyDebugHint {
                    manager.didLogEventTapKeyDebugHint = true
                    GlobalLogger.input.debug("Event Tap active (debug key logging disabled by default).")
                }

                // Bare Esc should exit explicit dictation mode (legacy behavior).
                let modifierMask: UInt64 =
                    CGEventFlags.maskControl.rawValue |
                    CGEventFlags.maskAlternate.rawValue |
                    CGEventFlags.maskShift.rawValue |
                    CGEventFlags.maskCommand.rawValue
                let masked = flags.rawValue & modifierMask
                if keyCode == Int64(kVK_Escape), masked == 0 {
                    DispatchQueue.main.async {
                        manager.exitDictationModeOnEscape()
                    }
                }

                // Dynamic hotkey matching via HotkeyManager
                if let action = HotkeyManager.shared.matchKeyDown(keyCode: keyCode, flags: flags) {
                    switch action {
                    case .toggleTracking:
                        if manager.isTracking {
                            GlobalLogger.input.info("Hotkey: Stop Tracking")
                            HUDManager.shared.showTemporary(message: "⏹ 停止追踪")
                            DispatchQueue.main.async { manager.stopTracking() }
                        } else {
                            GlobalLogger.input.info("Hotkey: Start Tracking")
                            HUDManager.shared.showTemporary(message: "▶️ 启动追踪")
                            DispatchQueue.main.async { manager.startTracking() }
                        }
                        return nil

                    case .connectionLock:
                        GlobalLogger.input.info("Hotkey: Toggle Connection Lock")
                        HUDManager.shared.showTemporary(message: "🔒 Connection Lock")
                        NotificationCenter.default.post(name: .toggleConnectionLock, object: nil)
                        return nil

                    case .toggleInputControlMode:
                        GlobalLogger.input.info("Hotkey: Toggle Input/Control Mode")
                        DispatchQueue.main.async {
                            manager.toggleRecognitionInputControlMode(source: "keyboard-hotkey", persist: true)
                        }
                        return nil

                    case .pushToTalk:
                        // If PTT is disabled, do not consume the event.
                        guard manager.isPTTEnabled else { return Unmanaged.passUnretained(event) }

                        let source = PTTSource.keyboard(Int(keyCode))
                        guard !manager.activePTTSources.contains(source) else { return nil }
                        
                        let wasPressed = manager.isPTTPressed
                        manager.activePTTSources.insert(source)
                        
                        if !wasPressed {
                            GlobalLogger.input.info("Hotkey: PTT DOWN Detected (Keyboard)")
                            manager.transientRecognitionControlMode = nil // Reset temporary override on new PTT session
                            manager.transientModeAnchorTypingState = nil
                            manager.transientModeObservedTypingState = nil
                            manager.transientModeObservedAt = .distantPast
                            NotificationCenter.default.post(
                                name: HeadMotionManager.pttDownNotification,
                                object: nil
                            )
                        }
                        return nil // Consumes event (Good)
                    }
                }
            }
            
            if type == .keyUp {
                // PTT Up — match the configured PTT key code OR just check if this key is in active sources
                // Note: HotkeyManager might map multiple keys? Assuming simple 1-1 for now.
                let pttKeyCode = HotkeyManager.shared.pttBinding.keyCode
                let source = PTTSource.keyboard(Int(keyCode))
                
                // If this specific key was part of PTT activation
                if manager.activePTTSources.contains(source) || (keyCode == Int64(pttKeyCode) && manager.isPTTPressed) {
                     // Cleanup legacy or current
                     manager.activePTTSources.remove(source)
                     // If pttKeyCode matched but wasn't in set (legacy recovery?), remove it too.
                     if keyCode == Int64(pttKeyCode) {
                          // Try removing generic if needed, but 'source' covers it.
                     }
                     
                     if !manager.isPTTPressed {
                         GlobalLogger.input.info("Hotkey: PTT UP Detected (Keyboard)")
                         NotificationCenter.default.post(
                             name: HeadMotionManager.pttUpNotification,
                             object: nil
                         )
                     }
                     return nil
                }
            }
            
            if type == .leftMouseDown || type == .rightMouseDown || type == .otherMouseDown {
                DispatchQueue.main.async {
                    manager.clearTransientRecognitionControlModeForInputRefocus(source: "mouse-input-refocus")
                }
            }

            // Mouse Button Hotkeys (Dynamic)
            if type == .otherMouseDown {
                let btn = Int(event.getIntegerValueField(.mouseEventButtonNumber))
                
                if let action = HotkeyManager.shared.matchMouseDown(button: btn, flags: flags) {
                    switch action {
                    case .toggleTracking:
                        if manager.isTracking {
                            GlobalLogger.input.info("Mouse Hotkey: Stop Tracking")
                            HUDManager.shared.showTemporary(message: "⏹ 停止追踪")
                            DispatchQueue.main.async { manager.stopTracking() }
                        } else {
                            GlobalLogger.input.info("Mouse Hotkey: Start Tracking")
                            HUDManager.shared.showTemporary(message: "▶️ 启动追踪")
                            DispatchQueue.main.async { manager.startTracking() }
                        }
                        return nil
                        
                    case .connectionLock:
                        GlobalLogger.input.info("Mouse Hotkey: Toggle Connection Lock")
                        HUDManager.shared.showTemporary(message: "🔒 Connection Lock")
                        NotificationCenter.default.post(name: .toggleConnectionLock, object: nil)
                        return nil

                    case .toggleInputControlMode:
                        GlobalLogger.input.info("Mouse Hotkey: Toggle Input/Control Mode")
                        DispatchQueue.main.async {
                            manager.toggleRecognitionInputControlMode(source: "mouse-hotkey", persist: true)
                        }
                        return nil

                    case .pushToTalk:
                        // [Fix] STRICT CHECK: If PTT is disabled, bypass.
                        guard manager.isPTTEnabled else { break }
                        
                        let source = PTTSource.mouse(btn)
                        if !manager.activePTTSources.contains(source) {
                            let wasPressed = manager.isPTTPressed
                            manager.activePTTSources.insert(source)
                            
                            if !wasPressed {
                                GlobalLogger.input.info("Mouse PTT DOWN Detected (Button \(btn))")
                                manager.transientRecognitionControlMode = nil // Reset temporary override
                                manager.transientModeAnchorTypingState = nil
                                manager.transientModeObservedTypingState = nil
                                manager.transientModeObservedAt = .distantPast
                                NotificationCenter.default.post(
                                    name: HeadMotionManager.pttDownNotification,
                                    object: nil
                                )
                            }
                        }
                        return nil
                    }
                }
            }
            
            if type == .otherMouseUp {
                let btn = Int(event.getIntegerValueField(.mouseEventButtonNumber))
                let source = PTTSource.mouse(btn)
                
                if manager.activePTTSources.contains(source) {
                    manager.activePTTSources.remove(source)
                    
                    if !manager.isPTTPressed {
                        GlobalLogger.input.info("Mouse PTT UP Detected (Button \(btn))")
                        NotificationCenter.default.post(
                            name: HeadMotionManager.pttUpNotification,
                            object: nil
                        )
                    }
                    return nil
                }
            }
            
            return Unmanaged.passUnretained(event)
        }
        
        let unsafeSelf = Unmanaged.passUnretained(self).toOpaque()

        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap,
                                          place: .headInsertEventTap,
                                          options: .defaultTap,
                                          eventsOfInterest: mask,
                                          callback: callback,
                                          userInfo: unsafeSelf) else {
            GlobalLogger.lifecycle.error("HeadMotionManager: Failed to create event tap")
            return
        }
        
        GlobalLogger.lifecycle.info("HeadMotionManager: Event Tap Created Successfully")
        
        self.eventTap = tap
        self.runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        isHotkeyRegistered = true
    }

    private func uninstallHotkeys() {
        if !Thread.isMainThread {
            DispatchQueue.main.async { [weak self] in self?.uninstallHotkeys() }
            return
        }

        guard isHotkeyRegistered else { return }

        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
        }

        eventTap = nil
        runLoopSource = nil
        isHotkeyRegistered = false
        activePTTSources.removeAll()

        GlobalLogger.lifecycle.info("HeadMotionManager: Hotkeys uninstalled.")
    }

    private func startStabilityTimer() {
        // Monitor connection health every 1.0s
        stabilityTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }

            // Retry hotkey installation if initial setup was missed during startup race.
            if AXIsProcessTrusted(), !self.isHotkeyRegistered {
                self.installHotkeysIfPossible()
            }

            // Event taps can be disabled by the system after callback timeout or user input transitions.
            // Keep hotkeys resilient by auto-recovering a disabled tap.
            if self.isHotkeyRegistered, let tap = self.eventTap, !CGEvent.tapIsEnabled(tap: tap) {
                GlobalLogger.lifecycle.error("HeadMotionManager: Event tap unexpectedly disabled; attempting auto-reenable.")
                CGEvent.tapEnable(tap: tap, enable: true)
            }

            guard self.isTracking else { return }
            
            // 1. Immediate Availability Check (e.g. Switched to iPhone)
            if !self.motionManager.isDeviceMotionAvailable {
                os_log("Monitor: AirPods capability lost (Switched device?)", log: self.log, type: .error)
                let msg = String(localized: "motion.error.airpods_disconnected") // "AirPods disconnected or switched to another device."
                HUDManager.shared.showTemporary(message: "⚠️ AirPods Disconnected")
                self.onError?(msg)
                self.stopTrackingInternal()
                DispatchQueue.main.async { self.attitudeText = "Disconnected" }
                return
            }
            
            // 2. Liveness Check (Timeout)
            if let lastTime = self.lastDataTime, Date().timeIntervalSince(lastTime) > 5.0 {
                os_log("Monitor: No data for 5s (Signal lost)", log: self.log, type: .error)
                let msg = String(localized: "motion.error.connection_lost") // "Connection lost. No data received."
                HUDManager.shared.showTemporary(message: "⚠️ Connection Lost")
                self.onError?(msg)
                self.stopTrackingInternal()
                DispatchQueue.main.async { self.attitudeText = "Signal Lost" }
                return
            }
        }
    }

    private func resolvedRecognitionControlMode(currentlyTyping: Bool? = nil) -> RecognitionControlMode {
        switch effectiveRecognitionControlMode {
        case .command, .dictation:
            return effectiveRecognitionControlMode
        case .auto:
            return (currentlyTyping ?? HUDManager.shared.lastKnownTypingState()) ? .dictation : .command
        }
    }

    func refreshTransientRecognitionControlModeIfNeeded(source: String = "focus-sync") {
        if !Thread.isMainThread {
            DispatchQueue.main.async { [weak self] in
                self?.refreshTransientRecognitionControlModeIfNeeded(source: source)
            }
            return
        }

        guard transientRecognitionControlMode != nil else {
            transientModeAnchorTypingState = nil
            transientModeObservedTypingState = nil
            transientModeObservedAt = .distantPast
            return
        }
        // Respect future explicit persistent preferences if introduced.
        guard persistentRecognitionControlMode == .auto else { return }

        let now = Date()
        if now.timeIntervalSince(lastTransientModeSyncAt) < 0.12 {
            return
        }
        lastTransientModeSyncAt = now

        guard let anchor = transientModeAnchorTypingState else { return }
        let currentlyTyping = HUDManager.shared.lastKnownTypingState()
        if transientModeObservedTypingState != currentlyTyping {
            transientModeObservedTypingState = currentlyTyping
            transientModeObservedAt = now
            return
        }
        guard now.timeIntervalSince(transientModeObservedAt) >= 0.45 else { return }
        guard currentlyTyping != anchor else { return }

        transientRecognitionControlMode = nil
        transientModeAnchorTypingState = nil
        transientModeObservedTypingState = nil
        transientModeObservedAt = .distantPast
        postRecognitionControlModeChanged(source: source)
        os_log("Recognition Mode transient override cleared (%{public}@): focus context changed",
               log: log, type: .info, source)
    }

    @MainActor
    private func clearTransientRecognitionControlModeForInputRefocus(source: String) {
        guard transientRecognitionControlMode == .command else { return }
        guard persistentRecognitionControlMode == .auto else { return }
        guard HUDManager.shared.lastKnownTypingState() else { return }

        transientRecognitionControlMode = nil
        transientModeAnchorTypingState = nil
        transientModeObservedTypingState = nil
        transientModeObservedAt = .distantPast
        postRecognitionControlModeChanged(source: source)
        os_log("Recognition Mode transient override cleared (%{public}@): refocused typing input",
               log: log, type: .info, source)
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
