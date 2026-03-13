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
    private static let headsetSinglePressActionKey = "AetherHeadsetSinglePressAction"
    private static let headsetDoublePressActionKey = "AetherHeadsetDoublePressAction"
    private static let headsetTriplePressActionKey = "AetherHeadsetTriplePressAction"
    private static let autoStartTrackingOnHeadsetConnectionKey = "AetherAutoStartTrackingOnHeadsetConnection"
    private static let showPostureGuideBeforeTrackingKey = "AetherShowPostureGuideBeforeTracking"
    private static let headGestureToggleEnabledKey = "AetherHeadGestureToggleEnabled"
    private static let headGestureNodActionKey = "AetherHeadGestureNodAction"
    private static let headGestureShakeActionKey = "AetherHeadGestureShakeAction"

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

    enum HeadsetPressKind: String, CaseIterable, Identifiable, Sendable {
        case single
        case double
        case triple

        var id: String { rawValue }

        var label: String {
            switch self {
            case .single:
                return String(localized: "headset.press.single")
            case .double:
                return String(localized: "headset.press.double")
            case .triple:
                return String(localized: "headset.press.triple")
            }
        }

        var eventSource: String {
            switch self {
            case .single:
                return "airpods-single-press"
            case .double:
                return "airpods-double-press"
            case .triple:
                return "airpods-triple-press"
            }
        }
    }

    enum HeadsetPressAction: String, CaseIterable, Identifiable, Sendable {
        case none
        case toggleLanguage
        case connectionLock
        case toggleShortcutPanel
        case toggleInputControlMode
        case toggleTracking

        var id: String { rawValue }

        static let allCases: [HeadsetPressAction] = [
            .none,
            .toggleLanguage,
            .toggleShortcutPanel,
            .toggleInputControlMode,
            .toggleTracking
        ]

        var hotkeyAction: HotkeyAction? {
            switch self {
            case .none:
                return nil
            case .toggleLanguage:
                return .toggleLanguage
            case .connectionLock:
                return .connectionLock
            case .toggleShortcutPanel:
                return .toggleShortcutPanel
            case .toggleInputControlMode:
                return .toggleInputControlMode
            case .toggleTracking:
                return .toggleTracking
            }
        }

        var label: String {
            switch self {
            case .none:
                return String(localized: "headset.action.none")
            case .toggleLanguage, .connectionLock, .toggleShortcutPanel, .toggleInputControlMode, .toggleTracking:
                return hotkeyAction?.label ?? rawValue
            }
        }

        var helperText: String {
            switch self {
            case .none:
                return String(localized: "headset.action.none.detail")
            case .toggleLanguage, .connectionLock, .toggleShortcutPanel, .toggleInputControlMode, .toggleTracking:
                return hotkeyAction?.helperText ?? ""
            }
        }
    }

    enum HeadGestureKind: String, CaseIterable, Identifiable, Sendable {
        case nod
        case shake

        var id: String { rawValue }

        var label: String {
            switch self {
            case .nod:
                return String(localized: "head_gesture.kind.nod")
            case .shake:
                return String(localized: "head_gesture.kind.shake")
            }
        }
    }

    enum HeadGestureAction: String, CaseIterable, Identifiable, Sendable {
        case none
        case toggleLanguage
        case toggleShortcutPanel
        case toggleInputControlMode
        case toggleTracking

        var id: String { rawValue }

        static let allCases: [HeadGestureAction] = [
            .none,
            .toggleInputControlMode,
            .toggleTracking,
            .toggleShortcutPanel,
            .toggleLanguage
        ]

        var hotkeyAction: HotkeyAction? {
            switch self {
            case .none:
                return nil
            case .toggleLanguage:
                return .toggleLanguage
            case .toggleShortcutPanel:
                return .toggleShortcutPanel
            case .toggleInputControlMode:
                return .toggleInputControlMode
            case .toggleTracking:
                return .toggleTracking
            }
        }

        var label: String {
            switch self {
            case .none:
                return String(localized: "head_gesture.action.none")
            case .toggleLanguage, .toggleShortcutPanel, .toggleInputControlMode, .toggleTracking:
                return hotkeyAction?.label ?? rawValue
            }
        }

        var helperText: String {
            switch self {
            case .none:
                return String(localized: "head_gesture.action.none.detail")
            case .toggleLanguage, .toggleShortcutPanel, .toggleInputControlMode, .toggleTracking:
                return hotkeyAction?.helperText ?? ""
            }
        }
    }

    private struct HeadGestureSample {
        let at: Date
        let yaw: Double
        let pitch: Double
    }

    private struct HeadGestureAxisMetrics {
        let minValue: Double
        let maxValue: Double
        let amplitude: Double
        let signChanges: Int
        let peakCount: Int
        let maxVelocity: Double
        let meanAbsVelocity: Double
        let sampleCount: Int
        let activeSampleCount: Int
        let activeDuration: TimeInterval
    }

    private init() {
        // Hotkeys require Accessibility trust. Install the event tap only after permissions are granted.
        // Reset legacy persisted override. Manual mode switch is now focus-follow aware and temporary.
        if persistentRecognitionControlMode != .auto {
            persistentRecognitionControlMode = .auto
        }
        lastObservedAirPodSide = AirPodsDetector.shared.currentSide()
        airPodsStateObserver = NotificationCenter.default.addObserver(
            forName: .AirPodsStateChanged,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor [weak self] in
                self?.handleAirPodsStateChanged(notification)
            }
        }
        startStabilityTimer()
        updateAirPodsRemoteCommandRegistration()
        DispatchQueue.main.async { [weak self] in
            self?.refreshHeadGestureMonitoringState(source: "initial-load")
        }
    }
    
    private var isHotkeyRegistered: Bool = false
    private var stabilityTimer: Timer?
    private var connectionTimer: Timer?
    private var lastDataTime: Date?
    var didLogEventTapKeyDebugHint: Bool = false
    
    private let motionManager = CMHeadphoneMotionManager()
    private let log = GlobalLogger.motion
    
    @Published var isTracking: Bool = false
    @Published var attitudeText: String = String(localized: "headset.status.no_data")
    @Published private(set) var isHeadsetRemoteRegistered: Bool = false
    @Published private(set) var headsetRemoteStatusText: String = ""
    @Published private(set) var lastHeadsetRemoteEventText: String = ""
    @Published private(set) var lastHeadsetRemoteEventAt: Date?
    @Published private(set) var lastHeadGestureEventText: String = ""
    @Published private(set) var lastHeadGestureEventAt: Date?
    
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
        didSet {
            UserDefaults.standard.set(isPTTEnabled, forKey: "isPTTEnabled")
            updateAirPodsRemoteCommandRegistration()
        }
    }

    @Published var headsetSinglePressAction: HeadsetPressAction = HeadMotionManager.loadHeadsetPressActionFromDefaults(for: .single) {
        didSet {
            HeadMotionManager.saveHeadsetPressAction(headsetSinglePressAction, for: .single)
            updateNowPlayingInfo()
        }
    }

    @Published var headsetDoublePressAction: HeadsetPressAction = HeadMotionManager.loadHeadsetPressActionFromDefaults(for: .double) {
        didSet {
            HeadMotionManager.saveHeadsetPressAction(headsetDoublePressAction, for: .double)
            updateNowPlayingInfo()
        }
    }

    @Published var headsetTriplePressAction: HeadsetPressAction = HeadMotionManager.loadHeadsetPressActionFromDefaults(for: .triple) {
        didSet {
            HeadMotionManager.saveHeadsetPressAction(headsetTriplePressAction, for: .triple)
            updateNowPlayingInfo()
        }
    }

    @Published var headGestureNodAction: HeadGestureAction = HeadMotionManager.loadHeadGestureActionFromDefaults(for: .nod) {
        didSet {
            HeadMotionManager.saveHeadGestureAction(headGestureNodAction, for: .nod)
        }
    }

    @Published var headGestureShakeAction: HeadGestureAction = HeadMotionManager.loadHeadGestureActionFromDefaults(for: .shake) {
        didSet {
            HeadMotionManager.saveHeadGestureAction(headGestureShakeAction, for: .shake)
        }
    }

    @Published var autoStartTrackingOnHeadsetConnection: Bool = UserDefaults.standard.object(forKey: HeadMotionManager.autoStartTrackingOnHeadsetConnectionKey) as? Bool ?? false {
        didSet {
            UserDefaults.standard.set(autoStartTrackingOnHeadsetConnection, forKey: HeadMotionManager.autoStartTrackingOnHeadsetConnectionKey)
            if !autoStartTrackingOnHeadsetConnection {
                pendingAutoTrackingStart?.cancel()
                pendingAutoTrackingStart = nil
                return
            }
            guard lastObservedAirPodSide != .none, !isTracking else { return }
            DispatchQueue.main.async { [weak self] in
                self?.scheduleAutoTrackingStartAfterConnection()
            }
        }
    }

    @Published var showPostureGuideBeforeTracking: Bool = UserDefaults.standard.object(forKey: HeadMotionManager.showPostureGuideBeforeTrackingKey) as? Bool ?? true {
        didSet {
            UserDefaults.standard.set(showPostureGuideBeforeTracking, forKey: HeadMotionManager.showPostureGuideBeforeTrackingKey)
        }
    }

    @Published var headGestureToggleEnabled: Bool = UserDefaults.standard.object(forKey: HeadMotionManager.headGestureToggleEnabledKey) as? Bool ?? true {
        didSet {
            UserDefaults.standard.set(headGestureToggleEnabled, forKey: HeadMotionManager.headGestureToggleEnabledKey)
            if !headGestureToggleEnabled {
                resetHeadGestureRecognition()
            }
            DispatchQueue.main.async { [weak self] in
                self?.refreshHeadGestureMonitoringState(source: "head-gesture-setting-changed")
            }
        }
    }
    
    // Experience Optimization Constants
    private let deadzone: Double = 0.005  // Ignore movements smaller than ~0.3 degrees
    private let trackingSmoothing: CGFloat = 0.5
    private let precisionSmoothing: CGFloat = 0.18
    private let cursorHoldRadius: CGFloat = 8
    private let precisionZoneRadius: CGFloat = 44
    private let headGestureWindow: TimeInterval = 0.85
    private let headGestureCooldown: TimeInterval = 1.2
    private let headGestureMinActiveDuration: TimeInterval = 0.12
    private let headGestureMaxActiveDuration: TimeInterval = 0.9
    private let headGestureMinVelocityNod: Double = 0.55
    private let headGestureMinVelocityShake: Double = 0.45
    private let headGestureCrossAxisLimitRatio: Double = 0.85
    // Restore head gesture sensitivity closer to the earlier tuning.
    private let headGestureSensitivityScale: Double = 0.8
    private var headGestureNodThreshold: Double { 0.11 * headGestureSensitivityScale }
    private var headGestureNodAmplitude: Double { 0.26 * headGestureSensitivityScale }
    private var headGestureShakeThreshold: Double { 0.13 * headGestureSensitivityScale }
    private var headGestureShakeAmplitude: Double { 0.28 * headGestureSensitivityScale }
    
    // Dynamic Range Calibration
    @Published var calibrationStatus: String = String(localized: "calibration.normal")
    
    // Real-time Data for UI Visualization
    @Published var currentHeadYaw: Double = 0.0
    @Published var currentHeadPitch: Double = 0.0
    @Published var currentVelocity: Double = 0.0
    
    private var minYaw: Double = -0.3
    private var maxYaw: Double = 0.3
    private var minPitch: Double = -0.2
    private var maxPitch: Double = 0.2
    private var isCalibratingRange: Bool = false
    private var isPassiveHeadGestureMonitoring: Bool = false
    private var passiveGestureBaseYaw: Double = 0.0
    private var passiveGestureBasePitch: Double = 0.0
    private var isPassiveGestureCalibrated: Bool = false
    private var recentHeadGestureSamples: [HeadGestureSample] = []
    private var lastHeadGestureTriggerAt: Date = .distantPast
    private var lastHeadGestureDebugLogAt: Date = .distantPast
    
    @Published var currentPostureBias: PostureBias = .neutral
    // Temporary override, usually from AirPods squeeze during a PTT session.
    @Published var transientRecognitionControlMode: RecognitionControlMode? = nil
    private var transientRecognitionControlModeFollowsFocus: Bool = false
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
    
    private var baseYaw: Double = 0
    private var basePitch: Double = 0
    private var isCalibrated: Bool = false
    private var isDragging: Bool = false
    
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var isAirPodsStreamActive: Bool = false

    // PTT State Tracking (Support multiple input sources)
    private enum PTTSource: Hashable {
        case keyboard(Int)
        case mouse(Int)
        case airPodsToggle
        case airPodsSeekForward
        case airPodsSeekBackward
    }
    private var activePTTSources: Set<PTTSource> = []
    private var isPTTPressed: Bool { !activePTTSources.isEmpty }
    
    // Store aggregate desktop dimensions
    private var desktopFrame: NSRect = .zero
    
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
    private var previousTrackTarget: Any?
    private var seekForwardTarget: Any?
    private var seekBackwardTarget: Any?
    private var voiceActivationMode: AppState.VoiceActivationMode = HeadMotionManager.loadVoiceActivationModeFromDefaults()
    private var lastHeadsetSinglePressAt: Date = .distantPast
    private var lastHeadsetDoublePressAt: Date = .distantPast
    private var lastHeadsetTriplePressAt: Date = .distantPast
    private let headsetRemoteActionDebounce: TimeInterval = 0.75
    private var lastObservedAirPodSide: AirPodSide = .none
    private var pendingAutoTrackingStart: DispatchWorkItem?
    private var airPodsStateObserver: NSObjectProtocol?

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

    private static func loadVoiceActivationModeFromDefaults() -> AppState.VoiceActivationMode {
        if let raw = UserDefaults.standard.string(forKey: "voiceActivationMode"),
           let mode = AppState.VoiceActivationMode(rawValue: raw) {
            return mode
        }
        return .pushToTalk
    }

    private static func loadHeadsetPressActionFromDefaults(for kind: HeadsetPressKind) -> HeadsetPressAction {
        guard let raw = UserDefaults.standard.string(forKey: headsetPressActionKey(for: kind)),
              let action = HeadsetPressAction(rawValue: raw) else {
            return defaultHeadsetPressAction(for: kind)
        }
        return action
    }

    private static func loadHeadGestureActionFromDefaults(for kind: HeadGestureKind) -> HeadGestureAction {
        guard let raw = UserDefaults.standard.string(forKey: headGestureActionKey(for: kind)),
              let action = HeadGestureAction(rawValue: raw) else {
            return defaultHeadGestureAction(for: kind)
        }
        return action
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

    private static func saveHeadsetPressAction(_ action: HeadsetPressAction, for kind: HeadsetPressKind) {
        UserDefaults.standard.set(action.rawValue, forKey: headsetPressActionKey(for: kind))
    }

    private static func saveHeadGestureAction(_ action: HeadGestureAction, for kind: HeadGestureKind) {
        UserDefaults.standard.set(action.rawValue, forKey: headGestureActionKey(for: kind))
    }

    private static func headsetPressActionKey(for kind: HeadsetPressKind) -> String {
        switch kind {
        case .single:
            return headsetSinglePressActionKey
        case .double:
            return headsetDoublePressActionKey
        case .triple:
            return headsetTriplePressActionKey
        }
    }

    private static func headGestureActionKey(for kind: HeadGestureKind) -> String {
        switch kind {
        case .nod:
            return headGestureNodActionKey
        case .shake:
            return headGestureShakeActionKey
        }
    }

    private static func defaultHeadsetPressAction(for kind: HeadsetPressKind) -> HeadsetPressAction {
        switch kind {
        case .single:
            return .toggleInputControlMode
        case .double:
            return .toggleTracking
        case .triple:
            return .toggleLanguage
        }
    }

    private static func defaultHeadGestureAction(for kind: HeadGestureKind) -> HeadGestureAction {
        switch kind {
        case .nod:
            return .toggleTracking
        case .shake:
            return .toggleInputControlMode
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
        pendingAutoTrackingStart?.cancel()
        pendingAutoTrackingStart = nil
        stopPassiveHeadGestureMonitoring(source: "tracking-start")
        
        // CRITICAL: Verify AirPods are actually available before starting
        // isDeviceMotionAvailable checks if the device SUPPORTS motion tracking
        // If it returns false, AirPods are definitely not connected
        if !motionManager.isDeviceMotionAvailable {
            let msg = String(localized: "motion.error.airpods_not_detected")
            attitudeText = String(localized: "headset.status.no_compatible")
            os_log("Cannot start tracking: AirPods not available", log: log, type: .error)
            HUDManager.shared.showTemporary(
                message: String(localized: "headset.hud.no_compatible"),
                icon: "xmark.circle.fill"
            )
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
        
        self.calibrationStatus = String(localized: "headset.status.calibrating")
        self.isCalibrated = false
        self.isAirPodsStreamActive = false
        self.refreshHeadsetRemoteStatus()
        
        // Reset attention state
        self.isLookingAtScreen = true
        
        // Start connection timeout timer (5 seconds)
        DispatchQueue.main.async {
            self.attitudeText = String(localized: "headset.status.connecting")
        }
        
        connectionTimer?.invalidate()
        connectionTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: false) { [weak self] _ in
            self?.handleConnectionTimeout()
        }
        
        motionManager.startDeviceMotionUpdates(to: .main) { [weak self] motion, error in
            guard let self = self else { return }
            
            if let error = error {
                DispatchQueue.main.async {
                    self.attitudeText = String(
                        format: String(localized: "headset.status.error_fmt"),
                        error.localizedDescription
                    )
                }
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
                Task { @MainActor in
                    ConnectionLockService.shared.setTrackingLockEnabled(true)
                }
                self.updateNowPlayingInfo()
                os_log("Aether: Connection Established (First Data Received)", log: self.log)
                
                // Reset lastDataTime to now
                self.lastDataTime = Date()
                
                DispatchQueue.main.async {
                    self.attitudeText = String(localized: "headset.status.tracking")
                }
            }
            // -------------------------------------
            
            if !self.isAirPodsStreamActive {
                self.isAirPodsStreamActive = true
                os_log("AirPods Stream Detected", log: self.log)
                self.refreshHeadsetRemoteStatus()
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

            self.processHeadGestureSample(yaw: offYaw, pitch: offPitch)
            
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
                     let away = String(localized: "headset.status.away")
                     if self.attitudeText != away { self.attitudeText = away }
                 }
                 return 
            }
            
            let rangeX = max(0.1, self.maxYaw - self.minYaw)
            let rangeY = max(0.1, self.maxPitch - self.minPitch)
            let midYaw = (self.minYaw + self.maxYaw) / 2.0
            let midPitch = (self.minPitch + self.maxPitch) / 2.0
            
            let rawNormX = (offYaw - midYaw) / rangeX
            let rawNormY = (offPitch - midPitch) / rangeY
            
            func applyDeadzoneAndLinearResponse(_ val: Double) -> Double {
                let absVal = abs(val)
                if absVal < deadzone { return 0 }
                let scaled = (absVal - deadzone) / (0.5 - deadzone)
                return min(0.5, scaled * 0.5) * (val > 0 ? 1 : -1)
            }
            
            let normX = max(-0.5, min(0.5, applyDeadzoneAndLinearResponse(rawNormX)))
            let normY = max(-0.5, min(0.5, applyDeadzoneAndLinearResponse(rawNormY)))
            
            let rawTargetX = self.desktopFrame.midX - (CGFloat(normX) * self.desktopFrame.width)
            let rawTargetY = self.desktopFrame.midY + (CGFloat(normY) * self.desktopFrame.height)

            let deltaX = rawTargetX - self.currentX
            let deltaY = rawTargetY - self.currentY
            let distance = hypot(deltaX, deltaY)

            if distance > self.cursorHoldRadius {
                let smoothing = distance < self.precisionZoneRadius ? self.precisionSmoothing : self.trackingSmoothing
                self.currentX = (self.currentX * (1 - smoothing)) + (rawTargetX * smoothing)
                self.currentY = (self.currentY * (1 - smoothing)) + (rawTargetY * smoothing)
            }
            
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
        HUDManager.shared.showTemporary(
            message: String(localized: "headset.hud.connection_timeout"),
            icon: "xmark.circle.fill"
        )
        onError?(msg)
        
        stopTrackingInternal()
        
        DispatchQueue.main.async {
            self.attitudeText = String(localized: "headset.status.connection_failed")
        }
    }
    
    func stopTracking() {
        pendingAutoTrackingStart?.cancel()
        pendingAutoTrackingStart = nil
        stopTrackingInternal()
    }

    private func stopTrackingInternal() {
        connectionTimer?.invalidate()
        connectionTimer = nil

        if isDragging {
            AutomationOutputs.shared.drag(start: false, at: nil)
            isDragging = false
        }

        Task { @MainActor in
            ConnectionLockService.shared.setTrackingLockEnabled(false)
        }
        
        motionManager.stopDeviceMotionUpdates()

        let finalizeTrackingStop = {
            if self.isTracking {
                self.attitudeText = String(localized: "headset.status.stopped")
            }
            self.isTracking = false
            self.refreshHeadGestureMonitoringState(source: "tracking-stopped")
        }

        if Thread.isMainThread {
            finalizeTrackingStop()
        } else {
            DispatchQueue.main.async(execute: finalizeTrackingStop)
        }
        
        isCalibrated = false
        isCalibratingRange = false
        isAirPodsStreamActive = false
        isLookingAtScreen = false
        refreshHeadsetRemoteStatus()
        resetHeadGestureRecognition()
        os_log("Aether: Stopped tracking", log: log)
    }

    private func refreshHeadGestureMonitoringState(source: String) {
        guard !isTracking else {
            stopPassiveHeadGestureMonitoring(source: "\(source)-tracking-active")
            return
        }

        let shouldMonitor = headGestureToggleEnabled && lastObservedAirPodSide != .none && motionManager.isDeviceMotionAvailable
        if shouldMonitor {
            startPassiveHeadGestureMonitoring(source: source)
        } else {
            os_log(
                "Head gesture monitor idle (%{public}@): enabled=%{public}@ connected=%{public}@ motionAvailable=%{public}@",
                log: log,
                type: .info,
                source,
                String(headGestureToggleEnabled),
                String(lastObservedAirPodSide != .none),
                String(motionManager.isDeviceMotionAvailable)
            )
            stopPassiveHeadGestureMonitoring(source: source)
        }
    }

    private func startPassiveHeadGestureMonitoring(source: String) {
        guard !isTracking else { return }
        guard headGestureToggleEnabled else { return }
        guard lastObservedAirPodSide != .none else { return }
        guard motionManager.isDeviceMotionAvailable else { return }
        guard !isPassiveHeadGestureMonitoring else { return }

        isPassiveHeadGestureMonitoring = true
        isPassiveGestureCalibrated = false
        resetHeadGestureRecognition()
        os_log("Head gesture monitor started (%{public}@)", log: log, type: .info, source)

        motionManager.startDeviceMotionUpdates(to: .main) { [weak self] motion, error in
            guard let self else { return }
            if let error {
                os_log("Head gesture monitor error: %{public}@", log: self.log, type: .error, error.localizedDescription)
                self.stopPassiveHeadGestureMonitoring(source: "gesture-monitor-error")
                return
            }
            guard let attitude = motion?.attitude else { return }
            self.handlePassiveHeadGestureMotion(attitude)
        }
    }

    private func stopPassiveHeadGestureMonitoring(source: String) {
        guard isPassiveHeadGestureMonitoring else { return }
        motionManager.stopDeviceMotionUpdates()
        isPassiveHeadGestureMonitoring = false
        isPassiveGestureCalibrated = false
        resetHeadGestureRecognition()
        os_log("Head gesture monitor stopped (%{public}@)", log: log, type: .info, source)
    }

    private func handlePassiveHeadGestureMotion(_ attitude: CMAttitude) {
        if !isPassiveGestureCalibrated {
            passiveGestureBaseYaw = attitude.yaw
            passiveGestureBasePitch = attitude.pitch
            isPassiveGestureCalibrated = true
            os_log(
                "Head gesture baseline calibrated: yaw=%.3f pitch=%.3f",
                log: log,
                type: .info,
                passiveGestureBaseYaw,
                passiveGestureBasePitch
            )
            return
        }

        let offYaw = attitude.yaw - passiveGestureBaseYaw
        let offPitch = attitude.pitch - passiveGestureBasePitch
        processHeadGestureSample(yaw: offYaw, pitch: offPitch)
    }

    private func resetHeadGestureRecognition() {
        recentHeadGestureSamples.removeAll(keepingCapacity: false)
    }

    private func processHeadGestureSample(yaw: Double, pitch: Double) {
        guard headGestureToggleEnabled else { return }

        let now = Date()
        recentHeadGestureSamples.append(HeadGestureSample(at: now, yaw: yaw, pitch: pitch))
        recentHeadGestureSamples.removeAll { now.timeIntervalSince($0.at) > headGestureWindow }

        let nodMetrics = axisMetrics(samples: recentHeadGestureSamples, keyPath: \.pitch, threshold: headGestureNodThreshold)
        let shakeMetrics = axisMetrics(samples: recentHeadGestureSamples, keyPath: \.yaw, threshold: headGestureShakeThreshold)
        maybeLogHeadGestureDiagnostics(
            at: now,
            nodMetrics: nodMetrics,
            shakeMetrics: shakeMetrics,
            yaw: yaw,
            pitch: pitch
        )

        guard now.timeIntervalSince(lastHeadGestureTriggerAt) >= headGestureCooldown else { return }

        let shakeDurationOK = shakeMetrics.activeDuration >= headGestureMinActiveDuration
            && shakeMetrics.activeDuration <= headGestureMaxActiveDuration
        let nodDurationOK = nodMetrics.activeDuration >= headGestureMinActiveDuration
            && nodMetrics.activeDuration <= headGestureMaxActiveDuration
        let shakeDominant = nodMetrics.amplitude <= (shakeMetrics.amplitude * headGestureCrossAxisLimitRatio)
        let nodDominant = shakeMetrics.amplitude <= (nodMetrics.amplitude * headGestureCrossAxisLimitRatio)

        if shakeMetrics.amplitude >= headGestureShakeAmplitude,
           shakeMetrics.signChanges >= 1,
           shakeMetrics.peakCount >= 1,
           shakeMetrics.maxVelocity >= headGestureMinVelocityShake,
           shakeDurationOK,
           shakeDominant {
            lastHeadGestureTriggerAt = now
            resetHeadGestureRecognition()
            os_log(
                "Head gesture detected: shake amp=%.3f signChanges=%{public}d peaks=%{public}d vel=%.3f samples=%{public}d",
                log: log,
                type: .info,
                shakeMetrics.amplitude,
                shakeMetrics.signChanges,
                shakeMetrics.peakCount,
                shakeMetrics.maxVelocity,
                shakeMetrics.sampleCount
            )
            Task { @MainActor [weak self] in
                self?.playHeadGestureConfirmationSound(for: .shake)
                self?.performConfiguredHeadGestureAction(kind: .shake, source: "head-gesture-shake")
            }
            return
        }

        guard nodMetrics.amplitude >= headGestureNodAmplitude,
              nodMetrics.signChanges >= 1,
              nodMetrics.peakCount >= 1,
              nodMetrics.maxVelocity >= headGestureMinVelocityNod,
              nodDurationOK,
              nodDominant else { return }
        lastHeadGestureTriggerAt = now
        resetHeadGestureRecognition()
        os_log(
            "Head gesture detected: nod amp=%.3f signChanges=%{public}d peaks=%{public}d vel=%.3f samples=%{public}d",
            log: log,
            type: .info,
            nodMetrics.amplitude,
            nodMetrics.signChanges,
            nodMetrics.peakCount,
            nodMetrics.maxVelocity,
            nodMetrics.sampleCount
        )
        Task { @MainActor [weak self] in
            self?.playHeadGestureConfirmationSound(for: .nod)
            self?.performConfiguredHeadGestureAction(kind: .nod, source: "head-gesture-nod")
        }
    }

    private func detectNodGesture(in samples: [HeadGestureSample]) -> Bool {
        let metrics = axisMetrics(samples: samples, keyPath: \.pitch, threshold: headGestureNodThreshold)
        let durationOK = metrics.activeDuration >= headGestureMinActiveDuration
            && metrics.activeDuration <= headGestureMaxActiveDuration
        return metrics.amplitude >= headGestureNodAmplitude
            && metrics.signChanges >= 1
            && metrics.peakCount >= 1
            && metrics.maxVelocity >= headGestureMinVelocityNod
            && durationOK
    }

    private func detectShakeGesture(in samples: [HeadGestureSample]) -> Bool {
        let metrics = axisMetrics(samples: samples, keyPath: \.yaw, threshold: headGestureShakeThreshold)
        let durationOK = metrics.activeDuration >= headGestureMinActiveDuration
            && metrics.activeDuration <= headGestureMaxActiveDuration
        return metrics.amplitude >= headGestureShakeAmplitude
            && metrics.signChanges >= 1
            && metrics.peakCount >= 1
            && metrics.maxVelocity >= headGestureMinVelocityShake
            && durationOK
    }

    private func axisMetrics(
        samples: [HeadGestureSample],
        keyPath: KeyPath<HeadGestureSample, Double>,
        threshold: Double
    ) -> HeadGestureAxisMetrics {
        let values = samples.map { $0[keyPath: keyPath] }
        guard let minValue = values.min(), let maxValue = values.max(), values.count >= 2 else {
            return HeadGestureAxisMetrics(
                minValue: 0,
                maxValue: 0,
                amplitude: 0,
                signChanges: 0,
                peakCount: 0,
                maxVelocity: 0,
                meanAbsVelocity: 0,
                sampleCount: values.count,
                activeSampleCount: 0,
                activeDuration: 0
            )
        }

        var signChanges = 0
        var lastSign = 0
        for value in values {
            let sign: Int
            if value >= threshold {
                sign = 1
            } else if value <= -threshold {
                sign = -1
            } else {
                continue
            }

            if lastSign != 0 && sign != lastSign {
                signChanges += 1
            }
            lastSign = sign
        }

        var peakCount = 0
        var maxVelocity = 0.0
        var meanAbsVelocity: Double = 0
        var velocitySamples = 0
        var lastDeltaSign = 0

        for idx in 1..<samples.count {
            let current = samples[idx]
            let previous = samples[idx - 1]
            let dt = current.at.timeIntervalSince(previous.at)
            guard dt > 0 else { continue }
            let dv = current[keyPath: keyPath] - previous[keyPath: keyPath]
            let velocity = dv / dt
            let absVelocity = abs(velocity)
            maxVelocity = max(maxVelocity, absVelocity)
            meanAbsVelocity += absVelocity
            velocitySamples += 1

            let deltaSign: Int
            if dv > 0 {
                deltaSign = 1
            } else if dv < 0 {
                deltaSign = -1
            } else {
                deltaSign = 0
            }
            if lastDeltaSign != 0 && deltaSign != 0 && deltaSign != lastDeltaSign {
                let candidateValue = previous[keyPath: keyPath]
                if abs(candidateValue) >= threshold {
                    peakCount += 1
                }
            }
            if deltaSign != 0 {
                lastDeltaSign = deltaSign
            }
        }

        if velocitySamples > 0 {
            meanAbsVelocity /= Double(velocitySamples)
        }

        let activeSamples = samples.filter { abs($0[keyPath: keyPath]) >= threshold }
        let activeDuration: TimeInterval
        if let firstActive = activeSamples.first, let lastActive = activeSamples.last, activeSamples.count >= 2 {
            activeDuration = lastActive.at.timeIntervalSince(firstActive.at)
        } else {
            activeDuration = 0
        }

        return HeadGestureAxisMetrics(
            minValue: minValue,
            maxValue: maxValue,
            amplitude: maxValue - minValue,
            signChanges: signChanges,
            peakCount: peakCount,
            maxVelocity: maxVelocity,
            meanAbsVelocity: meanAbsVelocity,
            sampleCount: values.count,
            activeSampleCount: activeSamples.count,
            activeDuration: activeDuration
        )
    }

    private func maybeLogHeadGestureDiagnostics(
        at now: Date,
        nodMetrics: HeadGestureAxisMetrics,
        shakeMetrics: HeadGestureAxisMetrics,
        yaw: Double,
        pitch: Double
    ) {
        guard isDebugModeEnabled else { return }
        guard now.timeIntervalSince(lastHeadGestureDebugLogAt) >= 1.0 else { return }
        guard nodMetrics.sampleCount >= 4 || shakeMetrics.sampleCount >= 4 else { return }

        lastHeadGestureDebugLogAt = now
        os_log(
            "Head gesture diag: tracking=%{public}@ passive=%{public}@ yaw=%.3f pitch=%.3f nodAmp=%.3f/%0.3f nodSigns=%{public}d nodPeaks=%{public}d nodVel=%.3f nodDur=%.2f shakeAmp=%.3f/%0.3f shakeSigns=%{public}d shakePeaks=%{public}d shakeVel=%.3f shakeDur=%.2f samples=%{public}d",
            log: log,
            type: .debug,
            String(isTracking),
            String(isPassiveHeadGestureMonitoring),
            yaw,
            pitch,
            nodMetrics.amplitude,
            headGestureNodAmplitude,
            nodMetrics.signChanges,
            nodMetrics.peakCount,
            nodMetrics.maxVelocity,
            nodMetrics.activeDuration,
            shakeMetrics.amplitude,
            headGestureShakeAmplitude,
            shakeMetrics.signChanges,
            shakeMetrics.peakCount,
            shakeMetrics.maxVelocity,
            shakeMetrics.activeDuration,
            max(nodMetrics.sampleCount, shakeMetrics.sampleCount)
        )
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
        HUDManager.shared.showTemporary(
            message: String(localized: "headset.hud.scroll_top"),
            icon: "arrow.up.to.line"
        )
    }

    func scrollToBottom() {
        AutomationOutputs.shared.scroll(dx: 0, dy: 100000)
        HUDManager.shared.showTemporary(
            message: String(localized: "headset.hud.scroll_bottom"),
            icon: "arrow.down.to.line"
        )
    }

    func dragStart() {
        guard !isDragging else { return }
        isDragging = true
        // Use current cursor location (nil) to avoid coordinate flipping issues
        AutomationOutputs.shared.drag(start: true, at: nil)
        HUDManager.shared.showTemporary(
            message: String(localized: "headset.hud.drag_start"),
            icon: "hand.draw.fill"
        )
    }

    func dragEnd() {
        guard isDragging else { return }
        isDragging = false
        // Use current cursor location (nil) to avoid coordinate flipping issues
        AutomationOutputs.shared.drag(start: false, at: nil)
        HUDManager.shared.showTemporary(
            message: String(localized: "headset.hud.drag_drop"),
            icon: "hand.raised.fill"
        )
    }

    func recenter() {
        guard isTracking else { return }
        // Force re-calibration on next motion sample.
        isCalibrated = false
        isCalibratingRange = true
        calibrationStatus = String(localized: "headset.status.calibrating")
    }
    
    func finishCalibration() {
        isCalibratingRange = false
        calibrationStatus = String(localized: "calibration.normal")
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
                    os_log("Attention: Regained", log: log)
                    // Optional: Play subtle feedback sound
                } else {
                    os_log("Attention: Lost", log: log)
                    // Optional: Play subtle feedback sound
                }
            }
        } else {
            attentionHysteresisBuffer = 0
        }
    }

    @MainActor
    private func handleAirPodsStateChanged(_ notification: Notification) {
        let newSide = (notification.object as? AirPodSide) ?? AirPodsDetector.shared.currentSide()
        let wasConnected = lastObservedAirPodSide != .none
        let isConnected = newSide != .none
        lastObservedAirPodSide = newSide

        if !isConnected {
            pendingAutoTrackingStart?.cancel()
            pendingAutoTrackingStart = nil
            stopPassiveHeadGestureMonitoring(source: "airpods-disconnected")
            if isTracking {
                let msg = String(localized: "motion.error.airpods_disconnected")
                HUDManager.shared.showTemporary(
                    message: String(localized: "headset.hud.disconnected"),
                    icon: "exclamationmark.triangle.fill"
                )
                onError?(msg)
                stopTrackingInternal()
                attitudeText = String(localized: "headset.status.disconnected")
            }
            return
        }

        refreshHeadGestureMonitoringState(source: "airpods-connected")
        guard autoStartTrackingOnHeadsetConnection, !wasConnected else { return }
        scheduleAutoTrackingStartAfterConnection()
    }

    @MainActor
    private func scheduleAutoTrackingStartAfterConnection() {
        guard autoStartTrackingOnHeadsetConnection, !isTracking else { return }

        pendingAutoTrackingStart?.cancel()

        let baseDelay: TimeInterval = showPostureGuideBeforeTracking ? 1.2 : 0.35
        if showPostureGuideBeforeTracking {
            HUDManager.shared.showTemporary(
                message: String(localized: "headset.hud.posture_guide"),
            )
        }

        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            guard self.autoStartTrackingOnHeadsetConnection, !self.isTracking, self.lastObservedAirPodSide != .none else { return }
            guard self.motionManager.isDeviceMotionAvailable else {
                HUDManager.shared.showTemporary(
                    message: String(localized: "headset.hud.unsupported"),
                )
                return
            }
            self.startTracking()
        }

        pendingAutoTrackingStart = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + baseDelay, execute: workItem)
    }

    private func enableAirPodsCommands(enableSeekPTT: Bool) {
        let commandCenter = MPRemoteCommandCenter.shared()

        disableAirPodsCommands()

        playTarget = commandCenter.playCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            DispatchQueue.main.async {
                os_log("Headset playCommand received", log: self.log, type: .info)
                self.handleHeadsetSinglePress(origin: "airpods-play")
            }
            return .success
        }
        pauseTarget = commandCenter.pauseCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            DispatchQueue.main.async {
                os_log("Headset pauseCommand received", log: self.log, type: .info)
                self.handleHeadsetSinglePress(origin: "airpods-pause")
            }
            return .success
        }
        toggleTarget = commandCenter.togglePlayPauseCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            DispatchQueue.main.async {
                os_log("Headset togglePlayPauseCommand received", log: self.log, type: .info)
                self.handleHeadsetSinglePress(origin: "airpods-toggle")
            }
            return .success
        }
        commandCenter.playCommand.isEnabled = true
        commandCenter.pauseCommand.isEnabled = true
        commandCenter.togglePlayPauseCommand.isEnabled = true

        nextTrackTarget = commandCenter.nextTrackCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            DispatchQueue.main.async { self.handleHeadsetDoublePress() }
            return .success
        }
        commandCenter.nextTrackCommand.isEnabled = true

        previousTrackTarget = commandCenter.previousTrackCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            DispatchQueue.main.async { self.handleHeadsetTriplePress() }
            return .success
        }
        commandCenter.previousTrackCommand.isEnabled = true

        if enableSeekPTT {
            seekForwardTarget = commandCenter.seekForwardCommand.addTarget { [weak self] event in
                guard let self, let seek = event as? MPSeekCommandEvent else { return .commandFailed }
                switch seek.type {
                case .beginSeeking:
                    return self.beginAirPodsPTT(source: .airPodsSeekForward, origin: "airpods-seek-forward-begin")
                case .endSeeking:
                    return self.endAirPodsPTT(source: .airPodsSeekForward, origin: "airpods-seek-forward-end")
                @unknown default:
                    return .commandFailed
                }
            }
            commandCenter.seekForwardCommand.isEnabled = true

            seekBackwardTarget = commandCenter.seekBackwardCommand.addTarget { [weak self] event in
                guard let self, let seek = event as? MPSeekCommandEvent else { return .commandFailed }
                switch seek.type {
                case .beginSeeking:
                    return self.beginAirPodsPTT(source: .airPodsSeekBackward, origin: "airpods-seek-backward-begin")
                case .endSeeking:
                    return self.endAirPodsPTT(source: .airPodsSeekBackward, origin: "airpods-seek-backward-end")
                @unknown default:
                    return .commandFailed
                }
            }
            commandCenter.seekBackwardCommand.isEnabled = true
        } else {
            commandCenter.seekForwardCommand.isEnabled = false
            commandCenter.seekBackwardCommand.isEnabled = false
        }
        
        updateNowPlayingInfo()
        isHeadsetRemoteRegistered = true
        refreshHeadsetRemoteStatus()
        SilentAudioManager.shared.start()
    }

    private func updateNowPlayingInfo() {
        guard shouldEnableAirPodsModeSwitch else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            refreshHeadsetRemoteStatus()
            return
        }

        var nowPlayingInfo = [String: Any]()
        nowPlayingInfo[MPMediaItemPropertyTitle] = String(localized: "headset.now_playing.title")
        nowPlayingInfo[MPMediaItemPropertyArtist] = String(
            format: String(localized: "headset.now_playing.artist_fmt"),
            headsetSinglePressAction.label,
            headsetDoublePressAction.label,
            headsetTriplePressAction.label
        )
        nowPlayingInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime] = 0.0
        // Mark as actively playing so MediaRemote routes headset commands to Aether.
        nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackRate] = 1.0
        nowPlayingInfo[MPNowPlayingInfoPropertyDefaultPlaybackRate] = 1.0
        
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
        if #available(macOS 10.13, *) {
            MPNowPlayingInfoCenter.default().playbackState = .playing
        }
        refreshHeadsetRemoteStatus()
    }
    
    private func disableAirPodsCommands() {
        let commandCenter = MPRemoteCommandCenter.shared()
        
        if let target = playTarget { commandCenter.playCommand.removeTarget(target) }
        if let target = pauseTarget { commandCenter.pauseCommand.removeTarget(target) }
        if let target = toggleTarget { commandCenter.togglePlayPauseCommand.removeTarget(target) }
        if let target = nextTrackTarget { commandCenter.nextTrackCommand.removeTarget(target) }
        if let target = previousTrackTarget { commandCenter.previousTrackCommand.removeTarget(target) }
        if let target = seekForwardTarget { commandCenter.seekForwardCommand.removeTarget(target) }
        if let target = seekBackwardTarget { commandCenter.seekBackwardCommand.removeTarget(target) }
        
        playTarget = nil
        pauseTarget = nil
        toggleTarget = nil
        nextTrackTarget = nil
        previousTrackTarget = nil
        seekForwardTarget = nil
        seekBackwardTarget = nil
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        if #available(macOS 10.13, *) {
            MPNowPlayingInfoCenter.default().playbackState = .stopped
        }
        isHeadsetRemoteRegistered = false
        refreshHeadsetRemoteStatus()
        SilentAudioManager.shared.stop()
    }

    @MainActor
    func toggleRecognitionInputControlMode(source: String = "hotkey", persist: Bool = true) {
        let currentlyTyping = HUDManager.shared.lastKnownTypingState()
        let currentResolvedMode = resolvedRecognitionControlMode(currentlyTyping: currentlyTyping)
        let nextMode: RecognitionControlMode = (currentResolvedMode == .command) ? .dictation : .command

        // Guard: dictation mode requires an actual text-input focus.
        // Control mode can always work without text field focus.
        if nextMode == .dictation && !currentlyTyping {
            let message = String(localized: "headset.hud.no_input_fallback")
            setTransientRecognitionControlMode(nil)
            persistentRecognitionControlMode = .auto
            postRecognitionControlModeChanged(source: source)
            HUDManager.shared.showTemporary(
                message: message,
                recognitionControlMode: .command,
            )
            os_log("Recognition Mode Toggle blocked (%{public}@, persist=%{public}@): no input focus",
                   log: log, type: .info, source, persist ? "yes" : "no")
            return
        }

        // Manual switch should still follow focus changes after the user toggles it.
        persistentRecognitionControlMode = .auto
        setTransientRecognitionControlMode(nextMode, anchorTypingState: currentlyTyping, followsFocus: true)

        let isCommandMode = nextMode == .command
        let message = isCommandMode
            ? String(localized: "headset.hud.switched_control")
            : String(localized: "headset.hud.switched_input")
        postRecognitionControlModeChanged(source: source)
        HUDManager.shared.showTemporary(
            message: message,
            recognitionControlMode: nextMode.hudMode,
        )
        if isCommandMode && !isTracking {
            os_log("Control mode toggled while tracking inactive; starting tracking", log: log, type: .info)
            startTracking()
        }
        os_log("Recognition Mode Override Toggled (%{public}@, persist=%{public}@): %{public}@",
               log: log, type: .info, source, persist ? "yes" : "no", isCommandMode ? "command" : "dictation")
    }

    @MainActor
    private func shouldHandleHeadsetRemoteAction(kind: HeadsetPressKind) -> Bool {
        let now = Date()
        switch kind {
        case .single:
            guard now.timeIntervalSince(lastHeadsetSinglePressAt) >= headsetRemoteActionDebounce else { return false }
            lastHeadsetSinglePressAt = now
        case .double:
            guard now.timeIntervalSince(lastHeadsetDoublePressAt) >= headsetRemoteActionDebounce else { return false }
            lastHeadsetDoublePressAt = now
        case .triple:
            guard now.timeIntervalSince(lastHeadsetTriplePressAt) >= headsetRemoteActionDebounce else { return false }
            lastHeadsetTriplePressAt = now
        }
        return true
    }

    @MainActor
    private func handleHeadsetSinglePress(origin: String) {
        guard shouldHandleHeadsetRemoteAction(kind: .single) else { return }
        performConfiguredHeadsetAction(kind: .single, source: origin)
    }

    @MainActor
    func handleSystemInputMuteGesture(_ inputShouldBeMuted: Bool) {
        let source = inputShouldBeMuted ? "airpods-input-mute" : "airpods-input-unmute"
        guard shouldHandleHeadsetRemoteAction(kind: .single) else { return }
        performConfiguredHeadsetAction(kind: .single, source: source)
    }

    @MainActor
    private func handleHeadsetDoublePress() {
        guard shouldHandleHeadsetRemoteAction(kind: .double) else { return }
        os_log("Headset double press received", log: log, type: .info)
        performConfiguredHeadsetAction(kind: .double, source: HeadsetPressKind.double.eventSource)
    }

    @MainActor
    private func handleHeadsetTriplePress() {
        guard shouldHandleHeadsetRemoteAction(kind: .triple) else { return }
        os_log("Headset triple press received", log: log, type: .info)
        performConfiguredHeadsetAction(kind: .triple, source: HeadsetPressKind.triple.eventSource)
    }

    @MainActor
    private func performConfiguredHeadsetAction(kind: HeadsetPressKind, source: String) {
        let configuredAction = headsetPressAction(for: kind)
        noteHeadsetRemoteEvent(
            display: String(format: String(localized: "headset.event.action_fmt"), kind.label, configuredAction.label)
        )
        guard let action = configuredAction.hotkeyAction else {
            HUDManager.shared.showTemporary(
                message: String(format: String(localized: "headset.hud.no_action_assigned_fmt"), kind.label),
            )
            return
        }
        performHeadsetAction(action, source: source)
    }

    @MainActor
    private func performConfiguredHeadGestureAction(kind: HeadGestureKind, source: String) {
        let configuredAction = headGestureAction(for: kind)
        noteHeadGestureEvent(
            display: String(format: String(localized: "head_gesture.event.action_fmt"), kind.label, configuredAction.label)
        )
        guard let action = configuredAction.hotkeyAction else {
            HUDManager.shared.showTemporary(
                message: String(format: String(localized: "head_gesture.hud.no_action_assigned_fmt"), kind.label),
            )
            return
        }
        performHeadsetAction(action, source: source)
    }

    @MainActor
    private func performHeadsetAction(_ action: HotkeyAction, source: String) {
        switch action {
        case .toggleTracking:
            performTrackingToggle(source: source)
        case .connectionLock:
            HUDManager.shared.showTemporary(
                message: String(localized: "headset.hud.connection_lock"),
                icon: "lock.fill",
            )
            NotificationCenter.default.post(name: .toggleConnectionLock, object: nil)
        case .toggleInputControlMode:
            toggleRecognitionInputControlMode(source: source, persist: false)
        case .toggleLanguage:
            NotificationCenter.default.post(name: Notification.Name("AetherToggleLanguage"), object: nil)
        case .toggleShortcutPanel:
            NotificationCenter.default.post(name: .toggleShortcutPanel, object: nil)
        case .pushToTalk:
            HUDManager.shared.showTemporary(
                message: String(localized: "headset.hud.push_to_talk_unsupported"),
            )
        }
    }

    private func headsetPressAction(for kind: HeadsetPressKind) -> HeadsetPressAction {
        switch kind {
        case .single:
            return headsetSinglePressAction
        case .double:
            return headsetDoublePressAction
        case .triple:
            return headsetTriplePressAction
        }
    }

    private func headGestureAction(for kind: HeadGestureKind) -> HeadGestureAction {
        switch kind {
        case .nod:
            return headGestureNodAction
        case .shake:
            return headGestureShakeAction
        }
    }

    @MainActor
    private func performTrackingToggle(source: String) {
        if isTracking {
            GlobalLogger.input.info("Tracking Toggle (\(source)): Stop Tracking")
            HUDManager.shared.showTemporary(
                message: String(localized: "headset.hud.stop_tracking"),
                icon: "stop.fill",
            )
            stopTracking()
        } else {
            GlobalLogger.input.info("Tracking Toggle (\(source)): Start Tracking")
            HUDManager.shared.showTemporary(
                message: String(localized: "headset.hud.start_tracking"),
                icon: "play.fill",
            )
            startTracking()
        }
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

        // Pressing Esc should force control mode immediately, while still allowing focus-follow auto mode.
        persistentRecognitionControlMode = .auto
        setTransientRecognitionControlMode(.command, anchorTypingState: currentlyTyping, followsFocus: true)

        let message = String(localized: "headset.hud.exit_input_mode")
        postRecognitionControlModeChanged(source: source)
        HUDManager.shared.showTemporary(
            message: message,
            recognitionControlMode: .command,
        )
        os_log("Recognition Mode escape exit (%{public}@): mode=%{public}@",
               log: log, type: .info, source, effectiveRecognitionControlMode.rawValue)
    }

    private func playHeadGestureConfirmationSound(for kind: HeadGestureKind) {
        let preferredNames: [String]
        switch kind {
        case .nod:
            preferredNames = ["Pop", "Tink", "Glass"]
        case .shake:
            preferredNames = ["Glass", "Ping", "Pop"]
        }
        for name in preferredNames {
            if let sound = NSSound(named: name) {
                sound.play()
                os_log("Head gesture confirmation sound: %{public}@", log: log, type: .info, name)
                return
            }
        }
        NSSound(named: "Tink")?.play()
        os_log("Head gesture confirmation sound fallback: Tink", log: log, type: .info)
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
        if Thread.isMainThread {
            HUDManager.shared.notifyPointerMoved()
        } else {
            DispatchQueue.main.async {
                HUDManager.shared.notifyPointerMoved()
            }
        }
    }

    func setVoiceActivationMode(_ mode: AppState.VoiceActivationMode) {
        voiceActivationMode = mode
        updateAirPodsRemoteCommandRegistration()
    }

    private var shouldEnableAirPodsModeSwitch: Bool {
        false
    }

    private func updateAirPodsRemoteCommandRegistration() {
        let shouldEnable = shouldEnableAirPodsModeSwitch
        if shouldEnable {
            let shouldEnableSeekPTT = voiceActivationMode == .pushToTalk && isPTTEnabled
            releaseAirPodsPTTSources(reason: shouldEnableSeekPTT ? "airpods-ptt-refresh" : "airpods-single-press-disabled")
            enableAirPodsCommands(enableSeekPTT: shouldEnableSeekPTT)
        } else {
            releaseAirPodsPTTSources(reason: "airpods-ptt-disabled")
            disableAirPodsCommands()
        }
        updateNowPlayingInfo()
    }

    private func refreshHeadsetRemoteStatus() {
        if !shouldEnableAirPodsModeSwitch {
            headsetRemoteStatusText = String(localized: "headset.remote.disabled")
            return
        }

        if isAirPodsStreamActive {
            headsetRemoteStatusText = String(localized: "headset.remote.stream_connected")
        } else if isHeadsetRemoteRegistered {
            headsetRemoteStatusText = String(localized: "headset.remote.waiting")
        } else {
            headsetRemoteStatusText = String(localized: "headset.remote.unregistered")
        }
    }

    private func noteHeadsetRemoteEvent(display: String) {
        lastHeadsetRemoteEventText = display
        lastHeadsetRemoteEventAt = Date()
        refreshHeadsetRemoteStatus()
    }

    private func noteHeadGestureEvent(display: String) {
        lastHeadGestureEventText = display
        lastHeadGestureEventAt = Date()
    }

    private func beginAirPodsPTT(source: PTTSource, origin: String) -> MPRemoteCommandHandlerStatus {
        guard voiceActivationMode == .pushToTalk, isPTTEnabled else { return .commandFailed }
        noteHeadsetRemoteEvent(
            display: String(localized: "headset.event.single")
        )
        beginPTT(from: source, origin: origin)
        return .success
    }

    private func endAirPodsPTT(source: PTTSource, origin: String) -> MPRemoteCommandHandlerStatus {
        guard voiceActivationMode == .pushToTalk else { return .commandFailed }
        noteHeadsetRemoteEvent(
            display: String(localized: "headset.event.single_end")
        )
        endPTT(from: source, origin: origin)
        return .success
    }

    private func toggleAirPodsPTT(origin: String) -> MPRemoteCommandHandlerStatus {
        guard voiceActivationMode == .pushToTalk, isPTTEnabled else { return .commandFailed }
        noteHeadsetRemoteEvent(
            display: String(localized: "headset.event.single_toggle")
        )
        if activePTTSources.contains(.airPodsToggle) {
            endPTT(from: .airPodsToggle, origin: origin)
        } else {
            beginPTT(from: .airPodsToggle, origin: origin)
        }
        return .success
    }

    private func beginPTT(from source: PTTSource, origin: String) {
        guard !activePTTSources.contains(source) else { return }
        let wasPressed = isPTTPressed
        activePTTSources.insert(source)

        if !wasPressed {
            setTransientRecognitionControlMode(nil)
            os_log("PTT DOWN (%{public}@)", log: log, type: .info, origin)
            NotificationCenter.default.post(name: HeadMotionManager.pttDownNotification, object: nil)
        }
        updateNowPlayingInfo()
    }

    private func endPTT(from source: PTTSource, origin: String) {
        guard activePTTSources.contains(source) else { return }
        activePTTSources.remove(source)
        if !isPTTPressed {
            os_log("PTT UP (%{public}@)", log: log, type: .info, origin)
            NotificationCenter.default.post(name: HeadMotionManager.pttUpNotification, object: nil)
        }
        updateNowPlayingInfo()
    }

    private func releaseAirPodsPTTSources(reason: String) {
        let wasPressed = isPTTPressed
        let retainedSources = activePTTSources.filter { source in
            switch source {
            case .airPodsToggle, .airPodsSeekForward, .airPodsSeekBackward:
                return false
            case .keyboard, .mouse:
                return true
            }
        }
        activePTTSources = Set(retainedSources)
        if wasPressed && !isPTTPressed {
            os_log("PTT UP (%{public}@)", log: log, type: .info, reason)
            NotificationCenter.default.post(name: HeadMotionManager.pttUpNotification, object: nil)
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

    @MainActor
    func recoverFromAccessibilityTrustChange(trusted: Bool, source: String = "ax-trust-change") {
        if !Thread.isMainThread {
            DispatchQueue.main.async { [weak self] in
                self?.recoverFromAccessibilityTrustChange(trusted: trusted, source: source)
            }
            return
        }

        if trusted {
            // Force rebuild to avoid stale/half-dead taps after TCC revoke/restore cycles.
            uninstallHotkeys()
            installHotkeysIfPossible()
            clearTransientRecognitionControlMode(source: "\(source)-trusted")
            os_log("HeadMotionManager recovery: AX trusted, hotkeys rebuilt",
                   log: log, type: .info)
        } else {
            uninstallHotkeys()
            clearTransientRecognitionControlMode(source: "\(source)-untrusted")
            os_log("HeadMotionManager recovery: AX untrusted, hotkeys removed",
                   log: log, type: .info)
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
        
        var mask: CGEventMask = 0
        mask |= (1 << CGEventType.keyDown.rawValue)
        mask |= (1 << CGEventType.keyUp.rawValue)
        mask |= (1 << CGEventType.flagsChanged.rawValue)
        mask |= (1 << CGEventType.leftMouseDown.rawValue)
        mask |= (1 << CGEventType.rightMouseDown.rawValue)
        mask |= (1 << CGEventType.otherMouseDown.rawValue)
        mask |= (1 << CGEventType.otherMouseUp.rawValue)
        
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
            let flags = event.flags
            let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
            
            if type == .flagsChanged {
                if let action = HotkeyManager.shared.matchFlagsChanged(keyCode: keyCode, flags: flags) {
                    switch action {
                    case .toggleLanguage:
                        GlobalLogger.input.info("Hotkey: Toggle Language (flagsChanged)")
                        NotificationCenter.default.post(name: Notification.Name("AetherToggleLanguage"), object: nil)
                        return Unmanaged.passUnretained(event)
                    case .pushToTalk:
                        guard manager.isPTTEnabled else { return Unmanaged.passUnretained(event) }
                        let source = PTTSource.keyboard(Int(keyCode))
                        if !manager.activePTTSources.contains(source) {
                            GlobalLogger.input.info("Hotkey: PTT DOWN Detected (flagsChanged)")
                            manager.beginPTT(from: source, origin: "keyboard-flagsChanged")
                        }
                        return nil
                    case .toggleTracking, .connectionLock, .toggleInputControlMode, .toggleShortcutPanel:
                        break
                    }
                }
                let source = PTTSource.keyboard(Int(keyCode))
                if manager.activePTTSources.contains(source) {
                    GlobalLogger.input.info("Hotkey: PTT UP Detected (flagsChanged)")
                    manager.endPTT(from: source, origin: "keyboard-flagsChanged")
                    return nil
                }
            }

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
                            HUDManager.shared.showTemporary(
                                message: String(localized: "headset.hud.stop_tracking"),
                                icon: "stop.fill"
                            )
                            DispatchQueue.main.async { manager.stopTracking() }
                        } else {
                            GlobalLogger.input.info("Hotkey: Start Tracking")
                            HUDManager.shared.showTemporary(
                                message: String(localized: "headset.hud.start_tracking"),
                                icon: "play.fill"
                            )
                            DispatchQueue.main.async { manager.startTracking() }
                        }
                        return nil

                    case .connectionLock:
                        GlobalLogger.input.info("Hotkey: Toggle Connection Lock")
                        HUDManager.shared.showTemporary(
                            message: String(localized: "headset.hud.connection_lock"),
                            icon: "lock.fill"
                        )
                        NotificationCenter.default.post(name: .toggleConnectionLock, object: nil)
                        return nil

                    case .toggleInputControlMode:
                        GlobalLogger.input.info("Hotkey: Toggle Input/Control Mode")
                        DispatchQueue.main.async {
                            manager.toggleRecognitionInputControlMode(source: "keyboard-hotkey", persist: true)
                        }
                        return nil

                    case .toggleLanguage:
                        GlobalLogger.input.info("Hotkey: Toggle Language")
                        NotificationCenter.default.post(name: Notification.Name("AetherToggleLanguage"), object: nil)
                        return Unmanaged.passUnretained(event)

                    case .toggleShortcutPanel:
                        GlobalLogger.input.info("Hotkey: Toggle Shortcut Panel")
                        NotificationCenter.default.post(name: .toggleShortcutPanel, object: nil)
                        return nil

                    case .pushToTalk:
                        // If PTT is disabled, do not consume the event.
                        guard manager.isPTTEnabled else { return Unmanaged.passUnretained(event) }

                        let source = PTTSource.keyboard(Int(keyCode))
                        guard !manager.activePTTSources.contains(source) else { return nil }
                        GlobalLogger.input.info("Hotkey: PTT DOWN Detected (Keyboard)")
                        manager.beginPTT(from: source, origin: "keyboard-hotkey")
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
                     GlobalLogger.input.info("Hotkey: PTT UP Detected (Keyboard)")
                     manager.endPTT(from: source, origin: "keyboard-hotkey")
                     return nil
                }
            }
            
            if type == .leftMouseDown || type == .rightMouseDown || type == .otherMouseDown {
                DispatchQueue.main.async {
                    guard manager.transientRecognitionControlMode != nil else { return }
                    guard manager.transientRecognitionControlModeFollowsFocus else { return }
                    guard HUDManager.shared.hasRecentExplicitTypingClickReentry() else { return }
                    manager.clearTransientRecognitionControlMode(source: "mouse-input-refocus")
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
                            HUDManager.shared.showTemporary(
                                message: String(localized: "headset.hud.stop_tracking"),
                                icon: "stop.fill"
                            )
                            DispatchQueue.main.async { manager.stopTracking() }
                        } else {
                            GlobalLogger.input.info("Mouse Hotkey: Start Tracking")
                            HUDManager.shared.showTemporary(
                                message: String(localized: "headset.hud.start_tracking"),
                                icon: "play.fill"
                            )
                            DispatchQueue.main.async { manager.startTracking() }
                        }
                        return nil
                        
                    case .connectionLock:
                        GlobalLogger.input.info("Mouse Hotkey: Toggle Connection Lock")
                        HUDManager.shared.showTemporary(
                            message: String(localized: "headset.hud.connection_lock"),
                            icon: "lock.fill"
                        )
                        NotificationCenter.default.post(name: .toggleConnectionLock, object: nil)
                        return nil

                    case .toggleInputControlMode:
                        GlobalLogger.input.info("Mouse Hotkey: Toggle Input/Control Mode")
                        DispatchQueue.main.async {
                            manager.toggleRecognitionInputControlMode(source: "mouse-hotkey", persist: true)
                        }
                        return nil

                    case .toggleLanguage:
                        GlobalLogger.input.info("Mouse Hotkey: Toggle Language")
                        NotificationCenter.default.post(name: Notification.Name("AetherToggleLanguage"), object: nil)
                        return nil

                    case .toggleShortcutPanel:
                        GlobalLogger.input.info("Mouse Hotkey: Toggle Shortcut Panel")
                        NotificationCenter.default.post(name: .toggleShortcutPanel, object: nil)
                        return nil

                    case .pushToTalk:
                        // [Fix] STRICT CHECK: If PTT is disabled, bypass.
                        guard manager.isPTTEnabled else { break }
                        
                        let source = PTTSource.mouse(btn)
                        if !manager.activePTTSources.contains(source) {
                            GlobalLogger.input.info("Mouse PTT DOWN Detected (Button \(btn))")
                            manager.beginPTT(from: source, origin: "mouse-hotkey")
                        }
                        return nil
                    }
                }
            }
            
            if type == .otherMouseUp {
                let btn = Int(event.getIntegerValueField(.mouseEventButtonNumber))
                let source = PTTSource.mouse(btn)
                
                if manager.activePTTSources.contains(source) {
                    GlobalLogger.input.info("Mouse PTT UP Detected (Button \(btn))")
                    manager.endPTT(from: source, origin: "mouse-hotkey")
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
                HUDManager.shared.showTemporary(
                    message: String(localized: "headset.hud.disconnected"),
                    icon: "exclamationmark.triangle.fill"
                )
                self.onError?(msg)
                self.stopTrackingInternal()
                DispatchQueue.main.async { self.attitudeText = String(localized: "headset.status.disconnected") }
                return
            }
            
            // 2. Liveness Check (Timeout)
            if let lastTime = self.lastDataTime, Date().timeIntervalSince(lastTime) > 5.0 {
                os_log("Monitor: No data for 5s (Signal lost)", log: self.log, type: .error)
                let msg = String(localized: "motion.error.connection_lost") // "Connection lost. No data received."
                HUDManager.shared.showTemporary(
                    message: String(localized: "headset.hud.connection_lost"),
                    icon: "exclamationmark.triangle.fill"
                )
                self.onError?(msg)
                self.stopTrackingInternal()
                DispatchQueue.main.async { self.attitudeText = String(localized: "headset.status.signal_lost") }
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
            transientRecognitionControlModeFollowsFocus = false
            return
        }
        guard transientRecognitionControlModeFollowsFocus else { return }
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

        if transientRecognitionControlMode == .command,
           currentlyTyping,
           !HUDManager.shared.hasRecentExplicitTypingClickReentry() {
            return
        }

        setTransientRecognitionControlMode(nil)
        postRecognitionControlModeChanged(source: source)
        os_log("Recognition Mode transient override cleared (%{public}@): focus context changed",
               log: log, type: .info, source)
    }

    @MainActor
    private func clearTransientRecognitionControlMode(source: String) {
        guard transientRecognitionControlMode != nil else { return }
        guard persistentRecognitionControlMode == .auto else { return }
        let priorMode = effectiveRecognitionControlMode.rawValue
        setTransientRecognitionControlMode(nil)
        postRecognitionControlModeChanged(source: source)
        os_log("Recognition Mode transient override cleared (%{public}@): prior=%{public}@ typing=%{public}@ explicitReentry=%{public}@",
               log: log, type: .info, source, priorMode,
               String(HUDManager.shared.lastKnownTypingState()),
               String(HUDManager.shared.hasRecentExplicitTypingClickReentry()))
    }

    private func setTransientRecognitionControlMode(
        _ mode: RecognitionControlMode?,
        anchorTypingState: Bool? = nil,
        followsFocus: Bool = false
    ) {
        transientRecognitionControlMode = mode
        transientRecognitionControlModeFollowsFocus = (mode != nil) && followsFocus
        transientModeAnchorTypingState = mode == nil ? nil : anchorTypingState
        transientModeObservedTypingState = mode == nil ? nil : anchorTypingState
        transientModeObservedAt = mode == nil ? .distantPast : Date()
    }

}
