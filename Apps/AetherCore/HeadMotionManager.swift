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
    private static let recordedHeadGesturesStorageKey = "AetherRecordedHeadGesturesV1"
    private static let headGestureHistoryStorageKey = "AetherHeadGestureHistoryV1"
    private static let builtInNodGestureID = UUID(uuidString: "7A6C3C40-6A61-4B70-AE79-3E4F0D4C1001")!
    private static let builtInShakeGestureID = UUID(uuidString: "7A6C3C40-6A61-4B70-AE79-3E4F0D4C1002")!

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

    enum HeadGestureAction: String, CaseIterable, Identifiable, Codable, Sendable {
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
        let cursorLocation: CGPoint?
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

    struct RecordedHeadGesturePoint: Codable, Equatable {
        let x: Double
        let y: Double
        let t: Double
    }

    struct RecordedHeadGesture: Codable, Identifiable, Equatable {
        var id: UUID
        var name: String
        var action: HeadGestureAction
        var enabled: Bool
        var cooldown: TimeInterval
        var minimumScore: Double
        var recordedDuration: TimeInterval
        var points: [RecordedHeadGesturePoint]
        var alternateSamples: [[RecordedHeadGesturePoint]]?
    }

    enum HeadGestureHistoryResult: String, Codable {
        case saved
        case triggered
        case noMatch
        case cancelled
        case tooSimple
        case noAction

        var label: String {
            if AppLocalization.isChinese {
                switch self {
                case .saved: return "已保存"
                case .triggered: return "已触发"
                case .noMatch: return "未匹配"
                case .cancelled: return "已取消"
                case .tooSimple: return "动作过于简单"
                case .noAction: return "未绑定动作"
                }
            }
            switch self {
            case .saved: return "Saved"
            case .triggered: return "Triggered"
            case .noMatch: return "No Match"
            case .cancelled: return "Cancelled"
            case .tooSimple: return "Too Simple"
            case .noAction: return "No Action"
            }
        }
    }

    struct HeadGestureHistoryEntry: Codable, Identifiable, Equatable {
        var id: UUID
        var date: Date
        var gestureName: String
        var actionName: String
        var result: HeadGestureHistoryResult
        var score: Double?
        var duration: TimeInterval
        var summary: String
    }

    struct HeadGestureDebugSample: Codable, Equatable {
        var t: Double
        var yaw: Double
        var pitch: Double
        var cursorX: Double?
        var cursorY: Double?
    }

    struct HeadGestureDebugEntry: Codable, Identifiable, Equatable {
        var id: UUID
        var date: Date
        var mode: String
        var result: String
        var gestureName: String?
        var actionName: String?
        var bestMatchName: String?
        var bestScore: Double?
        var totalDistance: Double
        var duration: TimeInterval
        var sampleCount: Int
        var samples: [HeadGestureDebugSample]
    }

    private struct HeadGestureDebugExportPayload: Codable {
        var exportedAt: Date
        var recordedGestures: [RecordedHeadGesture]
        var history: [HeadGestureHistoryEntry]
        var debugEntries: [HeadGestureDebugEntry]
    }

    private struct ActiveGestureRecordingSession {
        let gestureID: UUID
        var samples: [HeadGestureSample] = []
        var startedAt: Date
        var lastActiveAt: Date
        var hasObservedMeaningfulMotion: Bool = false
    }

    private struct ActiveGestureCandidate {
        var samples: [HeadGestureSample] = []
        var startedAt: Date
        var lastActiveAt: Date
        var didPlayStartSound: Bool = false
        var didPlayTurnCue: Bool = false
    }

    private struct GestureTemplateSummary {
        let points: [CGPoint]
        let duration: TimeInterval
        let totalDistance: Double
        let turnCount: Int
        let xSignChanges: Int
        let ySignChanges: Int
    }

    private struct GestureMatch {
        let gesture: RecordedHeadGesture
        let score: Double
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
        headsetRouteObserver = NotificationCenter.default.addObserver(
            forName: .aetherHeadsetRouteChanged,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor [weak self] in
                self?.handleHeadsetRouteChanged(notification)
            }
        }
        startStabilityTimer()
        updateAirPodsRemoteCommandRegistration()
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.applyHeadsetRouteConnectionUpdate(HeadsetRouteState.shared.isConnected, source: "startup")
            self.applyAirPodsSideUpdate(self.lastObservedAirPodSide, source: "startup")
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
    @Published var recordedHeadGestures: [RecordedHeadGesture] = HeadMotionManager.loadRecordedHeadGestures() {
        didSet { HeadMotionManager.saveRecordedHeadGestures(recordedHeadGestures) }
    }
    @Published private(set) var headGestureHistory: [HeadGestureHistoryEntry] = HeadMotionManager.loadHeadGestureHistory() {
        didSet { HeadMotionManager.saveHeadGestureHistory(headGestureHistory) }
    }
    @Published private(set) var headGestureDebugEntries: [HeadGestureDebugEntry] = []
    @Published private(set) var activeHeadGestureRecordingID: UUID?
    @Published private(set) var headGestureRecordingCountdown: Int = 0
    @Published private(set) var isHeadGestureRecording: Bool = false
    @Published private(set) var headGestureRecordingStatusText: String = ""
    @Published private(set) var isAppendingHeadGestureSample: Bool = false
    
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
            guard hasActiveHeadsetConnection, !isTracking else { return }
            DispatchQueue.main.async { [weak self] in
                self?.scheduleAutoTrackingStartAfterConnection(trigger: "settings-enabled")
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
    private let headGestureMinPathDistance: Double = 0.12
    private let headGestureActivationDistance: Double = 0.12
    private let headGestureOverlayDistance: Double = 0.08
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
    private var activeGestureCandidate: ActiveGestureCandidate?
    private var activeGestureRecordingSession: ActiveGestureRecordingSession?
    private var pendingHeadGestureRecordingCountdownWorkItem: DispatchWorkItem?
    private lazy var headGestureOverlayController = HeadGestureOverlayController()
    
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
    // Smoothing
    private var currentX: CGFloat = 0
    private var currentY: CGFloat = 0
    
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
        case airPodsToggle
        case airPodsSeekForward
        case airPodsSeekBackward
    }
    private var activePTTSources: Set<PTTSource> = []
    private var isPTTPressed: Bool { !activePTTSources.isEmpty }
    
    // Full cursor movement workspace across all displays.
    private var desktopFrame: NSRect = .zero
    // Neutral center used for calibration/recenter, typically the current screen midpoint.
    private var recenterAnchor: CGPoint = .zero
    
    // Attention Awareness
    @Published var isLookingAtScreen: Bool = true
    private let attentionAwayThresholdYaw: Double = 0.82   // ~47 degrees before marking "away"
    private let attentionReturnThresholdYaw: Double = 0.72 // ~41 degrees to recover "looking"
    private let attentionAwayDebounceFrames: Int = 18
    private let attentionReturnDebounceFrames: Int = 8
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
    private let headGestureHistoryLimit = 180
    private let headGestureDebugEntryLimit = 80
    private var lastHeadsetSinglePressAt: Date = .distantPast
    private var lastHeadsetDoublePressAt: Date = .distantPast
    private var lastHeadsetTriplePressAt: Date = .distantPast
    private let headsetRemoteActionDebounce: TimeInterval = 0.75
    private var lastObservedAirPodSide: AirPodSide = .none
    private var lastObservedHeadsetRouteConnected: Bool = false
    private var pendingAutoTrackingStart: DispatchWorkItem?
    private var pendingAutoTrackingRetry: DispatchWorkItem?
    private var autoTrackingRetryAttempts: Int = 0
    private var airPodsStateObserver: NSObjectProtocol?
    private var headsetRouteObserver: NSObjectProtocol?
    private let headTrackingConnectionTimeout: TimeInterval = 8.0
    private var headTrackingConnectionGraceUsed = false

    private var hasActiveHeadsetConnection: Bool {
        lastObservedHeadsetRouteConnected || lastObservedAirPodSide != .none
    }

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

    private static func loadRecordedHeadGestures() -> [RecordedHeadGesture] {
        let decoded: [RecordedHeadGesture]
        if let data = UserDefaults.standard.data(forKey: recordedHeadGesturesStorageKey),
           let stored = try? JSONDecoder().decode([RecordedHeadGesture].self, from: data) {
            decoded = stored
        } else {
            decoded = []
        }
        return mergeBuiltInHeadGestures(into: decoded)
    }

    private static func saveRecordedHeadGestures(_ gestures: [RecordedHeadGesture]) {
        guard let data = try? JSONEncoder().encode(gestures) else { return }
        UserDefaults.standard.set(data, forKey: recordedHeadGesturesStorageKey)
    }

    private static func loadHeadGestureHistory() -> [HeadGestureHistoryEntry] {
        guard let data = UserDefaults.standard.data(forKey: headGestureHistoryStorageKey),
              let decoded = try? JSONDecoder().decode([HeadGestureHistoryEntry].self, from: data) else {
            return []
        }
        return decoded
    }

    private static func saveHeadGestureHistory(_ history: [HeadGestureHistoryEntry]) {
        guard let data = try? JSONEncoder().encode(history) else { return }
        UserDefaults.standard.set(data, forKey: headGestureHistoryStorageKey)
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

    private static func mergeBuiltInHeadGestures(into gestures: [RecordedHeadGesture]) -> [RecordedHeadGesture] {
        var merged = gestures
        let builtIns = builtInRecordedHeadGestures()
        for builtIn in builtIns where !merged.contains(where: { $0.id == builtIn.id }) {
            merged.append(builtIn)
        }
        return merged
    }

    private static func builtInRecordedHeadGestures() -> [RecordedHeadGesture] {
        [
            RecordedHeadGesture(
                id: builtInNodGestureID,
                name: AppLocalization.isChinese ? "内置点头" : "Built-in Nod",
                action: defaultHeadGestureAction(for: .nod),
                enabled: true,
                cooldown: 1.0,
                minimumScore: 0.64,
                recordedDuration: 0.58,
                points: builtInGesturePoints(kind: .nod),
                alternateSamples: [builtInGesturePoints(kind: .nod, variant: 1)]
            ),
            RecordedHeadGesture(
                id: builtInShakeGestureID,
                name: AppLocalization.isChinese ? "内置摇头" : "Built-in Shake",
                action: defaultHeadGestureAction(for: .shake),
                enabled: true,
                cooldown: 1.0,
                minimumScore: 0.64,
                recordedDuration: 0.62,
                points: builtInGesturePoints(kind: .shake),
                alternateSamples: [builtInGesturePoints(kind: .shake, variant: 1)]
            )
        ]
    }

    private static func builtInGesturePoints(kind: HeadGestureKind, variant: Int = 0) -> [RecordedHeadGesturePoint] {
        let raw = legacyGesturePrototype(kind: kind, variant: variant)
        let maxIndex = max(raw.count - 1, 1)
        return raw.enumerated().map { index, point in
            RecordedHeadGesturePoint(
                x: point.0,
                y: point.1,
                t: Double(index) / Double(maxIndex)
            )
        }
    }

    private static func legacyGesturePrototype(kind: HeadGestureKind, variant: Int) -> [(Double, Double)] {
        let phaseShift = variant == 0 ? 0.0 : 0.35
        let crossAxisOffset = variant == 0 ? 0.018 : 0.028
        let sampleCount = 15

        return (0..<sampleCount).map { index in
            let t = Double(index) / Double(sampleCount - 1)
            let phase = (t * .pi * 1.6) + phaseShift

            switch kind {
            case .nod:
                let x = 0.50 + (sin(phase * 1.8) * crossAxisOffset)
                let y = 0.50 + (sin(phase) * 0.34)
                return (
                    min(max(x, 0.10), 0.90),
                    min(max(y, 0.08), 0.92)
                )
            case .shake:
                let x = 0.50 + (sin(phase) * 0.36)
                let y = 0.50 + (sin(phase * 1.7) * crossAxisOffset)
                return (
                    min(max(x, 0.08), 0.92),
                    min(max(y, 0.12), 0.88)
                )
            }
        }
    }

    @MainActor
    func createRecordedHeadGesture() {
        let gesture = RecordedHeadGesture(
            id: UUID(),
            name: defaultRecordedHeadGestureName(for: .none),
            action: .none,
            enabled: true,
            cooldown: 1.0,
            minimumScore: 0.70,
            recordedDuration: 0.0,
            points: [],
            alternateSamples: nil
        )
        recordedHeadGestures.insert(gesture, at: 0)
        startRecordingRecordedHeadGesture(id: gesture.id)
    }

    @MainActor
    func deleteRecordedHeadGesture(id: UUID) {
        if activeHeadGestureRecordingID == id {
            cancelRecordedHeadGestureRecording()
        }
        recordedHeadGestures.removeAll { $0.id == id }
    }

    @MainActor
    func clearHeadGestureHistory() {
        headGestureHistory = []
    }

    @MainActor
    func copyHeadGestureHistory() throws {
        let header = AppLocalization.isChinese ? "头部动作历史：" : "Head Gesture History:"
        let lines = headGestureHistory.map { formatHeadGestureHistoryEntry($0) }
        try copyTextToPasteboard(([header] + lines).joined(separator: "\n"))
    }

    @MainActor
    func copyHeadGestureHistoryEntry(_ entry: HeadGestureHistoryEntry) throws {
        let header = AppLocalization.isChinese ? "头部动作历史（单条）：" : "Head Gesture Event:"
        try copyTextToPasteboard([header, formatHeadGestureHistoryEntry(entry)].joined(separator: "\n"))
    }

    @MainActor
    func exportHeadGestureDebugData() throws -> URL? {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = "AetherHeadGestureDebug.json"
        panel.prompt = AppLocalization.isChinese ? "导出调试数据" : "Export Debug Data"

        guard panel.runModal() == .OK, let url = panel.url else { return nil }

        let payload = HeadGestureDebugExportPayload(
            exportedAt: Date(),
            recordedGestures: recordedHeadGestures,
            history: headGestureHistory,
            debugEntries: headGestureDebugEntries
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(payload)
        try data.write(to: url, options: .atomic)
        return url
    }

    @MainActor
    func copyHeadGestureDebugData() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let payload = HeadGestureDebugExportPayload(
            exportedAt: Date(),
            recordedGestures: recordedHeadGestures,
            history: headGestureHistory,
            debugEntries: headGestureDebugEntries
        )
        let data = try encoder.encode(payload)
        guard let text = String(data: data, encoding: .utf8) else {
            throw NSError(
                domain: "AetherHeadGestureDebugCopy",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: AppLocalization.isChinese ? "复制调试数据失败" : "Failed to copy head gesture debug data"]
            )
        }
        try copyTextToPasteboard(formattedHeadGestureDebugRequest(json: text))
    }

    private func formattedHeadGestureDebugRequest(json: String) -> String {
        if AppLocalization.isChinese {
            return [
                "请基于下面这份 Aether 头部动作调试数据做分析，并按这个格式反馈：",
                "1. 先判断问题主要是参数问题，还是算法/特征设计问题，不要只说“调阈值试试”。",
                "2. 请分别说明：",
                "   - 点头 / 摇头 / 自定义动作，各自最可能失败的原因",
                "   - 是时长问题、幅度问题、轴耦合问题、模板问题，还是评分逻辑问题",
                "3. 请结合具体样本说明，至少点名这些字段：result、gestureName、bestMatchName、bestScore、duration、totalDistance、samples。",
                "4. 如果你建议改代码，请尽量给到可落地的改法，优先回答：",
                "   - 应不应该引入 DTW 或类似时序匹配",
                "   - 是否应该做动态基线 / 自动校准",
                "   - 是否应该给主轴和副轴不同权重",
                "   - 自定义动作要如何避免逐个手调参数",
                "5. 请给出“先改什么、后改什么”的优先级，不要泛泛而谈。",
                "",
                "调试数据 JSON：",
                json
            ].joined(separator: "\n")
        }

        return [
            "Please analyze the Aether head-gesture debug data below and reply in this format:",
            "1. First decide whether the main issue is parameter tuning or the algorithm/feature design. Do not stop at 'try adjusting thresholds'.",
            "2. Explain separately for nod, shake, and custom gestures:",
            "   - the most likely failure mode",
            "   - whether the issue is duration, amplitude, axis coupling, template quality, or scoring logic",
            "3. Use concrete samples and reference these fields when possible: result, gestureName, bestMatchName, bestScore, duration, totalDistance, samples.",
            "4. If you recommend code changes, make them actionable and prioritize these questions:",
            "   - Should we introduce DTW or another temporal matching approach?",
            "   - Should we add dynamic baseline / auto-calibration?",
            "   - Should primary and secondary axes use different weights?",
            "   - How should custom gestures work without per-gesture manual tuning?",
            "5. Give a clear priority order for the fixes.",
            "",
            "Debug JSON:",
            json
        ].joined(separator: "\n")
    }

    @MainActor
    func updateRecordedHeadGestureName(id: UUID, name: String) {
        guard let index = recordedHeadGestures.firstIndex(where: { $0.id == id }) else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        recordedHeadGestures[index].name = trimmed.isEmpty
            ? defaultRecordedHeadGestureName(for: recordedHeadGestures[index].action)
            : trimmed
    }

    @MainActor
    func updateRecordedHeadGestureAction(id: UUID, action: HeadGestureAction) {
        guard let index = recordedHeadGestures.firstIndex(where: { $0.id == id }) else { return }
        let previousAction = recordedHeadGestures[index].action
        let previousName = recordedHeadGestures[index].name
        recordedHeadGestures[index].action = action
        if shouldAutoRenameRecordedHeadGesture(
            currentName: previousName,
            previousAction: previousAction,
            newAction: action
        ) {
            recordedHeadGestures[index].name = defaultRecordedHeadGestureName(for: action)
        }
    }

    @MainActor
    func toggleRecordedHeadGestureEnabled(id: UUID, enabled: Bool) {
        guard let index = recordedHeadGestures.firstIndex(where: { $0.id == id }) else { return }
        recordedHeadGestures[index].enabled = enabled
    }

    private func defaultRecordedHeadGestureName(for action: HeadGestureAction) -> String {
        switch action {
        case .none:
            return AppLocalization.isChinese ? "未命名动作" : "Untitled Gesture"
        default:
            return action.label
        }
    }

    private func shouldAutoRenameRecordedHeadGesture(
        currentName: String,
        previousAction: HeadGestureAction,
        newAction: HeadGestureAction
    ) -> Bool {
        let trimmed = currentName.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return true
        }

        let automaticNames: Set<String> = [
            defaultRecordedHeadGestureName(for: .none),
            defaultRecordedHeadGestureName(for: previousAction),
            previousAction.label,
            newAction.label
        ]

        return automaticNames.contains(trimmed)
    }

    @MainActor
    func startRecordingRecordedHeadGesture(id: UUID, appendSample: Bool = false) {
        guard hasActiveHeadsetConnection, motionManager.isDeviceMotionAvailable else {
            HUDManager.shared.showTemporary(
                message: AppLocalization.isChinese ? "录制前请先连接支持头动的耳机" : "Connect a motion-capable headset before recording",
                icon: "airpods"
            )
            return
        }
        guard recordedHeadGestures.contains(where: { $0.id == id }) else { return }
        pendingHeadGestureRecordingCountdownWorkItem?.cancel()
        pendingHeadGestureRecordingCountdownWorkItem = nil
        activeHeadGestureRecordingID = id
        isAppendingHeadGestureSample = appendSample
        isHeadGestureRecording = false
        headGestureRecordingCountdown = 3
        headGestureRecordingStatusText = appendSample
            ? (AppLocalization.isChinese ? "准备追加样本" : "Get ready to add")
            : (AppLocalization.isChinese ? "准备录制" : "Get ready")
        activeGestureRecordingSession = nil
        activeGestureCandidate = nil
        resetHeadGestureRecognition()
        headGestureToggleEnabled = true
        refreshHeadGestureMonitoringState(source: "head-gesture-recording-start")
        HUDManager.shared.showTemporary(
            message: headGestureRecordingStatusText,
            icon: "waveform.path",
            duration: 1.0
        )

        for offset in 0...3 {
            let workItem = DispatchWorkItem { [weak self] in
                guard let self, self.activeHeadGestureRecordingID == id else { return }
                let remaining = 3 - offset
                self.headGestureRecordingCountdown = remaining
                if remaining > 0 {
                    self.headGestureRecordingStatusText = self.appLocalizedCountdownText(remaining: remaining)
                    HUDManager.shared.showTemporary(
                        message: self.headGestureRecordingStatusText,
                        icon: "waveform.path",
                        duration: 0.9
                    )
                } else {
                    self.beginRecordedHeadGestureCapture(id: id)
                }
            }
            pendingHeadGestureRecordingCountdownWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(offset), execute: workItem)
        }
    }

    @MainActor
    func cancelRecordedHeadGestureRecording() {
        pendingHeadGestureRecordingCountdownWorkItem?.cancel()
        pendingHeadGestureRecordingCountdownWorkItem = nil
        let gestureName = recordedHeadGestures.first(where: { $0.id == activeHeadGestureRecordingID })?.name
            ?? (AppLocalization.isChinese ? "头部动作" : "Head Gesture")
        if activeHeadGestureRecordingID != nil || isHeadGestureRecording {
            appendHeadGestureHistory(
                gestureName: gestureName,
                actionName: AppLocalization.isChinese ? "录制" : "Recording",
                result: .cancelled,
                score: nil,
                duration: activeGestureRecordingSession.map { Date().timeIntervalSince($0.startedAt) } ?? 0,
                summary: AppLocalization.isChinese ? "用户取消录制" : "Recording cancelled by user"
            )
        }
        activeHeadGestureRecordingID = nil
        isAppendingHeadGestureSample = false
        isHeadGestureRecording = false
        headGestureRecordingCountdown = 0
        headGestureRecordingStatusText = ""
        activeGestureRecordingSession = nil
        headGestureOverlayController.hide()
        HUDManager.shared.updateHeadGestureTrail(points: [], status: "", visible: false)
        playHeadGestureCancelSound()
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
        GlobalLogger.lifecycle.info(
            "HeadMotion startTracking requested autoStart=\(autoStartTrackingOnHeadsetConnection) routeConnected=\(lastObservedHeadsetRouteConnected) airPodsSide=\(lastObservedAirPodSide.rawValue) hasHeadset=\(hasActiveHeadsetConnection) motionAvailable=\(motionManager.isDeviceMotionAvailable)"
        )
        pendingAutoTrackingStart?.cancel()
        pendingAutoTrackingStart = nil
        pendingAutoTrackingRetry?.cancel()
        pendingAutoTrackingRetry = nil
        stopPassiveHeadGestureMonitoring(source: "tracking-start")
        
        // CRITICAL: Verify AirPods are actually available before starting
        // isDeviceMotionAvailable checks if the device SUPPORTS motion tracking
        // If it returns false, AirPods are definitely not connected
        if !motionManager.isDeviceMotionAvailable {
            let msg = String(localized: "motion.error.airpods_not_detected")
            attitudeText = String(localized: "headset.status.no_compatible")
            GlobalLogger.lifecycle.info(
                "HeadMotion startTracking aborted motionUnavailable routeConnected=\(lastObservedHeadsetRouteConnected) airPodsSide=\(lastObservedAirPodSide.rawValue)"
            )
            os_log("Cannot start tracking: AirPods not available", log: log, type: .error)
            HUDManager.shared.showTemporary(
                message: String(localized: "headset.hud.no_compatible"),
                icon: "xmark.circle.fill"
            )
            onError?(msg)
            Task { @MainActor [weak self] in
                self?.scheduleAutoTrackingRetryIfNeeded(reason: "motion-unavailable")
            }
            return // BLOCK tracking if AirPods not available
        }
        
        self.desktopFrame = aggregateDesktopFrame()
        let activeScreenFrame = activeTrackingScreenFrame()
        self.recenterAnchor = CGPoint(x: activeScreenFrame.midX, y: activeScreenFrame.midY)
        os_log("Tracking workspace selected: %@ recenterAnchor=(%.1f, %.1f)", log: log, String(describing: self.desktopFrame), self.recenterAnchor.x, self.recenterAnchor.y)
        
        self.calibrationStatus = String(localized: "headset.status.calibrating")
        self.isCalibrated = false
        self.isAirPodsStreamActive = false
        self.headTrackingConnectionGraceUsed = false
        self.refreshHeadsetRemoteStatus()
        
        // Reset attention state
        self.isLookingAtScreen = true
        
        // Start connection timeout timer. AirPods motion packets can arrive a bit late,
        // so keep the initial window forgiving to avoid self-inflicted reconnect loops.
        DispatchQueue.main.async {
            self.attitudeText = String(localized: "headset.status.connecting")
        }
        
        connectionTimer?.invalidate()
        connectionTimer = Timer.scheduledTimer(withTimeInterval: headTrackingConnectionTimeout, repeats: false) { [weak self] _ in
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
                Task { @MainActor [weak self] in
                    self?.scheduleAutoTrackingRetryIfNeeded(reason: "motion-error")
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
                self.autoTrackingRetryAttempts = 0
                self.isTracking = true
                GlobalLogger.lifecycle.info(
                    "HeadMotion first packet received routeConnected=\(self.lastObservedHeadsetRouteConnected) airPodsSide=\(self.lastObservedAirPodSide.rawValue)"
                )
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
            
            // Baseline (Center)
            if !self.isCalibrated {
                self.baseYaw = attitude.yaw
                self.basePitch = attitude.pitch
                self.isCalibrated = true
                self.isCalibratingRange = true
                self.minYaw = -0.3; self.maxYaw = 0.3
                self.minPitch = -0.2; self.maxPitch = 0.2
                
                self.currentX = self.recenterAnchor.x
                self.currentY = self.recenterAnchor.y
                return
            }
            
            let offYaw = attitude.yaw - self.baseYaw
            let offPitch = attitude.pitch - self.basePitch

            Task { @MainActor [weak self] in
                self?.processHeadGestureSample(yaw: offYaw, pitch: offPitch)
            }
            
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
            
            let rawTargetX = self.targetCoordinate(
                for: CGFloat(normX),
                anchor: self.recenterAnchor.x,
                minimum: self.desktopFrame.minX,
                maximum: self.desktopFrame.maxX,
                invertDirection: true
            )
            let rawTargetY = self.targetCoordinate(
                for: CGFloat(normY),
                anchor: self.recenterAnchor.y,
                minimum: self.desktopFrame.minY,
                maximum: self.desktopFrame.maxY,
                invertDirection: false
            )

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
            if self.isDebugModeEnabled {
                self.attitudeText = String(format: "Y: %.2f, P: %.2f", attitude.yaw, attitude.pitch)
            } else if self.attitudeText != String(localized: "headset.status.tracking") {
                self.attitudeText = String(localized: "headset.status.tracking")
            }
            
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
    
    private func handleConnectionTimeout() {
        guard !isTracking else { return } // Already connected
        if !headTrackingConnectionGraceUsed,
           hasActiveHeadsetConnection,
           motionManager.isDeviceMotionAvailable {
            headTrackingConnectionGraceUsed = true
            GlobalLogger.lifecycle.info(
                "HeadMotion connection timeout grace extension routeConnected=\(lastObservedHeadsetRouteConnected) airPodsSide=\(lastObservedAirPodSide.rawValue)"
            )
            connectionTimer?.invalidate()
            connectionTimer = Timer.scheduledTimer(withTimeInterval: 4.0, repeats: false) { [weak self] _ in
                self?.handleConnectionTimeout()
            }
            return
        }
        GlobalLogger.lifecycle.info(
            "HeadMotion connection timeout routeConnected=\(lastObservedHeadsetRouteConnected) airPodsSide=\(lastObservedAirPodSide.rawValue) motionAvailable=\(motionManager.isDeviceMotionAvailable)"
        )
        os_log("Aether: Connection Timeout - No data received", log: log, type: .error)
        
        let msg = String(localized: "motion.error.connection_timeout")
        HUDManager.shared.showTemporary(
            message: String(localized: "headset.hud.connection_timeout"),
            icon: "xmark.circle.fill"
        )
        onError?(msg)
        
        stopTrackingInternal()
        Task { @MainActor [weak self] in
            self?.scheduleAutoTrackingRetryIfNeeded(reason: "connection-timeout")
        }
        
        DispatchQueue.main.async {
            self.attitudeText = String(localized: "headset.status.connection_failed")
        }
    }

    @MainActor
    private func scheduleAutoTrackingRetryIfNeeded(reason: String) {
        guard autoStartTrackingOnHeadsetConnection, !isTracking, hasActiveHeadsetConnection else { return }
        guard autoTrackingRetryAttempts < 3 else { return }

        autoTrackingRetryAttempts += 1
        pendingAutoTrackingRetry?.cancel()

        let retryDelay = 0.8 + (Double(autoTrackingRetryAttempts - 1) * 0.6)
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            guard self.autoStartTrackingOnHeadsetConnection, !self.isTracking, self.hasActiveHeadsetConnection else { return }
            self.startTracking()
        }
        pendingAutoTrackingRetry = workItem
        os_log(
            "Head tracking auto-start retry scheduled (%{public}@) attempt=%{public}d delay=%.2f",
            log: log,
            type: .info,
            reason,
            autoTrackingRetryAttempts,
            retryDelay
        )
        DispatchQueue.main.asyncAfter(deadline: .now() + retryDelay, execute: workItem)
    }
    
    func stopTracking() {
        pendingAutoTrackingStart?.cancel()
        pendingAutoTrackingStart = nil
        GlobalLogger.lifecycle.info("HeadMotion stopTracking requested")
        stopTrackingInternal()
    }

    private func stopTrackingInternal() {
        GlobalLogger.lifecycle.info(
            "HeadMotion stopTrackingInternal isTracking=\(isTracking) routeConnected=\(lastObservedHeadsetRouteConnected) airPodsSide=\(lastObservedAirPodSide.rawValue)"
        )
        connectionTimer?.invalidate()
        connectionTimer = nil
        pendingAutoTrackingRetry?.cancel()
        pendingAutoTrackingRetry = nil

        if AutomationOutputs.shared.isDraggingActive {
            AutomationOutputs.shared.drag(start: false, at: nil)
            HUDManager.shared.setDragStatusActive(false, language: AppLocalization.resolvedLocaleIdentifier)
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
        if !hasActiveHeadsetConnection {
            autoTrackingRetryAttempts = 0
        }
        refreshHeadsetRemoteStatus()
        resetHeadGestureRecognition()
        os_log("Aether: Stopped tracking", log: log)
    }

    private func refreshHeadGestureMonitoringState(source: String) {
        guard !isTracking else {
            stopPassiveHeadGestureMonitoring(source: "\(source)-tracking-active")
            return
        }

        let shouldMonitor = headGestureToggleEnabled && hasActiveHeadsetConnection && motionManager.isDeviceMotionAvailable
        if shouldMonitor {
            startPassiveHeadGestureMonitoring(source: source)
        } else {
            os_log(
                "Head gesture monitor idle (%{public}@): enabled=%{public}@ connected=%{public}@ routeConnected=%{public}@ side=%{public}@ motionAvailable=%{public}@",
                log: log,
                type: .info,
                source,
                String(headGestureToggleEnabled),
                String(hasActiveHeadsetConnection),
                String(lastObservedHeadsetRouteConnected),
                lastObservedAirPodSide.rawValue,
                String(motionManager.isDeviceMotionAvailable)
            )
            stopPassiveHeadGestureMonitoring(source: source)
        }
    }

    private func startPassiveHeadGestureMonitoring(source: String) {
        guard !isTracking else { return }
        guard headGestureToggleEnabled else { return }
        guard hasActiveHeadsetConnection else { return }
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
            Task { @MainActor [weak self] in
                self?.handlePassiveHeadGestureMotion(attitude)
            }
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

    @MainActor
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
        Task { @MainActor [weak self] in
            self?.processHeadGestureSample(yaw: offYaw, pitch: offPitch)
        }
    }

    private func resetHeadGestureRecognition() {
        recentHeadGestureSamples.removeAll(keepingCapacity: false)
        activeGestureCandidate = nil
        headGestureOverlayController.hide()
        HUDManager.shared.updateHeadGestureTrail(points: [], status: "", visible: false)
    }

    @MainActor
    private func processHeadGestureSample(yaw: Double, pitch: Double) {
        guard headGestureToggleEnabled else { return }

        let now = Date()
        let cursorLocation = currentSystemCursorLocation()
        recentHeadGestureSamples.append(HeadGestureSample(at: now, yaw: yaw, pitch: pitch, cursorLocation: cursorLocation))
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

        trackRecordedHeadGestureCapture(yaw: yaw, pitch: pitch, now: now, cursorLocation: cursorLocation)
        trackRecordedHeadGestureCandidate(yaw: yaw, pitch: pitch, now: now, cursorLocation: cursorLocation)
    }

    @MainActor
    private func trackRecordedHeadGestureCapture(yaw: Double, pitch: Double, now: Date, cursorLocation: CGPoint?) {
        guard let activeID = activeHeadGestureRecordingID else { return }
        guard isHeadGestureRecording else { return }
        guard var session = activeGestureRecordingSession, session.gestureID == activeID else { return }

        let sample = HeadGestureSample(at: now, yaw: yaw, pitch: pitch, cursorLocation: cursorLocation)
        session.samples.append(sample)
        let isMeaningful = hypot(yaw, pitch) >= 0.08
        if isMeaningful {
            session.lastActiveAt = now
            session.hasObservedMeaningfulMotion = true
        }
        activeGestureRecordingSession = session

        headGestureOverlayController.show(
            points: overlayTrailPoints(for: session.samples),
            status: headGestureRecordingStatusText.isEmpty
                ? (AppLocalization.isChinese ? "正在录制" : "Recording")
                : headGestureRecordingStatusText,
            emphasis: .recording,
            cursorLocation: cursorLocation
        )

        let recordingDuration = now.timeIntervalSince(session.startedAt)
        if recordingDuration >= 2.8 {
            finishRecordedHeadGestureCapture(reason: .saved)
            return
        }
        if session.hasObservedMeaningfulMotion,
           now.timeIntervalSince(session.lastActiveAt) >= 0.45,
           session.samples.count >= 10 {
            finishRecordedHeadGestureCapture(reason: .saved)
        }
    }

    @MainActor
    private func trackRecordedHeadGestureCandidate(yaw: Double, pitch: Double, now: Date, cursorLocation: CGPoint?) {
        guard !isHeadGestureRecording else { return }
        guard now.timeIntervalSince(lastHeadGestureTriggerAt) >= 1.25 else { return }
        let enabledGestures = eligibleHeadGesturesForRecognition()
        guard !enabledGestures.isEmpty else { return }

        let magnitude = hypot(yaw, pitch)
        let isActiveSample = magnitude >= 0.09

        if activeGestureCandidate == nil {
            let seedSamples = candidateSeedSamples(from: recentHeadGestureSamples, now: now)
            guard gestureActivationDistance(from: seedSamples) >= headGestureActivationDistance else { return }
            activeGestureCandidate = ActiveGestureCandidate(
                samples: seedSamples,
                startedAt: seedSamples.first?.at ?? now,
                lastActiveAt: now,
                didPlayStartSound: false,
                didPlayTurnCue: false
            )
        } else {
            activeGestureCandidate?.samples.append(HeadGestureSample(at: now, yaw: yaw, pitch: pitch, cursorLocation: cursorLocation))
            if isActiveSample {
                activeGestureCandidate?.lastActiveAt = now
            }
        }

        guard var candidate = activeGestureCandidate else { return }
        let duration = now.timeIntervalSince(candidate.startedAt)
        if !candidate.didPlayStartSound, duration >= 0.22 {
            candidate.didPlayStartSound = true
            activeGestureCandidate = candidate
            if shouldAnnounceHeadGestureRecognitionFeedback {
                HUDManager.shared.showTemporary(
                    message: AppLocalization.isChinese ? "开始识别" : "Listening",
                    icon: "waveform",
                    duration: 0.6
                )
            }
        }

        if candidate.didPlayStartSound,
           !candidate.didPlayTurnCue,
           shouldPlayBuiltInTurnCue(for: candidate.samples) {
            candidate.didPlayTurnCue = true
            activeGestureCandidate = candidate
            if shouldAnnounceHeadGestureRecognitionFeedback {
                playHeadGestureTurnCueSound()
            }
        }

        let liveOverlayThreshold = candidate.samples.count >= 4 && duration >= 0.06 && liveOverlayDistance(for: candidate.samples) >= headGestureOverlayDistance
        if candidate.didPlayStartSound, liveOverlayThreshold {
            let status: String
            if let tentativeMatch = bestGestureMatch(for: candidate.samples),
               tentativeMatch.score >= requiredScore(for: tentativeMatch.gesture, fallback: 0.56) {
                status = AppLocalization.isChinese
                    ? "可能：\(tentativeMatch.gesture.action.label)"
                    : "Possible: \(tentativeMatch.gesture.action.label)"
            } else {
                status = AppLocalization.isChinese ? "识别中…" : "Recognizing…"
            }
            headGestureOverlayController.show(
                points: overlayTrailPoints(for: candidate.samples),
                status: status,
                emphasis: .live,
                cursorLocation: cursorLocation
            )
        } else if candidate.didPlayStartSound {
            headGestureOverlayController.hide(after: 0.08)
        }

        let shouldFinish = now.timeIntervalSince(candidate.lastActiveAt) >= 0.28 || duration >= 2.2
        guard shouldFinish else { return }

        activeGestureCandidate = nil
        guard candidate.samples.count >= 6 else {
            headGestureOverlayController.hide(after: 0.12)
            return
        }
        evaluateHeadGestureCandidate(candidate)
    }

    @MainActor
    private func evaluateHeadGestureCandidate(_ candidate: ActiveGestureCandidate) {
        let summary = summarizeGesture(samples: candidate.samples)
        let candidateDistance = gestureActivationDistance(from: candidate.samples)
        guard isMatchableGesture(summary) else {
            guard candidateDistance >= headGestureMinPathDistance else {
                headGestureOverlayController.hide(after: 0.10)
                return
            }
            appendHeadGestureDebugEntry(
                mode: "recognition",
                result: HeadGestureHistoryResult.tooSimple.rawValue,
                samples: candidate.samples,
                gestureName: nil,
                actionName: nil,
                bestMatchName: nil,
                bestScore: nil
            )
            appendHeadGestureHistory(
                gestureName: AppLocalization.isChinese ? "未匹配动作" : "Unmatched Gesture",
                actionName: AppLocalization.isChinese ? "无" : "None",
                result: .tooSimple,
                score: nil,
                duration: summary?.duration ?? 0,
                summary: AppLocalization.isChinese ? "轨迹长度不够，已忽略" : "Ignored because the path length was too short"
            )
            if shouldAnnounceHeadGestureRecognitionFeedback {
                HUDManager.shared.showTemporary(
                    message: AppLocalization.isChinese ? "动作太短" : "Gesture too short",
                    icon: "scribble"
                )
                playHeadGestureNoMatchSound()
            }
            headGestureOverlayController.hide(after: 0.18)
            return
        }

        guard let summary else { return }
        let enabledGestures = eligibleHeadGesturesForRecognition()
        let matches = enabledGestures.compactMap { gesture -> GestureMatch? in
            guard gesturePassesDirectionalGate(gesture: gesture, samples: candidate.samples) else {
                return nil
            }
            let bestScore = recordedTemplates(for: gesture)
                .compactMap { summarizeGesture(points: $0) }
                .map { scoreGesture(summary, against: $0) }
                .max()
            guard let bestScore else { return nil }
            return GestureMatch(gesture: gesture, score: bestScore)
        }.sorted { $0.score > $1.score }

        guard let best = matches.first,
              best.score >= requiredScore(for: best.gesture) else {
            appendHeadGestureDebugEntry(
                mode: "recognition",
                result: HeadGestureHistoryResult.noMatch.rawValue,
                samples: candidate.samples,
                gestureName: nil,
                actionName: nil,
                bestMatchName: matches.first?.gesture.name,
                bestScore: matches.first?.score
            )
            appendHeadGestureHistory(
                gestureName: AppLocalization.isChinese ? "未匹配动作" : "Unmatched Gesture",
                actionName: AppLocalization.isChinese ? "无" : "None",
                result: .noMatch,
                score: matches.first?.score,
                duration: summary.duration,
                summary: AppLocalization.isChinese ? "没有找到匹配的模板" : "No recorded gesture matched"
            )
            if shouldAnnounceHeadGestureRecognitionFeedback {
                HUDManager.shared.showTemporary(
                    message: AppLocalization.isChinese ? "没匹配上" : "No gesture matched",
                    icon: "xmark.circle"
                )
                playHeadGestureNoMatchSound()
            }
            headGestureOverlayController.hide(after: 0.18)
            return
        }

        lastHeadGestureTriggerAt = Date()
        let preflightMessage = AppLocalization.isChinese
            ? "将触发：\(best.gesture.action.label)"
            : "About to trigger: \(best.gesture.action.label)"
        if shouldAnnounceHeadGestureRecognitionFeedback {
            HUDManager.shared.showTemporary(message: preflightMessage, icon: "bolt.fill", duration: 0.55)
        }
        headGestureOverlayController.show(
            points: overlayTrailPoints(for: candidate.samples),
            status: preflightMessage,
            emphasis: .matched,
            cursorLocation: currentSystemCursorLocation()
        )

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.14) { [weak self] in
            guard let self else { return }
            guard Date().timeIntervalSince(self.lastHeadGestureTriggerAt) < 0.5 else { return }
            self.fireMatchedHeadGesture(best, duration: summary.duration, samples: candidate.samples)
        }
    }

    @MainActor
    private func fireMatchedHeadGesture(_ match: GestureMatch, duration: TimeInterval, samples: [HeadGestureSample]) {
        noteHeadGestureEvent(
            display: "\(match.gesture.name) · \(match.gesture.action.label)"
        )
        guard let action = match.gesture.action.hotkeyAction else {
            appendHeadGestureDebugEntry(
                mode: "recognition",
                result: HeadGestureHistoryResult.noAction.rawValue,
                samples: samples,
                gestureName: match.gesture.name,
                actionName: match.gesture.action.label,
                bestMatchName: match.gesture.name,
                bestScore: match.score
            )
            appendHeadGestureHistory(
                gestureName: match.gesture.name,
                actionName: match.gesture.action.label,
                result: .noAction,
                score: match.score,
                duration: duration,
                summary: AppLocalization.isChinese ? "已识别，但未绑定动作" : "Matched, but no action is assigned"
            )
            HUDManager.shared.showTemporary(
                message: AppLocalization.isChinese ? "动作未绑定" : "Gesture has no action",
                icon: "exclamationmark.circle"
            )
            playHeadGestureNoMatchSound()
            return
        }

        playHeadGestureSuccessSound()
        performHeadsetAction(action, source: "recorded-head-gesture-\(match.gesture.id.uuidString)")
        headGestureOverlayController.hide(after: 0.22)
        appendHeadGestureDebugEntry(
            mode: "recognition",
            result: HeadGestureHistoryResult.triggered.rawValue,
            samples: samples,
            gestureName: match.gesture.name,
            actionName: match.gesture.action.label,
            bestMatchName: match.gesture.name,
            bestScore: match.score
        )
        appendHeadGestureHistory(
            gestureName: match.gesture.name,
            actionName: match.gesture.action.label,
            result: .triggered,
            score: match.score,
            duration: duration,
            summary: AppLocalization.isChinese ? "动作已触发" : "Gesture action triggered"
        )
    }

    @MainActor
    private func beginRecordedHeadGestureCapture(id: UUID) {
        guard activeHeadGestureRecordingID == id else { return }
        headGestureRecordingCountdown = 0
        isHeadGestureRecording = true
        headGestureRecordingStatusText = isAppendingHeadGestureSample
            ? (AppLocalization.isChinese ? "做动作，停下后追加样本" : "Perform gesture, then pause to add")
            : (AppLocalization.isChinese ? "做动作，停下后自动保存" : "Perform gesture, then pause to save")
        activeGestureRecordingSession = ActiveGestureRecordingSession(
            gestureID: id,
            startedAt: Date(),
            lastActiveAt: Date()
        )
        HUDManager.shared.showTemporary(
            message: headGestureRecordingStatusText,
            icon: "record.circle",
            duration: 1.2
        )
        playHeadGestureStartSound()
    }

    @MainActor
    private func finishRecordedHeadGestureCapture(reason: HeadGestureHistoryResult) {
        guard let recordingID = activeHeadGestureRecordingID,
              let session = activeGestureRecordingSession,
              let index = recordedHeadGestures.firstIndex(where: { $0.id == recordingID }) else {
            cancelRecordedHeadGestureRecording()
            return
        }

        pendingHeadGestureRecordingCountdownWorkItem?.cancel()
        pendingHeadGestureRecordingCountdownWorkItem = nil
        activeHeadGestureRecordingID = nil
        isHeadGestureRecording = false
        headGestureRecordingCountdown = 0
        activeGestureRecordingSession = nil
        let isAppendingSample = isAppendingHeadGestureSample
        isAppendingHeadGestureSample = false

        guard let summary = summarizeGesture(samples: session.samples) else {
            headGestureRecordingStatusText = ""
            playHeadGestureNoMatchSound()
            HUDManager.shared.showTemporary(
                message: AppLocalization.isChinese ? "录制太短" : "Recording too short",
                icon: "xmark.circle"
            )
            return
        }

        guard isRecordableGesture(summary) else {
            headGestureRecordingStatusText = ""
            playHeadGestureNoMatchSound()
            appendHeadGestureDebugEntry(
                mode: "recording",
                result: HeadGestureHistoryResult.tooSimple.rawValue,
                samples: session.samples,
                gestureName: recordedHeadGestures[index].name,
                actionName: recordedHeadGestures[index].action.label,
                bestMatchName: nil,
                bestScore: nil
            )
            HUDManager.shared.showTemporary(
                message: AppLocalization.isChinese ? "轨迹太短" : "Gesture too short",
                icon: "scribble"
            )
            appendHeadGestureHistory(
                gestureName: recordedHeadGestures[index].name,
                actionName: AppLocalization.isChinese ? "录制" : "Recording",
                result: .tooSimple,
                score: nil,
                duration: summary.duration,
                summary: AppLocalization.isChinese ? "录制失败：总轨迹长度不够" : "Recording failed because the total path length was too short"
            )
            return
        }

        let capturedPoints = summary.points.enumerated().map { idx, point in
            RecordedHeadGesturePoint(
                x: Double(point.x),
                y: Double(point.y),
                t: summary.duration == 0 ? 0 : Double(summary.duration) * Double(idx) / Double(max(summary.points.count - 1, 1))
            )
        }
        if isAppendingSample, !recordedHeadGestures[index].points.isEmpty {
            var alternate = recordedHeadGestures[index].alternateSamples ?? []
            alternate.append(capturedPoints)
            recordedHeadGestures[index].alternateSamples = alternate
        } else {
            recordedHeadGestures[index].points = capturedPoints
            recordedHeadGestures[index].alternateSamples = []
        }
        recordedHeadGestures[index].recordedDuration = summary.duration
        headGestureRecordingStatusText = ""
        appendHeadGestureDebugEntry(
            mode: "recording",
            result: reason.rawValue,
            samples: session.samples,
            gestureName: recordedHeadGestures[index].name,
            actionName: recordedHeadGestures[index].action.label,
            bestMatchName: recordedHeadGestures[index].name,
            bestScore: 1.0
        )
        headGestureOverlayController.show(
            points: overlayTrailPoints(for: session.samples),
            status: isAppendingSample
                ? (AppLocalization.isChinese ? "已追加样本" : "Sample added")
                : (AppLocalization.isChinese ? "已保存" : "Saved"),
            emphasis: .matched,
            cursorLocation: currentSystemCursorLocation()
        )
        playHeadGestureSuccessSound()
        HUDManager.shared.showTemporary(
            message: isAppendingSample
                ? (AppLocalization.isChinese ? "已追加样本" : "Added sample")
                : (AppLocalization.isChinese ? "动作已保存" : "Gesture saved"),
            icon: "checkmark.circle.fill"
        )
        appendHeadGestureHistory(
            gestureName: recordedHeadGestures[index].name,
            actionName: recordedHeadGestures[index].action.label,
            result: reason,
            score: 1.0,
            duration: summary.duration,
            summary: isAppendingSample
                ? (AppLocalization.isChinese ? "已追加一个动作样本" : "Added one gesture sample")
                : (AppLocalization.isChinese ? "已保存新的动作模板" : "Saved a new gesture template")
        )
        headGestureOverlayController.hide(after: 0.6)
    }

    private func summarizeGesture(samples: [HeadGestureSample]) -> GestureTemplateSummary? {
        guard samples.count >= 6 else { return nil }
        let points = samples.map { scaledGesturePoint(yaw: $0.yaw, pitch: $0.pitch) }
        let duration = max(samples.last?.at.timeIntervalSince(samples.first?.at ?? .distantPast) ?? 0, 0)
        return summarizeGesture(points: points, duration: duration)
    }

    private func summarizeGesture(points: [RecordedHeadGesturePoint]) -> GestureTemplateSummary? {
        let cgPoints = points.map { CGPoint(x: $0.x, y: $0.y) }
        let duration = max(points.last?.t ?? 0, 0)
        return summarizeGesture(points: cgPoints, duration: duration)
    }

    private func recordedTemplates(for gesture: RecordedHeadGesture) -> [[RecordedHeadGesturePoint]] {
        var templates: [[RecordedHeadGesturePoint]] = []
        if !gesture.points.isEmpty {
            templates.append(gesture.points)
        }
        templates.append(contentsOf: gesture.alternateSamples ?? [])
        return templates
    }

    func recordedSampleCount(for gesture: RecordedHeadGesture) -> Int {
        recordedTemplates(for: gesture).count
    }

    private func summarizeGesture(points rawPoints: [CGPoint], duration: TimeInterval) -> GestureTemplateSummary? {
        guard rawPoints.count >= 6 else { return nil }
        let simplified = dedupedGesturePoints(rawPoints)
        guard simplified.count >= 6 else { return nil }
        let smoothed = smoothedGesturePoints(simplified, radius: 2)
        let translated = smoothed.map { CGPoint(x: $0.x - smoothed[0].x, y: $0.y - smoothed[0].y) }
        let totalDistance = pathLength(translated)
        guard totalDistance >= headGestureMinPathDistance else { return nil }
        let resampled = resampleGesturePoints(translated, count: 18)
        let bounds = resampled.reduce(into: CGRect.null) { partialResult, point in
            let rect = CGRect(origin: point, size: .zero).insetBy(dx: -0.0001, dy: -0.0001)
            partialResult = partialResult.union(rect)
        }
        let scale = max(max(bounds.width, bounds.height), 0.01)
        let normalized = resampled.map { point in
            CGPoint(
                x: (point.x - bounds.minX) / scale,
                y: (point.y - bounds.minY) / scale
            )
        }
        return GestureTemplateSummary(
            points: normalized,
            duration: duration,
            totalDistance: totalDistance,
            turnCount: gestureTurnCount(points: translated),
            xSignChanges: signChanges(values: translated.map(\.x)),
            ySignChanges: signChanges(values: translated.map(\.y))
        )
    }

    private func scaledGesturePoint(yaw: Double, pitch: Double) -> CGPoint {
        CGPoint(x: yaw * 0.64, y: pitch)
    }

    private func isRecordableGesture(_ summary: GestureTemplateSummary?) -> Bool {
        guard let summary else { return false }
        guard summary.duration <= 2.8 else { return false }
        return summary.totalDistance >= headGestureMinPathDistance
    }

    private func isMatchableGesture(_ summary: GestureTemplateSummary?) -> Bool {
        guard let summary else { return false }
        guard summary.duration <= 2.8 else { return false }
        return summary.totalDistance >= headGestureMinPathDistance
    }

    private func scoreGesture(_ candidate: GestureTemplateSummary, against template: GestureTemplateSummary) -> Double {
        guard candidate.points.count == template.points.count else { return 0 }
        let pointDistance = zip(candidate.points, template.points).reduce(0.0) { partial, pair in
            let dx = pair.0.x - pair.1.x
            let dy = pair.0.y - pair.1.y
            return partial + Double(hypot(dx, dy))
        } / Double(candidate.points.count)
        let distanceScore = max(0.0, 1.0 - (pointDistance / 1.65))
        let durationRatio = template.duration > 0 ? abs(candidate.duration - template.duration) / max(template.duration, 0.1) : 0
        let durationScore = max(0.0, 1.0 - min(durationRatio, 0.8))
        let complexityDelta = abs(candidate.turnCount - template.turnCount)
        let complexityScore = max(0.0, 1.0 - (Double(complexityDelta) / 4.0))
        return (distanceScore * 0.85) + (durationScore * 0.07) + (complexityScore * 0.08)
    }

    private func requiredScore(for gesture: RecordedHeadGesture, fallback: Double = 0.58) -> Double {
        // Apply a small tolerance so stored thresholds don't make custom gestures too strict.
        max(fallback, gesture.minimumScore - 0.08)
    }

    private var shouldAnnounceHeadGestureRecognitionFeedback: Bool {
        isTracking
    }

    private func eligibleHeadGesturesForRecognition() -> [RecordedHeadGesture] {
        let enabled = recordedHeadGestures.filter { $0.enabled && !$0.points.isEmpty }
        guard !isTracking else { return enabled }
        return enabled.filter { $0.action == .toggleTracking }
    }

    private func builtInGestureKind(for gesture: RecordedHeadGesture) -> HeadGestureKind? {
        switch gesture.id {
        case Self.builtInNodGestureID:
            return .nod
        case Self.builtInShakeGestureID:
            return .shake
        default:
            return nil
        }
    }

    private func gesturePassesDirectionalGate(gesture: RecordedHeadGesture, samples: [HeadGestureSample]) -> Bool {
        guard let kind = builtInGestureKind(for: gesture) else { return true }
        let pitchMetrics = axisMetrics(samples: samples, keyPath: \.pitch, threshold: headGestureNodThreshold)
        let yawMetrics = axisMetrics(samples: samples, keyPath: \.yaw, threshold: headGestureShakeThreshold)
        switch kind {
        case .nod:
            return pitchMetrics.amplitude >= (headGestureNodAmplitude * 0.55)
                && pitchMetrics.signChanges >= 1
                && pitchMetrics.peakCount >= 1
                && pitchMetrics.amplitude >= (yawMetrics.amplitude * 0.95)
        case .shake:
            return yawMetrics.amplitude >= (headGestureShakeAmplitude * 0.55)
                && yawMetrics.signChanges >= 1
                && yawMetrics.peakCount >= 1
                && yawMetrics.amplitude >= (pitchMetrics.amplitude * 0.95)
        }
    }

    private func shouldPlayBuiltInTurnCue(for samples: [HeadGestureSample]) -> Bool {
        let pitchMetrics = axisMetrics(samples: samples, keyPath: \.pitch, threshold: headGestureNodThreshold)
        let yawMetrics = axisMetrics(samples: samples, keyPath: \.yaw, threshold: headGestureShakeThreshold)
        let nodReady = pitchMetrics.amplitude >= (headGestureNodAmplitude * 0.55)
            && pitchMetrics.peakCount >= 1
            && pitchMetrics.amplitude >= (yawMetrics.amplitude * 0.95)
        let shakeReady = yawMetrics.amplitude >= (headGestureShakeAmplitude * 0.55)
            && yawMetrics.peakCount >= 1
            && yawMetrics.amplitude >= (pitchMetrics.amplitude * 0.95)
        return nodReady || shakeReady
    }

    private func bestGestureMatch(for samples: [HeadGestureSample]) -> GestureMatch? {
        guard let summary = summarizeGesture(samples: samples), isMatchableGesture(summary) else { return nil }
        return eligibleHeadGesturesForRecognition()
            .compactMap { gesture -> GestureMatch? in
                guard gesturePassesDirectionalGate(gesture: gesture, samples: samples) else { return nil }
                let bestScore = recordedTemplates(for: gesture)
                    .compactMap { summarizeGesture(points: $0) }
                    .map { scoreGesture(summary, against: $0) }
                    .max()
                guard let bestScore else { return nil }
                return GestureMatch(gesture: gesture, score: bestScore)
            }
            .sorted { $0.score > $1.score }
            .first
    }

    private func dedupedGesturePoints(_ points: [CGPoint]) -> [CGPoint] {
        var result: [CGPoint] = []
        for point in points {
            if let last = result.last, hypot(point.x - last.x, point.y - last.y) < 0.003 {
                continue
            }
            result.append(point)
        }
        return result
    }

    private func smoothedGesturePoints(_ points: [CGPoint], radius: Int) -> [CGPoint] {
        guard points.count > 2, radius > 0 else { return points }
        return points.indices.map { index in
            let lower = max(points.startIndex, index - radius)
            let upper = min(points.endIndex - 1, index + radius)
            let slice = points[lower...upper]
            let avgX = slice.reduce(CGFloat.zero) { $0 + $1.x } / CGFloat(slice.count)
            let avgY = slice.reduce(CGFloat.zero) { $0 + $1.y } / CGFloat(slice.count)
            return CGPoint(x: avgX, y: avgY)
        }
    }

    private func candidateSeedSamples(from samples: [HeadGestureSample], now: Date) -> [HeadGestureSample] {
        let seeded = samples.filter { now.timeIntervalSince($0.at) <= 0.24 }
        return seeded.isEmpty ? Array(samples.suffix(3)) : seeded
    }

    private func gestureActivationDistance(from samples: [HeadGestureSample]) -> Double {
        guard samples.count >= 2 else { return 0 }
        let points = samples.map { scaledGesturePoint(yaw: $0.yaw, pitch: $0.pitch) }
        let translated = points.map { CGPoint(x: $0.x - points[0].x, y: $0.y - points[0].y) }
        return pathLength(translated)
    }

    private func pathLength(_ points: [CGPoint]) -> Double {
        guard points.count > 1 else { return 0 }
        return zip(points, points.dropFirst()).reduce(0.0) { partial, pair in
            partial + Double(hypot(pair.1.x - pair.0.x, pair.1.y - pair.0.y))
        }
    }

    private func resampleGesturePoints(_ points: [CGPoint], count: Int) -> [CGPoint] {
        guard !points.isEmpty else { return [] }
        guard points.count > 1, count > 1 else { return Array(repeating: points[0], count: max(count, 1)) }
        let targetSpacing = pathLength(points) / Double(count - 1)
        if targetSpacing == 0 { return Array(repeating: points[0], count: count) }

        var resampled: [CGPoint] = [points[0]]
        var accumulated = 0.0
        var previous = points[0]
        var index = 1

        while index < points.count {
            let current = points[index]
            let segment = Double(hypot(current.x - previous.x, current.y - previous.y))
            if accumulated + segment >= targetSpacing {
                let ratio = CGFloat((targetSpacing - accumulated) / max(segment, 0.0001))
                let interpolated = CGPoint(
                    x: previous.x + ((current.x - previous.x) * ratio),
                    y: previous.y + ((current.y - previous.y) * ratio)
                )
                resampled.append(interpolated)
                previous = interpolated
                accumulated = 0.0
            } else {
                accumulated += segment
                previous = current
                index += 1
            }
        }

        while resampled.count < count {
            resampled.append(points.last ?? points[0])
        }
        return Array(resampled.prefix(count))
    }

    private func gestureTurnCount(points: [CGPoint]) -> Int {
        guard points.count >= 3 else { return 0 }
        var turns = 0
        for idx in 2..<points.count {
            let a = points[idx - 2]
            let b = points[idx - 1]
            let c = points[idx]
            let v1 = CGPoint(x: b.x - a.x, y: b.y - a.y)
            let v2 = CGPoint(x: c.x - b.x, y: c.y - b.y)
            let mag1 = hypot(v1.x, v1.y)
            let mag2 = hypot(v2.x, v2.y)
            guard mag1 > 0.01, mag2 > 0.01 else { continue }
            let dot = max(-1.0, min(1.0, Double((v1.x * v2.x) + (v1.y * v2.y)) / Double(mag1 * mag2)))
            let angle = acos(dot)
            if angle >= 0.75 {
                turns += 1
            }
        }
        return turns
    }

    private func signChanges(values: [CGFloat]) -> Int {
        var lastSign = 0
        var changes = 0
        for value in values {
            let sign: Int
            if value > 0.02 {
                sign = 1
            } else if value < -0.02 {
                sign = -1
            } else {
                continue
            }
            if lastSign != 0, sign != lastSign {
                changes += 1
            }
            lastSign = sign
        }
        return changes
    }

    private func overlayTrailPoints(for samples: [HeadGestureSample]) -> [HeadGestureOverlayPoint] {
        guard samples.count >= 2 else { return [] }
        let cursorPoints = stabilizedOverlayCursorPoints(from: samples.compactMap(\.cursorLocation))
        guard cursorPoints.count >= 2, let endPoint = cursorPoints.last else { return [] }
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(endPoint) })
            ?? NSScreen.main
            ?? NSScreen.screens.first else { return [] }
        let displayScale: CGFloat = 1.12
        let origin = cursorPoints.first ?? endPoint
        return cursorPoints.map { point in
            let scaledPoint = CGPoint(
                x: origin.x + ((point.x - origin.x) * displayScale),
                y: origin.y + ((point.y - origin.y) * displayScale)
            )
            let localX = scaledPoint.x - screen.frame.minX
            let localY = screen.frame.height - (scaledPoint.y - screen.frame.minY)
            return HeadGestureOverlayPoint(
                x: localX,
                y: localY
            )
        }
    }

    private func stabilizedOverlayCursorPoints(from points: [CGPoint]) -> [CGPoint] {
        guard points.count >= 2 else { return points }

        var simplified: [CGPoint] = []
        simplified.reserveCapacity(points.count)
        for point in points {
            if let last = simplified.last, hypot(point.x - last.x, point.y - last.y) < 3.5 {
                continue
            }
            simplified.append(point)
        }

        guard simplified.count >= 2 else { return Array(points.suffix(min(points.count, 2))) }

        let window = 3
        var smoothed: [CGPoint] = []
        smoothed.reserveCapacity(simplified.count)
        for index in simplified.indices {
            let lower = max(simplified.startIndex, index - window)
            let upper = min(simplified.endIndex - 1, index + window)
            let slice = simplified[lower...upper]
            let avgX = slice.reduce(CGFloat.zero) { $0 + $1.x } / CGFloat(slice.count)
            let avgY = slice.reduce(CGFloat.zero) { $0 + $1.y } / CGFloat(slice.count)
            smoothed.append(CGPoint(x: avgX, y: avgY))
        }

        if let tail = points.last {
            if smoothed.isEmpty {
                smoothed.append(tail)
            } else {
                smoothed[smoothed.count - 1] = tail
            }
        }

        return smoothed
    }

    private func liveOverlayDistance(for samples: [HeadGestureSample]) -> Double {
        guard samples.count >= 2 else { return 0 }
        let points = samples.map { scaledGesturePoint(yaw: $0.yaw, pitch: $0.pitch) }
        let translated = points.map { point in
            CGPoint(x: point.x - points[0].x, y: point.y - points[0].y)
        }
        return pathLength(translated)
    }

    @MainActor
    private func appendHeadGestureDebugEntry(
        mode: String,
        result: String,
        samples: [HeadGestureSample],
        gestureName: String?,
        actionName: String?,
        bestMatchName: String?,
        bestScore: Double?
    ) {
        let duration = max(samples.last?.at.timeIntervalSince(samples.first?.at ?? .distantPast) ?? 0, 0)
        let totalDistance = gestureActivationDistance(from: samples)
        let debugSamples = serializeHeadGestureSamples(samples)
        let entry = HeadGestureDebugEntry(
            id: UUID(),
            date: Date(),
            mode: mode,
            result: result,
            gestureName: gestureName,
            actionName: actionName,
            bestMatchName: bestMatchName,
            bestScore: bestScore,
            totalDistance: totalDistance,
            duration: duration,
            sampleCount: samples.count,
            samples: debugSamples
        )
        headGestureDebugEntries.insert(entry, at: 0)
        if headGestureDebugEntries.count > headGestureDebugEntryLimit {
            headGestureDebugEntries = Array(headGestureDebugEntries.prefix(headGestureDebugEntryLimit))
        }
    }

    private func serializeHeadGestureSamples(_ samples: [HeadGestureSample]) -> [HeadGestureDebugSample] {
        guard let start = samples.first?.at else { return [] }
        return samples.map { sample in
            HeadGestureDebugSample(
                t: sample.at.timeIntervalSince(start),
                yaw: sample.yaw,
                pitch: sample.pitch,
                cursorX: sample.cursorLocation.map { Double($0.x) },
                cursorY: sample.cursorLocation.map { Double($0.y) }
            )
        }
    }

    @MainActor
    private func appendHeadGestureHistory(
        gestureName: String,
        actionName: String,
        result: HeadGestureHistoryResult,
        score: Double?,
        duration: TimeInterval,
        summary: String
    ) {
        let entry = HeadGestureHistoryEntry(
            id: UUID(),
            date: Date(),
            gestureName: gestureName,
            actionName: actionName,
            result: result,
            score: score,
            duration: duration,
            summary: summary
        )
        headGestureHistory.insert(entry, at: 0)
        if headGestureHistory.count > headGestureHistoryLimit {
            headGestureHistory = Array(headGestureHistory.prefix(headGestureHistoryLimit))
        }
        lastHeadGestureEventText = "\(gestureName) · \(result.label)"
        lastHeadGestureEventAt = entry.date
    }

    private func formatHeadGestureHistoryEntry(_ entry: HeadGestureHistoryEntry) -> String {
        let timestamp = ISO8601DateFormatter().string(from: entry.date)
        let scoreText = entry.score.map { String(format: "%.0f%%", $0 * 100) } ?? "-"
        return "[\(timestamp)] \(entry.gestureName) | \(entry.result.label) | \(entry.actionName) | score=\(scoreText) | duration=\(String(format: "%.2fs", entry.duration)) | \(entry.summary)"
    }

    private func copyTextToPasteboard(_ text: String) throws {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        guard pasteboard.setString(text, forType: .string) else {
            throw NSError(domain: "AetherHeadGestureCopy", code: 1, userInfo: [
                NSLocalizedDescriptionKey: AppLocalization.isChinese ? "复制头部动作历史失败" : "Failed to copy head gesture history"
            ])
        }
    }

    private func appLocalizedCountdownText(remaining: Int) -> String {
        AppLocalization.isChinese
            ? "\(remaining) 秒后开始"
            : "Starts in \(remaining)s"
    }

    private func playNamedHeadGestureSound(_ names: [String], fallback: String) {
        for name in names {
            if let sound = NSSound(named: name) {
                sound.play()
                return
            }
        }
        NSSound(named: fallback)?.play()
    }

    private func playHeadGestureStartSound() {
        playNamedHeadGestureSound(["Submarine", "Morse"], fallback: "Submarine")
    }

    private func playHeadGestureSuccessSound() {
        playNamedHeadGestureSound(["Pop", "Tink", "Glass"], fallback: "Tink")
    }

    private func playHeadGestureTurnCueSound() {
        playNamedHeadGestureSound(["Morse", "Ping"], fallback: "Morse")
    }

    private func playHeadGestureNoMatchSound() {
        playNamedHeadGestureSound(["Funk", "Basso"], fallback: "Basso")
    }

    private func playHeadGestureCancelSound() {
        playNamedHeadGestureSound(["Blow", "Hero"], fallback: "Blow")
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
        guard !AutomationOutputs.shared.isDraggingActive else { return }
        syncTrackedCursorToSystemCursor()
        // Use current cursor location (nil) to avoid coordinate flipping issues
        AutomationOutputs.shared.drag(start: true, at: nil)
        HUDManager.shared.setDragStatusActive(
            true,
            language: AppLocalization.resolvedLocaleIdentifier,
            recognitionControlMode: .command,
            icon: "hand.draw.fill"
        )
    }

    func dragEnd() {
        guard AutomationOutputs.shared.isDraggingActive else { return }
        // Use current cursor location (nil) to avoid coordinate flipping issues
        AutomationOutputs.shared.drag(start: false, at: nil)
        HUDManager.shared.setDragStatusActive(false, language: AppLocalization.resolvedLocaleIdentifier)
        HUDManager.shared.showTemporary(
            message: String(localized: "headset.hud.drag_drop"),
            icon: "hand.raised.fill"
        )
    }

    private func syncTrackedCursorToSystemCursor() {
        guard let currentCursor = CGEvent(source: nil)?.location else { return }
        let maxY = desktopFrame == .zero
            ? NSScreen.screens.reduce(CGFloat(0)) { max($0, $1.frame.maxY) }
            : desktopFrame.maxY
        currentX = currentCursor.x
        currentY = maxY - currentCursor.y
    }

    func recenter() {
        guard isTracking else { return }
        desktopFrame = aggregateDesktopFrame()
        let activeScreenFrame = activeTrackingScreenFrame()
        recenterAnchor = CGPoint(x: activeScreenFrame.midX, y: activeScreenFrame.midY)
        os_log("Recenter anchor updated workspace=%@ anchor=(%.1f, %.1f)", log: log, String(describing: desktopFrame), recenterAnchor.x, recenterAnchor.y)
        // Force re-calibration on next motion sample.
        isCalibrated = false
        isCalibratingRange = true
        calibrationStatus = String(localized: "headset.status.calibrating")
    }

    private func aggregateDesktopFrame() -> NSRect {
        NSScreen.screens.reduce(into: NSRect.zero) { partialResult, screen in
            partialResult = partialResult.union(screen.frame)
        }
    }

    private func targetCoordinate(
        for normalizedValue: CGFloat,
        anchor: CGFloat,
        minimum: CGFloat,
        maximum: CGFloat,
        invertDirection: Bool
    ) -> CGFloat {
        let signedValue = invertDirection ? -normalizedValue : normalizedValue
        let clamped = max(-0.5, min(0.5, signedValue))

        if clamped >= 0 {
            let positiveRange = max(0, maximum - anchor)
            return anchor + ((clamped / 0.5) * positiveRange)
        } else {
            let negativeRange = max(0, anchor - minimum)
            return anchor + ((clamped / 0.5) * negativeRange)
        }
    }

    private func activeTrackingScreenFrame() -> NSRect {
        let screens = NSScreen.screens
        if let cursor = currentSystemCursorLocation() {
            if let containingScreen = screens.first(where: { screenContainsCursor($0.frame, cursor: cursor) }) {
                return containingScreen.frame
            }

            if let nearestScreen = screens.min(by: {
                squaredDistance(from: cursor, to: $0.frame) < squaredDistance(from: cursor, to: $1.frame)
            }) {
                return nearestScreen.frame
            }
        }

        if let mainFrame = NSScreen.main?.frame {
            return mainFrame
        }

        return screens.first?.frame ?? .zero
    }

    private func currentSystemCursorLocation() -> CGPoint? {
        let mouseLocation = NSEvent.mouseLocation
        if mouseLocation != .zero || NSScreen.screens.contains(where: { screenContainsCursor($0.frame, cursor: mouseLocation) }) {
            return mouseLocation
        }
        return CGEvent(source: nil)?.location
    }

    private func screenContainsCursor(_ frame: NSRect, cursor: CGPoint) -> Bool {
        let expandedFrame = frame.insetBy(dx: -1, dy: -1)
        return expandedFrame.contains(cursor)
    }

    private func squaredDistance(from point: CGPoint, to frame: NSRect) -> CGFloat {
        let dx: CGFloat
        if point.x < frame.minX {
            dx = frame.minX - point.x
        } else if point.x > frame.maxX {
            dx = point.x - frame.maxX
        } else {
            dx = 0
        }

        let dy: CGFloat
        if point.y < frame.minY {
            dy = frame.minY - point.y
        } else if point.y > frame.maxY {
            dy = point.y - frame.maxY
        } else {
            dy = 0
        }

        return (dx * dx) + (dy * dy)
    }
    
    func finishCalibration() {
        isCalibratingRange = false
        calibrationStatus = String(localized: "calibration.normal")
        os_log("Aether: Calibration Finished", log: log)
    }
    
    private func updateAttentionState(yaw: Double) {
        let absYaw = abs(yaw)
        let isCurrentlyLooking = isLookingAtScreen
            ? absYaw < attentionAwayThresholdYaw
            : absYaw < attentionReturnThresholdYaw

        if isCurrentlyLooking != isLookingAtScreen {
            attentionHysteresisBuffer += 1
            let requiredFrames = isCurrentlyLooking ? attentionReturnDebounceFrames : attentionAwayDebounceFrames
            if attentionHysteresisBuffer >= requiredFrames {
                isLookingAtScreen = isCurrentlyLooking
                attentionHysteresisBuffer = 0

                if isLookingAtScreen {
                    os_log("Attention: Regained", log: log)
                } else {
                    os_log("Attention: Lost", log: log)
                }
            }
        } else {
            attentionHysteresisBuffer = 0
        }
    }

    @MainActor
    private func handleAirPodsStateChanged(_ notification: Notification) {
        let newSide = (notification.object as? AirPodSide) ?? AirPodsDetector.shared.currentSide()
        applyAirPodsSideUpdate(newSide, source: "notification")
    }

    @MainActor
    private func handleHeadsetRouteChanged(_ notification: Notification) {
        let connected = notification.userInfo?["connected"] as? Bool ?? false
        let source = notification.userInfo?["source"] as? String ?? "route"
        applyHeadsetRouteConnectionUpdate(connected, source: source)
    }

    @MainActor
    private func applyHeadsetRouteConnectionUpdate(_ connected: Bool, source: String) {
        let wasConnected = hasActiveHeadsetConnection
        guard connected != lastObservedHeadsetRouteConnected || source == "startup" else { return }
        lastObservedHeadsetRouteConnected = connected
        GlobalLogger.lifecycle.info(
            "HeadMotion headset route update source=\(source) connected=\(connected) airPodsSide=\(lastObservedAirPodSide.rawValue) hasHeadset=\(hasActiveHeadsetConnection)"
        )

        if !hasActiveHeadsetConnection {
            pendingAutoTrackingStart?.cancel()
            pendingAutoTrackingStart = nil
            stopPassiveHeadGestureMonitoring(source: "headset-route-disconnected-\(source)")
            return
        }

        refreshHeadGestureMonitoringState(source: "headset-route-\(source)")
        guard autoStartTrackingOnHeadsetConnection, !wasConnected else { return }
        scheduleAutoTrackingStartAfterConnection(trigger: source == "startup" ? "startup" : "connected")
    }

    @MainActor
    private func applyAirPodsSideUpdate(_ newSide: AirPodSide, source: String) {
        let wasConnected = lastObservedAirPodSide != .none
        let isConnected = newSide != .none
        guard newSide != lastObservedAirPodSide || source == "startup" else { return }
        lastObservedAirPodSide = newSide
        GlobalLogger.lifecycle.info(
            "HeadMotion airpods side update source=\(source) side=\(newSide.rawValue) routeConnected=\(lastObservedHeadsetRouteConnected) hasHeadset=\(hasActiveHeadsetConnection)"
        )

        if !isConnected {
            pendingAutoTrackingStart?.cancel()
            pendingAutoTrackingStart = nil
            stopPassiveHeadGestureMonitoring(source: "airpods-disconnected-\(source)")
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

        refreshHeadGestureMonitoringState(source: "airpods-connected-\(source)")
        
        // Side / ear detection can flap while the same headset remains active.
        // Do not restart a healthy tracking session just because the reported side changed.
        if isTracking && wasConnected && isConnected {
            GlobalLogger.lifecycle.info("HeadMotion: keeping active tracking session across side update source=\(source)")
        }

        guard autoStartTrackingOnHeadsetConnection, !wasConnected else { return }
        scheduleAutoTrackingStartAfterConnection(trigger: source == "startup" ? "startup" : "connected")
    }

    @MainActor
    private func scheduleAutoTrackingStartAfterConnection(trigger: String = "connected") {
        guard autoStartTrackingOnHeadsetConnection, !isTracking else { return }

        pendingAutoTrackingStart?.cancel()

        let baseDelay: TimeInterval
        if trigger == "startup" {
            baseDelay = showPostureGuideBeforeTracking ? 0.85 : 0.12
        } else {
            baseDelay = showPostureGuideBeforeTracking ? 1.2 : 0.35
        }
        if showPostureGuideBeforeTracking {
            HUDManager.shared.showTemporary(
                message: String(localized: "headset.hud.posture_guide"),
            )
        }

        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            guard self.autoStartTrackingOnHeadsetConnection, !self.isTracking, self.hasActiveHeadsetConnection else { return }
            guard self.motionManager.isDeviceMotionAvailable else {
                GlobalLogger.lifecycle.info(
                    "HeadMotion auto-start blocked trigger=\(trigger) motionUnavailable routeConnected=\(self.lastObservedHeadsetRouteConnected) airPodsSide=\(self.lastObservedAirPodSide.rawValue)"
                )
                HUDManager.shared.showTemporary(
                    message: String(localized: "headset.hud.unsupported"),
                )
                return
            }
            self.startTracking()
        }

        pendingAutoTrackingStart = workItem
        GlobalLogger.lifecycle.info(
            "HeadMotion auto-start scheduled trigger=\(trigger) delay=\(String(format: "%.2f", baseDelay)) routeConnected=\(lastObservedHeadsetRouteConnected) airPodsSide=\(lastObservedAirPodSide.rawValue)"
        )
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
        let preferredNames: [String] = ["Pop", "Tink", "Glass"]
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

            let detectorSide = AirPodsDetector.shared.currentSide()
            if detectorSide != self.lastObservedAirPodSide {
                Task { @MainActor [weak self] in
                    self?.applyAirPodsSideUpdate(detectorSide, source: "stability-sync")
                }
            }
            let routeConnected = HeadsetRouteState.shared.isConnected
            if routeConnected != self.lastObservedHeadsetRouteConnected {
                Task { @MainActor [weak self] in
                    self?.applyHeadsetRouteConnectionUpdate(routeConnected, source: "stability-sync")
                }
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

private struct HeadGestureOverlayPoint: Equatable {
    let x: CGFloat
    let y: CGFloat
}

private enum HeadGestureOverlayEmphasis {
    case recording
    case live
    case matched

        var gradient: LinearGradient {
        switch self {
        case .recording:
            return LinearGradient(colors: [Color.orange.opacity(0.96), Color.yellow.opacity(0.88)], startPoint: .leading, endPoint: .trailing)
        case .live:
            return LinearGradient(colors: [Color.white.opacity(0.88), Color.cyan.opacity(0.82)], startPoint: .leading, endPoint: .trailing)
        case .matched:
            return LinearGradient(colors: [Color.green.opacity(0.98), Color.cyan.opacity(0.86)], startPoint: .leading, endPoint: .trailing)
        }
    }

    var panelOpacity: Double {
        switch self {
        case .recording:
            return 0.76
        case .live:
            return 0.58
        case .matched:
            return 0.68
        }
    }
}

private final class HeadGestureOverlayController {
    private var panel: NSPanel?
    private var hideTask: DispatchWorkItem?

    func show(points: [HeadGestureOverlayPoint], status: String, emphasis: HeadGestureOverlayEmphasis, cursorLocation: CGPoint?) {
        guard !points.isEmpty else {
            hide()
            return
        }
        guard let cursorLocation else {
            hide()
            return
        }
        hideTask?.cancel()
        let panel = ensurePanel()
        _ = updatePanelFrame(panel, cursorLocation: cursorLocation)
        panel.contentView = NSHostingView(
            rootView: HeadGestureOverlayView(points: points, status: status, emphasis: emphasis)
        )
        panel.orderFrontRegardless()
    }

    func hide(after delay: TimeInterval = 0) {
        hideTask?.cancel()
        guard delay > 0 else {
            panel?.orderOut(nil)
            return
        }
        let task = DispatchWorkItem { [weak self] in
            self?.panel?.orderOut(nil)
        }
        hideTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: task)
    }

    private func ensurePanel() -> NSPanel {
        if let panel { return panel }
        let panel = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        self.panel = panel
        return panel
    }

    @discardableResult
    private func updatePanelFrame(_ panel: NSPanel, cursorLocation: CGPoint) -> NSRect {
        let pointerScreen = NSScreen.screens.first { $0.frame.contains(cursorLocation) }
        let screen = pointerScreen ?? NSScreen.main ?? NSScreen.screens.first
        guard let screen else { return .zero }
        panel.setFrame(screen.frame, display: true)
        return screen.frame
    }
}

private struct HeadGestureOverlayView: View {
    let points: [HeadGestureOverlayPoint]
    let status: String
    let emphasis: HeadGestureOverlayEmphasis

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                Path { path in
                    guard let first = points.first else { return }
                    path.move(to: map(first, in: proxy.size))
                    for point in points.dropFirst() {
                        path.addLine(to: map(point, in: proxy.size))
                    }
                }
                .stroke(emphasis.gradient, style: StrokeStyle(lineWidth: 14, lineCap: .round, lineJoin: .round))
                .shadow(color: .white.opacity(0.18), radius: 10)

                if let first = points.first {
                    Circle()
                        .fill(Color.white.opacity(0.28))
                        .frame(width: 12, height: 12)
                        .position(map(first, in: proxy.size))
                }

                if let last = points.last {
                    Circle()
                        .fill(Color.white.opacity(0.94))
                        .frame(width: 13, height: 13)
                        .shadow(color: .white.opacity(0.30), radius: 9)
                        .position(map(last, in: proxy.size))
                }

                if !status.isEmpty {
                    Text(status)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.white.opacity(0.92))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(.ultraThinMaterial.opacity(emphasis.panelOpacity))
                        .clipShape(Capsule())
                        .shadow(color: .black.opacity(0.18), radius: 6, x: 0, y: 3)
                        .position(labelPosition(in: proxy.size))
                }
            }
        }
    }

    private func map(_ point: HeadGestureOverlayPoint, in size: CGSize) -> CGPoint {
        CGPoint(
            x: min(max(point.x, 10), max(size.width - 10, 10)),
            y: min(max(point.y, 10), max(size.height - 10, 10))
        )
    }

    private func labelPosition(in size: CGSize) -> CGPoint {
        let anchor = points.last.map { CGPoint(x: $0.x, y: $0.y) } ?? CGPoint(x: size.width / 2, y: size.height / 2)
        return CGPoint(
            x: min(max(anchor.x, 70), max(size.width - 70, 70)),
            y: min(max(anchor.y + 38, 28), max(size.height - 28, 28))
        )
    }
}
