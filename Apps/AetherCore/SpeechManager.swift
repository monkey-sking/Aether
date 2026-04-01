import Foundation
import AVFoundation
import AVFAudio
import Speech
import AppKit
import os
import ApplicationServices
import Combine
import CoreAudio
import IOKit
import Carbon.HIToolbox

struct AudioInputDevice: Identifiable, Hashable {
    let id: AudioDeviceID
    let name: String
    let uid: String
    let iconName: String
    static let defaultSystem = AudioInputDevice(id: 0, name: String(localized: "settings.default_device"), uid: "SystemDefault", iconName: "mic.slash")
}

enum SpeechLanguageMode: String, CaseIterable, Identifiable {
    case single
    case bilingual

    var id: String { rawValue }
}

enum VoiceDefaults {
    static let alwaysListeningWakeWindowSeconds = 8.0
    static let minAlwaysListeningWakeWindowSeconds = 3.0
    static let maxAlwaysListeningWakeWindowSeconds = 30.0
}

struct UtteranceExecutionGuard {
    private var seenOrder: [String] = []
    private var seenSet: Set<String> = []
    private let maxHistory: Int
    init(maxHistory: Int = 64) { self.maxHistory = max(8, maxHistory) }
    mutating func shouldExecute(sessionGeneration: Int, utteranceID: Int) -> Bool {
        guard utteranceID > 0 else { return true }
        let key = "\(sessionGeneration)#\(utteranceID)"
        if seenSet.contains(key) { return false }
        seenSet.insert(key)
        seenOrder.append(key)
        while seenOrder.count > maxHistory { let r = seenOrder.removeFirst(); seenSet.remove(r) }
        return true
    }
    mutating func reset() { seenOrder.removeAll(); seenSet.removeAll() }
}

enum RecognizedTextCorrectionScope {
    case dictation
    case command
}

struct RecognizedTextReplacementRule: Equatable {
    let from: String
    let to: String
    let scope: RecognizedTextCorrectionScope?
}

enum DeveloperSpeechProfile {
    private static let terminalBundleIdentifiers: Set<String> = [
        "com.apple.terminal",
        "com.googlecode.iterm2",
        "com.github.wez.wezterm",
        "dev.warp.warp-stable"
    ]
    private static let editorBundleIdentifiers: Set<String> = [
        "com.apple.dt.xcode",
        "com.microsoft.vscode",
        "com.microsoft.vscodeinsiders",
        "com.todesktop.230313mzl4w4u92",
        "com.zed.zed",
        "com.openai.codex",
        "com.openai.chatgpt"
    ]
    private static let developerBundlePrefixes = [
        "com.jetbrains.",
        "com.cursor."
    ]
    private static let sharedContextualTerms = [
        "新包", "打包", "发版", "安装包", "构建", "归档",
        "release", "beta", "build", "archive", "workspace",
        "GitHub", "repo", "branch", "commit", "merge", "rebase",
        "stash", "checkout", "pull request", "PR"
    ]
    private static let terminalContextualTerms = [
        "shell", "zsh", "bash", "brew", "git", "npm", "pnpm", "yarn", "cargo"
    ]
    private static let xcodeContextualTerms = [
        "scheme", "simulator", "derived data", "signing", "notary", "TestFlight"
    ]
    private static let editorContextualTerms = [
        "diff", "refactor", "workspace", "extension", "pull request", "PR", "Codex"
    ]
    private static let builtInReplacements: [RecognizedTextReplacementRule] = [
        RecognizedTextReplacementRule(from: "打个心包", to: "打个新包", scope: .dictation),
        RecognizedTextReplacementRule(from: "打个钱包", to: "打个新包", scope: .dictation),
        RecognizedTextReplacementRule(from: "发个心包", to: "发个新包", scope: .dictation),
        RecognizedTextReplacementRule(from: "发个钱包", to: "发个新包", scope: .dictation),
        RecognizedTextReplacementRule(from: "构件", to: "构建", scope: .dictation),
        RecognizedTextReplacementRule(from: "归当", to: "归档", scope: .dictation),
        RecognizedTextReplacementRule(from: "安转包", to: "安装包", scope: .dictation),
        RecognizedTextReplacementRule(from: "git hub", to: "GitHub", scope: nil),
        RecognizedTextReplacementRule(from: "后果", to: "GitHub", scope: .command)
    ]

    static func matches(bundleIdentifier: String?) -> Bool {
        guard let bundleIdentifier else { return false }
        let normalized = bundleIdentifier.lowercased()
        if terminalBundleIdentifiers.contains(normalized) || editorBundleIdentifiers.contains(normalized) {
            return true
        }
        return developerBundlePrefixes.contains(where: { normalized.hasPrefix($0) })
    }

    static func contextualTerms(for bundleIdentifiers: [String]) -> [String] {
        guard bundleIdentifiers.contains(where: { matches(bundleIdentifier: $0) }) else { return [] }

        var terms = sharedContextualTerms
        for bundleIdentifier in bundleIdentifiers.map({ $0.lowercased() }) {
            if terminalBundleIdentifiers.contains(bundleIdentifier) {
                terms.append(contentsOf: terminalContextualTerms)
            }
            if bundleIdentifier == "com.apple.dt.xcode" {
                terms.append(contentsOf: xcodeContextualTerms)
            }
            if editorBundleIdentifiers.contains(bundleIdentifier)
                || developerBundlePrefixes.contains(where: { bundleIdentifier.lowercased().hasPrefix($0) }) {
                terms.append(contentsOf: editorContextualTerms)
            }
        }

        return VoiceLexiconSupport.uniqueTerms(terms)
    }

    static func correctedText(
        _ raw: String,
        scope: RecognizedTextCorrectionScope,
        bundleIdentifiers: [String]
    ) -> String {
        guard bundleIdentifiers.contains(where: { matches(bundleIdentifier: $0) }) else { return raw }

        var corrected = raw
        for rule in builtInReplacements.sorted(by: { $0.from.count > $1.from.count }) {
            if let ruleScope = rule.scope, ruleScope != scope {
                continue
            }
            guard corrected.contains(rule.from) else { continue }
            corrected = corrected.replacingOccurrences(of: rule.from, with: rule.to)
        }
        return corrected
    }
}

@MainActor
final class SpeechManager: ObservableObject {
    enum PlaybackLeakState: String {
        case none
        case suspectedPlaybackLeak
        case speechSuppressionActive
    }

    private enum SessionSpeechProcessingProfile: String {
        case passthrough
        case dictation
        case speechCommand

        var audioProfile: AudioCaptureSession.VoiceProcessingProfile {
            switch self {
            case .passthrough: return .passthrough
            case .dictation: return .dictation
            case .speechCommand: return .speechCommand
            }
        }
    }

    private struct AudioEnergyObservation {
        let at: Date
        let rms: Float
        let active: Bool
    }

    private let log = GlobalLogger.speech
    private let headsetInputMuteRouter = HeadsetInputMuteRouter()

    // MARK: - Intent Pipeline (unchanged)
    private struct IntentJob: Sendable {
        let seq: Int; let intent: VoiceIntent; let localeIdentifier: String
        let dictationEnhancementEnabled: Bool; let fullTextRewriteEnabled: Bool
        let originSessionGeneration: Int; let utteranceID: Int
        let inputControlSnapshot: InputControlSnapshot; let streamedTextSnapshot: String; let screenTypedCount: Int
        let targetPID: pid_t?; let targetBundleID: String?; let targetElementFingerprint: String?
        let targetSource: FocusedInputSource?
        let verificationSnapshot: InputVerificationSnapshot?
        let holdsTextRewriteBarrier: Bool
        let spokenText: String?
        let routeReason: String
        let commandHUDPreviewMessage: String?

        var typingInteraction: Bool { inputControlSnapshot.interactionState.isTyping }
    }
    private struct ProcessedJob: Sendable {
        let seq: Int; let intent: VoiceIntent; let localeIdentifier: String
        let originSessionGeneration: Int; let utteranceID: Int
        let inputControlSnapshot: InputControlSnapshot; let streamedTextSnapshot: String; let screenTypedCount: Int
        let targetPID: pid_t?; let targetBundleID: String?; let targetElementFingerprint: String?
        let targetSource: FocusedInputSource?
        let verificationSnapshot: InputVerificationSnapshot?
        let holdsTextRewriteBarrier: Bool
        let diagnostics: String?
        let spokenText: String?
        let originalContent: String?
        let enhancedContent: String?
        let routeReason: String
        let commandHUDPreviewMessage: String?

        var typingInteraction: Bool { inputControlSnapshot.interactionState.isTyping }
    }
    private struct InputVerificationSnapshot: Sendable {
        let pid: pid_t
        let bundleID: String?
        let elementFingerprint: String?
        let valueText: String?
        let selectedRangeLocation: Int?
        let selectedRangeLength: Int?
    }
    private struct PostSubmitDictationSuppression: Sendable {
        let expiresAt: Date
        let pid: pid_t?
        let bundleID: String?
        let elementFingerprint: String?
        let previousText: String
    }
    private enum FocusedInputSource: String, Sendable {
        case accessibility
        case recentClickFallback
    }
    private enum DictationVerificationResult {
        case success
        case mismatch
        case unverified
    }
    enum DictationEnhancementValidationResult: Equatable {
        case accept(String, changed: Bool)
        case reject(String)
    }
    private actor IntentPipeline {
        private var nextSeq: Int = 0; private var expectedSeq: Int = 0
        private var readyBySeq: [Int: ProcessedJob] = [:]
        func allocateSeq() -> Int { let s = nextSeq; nextSeq += 1; return s }
        func submit(_ job: ProcessedJob) -> [ProcessedJob] {
            readyBySeq[job.seq] = job
            var out: [ProcessedJob] = []
            while let j = readyBySeq.removeValue(forKey: expectedSeq) { out.append(j); expectedSeq += 1 }
            return out
        }
    }

    // MARK: - Published Properties (all preserved)
    @Published var status: String = "Idle"
    @Published var lastTranscript: String = ""
    @Published var lastError: String = ""
    @Published private(set) var playbackLeakState: PlaybackLeakState = .none
    @Published var enhancedPlaybackLeakSuppressionEnabled: Bool = UserDefaults.standard.object(forKey: "enhancedPlaybackLeakSuppressionEnabled") as? Bool ?? true {
        didSet {
            UserDefaults.standard.set(enhancedPlaybackLeakSuppressionEnabled, forKey: "enhancedPlaybackLeakSuppressionEnabled")
            refreshPlaybackLeakStateForCurrentSession()
        }
    }
    @Published private(set) var accessibilityTrustedSnapshot: Bool = false
    @Published var availableInputDevices: [AudioInputDevice] = []
    @Published var selectedInputDeviceID: AudioDeviceID = 0 {
        willSet {
            if newValue != selectedInputDeviceID {
                pendingSelectedInputRouteSnapshot = currentAudioRouteSnapshot()
            }
        }
        didSet {
            if oldValue != selectedInputDeviceID {
                if selectedInputDeviceID == 0 {
                    selectedInputDeviceUIDHint = nil
                    selectedInputDeviceNameHint = nil
                } else if let selected = availableInputDevices.first(where: { $0.id == selectedInputDeviceID }) {
                    selectedInputDeviceUIDHint = selected.uid
                    selectedInputDeviceNameHint = selected.name
                }
                GlobalLogger.speech.info(
                    "[AudioRoute] selection changed oldID=\(oldValue) newID=\(selectedInputDeviceID) selectedName=\(availableInputDevices.first(where: { $0.id == selectedInputDeviceID })?.name ?? "system-default") uidHint=\(selectedInputDeviceUIDHint ?? "nil")"
                )
                let active = audioCapture.isRunning || recognitionSession.isRunning || isAlwaysListeningEnabled
                let before = pendingSelectedInputRouteSnapshot
                pendingSelectedInputRouteSnapshot = nil
                if active && !suppressInputSelectionRestart,
                   let before,
                   shouldRestartForAudioRouteChange(from: before, to: currentAudioRouteSnapshot()) {
                    scheduleEngineRestart(reason: "input-device-selection")
                }
            }
        }
    }
    @Published var isPTTEnabled: Bool = UserDefaults.standard.object(forKey: "isPTTEnabled") as? Bool ?? true {
        didSet { UserDefaults.standard.set(isPTTEnabled, forKey: "isPTTEnabled"); syncRecognitionState() }
    }
    @Published var activeLocale: Locale = Locale(identifier: "zh-CN") {
        didSet {
            if oldValue.identifier != activeLocale.identifier {
                if isAlwaysListeningEnabled { startContinuous() }
                if hasCompletedInitialLocaleSetup {
                    DispatchQueue.main.async { [weak self] in
                        guard let self else { return }
                        let hud = HUDManager.shared
                        hud.update(
                            mode: hud.state.mode,
                            message: hud.state.message,
                            language: self.activeLocale.identifier,
                            recognitionControlMode: self.hudRecognitionControlMode,
                            inputDeviceIcon: self.hudInputIcon(),
                            inputDeviceHealth: self.hudInputHealth(),
                            contextIcon: self.hudContextIcon()
                        )
                        hud.showTemporaryLanguageIndicator()
                    }
                }
            }
        }
    }
    @Published var isAlwaysListeningEnabled: Bool = UserDefaults.standard.bool(forKey: "isAlwaysListeningEnabled") {
        didSet { UserDefaults.standard.set(isAlwaysListeningEnabled, forKey: "isAlwaysListeningEnabled"); syncRecognitionState() }
    }
    @Published var isDirectCommandEnabled: Bool = false
    @Published var isWakeWordEnabled: Bool = UserDefaults.standard.object(forKey: "isWakeWordEnabled") as? Bool ?? false {
        didSet { UserDefaults.standard.set(isWakeWordEnabled, forKey: "isWakeWordEnabled"); syncRecognitionState() }
    }
    @Published var isGazeWakeEnabled: Bool = {
        UserDefaults.standard.set(false, forKey: "isGazeWakeEnabled")
        return false
    }() {
        didSet {
            if isGazeWakeEnabled {
                isGazeWakeEnabled = false
                return
            }
            UserDefaults.standard.set(false, forKey: "isGazeWakeEnabled")
        }
    }
    @Published var isAutoDictationEnhancementEnabled: Bool = false {
        didSet {
            dictationHandler.isLLMEnhancementEnabled = isAutoDictationEnhancementEnabled
        }
    }
    @Published var isFullTextRewriteEnabled: Bool = false
    @Published var isDeveloperSpeechProfileEnabled: Bool = UserDefaults.standard.object(
        forKey: "developerSpeechProfileEnabledV1"
    ) as? Bool ?? true {
        didSet {
            UserDefaults.standard.set(
                isDeveloperSpeechProfileEnabled,
                forKey: "developerSpeechProfileEnabledV1"
            )
        }
    }
    @Published var isAutoPunctuationEnabled: Bool = {
        UserDefaults.standard.set(true, forKey: "isAutoPunctuationEnabled")
        return true
    }() {
        didSet {
            guard isAutoPunctuationEnabled else {
                if oldValue != true {
                    isAutoPunctuationEnabled = true
                }
                return
            }
            UserDefaults.standard.set(true, forKey: "isAutoPunctuationEnabled")
        }
    }
    @Published var isDictating: Bool = false
    @Published var lastWakeTime: Date?

    // MARK: - Sub-modules
    private let audioCapture = AudioCaptureSession()
    private let recognitionSession = RecognitionSession()
    private let wakeWordDetector = WakeWordDetector()
    private let eosDetector = EOSDetector()
    private let dictationHandler: DictationHandler
    private let commandHandler = CommandHandler()
    private let commandRouter = VoiceCommandRouter()
    private let injector = TextInjector()
    private var lastWakeWordDiagnosticsSignature: String = ""
    private var lastWakeMissInsightSignature: String?
    private var lastWakeMissInsightAt: Date = .distantPast
    private let wakeMissInsightDedupWindow: TimeInterval = 1.5
    private let maxTextRewriteSourceCharacters = 12_000

    // MARK: - Internal State
    var onIntent: ((VoiceIntent, String?, String?, String?, String?, String?, String?, String?) -> Void)?
    var onRecognitionFailure: ((String?, String?, String?, String?) -> Void)?
    var onWakeAnalyticsSignal: ((WakeAnalyticsSignal) -> Void)?
    var onIdlePauseResumeRequest: ((String) -> Void)?
    var isDictationExecutionEnabled: (() -> Bool)?
    var isCommandExecutionEnabled: (() -> Bool)?
    var isAppIdlePaused: (() -> Bool)?
    private var isIdlePauseSuspended: Bool = false
    private enum LLMUsage {
        case dictationEnhancement
        case fullTextRewrite
    }

    private var dictationLLMProviderConfig: LLMProviderConfiguration?
    private var rewriteLLMProviderConfig: LLMProviderConfiguration?
    private var dictationLLMServiceSource: LLMServiceSource = .openAICompatible
    private var rewriteLLMServiceSource: LLMServiceSource = .openAICompatible
    private let speechLocaleStorageKey = "speechLocaleIdentifier"
    private let speechLanguageModeStorageKey = "speechLanguageMode"
    private let speechPrimaryLocaleStorageKey = "speechPrimaryLocaleIdentifier"
    private let speechSecondaryLocaleStorageKey = "speechSecondaryLocaleIdentifier"
    private let speechFollowsSystemStorageKey = "speechFollowsSystemLanguage"
    private let supportedSpeechLocaleIdentifiers = ["zh-CN", "en-US", "ja-JP", "ko-KR", "fr-FR", "de-DE", "es-ES"]

    var speechLanguageMode: SpeechLanguageMode {
        get {
            if let raw = UserDefaults.standard.string(forKey: speechLanguageModeStorageKey),
               let mode = SpeechLanguageMode(rawValue: raw) {
                return mode
            }
            return .single
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: speechLanguageModeStorageKey)
            if newValue == .bilingual, primaryLocaleIdentifier == secondaryLocaleIdentifier {
                secondaryLocaleIdentifier = defaultSecondaryLocaleIdentifier(for: primaryLocaleIdentifier)
            }
            refreshLocale()
        }
    }

    var followsSystemLanguage: Bool {
        get {
            if UserDefaults.standard.object(forKey: speechFollowsSystemStorageKey) != nil {
                return UserDefaults.standard.bool(forKey: speechFollowsSystemStorageKey)
            }
            let legacy = UserDefaults.standard.string(forKey: speechLocaleStorageKey)
            return legacy == nil || legacy == "system" || legacy?.isEmpty == true
        }
        set {
            UserDefaults.standard.set(newValue, forKey: speechFollowsSystemStorageKey)
            if newValue {
                UserDefaults.standard.removeObject(forKey: speechLocaleStorageKey)
            } else {
                UserDefaults.standard.set(primaryLocaleIdentifier, forKey: speechLocaleStorageKey)
            }
            refreshLocale()
        }
    }

    var primaryLocaleIdentifier: String {
        get {
            if let stored = UserDefaults.standard.string(forKey: speechPrimaryLocaleStorageKey) {
                return normalizedSupportedLocaleIdentifier(stored)
            }
            if let legacy = UserDefaults.standard.string(forKey: speechLocaleStorageKey),
               !legacy.isEmpty,
               legacy != "system" {
                return normalizedSupportedLocaleIdentifier(legacy)
            }
            return normalizedSupportedLocaleIdentifier(Locale.current.identifier)
        }
        set {
            let normalized = normalizedSupportedLocaleIdentifier(newValue)
            UserDefaults.standard.set(normalized, forKey: speechPrimaryLocaleStorageKey)
            if !followsSystemLanguage || speechLanguageMode == .bilingual {
                UserDefaults.standard.set(normalized, forKey: speechLocaleStorageKey)
            }
            if normalized == secondaryLocaleIdentifier {
                UserDefaults.standard.set(defaultSecondaryLocaleIdentifier(for: normalized), forKey: speechSecondaryLocaleStorageKey)
            }
            refreshLocale()
        }
    }

    var secondaryLocaleIdentifier: String {
        get {
            if let stored = UserDefaults.standard.string(forKey: speechSecondaryLocaleStorageKey),
               !stored.isEmpty {
                let normalized = normalizedSupportedLocaleIdentifier(stored)
                if normalized != primaryLocaleIdentifier {
                    return normalized
                }
            }
            let legacy = lastNonEnglishLocaleIdentifier
            if !legacy.isEmpty {
                let normalized = normalizedSupportedLocaleIdentifier(legacy)
                if normalized != primaryLocaleIdentifier {
                    return normalized
                }
            }
            return defaultSecondaryLocaleIdentifier(for: primaryLocaleIdentifier)
        }
        set {
            let normalized = normalizedSupportedLocaleIdentifier(newValue)
            let resolved = normalized == primaryLocaleIdentifier
                ? defaultSecondaryLocaleIdentifier(for: primaryLocaleIdentifier)
                : normalized
            UserDefaults.standard.set(resolved, forKey: speechSecondaryLocaleStorageKey)
            refreshLocale()
        }
    }

    var effectiveLocaleIdentifier: String {
        activeLocale.identifier
    }

    var explicitLocaleIdentifier: String? {
        get {
            if speechLanguageMode == .single, followsSystemLanguage { return nil }
            return primaryLocaleIdentifier
        }
        set {
            speechLanguageMode = .single
            if let newValue, !newValue.isEmpty, newValue != "system" {
                UserDefaults.standard.set(false, forKey: speechFollowsSystemStorageKey)
                primaryLocaleIdentifier = normalizedSupportedLocaleIdentifier(newValue)
            } else {
                UserDefaults.standard.set(true, forKey: speechFollowsSystemStorageKey)
                refreshLocale()
            }
        }
    }
    var lastNonEnglishLocaleIdentifier: String {
        get { UserDefaults.standard.string(forKey: "lastNonEnglishLocaleIdentifier") ?? "zh-CN" }
        set { UserDefaults.standard.set(newValue, forKey: "lastNonEnglishLocaleIdentifier") }
    }

    private var lastLoggedHUDIcon: String?
    private var lastLoggedAirPodSide: AirPodSide = .none
    private var lastAnnouncedHUDInputIcon: String?
    private var lastAnnouncedHeadsetLikeInput: Bool?
    private var lastAnnouncedAirPodSide: AirPodSide?
    private var lastAnnouncedInputDeviceName: String?
    private var isPTTHeld: Bool = false
    private var wasAwake: Bool = false
    private var isStopping: Bool = false
    private var sessionGeneration: Int = 0
    private var activeUtteranceID: Int = 0
    private var nextUtteranceID: Int = 1
    private var shouldShowProcessingDotsDuringStop: Bool = false
    private var sessionTargetPID: pid_t?
    private var sessionTargetBundleID: String?
    private var sessionTargetElementFingerprint: String?
    private var sessionTargetSource: FocusedInputSource?
    private var specialInputModeProfile: SpecialInputModeProfile?
    private var specialInputModePID: pid_t?
    private var specialInputModeBundleID: String?
    private var specialInputModeWindowTitle: String?
    private var specialInputModeAnchorPoint: CGPoint?
    private var specialInputModeUntil: Date = .distantPast
    private var didLogSessionTargetMismatch: Bool = false
    private var typingRecoveryHoldUntil: Date = .distantPast
    private var typingRecoveryHoldReason: String?
    private let wakeTypingFallbackWindow: TimeInterval = 1.6
    private var wakeTypingFallbackUntil: Date = .distantPast
    private var lastFocusToastAt: Date = .distantPast
    private var hudOverrideUntil: Date = .distantPast
    private var hudOverrideMode: HUDMode = .command
    private var hudOverrideMessage: String = ""
    private var hudOverrideIcon: String = "info.circle"
    private var hudOverrideInputDeviceHealth: HUDInputDeviceHealth = .normal
    private var activeHUDStageOwner: String?
    private var activeHUDStageMode: HUDMode?
    private var activeHUDStageMessage: String = ""
    private var activeHUDStageControlMode: HUDRecognitionControlMode?
    private var pendingCheckingHUDWorkItem: DispatchWorkItem?
    private var activeTextRewriteHUDCount: Int = 0
    private var isTextRewriteHUDSlowPhase = false
    private var pendingTextRewriteSlowHUDWorkItem: DispatchWorkItem?
    private var isUtteranceActive: Bool = false
    private var cachedTypingMode: Bool = false
    private var lastTypingCheckAt: Date = .distantPast
    private var lastChangeAt: Date?
    private var lastStableText: String = ""
    private var lastHandsFreeHUDActivityAt: Date = Date()
    private var speechExitBarsHoldUntil: Date = .distantPast
    private var speechHUDTextVisible = false
    private var continuousTimer: Timer?
    private var stopTimer: Timer?
    private var finalizationWorkItem: DispatchWorkItem?
    private var pendingFinalizeKeepHUDVisible: Bool = false
    private var pendingFinalizeDiscardTranscript: Bool = false
    private var pendingEngineRestartWorkItem: DispatchWorkItem?
    private var continuousRecoveryWorkItem: DispatchWorkItem?
    private struct PendingWakeFollowUp {
        let groupID: String
        var phrase: String?
        let localeIdentifier: String
        let createdAt: Date
        var lastActivityAt: Date
        var timeoutWorkItem: DispatchWorkItem?
    }
    private struct RecentExpiredWakeFollowUp {
        let groupID: String
        let phrase: String?
        let localeIdentifier: String
        let createdAt: Date
        let expiredAt: Date
        var finalizeWorkItem: DispatchWorkItem?
    }
    private struct RecentWakeFollowUpDictationSuppression {
        let groupID: String
        let textKey: String
        let pid: pid_t?
        let bundleID: String?
        let elementFingerprint: String?
        let expiresAt: Date
    }
    private var pendingWakeFollowUp: PendingWakeFollowUp?
    private var recentExpiredWakeFollowUp: RecentExpiredWakeFollowUp?
    private var wakeActivatedDuringCurrentUtterance: Bool = false
    private var lastWakeHUDDiagnosticSignature: String?
    private var lastWakeHUDDiagnosticAt: Date = .distantPast
    private var lastWakeArmDiagnosticSignature: String?
    private var lastWakeArmDiagnosticAt: Date = .distantPast
    private var lastStandbyWakeMissSegmentationAt: Date = .distantPast
    private var lastEngineRestartAt: Date = .distantPast
    private var suppressRecognitionFailuresUntil: Date = .distantPast
    private var suppressRecognitionFailuresReason: String?
    private var hasCompletedInitialLocaleSetup = false
    private var headsetVoiceProcessingSuppressedUntil: Date = .distantPast
    private var headsetVoiceProcessingFaultTimes: [Date] = []
    private var customAppShortcutRules: [CustomAppShortcutRule] = []
    private let engineRestartDebounce: TimeInterval = 0.55
    private let engineRestartMinInterval: TimeInterval = 1.5
    private let voiceActivityWithoutPartialRecoveryThreshold: TimeInterval = 1.8
    private var continuousRecoveryGraceUntil: Date = .distantPast
    private var routeRebuildGraceUntil: Date = .distantPast
    private var recognitionStartupGraceUntil: Date = .distantPast
    private var recognitionUnavailableUntil: Date = .distantPast
    private var noSpeechRecoveryUntil: Date = .distantPast
    private var consecutiveRecognitionUnavailableCount: Int = 0
    private var consecutiveNoSpeechRecoveries: Int = 0
    private var standbyWakeMissRecoveryUntil: Date = .distantPast
    private var wakeActivationRecoveryUntil: Date = .distantPast
    private var lastContinuousStartAt: Date = .distantPast
    private var nextAllowedStartOnceAt: Date = .distantPast
    private var isContinuousDictationWaitingForInputFocus: Bool = false
    private var lastRecognitionBufferWithoutSessionAt: Date = .distantPast
    private let textRewriteHUDSlowMessageDelay: TimeInterval = 4.0
    private var pendingExplicitCommandPrefixExpiry: Date?
    private let pendingExplicitCommandPrefixWindow: TimeInterval = 4.0
    private var cancellables = Set<AnyCancellable>()
    private let intentPipeline = IntentPipeline()
    private var utteranceExecutionGuard = UtteranceExecutionGuard(maxHistory: 128)
    private var lastHandledSessionGeneration: Int = -1
    private var lastHandledUtteranceID: Int = -1
    private var lastHandledTranscript: String = ""
    private var lastHandledAt: Date = .distantPast
    private var lastCommittedDictationText: String = ""
    private var lastCommittedDictationAt: Date = .distantPast
    private var lastCommittedDictationPID: pid_t?
    private var lastCommittedDictationBundleID: String?
    private var customAppLaunchAliasRules: [CustomAppLaunchAliasRule] = []
    private var lastCommittedDictationElementFingerprint: String?
    private let wakeFollowUpDuplicateSuppressionWindow: TimeInterval = 1.2
    private let wakeFollowUpLateFinalGraceWindow: TimeInterval = 1.35
    private let wakeFollowUpLateFinalActivityWindow: TimeInterval = 1.1
    private let wakeFollowUpActivityRefreshDebounce: TimeInterval = 0.45
    private let standbyWakeMissSegmentationDebounce: TimeInterval = 0.85
    private var recentWakeFollowUpDictationSuppression: RecentWakeFollowUpDictationSuppression?
    private var wakeFollowUpDictationMarkers: [String: String] = [:]
    private var lastWakeFollowUpActivityRefreshAt: Date = .distantPast
    private let postSubmitStreamingSuppressionWindow: TimeInterval = 0.8
    private var postSubmitDictationSuppression: PostSubmitDictationSuppression?
    private let postSubmitDictationSuppressionWindow: TimeInterval = 1.2
    // Mic progress tracking (kept for HUD ring)
    private var micProgressTimer: Timer?
    private var segmentStartedAt: Date = .distantPast
    private var segmentDurationSec: TimeInterval = 0
    private var isMicProgressPausedForTarget: Bool = false
    private var micProgressLockedPID: pid_t?
    private var micProgressSilentTicks: Int = 0
    private var latestVoiceActivity: Bool = false
    private var latestVoiceRMS: Float = 0
    private var micProgressActiveTicks: Int = 0
    private var sessionStartedAt: Date = .distantPast
    private var didRecordFirstPartialForSession: Bool = false
    private var voiceActivityWithoutPartialSince: Date?
    private var lastVoiceActivityDiagnosticAt: Date = .distantPast
    private var lastVoiceWithoutPartialDiagnosticAt: Date = .distantPast
    private var lastVoiceWithoutPartialRecoveryAt: Date = .distantPast
    private var lastAdaptiveTextCount: Int = 0
    private var lastAdaptiveSampleAt: Date = .distantPast
    private var deferredAudioStopWorkItem: DispatchWorkItem?
    private var startupInputHealthProbeWorkItem: DispatchWorkItem?
    private var temporaryFallbackInputDeviceID: AudioDeviceID?
    private var startupDetectedUsableAudioForSession = false
    private var startupFallbackAttemptedForSession = false
    private var startupPlaybackLeakHintShownForSession = false
    private var audioEnergyObservations: [AudioEnergyObservation] = []
    private var currentSpeechProcessingProfile: SessionSpeechProcessingProfile = .passthrough
    private var pttAudioCaptureGracePeriod: TimeInterval {
        let raw = UserDefaults.standard.object(forKey: "pttAudioCaptureGracePeriod") as? Double ?? 8.0
        return min(max(raw, 1.5), 20.0)
    }

    private var handsFreeHUDCollapseDelay: TimeInterval { 8.0 }
    private var speechExitBarsHoldDuration: TimeInterval { 0.32 }

    private struct RuntimeSpeechMetrics {
        var sessions: Int = 0
        var utterances: Int = 0
        var commands: Int = 0
        var dictations: Int = 0
        var unknowns: Int = 0
        var engineRestarts: Int = 0
        var lowConfidenceCommandDowngrades: Int = 0
        var recoverableErrors: Int = 0
        var fatalErrors: Int = 0
        var firstPartialSamples: Int = 0
        var firstPartialLatencyTotalMs: Double = 0

        var firstPartialLatencyAvgMs: Double {
            guard firstPartialSamples > 0 else { return 0 }
            return firstPartialLatencyTotalMs / Double(firstPartialSamples)
        }
    }

    private var metrics = RuntimeSpeechMetrics()
    private var selectedInputDeviceUIDHint: String?
    private var selectedInputDeviceNameHint: String?
    private var pendingSelectedInputRouteSnapshot: AudioRouteSnapshot?
    private var suppressInputSelectionRestart = false

    private struct AudioRouteSnapshot: Equatable {
        let selectedInputID: AudioDeviceID
        let effectiveInputID: AudioDeviceID
        let defaultInputID: AudioDeviceID
        let defaultOutputID: AudioDeviceID
    }

    // MARK: - Computed Properties (preserved)
    private typealias RecognitionControlMode = HeadMotionManager.RecognitionControlMode

    private enum SpecialInputModeProfile: String {
        case weChatChat = "wechat-chat"
    }

    static func resolvedUtteranceTypingMode(
        recognitionControlMode: HeadMotionManager.RecognitionControlMode,
        sessionTypingMode: Bool,
        liveTyping: Bool,
        canType: Bool,
        hasStreamedDictation: Bool
    ) -> Bool {
        switch recognitionControlMode {
        case .command:
            return false
        case .dictation:
            return canType
        case .auto:
            guard canType else { return false }
            // Only keep a sticky typing state if this utterance has already injected text.
            // This prevents a stale input-state snapshot from hijacking a visible control-mode utterance.
            return liveTyping || (sessionTypingMode && hasStreamedDictation)
        }
    }

    static func shouldAllowWakeGatedTyping(
        isWakeWordEnabled: Bool,
        isDirectCommandEnabled: Bool,
        isAwake: Bool,
        wakeWordDetected: Bool
    ) -> Bool {
        guard isWakeWordEnabled, !isDirectCommandEnabled else { return true }
        return isAwake || wakeWordDetected
    }

    static func validateDictationEnhancement(
        sourceText: String,
        candidateText: String,
        localeIdentifier: String
    ) -> DictationEnhancementValidationResult {
        let source = sourceText.trimmingCharacters(in: .whitespacesAndNewlines)
        let candidate = candidateText.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !candidate.isEmpty else {
            return .reject("empty")
        }
        if source == candidate {
            return .accept(candidate, changed: false)
        }

        let sourceBody = guardrailComparableTextBody(source)
        let candidateBody = guardrailComparableTextBody(candidate)
        if sourceBody == candidateBody {
            return .accept(candidate, changed: false)
        }

        if hasProtectedTokenDrift(sourceText: source, candidateText: candidate) {
            return .reject("protected-token")
        }
        if hasLanguageDrift(sourceText: source, candidateText: candidate, localeIdentifier: localeIdentifier) {
            return .reject("language-drift")
        }

        let sourceCount = sourceBody.count
        let editDistance = levenshteinDistance(sourceBody, candidateBody)
        if sourceCount <= 6, editDistance > 1 {
            return .reject("short-text-rewrite")
        }
        if sourceCount <= 12, editDistance > 3 {
            return .reject("short-text-rewrite")
        }

        if sourceCount > 12 {
            let ratio = Double(editDistance) / Double(max(sourceCount, 1))
            if ratio > 0.45 {
                return .reject("over-rewrite")
            }
        }

        return .accept(candidate, changed: true)
    }

    static func dictationEnhancementSkipReason(
        text: String,
        localeIdentifier: String
    ) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "empty" }

        let urlLikePatterns = [
            #"https?://\S+"#,
            #"www\.\S+"#,
            #"[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}"#,
            #"(?:~?/[\w.\-]+)+(?:\.[A-Za-z0-9]+)?"#
        ]
        if urlLikePatterns.contains(where: { !regexMatches(pattern: $0, in: trimmed).isEmpty }) {
            return "structured-text"
        }

        let digitCount = trimmed.unicodeScalars.reduce(into: 0) { partialResult, scalar in
            if CharacterSet.decimalDigits.contains(scalar) {
                partialResult += 1
            }
        }
        if digitCount >= 4, Double(digitCount) / Double(max(trimmed.count, 1)) >= 0.25 {
            return "numeric-dense"
        }

        if isLikelyCodeLikeEnhancementInput(trimmed, localeIdentifier: localeIdentifier) {
            return "code-like"
        }

        return nil
    }

    static func wakeMatchMode(
        isWakeWordEnabled: Bool,
        isDirectCommandEnabled: Bool,
        isAlwaysListeningEnabled: Bool,
        isAwake: Bool
    ) -> WakeWordMatchMode {
        guard isWakeWordEnabled, !isDirectCommandEnabled, isAlwaysListeningEnabled else {
            return .strictPrefix
        }
        return isAwake ? .awakeFollowUp : .retryAwareStandby
    }

    static func shouldSegmentRecognitionAfterPartialWake(
        isAlwaysListeningEnabled: Bool,
        isWakeWordEnabled: Bool,
        isDirectCommandEnabled: Bool,
        wakePayload: String
    ) -> Bool {
        guard isAlwaysListeningEnabled, isWakeWordEnabled, !isDirectCommandEnabled else {
            return false
        }
        return wakePayload.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    static func shouldRecoverFromContinuousStandbyNoBufferStall(
        isAlwaysListeningEnabled: Bool,
        isWakeWordEnabled: Bool,
        isDirectCommandEnabled: Bool,
        isAwake: Bool,
        isStopping: Bool,
        isUtteranceActive: Bool,
        audioCaptureRunning: Bool,
        recognitionRunning: Bool,
        pendingEngineRestart: Bool,
        bufferAge: TimeInterval,
        routeRebuildGraceActive: Bool,
        continuousRecoveryGraceActive: Bool,
        recognitionStartupGraceActive: Bool,
        recognitionUnavailableActive: Bool
    ) -> Bool {
        guard isAlwaysListeningEnabled, isWakeWordEnabled, !isDirectCommandEnabled, !isAwake else {
            return false
        }
        guard !isStopping, !isUtteranceActive else { return false }
        guard audioCaptureRunning, recognitionRunning else { return false }
        guard !pendingEngineRestart else { return false }
        guard !routeRebuildGraceActive,
              !continuousRecoveryGraceActive,
              !recognitionStartupGraceActive,
              !recognitionUnavailableActive else {
            return false
        }
        guard bufferAge.isFinite else { return false }
        return bufferAge >= 1.8
    }

    static func shouldUseWakeTypingFallback(
        recognitionControlMode: HeadMotionManager.RecognitionControlMode,
        dictationEnabled: Bool,
        liveTyping: Bool,
        pendingWakeFollowUp: Bool,
        sessionTargetAvailable: Bool,
        frontmostMatchesTarget: Bool,
        fallbackWindowActive: Bool,
        typingSuppressed: Bool
    ) -> Bool {
        guard recognitionControlMode == .auto else { return false }
        guard dictationEnabled else { return false }
        guard !liveTyping else { return false }
        guard pendingWakeFollowUp else { return false }
        guard sessionTargetAvailable else { return false }
        guard frontmostMatchesTarget else { return false }
        guard fallbackWindowActive else { return false }
        guard !typingSuppressed else { return false }
        return true
    }

    static func shouldRestoreWakeTypingFallbackBeforeRouting(
        wakeLifecycleActive: Bool,
        recognitionControlMode: HeadMotionManager.RecognitionControlMode,
        dictationEnabled: Bool,
        liveTyping: Bool,
        pendingWakeFollowUp: Bool,
        sessionTargetAvailable: Bool,
        frontmostMatchesTarget: Bool,
        fallbackWindowActive: Bool,
        typingSuppressed: Bool
    ) -> Bool {
        guard !wakeLifecycleActive else { return false }
        return shouldUseWakeTypingFallback(
            recognitionControlMode: recognitionControlMode,
            dictationEnabled: dictationEnabled,
            liveTyping: liveTyping,
            pendingWakeFollowUp: pendingWakeFollowUp,
            sessionTargetAvailable: sessionTargetAvailable,
            frontmostMatchesTarget: frontmostMatchesTarget,
            fallbackWindowActive: fallbackWindowActive,
            typingSuppressed: typingSuppressed
        )
    }

    static func shouldPreferWakeCommandRouting(
        recognitionControlMode: HeadMotionManager.RecognitionControlMode,
        commandEnabled: Bool,
        wakeLifecycleActive: Bool,
        wakePayloadLooksLikeCommand: Bool,
        liveTyping: Bool
    ) -> Bool {
        guard recognitionControlMode == .auto else { return false }
        guard commandEnabled else { return false }
        guard wakeLifecycleActive else { return false }
        guard wakePayloadLooksLikeCommand else { return false }
        guard !liveTyping else { return false }
        return true
    }

    static func resolveWakeFollowUpArbitration(
        controlMode: HeadMotionManager.RecognitionControlMode,
        transcript: String,
        routerDecision: VoiceCommandDecision,
        hasStableTypingEvidence: Bool,
        hasLiveTypingEvidence: Bool,
        hasCommittedDictation: Bool
    ) -> UtteranceArbitrationResult {
        InputControlArbiter.resolveUtteranceDecision(
            controlMode: InputControlMode(controlMode),
            transcript: transcript,
            routerDecision: routerDecision,
            interactionState: hasStableTypingEvidence ? .typing : .pending,
            hasLiveTypingEvidence: hasLiveTypingEvidence,
            transport: .wakeFollowUp,
            hasCommittedDictation: hasCommittedDictation
        )
    }

    static func shouldPromoteInlineWakePayloadToTypingContext(
        recognitionControlMode: HeadMotionManager.RecognitionControlMode,
        dictationEnabled: Bool,
        wakeFollowUpActive: Bool,
        wakePayload: String,
        hasAuthoritativeTypingEvidence: Bool,
        liveTyping: Bool,
        commandLikely: Bool = false
    ) -> Bool {
        guard recognitionControlMode == .auto else { return false }
        guard dictationEnabled else { return false }
        guard wakeFollowUpActive else { return false }
        guard !wakePayload.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        guard !commandLikely else { return false }
        return hasAuthoritativeTypingEvidence || liveTyping
    }

    static func shouldSuppressWakeFollowUpEcho(
        pendingWakePhrase: String?,
        routedTranscript: String,
        hasStreamedDictation: Bool
    ) -> Bool {
        let phraseKey = wakeFollowUpComparisonKey(pendingWakePhrase ?? "")
        guard !phraseKey.isEmpty else { return false }
        let transcriptKey = wakeFollowUpComparisonKey(routedTranscript)
        guard !transcriptKey.isEmpty else { return false }
        if phraseKey == transcriptKey { return true }
        guard !hasStreamedDictation else { return false }
        return false
    }

    static func shouldSuppressImmediateWakeFollowUpDuplicate(
        previousText: String,
        currentText: String
    ) -> Bool {
        let previousKey = wakeFollowUpComparisonKey(previousText)
        guard !previousKey.isEmpty else { return false }

        return previousKey == wakeFollowUpComparisonKey(currentText)
    }

    static func wakeFollowUpComparisonKey(_ text: String) -> String {
        var trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }

        let trailingPunctuation = CharacterSet(charactersIn: "。！？!?.,，、；;：:…")
        while let lastScalar = trimmed.unicodeScalars.last,
              CharacterSet.whitespacesAndNewlines.contains(lastScalar) || trailingPunctuation.contains(lastScalar) {
            trimmed.removeLast()
        }

        return trimmed.folding(
            options: [.caseInsensitive, .diacriticInsensitive],
            locale: Locale(identifier: "en_US_POSIX")
        )
    }

    static func reconcileTypingContextWithVisibleHUD(
        recognitionControlMode: HeadMotionManager.RecognitionControlMode,
        computedTypingContext: Bool
    ) -> Bool {
        guard recognitionControlMode == .auto else { return computedTypingContext }

        // The visible HUD is downstream from typing inference, so it cannot be allowed
        // to veto routing in auto mode. Keep a single authoritative typing decision
        // and let the HUD follow it instead of feeding back into it.
        return computedTypingContext
    }

    static func resolvedRoutingBias(
        recognitionControlMode: HeadMotionManager.RecognitionControlMode,
        typingContext: Bool,
        dictationEnabled: Bool,
        commandEnabled: Bool,
        consumeExplicitCommandPrefix: Bool
    ) -> (bias: VoiceCommandRouter.RoutingBias, blockDictationWithoutInput: Bool) {
        var routingBias: VoiceCommandRouter.RoutingBias = .neutral
        var blockDictationWithoutInput = false

        switch recognitionControlMode {
        case .command:
            routingBias = .forceCommand
        case .dictation:
            if typingContext {
                routingBias = .forceDictation
            } else {
                routingBias = .forceCommand
                blockDictationWithoutInput = true
            }
        case .auto:
            routingBias = typingContext ? .dictationPreferred : .commandPreferred
        }

        if dictationEnabled && !commandEnabled {
            if typingContext {
                routingBias = .forceDictation
            }
        } else if !dictationEnabled && commandEnabled {
            routingBias = .forceCommand
            blockDictationWithoutInput = true
        }

        if commandEnabled && consumeExplicitCommandPrefix {
            routingBias = .forceCommand
            blockDictationWithoutInput = false
        }

        return (routingBias, blockDictationWithoutInput)
    }

    private var recognitionControlMode: RecognitionControlMode {
        HeadMotionManager.shared.effectiveRecognitionControlMode
    }

    private var authoritativeInputControlSnapshot: InputControlSnapshot {
        InputControlArbiter.shared.currentSnapshot
    }

    private var sessionTypingMode: Bool {
        authoritativeInputControlSnapshot.interactionState.isTyping
    }

    private func currentInputControlSessionState() -> InputControlSessionState {
        if recognitionControlMode == .auto, isTypingRecoveryHoldActive {
            return .recoveryHold
        }
        if isDictating || !dictationHandler.screenTypedText.isEmpty {
            return .typingSession
        }
        if recognitionSession.isRunning || isStopping || isUtteranceActive || isPTTHeld || pendingWakeFollowUp != nil {
            if authoritativeInputControlSnapshot.sessionState == .typingSession
                || authoritativeInputControlSnapshot.sessionState == .recoveryHold {
                return authoritativeInputControlSnapshot.sessionState
            }
            return .commandSession
        }
        return .idle
    }

    @discardableResult
    private func setAuthoritativeSessionTyping(
        _ typing: Bool,
        source: String
    ) -> InputControlSnapshot {
        let nextSessionState: InputControlSessionState
        if recognitionControlMode == .auto, isTypingRecoveryHoldActive {
            nextSessionState = .recoveryHold
        } else if typing {
            nextSessionState = .typingSession
        } else if recognitionSession.isRunning || isStopping || isUtteranceActive || isPTTHeld || pendingWakeFollowUp != nil {
            nextSessionState = .commandSession
        } else {
            nextSessionState = .idle
        }

        return InputControlArbiter.shared.sync(
            controlMode: InputControlMode(recognitionControlMode),
            sessionState: nextSessionState,
            utteranceDecision: authoritativeInputControlSnapshot.utteranceDecision,
            hasCommittedDictation: !dictationHandler.screenTypedText.isEmpty,
            hasStreamedDictation: !dictationHandler.screenTypedText.isEmpty,
            source: source
        )
    }

    @discardableResult
    private func syncInputControlState(source: String) -> InputControlSnapshot {
        InputControlArbiter.shared.sync(
            controlMode: InputControlMode(recognitionControlMode),
            sessionState: currentInputControlSessionState(),
            utteranceDecision: authoritativeInputControlSnapshot.utteranceDecision,
            hasCommittedDictation: !dictationHandler.screenTypedText.isEmpty,
            hasStreamedDictation: !dictationHandler.screenTypedText.isEmpty,
            source: source
        )
    }

    private func setCurrentUtteranceArbitration(
        _ result: UtteranceArbitrationResult,
        source: String
    ) {
        InputControlArbiter.shared.updateUtteranceDecision(
            InputControlUtteranceDecision(result.state),
            source: source
        )
    }

    private func audioDeviceID(for selector: AudioObjectPropertySelector) -> AudioDeviceID? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var id: AudioDeviceID = 0
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &id) == noErr,
              id != 0 else {
            return nil
        }
        return id
    }

    private func audioDeviceName(_ id: AudioDeviceID) -> String {
        guard id != 0 else { return "" }
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyName,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let ref = UnsafeMutablePointer<CFString?>.allocate(capacity: 1)
        ref.initialize(to: nil)
        defer {
            ref.deinitialize(count: 1)
            ref.deallocate()
        }
        var size = UInt32(MemoryLayout<CFString?>.size)
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, ref) == noErr,
              let resolved = ref.pointee else {
            return ""
        }
        return resolved as String
    }

    private func isHeadsetLikeDeviceName(_ raw: String) -> Bool {
        let name = raw.lowercased()
        return name.contains("airpods")
            || name.contains("beats")
            || name.contains("headphone")
            || name.contains("earphone")
            || name.contains("bluetooth")
            || name.contains("耳机")
    }

    private func normalizedInputDeviceName(_ raw: String) -> String {
        raw
            .lowercased()
            .replacingOccurrences(of: "麦克风", with: "")
            .replacingOccurrences(of: "microphone", with: "")
            .replacingOccurrences(of: "(输入)", with: "")
            .replacingOccurrences(of: "(input)", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func isVirtualOrAggregateAudioDevice(name: String, uid: String) -> Bool {
        let lowerName = name.lowercased()
        let lowerUID = uid.lowercased()
        return lowerName.contains("aggregate")
            || lowerUID.contains("aggregate")
            || lowerUID.contains("vpa")
            || lowerUID.contains("cadefaultdeviceaggregate")
            || lowerName.contains("blackhole")
            || lowerName.contains("soundflower")
            || lowerUID.contains("blackhole")
            || lowerUID.contains("soundflower")
    }

    private func audioDeviceTransportType(_ id: AudioDeviceID) -> UInt32? {
        guard id != 0 else { return nil }
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyTransportType,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var transport: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &transport) == noErr else {
            return nil
        }
        return transport
    }

    private func audioTransportLabel(_ transport: UInt32?) -> String {
        switch transport {
        case kAudioDeviceTransportTypeBuiltIn?: return "built-in"
        case kAudioDeviceTransportTypeUSB?: return "usb"
        case kAudioDeviceTransportTypeBluetooth?: return "bluetooth"
        case kAudioDeviceTransportTypeBluetoothLE?: return "bluetooth-le"
        case kAudioDeviceTransportTypeHDMI?: return "hdmi"
        case kAudioDeviceTransportTypeDisplayPort?: return "displayport"
        case kAudioDeviceTransportTypeAirPlay?: return "airplay"
        case kAudioDeviceTransportTypeAggregate?: return "aggregate"
        case kAudioDeviceTransportTypeVirtual?: return "virtual"
        case kAudioDeviceTransportTypeThunderbolt?: return "thunderbolt"
        case kAudioDeviceTransportTypeContinuityCapture?: return "continuity"
        case kAudioDeviceTransportTypeContinuityCaptureWired?: return "continuity-wired"
        case kAudioDeviceTransportTypeContinuityCaptureWireless?: return "continuity-wireless"
        case nil: return "unknown"
        default: return String(transport ?? 0)
        }
    }

    private func logVisibleInputDevices(_ devices: [AudioInputDevice], context: String) {
        let summary = devices
            .filter { $0.id != 0 }
            .map {
                "\($0.name){id=\($0.id),uid=\($0.uid),transport=\(audioTransportLabel(audioDeviceTransportType($0.id)))}"
            }
            .joined(separator: " | ")
        GlobalLogger.speech.info("[AudioRoute] \(context) visible inputs => \(summary)")
    }

    private func realCaptureDeviceUIDs() -> Set<String> {
        Set(AVCaptureDevice.devices(for: .audio).map(\.uniqueID))
    }

    private func realCaptureDeviceNames() -> Set<String> {
        Set(AVCaptureDevice.devices(for: .audio).map { normalizedInputDeviceName($0.localizedName) })
    }

    private func shouldKeepInputDeviceCandidate(
        name: String,
        uid: String,
        transportType: UInt32?,
        realCaptureUIDs: Set<String>,
        realCaptureNames: Set<String>
    ) -> Bool {
        let lowerName = name.lowercased()
        if lowerName.contains("speaker") || lowerName.contains("扬声器") {
            return false
        }

        switch transportType {
        case kAudioDeviceTransportTypeVirtual?,
             kAudioDeviceTransportTypeAggregate?,
             kAudioDeviceTransportTypeHDMI?,
             kAudioDeviceTransportTypeDisplayPort?,
             kAudioDeviceTransportTypeAirPlay?:
            return false
        default:
            break
        }

        if isVirtualOrAggregateAudioDevice(name: name, uid: uid) { return false }
        if realCaptureUIDs.contains(uid) || realCaptureNames.contains(normalizedInputDeviceName(name)) { return true }

        if isHeadsetLikeDeviceName(name) { return true }
        if lowerName.contains("mic") || lowerName.contains("microphone") || lowerName.contains("麦") {
            return true
        }

        switch transportType {
        case kAudioDeviceTransportTypeBuiltIn?,
             kAudioDeviceTransportTypeUSB?,
             kAudioDeviceTransportTypeBluetooth?,
             kAudioDeviceTransportTypeBluetoothLE?,
             kAudioDeviceTransportTypeThunderbolt?,
             kAudioDeviceTransportTypeContinuityCapture?,
             kAudioDeviceTransportTypeContinuityCaptureWired?,
             kAudioDeviceTransportTypeContinuityCaptureWireless?:
            return true
        default:
            return false
        }
    }

    private func shouldReplaceInputDeviceCandidate(
        existing: AudioInputDevice,
        replacementName: String,
        replacementUID: String,
        replacementTransportType: UInt32?
    ) -> Bool {
        if isVirtualOrAggregateAudioDevice(name: existing.name, uid: existing.uid)
            && !isVirtualOrAggregateAudioDevice(name: replacementName, uid: replacementUID) {
            return true
        }

        let existingTransport = audioDeviceTransportType(existing.id)
        let existingIsBluetooth = existingTransport == kAudioDeviceTransportTypeBluetooth
        let replacementIsBluetooth = replacementTransportType == kAudioDeviceTransportTypeBluetooth
        if replacementIsBluetooth && !existingIsBluetooth { return true }

        let existingIsBuiltIn = existingTransport == kAudioDeviceTransportTypeBuiltIn
        let replacementIsBuiltIn = replacementTransportType == kAudioDeviceTransportTypeBuiltIn
        if replacementIsBuiltIn && !existingIsBuiltIn { return true }

        let existingLooksHeadset = isHeadsetLikeDeviceName(existing.name)
        let replacementLooksHeadset = isHeadsetLikeDeviceName(replacementName)
        if replacementLooksHeadset && !existingLooksHeadset { return true }

        return false
    }

    private func canonicalInputDevices(from candidates: [AudioInputDevice]) -> [AudioInputDevice] {
        let captureDevices = AVCaptureDevice.devices(for: .audio)
        guard !captureDevices.isEmpty else { return candidates }

        var canonicalByName: [String: AudioInputDevice] = [:]
        for captureDevice in captureDevices {
            let normalizedName = normalizedInputDeviceName(captureDevice.localizedName)
            let match = candidates.first(where: { $0.uid == captureDevice.uniqueID })
                ?? candidates.first(where: { normalizedInputDeviceName($0.name) == normalizedName })
            guard let match else { continue }

            let canonical = AudioInputDevice(
                id: match.id,
                name: captureDevice.localizedName,
                uid: captureDevice.uniqueID.isEmpty ? match.uid : captureDevice.uniqueID,
                iconName: match.iconName
            )

            if let existing = canonicalByName[normalizedName] {
                if shouldReplaceInputDeviceCandidate(
                    existing: existing,
                    replacementName: canonical.name,
                    replacementUID: canonical.uid,
                    replacementTransportType: audioDeviceTransportType(canonical.id)
                ) {
                    canonicalByName[normalizedName] = canonical
                }
            } else {
                canonicalByName[normalizedName] = canonical
            }
        }

        let canonical = canonicalByName.values.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
        return canonical.isEmpty ? candidates : canonical
    }

    private func remapSelectedInputDeviceIfNeeded(using devices: [AudioInputDevice]) -> AudioDeviceID? {
        guard selectedInputDeviceID != 0 else { return nil }

        if let uidHint = selectedInputDeviceUIDHint,
           let uidMatch = devices.first(where: { $0.uid == uidHint }) {
            return uidMatch.id
        }

        if let nameHint = selectedInputDeviceNameHint {
            let normalizedHint = normalizedInputDeviceName(nameHint)
            if let nameMatch = devices.first(where: { normalizedInputDeviceName($0.name) == normalizedHint }) {
                return nameMatch.id
            }
        }

        if devices.contains(where: { $0.id == selectedInputDeviceID }) {
            return selectedInputDeviceID
        }

        return nil
    }

    private func preferredHeadsetInputDeviceID() -> AudioDeviceID? {
        guard selectedInputDeviceID == 0 else { return nil }
        guard let outputID = audioDeviceID(for: kAudioHardwarePropertyDefaultOutputDevice) else { return nil }

        let outputName = audioDeviceName(outputID)
        guard isHeadsetLikeDeviceName(outputName) else { return nil }

        let headsetInputs = availableInputDevices.filter { $0.id != 0 && isHeadsetLikeDeviceName($0.name) }
        guard !headsetInputs.isEmpty else { return nil }

        let lowerOutput = outputName.lowercased()
        if lowerOutput.contains("airpods"),
           let airPodsInput = headsetInputs.first(where: { $0.name.lowercased().contains("airpods") }) {
            return airPodsInput.id
        }

        if lowerOutput.contains("beats"),
           let beatsInput = headsetInputs.first(where: { $0.name.lowercased().contains("beats") }) {
            return beatsInput.id
        }

        return headsetInputs.first?.id
    }

    private func effectiveCaptureInputDeviceID() -> AudioDeviceID {
        if let temporaryFallbackInputDeviceID,
           availableInputDevices.contains(where: { $0.id == temporaryFallbackInputDeviceID }) {
            return temporaryFallbackInputDeviceID
        }
        if selectedInputDeviceID != 0 {
            if let remappedID = remapSelectedInputDeviceIfNeeded(using: availableInputDevices) {
                return remappedID
            }
            return selectedInputDeviceID
        }
        if let headsetInput = preferredHeadsetInputDeviceID() {
            return headsetInput
        }
        return audioDeviceID(for: kAudioHardwarePropertyDefaultInputDevice) ?? 0
    }

    private func currentAudioRouteSnapshot() -> AudioRouteSnapshot {
        AudioRouteSnapshot(
            selectedInputID: selectedInputDeviceID,
            effectiveInputID: effectiveCaptureInputDeviceID(),
            defaultInputID: audioDeviceID(for: kAudioHardwarePropertyDefaultInputDevice) ?? 0,
            defaultOutputID: audioDeviceID(for: kAudioHardwarePropertyDefaultOutputDevice) ?? 0
        )
    }

    private func applySelectedInputDeviceID(_ newValue: AudioDeviceID, allowRestart: Bool, reason: String) {
        guard selectedInputDeviceID != newValue else { return }
        temporaryFallbackInputDeviceID = nil
        let previous = suppressInputSelectionRestart
        suppressInputSelectionRestart = !allowRestart
        GlobalLogger.speech.info(
            "[AudioRoute] apply selection reason=\(reason) newID=\(newValue) allowRestart=\(allowRestart)"
        )
        selectedInputDeviceID = newValue
        suppressInputSelectionRestart = previous
    }

    private func shouldRestartForAudioRouteChange(from before: AudioRouteSnapshot, to after: AudioRouteSnapshot) -> Bool {
        before.effectiveInputID != after.effectiveInputID
    }

    private var currentResolvedInputDeviceName: String {
        if audioCapture.isRunning {
            let boundName = audioCapture.currentBoundInputDeviceName().trimmingCharacters(in: .whitespacesAndNewlines)
            if !boundName.isEmpty { return boundName }
        }
        let deviceIDToUse = effectiveCaptureInputDeviceID()
        return availableInputDevices.first(where: { $0.id == deviceIDToUse })?.name ?? ""
    }

    private var isHeadsetLikeInputDevice: Bool {
        let name = currentResolvedInputDeviceName.lowercased()
        let icon = currentInputDeviceIcon.lowercased()
        return icon.contains("airpod")
            || icon.contains("airpods")
            || name.contains("airpods")
            || name.contains("beats")
            || name.contains("headphone")
            || name.contains("earphone")
            || name.contains("bluetooth")
            || name.contains("耳机")
    }

    private var isPlaybackLeakRiskEnvironment: Bool {
        guard enhancedPlaybackLeakSuppressionEnabled else { return false }
        guard !audioCapture.isDefaultOutputHeadsetLike() else { return false }
        return NowPlayingService.shared.playbackRate > 0.05
    }

    private func shouldPreferPassthroughSpeechProcessing() -> Bool {
        let inputID = effectiveCaptureInputDeviceID()
        guard inputID != 0 else { return false }

        switch audioDeviceTransportType(inputID) {
        case kAudioDeviceTransportTypeBuiltIn?:
            return false
        default:
            return true
        }
    }

    private func desiredSpeechProcessingProfile(forTypingMode typingMode: Bool) -> SessionSpeechProcessingProfile {
        if shouldPreferPassthroughSpeechProcessing() {
            let inputName = currentResolvedInputDeviceName.isEmpty ? "unknown" : currentResolvedInputDeviceName
            GlobalLogger.speech.info("[VoiceProcessingIO] prefer passthrough for external input=\(inputName)")
            return .passthrough
        }
        return typingMode ? .dictation : .speechCommand
    }

    private func setPlaybackLeakState(_ newValue: PlaybackLeakState) {
        guard playbackLeakState != newValue else { return }
        playbackLeakState = newValue
    }

    private func appendAudioEnergyObservation(active: Bool, rms: Float, at now: Date) {
        audioEnergyObservations.append(AudioEnergyObservation(at: now, rms: rms, active: active))
        audioEnergyObservations.removeAll { now.timeIntervalSince($0.at) > 1.6 }
    }

    private func recentAudioEnergyObservations(window: TimeInterval = 0.9) -> [AudioEnergyObservation] {
        let now = Date()
        return audioEnergyObservations.filter { now.timeIntervalSince($0.at) <= window }
    }

    private func isCloseSpeechLikely(in observations: [AudioEnergyObservation]) -> Bool {
        guard !observations.isEmpty else { return false }
        let values = observations.map(\.rms)
        let maxRMS = values.max() ?? 0
        let minRMS = values.min() ?? 0
        let avgRMS = values.reduce(0, +) / Float(values.count)
        let earlySlice = observations.prefix(max(1, observations.count / 2))
        let earlyAvg = earlySlice.map(\.rms).reduce(0, +) / Float(earlySlice.count)
        let activeCount = observations.filter(\.active).count
        let rise = maxRMS - earlyAvg
        let range = maxRMS - minRMS
        return maxRMS >= 0.12
            || (maxRMS >= 0.085 && (rise >= 0.025 || range >= 0.035) && activeCount >= 3)
            || (avgRMS >= 0.07 && range >= 0.04 && activeCount >= 4)
    }

    private func isStablePlaybackLeakLikely(in observations: [AudioEnergyObservation]) -> Bool {
        guard observations.count >= 6 else { return false }
        let values = observations.map(\.rms)
        let maxRMS = values.max() ?? 0
        let minRMS = values.min() ?? 0
        let avgRMS = values.reduce(0, +) / Float(values.count)
        let activeRatio = Float(observations.filter(\.active).count) / Float(observations.count)
        let range = maxRMS - minRMS
        return avgRMS >= 0.035 && range <= 0.025 && activeRatio >= 0.65
    }

    private func applySpeechProcessingProfile(_ profile: SessionSpeechProcessingProfile, reason: String) {
        currentSpeechProcessingProfile = profile
        audioCapture.voiceProcessingProfile = profile.audioProfile
        if audioCapture.isRunning {
            audioCapture.applyRuntimeVoiceProcessingProfile(profile.audioProfile, reason: reason)
        }
        refreshPlaybackLeakStateForCurrentSession()
    }

    private func refreshPlaybackLeakStateForCurrentSession() {
        guard audioCapture.isRunning || recognitionSession.isRunning else {
            setPlaybackLeakState(.none)
            return
        }
        guard enhancedPlaybackLeakSuppressionEnabled else {
            setPlaybackLeakState(.none)
            return
        }
        if playbackLeakState == .suspectedPlaybackLeak,
           !didRecordFirstPartialForSession {
            return
        }
        if isPlaybackLeakRiskEnvironment, currentSpeechProcessingProfile != .passthrough {
            setPlaybackLeakState(.speechSuppressionActive)
        } else {
            setPlaybackLeakState(.none)
        }
    }

    private func cancelStartupInputHealthProbe() {
        startupInputHealthProbeWorkItem?.cancel()
        startupInputHealthProbeWorkItem = nil
    }

    private func bestNonHeadsetFallbackInputDeviceID(excluding excludedID: AudioDeviceID) -> AudioDeviceID? {
        let candidates = availableInputDevices.filter { $0.id != 0 && $0.id != excludedID && !isHeadsetLikeDeviceName($0.name) }
        guard !candidates.isEmpty else { return nil }

        if let defaultInputID = audioDeviceID(for: kAudioHardwarePropertyDefaultInputDevice),
           defaultInputID != excludedID,
           let defaultCandidate = candidates.first(where: { $0.id == defaultInputID }) {
            return defaultCandidate.id
        }

        return candidates.first?.id
    }

    private func scheduleStartupInputHealthProbe(for generation: Int) {
        cancelStartupInputHealthProbe()
        startupDetectedUsableAudioForSession = false
        startupFallbackAttemptedForSession = false
        guard isPTTHeld || !isAlwaysListeningEnabled else { return }

        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.startupInputHealthProbeWorkItem = nil
            guard self.sessionGeneration == generation else { return }
            guard self.audioCapture.isRunning, self.recognitionSession.isRunning, !self.isStopping else { return }
            guard self.isHeadsetLikeInputDevice else { return }
            guard !self.startupDetectedUsableAudioForSession, !self.startupFallbackAttemptedForSession else { return }

            let effectiveInputID = self.effectiveCaptureInputDeviceID()
            guard let fallbackID = self.bestNonHeadsetFallbackInputDeviceID(excluding: effectiveInputID) else {
                GlobalLogger.speech.info(
                    "[AudioRoute] startup health probe found no non-headset fallback selectedInputID=\(self.selectedInputDeviceID) effectiveInputID=\(effectiveInputID) boundInputID=\(self.audioCapture.currentBoundInputDeviceID())"
                )
                return
            }

            let boundInputID = self.audioCapture.currentBoundInputDeviceID()
            let boundInputName = self.audioCapture.currentBoundInputDeviceName()
            let fallbackName = self.availableInputDevices.first(where: { $0.id == fallbackID })?.name ?? self.audioDeviceName(fallbackID)
            self.startupFallbackAttemptedForSession = true
            self.temporaryFallbackInputDeviceID = fallbackID
            GlobalLogger.speech.info(
                "[AudioRoute] startup health probe fallback selectedInputID=\(self.selectedInputDeviceID) effectiveInputID=\(effectiveInputID) effectiveInputName=\(self.currentResolvedInputDeviceName) boundInputID=\(boundInputID) boundInputName=\(boundInputName) latestRMS=\(self.latestVoiceRMS) fallbackID=\(fallbackID) fallbackName=\(fallbackName)"
            )
            HUDManager.shared.showTemporary(
                message: AppLocalization.isChinese ? "已切到Mac麦" : "Switched to Mac mic",
                icon: self.hudInputIcon(),
                duration: 1.2
            )
            self.scheduleEngineRestart(reason: "startup-headset-unavailable", debounce: 0.01)
        }
        startupInputHealthProbeWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2, execute: workItem)
    }

    func isCurrentInputHeadsetLike() -> Bool {
        isHeadsetLikeInputDevice
    }

    private var shouldSuppressSystemHeadsetMicControl: Bool {
        false
    }

    private var isTypingRecoveryHoldActive: Bool {
        recognitionControlMode == .auto && Date() < typingRecoveryHoldUntil
    }

    private enum SessionSpeechStyle {
        case dictation
        case command
    }

    private func effectiveRecognitionControlMode(
        for availability: VoiceFeatureAvailability
    ) -> RecognitionControlMode {
        if availability.dictationEnabled && !availability.commandEnabled {
            return .auto
        }
        if !availability.dictationEnabled && availability.commandEnabled {
            return .command
        }
        return recognitionControlMode
    }

    private func currentSessionSpeechStyle(
        for availability: VoiceFeatureAvailability,
        sessionTypingModeOverride: Bool? = nil
    ) -> SessionSpeechStyle {
        if availability.dictationEnabled && !availability.commandEnabled {
            return .dictation
        }
        if !availability.dictationEnabled && availability.commandEnabled {
            return .command
        }

        switch effectiveRecognitionControlMode(for: availability) {
        case .dictation:
            return .dictation
        case .command:
            return .command
        case .auto:
            return (sessionTypingModeOverride ?? sessionTypingMode) ? .dictation : .command
        }
    }

    private func effectiveHUDRecognitionControlMode(
        for availability: VoiceFeatureAvailability,
        typingEligible: Bool
    ) -> HUDRecognitionControlMode {
        if availability.dictationEnabled && !availability.commandEnabled {
            return .dictation
        }
        if !availability.dictationEnabled && availability.commandEnabled {
            return .command
        }
        return effectiveRecognitionControlMode(for: availability).hudMode
    }

    private var hudRecognitionControlMode: HUDRecognitionControlMode {
        let availability = currentVoiceFeatureAvailability()
        let typingEligible = syncInputControlState(source: "speech.hud-control-mode").interactionState.isTyping
        return effectiveHUDRecognitionControlMode(
            for: availability,
            typingEligible: typingEligible
        )
    }

    private func recognitionTaskHint() -> SFSpeechRecognitionTaskHint {
        let availability = currentVoiceFeatureAvailability()
        switch currentSessionSpeechStyle(for: availability) {
        case .command:
            return .search
        case .dictation:
            return .dictation
        }
    }

    private func shouldPreferOnDeviceRecognition() -> Bool {
        let preferOnDevice = UserDefaults.standard.object(forKey: "preferOnDeviceRecognition") as? Bool ?? true
        if !preferOnDevice { return false }
        // Command mode benefits from lowest latency and deterministic behavior.
        if currentSessionSpeechStyle(for: currentVoiceFeatureAvailability()) == .command { return true }
        let preferForDictation = UserDefaults.standard.object(forKey: "preferOnDeviceForDictation") as? Bool ?? false
        return preferForDictation
    }

    private func configureEOSParameters(
        for availability: VoiceFeatureAvailability,
        sessionTypingMode: Bool
    ) {
        let baseTrailing = UserDefaults.standard.object(forKey: "trailingSilenceMs") as? Double ?? 1000
        let baseMinimum = UserDefaults.standard.object(forKey: "minUtteranceMs") as? Double ?? 550
        let dictationTrailingFloor = UserDefaults.standard.object(forKey: "dictationTrailingSilenceFloorMs") as? Double ?? 1300
        let dictationMinimumFloor = UserDefaults.standard.object(forKey: "dictationMinUtteranceFloorMs") as? Double ?? 650
        let wakeFollowUpTrailingFloor = UserDefaults.standard.object(forKey: "wakeFollowUpTrailingSilenceFloorMs") as? Double ?? 1000
        let wakeFollowUpMinimumFloor = UserDefaults.standard.object(forKey: "wakeFollowUpMinUtteranceFloorMs") as? Double ?? 550
        let style = currentSessionSpeechStyle(
            for: availability,
            sessionTypingModeOverride: sessionTypingMode
        )

        switch style {
        case .command:
            let commandTrailing = UserDefaults.standard.object(forKey: "commandTrailingSilenceMs") as? Double ?? 620
            let commandMinimum = UserDefaults.standard.object(forKey: "commandMinUtteranceMs") as? Double ?? 320
            eosDetector.trailingSilenceMs = min(baseTrailing, commandTrailing)
            eosDetector.minUtteranceMs = min(baseMinimum, commandMinimum)
        case .dictation:
            if isWakeFollowUpDictationContext(sessionTypingModeOverride: sessionTypingMode) {
                eosDetector.trailingSilenceMs = max(baseTrailing, wakeFollowUpTrailingFloor)
                eosDetector.minUtteranceMs = max(baseMinimum, wakeFollowUpMinimumFloor)
            } else {
                eosDetector.trailingSilenceMs = max(baseTrailing, dictationTrailingFloor)
                eosDetector.minUtteranceMs = max(baseMinimum, dictationMinimumFloor)
            }
        }

        let limits = resolvedSessionHardLimits(for: style)
        eosDetector.maxUtteranceMs = limits.maxUtteranceMs
        eosDetector.maxSegmentSec = limits.maxSegmentSec
    }

    private var isAwake: Bool {
        guard let last = lastWakeTime else { return false }
        return Date().timeIntervalSince(last) < alwaysListeningWakeWindowSeconds()
    }

    // Session-active follow-up means the app is still waiting for more speech.
    private var isWakeFollowUpSessionActive: Bool {
        isAwake || pendingWakeFollowUp != nil
    }

    // Routing stays slightly broader so late final results can still recover.
    private var isWakeFollowUpRoutingActive: Bool {
        isWakeFollowUpSessionActive || hasRecentExpiredWakeFollowUpGrace
    }

    private func isWakeFollowUpDictationContext(
        sessionTypingModeOverride: Bool? = nil,
        awakeOverride: Bool? = nil
    ) -> Bool {
        let typing = sessionTypingModeOverride ?? sessionTypingMode
        guard typing else { return false }
        guard isAlwaysListeningEnabled, isWakeWordEnabled, !isDirectCommandEnabled else { return false }
        if let awakeOverride {
            return awakeOverride || pendingWakeFollowUp != nil
        }
        return isWakeFollowUpSessionActive
    }

    private func alwaysListeningWakeWindowSeconds() -> TimeInterval {
        let v = UserDefaults.standard.object(forKey: "alwaysListeningWakeWindowSeconds") as? Double
            ?? VoiceDefaults.alwaysListeningWakeWindowSeconds
        return min(max(v, VoiceDefaults.minAlwaysListeningWakeWindowSeconds), VoiceDefaults.maxAlwaysListeningWakeWindowSeconds)
    }

    static func resolvedSessionHardLimits(
        isDictationStyle: Bool,
        commandMaxUtteranceMs: Double,
        commandMaxSegmentSec: Double,
        dictationMaxUtteranceMs: Double,
        dictationMaxSegmentSec: Double
    ) -> (maxUtteranceMs: Double, maxSegmentSec: Double) {
        if isDictationStyle {
            return (
                maxUtteranceMs: dictationMaxUtteranceMs,
                maxSegmentSec: dictationMaxSegmentSec
            )
        }

        return (
            maxUtteranceMs: commandMaxUtteranceMs,
            maxSegmentSec: commandMaxSegmentSec
        )
    }

    private func resolvedSessionHardLimits(
        for style: SessionSpeechStyle
    ) -> (maxUtteranceMs: Double, maxSegmentSec: Double) {
        let commandMaxUtteranceMs =
            UserDefaults.standard.object(forKey: "maxUtteranceMs") as? Double ?? 30000
        let commandMaxSegmentSec = maxRecordingSegmentSeconds()
        let dictationMaxUtteranceMsRaw =
            UserDefaults.standard.object(forKey: "dictationMaxUtteranceMs") as? Double ?? 600000
        let dictationMaxSegmentSecRaw =
            UserDefaults.standard.object(forKey: "dictationMaxRecordingSegmentSeconds") as? Double ?? 600.0
        let dictationMaxUtteranceMs = min(max(dictationMaxUtteranceMsRaw, 60000), 3600000)
        let dictationMaxSegmentSec = min(max(dictationMaxSegmentSecRaw, 60.0), 3600.0)

        return Self.resolvedSessionHardLimits(
            isDictationStyle: {
                switch style {
                case .dictation:
                    return true
                case .command:
                    return false
                }
            }(),
            commandMaxUtteranceMs: commandMaxUtteranceMs,
            commandMaxSegmentSec: commandMaxSegmentSec,
            dictationMaxUtteranceMs: dictationMaxUtteranceMs,
            dictationMaxSegmentSec: dictationMaxSegmentSec
        )
    }

    private func maxRecordingSegmentSeconds() -> TimeInterval {
        let v = UserDefaults.standard.object(forKey: "maxRecordingSegmentSeconds") as? Double ?? 32.0
        return min(max(v, 10.0), 120.0)
    }

    var currentInputDeviceIcon: String {
        let realHardware = availableInputDevices.filter { $0.id != 0 }
        if realHardware.isEmpty { return "mic.slash.fill" }
        let boundInputID = audioCapture.currentBoundInputDeviceID()
        let deviceIDToUse = (audioCapture.isRunning && boundInputID != 0) ? boundInputID : effectiveCaptureInputDeviceID()
        if let matched = availableInputDevices.first(where: { $0.id == deviceIDToUse }) {
            let lowerName = matched.name.lowercased()
            let isAP = lowerName.contains("airpods") || matched.iconName.contains("airpod")
            guard isAP else { return matched.iconName }
            let side = AirPodsDetector.shared.currentSide()
            if side == .none { return matched.iconName }
            let base = normalizeAirPodsSymbolName(matched.iconName)
            switch side {
            case .left: return base == "airpods.max" ? "airpods.max" : base == "airpods.pro" ? "airpods.pro.left" : "airpod.gen3.left"
            case .right: return base == "airpods.max" ? "airpods.max" : base == "airpods.pro" ? "airpods.pro.right" : "airpod.gen3.right"
            case .both: return base == "airpods.max" ? "airpods.max" : base == "airpods.pro" ? "airpods.pro" : "airpod.gen3"
            case .none: return matched.iconName
            }
        }
        if selectedInputDeviceID != 0, let sel = availableInputDevices.first(where: { $0.id == selectedInputDeviceID }) { return sel.iconName }
        if let any = availableInputDevices.first(where: { $0.id != 0 }) { return any.iconName }
        return AudioInputDevice.defaultSystem.iconName
    }

    private func hudInputIcon() -> String {
        let icon = currentInputDeviceIcon
        let side = AirPodsDetector.shared.currentSide()
        if icon != lastLoggedHUDIcon || side != lastLoggedAirPodSide {
            let deviceIDToUse = effectiveCaptureInputDeviceID()
            let activeName = availableInputDevices.first(where: { $0.id == deviceIDToUse })?.name ?? "unknown"
            GlobalLogger.speech.info("[HUD Icon] icon=\(icon), side=\(side.rawValue), selectedID=\(selectedInputDeviceID), activeID=\(deviceIDToUse), activeName=\(activeName)")
            lastLoggedHUDIcon = icon
            lastLoggedAirPodSide = side
        }
        return icon
    }

    private func hudInputHealth() -> HUDInputDeviceHealth {
        let realHardware = availableInputDevices.filter { $0.id != 0 }
        if realHardware.isEmpty {
            return .error
        }
        if AVCaptureDevice.authorizationStatus(for: .audio) != .authorized {
            return .error
        }
        if SFSpeechRecognizer.authorizationStatus() != .authorized {
            return .limited
        }
        if temporaryFallbackInputDeviceID != nil {
            return .limited
        }
        if selectedInputDeviceID != 0,
           !availableInputDevices.contains(where: { $0.id == selectedInputDeviceID }) {
            return .warning
        }
        switch playbackLeakState {
        case .none:
            return .normal
        case .suspectedPlaybackLeak:
            return .warning
        case .speechSuppressionActive:
            return .limited
        }
    }

    private func hudContextIcon() -> String {
        specialInputModeHUDIcon() ?? ""
    }

    private func specialInputModeHUDIcon() -> String? {
        if isWeChatAppWideInputModeEnabled(),
           let bundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier {
            return "app-bundle:\(bundleID)"
        }
        guard activeSpecialInputModeProfile() != nil,
              let bundleID = activeSpecialInputModeBundleID() else { return nil }
        return "app-bundle:\(bundleID)"
    }

    private func activeSpecialInputModeBundleID() -> String? {
        return activeSpecialInputModeSnapshot()?.bundleID
    }

    private func activeSpecialInputModeProfile() -> SpecialInputModeProfile? {
        guard activeSpecialInputModeSnapshot() != nil else { return nil }
        return specialInputModeProfile
    }

    private func isWeChatAppWideInputModeEnabled() -> Bool {
        guard recognitionControlMode == .auto,
              let frontmostApp = NSWorkspace.shared.frontmostApplication else {
            return false
        }
        return isRecentClickFallbackTypingAppBundle(frontmostApp.bundleIdentifier)
    }

    private func isWeChatSpecialModeActive() -> Bool {
        isWeChatAppWideInputModeEnabled() || activeSpecialInputModeProfile() == .weChatChat
    }

    private func specialInputModeProfile(for snapshot: FocusedInputSnapshot) -> SpecialInputModeProfile? {
        guard snapshot.source == .recentClickFallback else { return nil }
        if isRecentClickFallbackTypingAppBundle(snapshot.bundleID) {
            return .weChatChat
        }
        return nil
    }

    private func armSpecialInputMode(from snapshot: FocusedInputSnapshot, hold: TimeInterval = 4.0) {
        guard let profile = specialInputModeProfile(for: snapshot) else { return }
        specialInputModeProfile = profile
        specialInputModePID = snapshot.pid
        specialInputModeBundleID = snapshot.bundleID
        specialInputModeWindowTitle = snapshot.windowTitle
        specialInputModeAnchorPoint = snapshot.anchorPoint
        specialInputModeUntil = Date().addingTimeInterval(hold)
    }

    private func clearSpecialInputMode(reason: String) {
        guard specialInputModeUntil != .distantPast || specialInputModeBundleID != nil else { return }
        GlobalLogger.speech.info("[TypingMode] cleared special input mode reason=\(reason) bundle=\(specialInputModeBundleID ?? "nil")")
        specialInputModeProfile = nil
        specialInputModePID = nil
        specialInputModeBundleID = nil
        specialInputModeWindowTitle = nil
        specialInputModeAnchorPoint = nil
        specialInputModeUntil = .distantPast
    }

    private func activeSpecialInputModeSnapshot() -> FocusedInputSnapshot? {
        guard let bundleID = specialInputModeBundleID,
              Date() < specialInputModeUntil else {
            clearSpecialInputMode(reason: "expired")
            return nil
        }
        guard let frontmostApp = NSWorkspace.shared.frontmostApplication,
              frontmostApp.bundleIdentifier == bundleID else {
            clearSpecialInputMode(reason: "frontmost-changed")
            return nil
        }
        return FocusedInputSnapshot(
            pid: frontmostApp.processIdentifier,
            bundleID: bundleID,
            elementFingerprint: nil,
            source: .recentClickFallback,
            windowTitle: specialInputModeWindowTitle,
            anchorPoint: specialInputModeAnchorPoint
        )
    }

    private func isSpecialInputModeActive() -> Bool {
        activeSpecialInputModeSnapshot() != nil
    }

    private func syncHeadsetChangeAnnouncementBaseline() {
        lastAnnouncedHUDInputIcon = currentInputDeviceIcon
        lastAnnouncedHeadsetLikeInput = isHeadsetLikeInputDevice
        lastAnnouncedAirPodSide = AirPodsDetector.shared.currentSide()
        lastAnnouncedInputDeviceName = currentResolvedInputDeviceName
    }

    private func maybeRevealHUDForHeadsetChange() {
        let icon = currentInputDeviceIcon
        let isHeadsetLike = isHeadsetLikeInputDevice
        let side = AirPodsDetector.shared.currentSide()
        let deviceName = currentResolvedInputDeviceName

        guard let previousIcon = lastAnnouncedHUDInputIcon,
              let previousHeadsetLike = lastAnnouncedHeadsetLikeInput,
              let previousSide = lastAnnouncedAirPodSide else {
            lastAnnouncedHUDInputIcon = icon
            lastAnnouncedHeadsetLikeInput = isHeadsetLike
            lastAnnouncedAirPodSide = side
            lastAnnouncedInputDeviceName = deviceName
            return
        }

        let previousName = lastAnnouncedInputDeviceName ?? ""
        lastAnnouncedHUDInputIcon = icon
        lastAnnouncedHeadsetLikeInput = isHeadsetLike
        lastAnnouncedAirPodSide = side
        lastAnnouncedInputDeviceName = deviceName

        let headsetStateChanged = previousHeadsetLike != isHeadsetLike
        let headsetDeviceChanged = isHeadsetLike && (previousIcon != icon || previousName != deviceName)
        let airPodsSideChanged = isHeadsetLike && previousSide != side && (previousSide != .none || side != .none)
        guard headsetStateChanged || headsetDeviceChanged || airPodsSideChanged else { return }

        let hud = HUDManager.shared
        guard hud.state.mode == .hidden || hud.state.mode == .standby else { return }

        let message: String
        if !previousHeadsetLike && isHeadsetLike {
            message = AppLocalization.isChinese
                ? "耳机已连接"
                : "Headset connected"
        } else if previousHeadsetLike && !isHeadsetLike {
            message = AppLocalization.isChinese
                ? "耳机已断开"
                : "Headset disconnected"
        } else if airPodsSideChanged {
            let sideLabel: String = switch side {
            case .left:
                AppLocalization.isChinese ? "左耳" : "Left"
            case .right:
                AppLocalization.isChinese ? "右耳" : "Right"
            case .both:
                AppLocalization.isChinese ? "双耳" : "Both"
            case .none:
                AppLocalization.isChinese ? "耳机" : "Headset"
            }
            message = sideLabel
        } else {
            message = AppLocalization.isChinese
                ? (isHeadsetLike ? "已切到耳机" : "已切到麦克风")
                : (isHeadsetLike ? "Switched to headset" : "Switched to mic")
        }
        hud.showTemporary(
            message: message,
            language: activeLocale.identifier,
            recognitionControlMode: hudRecognitionControlMode,
            icon: icon,
            duration: 1.2
        )
    }

    private func normalizeAirPodsSymbolName(_ raw: String) -> String {
        switch raw {
        case "airpodspro":
            return "airpods.pro"
        case "airpodsmax":
            return "airpods.max"
        default:
            return raw
        }
    }

    // MARK: - Init
    init() {
        self.dictationHandler = DictationHandler(injector: injector)
        if let provider = OpenAICompatibleProvider.makeFromEnvironment() {
            let resolved = LLMProviderConfiguration.openAICompatible(provider.resolvedConfig)
            self.dictationLLMProviderConfig = resolved
            self.rewriteLLMProviderConfig = resolved
            self.dictationLLMServiceSource = .openAICompatible
            self.rewriteLLMServiceSource = .openAICompatible
        }
        headsetInputMuteRouter.deactivate()
        self.dictationHandler.onStatusUpdate = { [weak self] _ in
            guard let self else { return }
            DispatchQueue.main.async {
                self.refreshContinuousHUD(isDictating: self.isDictating)
            }
        }
        GlobalLogger.lifecycle.info("SpeechManager Initialized")
        refreshInputDevices()
        syncHeadsetChangeAnnouncementBaseline()
        DispatchQueue.main.async { [weak self] in self?.refreshContinuousHUD() }
        _ = AirPodsDetector.shared.currentSide()
        NotificationCenter.default.addObserver(self, selector: #selector(pttDown), name: HeadMotionManager.pttDownNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(pttUp), name: HeadMotionManager.pttUpNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(toggleLanguage), name: Notification.Name("AetherToggleLanguage"), object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleAirPodsChange), name: .AirPodsStateChanged, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleRecognitionControlModeChanged(_:)), name: HeadMotionManager.recognitionControlModeChangedNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleExplicitNonInputClick(_:)), name: HUDManager.typingContextSuppressedByNonInputClickNotification, object: nil)
        NSWorkspace.shared.notificationCenter
            .publisher(for: NSWorkspace.didActivateApplicationNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.handleFrontmostApplicationChanged()
            }
            .store(in: &cancellables)
        refreshLocale()
        hasCompletedInitialLocaleSetup = true
        DispatchQueue.main.async { [weak self] in self?.syncRecognitionState() }
        setupAudioDeviceListeners()

        // Wire sub-module callbacks
        audioCapture.onBuffer = { [weak self] buffer in
            guard let self else { return }
            if !self.recognitionSession.isRunning {
                let now = Date()
                let inRestartGrace = now < self.routeRebuildGraceUntil
                    || now < self.continuousRecoveryGraceUntil
                    || now < self.recognitionStartupGraceUntil
                if !inRestartGrace, now.timeIntervalSince(self.lastRecognitionBufferWithoutSessionAt) >= 0.5 {
                    self.lastRecognitionBufferWithoutSessionAt = now
                    GlobalLogger.speech.info(
                        "[ASR Session] buffer arrived while recognition inactive alwaysListening=\(self.isAlwaysListeningEnabled) audioRunning=\(self.audioCapture.isRunning) selectedInputID=\(self.selectedInputDeviceID) effectiveInputID=\(self.effectiveCaptureInputDeviceID())"
                    )
                }
                if !inRestartGrace,
                   self.isAlwaysListeningEnabled,
                   now >= self.continuousRecoveryGraceUntil,
                   self.pendingEngineRestartWorkItem == nil {
                    self.scheduleContinuousRecovery(delay: 0.05)
                }
            }
            self.recognitionSession.append(buffer)
        }
        audioCapture.onVoiceActivityChanged = { [weak self] active, rms in
            guard let self else { return }
            let previousActive = self.latestVoiceActivity
            self.latestVoiceActivity = active
            self.latestVoiceRMS = rms
            let now = Date()
            self.appendAudioEnergyObservation(active: active, rms: rms, at: now)
            if active != previousActive {
                self.logVoiceActivityTransition(active: active, rms: rms, at: now)
            }
            if active, !self.didRecordFirstPartialForSession {
                self.noteVoiceActivityWithoutPartial(at: now, rms: rms)
            } else if !active {
                self.voiceActivityWithoutPartialSince = nil
            }
            let observations = self.recentAudioEnergyObservations()
            let closeSpeechLikely = self.isCloseSpeechLikely(in: observations)
            if closeSpeechLikely {
                self.startupDetectedUsableAudioForSession = true
                self.cancelStartupInputHealthProbe()
            }
            if self.isPlaybackLeakRiskEnvironment,
               !self.didRecordFirstPartialForSession,
               self.audioCapture.isRunning,
               self.recognitionSession.isRunning,
               !self.isStopping,
               self.isStablePlaybackLeakLikely(in: observations) {
                self.applySpeechProcessingProfile(.speechCommand, reason: "playback-leak-suspected")
                if !self.startupPlaybackLeakHintShownForSession {
                    self.startupPlaybackLeakHintShownForSession = true
                    self.setPlaybackLeakState(.suspectedPlaybackLeak)
                    HUDManager.shared.showTemporary(
                        message: String(localized: "speech.playback_leak.detected"),
                        icon: self.hudInputIcon(),
                        duration: 1.6
                    )
                }
            } else if closeSpeechLikely {
                self.refreshPlaybackLeakStateForCurrentSession()
            }
            self.eosDetector.noteVoiceActivity(active)
            if active {
                self.refreshPendingWakeFollowUpActivity(reason: "voice-activity", at: now)
            }
        }
        eosDetector.endOfSpeechDeferralMsProvider = { [weak self] in
            self?.chineseDictationEOSDeferralMs()
        }
        eosDetector.onEndOfSpeech = { [weak self] in self?.handleEOS() }
        eosDetector.onSegmentTimeout = { [weak self] in self?.handleSegmentTimeout() }
        recognitionSession.onPartial = { [weak self] text in self?.handlePartial(text) }
        recognitionSession.onFinal = { [weak self] text in self?.handleFinalResult(text) }
        recognitionSession.onError = { [weak self] error, isRecoverable in self?.handleRecognitionError(error, isRecoverable: isRecoverable) }
        commandHandler.onIntent = { [weak self] intent in self?.onIntent?(intent, nil, nil, nil, nil, nil, nil, nil) }

        HeadMotionManager.shared.$isLookingAtScreen.removeDuplicates().receive(on: DispatchQueue.main).sink { [weak self] isLooking in
            if isLooking && HeadMotionManager.shared.isTracking && self?.isGazeWakeEnabled == true {
                self?.playWakeSound(reason: "look-at-screen")
            }
        }.store(in: &cancellables)

        Timer.publish(every: 0.15, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self else { return }
                let availability = self.currentVoiceFeatureAvailability()
                guard availability.dictationEnabled || availability.commandEnabled else { return }
                HeadMotionManager.shared.refreshTransientRecognitionControlModeIfNeeded(source: "speech-hud-poll")
                self.refreshContinuousHUD(isDictating: self.isDictating)
            }
            .store(in: &cancellables)
    }

    @objc private func handleAirPodsChange(_ note: Notification) {
        let side = (note.object as? AirPodSide) ?? AirPodsDetector.shared.currentSide()
        refreshContinuousHUD()
        maybeRevealHUDForHeadsetChange()

        let effectiveInputID = effectiveCaptureInputDeviceID()
        let effectiveInputName = audioDeviceName(effectiveInputID)
        GlobalLogger.speech.info(
            "[AudioRoute] AirPods side changed side=\(side.rawValue) selectedInputID=\(selectedInputDeviceID) effectiveInputID=\(effectiveInputID) effectiveInputName=\(effectiveInputName)"
        )
        
    }

    @objc private func handleRecognitionControlModeChanged(_ note: Notification) {
        let source = note.userInfo?["source"] as? String ?? "unknown"
        noteHandsFreeHUDActivity()
        resetTypingStateCache()
        if recognitionControlMode != .auto {
            endTypingRecoveryHold(reason: "mode-changed-\(recognitionControlMode.rawValue)")
        }
        let nextTypingMode: Bool
        switch recognitionControlMode {
        case .command:
            nextTypingMode = false
            dictationHandler.reset(targetPID: nil)
        case .dictation:
            nextTypingMode = true
        case .auto:
            nextTypingMode = isTypingMode
        }

        // Dictation UI mode should track active capture state, not just a persisted mode preference.
        let isCaptureActive = recognitionSession.isRunning || isStopping
        isDictating = isCaptureActive && nextTypingMode
        setAuthoritativeSessionTyping(nextTypingMode, source: "speech.mode-changed")

        // Avoid overriding manual mode-switch toasts when there is no active voice HUD lifecycle.
        let shouldRefreshHUD = isAlwaysListeningEnabled || isWakeWordEnabled || isCaptureActive
        GlobalLogger.speech.info(
            "[ModeSync] source=\(source) effective=\(recognitionControlMode.rawValue) sessionTyping=\(sessionTypingMode) captureActive=\(isCaptureActive) shouldRefreshHUD=\(shouldRefreshHUD)"
        )
        syncInputControlState(source: "speech.mode-changed")
        if shouldRefreshHUD {
            refreshContinuousHUD(isDictating: isDictating)
        }
    }

    @objc private func handleExplicitNonInputClick(_ note: Notification) {
        let clickedBundleID = note.userInfo?["bundleID"] as? String
        let frontmostBundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        if let clickedBundleID,
           let frontmostBundleID,
           clickedBundleID != frontmostBundleID {
            return
        }
        guard recognitionControlMode == .auto else { return }
        guard !isUtteranceActive else { return }

        let hadTypingState =
            sessionTypingMode
            || isDictating
            || isTypingRecoveryHoldActive
            || !dictationHandler.screenTypedText.isEmpty
        let hadLockedTarget =
            sessionTargetPID != nil
            || sessionTargetBundleID != nil
            || sessionTargetElementFingerprint != nil
        guard hadTypingState || hadLockedTarget else { return }

        resetTypingStateCache()
        endTypingRecoveryHold(reason: "mouse-noninput")
        isDictating = false
        dictationHandler.reset(targetPID: nil)
        clearSessionInputTarget(reason: "mouse-noninput")
        clearRecentWakeFollowUpDictationSuppression(reason: "mouse-noninput")
        GlobalLogger.speech.info(
            "[TypingMode] cleared session after explicit non-input click frontBundle=\(frontmostBundleID ?? "nil")"
        )
        setAuthoritativeSessionTyping(false, source: "speech.mouse-noninput")
        refreshContinuousHUD(isDictating: false)
    }

    // MARK: - Locale
    private func normalizedSupportedLocaleIdentifier(_ raw: String) -> String {
        let candidate = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if supportedSpeechLocaleIdentifiers.contains(candidate) {
            return candidate
        }
        if candidate.hasPrefix("zh") { return "zh-CN" }
        if candidate.hasPrefix("ja") { return "ja-JP" }
        if candidate.hasPrefix("ko") { return "ko-KR" }
        if candidate.hasPrefix("fr") { return "fr-FR" }
        if candidate.hasPrefix("de") { return "de-DE" }
        if candidate.hasPrefix("es") { return "es-ES" }
        return "en-US"
    }

    private func defaultSecondaryLocaleIdentifier(for primary: String) -> String {
        let fallback = primary == "en-US" ? "zh-CN" : "en-US"
        if fallback != primary { return fallback }
        return supportedSpeechLocaleIdentifiers.first(where: { $0 != primary }) ?? "en-US"
    }

    private func localeDisplayName(for identifier: String) -> String {
        switch identifier {
        case "zh-CN": return "中文 (简体)"
        case "en-US": return "English (US)"
        case "ja-JP": return "日本語"
        case "ko-KR": return "한국어"
        case "fr-FR": return "Français"
        case "de-DE": return "Deutsch"
        case "es-ES": return "Español"
        default:
            return Locale.current.localizedString(forIdentifier: identifier) ?? identifier
        }
    }

    private func refreshLocale() {
        let resolvedPrimary: String
        if speechLanguageMode == .single, followsSystemLanguage {
            resolvedPrimary = normalizedSupportedLocaleIdentifier(Locale.current.identifier)
        } else {
            resolvedPrimary = primaryLocaleIdentifier
        }
        activeLocale = Locale(identifier: resolvedPrimary)
        if !resolvedPrimary.starts(with: "en") {
            lastNonEnglishLocaleIdentifier = resolvedPrimary
        }
        os_log(
            "Locale refreshed: mode=%{public}@ primary=%{public}@ secondary=%{public}@ effective=%{public}@",
            log: log,
            type: .info,
            speechLanguageMode.rawValue,
            primaryLocaleIdentifier,
            secondaryLocaleIdentifier,
            activeLocale.identifier
        )
    }

    @objc func toggleLanguage() {
        if speechLanguageMode != .bilingual {
            let hud = HUDManager.shared
            hud.showTemporary(
                message: String(localized: "speech.bilingual_switch_unsupported"),
                language: activeLocale.identifier,
                recognitionControlMode: hudRecognitionControlMode,
                icon: hudInputIcon(),
            )
            hud.showTemporaryLanguageIndicator()
            return
        }
        let previousPrimary = primaryLocaleIdentifier
        let previousSecondary = secondaryLocaleIdentifier
        UserDefaults.standard.set(previousSecondary, forKey: speechPrimaryLocaleStorageKey)
        UserDefaults.standard.set(previousPrimary, forKey: speechSecondaryLocaleStorageKey)
        UserDefaults.standard.set(false, forKey: speechFollowsSystemStorageKey)
        UserDefaults.standard.set(previousSecondary, forKey: speechLocaleStorageKey)
        refreshLocale()
        status = activeLocale.identifier.starts(with: "zh")
            ? "双语主语言：\(localeDisplayName(for: previousSecondary))"
            : "Primary language: \(localeDisplayName(for: previousSecondary))"
        let hud = HUDManager.shared
        hud.update(
            mode: hud.state.mode,
            message: hud.state.message,
            language: activeLocale.identifier,
            recognitionControlMode: hudRecognitionControlMode,
            inputDeviceIcon: hudInputIcon(),
            inputDeviceHealth: hudInputHealth(),
            contextIcon: hudContextIcon()
        )
        if recognitionSession.isRunning {
            stopAndFinalize()
            startOnce()
        }
    }

    // MARK: - Permissions
    func requestPermissions() {
        NSApp.unhide(nil)
        NSRunningApplication.current.activate(options: [.activateAllWindows])
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            SFSpeechRecognizer.requestAuthorization { [weak self] auth in
                DispatchQueue.main.async {
                    guard let self else { return }
                    switch auth {
                    case .authorized: self.status = "Speech Authorized"
                    case .denied: self.status = "Speech Denied"
                    case .restricted: self.status = "Speech Restricted"
                    case .notDetermined: self.status = "Speech Not Determined"
                    @unknown default: self.status = "Speech Unknown"
                    }
                }
            }
            AVCaptureDevice.requestAccess(for: .audio) { _ in }
        }
    }

    private func missingVoicePermissionHint() -> (message: String, health: HUDInputDeviceHealth)? {
        if AVCaptureDevice.authorizationStatus(for: .audio) != .authorized {
            return (NSLocalizedString("speech.need_mic_permission", comment: ""), .error)
        }
        if SFSpeechRecognizer.authorizationStatus() != .authorized {
            return (NSLocalizedString("speech.need_recognition_permission", comment: ""), .limited)
        }
        return nil
    }

    private func setStatus(_ key: String) { self.status = NSLocalizedString(key, comment: "") }

    private func noteHandsFreeHUDActivity(at date: Date = Date()) {
        guard isAlwaysListeningEnabled, isDirectCommandEnabled else { return }
        lastHandsFreeHUDActivityAt = date
    }

    private func armSpeechExitBarsHold(at date: Date = Date()) {
        speechExitBarsHoldUntil = date.addingTimeInterval(speechExitBarsHoldDuration)
    }

    private func cancelSpeechExitBarsHold() {
        speechExitBarsHoldUntil = .distantPast
    }

    private func isSpeechExitBarsHoldActive(at date: Date = Date()) -> Bool {
        date < speechExitBarsHoldUntil
    }

    private func updateSpeechHUDTextVisibility(_ visible: Bool, at date: Date, armHold: Bool = true) {
        if visible {
            speechHUDTextVisible = true
            cancelSpeechExitBarsHold()
            return
        }
        if !armHold {
            cancelSpeechExitBarsHold()
        }
        if armHold && speechHUDTextVisible {
            armSpeechExitBarsHold(at: date)
        }
        speechHUDTextVisible = false
    }

    private func shouldSuppressSpeechExitBarsForCompletedDictation(
        featureAvailability: VoiceFeatureAvailability,
        controlMode: HUDRecognitionControlMode,
        isContinuousActive: Bool,
        isSessionActive: Bool
    ) -> Bool {
        guard speechHUDTextVisible else { return false }
        guard !isContinuousActive else { return false }
        guard !isSessionActive else { return false }
        guard !dictationHandler.isInputMutationActive else { return false }
        guard lastTranscript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }

        switch controlMode {
        case .dictation:
            return true
        case .auto:
            return featureAvailability.dictationEnabled && !featureAvailability.commandEnabled
        case .command:
            return false
        }
    }

    private var shouldCollapseHandsFreeHUDToStandby: Bool {
        guard isAlwaysListeningEnabled, isDirectCommandEnabled, !isWakeWordEnabled else { return false }
        guard !isStopping, !isDictating, !isUtteranceActive else { return false }
        guard lastTranscript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        guard lastChangeAt == nil else { return false }
        return Date().timeIntervalSince(lastHandsFreeHUDActivityAt) >= handsFreeHUDCollapseDelay
    }

    private func bundleIsSiriVoiceHost(_ bundleID: String?) -> Bool {
        guard let bundleID = bundleID?.lowercased() else { return false }
        return bundleID.contains("apple.siri")
            || bundleID == "com.apple.siri"
            || bundleID == "com.apple.siri.launcher"
            || bundleID == "com.apple.notificationcenterui"
    }

    // MARK: - State Sync
    func setIdlePauseSuspended(_ suspended: Bool) {
        guard suspended != isIdlePauseSuspended else { return }
        isIdlePauseSuspended = suspended
        pendingWakeFollowUp?.timeoutWorkItem?.cancel()
        pendingWakeFollowUp = nil
        lastWakeTime = nil
        clearHUDOverride()
        clearUnarmedWakePreview()
        GlobalLogger.speech.info(
            "[IdlePause] speech runtime suspended=\(suspended) alwaysListening=\(isAlwaysListeningEnabled) wakeWord=\(isWakeWordEnabled) directCommand=\(isDirectCommandEnabled) ptt=\(isPTTEnabled)"
        )
        if suspended {
            continuousTimer?.invalidate()
            continuousTimer = nil
            isContinuousDictationWaitingForInputFocus = false
            stopMicProgressUI(keepVisible: false)
            stopAndFinalize(discardTranscript: true)
            stopAudioCapture()
            HUDManager.shared.hide()
            return
        }
        syncRecognitionState()
        refreshContinuousHUD(isDictating: false)
    }

    private func syncRecognitionState() {
        if isIdlePauseSuspended {
            stopMicProgressUI(keepVisible: false)
            resetHUDTransientState()
            stopAndFinalize(discardTranscript: true)
            stopAudioCapture()
            HUDManager.shared.hide()
            return
        }
        let anyActive = isAlwaysListeningEnabled || isWakeWordEnabled || isPTTEnabled
        if !anyActive {
            resetHUDTransientState(); stopAndFinalize(); stopAudioCapture(); HUDManager.shared.hide()
        } else {
            if isAlwaysListeningEnabled || isWakeWordEnabled {
                if missingVoicePermissionHint() != nil { stopAndFinalize(); stopAudioCapture(); refreshContinuousHUD() }
                else { startContinuous() }
            } else {
                resetHUDTransientState()
                if isPTTHeld {
                    refreshContinuousHUD()
                } else {
                    stopAndFinalize(discardTranscript: true)
                    stopAudioCapture()
                    HUDManager.shared.hide()
                }
            }
        }
    }

    // MARK: - Core Session Lifecycle

    func startOnce() {
        if isIdlePauseSuspended {
            GlobalLogger.speech.info("[IdlePause] skip startOnce while speech runtime suspended")
            return
        }
        let now = Date()
        if now < noSpeechRecoveryUntil {
            return
        }
        if now < recognitionUnavailableUntil {
            let remaining = recognitionUnavailableUntil.timeIntervalSince(now)
            if remaining > 0.05 {
                GlobalLogger.speech.info(
                    "[ASR Session] defer startOnce while recognizer unavailable remaining=\(String(format: "%.2f", remaining)) selectedInputID=\(selectedInputDeviceID) effectiveInputID=\(effectiveCaptureInputDeviceID())"
                )
                return
            }
        }
        if now < nextAllowedStartOnceAt {
            GlobalLogger.speech.info(
                "[ASR Session] skip duplicate startOnce remaining=\(String(format: "%.2f", nextAllowedStartOnceAt.timeIntervalSince(now)))"
            )
            return
        }
        nextAllowedStartOnceAt = now.addingTimeInterval(0.18)
        routeRebuildGraceUntil = .distantPast
        recognitionStartupGraceUntil = now.addingTimeInterval(1.1)
        continuousRecoveryWorkItem?.cancel()
        continuousRecoveryWorkItem = nil
        cancelStartupInputHealthProbe()
        startupDetectedUsableAudioForSession = false
        startupFallbackAttemptedForSession = false
        startupPlaybackLeakHintShownForSession = false
        audioEnergyObservations.removeAll()
        setPlaybackLeakState(.none)
        cancelDeferredAudioStop()
        clearPendingFinalizeState()
        isStopping = false
        activeUtteranceID = 0
        setCurrentUtteranceArbitration(.init(state: .pending), source: "speech.start-once")
        resetTypingStateCache()

        stopTimer?.invalidate(); stopTimer = nil
        recognitionSession.cancel()

        if let hint = missingVoicePermissionHint() {
            setHUDOverride(
                mode: .feedback,
                message: hint.message,
                icon: hudInputIcon(),
                inputDeviceHealth: hint.health,
                duration: nil
            )
            refreshContinuousHUD(); return
        }

        let featureAvailability = currentVoiceFeatureAvailability()
        let focusedTypingEvidence = focusedTypingHUDEvidence()
        if featureAvailability.dictationEnabled,
           !featureAvailability.commandEnabled,
           !focusedTypingEvidence {
            isContinuousDictationWaitingForInputFocus = isAlwaysListeningEnabled
            clearHUDOverride()
            refreshContinuousHUD(isDictating: false)
            return
        }
        isContinuousDictationWaitingForInputFocus = false

        let predictedTypingMode: Bool = {
            if isWakeWordEnabled && !isAwake && !isDirectCommandEnabled { return false }
            return isTypingMode
        }()
        applySpeechProcessingProfile(
            desiredSpeechProcessingProfile(forTypingMode: predictedTypingMode),
            reason: "session-start"
        )

        // Start audio capture
        refreshHeadsetVoiceProcessingPolicy()
        let selectedInputID = selectedInputDeviceID
        let effectiveInputID = effectiveCaptureInputDeviceID()
        audioCapture.selectedDeviceID = effectiveInputID
        audioCapture.voiceProcessingProfile = currentSpeechProcessingProfile.audioProfile
        // AirPods / bluetooth headsets behave more like dynamic routes than
        // fixed capture devices. Let the system own those routes; explicit
        // binding has proven to fail with AVFAudio -10868 even when the UI
        // already shows the headset as active.
        audioCapture.preferSystemManagedHeadsetRoute = isHeadsetLikeInputDevice
        GlobalLogger.speech.info(
            "[AudioRoute] startOnce selectedInputID=\(selectedInputID) effectiveInputID=\(effectiveInputID) selectedName=\(availableInputDevices.first(where: { $0.id == selectedInputID })?.name ?? "system-default") effectiveName=\(availableInputDevices.first(where: { $0.id == effectiveInputID })?.name ?? audioDeviceName(effectiveInputID)) preferSystemManagedHeadsetRoute=\(audioCapture.preferSystemManagedHeadsetRoute)"
        )
        do { try audioCapture.start() } catch {
            let backoff = min(1.0 + (Double(consecutiveRecognitionUnavailableCount) * 0.35), 3.0)
            recognitionUnavailableUntil = Date().addingTimeInterval(backoff)
            GlobalLogger.speech.info(
                "[AudioCapture] start failed error=\(error.localizedDescription) selectedInputID=\(selectedInputID) effectiveInputID=\(effectiveInputID) retryIn=\(String(format: "%.2f", backoff))"
            )
            status = NSLocalizedString("speech.error", comment: ""); lastError = error.localizedDescription
            if isAlwaysListeningEnabled { refreshContinuousHUD(); scheduleContinuousRecovery(delay: backoff) }
            else { showPTTUnavailableHUD() }
            return
        }

        sessionGeneration += 1
        let gen = sessionGeneration
        sessionStartedAt = Date()
        didRecordFirstPartialForSession = false
        voiceActivityWithoutPartialSince = nil
        lastVoiceWithoutPartialDiagnosticAt = .distantPast
        lastVoiceWithoutPartialRecoveryAt = .distantPast
        lastAdaptiveTextCount = 0
        lastAdaptiveSampleAt = .distantPast
        metrics.sessions += 1
        lockSessionInputTarget()
        dictationHandler.reset(targetPID: preferredTypingInjectionTargetPID(sessionTargetPID, bundleID: sessionTargetBundleID))
        dictationHandler.llmProvider = contextualLLMProvider(
            for: .dictationEnhancement,
            bundleIDs: currentContextBundleIDs()
        )
        dictationHandler.llmProviderContext = llmProviderDiagnosticsContext(for: .dictationEnhancement)
        dictationHandler.isLLMEnhancementEnabled = isAutoDictationEnhancementEnabled

        let initialTypingMode: Bool
        if isWakeWordEnabled && !isAwake && !isDirectCommandEnabled { initialTypingMode = false }
        else { initialTypingMode = isTypingMode }
        isDictating = initialTypingMode
        setAuthoritativeSessionTyping(initialTypingMode, source: "speech.session-start")
        let finalProfile = desiredSpeechProcessingProfile(forTypingMode: initialTypingMode)
        if finalProfile != currentSpeechProcessingProfile {
            applySpeechProcessingProfile(finalProfile, reason: "session-mode-finalized")
        }

        // Start recognition
        do {
            let contextual = buildDynamicContextualStrings()
            let taskHint = recognitionTaskHint()
            let preferOnDevice = shouldPreferOnDeviceRecognition()
            let prebuffered = audioCapture.drainRingBuffer()
            try recognitionSession.start(
                locale: activeLocale,
                autoPunctuation: isAutoPunctuationEnabled,
                contextualStrings: contextual,
                prebuffered: prebuffered,
                taskHint: taskHint,
                preferOnDevice: preferOnDevice
            )
            let selectedDeviceName = availableInputDevices.first(where: { $0.id == effectiveCaptureInputDeviceID() })?.name ?? "system-default"
            GlobalLogger.speech.info(
                "[ASR Session] start locale=\(activeLocale.identifier) mode=\(recognitionControlMode.rawValue) taskHint=\(String(describing: taskHint)) preferOnDevice=\(preferOnDevice) selectedInputID=\(selectedInputDeviceID) effectiveInputID=\(effectiveCaptureInputDeviceID()) selectedInputName=\(selectedDeviceName) autoPunctuation=\(isAutoPunctuationEnabled) contextualCount=\(contextual.count) prebuffered=\(prebuffered.count)"
            )
            // Headset button / system microphone-control interception is disabled.
            // Keep the router torn down so AirPods presses stay owned by the system.
            headsetInputMuteRouter.deactivate()
            consecutiveRecognitionUnavailableCount = 0
            recognitionUnavailableUntil = .distantPast
            scheduleStartupInputHealthProbe(for: gen)
        } catch {
            let backoff = min(0.8 + (Double(consecutiveRecognitionUnavailableCount) * 0.45), 3.5)
            consecutiveRecognitionUnavailableCount += 1
            recognitionUnavailableUntil = Date().addingTimeInterval(backoff)
            let backoffText = String(format: "%.2f", backoff)
            GlobalLogger.speech.info(
                "[ASR Session] failed to start error=\(error.localizedDescription) selectedInputID=\(selectedInputDeviceID) effectiveInputID=\(effectiveCaptureInputDeviceID()) headsetLike=\(isHeadsetLikeInputDevice) retryIn=\(backoffText)"
            )
            status = NSLocalizedString("speech.unavailable", comment: ""); lastError = "Speech recognizer unavailable"; return
        }

        // Start EOS detection
        configureEOSParameters(
            for: currentVoiceFeatureAvailability(),
            sessionTypingMode: sessionTypingMode
        )
        eosDetector.start()

        lastTranscript = ""; lastError = ""
        status = NSLocalizedString("speech.listening", comment: "")
        noteHandsFreeHUDActivity()
        let limits = resolvedSessionHardLimits(
            for: currentSessionSpeechStyle(
                for: currentVoiceFeatureAvailability(),
                sessionTypingModeOverride: sessionTypingMode
            )
        )
        startMicProgressUI(durationSec: limits.maxSegmentSec, generation: gen)
        refreshContinuousHUD(isDictating: isDictating)
    }

    // MARK: - Recognition Callbacks

    private func handlePartial(_ rawText: String) {
        guard sessionGeneration > 0 else { return }
        let originalRawText = rawText
        var text = rawText
        var wakeWordDetected = false
        var wakeScore: Double = 0
        var matchedWakePhrase: String?

        // Wake word detection & stripping
        if isWakeWordEnabled && !isDirectCommandEnabled {
            logWakeWordConfigurationIfNeeded(reason: "partial")
            let matchMode = Self.wakeMatchMode(
                isWakeWordEnabled: isWakeWordEnabled,
                isDirectCommandEnabled: isDirectCommandEnabled,
                isAlwaysListeningEnabled: isAlwaysListeningEnabled,
                isAwake: isAwake
            )
            let result = wakeWordDetector.process(
                text,
                localeIdentifier: activeLocale.identifier,
                matchMode: matchMode
            )
            wakeScore = result.score
            matchedWakePhrase = result.matchedPhrase
            let wakePhraseOccurrence = wakeDiagnosticPhraseOccurrence(
                in: originalRawText,
                localeIdentifier: activeLocale.identifier
            )
            logWakeEvaluationIfNeeded(
                phase: isAwake ? "partial-awake" : "partial-standby",
                rawText: originalRawText,
                matchMode: matchMode,
                wakeDetected: result.wakeDetected,
                wakeScore: wakeScore,
                matchedWakePhrase: matchedWakePhrase,
                payload: result.wakeDetected ? result.payload : nil
            )
            if result.wakeDetected {
                wakeWordDetected = true
                if !isAwake {
                    beginPendingWakeFollowUp(phrase: matchedWakePhrase)
                    handleWakeActivation(
                        reason: "partial-wake-word",
                        rearmReason: (isAlwaysListeningEnabled && isWakeWordEnabled && !isDirectCommandEnabled) ? "wake-word" : nil
                    )
                    text = result.payload
                    if Self.shouldSegmentRecognitionAfterPartialWake(
                        isAlwaysListeningEnabled: isAlwaysListeningEnabled,
                        isWakeWordEnabled: isWakeWordEnabled,
                        isDirectCommandEnabled: isDirectCommandEnabled,
                        wakePayload: text
                    ) {
                        segmentRecognitionAfterWakeWord(reason: "partial-wake-word")
                        return
                    }
                    wakeActivatedDuringCurrentUtterance = true
                } else {
                    text = result.payload
                }
            } else if shouldSegmentRecognitionAfterStandbyWakeMiss(
                rawText: originalRawText,
                wakeScore: wakeScore,
                phraseOccurrence: wakePhraseOccurrence
            ) {
                let missReason: String
                if wakeScore > 0 {
                    missReason = "below-threshold"
                } else if let wakePhraseOccurrence, wakePhraseOccurrence.offset > 0 {
                    missReason = "phrase-not-at-prefix"
                } else if wakePhraseOccurrence != nil {
                    missReason = "prefix-rejected"
                } else {
                    missReason = "diagnosable-miss"
                }
                segmentRecognitionAfterStandbyWakeMiss(
                    reason: missReason,
                    rawText: originalRawText
                )
                return
            }
        }

        text = normalizeRecognizedText(text)
        let featureAvailability = currentVoiceFeatureAvailability()
        let controlMode = effectiveRecognitionControlMode(for: featureAvailability)
        if !originalRawText.isEmpty || !text.isEmpty {
            GlobalLogger.speech.info(
                "[ASR Partial] raw='\(originalRawText)' normalized='\(text)' wakeDetected=\(wakeWordDetected) wakeScore=\(String(format: "%.2f", wakeScore)) wakePhrase=\(matchedWakePhrase ?? "nil") mode=\(controlMode.rawValue) locale=\(activeLocale.identifier)"
            )
        }
        let wakeTypingAllowed = Self.shouldAllowWakeGatedTyping(
            isWakeWordEnabled: isWakeWordEnabled,
            isDirectCommandEnabled: isDirectCommandEnabled,
            isAwake: isAwake,
            wakeWordDetected: wakeWordDetected
        )
        if !wakeTypingAllowed {
            clearUnarmedWakePreview()
            refreshContinuousHUD(isDictating: false)
            return
        }
        let prev = lastTranscript
        let now = Date()
        if text != prev {
            lastTranscript = text; lastChangeAt = now
            if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                startupDetectedUsableAudioForSession = true
                cancelStartupInputHealthProbe()
                noteHandsFreeHUDActivity(at: now)
                if activeUtteranceID == 0 { activeUtteranceID = nextUtteranceID; nextUtteranceID += 1 }
                eosDetector.noteUtteranceStarted()
                eosDetector.noteTranscriptChanged()
                noteFirstPartialIfNeeded(at: now)
                applyAdaptiveEOS(with: text, at: now)
                refreshPendingWakeFollowUpActivity(reason: "partial", at: now)
            }
        }

        let hasPayload = !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if hasPayload && !isUtteranceActive {
            isUtteranceActive = true
            if activeUtteranceID == 0 { activeUtteranceID = nextUtteranceID; nextUtteranceID += 1 }
            if isAlwaysListeningEnabled && isDirectCommandEnabled { rearmInputTarget(reason: "direct-utterance-start") }
        }
        if !hasPayload && isUtteranceActive { isUtteranceActive = false }

        let lockedFocusedSnapshot = currentFocusedInputSnapshot()
        let lockedTargetMatches = hasLockedFocusedInputTarget(lockedFocusedSnapshot)
        let liveTyping = throttledTypingMode()
        let canType = wakeTypingAllowed
        let hasStreamedDictation = !dictationHandler.screenTypedText.isEmpty
        let wakeFollowUpActive = isWakeFollowUpSessionActive || wakeWordDetected
        let computedTypingMode = Self.resolvedUtteranceTypingMode(
            recognitionControlMode: controlMode,
            sessionTypingMode: sessionTypingMode,
            liveTyping: liveTyping,
            canType: canType,
            hasStreamedDictation: hasStreamedDictation
        )
        let hasAuthoritativeTypingEvidence = hasAuthoritativeTypingEvidence()
        let wakePayloadLooksLikeCommand = likelyWakePayloadCommand(text)
        let hasStrongTypingFallback = hasStrongTypingFallbackEvidence(
            lockedFocusedSnapshot: lockedFocusedSnapshot,
            lockedTargetMatches: lockedTargetMatches,
            computedTypingContext: computedTypingMode,
            hasAuthoritativeTypingEvidence: hasAuthoritativeTypingEvidence,
            hasStreamedDictation: hasStreamedDictation
        )
        let wakeArbitration = wakeFollowUpActive
            ? wakeFollowUpArbitrationResult(
                controlMode: controlMode,
                transcript: text,
                routerDecision: commandRouter.routeDetailed(
                    transcript: text,
                    bias: .commandPreferred,
                    localeIdentifier: activeLocale.identifier
                ),
                hasStableTypingEvidence: hasStrongTypingFallback,
                hasLiveTypingEvidence: liveTyping
            )
            : .init(state: .pending)
        setCurrentUtteranceArbitration(wakeArbitration, source: "speech.partial-wake")
        let nextTypingMode = hasStrongTypingFallback
            ? computedTypingMode
            : Self.reconcileTypingContextWithVisibleHUD(
                recognitionControlMode: controlMode,
                computedTypingContext: computedTypingMode
            )
        let effectiveTypingMode = effectiveTypingContext(
            reconciledTypingContext: nextTypingMode,
            computedTypingContext: computedTypingMode,
            availability: featureAvailability
        )
        let restoredWakeTypingMode =
            !effectiveTypingMode
            && shouldUseWakeTypingFallback(
                wakeLifecycleActive: wakeFollowUpActive,
                recognitionControlMode: controlMode,
                featureAvailability: featureAvailability,
                liveTyping: liveTyping
            )
        let preferWakeCommandRouting = Self.shouldPreferWakeCommandRouting(
            recognitionControlMode: controlMode,
            commandEnabled: featureAvailability.commandEnabled,
            wakeLifecycleActive: wakeFollowUpActive,
            wakePayloadLooksLikeCommand: wakePayloadLooksLikeCommand,
            liveTyping: liveTyping
        )
        let promotedInlineWakePayloadTyping =
            !effectiveTypingMode
            && Self.shouldPromoteInlineWakePayloadToTypingContext(
                recognitionControlMode: controlMode,
                dictationEnabled: featureAvailability.dictationEnabled,
                wakeFollowUpActive: wakeFollowUpActive,
                wakePayload: text,
                hasAuthoritativeTypingEvidence: hasAuthoritativeTypingEvidence,
                liveTyping: liveTyping,
                commandLikely: wakePayloadLooksLikeCommand
            )
        let resolvedTypingMode: Bool
        if wakeFollowUpActive {
            resolvedTypingMode = wakeArbitration.state == .dictationCommitted
        } else {
            resolvedTypingMode = preferWakeCommandRouting
                ? false
                : ((restoredWakeTypingMode || promotedInlineWakePayloadTyping) ? true : effectiveTypingMode)
        }
        if restoredWakeTypingMode {
            GlobalLogger.speech.info(
                "[TypingMode] restored wake-follow-up typing fallback targetPID=\(sessionTargetPID ?? 0) targetBundle=\(sessionTargetBundleID ?? "nil") liveTyping=\(liveTyping)"
            )
        }
        if preferWakeCommandRouting && effectiveTypingMode {
            GlobalLogger.speech.info(
                "[TypingMode] prefer wake command routing over sticky typing partial liveTyping=\(liveTyping) transcript='\(wakeDiagnosticSnippet(text))'"
            )
        }
        if promotedInlineWakePayloadTyping {
            GlobalLogger.speech.info(
                "[TypingMode] promoted inline wake payload to typing context liveTyping=\(liveTyping) authoritativeFocus=\(hasAuthoritativeTypingEvidence)"
            )
        }
        if controlMode == .auto,
           sessionTypingMode,
           !nextTypingMode,
           !liveTyping,
            !hasStreamedDictation {
            GlobalLogger.speech.info("[TypingMode] cleared stale auto typing state before routing partials")
        }
        if controlMode == .auto,
           computedTypingMode,
           !nextTypingMode,
           !hasStreamedDictation {
            GlobalLogger.speech.info("[TypingMode] HUD control state overrode stale typing context before partial injection")
        }
        if controlMode == .auto,
           !liveTyping,
           lockedTargetMatches,
           resolvedTypingMode {
            let currentPID = lockedFocusedSnapshot?.pid ?? 0
            let currentBundle = lockedFocusedSnapshot?.bundleID ?? "nil"
            let targetPID = sessionTargetPID ?? 0
            let targetBundle = sessionTargetBundleID ?? "nil"
            GlobalLogger.speech.info(
                "[TypingMode] holding dictation on locked input target liveTyping=false currentPID=\(currentPID) targetPID=\(targetPID) currentBundle=\(currentBundle) targetBundle=\(targetBundle)"
            )
        }
        if controlMode == .auto, sessionTypingMode != resolvedTypingMode {
            let currentPID = lockedFocusedSnapshot?.pid ?? 0
            let currentBundle = lockedFocusedSnapshot?.bundleID ?? "nil"
            let targetPID = sessionTargetPID ?? 0
            let targetBundle = sessionTargetBundleID ?? "nil"
            GlobalLogger.speech.info(
                "[TypingMode] transition \(sessionTypingMode)->\(resolvedTypingMode) liveTyping=\(liveTyping) computed=\(computedTypingMode) reconciled=\(nextTypingMode) hasStreamed=\(hasStreamedDictation) utteranceActive=\(isUtteranceActive) lockedTarget=\(lockedTargetMatches) dictationEnabled=\(featureAvailability.dictationEnabled) commandEnabled=\(featureAvailability.commandEnabled) currentPID=\(currentPID) targetPID=\(targetPID) currentBundle=\(currentBundle) targetBundle=\(targetBundle)"
            )
        }
        if isTypingRecoveryHoldActive, resolvedTypingMode, (liveTyping || lockedTargetMatches) {
            endTypingRecoveryHold(reason: "typing-restored")
        }
        isDictating = resolvedTypingMode && featureAvailability.dictationEnabled
        setAuthoritativeSessionTyping(resolvedTypingMode, source: "speech.partial-routing")
        if controlMode != .command, resolvedTypingMode {
            syncSessionInputTargetFromCurrentFocus(resetDictationStream: dictationHandler.screenTypedText.isEmpty)
        }

        if text.count > 2 && isAwake { lastWakeTime = Date() }
        let shouldDelayHUDRefreshUntilStreamingSync =
            sessionTypingMode && featureAvailability.dictationEnabled && !isStopping

        // Dispatch to handler
        let pendingExplicitCommandPrefix = hasPendingExplicitCommandPrefix()
        if sessionTypingMode && featureAvailability.dictationEnabled {
            if featureAvailability.commandEnabled,
               (pendingExplicitCommandPrefix
                || partialHasExplicitCommandPrefix(text)
                || partialMayBecomeExplicitCommandPrefix(text)) {
                commandHandler.onPartial(text)
            } else if shouldSuppressStreamingDictationAfterRecentSubmit(
                targetPID: preferredTypingInjectionTargetPID(sessionTargetPID, bundleID: sessionTargetBundleID),
                bundleID: sessionTargetBundleID,
                elementFingerprint: sessionTargetElementFingerprint
            ) {
                GlobalLogger.speech.info(
                    "[TextPipeline] skip streaming dictation after submit bundle=\(sessionTargetBundleID ?? "nil") targetPID=\(sessionTargetPID ?? 0) textCount=\(text.count)"
                )
            } else if shouldUsePasteFallbackForCurrentTypingTarget() {
                GlobalLogger.speech.info(
                    "[TextPipeline] skip partial streaming for paste fallback target bundle=\(sessionTargetBundleID ?? "nil")"
                )
            } else {
                // Wake-follow-up dictation still needs live partial injection so the
                // user sees text flow into the target immediately after wake.
                // Final routing already owns diff correction and duplicate suppression.
                dictationHandler.onPartial(text)
            }
        } else if featureAvailability.commandEnabled {
            commandHandler.onPartial(text)
        }

        if shouldDelayHUDRefreshUntilStreamingSync || (sessionTypingMode && featureAvailability.dictationEnabled) {
            refreshContinuousHUD(isDictating: isDictating)
        } else if (!isStopping || isAlwaysListeningEnabled) {
            refreshContinuousHUD(isDictating: isDictating)
        } else if isStopping {
            refreshContinuousHUD()
        }
    }

    private func segmentRecognitionAfterWakeWord(reason: String) {
        guard isAlwaysListeningEnabled,
              isWakeWordEnabled,
              !isDirectCommandEnabled,
              audioCapture.isRunning else {
            return
        }

        resetNoSpeechRecoveryBackoff()
        wakeActivationRecoveryUntil = Date().addingTimeInterval(1.6)
        suppressRecognitionFailuresUntil = Date().addingTimeInterval(1.6)
        suppressRecognitionFailuresReason = "wake-activation-recovery"
        GlobalLogger.speech.info(
            "[WakeWord] segmenting recognition after activation reason=\(reason) session=\(sessionGeneration) utterance=\(activeUtteranceID)"
        )

        finalizationWorkItem?.cancel()
        finalizationWorkItem = nil
        stopTimer?.invalidate()
        stopTimer = nil
        eosDetector.stop()
        recognitionSession.cancel()
        resetUtteranceTrackingForNextPhrase()
        audioCapture.clearRingBuffer()
        nextAllowedStartOnceAt = .distantPast

        DispatchQueue.main.async { [weak self] in
            guard let self,
                  self.isAlwaysListeningEnabled,
                  !self.isStopping else { return }
            self.startOnce()
        }
    }

    private func shouldSegmentRecognitionAfterStandbyWakeMiss(
        rawText: String,
        wakeScore: Double,
        phraseOccurrence: (phrase: String, offset: Int, leadingContext: String)?
    ) -> Bool {
        guard isAlwaysListeningEnabled,
              isWakeWordEnabled,
              !isDirectCommandEnabled,
              !isAwake,
              pendingWakeFollowUp == nil,
              recentExpiredWakeFollowUp == nil else {
            return false
        }
        guard audioCapture.isRunning,
              recognitionSession.isRunning,
              !isStopping else {
            return false
        }
        guard wakeScore > 0 || phraseOccurrence != nil else {
            return false
        }
        let now = Date()
        guard now.timeIntervalSince(lastStandbyWakeMissSegmentationAt) >= standbyWakeMissSegmentationDebounce else {
            return false
        }
        let normalized = wakeDiagnosticNormalizeForMatching(rawText)
        guard normalized.count >= 2 else { return false }
        return true
    }

    private func segmentRecognitionAfterStandbyWakeMiss(reason: String, rawText: String) {
        guard isAlwaysListeningEnabled,
              isWakeWordEnabled,
              !isDirectCommandEnabled,
              audioCapture.isRunning else {
            return
        }

        lastStandbyWakeMissSegmentationAt = Date()
        resetNoSpeechRecoveryBackoff()
        standbyWakeMissRecoveryUntil = Date().addingTimeInterval(1.6)
        suppressRecognitionFailuresUntil = Date().addingTimeInterval(1.6)
        suppressRecognitionFailuresReason = "standby-wake-miss-recovery"
        GlobalLogger.speech.info(
            "[WakeWord] segmenting recognition after standby miss reason=\(reason) session=\(sessionGeneration) utterance=\(activeUtteranceID) transcript='\(wakeDiagnosticSnippet(rawText))'"
        )

        finalizationWorkItem?.cancel()
        finalizationWorkItem = nil
        stopTimer?.invalidate()
        stopTimer = nil
        eosDetector.stop()
        recognitionSession.cancel()
        resetUtteranceTrackingForNextPhrase()
        audioCapture.clearRingBuffer()
        nextAllowedStartOnceAt = .distantPast

        DispatchQueue.main.async { [weak self] in
            guard let self,
                  self.isAlwaysListeningEnabled,
                  !self.isStopping else { return }
            self.startOnce()
        }
    }

    private func handleFinalResult(_ text: String) {
        let normalized = normalizeRecognizedText(text)
        let fallbackTranscript = Self.fallbackTranscriptForUnexpectedEmptyFinal(
            finalTranscript: normalized,
            lastPartialTranscript: lastTranscript
        )
        if !normalized.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            resetNoSpeechRecoveryBackoff()
        }
        os_log("isFinal received: '%{public}@'", log: log, type: .info, text)
        let controlMode = recognitionControlMode
        GlobalLogger.speech.info(
            "[ASR Final] raw='\(text)' normalized='\(normalized)' mode=\(controlMode.rawValue) typing=\(sessionTypingMode) locale=\(activeLocale.identifier)"
        )
        finalizationWorkItem?.cancel(); finalizationWorkItem = nil
        eosDetector.noteUtteranceEnded()
        if isStopping {
            if isAlwaysListeningEnabled {
                completeAlwaysListeningFinalResult(
                    fallbackTranscript ?? text,
                    source: "final-callback"
                )
            } else {
                completeStoppedOneShotFinalResult(fallbackTranscript ?? text)
            }
        } else if Self.shouldCommitCompletedOneShotFinalResult(
            isStopping: isStopping,
            isAlwaysListeningEnabled: isAlwaysListeningEnabled,
            finalTranscript: normalized
        ) {
            handleCompletedOneShotFinalResult(normalized)
        } else if let fallbackTranscript {
            GlobalLogger.speech.info(
                "[ASR Final] empty-final fallback transcript='\(wakeDiagnosticSnippet(fallbackTranscript))'"
            )
            handleTranscript(fallbackTranscript, utteranceID: activeUtteranceID)
            resetUtteranceTrackingForNextPhrase()
            refreshContinuousHUD(isDictating: false)
        }
    }

    private func completeStoppedOneShotFinalResult(_ transcript: String) {
        stopTimer?.invalidate()
        stopTimer = nil

        let finalTranscript = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        if !finalTranscript.isEmpty {
            handleTranscript(finalTranscript, utteranceID: activeUtteranceID)
        }

        resetUtteranceTrackingForNextPhrase()
        isStopping = false
        shouldShowProcessingDotsDuringStop = false
        clearHUDOverride()
        stopMicProgressUI(keepVisible: false)
        stopAudioCapture()
        if activeHUDStageMode != nil {
            refreshContinuousHUD(isDictating: false)
        } else {
            clearHUDStage()
            HUDManager.shared.hide()
        }
    }

    private func clearPendingFinalizeState() {
        pendingFinalizeKeepHUDVisible = false
        pendingFinalizeDiscardTranscript = false
    }

    private func completeAlwaysListeningFinalResult(_ transcript: String, source: String) {
        let discardTranscript = pendingFinalizeDiscardTranscript
        let keepHUDVisible = pendingFinalizeKeepHUDVisible
        let finalTranscript = transcript.trimmingCharacters(in: .whitespacesAndNewlines)

        if discardTranscript {
            resetHUDTransientState()
        } else {
            if !finalTranscript.isEmpty {
                handleTranscript(finalTranscript, utteranceID: activeUtteranceID)
            }
            resetUtteranceTrackingForNextPhrase()
        }

        audioCapture.clearRingBuffer()
        isStopping = false
        shouldShowProcessingDotsDuringStop = false
        clearPendingFinalizeState()

        GlobalLogger.speech.info(
            "[ASR Session] complete always-listening final source=\(source) discardTranscript=\(discardTranscript) keepHUDVisible=\(keepHUDVisible) transcriptEmpty=\(finalTranscript.isEmpty) clearedPrebuffer=true"
        )

        guard !isIdlePauseSuspended else { return }
        refreshContinuousHUD(isDictating: false)
        ensureRecognitionSessionForVisibleHUD(
            reason: keepHUDVisible
                ? "always-listening-final-\(source)-keep-hud"
                : "always-listening-final-\(source)"
        )
    }

    private func handleCompletedOneShotFinalResult(_ transcript: String) {
        let finalTranscript = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !finalTranscript.isEmpty else { return }

        GlobalLogger.speech.info(
            "[ASR Final] committing self-ended one-shot transcript='\(wakeDiagnosticSnippet(finalTranscript))' held=\(isPTTHeld)"
        )

        stopMicProgressUI(keepVisible: isPTTHeld)
        handleTranscript(finalTranscript, utteranceID: activeUtteranceID)
        resetUtteranceTrackingForNextPhrase()

        guard isPTTHeld else {
            stopAudioCapture()
            if activeHUDStageMode != nil {
                refreshContinuousHUD(isDictating: false)
            } else {
                HUDManager.shared.hide()
            }
            return
        }

        refreshContinuousHUD(isDictating: false)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            guard let self,
                  self.isPTTHeld,
                  !self.isStopping,
                  !self.recognitionSession.isRunning,
                  !self.isAlwaysListeningEnabled else { return }
            self.startOnce()
        }
    }

    private func handleRecognitionError(_ error: Error, isRecoverable: Bool) {
        let trimmed = lastTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        let reason = classifyRecognitionFailureReason(error)
        let fallbackTranscript = recoverableNoSpeechFallbackTranscript(
            lastPartialTranscript: trimmed,
            failureReason: reason,
            isRecoverable: isRecoverable
        )
        if let fallbackTranscript {
            GlobalLogger.speech.info(
                "[ASR Error] recoverable-no-speech using partial fallback transcript='\(wakeDiagnosticSnippet(fallbackTranscript))' utterance=\(activeUtteranceID) typing=\(sessionTypingMode)"
            )
            handleTranscript(fallbackTranscript, utteranceID: activeUtteranceID)
            resetUtteranceTrackingForNextPhrase()
            refreshContinuousHUD(isDictating: false)
        }

        let failedTranscript = fallbackTranscript == nil && !trimmed.isEmpty ? trimmed : nil
        let appName = NSWorkspace.shared.frontmostApplication?.localizedName
        let bundleIdentifier = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        let shouldSuppressFailure = fallbackTranscript != nil || (failedTranscript == nil
            && Date() < suppressRecognitionFailuresUntil
            && (reason == "no-speech-detected" || reason == "recognition-interrupted"))
        if shouldSuppressFailure {
            GlobalLogger.speech.info(
                "[RecognitionFailure] suppressed reason=\(reason) suppressReason=\(suppressRecognitionFailuresReason ?? "unknown")"
            )
        } else {
            onRecognitionFailure?(
                failedTranscript,
                reason,
                appName,
                bundleIdentifier
            )
        }

        beginTypingRecoveryHold(reason: isRecoverable ? "recognition-recoverable-error" : "recognition-fatal-error")
        if isRecoverable {
            noteRecoverableHeadsetVoiceProcessingFailure(reason: "recognition-recoverable-error")
            metrics.recoverableErrors += 1
            os_log("Recognition recoverable error: %{public}@", log: log, type: .info, error.localizedDescription)
            let recoveryDelay = recoverableRecognitionRetryDelay(for: reason)
            if isAlwaysListeningEnabled {
                cleanup(); refreshContinuousHUD(); scheduleContinuousRecovery(delay: recoveryDelay)
            } else { stopAndFinalize() }
        } else {
            resetNoSpeechRecoveryBackoff()
            metrics.fatalErrors += 1
            status = NSLocalizedString("speech.error", comment: ""); lastError = error.localizedDescription
            stopAndFinalize(); scheduleContinuousRecovery(delay: 0.4)
        }
        maybeLogRuntimeMetrics(force: false)
    }

    private func classifyRecognitionFailureReason(_ error: Error) -> String {
        let ns = error as NSError
        let lowered = error.localizedDescription.lowercased()

        let isNoSpeech = (ns.domain == "kAFAssistantErrorDomain" && ns.code == 203)
            || lowered.contains("no speech detected")
            || lowered.contains("speech timeout")
            || lowered.contains("timeout")
        if isNoSpeech {
            return "no-speech-detected"
        }

        let isCancelled = ns.code == 10 || ns.code == 216 || ns.code == 1700
            || lowered.contains("canceled")
            || lowered.contains("cancelled")
            || lowered.contains("interrupted")
        if isCancelled {
            return "recognition-interrupted"
        }

        if ns.domain == "kLSRErrorDomain" || lowered.contains("not available") || lowered.contains("unavailable") {
            return "recognition-unavailable"
        }

        return "recognition-failed"
    }

    private func recoverableNoSpeechFallbackTranscript(
        lastPartialTranscript: String,
        failureReason: String,
        isRecoverable: Bool
    ) -> String? {
        let normalizedPartial = normalizeRecognizedText(
            lastPartialTranscript,
            scope: sessionTypingMode ? .dictation : .command
        ).trimmingCharacters(in: .whitespacesAndNewlines)

        if let fallback = Self.fallbackTranscriptForRecoverableNoSpeechError(
            isAlwaysListeningEnabled: isAlwaysListeningEnabled,
            isRecoverable: isRecoverable,
            failureReason: failureReason,
            lastPartialTranscript: normalizedPartial,
            isUtteranceActive: isUtteranceActive
        ) {
            return fallback
        }

        guard isAlwaysListeningEnabled,
              isRecoverable,
              failureReason == "no-speech-detected",
              isUtteranceActive,
              !normalizedPartial.isEmpty else {
            return nil
        }

        let decision = commandRouter.routeDetailed(
            transcript: normalizedPartial,
            bias: .commandPreferred,
            localeIdentifier: activeLocale.identifier
        )
        guard decision.confidence >= .medium, isCommandIntent(decision.intent) else {
            return nil
        }
        return normalizedPartial
    }

    private func recoverableRecognitionRetryDelay(for reason: String) -> TimeInterval {
        let standbyWakeMissRecoveryActive = Date() < standbyWakeMissRecoveryUntil
        let wakeActivationRecoveryActive = Date() < wakeActivationRecoveryUntil
        let resolution = Self.resolvedNoSpeechRecoveryBackoffDelay(
            reason: reason,
            standbyWakeMissRecoveryActive: standbyWakeMissRecoveryActive,
            wakeActivationRecoveryActive: wakeActivationRecoveryActive,
            consecutiveRecoveries: consecutiveNoSpeechRecoveries
        )

        guard reason == "no-speech-detected" else {
            resetNoSpeechRecoveryBackoff()
            return resolution.delay
        }

        if standbyWakeMissRecoveryActive || wakeActivationRecoveryActive {
            consecutiveNoSpeechRecoveries = resolution.nextConsecutiveRecoveries
            noSpeechRecoveryUntil = Date().addingTimeInterval(resolution.delay)
            let recoveryReason = standbyWakeMissRecoveryActive
                ? "standby-wake-miss"
                : "wake-activation"
            GlobalLogger.speech.info(
                "[ASR Session] bypassed no-speech backoff during \(recoveryReason) recovery retryIn=\(String(format: "%.2f", resolution.delay))"
            )
            return resolution.delay
        }

        consecutiveNoSpeechRecoveries = resolution.nextConsecutiveRecoveries
        let delay = resolution.delay
        noSpeechRecoveryUntil = Date().addingTimeInterval(delay)
        GlobalLogger.speech.info(
            "[ASR Session] backoff after no-speech consecutive=\(consecutiveNoSpeechRecoveries) retryIn=\(String(format: "%.2f", delay))"
        )
        return delay
    }

    private func resetNoSpeechRecoveryBackoff() {
        consecutiveNoSpeechRecoveries = 0
        noSpeechRecoveryUntil = .distantPast
        standbyWakeMissRecoveryUntil = .distantPast
        wakeActivationRecoveryUntil = .distantPast
    }

    // MARK: - EOS Callbacks
    private func handleEOS() {
        guard !isStopping else { return }
        let isStandby = isAlwaysListeningEnabled && isWakeWordEnabled && !isAwake && !isDirectCommandEnabled && !sessionTypingMode
        if isStandby { return }
        os_log("EOS detected, finalizing", log: log, type: .info)
        isStopping = true
        shouldShowProcessingDotsDuringStop = shouldUseProcessingDotsForCurrentMode()
        flushDictationStreamingForFinalization(reason: "eos")
        os_log(
            "Stop latch (EOS): controlMode=%{public}@ typing=%{public}@ showDots=%{public}@ lastTranscript=%{public}@",
            log: log,
            type: .info,
            hudRecognitionControlMode.rawValue,
            String(sessionTypingMode),
            String(shouldShowProcessingDotsDuringStop),
            lastTranscript
        )
        refreshContinuousHUD(isDictating: false)
        stopAndFinalize(keepHUDVisible: true)
    }

    private func handleSegmentTimeout() {
        guard recognitionSession.isRunning, !isStopping else { return }
        let isStandby = isAlwaysListeningEnabled && isWakeWordEnabled && !isAwake && !isDirectCommandEnabled && !sessionTypingMode
        if isStandby { eosDetector.start(); return }
        let shouldContinue = isPTTHeld || isAlwaysListeningEnabled
        os_log("Segment timeout. shouldContinue=%d", log: log, type: .info, shouldContinue)
        isStopping = true
        shouldShowProcessingDotsDuringStop = shouldUseProcessingDotsForCurrentMode()
        flushDictationStreamingForFinalization(reason: "segment-timeout")
        os_log(
            "Stop latch (timeout): controlMode=%{public}@ typing=%{public}@ showDots=%{public}@ lastTranscript=%{public}@",
            log: log,
            type: .info,
            hudRecognitionControlMode.rawValue,
            String(sessionTypingMode),
            String(shouldShowProcessingDotsDuringStop),
            lastTranscript
        )
        refreshContinuousHUD(isDictating: false)
        stopMicProgressUI(keepVisible: shouldContinue)
        stopAndFinalize(keepHUDVisible: shouldContinue)
        guard shouldContinue else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) { [weak self] in
            guard let self, !self.recognitionSession.isRunning, !self.isStopping else { return }
            self.startOnce()
        }
    }

    // MARK: - PTT
    @objc private func pttDown() {
        isPTTHeld = true
        guard !isIdlePauseSuspended else { return }
        guard isPTTEnabled else { return }
        if isAlwaysListeningEnabled {
            lastWakeTime = Date(); playWakeSound(reason: "ptt-down-always-listening"); refreshContinuousHUD(isDictating: isDictating)
            if !recognitionSession.isRunning { startOnce() }
            return
        }
        refreshContinuousHUD()
        if !availableInputDevices.contains(where: { $0.id != 0 }) { showPTTUnavailableHUD() }
        startOnce()
    }

    @objc private func pttUp() {
        isPTTHeld = false
        guard !isAlwaysListeningEnabled else { return }
        guard recognitionSession.isRunning else {
            isStopping = false
            shouldShowProcessingDotsDuringStop = false
            clearHUDStage()
            stopMicProgressUI(keepVisible: false)
            HUDManager.shared.hide()
            return
        }
        isStopping = true
        shouldShowProcessingDotsDuringStop = shouldUseProcessingDotsForCurrentMode()
        flushDictationStreamingForFinalization(reason: "ptt-up")
        clearHUDStage()
        clearHUDOverride()
        stopMicProgressUI(keepVisible: false)
        refreshContinuousHUD(isDictating: false)
        stopTimer?.invalidate()
        stopTimer = Timer.scheduledTimer(withTimeInterval: 0.6, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.stopAndFinalize(keepHUDVisible: true) }
        }
    }

    // MARK: - Stop & Finalize
    func stopAndFinalize(keepHUDVisible: Bool = false, discardTranscript: Bool = false) {
        if !keepHUDVisible { clearHUDOverride() }
        flushDictationStreamingForFinalization(reason: "stop-and-finalize")
        stopMicProgressUI(keepVisible: keepHUDVisible)
        eosDetector.stop()
        if !keepHUDVisible {
            if isAlwaysListeningEnabled { refreshContinuousHUD(isDictating: false) } else { HUDManager.shared.hide() }
        }
        guard recognitionSession.isRunning else {
            clearPendingFinalizeState()
            resetHUDTransientState()
            if keepHUDVisible, activeHUDStageMode != nil {
                refreshContinuousHUD(isDictating: false)
            } else if !keepHUDVisible {
                if isAlwaysListeningEnabled {
                    refreshContinuousHUD()
                } else {
                    HUDManager.shared.hide()
                }
            } else {
                HUDManager.shared.hide()
            }
            ensureRecognitionSessionForVisibleHUD(reason: "finalize-no-active-session")
            return
        }
        pendingFinalizeKeepHUDVisible = keepHUDVisible
        pendingFinalizeDiscardTranscript = discardTranscript
        let genToFinalize = sessionGeneration
        let fallbackTranscript = lastTranscript
        recognitionSession.finish()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self, self.sessionGeneration == genToFinalize else { return }
            self.recognitionSession.cancel()
            self.flushDictationStreamingForFinalization(reason: "finalize-timeout")
            let textToUse = discardTranscript ? "" : (self.lastTranscript.isEmpty ? fallbackTranscript : self.lastTranscript)
            if self.isAlwaysListeningEnabled {
                self.completeAlwaysListeningFinalResult(
                    textToUse,
                    source: "finalize-timeout"
                )
                return
            }
            if discardTranscript {
                self.resetHUDTransientState()
            } else {
                self.handleTranscript(textToUse, utteranceID: self.activeUtteranceID)
                self.resetUtteranceTrackingForNextPhrase()
            }
            self.isStopping = false
            self.shouldShowProcessingDotsDuringStop = false
            self.clearPendingFinalizeState()
            os_log(
                "Stop finalize complete: keepHUDVisible=%{public}@ discardTranscript=%{public}@ transcriptEmpty=%{public}@ status=%{public}@",
                log: self.log,
                type: .info,
                String(keepHUDVisible),
                String(discardTranscript),
                String(textToUse.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty),
                self.status
            )
            if !self.isAlwaysListeningEnabled {
                self.scheduleDeferredAudioStop()
                if keepHUDVisible {
                    self.refreshContinuousHUD(isDictating: false)
                } else {
                    HUDManager.shared.hide()
                }
            }
            else {
                self.refreshContinuousHUD()
                self.ensureRecognitionSessionForVisibleHUD(reason: keepHUDVisible ? "finalize-keep-hud-visible" : "finalize-always-listening")
            }
        }
        finalizationWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18, execute: workItem)
    }

    private func flushDictationStreamingForFinalization(reason: String) {
        guard sessionTypingMode || !dictationHandler.screenTypedText.isEmpty else { return }
        GlobalLogger.speech.info(
            "[TextPipeline] finalize-flush reason=\(reason) screenTypedCount=\(dictationHandler.screenTypedText.count)"
        )
        dictationHandler.flushPendingAppendForFinalization()
    }

    private func stopAudioCapture() {
        cancelStartupInputHealthProbe()
        cancelDeferredAudioStop()
        headsetInputMuteRouter.deactivate()
        audioCapture.stop()
        setPlaybackLeakState(.none)
        audioEnergyObservations.removeAll()
        currentSpeechProcessingProfile = .passthrough
    }

    private func cancelDeferredAudioStop() {
        deferredAudioStopWorkItem?.cancel()
        deferredAudioStopWorkItem = nil
    }

    private func scheduleDeferredAudioStop() {
        cancelDeferredAudioStop()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.deferredAudioStopWorkItem = nil
            guard !self.recognitionSession.isRunning, !self.isStopping, !self.isAlwaysListeningEnabled, !self.isPTTHeld else { return }
            self.headsetInputMuteRouter.deactivate()
            self.audioCapture.stop()
            self.setPlaybackLeakState(.none)
            self.audioEnergyObservations.removeAll()
            self.currentSpeechProcessingProfile = .passthrough
        }
        deferredAudioStopWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + pttAudioCaptureGracePeriod, execute: workItem)
    }

    func teardownEngine() {
        continuousRecoveryWorkItem?.cancel()
        continuousRecoveryWorkItem = nil
        cancelStartupInputHealthProbe()
        recognitionStartupGraceUntil = .distantPast
        cancelDeferredAudioStop()
        clearPendingFinalizeState()
        isStopping = false
        eosDetector.stop()
        recognitionSession.cancel()
        headsetInputMuteRouter.deactivate()
        audioCapture.stop()
    }

    func setVoiceCommandOverrides(_ overrides: [VoiceCommandOverrideConfig]) {
        commandRouter.overrides = overrides
    }

    func setLLMProviderConfiguration(
        dictationConfig: LLMProviderConfiguration?,
        dictationSource: LLMServiceSource,
        rewriteConfig: LLMProviderConfiguration?,
        rewriteSource: LLMServiceSource
    ) {
        dictationLLMServiceSource = dictationSource
        rewriteLLMServiceSource = rewriteSource
        dictationLLMProviderConfig = dictationConfig
        rewriteLLMProviderConfig = rewriteConfig
        dictationHandler.llmProvider = contextualLLMProvider(
            for: .dictationEnhancement,
            bundleIDs: currentContextBundleIDs()
        )
        dictationHandler.llmProviderContext = llmProviderDiagnosticsContext(for: .dictationEnhancement)
        dictationHandler.isLLMEnhancementEnabled = isAutoDictationEnhancementEnabled
    }

    func setVoiceLanguageTermsOverrides(_ overrides: [VoiceLanguageTermsOverrideConfig]) {
        wakeWordDetector.overrides = overrides
        commandRouter.languageTermsOverrides = overrides
    }

    func setCustomAppShortcutRules(_ rules: [CustomAppShortcutRule]) {
        customAppShortcutRules = rules
        _ = refreshFrontmostAppCommands(force: true)
    }

    func setCustomAppLaunchAliasRules(_ rules: [CustomAppLaunchAliasRule]) {
        customAppLaunchAliasRules = rules
        commandRouter.appLaunchTargets = AppLaunchResolver.contextualTargets(customRules: rules)
    }

    private func cleanup() {
        continuousRecoveryWorkItem?.cancel()
        continuousRecoveryWorkItem = nil
        recognitionStartupGraceUntil = .distantPast
        recognitionSession.cancel()
        eosDetector.stop()
        stopTimer?.invalidate(); stopTimer = nil
        clearPendingFinalizeState()
        headsetInputMuteRouter.deactivate()
        isStopping = false; isDictating = false; shouldShowProcessingDotsDuringStop = false
        activeUtteranceID = 0
        setCurrentUtteranceArbitration(.init(state: .pending), source: "speech.reset-recognition-session")
        recentExpiredWakeFollowUp?.finalizeWorkItem?.cancel()
        recentExpiredWakeFollowUp = nil
        wakeActivatedDuringCurrentUtterance = false
        lastStandbyWakeMissSegmentationAt = .distantPast
        lastWakeMissInsightSignature = nil
        lastWakeMissInsightAt = .distantPast
        wakeTypingFallbackUntil = .distantPast
        recentWakeFollowUpDictationSuppression = nil
        wakeFollowUpDictationMarkers.removeAll()
        if !isTypingRecoveryHoldActive {
            sessionTargetPID = nil; sessionTargetBundleID = nil
            sessionTargetElementFingerprint = nil; sessionTargetSource = nil
            didLogSessionTargetMismatch = false
        }
        isUtteranceActive = false
        postSubmitDictationSuppression = nil
        dictationHandler.reset(targetPID: nil)
        resetTypingStateCache()
        setAuthoritativeSessionTyping(false, source: "speech.reset-recognition-session")
    }

    private func resetHUDTransientState() {
        headsetInputMuteRouter.deactivate()
        clearPendingFinalizeState()
        isStopping = false; isDictating = false; shouldShowProcessingDotsDuringStop = false
        activeUtteranceID = 0
        setCurrentUtteranceArbitration(.init(state: .pending), source: "speech.reset-hud-transient")
        recentExpiredWakeFollowUp?.finalizeWorkItem?.cancel()
        recentExpiredWakeFollowUp = nil
        wakeActivatedDuringCurrentUtterance = false
        lastStandbyWakeMissSegmentationAt = .distantPast
        lastWakeMissInsightSignature = nil
        lastWakeMissInsightAt = .distantPast
        wakeTypingFallbackUntil = .distantPast
        recentWakeFollowUpDictationSuppression = nil
        wakeFollowUpDictationMarkers.removeAll()
        setAuthoritativeSessionTyping(false, source: "speech.reset-hud-transient")
        if !isTypingRecoveryHoldActive {
            sessionTargetPID = nil; sessionTargetBundleID = nil
            sessionTargetElementFingerprint = nil; sessionTargetSource = nil
            didLogSessionTargetMismatch = false
        }
        isUtteranceActive = false; lastTranscript = ""; lastChangeAt = nil; lastStableText = ""
        postSubmitDictationSuppression = nil
        dictationHandler.reset(targetPID: nil)
        resetTypingStateCache()
    }

    // MARK: - Continuous Mode
    private func startContinuous() {
        let now = Date()
        if now.timeIntervalSince(lastContinuousStartAt) < 0.8 { return }
        lastContinuousStartAt = now
        startOnce()
        continuousTimer?.invalidate()
        if isAlwaysListeningEnabled {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in self?.refreshContinuousHUD() }
            continuousTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.tickContinuous() }
            }
        }
    }

    private func stopContinuous() {
        continuousTimer?.invalidate(); continuousTimer = nil
        stopAndFinalize(); teardownEngine()
    }

    private func tickContinuous() {
        guard isAlwaysListeningEnabled else { return }
        let currentlyAwake = isAwake
        if currentlyAwake != wasAwake {
            wasAwake = currentlyAwake; refreshContinuousHUD()
            if currentlyAwake {
                if isWakeWordEnabled && !isDirectCommandEnabled {
                    refreshArmedInputTargetIfNeeded(reason: "wake-window-open")
                }
                let limits = resolvedSessionHardLimits(
                    for: currentSessionSpeechStyle(
                        for: currentVoiceFeatureAvailability(),
                        sessionTypingModeOverride: sessionTypingMode
                    )
                )
                startMicProgressUI(durationSec: limits.maxSegmentSec, generation: sessionGeneration)
            } else {
                clearStandbyTypingStateIfNeeded(reason: "wake-window-closed")
                // Wake-word standby hides the HUD, but the next wake phrase still
                // depends on the recognizer being re-armed immediately.
                ensureRecognitionSessionForVisibleHUD(reason: "wake-window-closed")
            }
        }
        let isWakeGated = isAlwaysListeningEnabled && isWakeWordEnabled && !isDirectCommandEnabled
        if isWakeGated && !currentlyAwake {
            if micProgressTimer != nil || HUDManager.shared.state.isMicProgressVisible { stopMicProgressUI(keepVisible: false) }
        }
        if shouldCollapseHandsFreeHUDToStandby != (HUDManager.shared.state.mode == .standby) {
            refreshContinuousHUD()
        }
        refreshArmedInputTargetIfNeeded(reason: "continuous-focus-check")

        // Health check
        if !recognitionSession.isRunning || !audioCapture.isRunning {
            if shouldWaitForInputFocusBeforeContinuousDictationStart() {
                isContinuousDictationWaitingForInputFocus = true
                refreshContinuousHUD()
                return
            }
            if isContinuousDictationWaitingForInputFocus {
                isContinuousDictationWaitingForInputFocus = false
                startOnce()
                return
            }
            if Date() < continuousRecoveryGraceUntil
                || Date() < routeRebuildGraceUntil
                || Date() < recognitionStartupGraceUntil
                || Date() < recognitionUnavailableUntil { return }
            if !audioCapture.isRunning {
                if pendingEngineRestartWorkItem == nil { scheduleEngineRestart(reason: "continuous-health-check-engine-down") }
                return
            }
            scheduleContinuousRecovery(delay: 0.12); return
        }

        let now = Date()
        let bufferAge = now.timeIntervalSince(audioCapture.lastBufferAt)
        if Self.shouldRecoverFromContinuousStandbyNoBufferStall(
            isAlwaysListeningEnabled: isAlwaysListeningEnabled,
            isWakeWordEnabled: isWakeWordEnabled,
            isDirectCommandEnabled: isDirectCommandEnabled,
            isAwake: currentlyAwake,
            isStopping: isStopping,
            isUtteranceActive: isUtteranceActive,
            audioCaptureRunning: audioCapture.isRunning,
            recognitionRunning: recognitionSession.isRunning,
            pendingEngineRestart: pendingEngineRestartWorkItem != nil,
            bufferAge: bufferAge,
            routeRebuildGraceActive: now < routeRebuildGraceUntil,
            continuousRecoveryGraceActive: now < continuousRecoveryGraceUntil,
            recognitionStartupGraceActive: now < recognitionStartupGraceUntil,
            recognitionUnavailableActive: now < recognitionUnavailableUntil
        ) {
            let bufferAgeText = String(format: "%.2fs", bufferAge)
            GlobalLogger.speech.info(
                "[ASRStall] scheduling recovery reason=no-audio-buffers age=\(bufferAgeText) recognitionRunning=\(recognitionSession.isRunning) audioRunning=\(audioCapture.isRunning) awake=\(currentlyAwake) utteranceActive=\(isUtteranceActive) selectedInputID=\(selectedInputDeviceID) effectiveInputID=\(effectiveCaptureInputDeviceID()) boundInputID=\(audioCapture.currentBoundInputDeviceID()) input='\(currentResolvedInputDeviceName)'"
            )
            scheduleEngineRestart(reason: "audio-buffer-stall", debounce: 0.05)
            return
        }

        // EOSDetector is the single source of truth for utterance boundaries.
        // Avoid a second transcript-stability splitter here; it can cut a continuous
        // sentence into multiple fragments even when the user never paused.
    }

    private func scheduleContinuousRecovery(delay: TimeInterval = 0.25) {
        guard isAlwaysListeningEnabled else { return }
        continuousRecoveryWorkItem?.cancel()
        continuousRecoveryGraceUntil = Date().addingTimeInterval(delay + 0.6)
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.continuousRecoveryWorkItem = nil
            guard self.isAlwaysListeningEnabled, !self.recognitionSession.isRunning else { return }
            if self.shouldWaitForInputFocusBeforeContinuousDictationStart() {
                self.isContinuousDictationWaitingForInputFocus = true
                self.refreshContinuousHUD()
                return
            }
            self.startOnce()
        }
        continuousRecoveryWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    func undoLastInjection() { injector.undoPasteIfRecent() }
    func updateAccessibilityTrusted(_ trusted: Bool) { accessibilityTrustedSnapshot = trusted }
    @MainActor
    func exportFocusedInputDiagnostics() throws -> URL {
        let report = buildFocusedInputDiagnosticsReport()
        let logsDir = focusedInputDiagnosticsDirectoryURL()
        try FileManager.default.createDirectory(at: logsDir, withIntermediateDirectories: true)

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let fileURL = logsDir.appendingPathComponent(
            "focused-input-diagnostics-\(formatter.string(from: Date())).txt",
            isDirectory: false
        )
        try report.write(to: fileURL, atomically: true, encoding: .utf8)
        return fileURL
    }

    private func focusedInputDiagnosticsDirectoryURL() -> URL {
        let base = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library", isDirectory: true)
        return base
            .appendingPathComponent("Logs", isDirectory: true)
            .appendingPathComponent("Aether", isDirectory: true)
    }

    private func shouldEmitWakeDiagnostic(
        signature: String,
        lastSignature: inout String?,
        lastAt: inout Date,
        minInterval: TimeInterval
    ) -> Bool {
        let now = Date()
        if lastSignature != signature || now.timeIntervalSince(lastAt) >= minInterval {
            lastSignature = signature
            lastAt = now
            return true
        }
        return false
    }

    private func wakeDiagnosticAgeDescription(since date: Date?) -> String {
        guard let date else { return "nil" }
        return String(format: "%.2fs", max(0, Date().timeIntervalSince(date)))
    }

    private func wakeDiagnosticRemainingDescription(until date: Date) -> String {
        let remaining = date.timeIntervalSinceNow
        if remaining <= 0 {
            return "0.00s"
        }
        return String(format: "%.2fs", remaining)
    }

    private func wakeDiagnosticSnippet(_ text: String, limit: Int = 48) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        if trimmed.count <= limit {
            return trimmed
        }
        let end = trimmed.index(trimmed.startIndex, offsetBy: limit)
        return "\(trimmed[..<end])..."
    }

    private func wakeDiagnosticNormalizeForMatching(_ text: String) -> String {
        text
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .unicodeScalars
            .filter {
                !CharacterSet.whitespacesAndNewlines.contains($0)
                    && !CharacterSet.punctuationCharacters.contains($0)
            }
            .map(String.init)
            .joined()
            .lowercased()
    }

    private func wakeDiagnosticTrimLeadingIgnorables(_ text: String) -> String {
        var index = text.startIndex
        while index < text.endIndex {
            let scalarView = text[index].unicodeScalars
            let isIgnorable = scalarView.allSatisfy {
                CharacterSet.whitespacesAndNewlines.contains($0)
                    || CharacterSet.punctuationCharacters.contains($0)
            }
            if !isIgnorable { break }
            index = text.index(after: index)
        }
        return String(text[index...])
    }

    private func wakeDiagnosticMatchModeDescription(_ matchMode: WakeWordMatchMode) -> String {
        switch matchMode {
        case .strictPrefix:
            return "strictPrefix"
        case .retryAwareStandby:
            return "retryAwareStandby"
        case .awakeFollowUp:
            return "awakeFollowUp"
        }
    }

    private func wakeDiagnosticThresholdDescription(for matchMode: WakeWordMatchMode) -> String {
        switch matchMode {
        case .strictPrefix:
            return "0.88"
        case .retryAwareStandby:
            return "strict=0.88 retry=0.93"
        case .awakeFollowUp:
            return "0.88"
        }
    }

    private func wakeDiagnosticEffectivePhrases(for localeIdentifier: String) -> [String] {
        WakeWordDetector.effectiveWakePhrases(
            for: localeIdentifier,
            overrides: wakeWordDetector.overrides
        )
        .sorted { $0.count > $1.count }
    }

    private func wakeDiagnosticPhraseOccurrence(
        in rawText: String,
        localeIdentifier: String
    ) -> (phrase: String, offset: Int, leadingContext: String)? {
        let trimmedLeading = wakeDiagnosticTrimLeadingIgnorables(rawText)
        let normalizedText = wakeDiagnosticNormalizeForMatching(trimmedLeading)
        guard !normalizedText.isEmpty else { return nil }

        var best: (phrase: String, offset: Int, leadingContext: String)?

        for phrase in wakeDiagnosticEffectivePhrases(for: localeIdentifier) {
            let normalizedPhrase = wakeDiagnosticNormalizeForMatching(phrase)
            guard !normalizedPhrase.isEmpty,
                  let range = normalizedText.range(of: normalizedPhrase) else {
                continue
            }

            let offset = normalizedText.distance(from: normalizedText.startIndex, to: range.lowerBound)
            let leadingContext = String(normalizedText.prefix(offset))
            let candidate = (phrase: phrase, offset: offset, leadingContext: leadingContext)

            if let current = best {
                if candidate.offset < current.offset
                    || (candidate.offset == current.offset && candidate.phrase.count > current.phrase.count) {
                    best = candidate
                }
            } else {
                best = candidate
            }
        }

        return best
    }

    private func logWakeEvaluationIfNeeded(
        phase: String,
        rawText: String,
        matchMode: WakeWordMatchMode,
        wakeDetected: Bool,
        wakeScore: Double,
        matchedWakePhrase: String?,
        payload: String?
    ) {
        let rawSnippet = wakeDiagnosticSnippet(rawText)
        guard !rawSnippet.isEmpty else { return }

        let phraseOccurrence = wakeDiagnosticPhraseOccurrence(
            in: rawText,
            localeIdentifier: activeLocale.identifier
        )
        let shouldLogMiss = phase.hasPrefix("final") || wakeScore > 0 || phraseOccurrence != nil
        guard wakeDetected || shouldLogMiss else { return }

        let result = wakeDetected ? "hit" : "miss"
        let reason: String
        let failureReason: WakeAnalyticsFailureReason
        if wakeDetected {
            reason = "matched-prefix"
            failureReason = .noPhraseMatch
        } else if wakeScore > 0 {
            reason = "below-threshold"
            failureReason = .belowThreshold
        } else if let phraseOccurrence, phraseOccurrence.offset > 0 {
            reason = "phrase-not-at-prefix"
            failureReason = .phraseNotAtPrefix
        } else if phraseOccurrence != nil {
            reason = "prefix-rejected"
            failureReason = .prefixRejected
        } else {
            reason = "no-phrase-match"
            failureReason = .noPhraseMatch
        }

        let occurrenceDetails: String
        if let phraseOccurrence {
            occurrenceDetails = " candidate='\(phraseOccurrence.phrase)' candidateOffset=\(phraseOccurrence.offset) leadIn='\(wakeDiagnosticSnippet(phraseOccurrence.leadingContext, limit: 24))'"
        } else {
            occurrenceDetails = ""
        }

        let payloadDetails: String
        if let payload {
            payloadDetails = " payload='\(wakeDiagnosticSnippet(payload))'"
        } else {
            payloadDetails = ""
        }

        GlobalLogger.speech.info(
            "[WakeWordResult] phase=\(phase) result=\(result) reason=\(reason) awake=\(isAwake) alwaysListening=\(isAlwaysListeningEnabled) directCommand=\(isDirectCommandEnabled) matchMode=\(wakeDiagnosticMatchModeDescription(matchMode)) score=\(String(format: "%.2f", wakeScore)) threshold=\(wakeDiagnosticThresholdDescription(for: matchMode)) matched=\(matchedWakePhrase ?? "nil")\(occurrenceDetails) raw='\(rawSnippet)'\(payloadDetails)"
        )

        let candidatePhrase = matchedWakePhrase ?? phraseOccurrence?.phrase
        let shouldEmitWakeMiss = !wakeDetected && shouldEmitWakeMissToInsights(
            phase: phase,
            reason: failureReason,
            candidatePhrase: candidatePhrase,
            wakeScore: wakeScore,
            phraseOccurrence: phraseOccurrence,
            transcript: rawSnippet
        )
        if shouldEmitWakeMiss {
            onWakeAnalyticsSignal?(
                .miss(
                    phase: phase,
                    reason: failureReason,
                    phrase: candidatePhrase,
                    localeIdentifier: activeLocale.identifier,
                    transcript: rawSnippet
                )
            )
        }
    }

    private func shouldEmitWakeMissToInsights(
        phase: String,
        reason: WakeAnalyticsFailureReason,
        candidatePhrase: String?,
        wakeScore: Double,
        phraseOccurrence: (phrase: String, offset: Int, leadingContext: String)?,
        transcript: String
    ) -> Bool {
        let isDiagnosableMiss = wakeScore > 0 || phraseOccurrence != nil
        guard isDiagnosableMiss else { return false }

        let shouldSurfaceInInsights: Bool
        if phase.contains("awake") {
            shouldSurfaceInInsights = false
        } else if phase.hasPrefix("final") {
            shouldSurfaceInInsights = true
        } else if phase.hasPrefix("partial") {
            switch reason {
            case .belowThreshold, .phraseNotAtPrefix, .prefixRejected:
                shouldSurfaceInInsights = true
            case .noPhraseMatch:
                shouldSurfaceInInsights = false
            }
        } else {
            shouldSurfaceInInsights = false
        }
        guard shouldSurfaceInInsights else { return false }

        let normalizedLeadIn = phraseOccurrence.map {
            wakeDiagnosticNormalizeForMatching($0.leadingContext)
        } ?? ""
        let leadingSignature = normalizedLeadIn.isEmpty
            ? String(wakeDiagnosticNormalizeForMatching(transcript).prefix(12))
            : String(normalizedLeadIn.prefix(12))
        let signature = [
            reason.rawValue,
            candidatePhrase ?? "nil",
            leadingSignature
        ].joined(separator: "|")
        let now = Date()

        if lastWakeMissInsightSignature == signature,
           now.timeIntervalSince(lastWakeMissInsightAt) < wakeMissInsightDedupWindow {
            return false
        }

        lastWakeMissInsightSignature = signature
        lastWakeMissInsightAt = now
        return true
    }

    private func wakeHUDStateSnapshot(
        controlMode: HUDRecognitionControlMode?,
        typingEligible: Bool?,
        effectiveDictating: Bool?,
        isSessionActive: Bool?
    ) -> String {
        let hudState = HUDManager.shared.state
        let wakePhrase = pendingWakeFollowUp?.phrase ?? "nil"
        return [
            "hud=\(hudState.mode.rawValue)",
            "hudControl=\((controlMode ?? hudState.recognitionControlMode).rawValue)",
            "awake=\(isAwake)",
            "wakeAge=\(wakeDiagnosticAgeDescription(since: lastWakeTime))",
            "pendingWake=\(pendingWakeFollowUp != nil)",
            "pendingWakeAge=\(wakeDiagnosticAgeDescription(since: pendingWakeFollowUp?.createdAt))",
            "pendingWakePhrase='\(wakePhrase)'",
            "recognitionRunning=\(recognitionSession.isRunning)",
            "audioRunning=\(audioCapture.isRunning)",
            "isStopping=\(isStopping)",
            "isUtteranceActive=\(isUtteranceActive)",
            "sessionTypingMode=\(sessionTypingMode)",
            "focusWait=\(isContinuousDictationWaitingForInputFocus)",
            "tempHUD=\(HUDManager.shared.isTemporaryHUDActive)",
            "langIndicator=\(hudState.isLanguageIndicatorVisible)",
            "typingEligible=\(typingEligible.map(String.init(describing:)) ?? "nil")",
            "effectiveDictating=\(effectiveDictating.map(String.init(describing:)) ?? "nil")",
            "sessionActive=\(isSessionActive.map(String.init(describing:)) ?? "nil")",
            "lastTranscript='\(wakeDiagnosticSnippet(lastTranscript))'",
            "lastStable='\(wakeDiagnosticSnippet(lastStableText))'"
        ].joined(separator: " ")
    }

    private func logWakeHUDStateIfNeeded(
        reason: String,
        controlMode: HUDRecognitionControlMode?,
        typingEligible: Bool?,
        effectiveDictating: Bool?,
        isSessionActive: Bool?
    ) {
        let snapshot = wakeHUDStateSnapshot(
            controlMode: controlMode,
            typingEligible: typingEligible,
            effectiveDictating: effectiveDictating,
            isSessionActive: isSessionActive
        )
        let signature = "\(reason)|\(snapshot)"
        guard shouldEmitWakeDiagnostic(
            signature: signature,
            lastSignature: &lastWakeHUDDiagnosticSignature,
            lastAt: &lastWakeHUDDiagnosticAt,
            minInterval: 1.5
        ) else {
            return
        }
        GlobalLogger.speech.info("[WakeHUD] reason=\(reason) \(snapshot)")
    }

    private func logWakeArmStateIfNeeded(reason: String, outcome: String) {
        let signature = [
            reason,
            outcome,
            String(recognitionSession.isRunning),
            String(audioCapture.isRunning),
            String(isStopping),
            String(pendingEngineRestartWorkItem != nil),
            wakeDiagnosticRemainingDescription(until: routeRebuildGraceUntil),
            wakeDiagnosticRemainingDescription(until: continuousRecoveryGraceUntil),
            wakeDiagnosticRemainingDescription(until: recognitionUnavailableUntil)
        ].joined(separator: "|")
        guard shouldEmitWakeDiagnostic(
            signature: signature,
            lastSignature: &lastWakeArmDiagnosticSignature,
            lastAt: &lastWakeArmDiagnosticAt,
            minInterval: 1.0
        ) else {
            return
        }
        GlobalLogger.speech.info(
            "[WakeArm] reason=\(reason) outcome=\(outcome) recognitionRunning=\(recognitionSession.isRunning) audioRunning=\(audioCapture.isRunning) isStopping=\(isStopping) pendingRestart=\(pendingEngineRestartWorkItem != nil) routeGraceRemaining=\(wakeDiagnosticRemainingDescription(until: routeRebuildGraceUntil)) recoveryGraceRemaining=\(wakeDiagnosticRemainingDescription(until: continuousRecoveryGraceUntil)) unavailableRemaining=\(wakeDiagnosticRemainingDescription(until: recognitionUnavailableUntil)) wakeAge=\(wakeDiagnosticAgeDescription(since: lastWakeTime))"
        )
    }

    private func playWakeSound(reason: String) {
        GlobalLogger.speech.info("[AudioCue] play Tink reason=\(reason)")
        NSSound(named: "Tink")?.play()
    }

    private func shouldHoldWakeFollowUpForLateFinal(at now: Date) -> Bool {
        if isUtteranceActive {
            return true
        }
        if !lastTranscript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return true
        }
        if let lastChangeAt,
           now.timeIntervalSince(lastChangeAt) <= wakeFollowUpLateFinalActivityWindow {
            return true
        }
        if let voiceActivityWithoutPartialSince,
           now.timeIntervalSince(voiceActivityWithoutPartialSince) <= wakeFollowUpLateFinalActivityWindow {
            return true
        }
        return false
    }

    private func finalizeWakeFollowUpAsEmpty(
        groupID: String,
        phrase: String?,
        localeIdentifier: String,
        createdAt: Date,
        reason: String
    ) {
        if let recentExpiredWakeFollowUp,
           recentExpiredWakeFollowUp.groupID == groupID {
            recentExpiredWakeFollowUp.finalizeWorkItem?.cancel()
            self.recentExpiredWakeFollowUp = nil
        }
        if lastWakeTime != nil {
            lastWakeTime = nil
            GlobalLogger.speech.info(
                "[WakeWord] closed wake window reason=\(reason) group=\(groupID)"
            )
        }
        GlobalLogger.speech.info(
            "[WakeFollowUp] timeout-finalized group=\(groupID) reason=\(reason) age=\(wakeDiagnosticAgeDescription(since: createdAt)) phrase='\(phrase ?? "nil")' hud=\(HUDManager.shared.state.mode.rawValue) recognitionRunning=\(recognitionSession.isRunning) audioRunning=\(audioCapture.isRunning) awake=\(isAwake) lastTranscript='\(wakeDiagnosticSnippet(lastTranscript))'"
        )
        clearSessionInputTarget(reason: "wake-follow-up-timeout")
        clearStandbyTypingStateIfNeeded(reason: "wake-follow-up-timeout")
        onWakeAnalyticsSignal?(
            .empty(
                groupID: groupID,
                phrase: phrase,
                localeIdentifier: localeIdentifier
            )
        )
    }

    private func armRecentExpiredWakeFollowUpGrace(
        from pending: PendingWakeFollowUp,
        expiredAt: Date
    ) {
        recentExpiredWakeFollowUp?.finalizeWorkItem?.cancel()

        let finalizeWorkItem = DispatchWorkItem { [weak self] in
            DispatchQueue.main.async {
                guard let self,
                      let recentExpiredWakeFollowUp = self.recentExpiredWakeFollowUp,
                      recentExpiredWakeFollowUp.groupID == pending.groupID else { return }
                self.finalizeWakeFollowUpAsEmpty(
                    groupID: recentExpiredWakeFollowUp.groupID,
                    phrase: recentExpiredWakeFollowUp.phrase,
                    localeIdentifier: recentExpiredWakeFollowUp.localeIdentifier,
                    createdAt: recentExpiredWakeFollowUp.createdAt,
                    reason: "late-final-grace-expired"
                )
            }
        }

        recentExpiredWakeFollowUp = RecentExpiredWakeFollowUp(
            groupID: pending.groupID,
            phrase: pending.phrase,
            localeIdentifier: pending.localeIdentifier,
            createdAt: pending.createdAt,
            expiredAt: expiredAt,
            finalizeWorkItem: finalizeWorkItem
        )
        GlobalLogger.speech.info(
            "[WakeFollowUp] timeout-grace group=\(pending.groupID) age=\(wakeDiagnosticAgeDescription(since: pending.createdAt)) grace=\(String(format: "%.2fs", wakeFollowUpLateFinalGraceWindow)) phrase='\(pending.phrase ?? "nil")' utteranceActive=\(isUtteranceActive) lastTranscript='\(wakeDiagnosticSnippet(lastTranscript))'"
        )
        DispatchQueue.main.asyncAfter(
            deadline: .now() + wakeFollowUpLateFinalGraceWindow,
            execute: finalizeWorkItem
        )
    }

    private func consumeRecentExpiredWakeFollowUpIfNeeded() -> PendingWakeFollowUp? {
        guard let recentExpiredWakeFollowUp else { return nil }
        recentExpiredWakeFollowUp.finalizeWorkItem?.cancel()
        self.recentExpiredWakeFollowUp = nil
        GlobalLogger.speech.info(
            "[WakeFollowUp] recovered-late-final group=\(recentExpiredWakeFollowUp.groupID) age=\(wakeDiagnosticAgeDescription(since: recentExpiredWakeFollowUp.createdAt)) graceAge=\(wakeDiagnosticAgeDescription(since: recentExpiredWakeFollowUp.expiredAt)) phrase='\(recentExpiredWakeFollowUp.phrase ?? "nil")'"
        )
        return PendingWakeFollowUp(
            groupID: recentExpiredWakeFollowUp.groupID,
            phrase: recentExpiredWakeFollowUp.phrase,
            localeIdentifier: recentExpiredWakeFollowUp.localeIdentifier,
            createdAt: recentExpiredWakeFollowUp.createdAt,
            lastActivityAt: recentExpiredWakeFollowUp.expiredAt,
            timeoutWorkItem: nil
        )
    }

    private var hasRecentExpiredWakeFollowUpGrace: Bool {
        recentExpiredWakeFollowUp != nil
    }

    private func refreshPendingWakeFollowUpActivity(reason: String, at now: Date = Date()) {
        guard var pending = pendingWakeFollowUp else { return }
        guard now.timeIntervalSince(lastWakeFollowUpActivityRefreshAt) >= wakeFollowUpActivityRefreshDebounce else { return }

        let previousActivityAt = pending.lastActivityAt
        pending.timeoutWorkItem?.cancel()
        pending.lastActivityAt = now
        let workItem = makeWakeFollowUpTimeoutWorkItem(groupID: pending.groupID)
        pending.timeoutWorkItem = workItem
        pendingWakeFollowUp = pending
        lastWakeFollowUpActivityRefreshAt = now

        GlobalLogger.speech.info(
            "[WakeFollowUp] activity-extend group=\(pending.groupID) reason=\(reason) age=\(wakeDiagnosticAgeDescription(since: pending.createdAt)) idle=\(String(format: "%.2fs", now.timeIntervalSince(previousActivityAt))) timeout=\(String(format: "%.2fs", alwaysListeningWakeWindowSeconds()))"
        )
        DispatchQueue.main.asyncAfter(
            deadline: .now() + alwaysListeningWakeWindowSeconds(),
            execute: workItem
        )
    }

    private func makeWakeFollowUpTimeoutWorkItem(groupID: String) -> DispatchWorkItem {
        DispatchWorkItem { [weak self] in
            DispatchQueue.main.async {
                guard let self,
                      let pending = self.pendingWakeFollowUp,
                      pending.groupID == groupID else { return }
                let now = Date()
                GlobalLogger.speech.info(
                    "[WakeFollowUp] timeout group=\(pending.groupID) age=\(self.wakeDiagnosticAgeDescription(since: pending.createdAt)) idle=\(String(format: "%.2fs", now.timeIntervalSince(pending.lastActivityAt))) phrase='\(pending.phrase ?? "nil")' hud=\(HUDManager.shared.state.mode.rawValue) recognitionRunning=\(self.recognitionSession.isRunning) audioRunning=\(self.audioCapture.isRunning) awake=\(self.isAwake) lastTranscript='\(self.wakeDiagnosticSnippet(self.lastTranscript))'"
                )
                self.pendingWakeFollowUp = nil
                self.lastWakeFollowUpActivityRefreshAt = .distantPast
                if self.shouldHoldWakeFollowUpForLateFinal(at: now) {
                    self.armRecentExpiredWakeFollowUpGrace(from: pending, expiredAt: now)
                    return
                }
                self.finalizeWakeFollowUpAsEmpty(
                    groupID: pending.groupID,
                    phrase: pending.phrase,
                    localeIdentifier: pending.localeIdentifier,
                    createdAt: pending.createdAt,
                    reason: "primary-timeout"
                )
            }
        }
    }

    private func beginPendingWakeFollowUp(phrase: String?, allowReuseExisting: Bool = false) {
        let normalizedPhrase = phrase?.trimmingCharacters(in: .whitespacesAndNewlines)
        recentExpiredWakeFollowUp?.finalizeWorkItem?.cancel()
        recentExpiredWakeFollowUp = nil
        if allowReuseExisting, var pending = pendingWakeFollowUp {
            pending.timeoutWorkItem?.cancel()
            if pending.phrase == nil, normalizedPhrase?.isEmpty == false {
                pending.phrase = normalizedPhrase
            }
            pending.lastActivityAt = Date()
            let workItem = makeWakeFollowUpTimeoutWorkItem(groupID: pending.groupID)
            pending.timeoutWorkItem = workItem
            pendingWakeFollowUp = pending
            lastWakeFollowUpActivityRefreshAt = pending.lastActivityAt
            GlobalLogger.speech.info(
                "[WakeFollowUp] extend group=\(pending.groupID) age=\(wakeDiagnosticAgeDescription(since: pending.createdAt)) phrase='\(pending.phrase ?? "nil")' timeout=\(String(format: "%.2fs", alwaysListeningWakeWindowSeconds()))"
            )
            DispatchQueue.main.asyncAfter(
                deadline: .now() + alwaysListeningWakeWindowSeconds(),
                execute: workItem
            )
            return
        }

        if let pending = pendingWakeFollowUp {
            pending.timeoutWorkItem?.cancel()
            GlobalLogger.speech.info(
                "[WakeFollowUp] replacing pending group=\(pending.groupID) age=\(wakeDiagnosticAgeDescription(since: pending.createdAt)) phrase='\(pending.phrase ?? "nil")' reason=new-wake-hit"
            )
            onWakeAnalyticsSignal?(
                .empty(
                    groupID: pending.groupID,
                    phrase: pending.phrase,
                    localeIdentifier: pending.localeIdentifier
                )
            )
            pendingWakeFollowUp = nil
            lastWakeFollowUpActivityRefreshAt = .distantPast
        }

        let groupID = UUID().uuidString
        let localeIdentifier = activeLocale.identifier
        let phraseToStore = normalizedPhrase?.isEmpty == false ? normalizedPhrase : nil
        let now = Date()
        onWakeAnalyticsSignal?(
            .hit(
                groupID: groupID,
                phrase: phraseToStore,
                localeIdentifier: localeIdentifier
            )
        )

        let workItem = makeWakeFollowUpTimeoutWorkItem(groupID: groupID)

        pendingWakeFollowUp = PendingWakeFollowUp(
            groupID: groupID,
            phrase: phraseToStore,
            localeIdentifier: localeIdentifier,
            createdAt: now,
            lastActivityAt: now,
            timeoutWorkItem: workItem
        )
        lastWakeFollowUpActivityRefreshAt = now
        GlobalLogger.speech.info(
            "[WakeFollowUp] begin group=\(groupID) phrase='\(phraseToStore ?? "nil")' locale=\(localeIdentifier) timeout=\(String(format: "%.2fs", alwaysListeningWakeWindowSeconds())) hudBefore=\(HUDManager.shared.state.mode.rawValue)"
        )
        DispatchQueue.main.asyncAfter(
            deadline: .now() + alwaysListeningWakeWindowSeconds(),
            execute: workItem
        )
    }

    @discardableResult
    private func completePendingWakeFollowUpIfNeeded(intent: VoiceIntent, transcript: String) -> PendingWakeFollowUp? {
        let pending: PendingWakeFollowUp
        if let activePendingWakeFollowUp = pendingWakeFollowUp {
            pending = activePendingWakeFollowUp
        } else if let lateFinalPendingWakeFollowUp = consumeRecentExpiredWakeFollowUpIfNeeded() {
            pending = lateFinalPendingWakeFollowUp
        } else {
            return nil
        }

        let followUp: WakeAnalyticsFollowUpKind
        switch intent {
        case .dictation:
            followUp = .dictation
        default:
            guard Self.isCommandIntentStatic(intent) else { return nil }
            followUp = .control
        }

        pending.timeoutWorkItem?.cancel()
        pendingWakeFollowUp = nil
        lastWakeFollowUpActivityRefreshAt = .distantPast
        clearWakeTypingFallback(reason: "wake-follow-up-converted")
        GlobalLogger.speech.info(
            "[WakeFollowUp] converted group=\(pending.groupID) followUp=\(String(describing: followUp)) age=\(wakeDiagnosticAgeDescription(since: pending.createdAt)) hud=\(HUDManager.shared.state.mode.rawValue) transcript='\(wakeDiagnosticSnippet(transcript))'"
        )
        onWakeAnalyticsSignal?(
            .converted(
                groupID: pending.groupID,
                followUp: followUp,
                phrase: pending.phrase,
                localeIdentifier: pending.localeIdentifier,
                transcript: transcript
            )
        )
        return pending
    }

    private func handleWakeActivation(reason: String, rearmReason: String? = nil) {
        if isAppIdlePaused?() == true {
            GlobalLogger.speech.info("[IdlePause] wake word requested resume reason=\(reason)")
            onIdlePauseResumeRequest?("wake-word-\(reason)")
        }
        let hudBefore = HUDManager.shared.state.mode
        lastWakeTime = Date()
        GlobalLogger.speech.info(
            "[WakeWord] activated reason=\(reason) hudBefore=\(hudBefore.rawValue) recognitionRunning=\(recognitionSession.isRunning) audioRunning=\(audioCapture.isRunning) transcript='\(wakeDiagnosticSnippet(lastTranscript))'"
        )
        playWakeSound(reason: reason)
        let effectiveRearmReason = rearmReason ?? ((isWakeWordEnabled && !isDirectCommandEnabled) ? "wake-activation" : nil)
        if let effectiveRearmReason {
            refreshArmedInputTargetIfNeeded(reason: effectiveRearmReason)
        }
        armWakeTypingFallback(reason: reason)
        if recognitionControlMode == .auto,
           dictationHandler.screenTypedText.isEmpty,
           (sessionTypingMode || isDictating || isTypingRecoveryHoldActive) {
            isDictating = false
            endTypingRecoveryHold(reason: "wake-activation-command-baseline")
            setAuthoritativeSessionTyping(false, source: "speech.wake-activation")
            GlobalLogger.speech.info(
                "[TypingMode] reset to command baseline on wake activation reason=\(reason)"
            )
        }
        else {
            syncInputControlState(source: "speech.wake-activation")
        }
        clearUnarmedWakePreview()
        setHUDOverride(
            mode: .feedback,
            message: "",
            icon: hudInputIcon(),
            inputDeviceHealth: hudInputHealth(),
            duration: 0.22
        )
        refreshContinuousHUD(isDictating: false)
        let hudAfter = HUDManager.shared.state.mode
        GlobalLogger.speech.info(
            "[WakeWord] activation-complete reason=\(reason) hudAfter=\(hudAfter.rawValue) recognitionRunning=\(recognitionSession.isRunning) audioRunning=\(audioCapture.isRunning) pendingWake=\(pendingWakeFollowUp != nil)"
        )
        if hudAfter == .hidden {
            let hudState = HUDManager.shared.state
            logWakeHUDStateIfNeeded(
                reason: "hidden-after-activation-\(reason)",
                controlMode: hudState.recognitionControlMode,
                typingEligible: nil,
                effectiveDictating: isDictating,
                isSessionActive: recognitionSession.isRunning || audioCapture.isRunning || isStopping
            )
        }
    }

    // MARK: - handleTranscript (unified finalization)
    private func handleTranscript(_ transcript: String, utteranceID: Int? = nil) {
        let rawTrimmed = canonicalizedExplicitCommandPrefixText(
            transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        guard !rawTrimmed.isEmpty else { return }
        noteHandsFreeHUDActivity()

        var textToRoute = rawTrimmed
        var wakeWordDetected = false
        var wakeScore: Double = 0
        var matchedWakePhrase: String?
        let wakeRoutingActive = isWakeFollowUpRoutingActive

        if isDirectCommandEnabled {
            logWakeWordConfigurationIfNeeded(reason: "final-direct-command")
            let wakeResult = wakeWordDetector.process(rawTrimmed, localeIdentifier: activeLocale.identifier)
            wakeScore = wakeResult.score
            matchedWakePhrase = wakeResult.matchedPhrase
            if isWakeWordEnabled {
                logWakeEvaluationIfNeeded(
                    phase: "final-direct-command",
                    rawText: rawTrimmed,
                    matchMode: .strictPrefix,
                    wakeDetected: wakeResult.wakeDetected,
                    wakeScore: wakeScore,
                    matchedWakePhrase: matchedWakePhrase,
                    payload: wakeResult.wakeDetected ? wakeResult.payload : nil
                )
            }
            if isWakeWordEnabled && wakeResult.wakeDetected {
                textToRoute = wakeResult.payload; wakeWordDetected = true; handleWakeActivation(reason: "direct-command-final-wake")
            } else {
                textToRoute = rawTrimmed
            }
        } else if isWakeWordEnabled && !isDirectCommandEnabled {
            logWakeWordConfigurationIfNeeded(reason: "final-always-listening")
            let matchMode = Self.wakeMatchMode(
                isWakeWordEnabled: isWakeWordEnabled,
                isDirectCommandEnabled: isDirectCommandEnabled,
                isAlwaysListeningEnabled: isAlwaysListeningEnabled,
                isAwake: wakeRoutingActive
            )
            let wakeResult = wakeWordDetector.process(
                rawTrimmed,
                localeIdentifier: activeLocale.identifier,
                matchMode: matchMode
            )
            wakeScore = wakeResult.score
            matchedWakePhrase = wakeResult.matchedPhrase
            logWakeEvaluationIfNeeded(
                phase: wakeRoutingActive ? "final-awake" : "final-sleeping",
                rawText: rawTrimmed,
                matchMode: matchMode,
                wakeDetected: wakeResult.wakeDetected,
                wakeScore: wakeScore,
                matchedWakePhrase: matchedWakePhrase,
                payload: wakeResult.wakeDetected ? wakeResult.payload : nil
            )
            if wakeRoutingActive {
                if wakeResult.wakeDetected {
                    textToRoute = wakeResult.payload
                    wakeWordDetected = true
                    if !wakeActivatedDuringCurrentUtterance {
                        handleWakeActivation(reason: "always-listening-awake-final-wake")
                    }
                }
                else {
                    textToRoute = rawTrimmed
                }
            } else {
                if wakeResult.wakeDetected {
                    textToRoute = wakeResult.payload
                    wakeWordDetected = true
                    if !wakeActivatedDuringCurrentUtterance {
                        handleWakeActivation(reason: "always-listening-sleeping-final-wake")
                    }
                }
                else {
                    return
                }
            }
        }
        if wakeWordDetected {
            beginPendingWakeFollowUp(phrase: matchedWakePhrase, allowReuseExisting: true)
        }

        let lockedFocusedSnapshot = currentFocusedInputSnapshot()
        let lockedTargetMatches = hasLockedFocusedInputTarget(lockedFocusedSnapshot)
        let liveTyping = throttledTypingMode()
        let hasStreamedDictation = !dictationHandler.screenTypedText.isEmpty
        let featureAvailability = currentVoiceFeatureAvailability()
        let controlMode = effectiveRecognitionControlMode(for: featureAvailability)
        let wakeTypingAllowed = Self.shouldAllowWakeGatedTyping(
            isWakeWordEnabled: isWakeWordEnabled,
            isDirectCommandEnabled: isDirectCommandEnabled,
            isAwake: wakeRoutingActive,
            wakeWordDetected: wakeWordDetected
        )
        let computedTypingContext = Self.resolvedUtteranceTypingMode(
            recognitionControlMode: controlMode,
            sessionTypingMode: sessionTypingMode,
            liveTyping: liveTyping,
            canType: wakeTypingAllowed,
            hasStreamedDictation: hasStreamedDictation
        )
        let hudState = HUDManager.shared.state
        let hasAuthoritativeTypingEvidence = hasAuthoritativeTypingEvidence()
        let wakePayloadLooksLikeCommand = likelyWakePayloadCommand(textToRoute)
        let hasStrongTypingFallback = hasStrongTypingFallbackEvidence(
            lockedFocusedSnapshot: lockedFocusedSnapshot,
            lockedTargetMatches: lockedTargetMatches,
            computedTypingContext: computedTypingContext,
            hasAuthoritativeTypingEvidence: hasAuthoritativeTypingEvidence,
            hasStreamedDictation: hasStreamedDictation
        )
        let wakeArbitrationActive = wakeRoutingActive || wakeWordDetected
        let wakeArbitration = wakeArbitrationActive
            ? wakeFollowUpArbitrationResult(
                controlMode: controlMode,
                transcript: textToRoute,
                routerDecision: commandRouter.routeDetailed(
                    transcript: textToRoute,
                    bias: .commandPreferred,
                    localeIdentifier: activeLocale.identifier
                ),
                hasStableTypingEvidence: hasStrongTypingFallback,
                hasLiveTypingEvidence: liveTyping
            )
            : .init(state: .pending)
        setCurrentUtteranceArbitration(wakeArbitration, source: "speech.final-wake")
        var typingContext = Self.reconcileTypingContextWithVisibleHUD(
            recognitionControlMode: controlMode,
            computedTypingContext: computedTypingContext
        )
        if hasStrongTypingFallback {
            typingContext = computedTypingContext
        }
        typingContext = effectiveTypingContext(
            reconciledTypingContext: typingContext,
            computedTypingContext: computedTypingContext,
            availability: featureAvailability
        )
        if wakeArbitrationActive {
            typingContext = wakeArbitration.state == .dictationCommitted
        } else {
            if !typingContext,
               shouldUseWakeTypingFallback(
                   wakeLifecycleActive: wakeArbitrationActive,
                   recognitionControlMode: controlMode,
                   featureAvailability: featureAvailability,
                   liveTyping: liveTyping
               ) {
                typingContext = true
                GlobalLogger.speech.info(
                    "[TypingMode] restored wake-follow-up typing fallback targetPID=\(sessionTargetPID ?? 0) targetBundle=\(sessionTargetBundleID ?? "nil") liveTyping=\(liveTyping)"
                )
            }
            if !typingContext,
               Self.shouldPromoteInlineWakePayloadToTypingContext(
                   recognitionControlMode: controlMode,
                   dictationEnabled: featureAvailability.dictationEnabled,
                   wakeFollowUpActive: wakeArbitrationActive,
                   wakePayload: textToRoute,
                   hasAuthoritativeTypingEvidence: hasAuthoritativeTypingEvidence,
                   liveTyping: liveTyping,
                   commandLikely: wakePayloadLooksLikeCommand
               ) {
                typingContext = true
                GlobalLogger.speech.info(
                    "[TypingMode] promoted inline wake payload to typing context before final routing liveTyping=\(liveTyping) authoritativeFocus=\(hasAuthoritativeTypingEvidence)"
                )
            }
        }
        isDictating = typingContext && featureAvailability.dictationEnabled
        setAuthoritativeSessionTyping(typingContext, source: "speech.final-routing")
        if controlMode != .command, typingContext {
            syncSessionInputTargetFromCurrentFocus(resetDictationStream: dictationHandler.screenTypedText.isEmpty)
        }
        if controlMode == .auto,
           typingContext,
           hudState.recognitionControlMode == .command || !hudState.isTypingContext {
            GlobalLogger.speech.info("[TypingMode] ignoring stale HUD command block after typing reconciliation")
        }
        if controlMode == .auto,
           computedTypingContext,
           !typingContext,
           !hasStreamedDictation {
            GlobalLogger.speech.info("[TypingMode] HUD control state overrode stale typing context before final routing")
        }

        let consumedExplicitCommandPrefix =
            typingContext &&
            featureAvailability.commandEnabled &&
            consumePendingExplicitCommandPrefixIfNeeded()
        let routingDecision = Self.resolvedRoutingBias(
            recognitionControlMode: controlMode,
            typingContext: typingContext,
            dictationEnabled: featureAvailability.dictationEnabled,
            commandEnabled: featureAvailability.commandEnabled,
            consumeExplicitCommandPrefix: consumedExplicitCommandPrefix
        )
        let routingBias = routingDecision.bias
        let blockDictationWithoutInput = routingDecision.blockDictationWithoutInput

        if consumedExplicitCommandPrefix {
            GlobalLogger.router.info(
                "[Route] consumed pending explicit command prefix transcript='\(textToRoute)'"
            )
        }

        let correctionScope: SpeechCorrectionScope = switch routingBias {
        case .forceCommand, .commandPreferred:
            .command
        case .forceDictation, .dictationPreferred, .neutral:
            typingContext ? .dictation : .command
        }

        textToRoute = normalizeRecognizedText(textToRoute, scope: correctionScope).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !textToRoute.isEmpty else { return }

        if Self.shouldSuppressWakeFollowUpEcho(
            pendingWakePhrase: pendingWakeFollowUp?.phrase,
            routedTranscript: textToRoute,
            hasStreamedDictation: hasStreamedDictation
        ) {
            GlobalLogger.speech.info(
                "[WakeFollowUp] suppressed-wake-echo phrase='\(pendingWakeFollowUp?.phrase ?? "nil")' transcript='\(wakeDiagnosticSnippet(textToRoute))'"
            )
            return
        }

        if Self.isHiddenFocusedInputDiagnosticsCommand(textToRoute) {
            GlobalLogger.router.info("[Route] hidden focused-input diagnostics command matched transcript='\(textToRoute)'")
            NotificationCenter.default.post(name: .exportFocusedInputDiagnostics, object: nil)
            clearHUDOverride()
            refreshContinuousHUD(isDictating: false)
            return
        }

        if typingContext,
           featureAvailability.commandEnabled,
           isExplicitCommandPrefixOnly(textToRoute) {
            armPendingExplicitCommandPrefix(reason: "prefix-only-transcript")
            status = NSLocalizedString("speech.waiting_command", comment: "")
            clearHUDOverride()
            refreshContinuousHUD(isDictating: false)
            return
        }

        let candidateUtteranceID = utteranceID ?? activeUtteranceID
        let now = Date()
        if candidateUtteranceID > 0, sessionGeneration == lastHandledSessionGeneration,
           candidateUtteranceID == lastHandledUtteranceID, textToRoute == lastHandledTranscript,
           now.timeIntervalSince(lastHandledAt) < 2.0 { return }

        _ = refreshFrontmostAppCommands()
        let decision = commandRouter.routeDetailed(
            transcript: textToRoute,
            bias: routingBias,
            localeIdentifier: activeLocale.identifier
        )
        var intent = decision.intent

        GlobalLogger.router.info(
            "[Route] transcript='\(textToRoute)' mode=\(recognitionControlMode.rawValue) effective=\(controlMode.rawValue) typing=\(typingContext) bias=\(routingBiasSummary(routingBias)) confidence=\(decision.confidence.rawValue) intent=\(intentSummary(intent))"
        )

        if controlMode == .command,
           featureAvailability.commandEnabled,
           case .dictation(let payload) = intent {
            intent = .unknown(payload)
            GlobalLogger.router.info(
                "[Route] explicit command mode downgraded dictation -> unknown transcript='\(payload)'"
            )
        }

        if wakeArbitrationActive,
           wakeArbitration.state != .dictationCommitted,
           case .dictation(let payload) = intent {
            intent = .unknown(payload)
            GlobalLogger.router.info(
                "[Route] wake arbitration blocked uncommitted dictation -> unknown transcript='\(payload)' state=\(String(describing: wakeArbitration.state))"
            )
        }

        if featureAvailability.dictationEnabled,
           !featureAvailability.commandEnabled,
           typingContext {
            switch intent {
            case .dictation:
                break
            default:
                intent = .dictation(textToRoute)
                GlobalLogger.router.info(
                    "[Route] voice control disabled -> dictation transcript='\(textToRoute)'"
                )
            }
        }

        let isExplicitControlMode = featureAvailability.commandEnabled &&
            (controlMode == .command || routingBias == .forceCommand)
        if decision.confidence == .low,
           !typingContext,
           isCommandIntent(intent),
           !isExplicitControlMode {
            metrics.lowConfidenceCommandDowngrades += 1
            intent = .unknown(textToRoute)
            GlobalLogger.router.info(
                "[Route] downgraded low-confidence command -> unknown transcript='\(textToRoute)'"
            )
        }

        if blockDictationWithoutInput, case .dictation(let p) = intent {
            intent = .unknown(p)
            GlobalLogger.router.info(
                "[Route] blocked dictation without input -> unknown transcript='\(p)'"
            )
        }
        let isForcedCommandMiss = decision.reason == "forced-command-no-match"
        if consumedExplicitCommandPrefix && isForcedCommandMiss {
            armPendingExplicitCommandPrefix(reason: "forced-command-miss")
            GlobalLogger.router.info(
                "[Route] re-armed pending explicit command prefix after forced-command miss transcript='\(textToRoute)'"
            )
        }
        if case .toggleInputControlMode = intent {
            armPendingExplicitCommandPrefix(reason: "mode-switch-follow-up")
        }
        if !isAlwaysListeningEnabled,
           recognitionControlMode != .command,
           !blockDictationWithoutInput,
           case .unknown = intent,
           !textToRoute.isEmpty,
           typingContext,
           !isForcedCommandMiss {
            intent = .dictation(textToRoute)
            GlobalLogger.router.info(
                "[Route] fallback unknown -> dictation transcript='\(textToRoute)'"
            )
        }

        let explicitInlineCommandPrefix = Self.hasLeadingExplicitCommandPrefix(
            textToRoute,
            localeIdentifier: activeLocale.identifier,
            overrides: commandRouter.languageTermsOverrides
        )
        let commandHUDPreviewMessage =
            Self.shouldPreviewForcedCommandHUD(
                typingContext: typingContext,
                intent: intent,
                routingBias: routingBias,
                consumedExplicitCommandPrefix: consumedExplicitCommandPrefix,
                inlineExplicitCommandPrefix: explicitInlineCommandPrefix
            )
            ? Self.commandHUDPreviewMessage(for: intent, localeIdentifier: activeLocale.identifier)
            : nil

        noteIntentMetrics(intent)
        let completedWakeFollowUp = completePendingWakeFollowUpIfNeeded(intent: intent, transcript: textToRoute)

        if wakeWordDetected { lastWakeTime = Date() }
        else if case .unknown = intent { /* don't extend */ }
        else { lastWakeTime = Date() }

        var resolvedUID = utteranceID ?? activeUtteranceID
        if resolvedUID <= 0 { resolvedUID = nextUtteranceID; nextUtteranceID += 1; activeUtteranceID = resolvedUID }
        lastHandledSessionGeneration = sessionGeneration; lastHandledUtteranceID = resolvedUID
        lastHandledTranscript = textToRoute; lastHandledAt = now
        if case .dictation = intent, let completedWakeFollowUp {
            rememberWakeFollowUpDictationMarker(
                sessionGeneration: sessionGeneration,
                utteranceID: resolvedUID,
                groupID: completedWakeFollowUp.groupID
            )
        }

        primeQueuedHUDStage(
            for: intent,
            typingContext: typingContext,
            utteranceID: resolvedUID,
            sessionGeneration: sessionGeneration
        )

        enqueueIntentForParallelExecution(
            intent,
            typingContext: typingContext,
            utteranceID: resolvedUID,
            originSessionGeneration: sessionGeneration,
            spokenText: rawTrimmed,
            routeReason: decision.reason,
            commandHUDPreviewMessage: commandHUDPreviewMessage
        )
    }

    private func primeQueuedHUDStage(
        for intent: VoiceIntent,
        typingContext: Bool,
        utteranceID: Int,
        sessionGeneration: Int
    ) {
        guard utteranceID > 0 else { return }
        guard !shouldHoldTextRewriteBarrier(for: intent) else { return }

        let controlMode: HUDRecognitionControlMode = {
            if isCommandIntent(intent) { return .command }
            if typingContext { return .dictation }
            return .auto
        }()

        setHUDStage(
            owner: "job:\(sessionGeneration)#\(utteranceID)",
            mode: .organizing,
            controlMode: controlMode
        )
        status = organizingHUDStatus
    }

    private func enqueueIntentForParallelExecution(
        _ intent: VoiceIntent,
        typingContext: Bool,
        utteranceID: Int,
        originSessionGeneration: Int,
        spokenText: String?,
        routeReason: String,
        commandHUDPreviewMessage: String?
    ) {
        if shouldBlockIntentDuringTextRewrite(intent) {
            showTextRewriteBusyHUD()
            return
        }

        let localeID = activeLocale.identifier
        let typingTarget = typingContext ? resolvedTypingTargetSnapshot() : nil
        let resolvedPID = typingTarget?.pid
        let bid = typingTarget?.bundleID
        let fp = typingTarget?.elementFingerprint
        let source = typingTarget?.source
        let pid = typingContext
            ? preferredTypingInjectionTargetPID(resolvedPID, bundleID: bid)
            : normalizedInjectionTargetPID(resolvedPID, bundleID: bid)
        let verificationSnapshot = typingContext ? currentFocusedInputVerificationSnapshot() : nil
        let hydratedIntent = hydrateExecutionIntent(
            intent,
            typingContext: typingContext,
            verificationSnapshot: verificationSnapshot
        )
        let inputControlSnapshot = authoritativeInputControlSnapshot
        let holdsTextRewriteBarrier = shouldHoldTextRewriteBarrier(for: hydratedIntent)
        if holdsTextRewriteBarrier {
            beginTextRewriteHUDActivity()
        }
        let job = IntentJob(seq: -1, intent: hydratedIntent, localeIdentifier: localeID,
                            dictationEnhancementEnabled: isAutoDictationEnhancementEnabled,
                            fullTextRewriteEnabled: isFullTextRewriteEnabled,
                            originSessionGeneration: originSessionGeneration, utteranceID: utteranceID, inputControlSnapshot: inputControlSnapshot,
                            streamedTextSnapshot: dictationHandler.screenTypedText, screenTypedCount: dictationHandler.screenTypedText.count,
                            targetPID: pid, targetBundleID: bid, targetElementFingerprint: fp, targetSource: source, verificationSnapshot: verificationSnapshot,
                            holdsTextRewriteBarrier: holdsTextRewriteBarrier,
                            spokenText: spokenText, routeReason: routeReason, commandHUDPreviewMessage: commandHUDPreviewMessage)
        let targetBundleLog = bid ?? "nil"
        GlobalLogger.speech.info(
            "[IntentPipeline] enqueue utterance=\(utteranceID) session=\(originSessionGeneration) typing=\(typingContext) intent=\(intentSummary(hydratedIntent)) targetPID=\(pid ?? 0) targetBundle=\(targetBundleLog) targetSource=\(source?.rawValue ?? "nil")"
        )
        Task { [weak self] in
            guard let self else { return }
            let seq = await self.intentPipeline.allocateSeq()
            let seeded = IntentJob(seq: seq, intent: job.intent, localeIdentifier: job.localeIdentifier,
                                   dictationEnhancementEnabled: job.dictationEnhancementEnabled,
                                   fullTextRewriteEnabled: job.fullTextRewriteEnabled,
                                   originSessionGeneration: job.originSessionGeneration, utteranceID: job.utteranceID, inputControlSnapshot: job.inputControlSnapshot,
                                   streamedTextSnapshot: job.streamedTextSnapshot, screenTypedCount: job.screenTypedCount,
                                   targetPID: job.targetPID, targetBundleID: job.targetBundleID, targetElementFingerprint: job.targetElementFingerprint,
                                   targetSource: job.targetSource,
                                   verificationSnapshot: job.verificationSnapshot, holdsTextRewriteBarrier: job.holdsTextRewriteBarrier,
                                   spokenText: job.spokenText, routeReason: job.routeReason,
                                   commandHUDPreviewMessage: job.commandHUDPreviewMessage)
            Task.detached(priority: .userInitiated) { [weak self] in
                guard let self else { return }
                let processed = await self.processIntentJob(seeded)
                let ready = await self.intentPipeline.submit(processed)
                for r in ready { await MainActor.run { [weak self] in self?.applyProcessedJob(r) } }
            }
        }
    }

    private func hydrateExecutionIntent(
        _ intent: VoiceIntent,
        typingContext: Bool,
        verificationSnapshot: InputVerificationSnapshot?
    ) -> VoiceIntent {
        switch intent {
        case .rewriteText(let payload):
            return .rewriteText(
                hydrateRewritePayload(
                    payload,
                    typingContext: typingContext,
                    verificationSnapshot: verificationSnapshot
                )
            )
        default:
            return intent
        }
    }

    private func hydrateRewritePayload(
        _ payload: TextRewriteIntentPayload,
        typingContext: Bool,
        verificationSnapshot: InputVerificationSnapshot?
    ) -> TextRewriteIntentPayload {
        var hydrated = payload
        hydrated.resultText = nil

        guard typingContext else {
            hydrated.failureReason = .noInputTarget
            logTextRewriteFailure(
                .noInputTarget,
                phase: "prepare",
                payload: hydrated,
                note: "typing-context-missing"
            )
            return hydrated
        }

        guard let sourceText = captureRewriteSourceText(
            scope: payload.scope,
            verificationSnapshot: verificationSnapshot
        ) else {
            hydrated.failureReason = .unsupportedTarget
            logTextRewriteFailure(
                .unsupportedTarget,
                phase: "prepare",
                payload: hydrated,
                note: "capture-source-failed"
            )
            return hydrated
        }

        if sourceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            hydrated.failureReason = .sourceEmpty
            logTextRewriteFailure(
                .sourceEmpty,
                phase: "prepare",
                payload: hydrated,
                sourceCount: sourceText.count
            )
            return hydrated
        }

        if sourceText.count > maxTextRewriteSourceCharacters {
            hydrated.failureReason = .sourceTooLong
            logTextRewriteFailure(
                .sourceTooLong,
                phase: "prepare",
                payload: hydrated,
                sourceCount: sourceText.count
            )
            return hydrated
        }

        hydrated.sourceText = sourceText
        hydrated.failureReason = nil
        return hydrated
    }

    private func captureRewriteSourceText(
        scope: TextRewriteScope,
        verificationSnapshot: InputVerificationSnapshot?
    ) -> String? {
        switch scope {
        case .fullDocument:
            return verificationSnapshot?.valueText
        }
    }

    private func handleFrontmostApplicationChanged() {
        guard isAlwaysListeningEnabled else { return }

        // App switches frequently invalidate the previously locked AX target while the wake window is still open.
        // Re-arm against the current focus so the next utterance does not keep routing to a stale element.
        clearStandbyTypingStateIfNeeded(reason: "frontmost-app-changed")
        clearSessionInputTarget(reason: "frontmost-app-changed")
        clearRecentWakeFollowUpDictationSuppression(reason: "frontmost-app-changed")
        refreshArmedInputTargetIfNeeded(reason: "frontmost-app-changed")
        reconcileTypingModeAfterFrontmostApplicationChange()
        refreshContinuousHUD(isDictating: false)
        ensureRecognitionSessionForVisibleHUD(reason: "frontmost-app-changed")

        if isWeChatAppWideInputModeEnabled(),
           Date().timeIntervalSince(lastFocusToastAt) > 6.0 {
            lastFocusToastAt = Date()
            HUDManager.shared.showTemporary(
                message: activeLocale.identifier.hasPrefix("zh")
                    ? "微信输入中，命令前加“命令”"
                    : "WeChat input mode. Prefix commands with “Command”",
                recognitionControlMode: .auto,
                duration: 1.8
            )
        }
    }

    private func reconcileTypingModeAfterFrontmostApplicationChange() {
        guard recognitionControlMode == .auto else { return }
        guard dictationHandler.screenTypedText.isEmpty else { return }
        guard sessionTypingMode || pendingWakeFollowUp != nil || isUtteranceActive else { return }

        if shouldForceStandbyCommandTypingState() {
            clearStandbyTypingStateIfNeeded(reason: "frontmost-app-changed-standby")
            return
        }

        if isTypingRecoveryHoldActive {
            endTypingRecoveryHold(reason: "frontmost-app-changed")
        }

        resetTypingStateCache()
        let refreshedTypingMode = isTypingMode
        guard refreshedTypingMode != sessionTypingMode else { return }

        let frontmostBundle = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "nil"
        GlobalLogger.speech.info(
            "[TypingMode] frontmost-app change reconciled \(sessionTypingMode)->\(refreshedTypingMode) pendingWake=\(pendingWakeFollowUp != nil) utteranceActive=\(isUtteranceActive) frontmostBundle=\(frontmostBundle)"
        )
        isDictating = refreshedTypingMode && currentVoiceFeatureAvailability().dictationEnabled
        setAuthoritativeSessionTyping(refreshedTypingMode, source: "speech.frontmost-app-changed")
    }

    private func shouldKeepWakeHUDArmed() -> Bool {
        // Wake-word mode intentionally hides the HUD while idle, but continuous
        // recognition still has to stay armed so the next wake word is not dropped.
        isAlwaysListeningEnabled || isWakeWordEnabled
    }

    private func ensureRecognitionSessionForVisibleHUD(reason: String) {
        guard shouldKeepWakeHUDArmed() else { return }
        guard !recognitionSession.isRunning, !isStopping else {
            logWakeArmStateIfNeeded(reason: reason, outcome: "skip-already-running-or-stopping")
            return
        }
        guard pendingEngineRestartWorkItem == nil else {
            logWakeArmStateIfNeeded(reason: reason, outcome: "blocked-pending-engine-restart")
            return
        }

        let now = Date()
        guard now >= routeRebuildGraceUntil,
              now >= continuousRecoveryGraceUntil,
              now >= recognitionUnavailableUntil else {
            var blockers: [String] = []
            if now < routeRebuildGraceUntil {
                blockers.append("routeGrace=\(wakeDiagnosticRemainingDescription(until: routeRebuildGraceUntil))")
            }
            if now < continuousRecoveryGraceUntil {
                blockers.append("recoveryGrace=\(wakeDiagnosticRemainingDescription(until: continuousRecoveryGraceUntil))")
            }
            if now < recognitionUnavailableUntil {
                blockers.append("recognizerUnavailable=\(wakeDiagnosticRemainingDescription(until: recognitionUnavailableUntil))")
            }
            logWakeArmStateIfNeeded(
                reason: reason,
                outcome: "blocked-\(blockers.joined(separator: ","))"
            )
            return
        }

        GlobalLogger.speech.info("[ASR Session] rearm visible HUD reason=\(reason) awake=\(isAwake) direct=\(isDirectCommandEnabled)")
        logWakeArmStateIfNeeded(reason: reason, outcome: "schedule-continuous-recovery")
        scheduleContinuousRecovery(delay: 0.05)
    }

    private func refreshArmedInputTargetIfNeeded(reason: String) {
        guard shouldKeepWakeHUDArmed() else { return }
        guard !isUtteranceActive, !isStopping else { return }
        guard shouldAllowIdleTargetRearm(reason: reason) else { return }
        guard hasAuthoritativeTypingEvidence() else { return }
        guard let snapshot = currentFocusedInputSnapshot() else { return }

        let changed = sessionTargetPID != snapshot.pid
            || sessionTargetBundleID != snapshot.bundleID
            || sessionTargetElementFingerprint != snapshot.elementFingerprint
        guard changed else { return }

        GlobalLogger.speech.info(
            "[TypingTarget] rearm focused target reason=\(reason) pid=\(snapshot.pid) bundle=\(snapshot.bundleID ?? "nil")"
        )
        rearmInputTarget(reason: reason)
    }

    private func armWakeTypingFallback(reason: String) {
        guard sessionTargetPID != nil || sessionTargetBundleID != nil || sessionTargetElementFingerprint != nil else {
            clearWakeTypingFallback(reason: "no-session-target")
            return
        }
        wakeTypingFallbackUntil = Date().addingTimeInterval(wakeTypingFallbackWindow)
        GlobalLogger.speech.info(
            "[TypingMode] armed wake typing fallback reason=\(reason) targetPID=\(sessionTargetPID ?? 0) targetBundle=\(sessionTargetBundleID ?? "nil")"
        )
    }

    private func clearWakeTypingFallback(reason: String) {
        guard wakeTypingFallbackUntil != .distantPast else { return }
        wakeTypingFallbackUntil = .distantPast
        GlobalLogger.speech.info("[TypingMode] cleared wake typing fallback reason=\(reason)")
    }

    private func clearSessionInputTarget(reason: String) {
        let hadTarget =
            sessionTargetPID != nil
            || sessionTargetBundleID != nil
            || sessionTargetElementFingerprint != nil
        let hadWakeFallback = wakeTypingFallbackUntil != .distantPast
        guard hadTarget || hadWakeFallback else { return }

        sessionTargetPID = nil
        sessionTargetBundleID = nil
        sessionTargetElementFingerprint = nil
        sessionTargetSource = nil
        didLogSessionTargetMismatch = false
        wakeTypingFallbackUntil = .distantPast
        GlobalLogger.speech.info("[TypingTarget] cleared session target reason=\(reason)")
    }

    private func shouldForceStandbyCommandTypingState() -> Bool {
        guard recognitionControlMode == .auto else { return false }
        guard isAlwaysListeningEnabled, isWakeWordEnabled, !isAwake, !isDirectCommandEnabled else {
            return false
        }
        guard pendingWakeFollowUp == nil else { return false }
        guard recentExpiredWakeFollowUp == nil else { return false }
        guard dictationHandler.screenTypedText.isEmpty else { return false }
        return true
    }

    private func clearStandbyTypingStateIfNeeded(reason: String) {
        guard shouldForceStandbyCommandTypingState() else { return }
        let hadTypingState = sessionTypingMode || isDictating
        let hadTarget =
            sessionTargetPID != nil
            || sessionTargetBundleID != nil
            || sessionTargetElementFingerprint != nil
            || wakeTypingFallbackUntil != .distantPast
        guard hadTypingState || hadTarget else { return }
        isDictating = false
        clearSessionInputTarget(reason: reason)
        GlobalLogger.speech.info("[TypingMode] cleared standby typing state reason=\(reason)")
        setAuthoritativeSessionTyping(false, source: "speech.clear-standby-typing")
    }

    private func shouldAllowIdleTargetRearm(reason: String) -> Bool {
        let availability = currentVoiceFeatureAvailability()
        switch effectiveRecognitionControlMode(for: availability) {
        case .dictation:
            return true
        case .command:
            return false
        case .auto:
            if pendingWakeFollowUp != nil { return true }
            if !dictationHandler.screenTypedText.isEmpty { return true }
            if hasRecentClickTypingFallbackEvidence() { return true }
            if HUDManager.shared.hasRecentExplicitTypingClickReentry() { return true }
            if isWeChatSpecialModeActive() { return true }
            return reason == "wake-window-open"
                || reason == "wake-activation"
        }
    }

    private func rememberWakeFollowUpDictationMarker(
        sessionGeneration: Int,
        utteranceID: Int,
        groupID: String
    ) {
        wakeFollowUpDictationMarkers["\(sessionGeneration)#\(utteranceID)"] = groupID
    }

    private func consumeWakeFollowUpDictationMarker(
        sessionGeneration: Int,
        utteranceID: Int
    ) -> String? {
        wakeFollowUpDictationMarkers.removeValue(forKey: "\(sessionGeneration)#\(utteranceID)")
    }

    private func armRecentWakeFollowUpDictationSuppressionIfNeeded(
        _ text: String,
        for job: ProcessedJob,
        groupID: String?
    ) {
        guard let groupID else { return }

        let textKey = Self.wakeFollowUpComparisonKey(text)
        guard !textKey.isEmpty else { return }

        recentWakeFollowUpDictationSuppression = RecentWakeFollowUpDictationSuppression(
            groupID: groupID,
            textKey: textKey,
            pid: job.targetPID,
            bundleID: job.targetBundleID,
            elementFingerprint: job.targetElementFingerprint,
            expiresAt: Date().addingTimeInterval(wakeFollowUpDuplicateSuppressionWindow)
        )
        GlobalLogger.speech.info(
            "[WakeFollowUp] armed-duplicate-suppression group=\(groupID) utterance=\(job.utteranceID) targetPID=\(job.targetPID ?? 0) bundle=\(job.targetBundleID ?? "nil")"
        )
    }

    private func shouldSuppressRecentWakeFollowUpDuplicate(
        _ text: String,
        for job: ProcessedJob
    ) -> Bool {
        guard let suppression = recentWakeFollowUpDictationSuppression else { return false }
        guard Date() <= suppression.expiresAt else {
            clearRecentWakeFollowUpDictationSuppression(reason: "expired")
            return false
        }

        let sameFingerprint = suppression.elementFingerprint != nil
            && suppression.elementFingerprint == job.targetElementFingerprint
        let samePID = suppression.pid != nil && suppression.pid == job.targetPID
        let sameBundleOnly = suppression.bundleID != nil
            && suppression.bundleID == job.targetBundleID
            && suppression.pid == nil
            && job.targetPID == nil
            && suppression.elementFingerprint == nil
            && job.targetElementFingerprint == nil
        guard sameFingerprint || samePID || sameBundleOnly else { return false }

        guard suppression.textKey == Self.wakeFollowUpComparisonKey(text) else { return false }

        clearRecentWakeFollowUpDictationSuppression(reason: "duplicate-consumed")
        GlobalLogger.speech.info(
            "[WakeFollowUp] suppressed-duplicate-dictation group=\(suppression.groupID) utterance=\(job.utteranceID) targetPID=\(job.targetPID ?? 0) bundle=\(job.targetBundleID ?? "nil")"
        )
        return true
    }

    private func clearRecentWakeFollowUpDictationSuppression(reason: String) {
        guard recentWakeFollowUpDictationSuppression != nil else { return }
        recentWakeFollowUpDictationSuppression = nil
        GlobalLogger.speech.info("[WakeFollowUp] cleared-duplicate-suppression reason=\(reason)")
    }

    private func resolvedTypingTargetSnapshot() -> FocusedInputSnapshot? {
        let current = currentFocusedInputSnapshot()

        guard let current else {
            if sessionTargetPID == nil || sessionTargetPID == 0 {
                return nil
            }
            return FocusedInputSnapshot(
                pid: sessionTargetPID ?? 0,
                bundleID: sessionTargetBundleID,
                elementFingerprint: sessionTargetElementFingerprint,
                source: sessionTargetSource ?? .accessibility,
                windowTitle: nil,
                anchorPoint: nil
            )
        }

        return current
    }

    private func processIntentJob(_ job: IntentJob) async -> ProcessedJob {
        let stageOwner = hudStageOwner(for: job)
        if !job.holdsTextRewriteBarrier {
            let stageControlMode: HUDRecognitionControlMode = {
                if isCommandIntent(job.intent) { return .command }
                if job.typingInteraction { return .dictation }
                return .auto
            }()
            setHUDStage(
                owner: stageOwner,
                mode: .organizing,
                controlMode: stageControlMode
            )
            status = organizingHUDStatus
        }
        let llmBundleIDs = VoiceLexiconSupport.uniqueTerms(
            ([job.targetBundleID].compactMap { $0 } + currentContextBundleIDs()).map { $0.lowercased() }
        )

        if case .dictation(let text) = job.intent {
            let sourceText = text.trimmingCharacters(in: .whitespacesAndNewlines)
            func passthroughResult(_ diagnostics: String, enhancedContent: String? = nil) -> ProcessedJob {
                ProcessedJob(
                    seq: job.seq,
                    intent: .dictation(text),
                    localeIdentifier: job.localeIdentifier,
                    originSessionGeneration: job.originSessionGeneration,
                    utteranceID: job.utteranceID,
                    inputControlSnapshot: job.inputControlSnapshot,
                    streamedTextSnapshot: job.streamedTextSnapshot,
                    screenTypedCount: job.screenTypedCount,
                    targetPID: job.targetPID,
                    targetBundleID: job.targetBundleID,
                    targetElementFingerprint: job.targetElementFingerprint,
                    targetSource: job.targetSource,
                    verificationSnapshot: job.verificationSnapshot,
                    holdsTextRewriteBarrier: job.holdsTextRewriteBarrier,
                    diagnostics: diagnostics,
                    spokenText: job.spokenText,
                    originalContent: sourceText,
                    enhancedContent: enhancedContent,
                    routeReason: job.routeReason,
                    commandHUDPreviewMessage: job.commandHUDPreviewMessage
                )
            }

            guard job.dictationEnhancementEnabled else {
                return passthroughResult("llm=disabled")
            }
            guard job.typingInteraction else {
                return passthroughResult("llm=skipped-no-typing")
            }
            if let skipReason = Self.dictationEnhancementSkipReason(
                text: text,
                localeIdentifier: job.localeIdentifier
            ) {
                return passthroughResult("llm=skipped-\(skipReason)")
            }
            guard let llmProvider = contextualLLMProvider(
                for: .dictationEnhancement,
                bundleIDs: llmBundleIDs
            ) else {
                logDictationEnhancementFailure(
                    phase: "process",
                    job: job,
                    textCount: text.count,
                    note: "provider-unavailable"
                )
                return passthroughResult("llm=provider-unavailable")
            }

            do {
                let enhanced = try await llmProvider.enhanceDictation(text)
                switch Self.validateDictationEnhancement(
                    sourceText: text,
                    candidateText: enhanced,
                    localeIdentifier: job.localeIdentifier
                ) {
                case .accept(let finalText, let changed):
                    return ProcessedJob(
                        seq: job.seq,
                        intent: .dictation(finalText),
                        localeIdentifier: job.localeIdentifier,
                        originSessionGeneration: job.originSessionGeneration,
                        utteranceID: job.utteranceID,
                        inputControlSnapshot: job.inputControlSnapshot,
                        streamedTextSnapshot: job.streamedTextSnapshot,
                        screenTypedCount: job.screenTypedCount,
                        targetPID: job.targetPID,
                        targetBundleID: job.targetBundleID,
                        targetElementFingerprint: job.targetElementFingerprint,
                        targetSource: job.targetSource,
                        verificationSnapshot: job.verificationSnapshot,
                        holdsTextRewriteBarrier: job.holdsTextRewriteBarrier,
                        diagnostics: changed ? "llm=applied" : "llm=unchanged",
                        spokenText: job.spokenText,
                        originalContent: sourceText,
                        enhancedContent: finalText,
                        routeReason: job.routeReason,
                        commandHUDPreviewMessage: job.commandHUDPreviewMessage
                    )
                case .reject(let reason):
                    GlobalLogger.speech.info(
                        "[DictationLLM] rejected phase=process reason=\(reason) \(llmProviderDiagnosticsContext(for: .dictationEnhancement, utteranceID: job.utteranceID, typing: job.typingInteraction, targetPID: job.targetPID, bundleID: job.targetBundleID, sourceCount: text.count))"
                    )
                    return passthroughResult("llm=rejected-\(reason)", enhancedContent: enhanced.trimmingCharacters(in: .whitespacesAndNewlines))
                }
            } catch {
                logDictationEnhancementFailure(
                    phase: "process",
                    job: job,
                    textCount: text.count,
                    error: error
                )
                return passthroughResult("llm=provider-failed")
            }
        }
        if case .rewriteText(var payload) = job.intent {
            if let failureReason = payload.failureReason {
                logTextRewriteFailure(
                    failureReason,
                    phase: "prepare",
                    utteranceID: job.utteranceID,
                    typing: job.typingInteraction,
                    targetPID: job.targetPID,
                    bundleID: job.targetBundleID,
                    payload: payload,
                    sourceCount: payload.sourceText?.count
                )
                return ProcessedJob(
                    seq: job.seq,
                    intent: .rewriteText(payload),
                    localeIdentifier: job.localeIdentifier,
                    originSessionGeneration: job.originSessionGeneration,
                    utteranceID: job.utteranceID,
                    inputControlSnapshot: job.inputControlSnapshot,
                    streamedTextSnapshot: job.streamedTextSnapshot,
                    screenTypedCount: job.screenTypedCount,
                    targetPID: job.targetPID,
                    targetBundleID: job.targetBundleID,
                    targetElementFingerprint: job.targetElementFingerprint,
                    targetSource: job.targetSource,
                    verificationSnapshot: job.verificationSnapshot,
                    holdsTextRewriteBarrier: job.holdsTextRewriteBarrier,
                    diagnostics: "rewrite=\(failureReason.rawValue)",
                    spokenText: job.spokenText,
                    originalContent: nil,
                    enhancedContent: nil,
                    routeReason: job.routeReason,
                    commandHUDPreviewMessage: job.commandHUDPreviewMessage
                )
            }
            guard job.fullTextRewriteEnabled,
                  let llmProvider = contextualLLMProvider(
                    for: .fullTextRewrite,
                    bundleIDs: llmBundleIDs
                  ) else {
                payload.failureReason = .llmUnavailable
                logTextRewriteFailure(
                    .llmUnavailable,
                    phase: "execute",
                    utteranceID: job.utteranceID,
                    typing: job.typingInteraction,
                    targetPID: job.targetPID,
                    bundleID: job.targetBundleID,
                    payload: payload,
                    sourceCount: payload.sourceText?.count,
                    note: job.fullTextRewriteEnabled ? "provider-unavailable" : "rewrite-disabled"
                )
                return ProcessedJob(
                    seq: job.seq,
                    intent: .rewriteText(payload),
                    localeIdentifier: job.localeIdentifier,
                    originSessionGeneration: job.originSessionGeneration,
                    utteranceID: job.utteranceID,
                    inputControlSnapshot: job.inputControlSnapshot,
                    streamedTextSnapshot: job.streamedTextSnapshot,
                    screenTypedCount: job.screenTypedCount,
                    targetPID: job.targetPID,
                    targetBundleID: job.targetBundleID,
                    targetElementFingerprint: job.targetElementFingerprint,
                    targetSource: job.targetSource,
                    verificationSnapshot: job.verificationSnapshot,
                    holdsTextRewriteBarrier: job.holdsTextRewriteBarrier,
                    diagnostics: "rewrite=llm-unavailable",
                    spokenText: job.spokenText,
                    originalContent: nil,
                    enhancedContent: nil,
                    routeReason: job.routeReason,
                    commandHUDPreviewMessage: job.commandHUDPreviewMessage
                )
            }
            guard let sourceText = payload.sourceText else {
                payload.failureReason = .unsupportedTarget
                logTextRewriteFailure(
                    .unsupportedTarget,
                    phase: "execute",
                    utteranceID: job.utteranceID,
                    typing: job.typingInteraction,
                    targetPID: job.targetPID,
                    bundleID: job.targetBundleID,
                    payload: payload,
                    note: "missing-source-text"
                )
                return ProcessedJob(
                    seq: job.seq,
                    intent: .rewriteText(payload),
                    localeIdentifier: job.localeIdentifier,
                    originSessionGeneration: job.originSessionGeneration,
                    utteranceID: job.utteranceID,
                    inputControlSnapshot: job.inputControlSnapshot,
                    streamedTextSnapshot: job.streamedTextSnapshot,
                    screenTypedCount: job.screenTypedCount,
                    targetPID: job.targetPID,
                    targetBundleID: job.targetBundleID,
                    targetElementFingerprint: job.targetElementFingerprint,
                    targetSource: job.targetSource,
                    verificationSnapshot: job.verificationSnapshot,
                    holdsTextRewriteBarrier: job.holdsTextRewriteBarrier,
                    diagnostics: "rewrite=missing-source",
                    spokenText: job.spokenText,
                    originalContent: nil,
                    enhancedContent: nil,
                    routeReason: job.routeReason,
                    commandHUDPreviewMessage: job.commandHUDPreviewMessage
                )
            }
            do {
                let rewritten = try await llmProvider.rewriteText(sourceText, mode: payload.mode)
                payload.resultText = rewritten.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? sourceText : rewritten
                payload.failureReason = nil
                return ProcessedJob(
                    seq: job.seq,
                    intent: .rewriteText(payload),
                    localeIdentifier: job.localeIdentifier,
                    originSessionGeneration: job.originSessionGeneration,
                    utteranceID: job.utteranceID,
                    inputControlSnapshot: job.inputControlSnapshot,
                    streamedTextSnapshot: job.streamedTextSnapshot,
                    screenTypedCount: job.screenTypedCount,
                    targetPID: job.targetPID,
                    targetBundleID: job.targetBundleID,
                    targetElementFingerprint: job.targetElementFingerprint,
                    targetSource: job.targetSource,
                    verificationSnapshot: job.verificationSnapshot,
                    holdsTextRewriteBarrier: job.holdsTextRewriteBarrier,
                    diagnostics: "rewrite=ok",
                    spokenText: job.spokenText,
                    originalContent: nil,
                    enhancedContent: rewritten.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? sourceText : rewritten,
                    routeReason: job.routeReason,
                    commandHUDPreviewMessage: job.commandHUDPreviewMessage
                )
            } catch {
                let failureReason = textRewriteFailureReason(for: error)
                payload.failureReason = failureReason
                logTextRewriteFailure(
                    failureReason,
                    phase: "execute",
                    utteranceID: job.utteranceID,
                    typing: job.typingInteraction,
                    targetPID: job.targetPID,
                    bundleID: job.targetBundleID,
                    payload: payload,
                    sourceCount: sourceText.count,
                    error: error
                )
                return ProcessedJob(
                    seq: job.seq,
                    intent: .rewriteText(payload),
                    localeIdentifier: job.localeIdentifier,
                    originSessionGeneration: job.originSessionGeneration,
                    utteranceID: job.utteranceID,
                    inputControlSnapshot: job.inputControlSnapshot,
                    streamedTextSnapshot: job.streamedTextSnapshot,
                    screenTypedCount: job.screenTypedCount,
                    targetPID: job.targetPID,
                    targetBundleID: job.targetBundleID,
                    targetElementFingerprint: job.targetElementFingerprint,
                    targetSource: job.targetSource,
                    verificationSnapshot: job.verificationSnapshot,
                    holdsTextRewriteBarrier: job.holdsTextRewriteBarrier,
                    diagnostics: failureReason == .timedOut ? "rewrite=timed-out" : "rewrite=provider-failed",
                    spokenText: job.spokenText,
                    originalContent: nil,
                    enhancedContent: nil,
                    routeReason: job.routeReason,
                    commandHUDPreviewMessage: job.commandHUDPreviewMessage
                )
            }
        }
        return ProcessedJob(seq: job.seq, intent: job.intent, localeIdentifier: job.localeIdentifier,
                            originSessionGeneration: job.originSessionGeneration, utteranceID: job.utteranceID,
                            inputControlSnapshot: job.inputControlSnapshot, streamedTextSnapshot: job.streamedTextSnapshot,
                            screenTypedCount: job.screenTypedCount, targetPID: job.targetPID,
                            targetBundleID: job.targetBundleID, targetElementFingerprint: job.targetElementFingerprint,
                            targetSource: job.targetSource,
                            verificationSnapshot: job.verificationSnapshot, holdsTextRewriteBarrier: job.holdsTextRewriteBarrier,
                            diagnostics: nil, spokenText: job.spokenText,
                            originalContent: nil,
                            enhancedContent: nil,
                            routeReason: job.routeReason, commandHUDPreviewMessage: job.commandHUDPreviewMessage)
    }

    private func applyProcessedJob(_ job: ProcessedJob) {
        guard utteranceExecutionGuard.shouldExecute(sessionGeneration: job.originSessionGeneration, utteranceID: job.utteranceID) else {
            if job.holdsTextRewriteBarrier {
                endTextRewriteHUDActivity()
            }
            return
        }
        let phaseOwner = hudStageOwner(for: job)
        let diagnosticsLog = job.diagnostics ?? "nil"
        let usageContext = resolvedUsageAppContext(for: job)
        GlobalLogger.speech.info(
            "[IntentPipeline] apply seq=\(job.seq) utterance=\(job.utteranceID) typing=\(job.typingInteraction) intent=\(intentSummary(job.intent)) targetSource=\(job.targetSource?.rawValue ?? "nil") diagnostics=\(diagnosticsLog)"
        )
        func finishWithFeedback(
            _ message: String,
            controlMode: HUDRecognitionControlMode,
            preserveStageUntilFeedback: Bool = false
        ) {
            status = message
            if !preserveStageUntilFeedback {
                clearHUDStage(owner: phaseOwner)
            }
            clearHandledCommandPreview()
            HUDManager.shared.showTemporary(
                message: message,
                recognitionControlMode: controlMode,
                icon: hudInputIcon()
            )
        }
        if let commandHUDPreviewMessage = job.commandHUDPreviewMessage,
           !commandHUDPreviewMessage.isEmpty {
            HUDManager.shared.showTemporary(
                message: commandHUDPreviewMessage,
                recognitionControlMode: .command,
                icon: hudInputIcon()
            )
        }
        revertStreamedDictationIfNeeded(for: job)
        if case .dictation(let text) = job.intent,
           !(isDictationExecutionEnabled?() ?? true) {
            revertBlockedDictationIfNeeded(for: job)
            let feedback = currentVoiceBlockFeedback(
                featureDisabledMessageKey: "speech.voice_input_disabled",
                featureDisabledLogReason: "voice input disabled"
            )
            GlobalLogger.speech.info(
                "[IntentPipeline] dictation blocked: \(feedback.logReason) utterance=\(job.utteranceID)"
            )
            if let analyticsReason = feedback.analyticsReason {
                onRecognitionFailure?(text, analyticsReason, usageContext.appName, usageContext.bundleIdentifier)
            }
            status = feedback.message
            clearHUDStage(owner: phaseOwner)
            HUDManager.shared.showTemporary(
                message: feedback.message,
                recognitionControlMode: .dictation,
                icon: hudInputIcon()
            )
            clearHandledCommandPreview()
            return
        }
        if isCommandIntent(job.intent),
           !(isCommandExecutionEnabled?() ?? true) {
            let feedback = currentVoiceBlockFeedback(
                featureDisabledMessageKey: "speech.voice_control_disabled",
                featureDisabledLogReason: "voice control disabled"
            )
            GlobalLogger.speech.info(
                "[IntentPipeline] command blocked: \(feedback.logReason) utterance=\(job.utteranceID) intent=\(intentSummary(job.intent))"
            )
            status = feedback.message
            if job.holdsTextRewriteBarrier {
                endTextRewriteHUDActivity()
            }
            clearHUDStage(owner: phaseOwner)
            clearHandledCommandPreview()
            HUDManager.shared.showTemporary(
                message: feedback.message,
                recognitionControlMode: .command,
                icon: hudInputIcon()
            )
            return
        }
        switch job.intent {
        case .undo:
            setHUDStage(owner: phaseOwner, mode: .executing, controlMode: .command)
            status = executingHUDStatus
            injector.undoPasteIfRecent()
            onIntent?(.undo, usageContext.appName, usageContext.bundleIdentifier, job.spokenText, job.originalContent, job.enhancedContent, job.diagnostics, nil)
            finishWithFeedback(NSLocalizedString("speech.undo_done", comment: ""), controlMode: .command)
        case .paste:
            setHUDStage(owner: phaseOwner, mode: .executing, controlMode: .command)
            status = executingHUDStatus
            AutomationOutputs.shared.pasteFromClipboard()
            onIntent?(.paste, usageContext.appName, usageContext.bundleIdentifier, job.spokenText, job.originalContent, job.enhancedContent, job.diagnostics, nil)
            finishWithFeedback(NSLocalizedString("speech.pasted_cmdv", comment: ""), controlMode: .command)
        case .clearInput:
            setHUDStage(owner: phaseOwner, mode: .executing, controlMode: .command)
            status = executingHUDStatus
            let selectAll = HotkeyBinding(keyCode: kVK_ANSI_A, modifiers: CGEventFlags.maskCommand.rawValue)
            let injectionPID = preferredTypingInjectionTargetPID(job.targetPID, bundleID: job.targetBundleID)
            AutomationOutputs.shared.pressShortcut(selectAll, targetPID: injectionPID)
            AutomationOutputs.shared.backspace(count: 1, targetPID: injectionPID)
            onIntent?(.clearInput, usageContext.appName, usageContext.bundleIdentifier, job.spokenText, job.originalContent, job.enhancedContent, job.diagnostics, nil)
            finishWithFeedback(NSLocalizedString("speech.done", comment: ""), controlMode: .command)
        case .deleteBackward(let count):
            setHUDStage(owner: phaseOwner, mode: .executing, controlMode: .command)
            status = executingHUDStatus
            let injectionPID = preferredTypingInjectionTargetPID(job.targetPID, bundleID: job.targetBundleID)
            AutomationOutputs.shared.backspace(count: count, targetPID: injectionPID)
            onIntent?(.deleteBackward(count), usageContext.appName, usageContext.bundleIdentifier, job.spokenText, job.originalContent, job.enhancedContent, job.diagnostics, nil)
            finishWithFeedback(NSLocalizedString("speech.done", comment: ""), controlMode: .command)
        case .moveCursorHorizontally(let offset):
            setHUDStage(owner: phaseOwner, mode: .executing, controlMode: .command)
            status = executingHUDStatus
            let injectionPID = preferredTypingInjectionTargetPID(job.targetPID, bundleID: job.targetBundleID)
            let binding = HotkeyBinding(
                keyCode: offset >= 0 ? kVK_RightArrow : kVK_LeftArrow,
                modifiers: 0
            )
            for _ in 0..<min(abs(offset), 200) {
                AutomationOutputs.shared.pressShortcut(binding, targetPID: injectionPID)
            }
            onIntent?(.moveCursorHorizontally(offset), usageContext.appName, usageContext.bundleIdentifier, job.spokenText, job.originalContent, job.enhancedContent, job.diagnostics, nil)
            finishWithFeedback(NSLocalizedString("speech.done", comment: ""), controlMode: .command)
        case .selectHorizontally(let offset):
            setHUDStage(owner: phaseOwner, mode: .executing, controlMode: .command)
            status = executingHUDStatus
            let injectionPID = preferredTypingInjectionTargetPID(job.targetPID, bundleID: job.targetBundleID)
            let binding = HotkeyBinding(
                keyCode: offset >= 0 ? kVK_RightArrow : kVK_LeftArrow,
                modifiers: CGEventFlags.maskShift.rawValue
            )
            for _ in 0..<min(abs(offset), 200) {
                AutomationOutputs.shared.pressShortcut(binding, targetPID: injectionPID)
            }
            onIntent?(.selectHorizontally(offset), usageContext.appName, usageContext.bundleIdentifier, job.spokenText, job.originalContent, job.enhancedContent, job.diagnostics, nil)
            finishWithFeedback(NSLocalizedString("speech.done", comment: ""), controlMode: .command)
        case .rewriteText(let payload):
            defer {
                if job.holdsTextRewriteBarrier {
                    endTextRewriteHUDActivity()
                }
            }
            guard let sourceText = payload.sourceText else {
                logTextRewriteFailure(
                    payload.failureReason ?? .unsupportedTarget,
                    phase: "apply",
                    utteranceID: job.utteranceID,
                    typing: job.typingInteraction,
                    targetPID: job.targetPID,
                    bundleID: job.targetBundleID,
                    payload: payload,
                    note: "missing-source-text"
                )
                status = textRewriteFailureMessage(payload.failureReason ?? .unsupportedTarget)
                clearHUDStage(owner: phaseOwner)
                HUDManager.shared.showTemporary(
                    message: status,
                    recognitionControlMode: .command,
                    icon: hudInputIcon()
                )
                clearHandledCommandPreview()
                return
            }

            if let failureReason = payload.failureReason {
                logTextRewriteFailure(
                    failureReason,
                    phase: "apply",
                    utteranceID: job.utteranceID,
                    typing: job.typingInteraction,
                    targetPID: job.targetPID,
                    bundleID: job.targetBundleID,
                    payload: payload,
                    sourceCount: sourceText.count
                )
                status = textRewriteFailureMessage(failureReason)
                clearHUDStage(owner: phaseOwner)
                HUDManager.shared.showTemporary(
                    message: status,
                    recognitionControlMode: .command,
                    icon: hudInputIcon()
                )
                clearHandledCommandPreview()
                return
            }

            guard let rewrittenText = payload.resultText else {
                logTextRewriteFailure(
                    .providerFailed,
                    phase: "apply",
                    utteranceID: job.utteranceID,
                    typing: job.typingInteraction,
                    targetPID: job.targetPID,
                    bundleID: job.targetBundleID,
                    payload: payload,
                    sourceCount: sourceText.count,
                    note: "missing-result-text"
                )
                status = textRewriteFailureMessage(.providerFailed)
                clearHUDStage(owner: phaseOwner)
                HUDManager.shared.showTemporary(
                    message: status,
                    recognitionControlMode: .command,
                    icon: hudInputIcon()
                )
                clearHandledCommandPreview()
                return
            }

            guard isJobInputTargetValidForInjection(job) else {
                logTextRewriteFailure(
                    .inputInvalid,
                    phase: "apply",
                    utteranceID: job.utteranceID,
                    typing: job.typingInteraction,
                    targetPID: job.targetPID,
                    bundleID: job.targetBundleID,
                    payload: payload,
                    sourceCount: sourceText.count
                )
                status = textRewriteFailureMessage(.inputInvalid)
                clearHUDStage(owner: phaseOwner)
                HUDManager.shared.showTemporary(
                    message: status,
                    recognitionControlMode: .command,
                    icon: hudInputIcon()
                )
                clearHandledCommandPreview()
                return
            }

            guard isRewriteTargetStable(for: job) else {
                logTextRewriteFailure(
                    .focusChanged,
                    phase: "apply",
                    utteranceID: job.utteranceID,
                    typing: job.typingInteraction,
                    targetPID: job.targetPID,
                    bundleID: job.targetBundleID,
                    payload: payload,
                    sourceCount: sourceText.count
                )
                status = textRewriteFailureMessage(.focusChanged)
                clearHUDStage(owner: phaseOwner)
                HUDManager.shared.showTemporary(
                    message: status,
                    recognitionControlMode: .command,
                    icon: hudInputIcon()
                )
                clearHandledCommandPreview()
                return
            }

            let completedPayload = TextRewriteIntentPayload(
                scope: payload.scope,
                mode: payload.mode,
                sourceText: sourceText,
                resultText: rewrittenText,
                failureReason: nil
            )

            if rewrittenText == sourceText {
                onIntent?(.rewriteText(completedPayload), usageContext.appName, usageContext.bundleIdentifier, job.spokenText, job.originalContent, job.enhancedContent, job.diagnostics, nil)
                finishWithFeedback(textRewriteSuccessMessage(changed: false), controlMode: .command)
                return
            }

            setHUDStage(owner: phaseOwner, mode: .typing, controlMode: .dictation)
            status = typingHUDStatus
            let commitMode = commitTextRewriteResult(
                rewrittenText,
                for: job
            )
            GlobalLogger.speech.info(
                "[TextRewrite] commit mode=\(commitMode.rawValue) utterance=\(job.utteranceID) targetPID=\(job.targetPID ?? 0) bundle=\(job.targetBundleID ?? "nil")"
            )
            status = textRewriteSuccessMessage(changed: true)
            scheduleCheckingHUDStage(owner: phaseOwner, controlMode: .command)

            Task { @MainActor [weak self] in
                guard let self else { return }
                let verification = await self.verifyTextRewriteInjection(rewrittenText, for: job)
                self.cancelPendingCheckingHUDStage()
                switch verification {
                case .success:
                    self.onIntent?(.rewriteText(completedPayload), usageContext.appName, usageContext.bundleIdentifier, job.spokenText, job.originalContent, job.enhancedContent, job.diagnostics, nil)
                    self.status = self.textRewriteSuccessMessage(changed: true)
                    self.clearHUDStage(owner: phaseOwner)
                    self.clearHandledCommandPreview()
                    HUDManager.shared.showTemporary(
                        message: self.status,
                        recognitionControlMode: .command,
                        icon: self.hudInputIcon()
                    )
                case .mismatch:
                    self.logTextRewriteFailure(
                        .commitFailed,
                        phase: "verify",
                        utteranceID: job.utteranceID,
                        typing: job.typingInteraction,
                        targetPID: job.targetPID,
                        bundleID: job.targetBundleID,
                        payload: completedPayload,
                        sourceCount: sourceText.count,
                        note: "post-injection-mismatch"
                    )
                    self.status = self.textRewriteFailureMessage(.commitFailed)
                    HUDManager.shared.showTemporary(
                        message: self.status,
                        recognitionControlMode: .command,
                        icon: self.hudInputIcon()
                    )
                    self.clearHUDStage(owner: phaseOwner)
                    self.clearHandledCommandPreview()
                    self.onRecognitionFailure?(rewrittenText, "post-injection-mismatch", usageContext.appName, usageContext.bundleIdentifier)
                case .unverified:
                    self.onIntent?(.rewriteText(completedPayload), usageContext.appName, usageContext.bundleIdentifier, job.spokenText, job.originalContent, job.enhancedContent, job.diagnostics, nil)
                    self.status = self.textRewriteSuccessMessage(changed: true)
                    self.clearHUDStage(owner: phaseOwner)
                    self.clearHandledCommandPreview()
                    HUDManager.shared.showTemporary(
                        message: self.status,
                        recognitionControlMode: .command,
                        icon: self.hudInputIcon()
                    )
                }
            }
        case .frontmostAppCommand(let command):
            setHUDStage(owner: phaseOwner, mode: .executing, controlMode: .command)
            status = executingHUDStatus
            armPostSubmitDictationSuppressionIfNeeded(for: command, job: job)
            onIntent?(job.intent, usageContext.appName, usageContext.bundleIdentifier, job.spokenText, job.originalContent, job.enhancedContent, job.diagnostics, nil)
            finishWithFeedback(NSLocalizedString("speech.done", comment: ""), controlMode: .command)
        case .dictation(let text):
            let wakeFollowUpGroupID = consumeWakeFollowUpDictationMarker(
                sessionGeneration: job.originSessionGeneration,
                utteranceID: job.utteranceID
            )
            let dedupedText = trimRepeatedDictationOverlap(text, for: job)
            let finalText = applyChineseFinalPunctuationFallback(
                dedupedText,
                localeIdentifier: job.localeIdentifier
            )
            guard !finalText.isEmpty else {
                GlobalLogger.speech.info(
                    "[TextPipeline] skip fully-overlapped dictation utterance=\(job.utteranceID) targetPID=\(job.targetPID ?? 0) bundle=\(job.targetBundleID ?? "nil")"
                )
                clearHandledCommandPreview()
                return
            }
            if shouldSuppressRecentWakeFollowUpDuplicate(finalText, for: job) {
                clearHandledCommandPreview()
                return
            }
            if shouldSuppressPostSubmitResidualDictation(finalText, for: job) {
                clearHandledCommandPreview()
                return
            }
            guard isJobInputTargetValidForInjection(job) else {
                let targetBundleLog = job.targetBundleID ?? "nil"
                GlobalLogger.speech.info(
                    "[IntentPipeline] dictation blocked: invalid target utterance=\(job.utteranceID) targetPID=\(job.targetPID ?? 0) bundle=\(targetBundleLog)"
                )
                onRecognitionFailure?(finalText, "invalid-input-target", usageContext.appName, usageContext.bundleIdentifier)
                clearSessionInputTarget(reason: "invalid-input-target")
                status = NSLocalizedString("speech.done", comment: "")
                clearHUDStage(owner: phaseOwner)
                showMissingInputTargetHUD()
                clearHandledCommandPreview()
                return
            }
            setHUDStage(owner: phaseOwner, mode: .typing, controlMode: .dictation)
            status = typingHUDStatus
            let hasStreamed = job.screenTypedCount > 0 || !job.streamedTextSnapshot.isEmpty
            let targetBundleLog = job.targetBundleID ?? "nil"
            if shouldUsePasteFallback(for: job) {
                GlobalLogger.speech.info(
                    "[TextPipeline] paste-fallback utterance=\(job.utteranceID) targetPID=\(job.targetPID ?? 0) bundle=\(targetBundleLog) textCount=\(finalText.count)"
                )
                injector.paste(finalText)
            } else if job.typingInteraction || hasStreamed {
                // Use DictationHandler's diff-based correction instead of old TypingFinalizationPlanner
                // The handler already applied corrections during streaming; final sync is done here
                if finalText == job.streamedTextSnapshot {
                    GlobalLogger.speech.info(
                        "[TextPipeline] synced-noop utterance=\(job.utteranceID) targetPID=\(job.targetPID ?? 0) bundle=\(targetBundleLog) textCount=\(finalText.count) streamedCount=\(job.streamedTextSnapshot.count)"
                    )
                    // Already fully synced by streaming
                } else if finalText.hasPrefix(job.streamedTextSnapshot) {
                    let suffix = String(finalText.dropFirst(job.streamedTextSnapshot.count))
                    GlobalLogger.speech.info(
                        "[TextPipeline] append-suffix utterance=\(job.utteranceID) targetPID=\(job.targetPID ?? 0) bundle=\(targetBundleLog) suffixCount=\(suffix.count) finalCount=\(finalText.count) streamedCount=\(job.streamedTextSnapshot.count)"
                    )
                    if !suffix.isEmpty { injector.type(suffix, targetPID: job.targetPID) }
                } else {
                    // Diff correction: find common prefix, backspace, type remainder
                    let commonLen = commonPrefixLen(job.streamedTextSnapshot, finalText)
                    let toDelete = job.streamedTextSnapshot.count - commonLen
                    let toType = String(finalText.dropFirst(commonLen))
                    GlobalLogger.speech.info(
                        "[TextPipeline] diff-correct utterance=\(job.utteranceID) targetPID=\(job.targetPID ?? 0) bundle=\(targetBundleLog) deleteCount=\(toDelete) typeCount=\(toType.count) finalCount=\(finalText.count) streamedCount=\(job.streamedTextSnapshot.count)"
                    )
                    if toDelete > 0 { injector.deleteBackward(count: toDelete, targetPID: job.targetPID) }
                    if !toType.isEmpty { injector.type(toType, targetPID: job.targetPID) }
                }
            } else {
                GlobalLogger.speech.info(
                    "[TextPipeline] direct-type utterance=\(job.utteranceID) targetPID=\(job.targetPID ?? 0) bundle=\(targetBundleLog) textCount=\(finalText.count)"
                )
                injector.type(finalText, targetPID: job.targetPID)
            }
            let completionStatus = shouldUsePasteFallback(for: job)
                ? NSLocalizedString("speech.pasted_cmdv", comment: "")
                : NSLocalizedString("speech.typed", comment: "")
            status = completionStatus
            rememberCommittedDictation(finalText, for: job)
            armRecentWakeFollowUpDictationSuppressionIfNeeded(finalText, for: job, groupID: wakeFollowUpGroupID)
            scheduleCheckingHUDStage(owner: phaseOwner, controlMode: .dictation)
            Task { @MainActor [weak self] in
                guard let self else { return }
                let verification = await self.verifyDictationInjection(finalText, for: job)
                self.cancelPendingCheckingHUDStage()
                switch verification {
                case .success:
                    self.onIntent?(.dictation(finalText), usageContext.appName, usageContext.bundleIdentifier, job.spokenText, job.originalContent, job.enhancedContent, job.diagnostics, wakeFollowUpGroupID)
                    self.status = completionStatus
                    self.clearHUDStage(owner: phaseOwner)
                    self.clearHandledCommandPreview()
                case .mismatch:
                    self.status = self.genericIncompleteHUDMessage
                    self.clearHUDStage(owner: phaseOwner)
                    self.clearHandledCommandPreview()
                    HUDManager.shared.showTemporary(
                        message: self.status,
                        recognitionControlMode: .dictation,
                        icon: self.hudInputIcon()
                    )
                    self.onRecognitionFailure?(finalText, "post-injection-mismatch", usageContext.appName, usageContext.bundleIdentifier)
                case .unverified:
                    GlobalLogger.speech.info(
                        "[TextPipeline] verification-unverified treating-as-success utterance=\(job.utteranceID) targetPID=\(job.targetPID ?? 0) bundle=\(job.targetBundleID ?? "nil")"
                    )
                    self.onIntent?(.dictation(finalText), usageContext.appName, usageContext.bundleIdentifier, job.spokenText, job.originalContent, job.enhancedContent, job.diagnostics, wakeFollowUpGroupID)
                    self.status = completionStatus
                    self.clearHUDStage(owner: phaseOwner)
                    self.clearHandledCommandPreview()
                }
            }
        case .unknown(let transcript):
            GlobalLogger.router.info(
                "[IntentPipeline] unknown utterance=\(job.utteranceID) typing=\(job.typingInteraction) transcript='\(transcript)'"
            )
            status = NSLocalizedString("speech.no_matching_command", comment: "")
            clearHUDStage(owner: phaseOwner)
            clearHandledCommandPreview()
            let commandEnabled = isCommandExecutionEnabled?() ?? true
            let shouldSurfaceUnknownHUD =
                commandEnabled && (
                    !job.typingInteraction ||
                    effectiveRecognitionControlMode(for: currentVoiceFeatureAvailability()) == .command ||
                    job.routeReason == "forced-command-no-match"
                )
            if shouldSurfaceUnknownHUD {
                showUnknownCommandHUD()
            }
            onIntent?(job.intent, usageContext.appName, usageContext.bundleIdentifier, job.spokenText, job.originalContent, job.enhancedContent, job.diagnostics, nil)
        default:
            setHUDStage(owner: phaseOwner, mode: .executing, controlMode: .command)
            status = executingHUDStatus
            onIntent?(job.intent, usageContext.appName, usageContext.bundleIdentifier, job.spokenText, job.originalContent, job.enhancedContent, job.diagnostics, nil)
            finishWithFeedback(NSLocalizedString("speech.done", comment: ""), controlMode: .command)
        }
    }

    private func revertStreamedDictationIfNeeded(for job: ProcessedJob) {
        let streamedCount = max(job.screenTypedCount, job.streamedTextSnapshot.count)
        guard streamedCount > 0 else { return }

        let shouldRevert: Bool
        let reason: String
        switch job.intent {
        case .dictation:
            return
        case .unknown:
            guard !job.typingInteraction else { return }
            shouldRevert = true
            reason = "unknown-control"
        default:
            shouldRevert = true
            reason = "command-intent"
        }

        guard shouldRevert else { return }
        let targetBundleLog = job.targetBundleID ?? "nil"
        GlobalLogger.speech.info(
            "[TextPipeline] revert-streamed utterance=\(job.utteranceID) targetPID=\(job.targetPID ?? 0) bundle=\(targetBundleLog) deleteCount=\(streamedCount) reason=\(reason)"
        )
        let injectionPID = normalizedInjectionTargetPID(job.targetPID, bundleID: job.targetBundleID)
        injector.deleteBackward(count: streamedCount, targetPID: injectionPID)
        dictationHandler.reset(targetPID: injectionPID)
    }

    private func revertBlockedDictationIfNeeded(for job: ProcessedJob) {
        let streamedCount = max(job.screenTypedCount, job.streamedTextSnapshot.count)
        guard streamedCount > 0 else { return }
        let injectionPID = normalizedInjectionTargetPID(job.targetPID, bundleID: job.targetBundleID)
        injector.deleteBackward(count: streamedCount, targetPID: injectionPID)
        dictationHandler.reset(targetPID: injectionPID)
    }

    private func clearHandledCommandPreview() {
        lastTranscript = ""
        lastChangeAt = nil
        lastStableText = ""
        isUtteranceActive = false
        if isAlwaysListeningEnabled || isWakeWordEnabled || recognitionSession.isRunning || isStopping {
            refreshContinuousHUD(isDictating: false)
        } else {
            HUDManager.shared.hide()
        }
    }

    private func showMissingInputTargetHUD() {
        guard shouldShowMissingInputTargetHUD() else {
            clearHUDOverride()
            refreshContinuousHUD(isDictating: false)
            return
        }
        HUDManager.shared.showTemporary(
            message: NSLocalizedString("speech.no_editable_field", comment: ""),
            recognitionControlMode: .command,
            icon: hudInputIcon(),
        )
    }

    private func shouldUsePasteFallbackForCurrentTypingTarget() -> Bool {
        currentFocusedInputSnapshot()?.source == .recentClickFallback
    }

    private func shouldUsePasteFallback(for job: ProcessedJob) -> Bool {
        job.targetSource == .recentClickFallback
    }

    private func showUnknownCommandHUD() {
        let baseMessage = NSLocalizedString("speech.no_matching_command", comment: "")
        HUDManager.shared.showTemporary(
            message: baseMessage,
            recognitionControlMode: .command,
            icon: hudInputIcon(),
        )
    }

    private func clearUnarmedWakePreview() {
        guard !lastTranscript.isEmpty || lastChangeAt != nil || isUtteranceActive || !lastStableText.isEmpty else {
            return
        }
        lastTranscript = ""
        lastChangeAt = nil
        lastStableText = ""
        isUtteranceActive = false
    }

    private func commonPrefixLen(_ a: String, _ b: String) -> Int {
        var count = 0; var ai = a.startIndex; var bi = b.startIndex
        while ai < a.endIndex && bi < b.endIndex { if a[ai] != b[bi] { break }; count += 1; ai = a.index(after: ai); bi = b.index(after: bi) }
        return count
    }

    private func remainingDictationHUDText() -> String {
        let transcript = lastTranscript
        guard !transcript.isEmpty else { return "" }

        let typed = dictationHandler.screenTypedText
        guard !typed.isEmpty else { return transcript }

        if transcript.hasPrefix(typed) {
            return String(transcript.dropFirst(typed.count))
        }

        let common = commonPrefixLen(typed, transcript)
        return common > 0 ? String(transcript.dropFirst(common)) : transcript
    }

    private func displayedDictationHUDTail() -> String {
        semanticHUDTailSlice(
            from: remainingDictationHUDText()
                .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    private func semanticHUDTailSlice(from tail: String) -> String {
        let preferredLength = 18
        let searchWindow = 34
        let minimumSemanticSegmentLength = 5
        guard tail.count > preferredLength else { return tail }

        let characters = Array(tail)
        let lowerBound = max(0, characters.count - searchWindow)
        let preferredBreakpointStart = max(lowerBound, characters.count - preferredLength)

        for index in stride(from: preferredBreakpointStart, through: lowerBound, by: -1) {
            guard isSemanticHUDTailBreakpoint(characters[index]) else { continue }
            let nextIndex = index + 1
            guard nextIndex < characters.count else { continue }
            let candidate = String(characters[nextIndex...]).trimmingCharacters(in: .whitespacesAndNewlines)
            if candidate.count >= minimumSemanticSegmentLength {
                return candidate
            }
        }

        return tail
    }

    private func isSemanticHUDTailBreakpoint(_ character: Character) -> Bool {
        switch character {
        case "，", "。", "！", "？", "；", "、", " ":
            return true
        default:
            return false
        }
    }

    private func shouldCollapseHUDToTwoState(mode: HUDMode) -> Bool {
        switch mode {
        case .listening, .command, .dictation, .organizing, .typing, .executing, .checking, .processing:
            return true
        default:
            return false
        }
    }

    private func collapsedHUDMessage(for mode: HUDMode, explicitMessage: String = "") -> String {
        let trimmedExplicit = explicitMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        let tail = displayedDictationHUDTail()
        let shouldKeepTextVisibleDuringMutation =
            tail.isEmpty && dictationHandler.isInputMutationActive
        let mutationFallbackText = shouldKeepTextVisibleDuringMutation
            ? semanticHUDTailSlice(
                from: lastTranscript
                    .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            )
            : ""

        switch mode {
        case .listening:
            return trimmedExplicit
        case .command:
            if !trimmedExplicit.isEmpty { return trimmedExplicit }
            if !tail.isEmpty { return tail }
            return lastTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        case .dictation, .organizing, .typing, .executing, .checking, .processing:
            if !tail.isEmpty { return tail }
            if !mutationFallbackText.isEmpty { return mutationFallbackText }
            if shouldSuppressCollapsedHUDStatus(trimmedExplicit) { return "" }
            return trimmedExplicit
        default:
            return trimmedExplicit
        }
    }

    private func shouldSuppressCollapsedHUDStatus(_ message: String) -> Bool {
        guard !message.isEmpty else { return false }
        return message == organizingHUDStatus
            || message == typingHUDStatus
            || message == executingHUDStatus
            || message == checkingHUDStatus
    }

    private func showSpeechBarsHUD(recognitionControlMode: HUDRecognitionControlMode) {
        HUDManager.shared.update(
            mode: .listening,
            message: "",
            language: activeLocale.identifier,
            recognitionControlMode: recognitionControlMode,
            inputDeviceIcon: hudInputIcon(),
            inputDeviceHealth: hudInputHealth(),
            contextIcon: hudContextIcon()
        )
    }

    private func noteFirstPartialIfNeeded(at now: Date) {
        guard !didRecordFirstPartialForSession else { return }
        guard sessionStartedAt != .distantPast else { return }
        didRecordFirstPartialForSession = true
        voiceActivityWithoutPartialSince = nil
        lastVoiceWithoutPartialDiagnosticAt = .distantPast
        lastVoiceWithoutPartialRecoveryAt = .distantPast
        resetNoSpeechRecoveryBackoff()
        startupDetectedUsableAudioForSession = true
        cancelStartupInputHealthProbe()
        let latency = max(0, now.timeIntervalSince(sessionStartedAt) * 1000.0)
        metrics.firstPartialSamples += 1
        metrics.firstPartialLatencyTotalMs += latency
        refreshPlaybackLeakStateForCurrentSession()
        maybeLogRuntimeMetrics(force: false)
    }

    private func audioDiagnosticRMSDescription(_ rms: Float) -> String {
        String(format: "%.4f", rms)
    }

    private func logVoiceActivityTransition(active: Bool, rms: Float, at now: Date) {
        guard now.timeIntervalSince(lastVoiceActivityDiagnosticAt) >= 0.12 else { return }
        lastVoiceActivityDiagnosticAt = now
        GlobalLogger.speech.info(
            "[ASRVAD] active=\(active) rms=\(audioDiagnosticRMSDescription(rms)) recognitionRunning=\(recognitionSession.isRunning) audioRunning=\(audioCapture.isRunning) isStopping=\(isStopping) utteranceActive=\(isUtteranceActive) session=\(sessionGeneration) typing=\(sessionTypingMode) lastTranscript='\(wakeDiagnosticSnippet(lastTranscript))'"
        )
    }

    private func noteVoiceActivityWithoutPartial(at now: Date, rms: Float) {
        guard recognitionSession.isRunning, audioCapture.isRunning, !isStopping else {
            voiceActivityWithoutPartialSince = nil
            return
        }
        if voiceActivityWithoutPartialSince == nil {
            voiceActivityWithoutPartialSince = now
        }
        guard let startedAt = voiceActivityWithoutPartialSince else { return }
        let age = now.timeIntervalSince(startedAt)
        guard age >= 0.9 else { return }
        guard now.timeIntervalSince(lastVoiceWithoutPartialDiagnosticAt) >= 0.9 else { return }
        lastVoiceWithoutPartialDiagnosticAt = now
        let sinceSessionStart = sessionStartedAt == .distantPast ? "nil" : String(format: "%.2fs", now.timeIntervalSince(sessionStartedAt))
        GlobalLogger.speech.info(
            "[ASRStall] reason=voice-active-no-partial age=\(String(format: "%.2fs", age)) rms=\(audioDiagnosticRMSDescription(rms)) recognitionRunning=\(recognitionSession.isRunning) audioRunning=\(audioCapture.isRunning) awake=\(isAwake) utteranceActive=\(isUtteranceActive) session=\(sessionGeneration) sinceSessionStart=\(sinceSessionStart) typing=\(sessionTypingMode) lastTranscript='\(wakeDiagnosticSnippet(lastTranscript))' lastStable='\(wakeDiagnosticSnippet(lastStableText))'"
        )
        maybeRecoverVoiceActiveNoPartialStall(age: age, now: now, rms: rms)
    }

    private func maybeRecoverVoiceActiveNoPartialStall(age: TimeInterval, now: Date, rms: Float) {
        guard age >= voiceActivityWithoutPartialRecoveryThreshold else { return }
        guard isAlwaysListeningEnabled || isWakeWordEnabled else { return }
        guard pendingEngineRestartWorkItem == nil else { return }
        guard now >= routeRebuildGraceUntil,
              now >= continuousRecoveryGraceUntil,
              now >= recognitionStartupGraceUntil,
              now >= recognitionUnavailableUntil else { return }
        guard now.timeIntervalSince(lastVoiceWithoutPartialRecoveryAt) >= engineRestartMinInterval else { return }

        lastVoiceWithoutPartialRecoveryAt = now
        GlobalLogger.speech.info(
            "[ASRStall] scheduling recovery reason=voice-active-no-partial age=\(String(format: "%.2fs", age)) rms=\(audioDiagnosticRMSDescription(rms)) session=\(sessionGeneration) awake=\(isAwake) typing=\(sessionTypingMode)"
        )
        scheduleEngineRestart(reason: "voice-active-no-partial-stall", debounce: 0.05)
    }

    private func applyAdaptiveEOS(with text: String, at now: Date) {
        guard UserDefaults.standard.object(forKey: "adaptiveEOSTuningEnabled") as? Bool ?? true else { return }
        guard !text.isEmpty else { return }

        if lastAdaptiveSampleAt == .distantPast {
            lastAdaptiveSampleAt = now
            lastAdaptiveTextCount = text.count
            return
        }

        let dt = now.timeIntervalSince(lastAdaptiveSampleAt)
        guard dt >= 0.08 else { return }
        let deltaChars = max(0, text.count - lastAdaptiveTextCount)
        lastAdaptiveSampleAt = now
        lastAdaptiveTextCount = text.count
        guard deltaChars > 0 else { return }

        let cps = Double(deltaChars) / dt
        var targetTrailingMs: Double
        switch cps {
        case 0..<3:
            targetTrailingMs = 1050
        case 3..<7:
            targetTrailingMs = 900
        case 7..<12:
            targetTrailingMs = 760
        case 12..<18:
            targetTrailingMs = 650
        default:
            targetTrailingMs = 560
        }

        let style = currentSessionSpeechStyle(
            for: currentVoiceFeatureAvailability(),
            sessionTypingModeOverride: sessionTypingMode
        )
        let wakeFollowUpDictation = isWakeFollowUpDictationContext()
        let wakeFollowUpTrailingMinimum = 900.0

        switch style {
        case .command:
            targetTrailingMs = min(targetTrailingMs, 620)
        case .dictation:
            targetTrailingMs = max(targetTrailingMs, wakeFollowUpDictation ? wakeFollowUpTrailingMinimum : 1150)
        }

        if sessionTypingMode {
            targetTrailingMs = max(targetTrailingMs, wakeFollowUpDictation ? wakeFollowUpTrailingMinimum : 1150)
        }

        targetTrailingMs = min(max(targetTrailingMs, 450), 1400)
        eosDetector.trailingSilenceMs = eosDetector.trailingSilenceMs * 0.65 + targetTrailingMs * 0.35
    }

    private struct VoiceFeatureAvailability {
        let dictationEnabled: Bool
        let commandEnabled: Bool
    }

    private func currentVoiceFeatureAvailability() -> VoiceFeatureAvailability {
        VoiceFeatureAvailability(
            dictationEnabled: isDictationExecutionEnabled?() ?? true,
            commandEnabled: isCommandExecutionEnabled?() ?? true
        )
    }

    private func effectiveTypingContext(
        reconciledTypingContext: Bool,
        computedTypingContext: Bool,
        availability: VoiceFeatureAvailability
    ) -> Bool {
        if availability.dictationEnabled && !availability.commandEnabled {
            return reconciledTypingContext || computedTypingContext
        }
        if !availability.dictationEnabled && availability.commandEnabled {
            return false
        }
        return reconciledTypingContext
    }

    private func likelyWakePayloadCommand(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        let decision = commandRouter.routeDetailed(
            transcript: trimmed,
            bias: .commandPreferred,
            localeIdentifier: activeLocale.identifier
        )
        guard decision.confidence >= .medium else { return false }
        return isCommandIntent(decision.intent)
    }

    private func isCommandIntent(_ intent: VoiceIntent) -> Bool {
        switch intent {
        case .dictation, .unknown:
            return false
        default:
            return true
        }
    }

    private func currentVoiceBlockFeedback(
        featureDisabledMessageKey: String,
        featureDisabledLogReason: String
    ) -> (message: String, icon: String, logReason: String, analyticsReason: String?) {
        if isAppIdlePaused?() == true {
            return (
                NSLocalizedString("speech.app_paused_idle", comment: ""),
                "pause.circle.fill",
                "app idle paused",
                nil
            )
        }

        let icon = featureDisabledMessageKey == "speech.voice_input_disabled"
            ? "text.cursor"
            : "command.circle"
        let analyticsReason = featureDisabledMessageKey == "speech.voice_input_disabled"
            ? "dictation-disabled"
            : nil
        return (
            NSLocalizedString(featureDisabledMessageKey, comment: ""),
            icon,
            featureDisabledLogReason,
            analyticsReason
        )
    }

    static func shouldPreviewForcedCommandHUD(
        typingContext: Bool,
        intent: VoiceIntent,
        routingBias: VoiceCommandRouter.RoutingBias,
        consumedExplicitCommandPrefix: Bool,
        inlineExplicitCommandPrefix: Bool
    ) -> Bool {
        guard isCommandIntentStatic(intent) else { return false }

        // Some commands already surface a dedicated HUD after execution.
        switch intent {
        case .toggleInputControlMode, .scrollToWeb, .dragStart, .dragEnd:
            return false
        case .dictation, .unknown:
            return false
        default:
            return true
        }
    }

    static func commandHUDPreviewMessage(
        for intent: VoiceIntent,
        localeIdentifier: String
    ) -> String? {
        let locale = Locale(identifier: localeIdentifier)
        let label: String?

        switch intent {
        case .clickLeft:
            label = VoiceCommandPreset.clickLeft.title(locale: locale)
        case .clickRight:
            label = VoiceCommandPreset.clickRight.title(locale: locale)
        case .doubleClick:
            label = VoiceCommandPreset.doubleClick.title(locale: locale)
        case .toggleInputControlMode:
            label = VoiceCommandPreset.toggleInputControlMode.title(locale: locale)
        case .toggleTracking:
            label = VoiceCommandPreset.toggleTracking.title(locale: locale)
        case .toggleLanguage:
            label = VoiceCommandPreset.toggleLanguage.title(locale: locale)
        case .toggleShortcutPanel:
            label = VoiceCommandPreset.toggleShortcutPanel.title(locale: locale)
        case .mediaPlayPause:
            label = VoiceCommandPreset.mediaPlayPause.title(locale: locale)
        case .mediaPrevious:
            label = VoiceCommandPreset.mediaPrevious.title(locale: locale)
        case .mediaNext:
            label = VoiceCommandPreset.mediaNext.title(locale: locale)
        case .showShortcutPanel:
            label = VoiceCommandPreset.showShortcutPanel.title(locale: locale)
        case .hideShortcutPanel:
            label = VoiceCommandPreset.hideShortcutPanel.title(locale: locale)
        case .startPointer:
            label = VoiceCommandPreset.startPointer.title(locale: locale)
        case .stopPointer:
            label = VoiceCommandPreset.stopPointer.title(locale: locale)
        case .recenter:
            label = VoiceCommandPreset.recenter.title(locale: locale)
        case .openApplication(let target):
            label = target.displayName
        case .scroll(_, let dy):
            label = dy < 0
                ? VoiceCommandPreset.scrollUp.title(locale: locale)
                : VoiceCommandPreset.scrollDown.title(locale: locale)
        case .scrollToWeb(let edge):
            label = edge == "top"
                ? VoiceCommandPreset.scrollTop.title(locale: locale)
                : VoiceCommandPreset.scrollBottom.title(locale: locale)
        case .dragStart:
            label = VoiceCommandPreset.dragStart.title(locale: locale)
        case .dragEnd:
            label = VoiceCommandPreset.dragEnd.title(locale: locale)
        case .undo:
            label = VoiceCommandPreset.undo.title(locale: locale)
        case .paste:
            label = VoiceCommandPreset.paste.title(locale: locale)
        case .clearInput:
            label = VoiceCommandPreset.clearInput.title(locale: locale)
        case .deleteBackward:
            label = VoiceCommandPreset.deleteBackward.title(locale: locale)
        case .moveCursorHorizontally(let offset):
            label = offset < 0
                ? VoiceCommandPreset.moveCursorLeft.title(locale: locale)
                : VoiceCommandPreset.moveCursorRight.title(locale: locale)
        case .selectHorizontally(let offset):
            label = offset < 0
                ? VoiceCommandPreset.selectLeft.title(locale: locale)
                : VoiceCommandPreset.selectRight.title(locale: locale)
        case .rewriteText(let payload):
            label = payload.mode.actionTitle(isChinese: locale.identifier.hasPrefix("zh"))
        case .frontmostAppCommand(let command):
            let path = command.displayPath.trimmingCharacters(in: .whitespacesAndNewlines)
            let title = command.title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !path.isEmpty else { return title }
            if command.isCustomRuleCommand {
                return compactHUDSnippet(
                    title.isEmpty ? path : title,
                    maxEnglishCharacters: 24,
                    maxNonEnglishCharacters: 12
                )
            }
            if command.menuPath.count <= 1 {
                return compactHUDSnippet(path, maxEnglishCharacters: 30, maxNonEnglishCharacters: 14)
            }
            return title.isEmpty
                ? compactHUDSnippet(path, maxEnglishCharacters: 24, maxNonEnglishCharacters: 12)
                : compactHUDSnippet(title, maxEnglishCharacters: 24, maxNonEnglishCharacters: 12)
        case .dictation, .unknown:
            return nil
        }

        guard let label else { return nil }
        return compactHUDSnippet(label, maxEnglishCharacters: 24, maxNonEnglishCharacters: 10)
    }

    private static func compactHUDSnippet(
        _ text: String,
        maxEnglishCharacters: Int = 26,
        maxNonEnglishCharacters: Int = 12
    ) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return trimmed }

        let isEnglishLike = trimmed.unicodeScalars.contains {
            $0.isASCII && CharacterSet.letters.contains($0)
        }
        let limit = max(4, isEnglishLike ? maxEnglishCharacters : maxNonEnglishCharacters)
        guard trimmed.count > limit else { return trimmed }

        let endIndex = trimmed.index(trimmed.startIndex, offsetBy: max(1, limit - 1))
        return "\(trimmed[..<endIndex])…"
    }

    static func hasLeadingExplicitCommandPrefix(
        _ text: String,
        localeIdentifier: String,
        overrides: [VoiceLanguageTermsOverrideConfig]
    ) -> Bool {
        let trimmed = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingLeadingCommandPrefixIgnorables()
        guard !trimmed.isEmpty else { return false }

        let prefixes = VoiceCommandRouter.effectiveCommandPrefixes(
            for: localeIdentifier,
            overrides: overrides
        )
        let lowered = trimmed.lowercased()

        for prefix in Set(prefixes.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) })
            .filter({ !$0.isEmpty })
            .sorted(by: { $0.count > $1.count }) {
            if lowered.hasPrefix(prefix.lowercased()) {
                return true
            }
        }

        return false
    }

    private enum ScriptBias {
        case chinese
        case latin
        case mixed
        case other
    }

    private static func guardrailComparableTextBody(_ text: String) -> String {
        let filtered = text.unicodeScalars.filter {
            CharacterSet.letters.contains($0) || CharacterSet.decimalDigits.contains($0)
        }
        return String(String.UnicodeScalarView(filtered)).lowercased()
    }

    private static func hasProtectedTokenDrift(sourceText: String, candidateText: String) -> Bool {
        let sourceTokens = Set(protectedTokens(in: sourceText))
        guard !sourceTokens.isEmpty else { return false }
        let candidateTokens = Set(protectedTokens(in: candidateText))
        return sourceTokens != candidateTokens
    }

    private static func protectedTokens(in text: String) -> [String] {
        let patterns = [
            #"https?://\S+"#,
            #"www\.\S+"#,
            #"[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}"#,
            #"(?:~?/[\w.\-]+)+(?:\.[A-Za-z0-9]+)?"#,
            #"(?<![\p{L}\d])\d[\d:.,/-]*(?![\p{L}\d])"#
        ]

        return patterns.flatMap { pattern in
            regexMatches(pattern: pattern, in: text)
        }
    }

    private static func hasLanguageDrift(
        sourceText: String,
        candidateText: String,
        localeIdentifier: String
    ) -> Bool {
        let sourceBias = scriptBias(for: sourceText, localeIdentifier: localeIdentifier)
        let candidateBias = scriptBias(for: candidateText, localeIdentifier: localeIdentifier)

        switch (sourceBias, candidateBias) {
        case (.chinese, .latin), (.latin, .chinese):
            return true
        default:
            return false
        }
    }

    private static func isLikelyCodeLikeEnhancementInput(
        _ text: String,
        localeIdentifier _: String
    ) -> Bool {
        let markers = [".swift", ".js", ".ts", ".tsx", ".py", "--", "⌘", "::", "->", "{", "}"]
        return markers.contains(where: { text.contains($0) })
    }

    private static func scriptBias(for text: String, localeIdentifier: String) -> ScriptBias {
        let chineseCount = text.unicodeScalars.reduce(into: 0) { partialResult, scalar in
            let value = Int(scalar.value)
            if (0x3400...0x4DBF).contains(value)
                || (0x4E00...0x9FFF).contains(value)
                || (0xF900...0xFAFF).contains(value) {
                partialResult += 1
            }
        }
        let latinCount = text.unicodeScalars.reduce(into: 0) { partialResult, scalar in
            if scalar.isASCII, CharacterSet.letters.contains(scalar) {
                partialResult += 1
            }
        }

        if chineseCount >= max(3, latinCount * 2) {
            return .chinese
        }
        if latinCount >= max(4, chineseCount * 2) {
            return .latin
        }
        if chineseCount > 0, latinCount > 0 {
            return .mixed
        }
        if localeIdentifier.lowercased().hasPrefix("zh"), chineseCount > 0 {
            return .chinese
        }
        return .other
    }

    private static func regexMatches(pattern: String, in text: String) -> [String] {
        guard let regex = try? NSRegularExpression(
            pattern: pattern,
            options: [.caseInsensitive]
        ) else {
            return []
        }

        let nsRange = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, options: [], range: nsRange).compactMap { match in
            guard let range = Range(match.range, in: text) else { return nil }
            return String(text[range])
        }
    }

    private static func levenshteinDistance(_ lhs: String, _ rhs: String) -> Int {
        if lhs == rhs { return 0 }
        if lhs.isEmpty { return rhs.count }
        if rhs.isEmpty { return lhs.count }

        let lhsChars = Array(lhs)
        let rhsChars = Array(rhs)
        var previous = Array(0...rhsChars.count)

        for (lhsIndex, lhsChar) in lhsChars.enumerated() {
            var current = Array(repeating: 0, count: rhsChars.count + 1)
            current[0] = lhsIndex + 1

            for (rhsIndex, rhsChar) in rhsChars.enumerated() {
                let substitutionCost = lhsChar == rhsChar ? 0 : 1
                current[rhsIndex + 1] = min(
                    previous[rhsIndex + 1] + 1,
                    current[rhsIndex] + 1,
                    previous[rhsIndex] + substitutionCost
                )
            }

            previous = current
        }

        return previous[rhsChars.count]
    }

    static func isSubmitLikeFrontmostAppCommand(_ command: FrontmostAppCommand) -> Bool {
        let returnLikeKeyCodes: Set<Int> = [kVK_Return, kVK_ANSI_KeypadEnter]
        guard returnLikeKeyCodes.contains(command.shortcut.keyCode) else { return false }

        let keywordCandidates = ([command.title] + command.aliases + command.menuPath)
            .map(looseSpeechComparisonKey)
            .filter { !$0.isEmpty }

        let submitLikeKeywords = [
            "send",
            "sendreply",
            "sendmessage",
            "submit",
            "confirmsend",
            "确认发送",
            "发送",
            "发送消息",
            "发送回复",
            "提交",
            "确认提交"
        ]

        return keywordCandidates.contains { candidate in
            submitLikeKeywords.contains { candidate.contains($0) }
        }
    }

    static func shouldSuppressResidualDictationAfterSubmit(
        previous: String,
        current: String
    ) -> Bool {
        let previousTrimmed = previous.trimmingCharacters(in: .whitespacesAndNewlines)
        let currentTrimmed = current.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !previousTrimmed.isEmpty, !currentTrimmed.isEmpty else { return false }

        let previousLoose = looseSpeechComparisonKey(previousTrimmed)
        let currentLoose = looseSpeechComparisonKey(currentTrimmed)
        guard !previousLoose.isEmpty, !currentLoose.isEmpty else { return false }

        if previousLoose == currentLoose {
            return true
        }

        let minComparableCount = 6
        if min(previousLoose.count, currentLoose.count) >= minComparableCount,
           (previousLoose.contains(currentLoose) || currentLoose.contains(previousLoose)) {
            return true
        }

        let overlap = repeatedTailPrefixOverlap(previous: previousLoose, current: currentLoose)
        return overlap >= minimumCrossUtteranceOverlapLength(for: currentLoose)
    }

    private static func looseSpeechComparisonKey(_ raw: String) -> String {
        raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .unicodeScalars
            .filter {
                !CharacterSet.whitespacesAndNewlines.contains($0)
                    && !CharacterSet.punctuationCharacters.contains($0)
            }
            .map(String.init)
            .joined()
    }

    private static func isCommandIntentStatic(_ intent: VoiceIntent) -> Bool {
        switch intent {
        case .dictation, .unknown:
            return false
        default:
            return true
        }
    }

    private func intentSummary(_ intent: VoiceIntent) -> String {
        switch intent {
        case .clickLeft: return "clickLeft"
        case .clickRight: return "clickRight"
        case .doubleClick: return "doubleClick"
        case .toggleInputControlMode: return "toggleInputControlMode"
        case .toggleTracking: return "toggleTracking"
        case .toggleLanguage: return "toggleLanguage"
        case .toggleShortcutPanel: return "toggleShortcutPanel"
        case .mediaPlayPause: return "mediaPlayPause"
        case .mediaPrevious: return "mediaPrevious"
        case .mediaNext: return "mediaNext"
        case .showShortcutPanel: return "showShortcutPanel"
        case .hideShortcutPanel: return "hideShortcutPanel"
        case .startPointer: return "startPointer"
        case .stopPointer: return "stopPointer"
        case .recenter: return "recenter"
        case .openApplication(let target):
            return "openApplication(\(target.displayName):\(target.bundleIdentifier))"
        case .scroll(let dx, let dy): return "scroll(\(dx),\(dy))"
        case .scrollToWeb(let edge): return "scrollToWeb(\(edge))"
        case .dragStart: return "dragStart"
        case .dragEnd: return "dragEnd"
        case .undo: return "undo"
        case .paste: return "paste"
        case .clearInput: return "clearInput"
        case .deleteBackward(let count): return "deleteBackward(\(count))"
        case .moveCursorHorizontally(let offset): return "moveCursorHorizontally(\(offset))"
        case .selectHorizontally(let offset): return "selectHorizontally(\(offset))"
        case .rewriteText(let payload):
            return "rewriteText(scope=\(payload.scope.rawValue),mode=\(payload.mode.rawValue),hasSource=\(payload.sourceText != nil),hasResult=\(payload.resultText != nil),failure=\(payload.failureReason?.rawValue ?? "nil"))"
        case .frontmostAppCommand(let command):
            return "frontmostAppCommand(\(command.appName):\(command.title):\(command.shortcut.displayString))"
        case .dictation(let text):
            return "dictation(\(text))"
        case .unknown(let text):
            return "unknown(\(text))"
        }
    }

    private func routingBiasSummary(_ bias: VoiceCommandRouter.RoutingBias) -> String {
        switch bias {
        case .neutral: return "neutral"
        case .forceCommand: return "forceCommand"
        case .commandPreferred: return "commandPreferred"
        case .forceDictation: return "forceDictation"
        case .dictationPreferred: return "dictationPreferred"
        }
    }

    private func noteIntentMetrics(_ intent: VoiceIntent) {
        metrics.utterances += 1
        switch intent {
        case .dictation:
            metrics.dictations += 1
        case .unknown:
            metrics.unknowns += 1
        default:
            metrics.commands += 1
        }
        maybeLogRuntimeMetrics(force: false)
    }

    private func maybeLogRuntimeMetrics(force: Bool) {
        if !force, metrics.utterances == 0 { return }
        if !force, metrics.utterances % 10 != 0 { return }
        let avgFirstPartial = Int(metrics.firstPartialLatencyAvgMs.rounded())
        GlobalLogger.speech.info(
            "[Metrics] sessions=\(metrics.sessions) utterances=\(metrics.utterances) commands=\(metrics.commands) dictation=\(metrics.dictations) unknown=\(metrics.unknowns) firstPartialAvgMs=\(avgFirstPartial) engineRestarts=\(metrics.engineRestarts) lowConfDrops=\(metrics.lowConfidenceCommandDowngrades) recoverableErr=\(metrics.recoverableErrors) fatalErr=\(metrics.fatalErrors)"
        )
    }

    private func handleHeadsetInputMuteGesture(_ inputShouldBeMuted: Bool) {
        HeadMotionManager.shared.handleSystemInputMuteGesture(inputShouldBeMuted)
    }

    @discardableResult
    private func refreshFrontmostAppCommands(force: Bool = false) -> [FrontmostAppCommand] {
        let snapshot = FrontmostAppCommandCatalog.refreshSnapshotFromAnyThread(force: force)
        let merged = mergeFrontmostAppCommandSnapshot(snapshot: snapshot, customRules: customAppShortcutRules)
        let commands = merged?.commands ?? []
        commandRouter.frontmostAppCommands = commands
        return commands
    }

    private func buildDynamicContextualStrings() -> [String] {
        var ordered: [String] = []
        var seen = Set<String>()

        func add(_ token: String) {
            guard let normalized = normalizeContextualToken(token) else { return }
            let key = normalized.lowercased()
            guard !seen.contains(key) else { return }
            seen.insert(key)
            ordered.append(normalized)
        }

        let staticSeeds = [
            "点击", "双击", "向下", "向上", "右键",
            "Click", "Double Click", "Scroll Down", "Scroll Up", "Right Click",
            "GitHub", "git", "repo", "repository", "issue", "pull request", "PR",
            "commit", "branch", "merge", "rebase", "checkout", "clone", "push", "pull",
            "origin", "main", "develop", "release"
        ]
        staticSeeds.forEach(add)
        wakeWordDetector.contextualStrings(for: activeLocale.identifier).forEach(add)
        _ = refreshFrontmostAppCommands()
        commandRouter.appLaunchTargets = AppLaunchResolver.contextualTargets(customRules: customAppLaunchAliasRules)
        commandRouter.contextualStrings(for: activeLocale.identifier).forEach(add)

        let frontApp = NSWorkspace.shared.frontmostApplication
        if let appName = frontApp?.localizedName {
            tokenizeContextualString(appName).forEach(add)
        }
        if let bundleID = frontApp?.bundleIdentifier {
            tokenizeContextualString(bundleID).forEach(add)
        }

        let bundleIDs = currentContextBundleIDs()
        if shouldEnableDeveloperSpeechProfile(bundleIDs: bundleIDs) {
            DeveloperSpeechProfile.contextualTerms(for: bundleIDs).forEach(add)
        }

        if shouldEnableSpeechTermCorrection() {
            for group in activeGroupsForCurrentContext() {
                tokenizeContextualString(group.name).forEach(add)
                for rule in replacementRules(for: group) {
                    tokenizeContextualString(rule.from).forEach(add)
                    tokenizeContextualString(rule.to).forEach(add)
                }
            }
        }

        if !lastTranscript.isEmpty {
            tokenizeContextualString(lastTranscript).forEach(add)
        }

        if ordered.count > 160 {
            ordered = Array(ordered.prefix(160))
        }
        return ordered
    }

    private func tokenizeContextualString(_ raw: String) -> [String] {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        var out: [String] = [trimmed]
        let splitSet = CharacterSet(charactersIn: " ,./_:-+@()[]{}<>|\\\t\n")
        let parts = trimmed
            .components(separatedBy: splitSet)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        out.append(contentsOf: parts)
        return out
    }

    private func normalizeContextualToken(_ token: String) -> String? {
        let t = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return nil }
        guard t.count <= 32 else { return nil }
        if t.count == 1 {
            let isAscii = t.unicodeScalars.allSatisfy { $0.isASCII }
            if isAscii { return nil }
        }
        return t
    }

    private var textRewriteHUDMessage: String {
        let isSlow = isTextRewriteHUDSlowPhase
        if AppLocalization.isChinese {
            return activeTextRewriteHUDCount > 1
                ? (isSlow ? "还在优化（\(activeTextRewriteHUDCount)）…" : "正在优化（\(activeTextRewriteHUDCount)）")
                : (isSlow ? "还在优化…" : "正在优化…")
        }
        return activeTextRewriteHUDCount > 1
            ? (isSlow ? "Still optimizing (\(activeTextRewriteHUDCount))…" : "Optimizing (\(activeTextRewriteHUDCount))")
            : (isSlow ? "Still optimizing..." : "Optimizing...")
    }

    private func beginTextRewriteHUDActivity() {
        if activeTextRewriteHUDCount == 0 {
            isTextRewriteHUDSlowPhase = false
            armTextRewriteHUDSlowTransition()
        }
        activeTextRewriteHUDCount += 1
        status = textRewriteHUDMessage
        setHUDStage(
            owner: "rewrite-global",
            mode: .optimizing,
            message: textRewriteHUDMessage,
            controlMode: .command
        )
    }

    private func endTextRewriteHUDActivity() {
        activeTextRewriteHUDCount = max(0, activeTextRewriteHUDCount - 1)
        if activeTextRewriteHUDCount > 0 {
            setHUDStage(
                owner: "rewrite-global",
                mode: .optimizing,
                message: textRewriteHUDMessage,
                controlMode: .command
            )
        } else if activeHUDStageOwner == "rewrite-global" {
            cancelTextRewriteHUDSlowTransition()
            isTextRewriteHUDSlowPhase = false
            clearHUDStage(owner: "rewrite-global")
        } else {
            cancelTextRewriteHUDSlowTransition()
            isTextRewriteHUDSlowPhase = false
            refreshContinuousHUD(isDictating: false)
        }
    }

    private func armTextRewriteHUDSlowTransition() {
        cancelTextRewriteHUDSlowTransition()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self, self.activeTextRewriteHUDCount > 0 else { return }
            self.isTextRewriteHUDSlowPhase = true
            self.status = self.textRewriteHUDMessage
            self.setHUDStage(
                owner: "rewrite-global",
                mode: .optimizing,
                message: self.textRewriteHUDMessage,
                controlMode: .command
            )
        }
        pendingTextRewriteSlowHUDWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + textRewriteHUDSlowMessageDelay, execute: workItem)
    }

    private func cancelTextRewriteHUDSlowTransition() {
        pendingTextRewriteSlowHUDWorkItem?.cancel()
        pendingTextRewriteSlowHUDWorkItem = nil
    }

    private func textRewriteFailureReason(for error: Error) -> TextRewriteFailureReason {
        if let providerError = error as? LLMProviderError,
           case .requestTimedOut = providerError {
            return .timedOut
        }
        return .providerFailed
    }

    private func shouldHoldTextRewriteBarrier(for intent: VoiceIntent) -> Bool {
        guard case .rewriteText(let payload) = intent else { return false }
        return payload.failureReason == nil
    }

    private func shouldBlockIntentDuringTextRewrite(_ intent: VoiceIntent) -> Bool {
        guard activeTextRewriteHUDCount > 0 else { return false }
        switch intent {
        case .rewriteText,
             .dictation,
             .undo,
             .paste,
             .clearInput,
             .deleteBackward,
             .moveCursorHorizontally,
             .selectHorizontally,
             .openApplication,
             .frontmostAppCommand:
            return true
        default:
            return false
        }
    }

    private func showTextRewriteBusyHUD() {
        let message = AppLocalization.isChinese
            ? "正在优化，请稍候"
            : "Optimizing. Please wait."
        status = message
        HUDManager.shared.showTemporary(
            message: message,
            recognitionControlMode: .command,
            icon: hudInputIcon(),
            duration: 1.2
        )
    }

    private func shouldSuppressStreamingDictationAfterRecentSubmit(
        targetPID: pid_t?,
        bundleID: String?,
        elementFingerprint: String?
    ) -> Bool {
        guard let suppression = postSubmitDictationSuppression else { return false }

        let now = Date()
        guard now <= suppression.expiresAt else {
            postSubmitDictationSuppression = nil
            return false
        }
        guard now.timeIntervalSince(suppression.expiresAt.addingTimeInterval(-postSubmitDictationSuppressionWindow))
            <= postSubmitStreamingSuppressionWindow else {
            return false
        }

        let sameFingerprint = suppression.elementFingerprint != nil
            && suppression.elementFingerprint == elementFingerprint
        let samePID = suppression.pid != nil && suppression.pid == targetPID
        let sameBundle = suppression.bundleID != nil && suppression.bundleID == bundleID
        return sameFingerprint || samePID || sameBundle
    }

    private func armPostSubmitDictationSuppressionIfNeeded(
        for command: FrontmostAppCommand,
        job: ProcessedJob
    ) {
        guard Self.isSubmitLikeFrontmostAppCommand(command) else { return }

        let previousText = lastCommittedDictationText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !previousText.isEmpty,
              Date().timeIntervalSince(lastCommittedDictationAt) <= 6.0 else {
            return
        }

        postSubmitDictationSuppression = PostSubmitDictationSuppression(
            expiresAt: Date().addingTimeInterval(postSubmitDictationSuppressionWindow),
            pid: lastCommittedDictationPID ?? job.targetPID ?? (command.isGlobalRule ? nil : command.processIdentifier),
            bundleID: lastCommittedDictationBundleID ?? job.targetBundleID ?? command.bundleIdentifier,
            elementFingerprint: lastCommittedDictationElementFingerprint ?? job.targetElementFingerprint,
            previousText: previousText
        )
        GlobalLogger.speech.info(
            "[TextPipeline] armed-post-submit-suppression title=\(command.title) pid=\(postSubmitDictationSuppression?.pid ?? 0) bundle=\(postSubmitDictationSuppression?.bundleID ?? "nil") textCount=\(previousText.count)"
        )
    }

    private func shouldSuppressPostSubmitResidualDictation(
        _ text: String,
        for job: ProcessedJob
    ) -> Bool {
        guard let suppression = postSubmitDictationSuppression else { return false }
        guard Date() <= suppression.expiresAt else {
            postSubmitDictationSuppression = nil
            return false
        }

        let sameFingerprint = suppression.elementFingerprint != nil
            && suppression.elementFingerprint == job.targetElementFingerprint
        let samePID = suppression.pid != nil && suppression.pid == job.targetPID
        let sameBundle = suppression.bundleID != nil && suppression.bundleID == job.targetBundleID
        guard sameFingerprint || samePID || sameBundle else { return false }

        guard Self.shouldSuppressResidualDictationAfterSubmit(
            previous: suppression.previousText,
            current: text
        ) else {
            return false
        }

        postSubmitDictationSuppression = nil
        GlobalLogger.speech.info(
            "[TextPipeline] suppressed-post-submit-residual utterance=\(job.utteranceID) targetPID=\(job.targetPID ?? 0) bundle=\(job.targetBundleID ?? "nil") previousCount=\(suppression.previousText.count) currentCount=\(text.count)"
        )
        return true
    }

    private func clearPostSubmitDictationSuppression() {
        postSubmitDictationSuppression = nil
    }

    private func hudStageOwner(for job: IntentJob) -> String {
        "job:\(job.originSessionGeneration)#\(job.utteranceID)"
    }

    private func hudStageOwner(for job: ProcessedJob) -> String {
        "job:\(job.originSessionGeneration)#\(job.utteranceID)"
    }

    private var organizingHUDStatus: String {
        AppLocalization.isChinese ? "整理中" : "Organizing"
    }

    private var typingHUDStatus: String {
        AppLocalization.isChinese ? "正在输入" : "Typing"
    }

    private var executingHUDStatus: String {
        AppLocalization.isChinese ? "正在执行" : "Executing"
    }

    private var checkingHUDStatus: String {
        AppLocalization.isChinese ? "校验中" : "Checking"
    }

    private var genericIncompleteHUDMessage: String {
        AppLocalization.isChinese ? "没完成" : "Didn't finish"
    }

    private func cancelPendingCheckingHUDStage() {
        pendingCheckingHUDWorkItem?.cancel()
        pendingCheckingHUDWorkItem = nil
    }

    private func setHUDStage(
        owner: String,
        mode: HUDMode,
        message: String = "",
        controlMode: HUDRecognitionControlMode? = nil
    ) {
        if mode != .checking {
            cancelPendingCheckingHUDStage()
        }
        activeHUDStageOwner = owner
        activeHUDStageMode = mode
        activeHUDStageMessage = message
        activeHUDStageControlMode = controlMode
        refreshContinuousHUD(isDictating: false)
    }

    private func clearHUDStage(owner: String? = nil) {
        if let owner, activeHUDStageOwner != owner {
            return
        }
        cancelPendingCheckingHUDStage()
        activeHUDStageOwner = nil
        activeHUDStageMode = nil
        activeHUDStageMessage = ""
        activeHUDStageControlMode = nil
        refreshContinuousHUD(isDictating: false)
    }

    private func scheduleCheckingHUDStage(
        owner: String,
        controlMode: HUDRecognitionControlMode,
        message: String = ""
    ) {
        cancelPendingCheckingHUDStage()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self, self.activeHUDStageOwner == owner else { return }
            self.activeHUDStageMode = .checking
            self.activeHUDStageMessage = message
            self.activeHUDStageControlMode = controlMode
            self.refreshContinuousHUD(isDictating: false)
        }
        pendingCheckingHUDWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.36, execute: workItem)
    }

    // MARK: - HUD Management
    private func setHUDOverride(
        mode: HUDMode,
        message: String,
        icon: String,
        inputDeviceHealth: HUDInputDeviceHealth,
        duration: TimeInterval?
    ) {
        let resolvedDuration = duration ?? HUDManager.shared.suggestedTemporaryDuration(for: message)
        hudOverrideMode = mode
        hudOverrideMessage = message
        hudOverrideIcon = icon
        hudOverrideInputDeviceHealth = inputDeviceHealth
        hudOverrideUntil = Date().addingTimeInterval(max(0.2, resolvedDuration))
    }
    private func clearHUDOverride() {
        hudOverrideUntil = .distantPast
        hudOverrideMessage = ""
        hudOverrideIcon = "info.circle"
        hudOverrideInputDeviceHealth = .normal
    }

    private func refreshContinuousHUD(isDictating: Bool = false) {
        let now = Date()
        if isIdlePauseSuspended {
            updateSpeechHUDTextVisibility(false, at: now, armHold: false)
            if HUDManager.shared.isTemporaryHUDActive || HUDManager.shared.state.isLanguageIndicatorVisible {
                return
            }
            HUDManager.shared.hide()
            return
        }
        let featureAvailability = currentVoiceFeatureAvailability()
        let isDictationOnly =
            featureAvailability.dictationEnabled
            && !featureAvailability.commandEnabled
        let authoritativeState = syncInputControlState(source: "speech.refresh-continuous-hud")
        let focusedTypingEvidence = focusedTypingHUDEvidence()
        let stickyTypingHUDEligible = authoritativeState.interactionState.isTyping
        let idleTypingEvidence = isDictationOnly ? focusedTypingEvidence : authoritativeState.interactionState.isTyping
        let typingHUDEligible = authoritativeState.interactionState.isTyping
        let isContinuousActive = isAlwaysListeningEnabled
        let isPushToTalkOnlyIdle = !isAlwaysListeningEnabled && !isWakeWordEnabled
        let controlMode = effectiveHUDRecognitionControlMode(
            for: featureAvailability,
            typingEligible: (isContinuousActive || recognitionSession.isRunning || isStopping || isDictating || isPTTHeld)
                ? typingHUDEligible
                : idleTypingEvidence
        )
        let isWakeGated = isAlwaysListeningEnabled && isWakeWordEnabled && !isDirectCommandEnabled
        let wakeFollowUpActive = isWakeFollowUpSessionActive
        let isWakeGatedStandby = isWakeGated && !wakeFollowUpActive && !isStopping
        let shouldHoldDictationHUD =
            authoritativeState.sessionState == .recoveryHold
            && controlMode == .auto
            && (!isWakeGated || wakeFollowUpActive)
        let effectiveDictating = isDictating || shouldHoldDictationHUD
        let realHardware = availableInputDevices.filter { $0.id != 0 }
        let shouldShowIdleDictationHUD =
            featureAvailability.dictationEnabled
            && !featureAvailability.commandEnabled
            && focusedTypingEvidence
        let shouldShowIdleCommandHUD =
            featureAvailability.commandEnabled
            && !featureAvailability.dictationEnabled
        let suppressCompletedDictationExitBars = shouldSuppressSpeechExitBarsForCompletedDictation(
            featureAvailability: featureAvailability,
            controlMode: controlMode,
            isContinuousActive: isContinuousActive,
            isSessionActive: recognitionSession.isRunning || isStopping || effectiveDictating || isPTTHeld
        )
        if !isStopping && Date() < hudOverrideUntil {
            updateSpeechHUDTextVisibility(false, at: now, armHold: false)
            HUDManager.shared.update(
                mode: hudOverrideMode,
                message: hudOverrideMessage,
                language: activeLocale.identifier,
                recognitionControlMode: controlMode,
                inputDeviceIcon: hudOverrideIcon,
                inputDeviceHealth: hudOverrideInputDeviceHealth,
                contextIcon: hudContextIcon()
            )
            return
        }
        if (isAlwaysListeningEnabled || isWakeWordEnabled), let hint = missingVoicePermissionHint() {
            updateSpeechHUDTextVisibility(false, at: now, armHold: false)
            HUDManager.shared.update(
                mode: .feedback,
                message: hint.message,
                language: activeLocale.identifier,
                recognitionControlMode: controlMode,
                inputDeviceIcon: hudInputIcon(),
                inputDeviceHealth: hint.health,
                contextIcon: hudContextIcon()
            )
            return
        }
        if let activeStageMode = activeHUDStageMode {
            let activeStageMessage =
                shouldCollapseHUDToTwoState(mode: activeStageMode)
                ? collapsedHUDMessage(for: activeStageMode, explicitMessage: activeHUDStageMessage)
                : activeHUDStageMessage
            if shouldCollapseHUDToTwoState(mode: activeStageMode) {
                updateSpeechHUDTextVisibility(!activeStageMessage.isEmpty, at: now)
            } else {
                updateSpeechHUDTextVisibility(false, at: now, armHold: false)
            }
            HUDManager.shared.update(
                mode: activeStageMode,
                message: activeStageMessage,
                language: activeLocale.identifier,
                recognitionControlMode: activeHUDStageControlMode ?? controlMode,
                inputDeviceIcon: hudInputIcon(),
                inputDeviceHealth: hudInputHealth(),
                contextIcon: hudContextIcon()
            )
            return
        }
        if isWakeGatedStandby {
            clearHUDOverride()
            clearUnarmedWakePreview()
            updateSpeechHUDTextVisibility(false, at: now, armHold: !suppressCompletedDictationExitBars)
            logWakeHUDStateIfNeeded(
                reason: "wake-standby-hidden",
                controlMode: controlMode,
                typingEligible: typingHUDEligible,
                effectiveDictating: effectiveDictating,
                isSessionActive: recognitionSession.isRunning || isStopping || effectiveDictating || isPTTHeld
            )
            ensureRecognitionSessionForVisibleHUD(reason: "wake-standby-hidden")
            if isSpeechExitBarsHoldActive(at: now) {
                showSpeechBarsHUD(recognitionControlMode: controlMode)
                return
            }
            if HUDManager.shared.isTemporaryHUDActive || HUDManager.shared.state.isLanguageIndicatorVisible {
                return
            }
            HUDManager.shared.hide()
            return
        }
        let isSessionActive = recognitionSession.isRunning || isStopping || effectiveDictating || isPTTHeld
        if !isContinuousActive && !isSessionActive {
            clearHUDOverride()
            updateSpeechHUDTextVisibility(false, at: now, armHold: !suppressCompletedDictationExitBars)
            if isSpeechExitBarsHoldActive(at: now) {
                showSpeechBarsHUD(recognitionControlMode: controlMode)
                return
            }
            if isPushToTalkOnlyIdle {
                if HUDManager.shared.isTemporaryHUDActive || HUDManager.shared.state.isLanguageIndicatorVisible {
                    return
                }
                HUDManager.shared.hide()
                return
            }
            if realHardware.isEmpty {
                HUDManager.shared.update(
                    mode: .feedback,
                    message: NSLocalizedString("speech.no_mic_detected", comment: ""),
                    language: activeLocale.identifier,
                    recognitionControlMode: controlMode,
                    inputDeviceIcon: hudInputIcon(),
                    inputDeviceHealth: .error,
                    contextIcon: hudContextIcon()
                )
                return
            }
            // Keep the HUD visible briefly if a temporary toast or language indicator is active.
            if HUDManager.shared.isTemporaryHUDActive || HUDManager.shared.state.isLanguageIndicatorVisible {
                return
            }
            HUDManager.shared.hide()
            return
        }
        if featureAvailability.dictationEnabled,
           !featureAvailability.commandEnabled,
           !focusedTypingEvidence {
            clearHUDOverride()
            updateSpeechHUDTextVisibility(false, at: now, armHold: !suppressCompletedDictationExitBars)
            logWakeHUDStateIfNeeded(
                reason: "dictation-only-without-focus-hidden",
                controlMode: controlMode,
                typingEligible: typingHUDEligible,
                effectiveDictating: effectiveDictating,
                isSessionActive: recognitionSession.isRunning || isStopping || effectiveDictating || isPTTHeld
            )
            if isSpeechExitBarsHoldActive(at: now) {
                showSpeechBarsHUD(recognitionControlMode: controlMode)
                return
            }
            HUDManager.shared.hide()
            return
        }

        if realHardware.isEmpty {
            updateSpeechHUDTextVisibility(false, at: now, armHold: false)
            HUDManager.shared.update(
                mode: .feedback,
                message: NSLocalizedString("speech.no_mic_detected", comment: ""),
                language: activeLocale.identifier,
                recognitionControlMode: controlMode,
                inputDeviceIcon: hudInputIcon(),
                inputDeviceHealth: .error,
                contextIcon: hudContextIcon()
            )
            return
        }

        let mode: HUDMode; var message = ""
        let shouldShowProcessingDots = isStopping && shouldShowProcessingDotsDuringStop
        let shouldShowRecognizingWhileDictating =
            effectiveDictating && dictationHandler.isAwaitingPartialReconciliation
        let shouldShowIdleAutoDictationHUD =
            controlMode == .auto
            && typingHUDEligible
            && !isStopping
            && lastTranscript.isEmpty
            && !effectiveDictating
        if isWakeGated && !wakeFollowUpActive && !isStopping && !effectiveDictating {
            clearHUDOverride()
            clearUnarmedWakePreview()
            updateSpeechHUDTextVisibility(false, at: now, armHold: !suppressCompletedDictationExitBars)
            logWakeHUDStateIfNeeded(
                reason: "wake-gated-hidden-before-mode-selection",
                controlMode: controlMode,
                typingEligible: typingHUDEligible,
                effectiveDictating: effectiveDictating,
                isSessionActive: isSessionActive
            )
            if isSpeechExitBarsHoldActive(at: now) {
                showSpeechBarsHUD(recognitionControlMode: controlMode)
                return
            }
            HUDManager.shared.hide()
            return
        }
        else if shouldCollapseHandsFreeHUDToStandby { mode = .standby }
        else if shouldShowProcessingDots || shouldShowRecognizingWhileDictating { mode = .organizing }
        else if effectiveDictating { mode = .dictation; message = remainingDictationHUDText() }
        else if shouldShowIdleAutoDictationHUD { mode = .listening }
        else if !lastTranscript.isEmpty { mode = .command; message = lastTranscript }
        else { mode = .listening }
        if shouldCollapseHUDToTwoState(mode: mode) {
            message = collapsedHUDMessage(for: mode, explicitMessage: message)
            let shouldShowCollapsedText = !message.isEmpty || dictationHandler.isInputMutationActive
            updateSpeechHUDTextVisibility(shouldShowCollapsedText, at: now)
        } else {
            updateSpeechHUDTextVisibility(false, at: now)
            if mode == .standby, isSpeechExitBarsHoldActive(at: now) {
                showSpeechBarsHUD(recognitionControlMode: controlMode)
                return
            }
        }
        if message.isEmpty {
            switch playbackLeakState {
            case .suspectedPlaybackLeak:
                message = String(localized: "speech.playback_leak.detected")
            case .speechSuppressionActive:
                if mode == .listening || mode == .dictation {
                    message = String(localized: "speech.playback_leak.suppression_active")
                }
            case .none:
                break
            }
        }
        HUDManager.shared.update(mode: mode, message: message, language: activeLocale.identifier, recognitionControlMode: controlMode, inputDeviceIcon: hudInputIcon(), inputDeviceHealth: hudInputHealth(), contextIcon: hudContextIcon())
    }

    private func shouldUseProcessingDotsForCurrentMode() -> Bool {
        switch hudRecognitionControlMode {
        case .dictation:
            return true
        case .command:
            return false
        case .auto:
            return authoritativeInputControlSnapshot.interactionState.isTyping
        }
    }

    private func showPTTUnavailableHUD() {
        HUDManager.shared.update(
            mode: .feedback,
            message: NSLocalizedString("speech.no_mic_detected", comment: ""),
            language: activeLocale.identifier,
            recognitionControlMode: hudRecognitionControlMode,
            inputDeviceIcon: hudInputIcon(),
            inputDeviceHealth: .error,
            contextIcon: hudContextIcon()
        )
    }

    // MARK: - Mic Progress Ring
    private func startMicProgressUI(durationSec: TimeInterval, generation gen: Int) {
        micProgressTimer?.invalidate()
        segmentStartedAt = .distantPast
        segmentDurationSec = max(durationSec, 0.1)
        micProgressLockedPID = sessionTargetPID; isMicProgressPausedForTarget = false
        micProgressSilentTicks = 0
        micProgressActiveTicks = 0
        latestVoiceActivity = false
        latestVoiceRMS = 0
        HUDManager.shared.updateMicProgress(progress: 0.0, visible: false)
        micProgressTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                guard self.sessionGeneration == gen, !self.isMicProgressPausedForTarget else { return }
                
                // Rely solely on the robust adaptive VAD from AudioCaptureSession
                let isVoiceActive = self.latestVoiceActivity

                if isVoiceActive {
                    self.micProgressSilentTicks = 0
                    self.micProgressActiveTicks += 1
                    guard self.micProgressActiveTicks >= 3 else { return }
                    if self.segmentStartedAt == .distantPast {
                        self.segmentStartedAt = Date()
                        HUDManager.shared.updateMicProgress(progress: 0.0, visible: true)
                        return
                    }
                    let elapsed = Date().timeIntervalSince(self.segmentStartedAt)
                    let progress = CGFloat(min(max(elapsed / self.segmentDurationSec, 0.0), 1.0))
                    HUDManager.shared.updateMicProgress(progress: progress, visible: true)
                    return
                }

                self.micProgressSilentTicks += 1
                if self.micProgressSilentTicks >= 3 {
                    self.micProgressActiveTicks = 0
                    self.segmentStartedAt = .distantPast
                    HUDManager.shared.updateMicProgress(progress: 0.0, visible: false)
                }
            }
        }
    }

    private func stopMicProgressUI(keepVisible: Bool) {
        micProgressTimer?.invalidate(); micProgressTimer = nil
        micProgressSilentTicks = 0
        micProgressActiveTicks = 0
        latestVoiceActivity = false
        latestVoiceRMS = 0
        let wasPaused = isMicProgressPausedForTarget; isMicProgressPausedForTarget = false; micProgressLockedPID = nil
        HUDManager.shared.updateMicProgress(progress: keepVisible ? (wasPaused ? 0.0 : 1.0) : 0.0, visible: keepVisible)
    }

    // MARK: - Engine Restart
    private func scheduleEngineRestart(reason: String, debounce: TimeInterval? = nil) {
        if Self.shouldSuppressRecognitionFailureDuringRestart(reason: reason) {
            suppressRecognitionFailuresUntil = Date().addingTimeInterval(2.5)
            suppressRecognitionFailuresReason = reason
        }
        let wait = debounce ?? engineRestartDebounce
        pendingEngineRestartWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }; self.pendingEngineRestartWorkItem = nil; self.performEngineRestart(reason: reason)
        }
        pendingEngineRestartWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + wait, execute: work)
    }

    private func performEngineRestart(reason: String) {
        let elapsed = Date().timeIntervalSince(lastEngineRestartAt)
        if elapsed < engineRestartMinInterval { scheduleEngineRestart(reason: "\(reason)-throttled", debounce: engineRestartMinInterval - elapsed); return }
        metrics.engineRestarts += 1
        beginTypingRecoveryHold(reason: "engine-restart-\(reason)")
        continuousRecoveryWorkItem?.cancel()
        continuousRecoveryWorkItem = nil
        let shouldFullyRebuild = Self.shouldFullyRebuildForEngineRestart(reason: reason)
        routeRebuildGraceUntil = Date().addingTimeInterval((shouldFullyRebuild ? 0.12 : 0.25) + 0.45)
        if shouldFullyRebuild {
            GlobalLogger.speech.info("[AudioRoute] performing full speech rebuild reason=\(reason)")
            finalizationWorkItem?.cancel()
            finalizationWorkItem = nil
            stopTimer?.invalidate()
            stopTimer = nil
            resetHUDTransientState()
            teardownEngine()
        } else {
            stopAndFinalize(discardTranscript: Self.shouldDiscardTranscriptOnEngineRestart(reason: reason))
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + (shouldFullyRebuild ? 0.12 : 0.25)) { [weak self] in
            guard let self else { return }
            if self.isAlwaysListeningEnabled { self.startOnce() }
            self.lastEngineRestartAt = Date()
            self.maybeLogRuntimeMetrics(force: false)
        }
    }

    static func shouldDiscardTranscriptOnEngineRestart(reason: String) -> Bool {
        reason == "input-device-selection"
            || reason == "default-input-device-changed"
            || reason == "audio-route-changed"
    }

    static func shouldSuppressRecognitionFailureDuringRestart(reason: String) -> Bool {
        reason == "input-device-selection"
            || reason == "default-input-device-changed"
            || reason == "audio-route-changed"
            || reason == "audio-buffer-stall"
            || reason.contains("headset")
    }

    static func shouldFullyRebuildForEngineRestart(reason: String) -> Bool {
        reason == "input-device-selection"
            || reason == "default-input-device-changed"
            || reason == "audio-route-changed"
            || reason == "audio-buffer-stall"
            || reason.contains("headset")
    }

    private func refreshHeadsetVoiceProcessingPolicy() {
        let isSuppressed = Date() < headsetVoiceProcessingSuppressedUntil
        audioCapture.allowAutomaticHeadsetVoiceProcessing = !isSuppressed
        if !isSuppressed, !headsetVoiceProcessingFaultTimes.isEmpty {
            headsetVoiceProcessingFaultTimes.removeAll()
        }
    }

    private func noteRecoverableHeadsetVoiceProcessingFailure(reason: String) {
        guard isHeadsetLikeInputDevice else { return }

        let now = Date()
        headsetVoiceProcessingFaultTimes.append(now)
        headsetVoiceProcessingFaultTimes.removeAll { now.timeIntervalSince($0) > 18 }
        guard headsetVoiceProcessingFaultTimes.count >= 3 else { return }
        guard now >= headsetVoiceProcessingSuppressedUntil else { return }

        headsetVoiceProcessingSuppressedUntil = now.addingTimeInterval(180)
        headsetVoiceProcessingFaultTimes.removeAll()
        audioCapture.allowAutomaticHeadsetVoiceProcessing = false
        GlobalLogger.speech.info(
            "[VoiceProcessingIO] suppress headset auto-enable for 180s reason=\(reason) input=\(currentResolvedInputDeviceName)"
        )
        if pendingEngineRestartWorkItem == nil {
            scheduleEngineRestart(reason: "headset-vpio-suppressed", debounce: 0.05)
        }
    }

    // MARK: - Device Management
    func refreshInputDevices() {
        var devices: [AudioInputDevice] = [.defaultSystem]
        let realCaptureUIDs = realCaptureDeviceUIDs()
        let realCaptureNames = realCaptureDeviceNames()
        var dedupedByName: [String: AudioInputDevice] = [:]
        var propAddr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var dataSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &propAddr, 0, nil, &dataSize) == noErr else { return }
        let count = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var ids = [AudioDeviceID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &propAddr, 0, nil, &dataSize, &ids) == noErr else { return }
        for id in ids {
            var name = "Unknown Device"; var nameSize = UInt32(MemoryLayout<CFString?>.size)
            var nameAddr = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyDeviceNameCFString, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
            let nameRef = UnsafeMutablePointer<CFString?>.allocate(capacity: 1)
            nameRef.initialize(to: nil)
            defer {
                nameRef.deinitialize(count: 1)
                nameRef.deallocate()
            }
            if AudioObjectGetPropertyData(id, &nameAddr, 0, nil, &nameSize, nameRef) == noErr, let resolvedName = nameRef.pointee {
                name = resolvedName as String
            }
            var addr = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreamConfiguration, mScope: kAudioDevicePropertyScopeInput, mElement: 0)
            var size: UInt32 = 0; AudioObjectGetPropertyDataSize(id, &addr, 0, nil, &size)
            if size > 0 {
                let rawBuffer = UnsafeMutableRawPointer.allocate(
                    byteCount: Int(size),
                    alignment: MemoryLayout<AudioBufferList>.alignment
                )
                defer { rawBuffer.deallocate() }
                let bufferList = rawBuffer.bindMemory(to: AudioBufferList.self, capacity: 1)
                guard AudioObjectGetPropertyData(id, &addr, 0, nil, &size, bufferList) == noErr else { continue }
                let channels = UnsafeMutableAudioBufferListPointer(bufferList).reduce(0) { $0 + Int($1.mNumberChannels) }
                if channels > 0 {
                    var uid = "\(id)"; var uidSize = UInt32(MemoryLayout<CFString?>.size)
                    var uidAddr = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyDeviceUID, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
                    let uidRef = UnsafeMutablePointer<CFString?>.allocate(capacity: 1)
                    uidRef.initialize(to: nil)
                    defer {
                        uidRef.deinitialize(count: 1)
                        uidRef.deallocate()
                    }
                    if AudioObjectGetPropertyData(id, &uidAddr, 0, nil, &uidSize, uidRef) == noErr, let resolvedUID = uidRef.pointee {
                        uid = resolvedUID as String
                    }
                    let transportType = audioDeviceTransportType(id)
                    guard shouldKeepInputDeviceCandidate(
                        name: name,
                        uid: uid,
                        transportType: transportType,
                        realCaptureUIDs: realCaptureUIDs,
                        realCaptureNames: realCaptureNames
                    ) else { continue }
                    var icon = "mic.fill"; let ln = name.lowercased()
                    if ln.contains("airpods") { icon = "airpods"; if ln.contains("pro") { icon = "airpodspro" }; if ln.contains("max") { icon = "airpodsmax" } }
                    else if ln.contains("studio display") { icon = "monitor" }
                    else if ln.contains("external") { icon = "mic.badge.plus" }
                    else if ln.contains("macbook") || ln.contains("built-in") { icon = "laptopcomputer" }
                    let candidate = AudioInputDevice(id: id, name: name, uid: uid, iconName: icon)
                    let key = normalizedInputDeviceName(name)
                    if let existing = dedupedByName[key] {
                        if shouldReplaceInputDeviceCandidate(
                            existing: existing,
                            replacementName: name,
                            replacementUID: uid,
                            replacementTransportType: transportType
                        ) {
                            dedupedByName[key] = candidate
                        }
                    } else {
                        dedupedByName[key] = candidate
                    }
                }
            }
        }
        let coreDevices = dedupedByName.values.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
        devices.append(contentsOf: canonicalInputDevices(from: coreDevices))
        availableInputDevices = devices
        logVisibleInputDevices(devices, context: "refresh")

        if let remappedID = remapSelectedInputDeviceIfNeeded(using: devices) {
            if remappedID != selectedInputDeviceID {
                GlobalLogger.speech.info("[AudioRoute] remapped selected input to replacement device id=\(remappedID)")
                applySelectedInputDeviceID(remappedID, allowRestart: false, reason: "refresh-remap")
            }
        } else if selectedInputDeviceID != 0 && !devices.contains(where: { $0.id == selectedInputDeviceID }) {
            GlobalLogger.speech.info("[AudioRoute] selected input disappeared, falling back to system default")
            applySelectedInputDeviceID(0, allowRestart: false, reason: "refresh-fallback")
        } else if selectedInputDeviceID != 0,
                  let selected = devices.first(where: { $0.id == selectedInputDeviceID }) {
            selectedInputDeviceUIDHint = selected.uid
            selectedInputDeviceNameHint = selected.name
        }
        refreshContinuousHUD()
        maybeRevealHUDForHeadsetChange()
    }

    func syncHUDState() {
        refreshContinuousHUD(isDictating: isDictating)
    }

    private func setupAudioDeviceListeners() {
        let addresses: [AudioObjectPropertyAddress] = [
            AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultInputDevice, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain),
            AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain),
            AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        ]
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            DispatchQueue.main.async { guard let self else { return }
                let before = self.currentAudioRouteSnapshot()
                self.temporaryFallbackInputDeviceID = nil
                self.refreshInputDevices()
                let after = self.currentAudioRouteSnapshot()
                GlobalLogger.speech.info(
                    "[AudioRoute] selectedInputID=\(self.selectedInputDeviceID) effectiveInputID=\(after.effectiveInputID) defaultInputID=\(after.defaultInputID) defaultOutputID=\(after.defaultOutputID) effectiveInputName=\(self.audioDeviceName(after.effectiveInputID)) defaultOutputName=\(self.audioDeviceName(after.defaultOutputID))"
                )
                let hud = HUDManager.shared
                hud.update(
                    mode: hud.state.mode,
                    message: hud.state.message,
                    language: hud.state.language,
                    recognitionControlMode: self.hudRecognitionControlMode,
                    inputDeviceIcon: self.hudInputIcon(),
                    inputDeviceHealth: self.hudInputHealth(),
                    contextIcon: self.hudContextIcon()
                )
                let active = self.audioCapture.isRunning || self.recognitionSession.isRunning || self.isAlwaysListeningEnabled
                if active && self.shouldRestartForAudioRouteChange(from: before, to: after) {
                    self.scheduleEngineRestart(reason: "audio-route-changed")
                }
            }
        }
        for var address in addresses {
            AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, nil, block)
        }
    }

    // MARK: - Focus / Typing Detection (preserved from original)
    private var isTypingMode: Bool {
        let availability = currentVoiceFeatureAvailability()
        if availability.dictationEnabled && !availability.commandEnabled {
            return focusedTypingHUDEvidence()
        }
        switch effectiveRecognitionControlMode(for: availability) {
        case .command:
            return false
        case .dictation:
            return true
        case .auto:
            break
        }

        let liveTypingEvidence = liveTypingHUDEvidence()
        if isWeChatSpecialModeActive() {
            return true
        }
        if hasRecentClickTypingFallbackEvidence() {
            return true
        }
        if isTypingRecoveryHoldActive {
            return liveTypingEvidence || !dictationHandler.screenTypedText.isEmpty
        }
        if !dictationHandler.screenTypedText.isEmpty {
            return true
        }
        if let app = NSWorkspace.shared.frontmostApplication,
           isSystemSearchLikeApplication(app) {
            _ = HUDManager.shared.refreshInputControlFocusState()
            let interactionState = authoritativeInputControlSnapshot.interactionState
            if interactionState == .command || interactionState == .suppressed {
                return false
            }
            if interactionState == .typing {
                return true
            }
            return currentFocusedInputSnapshot() != nil
        }
        return liveTypingEvidence
    }

    private func liveTypingHUDEvidence() -> Bool {
        let frontmostApp = NSWorkspace.shared.frontmostApplication
        if isWeChatSpecialModeActive() {
            return true
        }
        if isSystemSearchLikeApplication(frontmostApp) {
            _ = HUDManager.shared.refreshInputControlFocusState()
        }
        if isSystemSearchLikeApplication(frontmostApp),
           authoritativeInputControlSnapshot.focusState.indicatesTyping {
            return true
        }
        if hasRecentClickTypingFallbackEvidence() {
            return true
        }
        if HUDManager.shared.hasRecentExplicitTypingClickReentry() {
            return true
        }
        if shouldSuppressFocusedTypingForExplicitNonInputClick() {
            return false
        }
        let axEvaluation = HUDManager.shared.currentAXTypingEvaluation()
        if axEvaluation.insertionContextAvailable || axEvaluation.editableLikely || axEvaluation.looselyEditableForWeb {
            return true
        }
        return false
    }

    private func focusedTypingHUDEvidence() -> Bool {
        if isWeChatSpecialModeActive() {
            return true
        }
        if shouldSuppressFocusedTypingForExplicitNonInputClick() {
            return false
        }
        if hasRecentClickTypingFallbackEvidence() {
            return true
        }
        if HUDManager.shared.hasRecentExplicitTypingClickReentry() {
            return true
        }
        let axEvaluation = HUDManager.shared.currentAXTypingEvaluation()
        if axEvaluation.insertionContextAvailable || axEvaluation.editableLikely || axEvaluation.looselyEditableForWeb {
            return true
        }
        return false
    }

    private func resetUtteranceTrackingForNextPhrase() {
        activeUtteranceID = 0
        setCurrentUtteranceArbitration(.init(state: .pending), source: "speech.reset-utterance-tracking")
        recentExpiredWakeFollowUp?.finalizeWorkItem?.cancel()
        recentExpiredWakeFollowUp = nil
        wakeActivatedDuringCurrentUtterance = false
        lastStandbyWakeMissSegmentationAt = .distantPast
        lastWakeMissInsightSignature = nil
        lastWakeMissInsightAt = .distantPast
        isUtteranceActive = false
        isDictating = false
        voiceActivityWithoutPartialSince = nil
        lastTranscript = ""
        lastChangeAt = nil
        lastStableText = ""
        dictationHandler.reset(
            targetPID: preferredTypingInjectionTargetPID(
                sessionTargetPID,
                bundleID: sessionTargetBundleID
            )
        )
        setAuthoritativeSessionTyping(false, source: "speech.reset-utterance-tracking")
    }

    private func partialHasExplicitCommandPrefix(_ text: String) -> Bool {
        let trimmed = canonicalizedExplicitCommandPrefixText(
            text.trimmingCharacters(in: .whitespacesAndNewlines)
        ).trimmingLeadingCommandPrefixIgnorables()
        guard !trimmed.isEmpty else { return false }

        let prefixes = VoiceCommandRouter.effectiveCommandPrefixes(
            for: activeLocale.identifier,
            overrides: commandRouter.languageTermsOverrides
        ).sorted { $0.count > $1.count }

        let lowered = trimmed.lowercased()
        for prefix in prefixes {
            let candidate = prefix.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !candidate.isEmpty else { continue }
            if lowered.hasPrefix(candidate) {
                return true
            }
        }
        return false
    }

    private func partialMayBecomeExplicitCommandPrefix(_ text: String) -> Bool {
        let trimmed = canonicalizedExplicitCommandPrefixText(
            text.trimmingCharacters(in: .whitespacesAndNewlines)
        ).trimmingLeadingCommandPrefixIgnorables()
        guard !trimmed.isEmpty else { return false }

        let prefixes = VoiceCommandRouter.effectiveCommandPrefixes(
            for: activeLocale.identifier,
            overrides: commandRouter.languageTermsOverrides
        ).sorted { $0.count > $1.count }

        let lowered = trimmed.lowercased()
        for prefix in prefixes {
            let candidate = prefix.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !candidate.isEmpty, lowered.count < candidate.count else { continue }
            if candidate.hasPrefix(lowered) {
                return true
            }
        }
        return false
    }

    private func isExplicitCommandPrefixOnly(_ text: String) -> Bool {
        let trimmed = canonicalizedExplicitCommandPrefixText(
            text.trimmingCharacters(in: .whitespacesAndNewlines)
        ).trimmingLeadingCommandPrefixIgnorables().lowercased()
        guard !trimmed.isEmpty else { return false }

        return VoiceCommandRouter.effectiveCommandPrefixes(
            for: activeLocale.identifier,
            overrides: commandRouter.languageTermsOverrides
        ).contains {
            $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == trimmed
        }
    }

    private func armPendingExplicitCommandPrefix() {
        pendingExplicitCommandPrefixExpiry = Date().addingTimeInterval(pendingExplicitCommandPrefixWindow)
        GlobalLogger.router.info("[Route] armed pending explicit command prefix window")
    }

    private func armPendingExplicitCommandPrefix(reason: String) {
        pendingExplicitCommandPrefixExpiry = Date().addingTimeInterval(pendingExplicitCommandPrefixWindow)
        GlobalLogger.router.info("[Route] armed pending explicit command prefix window reason=\(reason)")
    }

    private func hasPendingExplicitCommandPrefix() -> Bool {
        guard let expiry = pendingExplicitCommandPrefixExpiry else { return false }
        if Date() > expiry {
            pendingExplicitCommandPrefixExpiry = nil
            return false
        }
        return true
    }

    private func consumePendingExplicitCommandPrefixIfNeeded() -> Bool {
        guard let expiry = pendingExplicitCommandPrefixExpiry else { return false }
        let now = Date()
        if now > expiry {
            pendingExplicitCommandPrefixExpiry = nil
            return false
        }
        pendingExplicitCommandPrefixExpiry = nil
        return true
    }

    private func throttledTypingMode(interval: TimeInterval = 0.12) -> Bool {
        let now = Date()
        if now.timeIntervalSince(lastTypingCheckAt) < interval { return cachedTypingMode }
        cachedTypingMode = isTypingMode; lastTypingCheckAt = now; return cachedTypingMode
    }

    private func resetTypingStateCache() {
        cachedTypingMode = false
        lastTypingCheckAt = .distantPast
    }

    private func canonicalizedExplicitCommandPrefixText(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, activeLocale.identifier.hasPrefix("zh") else { return trimmed }

        let prefixes = VoiceCommandRouter.effectiveCommandPrefixes(
            for: activeLocale.identifier,
            overrides: commandRouter.languageTermsOverrides
        )
        guard prefixes.contains(where: { $0 == "执行" }) else { return trimmed }

        let leadingIgnorableCount = trimmed.prefix { character in
            character.unicodeScalars.allSatisfy {
                CharacterSet.whitespacesAndNewlines.contains($0)
                    || CharacterSet.punctuationCharacters.contains($0)
            }
        }.count
        let leadingIgnorables = String(trimmed.prefix(leadingIgnorableCount))
        let commandProbe = String(trimmed.dropFirst(leadingIgnorableCount))

        let variants = ["直径", "致敬", "制景", "之景", "知景"]
        for variant in variants {
            if commandProbe == variant {
                return leadingIgnorables + "执行"
            }
            if commandProbe.hasPrefix(variant) {
                return leadingIgnorables + "执行" + commandProbe.dropFirst(variant.count)
            }
        }
        return trimmed
    }

    private func shouldWaitForInputFocusBeforeContinuousDictationStart(
        availability: VoiceFeatureAvailability? = nil
    ) -> Bool {
        guard isAlwaysListeningEnabled else { return false }
        let availability = availability ?? currentVoiceFeatureAvailability()
        guard availability.dictationEnabled, !availability.commandEnabled else { return false }
        return !focusedTypingHUDEvidence()
    }

    private func shouldShowMissingInputTargetHUD(
        availability: VoiceFeatureAvailability? = nil
    ) -> Bool {
        let availability = availability ?? currentVoiceFeatureAvailability()
        return availability.commandEnabled || !availability.dictationEnabled
    }

    static func shouldAcceptStreamedDictationTargetWithoutLiveFocus(
        sessionTypingMode: Bool,
        screenTypedCount: Int,
        streamedTextSnapshot: String,
        frontmostMatchesTarget: Bool
    ) -> Bool {
        guard sessionTypingMode else { return false }
        guard screenTypedCount > 0 || !streamedTextSnapshot.isEmpty else { return false }
        return frontmostMatchesTarget
    }

    static func shouldTrustLockedWeirdTypingTargetWithoutLiveFocus(
        sessionTypingMode: Bool,
        targetBundleID: String?,
        targetElementFingerprint: String?,
        verificationSnapshotAvailable: Bool,
        frontmostMatchesTarget: Bool
    ) -> Bool {
        guard sessionTypingMode else { return false }
        guard frontmostMatchesTarget else { return false }
        guard isWeirdTypingAppBundleIdentifier(targetBundleID) else { return false }
        return targetElementFingerprint != nil || verificationSnapshotAvailable
    }

    private func hasRecentClickTypingFallbackEvidence() -> Bool {
        guard let frontmostApp = NSWorkspace.shared.frontmostApplication,
              isRecentClickFallbackTypingAppBundle(frontmostApp.bundleIdentifier) else {
            return false
        }
        let hasEvidence: Bool
        if let snapshot = recentClickTypingFallbackSnapshot() {
            armSpecialInputMode(from: snapshot)
            hasEvidence = true
        } else {
            hasEvidence = activeSpecialInputModeSnapshot() != nil
        }
        if hasEvidence {
            GlobalLogger.speech.info(
                "[TypingMode] recent-click fallback evidence bundle=\(frontmostApp.bundleIdentifier ?? "nil")"
            )
        }
        return hasEvidence
    }

    private func hasStrongTypingFallbackEvidence(
        lockedFocusedSnapshot _: FocusedInputSnapshot?,
        lockedTargetMatches _: Bool,
        computedTypingContext: Bool,
        hasAuthoritativeTypingEvidence: Bool,
        hasStreamedDictation: Bool
    ) -> Bool {
        guard recognitionControlMode == .auto, computedTypingContext else {
            return false
        }
        return hasAuthoritativeTypingEvidence || hasStreamedDictation
    }

    private func hasAuthoritativeTypingEvidence() -> Bool {
        if isWeChatSpecialModeActive() {
            return true
        }
        if hasRecentClickTypingFallbackEvidence() {
            return true
        }
        if HUDManager.shared.hasRecentExplicitTypingClickReentry() {
            return true
        }
        return resolveCurrentFocusedInput() != nil
    }

    private func beginTypingRecoveryHold(reason: String) {
        guard recognitionControlMode == .auto else { return }
        guard isAlwaysListeningEnabled || isPTTHeld || recognitionSession.isRunning || isStopping else { return }
        guard sessionTypingMode || !dictationHandler.screenTypedText.isEmpty else { return }
        typingRecoveryHoldUntil = Date().addingTimeInterval(2.0)
        typingRecoveryHoldReason = reason
        syncInputControlState(source: "speech.begin-typing-recovery")
        GlobalLogger.speech.info(
            "[TypingMode] begin recovery hold reason=\(reason) targetPID=\(sessionTargetPID ?? 0) targetBundle=\(sessionTargetBundleID ?? "nil")"
        )
    }

    private func endTypingRecoveryHold(reason: String) {
        guard typingRecoveryHoldUntil != .distantPast || typingRecoveryHoldReason != nil else { return }
        let priorReason = typingRecoveryHoldReason ?? "unknown"
        typingRecoveryHoldUntil = .distantPast
        typingRecoveryHoldReason = nil
        syncInputControlState(source: "speech.end-typing-recovery")
        GlobalLogger.speech.info("[TypingMode] end recovery hold reason=\(reason) prior=\(priorReason)")
    }

    private func hasLockedFocusedInputTarget(_ snapshot: FocusedInputSnapshot? = nil) -> Bool {
        guard recognitionControlMode == .auto else { return false }
        guard sessionTargetPID != nil || sessionTargetBundleID != nil || sessionTargetElementFingerprint != nil else {
            return false
        }
        guard let snapshot = snapshot ?? currentFocusedInputSnapshot() else { return false }

        if let targetPID = sessionTargetPID, targetPID > 0, snapshot.pid != targetPID {
            return false
        }
        if let targetBundleID = sessionTargetBundleID, snapshot.bundleID != targetBundleID {
            return false
        }
        if let targetFingerprint = sessionTargetElementFingerprint,
           snapshot.elementFingerprint != targetFingerprint {
            return false
        }
        return true
    }

    // MARK: - Focus Snapshots
    private struct FocusedInputSnapshot {
        let pid: pid_t
        let bundleID: String?
        let elementFingerprint: String?
        let source: FocusedInputSource
        let windowTitle: String?
        let anchorPoint: CGPoint?
    }

    private func axStringAttribute(_ el: AXUIElement, _ attr: CFString) -> String? {
        var v: CFTypeRef?; guard AXUIElementCopyAttributeValue(el, attr, &v) == .success, let r = v as? String else { return nil }
        return r.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    private func axCGPointAttribute(_ el: AXUIElement, _ attr: CFString) -> CGPoint? {
        var v: CFTypeRef?; guard AXUIElementCopyAttributeValue(el, attr, &v) == .success, let r = v, CFGetTypeID(r) == AXValueGetTypeID() else { return nil }
        let a = r as! AXValue; guard AXValueGetType(a) == .cgPoint else { return nil }; var p = CGPoint.zero; return AXValueGetValue(a, .cgPoint, &p) ? p : nil
    }
    private func axCGSizeAttribute(_ el: AXUIElement, _ attr: CFString) -> CGSize? {
        var v: CFTypeRef?; guard AXUIElementCopyAttributeValue(el, attr, &v) == .success, let r = v, CFGetTypeID(r) == AXValueGetTypeID() else { return nil }
        let a = r as! AXValue; guard AXValueGetType(a) == .cgSize else { return nil }; var s = CGSize.zero; return AXValueGetValue(a, .cgSize, &s) ? s : nil
    }
    private func axSelectedRange(_ el: AXUIElement) -> NSRange? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, kAXSelectedTextRangeAttribute as CFString, &value) == .success,
              let raw = value,
              CFGetTypeID(raw) == AXValueGetTypeID() else { return nil }
        let ax = raw as! AXValue
        guard AXValueGetType(ax) == .cfRange else { return nil }
        var range = CFRange()
        guard AXValueGetValue(ax, .cfRange, &range) else { return nil }
        guard range.location >= 0, range.length >= 0 else { return nil }
        return NSRange(location: range.location, length: range.length)
    }
    private func axValueText(_ el: AXUIElement) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, kAXValueAttribute as CFString, &value) == .success else { return nil }
        if let text = value as? String { return text }
        if let attributed = value as? NSAttributedString { return attributed.string }
        return nil
    }
    private func sanitizeFP(_ raw: String?, fallback: String = "-") -> String {
        guard let raw, !raw.isEmpty else { return fallback }
        return raw.replacingOccurrences(of: "|", with: "/").replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespacesAndNewlines)
    }
    private func bundleIsSystemSearchLike(_ bundleID: String?) -> Bool {
        guard let bundleID = bundleID?.lowercased() else { return false }
        return bundleID.contains("apple.siri")
            || bundleID == "com.apple.siri"
            || bundleID == "com.apple.siri.launcher"
            || bundleID == "com.apple.spotlight"
            || bundleID == "com.apple.spotlightui"
            || bundleID == "com.apple.notificationcenterui"
    }
    private func isSystemSearchLikeApplication(_ app: NSRunningApplication?) -> Bool {
        guard let app else { return false }
        let appName = app.localizedName?.lowercased() ?? ""
        return bundleIsSystemSearchLike(app.bundleIdentifier)
            || appName.contains("siri")
            || appName.contains("spotlight")
    }
    private func preferredTypingInjectionTargetPID(_ pid: pid_t?, bundleID: String?) -> pid_t? {
        if bundleIsSystemSearchLike(bundleID)
            || isSystemSearchLikeApplication(NSWorkspace.shared.frontmostApplication) {
            return nil
        }
        guard let pid, pid > 0 else { return nil }
        if let frontmost = NSWorkspace.shared.frontmostApplication {
            if frontmost.processIdentifier == pid {
                return nil
            }
            if let bundleID, !bundleID.isEmpty, frontmost.bundleIdentifier == bundleID {
                return nil
            }
        }
        return pid
    }
    private func normalizedInjectionTargetPID(_ pid: pid_t?, bundleID: String?) -> pid_t? {
        if bundleIsSystemSearchLike(bundleID)
            || bundleIsSystemSearchLike(NSWorkspace.shared.frontmostApplication?.bundleIdentifier) {
            return nil
        }
        guard let pid, pid > 0 else { return nil }
        return pid
    }
    private func axFocusedRole(_ el: AXUIElement) -> String {
        axStringAttribute(el, kAXRoleAttribute as CFString) ?? ""
    }

    private func buildFocusedInputDiagnosticsReport() -> String {
        let now = Date()
        let frontmostApp = NSWorkspace.shared.frontmostApplication
        let frontBundleID = frontmostApp?.bundleIdentifier
        let frontPID = frontmostApp?.processIdentifier ?? 0
        let axTrusted = accessibilityTrustedSnapshot || AXIsProcessTrusted()
        let hudEvaluation = HUDManager.shared.currentAXTypingEvaluation()
        _ = HUDManager.shared.refreshInputControlFocusState()
        let arbiterState = authoritativeInputControlSnapshot
        let hudTypingState = arbiterState.focusState.indicatesTyping
        let hudDisplayState = HUDManager.shared.currentDisplayStateSnapshot()
        let hudSuppressionState = HUDManager.shared.currentTypingSuppressionStateSnapshot()
        let snapshot = currentFocusedInputSnapshot()
        let isoFormatter = ISO8601DateFormatter()

        func formatRect(_ rect: CGRect?) -> String {
            guard let rect else { return "nil" }
            return "{x=\(Int(rect.origin.x.rounded())), y=\(Int(rect.origin.y.rounded())), w=\(Int(rect.width.rounded())), h=\(Int(rect.height.rounded()))}"
        }

        var lines: [String] = []
        lines.append("Aether Focused Input Diagnostics")
        lines.append("generatedAt=\(isoFormatter.string(from: now))")
        lines.append("axTrusted=\(axTrusted)")
        lines.append("frontmostApp.name=\(frontmostApp?.localizedName ?? "nil")")
        lines.append("frontmostApp.bundleID=\(frontBundleID ?? "nil")")
        lines.append("frontmostApp.pid=\(frontPID)")
        lines.append("speech.sessionTargetPID=\(sessionTargetPID.map(String.init) ?? "nil")")
        lines.append("speech.sessionTargetBundleID=\(sessionTargetBundleID ?? "nil")")
        lines.append("speech.sessionTargetFingerprint=\(sessionTargetElementFingerprint ?? "nil")")
        lines.append("speech.sessionTargetSource=\(sessionTargetSource?.rawValue ?? "nil")")
        lines.append("speech.currentFocusedInputSnapshot.pid=\(snapshot.map { String($0.pid) } ?? "nil")")
        lines.append("speech.currentFocusedInputSnapshot.bundleID=\(snapshot?.bundleID ?? "nil")")
        lines.append("speech.currentFocusedInputSnapshot.fingerprint=\(snapshot?.elementFingerprint ?? "nil")")
        lines.append("speech.currentFocusedInputSnapshot.source=\(snapshot?.source.rawValue ?? "nil")")
        lines.append("speech.currentFocusedInputSnapshot.windowTitle=\(snapshot?.windowTitle ?? "nil")")
        let anchorPointSummary = snapshot.flatMap { snap in
            snap.anchorPoint.map { point in
                "{x=\(Int(point.x.rounded())), y=\(Int(point.y.rounded()))}"
            }
        } ?? "nil"
        lines.append("speech.currentFocusedInputSnapshot.anchorPoint=\(anchorPointSummary)")
        lines.append("hud.lastKnownTypingState=\(hudTypingState)")
        lines.append("arbiter.interactionState=\(arbiterState.interactionState.rawValue)")
        lines.append("arbiter.focusState=\(arbiterState.focusState.rawValue)")
        lines.append("arbiter.sessionState=\(arbiterState.sessionState.rawValue)")
        lines.append("hud.display.mode=\(hudDisplayState.mode.rawValue)")
        lines.append("hud.display.isTypingContext=\(hudDisplayState.isTypingContext)")
        lines.append("hud.display.recognitionControlMode=\(hudDisplayState.recognitionControlMode.rawValue)")
        lines.append("hud.typingExplicitlySuppressed=\(HUDManager.shared.isTypingExplicitlySuppressedForCurrentApp())")
        lines.append("hud.requiresExplicitTypingReentry=\(hudSuppressionState.requiresExplicitTypingReentry)")
        lines.append("hud.explicitTypingReentryBundleID=\(hudSuppressionState.explicitTypingReentryBundleID ?? "nil")")
        lines.append("hud.explicitTypingReentrySourceFingerprint=\(hudSuppressionState.explicitTypingReentrySourceFingerprint ?? "nil")")
        lines.append("hud.explicitTypingReentrySourceRect=\(formatRect(hudSuppressionState.explicitTypingReentrySourceRect))")
        lines.append("hud.typingSuppressedUntil=\(isoFormatter.string(from: hudSuppressionState.typingSuppressedUntil))")
        lines.append("hud.preferredExplicitTypingInputRect=\(formatRect(hudSuppressionState.preferredExplicitTypingInputRect))")
        lines.append("hud.ax.role=\(hudEvaluation.role)")
        lines.append("hud.ax.editableLikely=\(hudEvaluation.editableLikely)")
        lines.append("hud.ax.insertionContextAvailable=\(hudEvaluation.insertionContextAvailable)")
        lines.append("hud.ax.looselyEditableForWeb=\(hudEvaluation.looselyEditableForWeb)")
        lines.append("hud.ax.hasEditableAttribute=\(hudEvaluation.hasEditableAttribute)")
        lines.append("hud.ax.hasSettableValue=\(hudEvaluation.hasSettableValue)")
        lines.append("hud.ax.hasEditableAncestor=\(hudEvaluation.hasEditableAncestor)")

        let mouseHistory = HUDManager.shared.recentMouseDownDiagnosticHistory()
        if mouseHistory.isEmpty {
            lines.append("hud.recentMouseDownHistory=empty")
        } else {
            for (index, record) in mouseHistory.enumerated() {
                lines.append(
                    "[mouseDown:\(index)] ts=\(isoFormatter.string(from: record.timestamp)) bundleID=\(record.bundleID ?? "nil") point={x=\(Int(record.point.x.rounded())), y=\(Int(record.point.y.rounded()))} preferredRect=\(formatRect(record.preferredInputRect)) hitPreferredRect=\(record.hitPreferredInputRect)"
                )
            }
        }

        let suppressionHistory = HUDManager.shared.typingSuppressionDiagnosticHistory()
        if suppressionHistory.isEmpty {
            lines.append("hud.typingSuppressionHistory=empty")
        } else {
            for (index, record) in suppressionHistory.enumerated() {
                lines.append(
                    "[typingSuppression:\(index)] ts=\(isoFormatter.string(from: record.timestamp)) suppressed=\(record.suppressed) reason=\(record.reason) bundleID=\(record.bundleID ?? "nil") suppressedUntil=\(isoFormatter.string(from: record.suppressedUntil)) requiresExplicitTypingReentry=\(record.requiresExplicitTypingReentry)"
                )
            }
        }

        let systemWide = AXUIElementCreateSystemWide()
        var focusedRef: CFTypeRef?
        let focusedResult = AXUIElementCopyAttributeValue(
            systemWide,
            kAXFocusedUIElementAttribute as CFString,
            &focusedRef
        )
        guard focusedResult == .success,
              let focusedRef,
              CFGetTypeID(focusedRef) == AXUIElementGetTypeID() else {
            lines.append("focusedElement.error=\(focusedResult.rawValue)")
            return lines.joined(separator: "\n")
        }

        let focused = focusedRef as! AXUIElement
        appendAXElementDiagnostics(
            &lines,
            element: focused,
            label: "focused",
            bundleID: frontBundleID
        )

        if let editableAncestor = editableAncestor(for: focused),
           makeElementFingerprint(editableAncestor) != makeElementFingerprint(focused) {
            appendAXElementDiagnostics(
                &lines,
                element: editableAncestor,
                label: "editableAncestor",
                bundleID: frontBundleID
            )
        }

        var currentParentRef: CFTypeRef?
        var parentResult = AXUIElementCopyAttributeValue(
            focused,
            kAXParentAttribute as CFString,
            &currentParentRef
        )
        var depth = 1
        while parentResult == .success,
              let parentRef = currentParentRef,
              CFGetTypeID(parentRef) == AXUIElementGetTypeID(),
              depth <= 6 {
            let parentElement = parentRef as! AXUIElement
            appendAXElementDiagnostics(
                &lines,
                element: parentElement,
                label: "ancestor[\(depth)]",
                bundleID: frontBundleID
            )
            parentResult = AXUIElementCopyAttributeValue(
                parentElement,
                kAXParentAttribute as CFString,
                &currentParentRef
            )
            depth += 1
        }

        if let candidate = findDictationCandidate(in: focused, bundleID: frontBundleID) {
            appendAXElementDiagnostics(
                &lines,
                element: candidate,
                label: "candidate",
                bundleID: frontBundleID
            )
        }

        return lines.joined(separator: "\n")
    }

    private func logWakeWordConfigurationIfNeeded(reason: String) {
        guard isWakeWordEnabled else { return }
        let summary = wakeWordDetector.diagnosticsSummary(for: activeLocale.identifier)
        let signature = "\(reason)|\(isAlwaysListeningEnabled)|\(isDirectCommandEnabled)|\(isAwake)|\(summary)"
        guard signature != lastWakeWordDiagnosticsSignature else { return }
        lastWakeWordDiagnosticsSignature = signature
        GlobalLogger.speech.info(
            "[WakeWordConfig] reason=\(reason) alwaysListening=\(self.isAlwaysListeningEnabled) directCommand=\(self.isDirectCommandEnabled) awake=\(self.isAwake) \(summary)"
        )
    }

    private func appendAXElementDiagnostics(
        _ lines: inout [String],
        element: AXUIElement,
        label: String,
        bundleID: String?
    ) {
        let role = axStringAttribute(element, kAXRoleAttribute as CFString) ?? ""
        let subrole = axStringAttribute(element, kAXSubroleAttribute as CFString) ?? ""
        let title = compactDiagnosticText(axStringAttribute(element, kAXTitleAttribute as CFString))
        let identifier = compactDiagnosticText(axStringAttribute(element, "AXIdentifier" as CFString))
        let placeholder = compactDiagnosticText(axStringAttribute(element, "AXPlaceholderValue" as CFString))
        let valuePreview = compactDiagnosticText(axValueText(element), limit: 120)
        let selectedRange = axSelectedRange(element).map { "{location=\($0.location), length=\($0.length)}" } ?? "nil"
        let markerRangePresent = axAttributeExists(element, "AXSelectedTextMarkerRange" as CFString)
        let editable = axBoolAttribute(element, "AXEditable" as CFString).map(String.init(describing:)) ?? "nil"
        let settableValue = valueAttributeIsSettable(element)
        let insertionContext = hasInsertionContext(element)
        let hasEditableAncestor = editableAncestor(for: element) != nil
        let usableForDictation = isFocusedElementUsableForDictation(element, bundleID: bundleID)
        let fingerprint = makeElementFingerprint(element)
        let position = axCGPointAttribute(element, kAXPositionAttribute as CFString)
            .map { "{x=\(Int($0.x.rounded())), y=\(Int($0.y.rounded()))}" } ?? "nil"
        let size = axCGSizeAttribute(element, kAXSizeAttribute as CFString)
            .map { "{w=\(Int($0.width.rounded())), h=\(Int($0.height.rounded()))}" } ?? "nil"

        lines.append("[\(label)] fingerprint=\(fingerprint)")
        lines.append("[\(label)] role=\(role) subrole=\(subrole) title=\(title) identifier=\(identifier) placeholder=\(placeholder)")
        lines.append("[\(label)] editable=\(editable) settableValue=\(settableValue) insertionContext=\(insertionContext) markerRangePresent=\(markerRangePresent) selectedRange=\(selectedRange)")
        lines.append("[\(label)] hasEditableAncestor=\(hasEditableAncestor) usableForDictation=\(usableForDictation) position=\(position) size=\(size)")
        lines.append("[\(label)] valuePreview=\(valuePreview)")

        let children = axChildElements(element)
        if !children.isEmpty {
            let childSummary = children.prefix(8).enumerated().map { index, child in
                let childRole = axStringAttribute(child, kAXRoleAttribute as CFString) ?? ""
                let childSubrole = axStringAttribute(child, kAXSubroleAttribute as CFString) ?? ""
                let childTitle = compactDiagnosticText(axStringAttribute(child, kAXTitleAttribute as CFString), limit: 40)
                return "#\(index){role=\(childRole),subrole=\(childSubrole),title=\(childTitle)}"
            }.joined(separator: " ")
            lines.append("[\(label)] children=\(childSummary)")
        }
    }

    private func axChildElements(_ element: AXUIElement) -> [AXUIElement] {
        var childrenRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            kAXChildrenAttribute as CFString,
            &childrenRef
        ) == .success,
        let children = childrenRef as? [AXUIElement] else {
            return []
        }
        return children
    }

    private func axAttributeExists(_ element: AXUIElement, _ attr: CFString) -> Bool {
        var value: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, attr, &value) == .success
    }

    private func compactDiagnosticText(_ raw: String?, limit: Int = 80) -> String {
        let text = (raw ?? "nil")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\t", with: " ")
        guard text.count > limit else { return text }
        return String(text.prefix(limit)) + "..."
    }

    static func isHiddenFocusedInputDiagnosticsCommand(_ text: String) -> Bool {
        let normalized = text
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)
            .replacingOccurrences(of: "[\\p{P}\\p{S}]+", with: "", options: .regularExpression)
        return normalized == "芝麻开门" || normalized == "opensesame"
    }

    private func findDictationCandidate(in element: AXUIElement, bundleID: String?, depth: Int = 5) -> AXUIElement? {
        guard depth > 0 else { return nil }
        if isFocusedElementUsableForDictation(element, bundleID: bundleID) { return element }

        if let ancestor = editableAncestor(for: element),
           makeElementFingerprint(ancestor) != makeElementFingerprint(element),
           isFocusedElementUsableForDictation(ancestor, bundleID: bundleID) {
            return ancestor
        }

        var childrenRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenRef) == .success,
              let children = childrenRef as? [AXUIElement] else { return nil }

        for child in children {
            if let found = findDictationCandidate(in: child, bundleID: bundleID, depth: depth - 1) {
                return found
            }
        }
        return nil
    }
    private func makeElementFingerprint(_ el: AXUIElement) -> String {
        let role = sanitizeFP(axStringAttribute(el, kAXRoleAttribute as CFString), fallback: "?")
        let sub = sanitizeFP(axStringAttribute(el, kAXSubroleAttribute as CFString))
        let id = sanitizeFP(axStringAttribute(el, "AXIdentifier" as CFString))
        let title = sanitizeFP(axStringAttribute(el, kAXTitleAttribute as CFString))
        let ph = sanitizeFP(axStringAttribute(el, "AXPlaceholderValue" as CFString))
        let pos = axCGPointAttribute(el, kAXPositionAttribute as CFString).map { "\(Int($0.x.rounded()))x\(Int($0.y.rounded()))" } ?? "-"
        let size = axCGSizeAttribute(el, kAXSizeAttribute as CFString).map { "\(Int($0.width.rounded()))x\(Int($0.height.rounded()))" } ?? "-"
        var wt = "-"; var wr: CFTypeRef?
        if AXUIElementCopyAttributeValue(el, kAXWindowAttribute as CFString, &wr) == .success, let w = wr, CFGetTypeID(w) == AXUIElementGetTypeID() {
            wt = sanitizeFP(axStringAttribute(w as! AXUIElement, kAXTitleAttribute as CFString))
        }
        return [role, sub, id, title, ph, wt, pos, size].joined(separator: "|")
    }
    private struct FrontmostWindowCandidate {
        let title: String?
        let contentBounds: CGRect
    }
    private struct FocusProbeResult {
        let error: AXError
        let element: AXUIElement?
    }
    private struct ResolvedFocusedInput {
        let element: AXUIElement
        let snapshot: FocusedInputSnapshot
    }

    private func focusedElementProbe(for element: AXUIElement) -> FocusProbeResult {
        var focusedRef: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, kAXFocusedUIElementAttribute as CFString, &focusedRef)
        guard result == .success,
              let focusedRef,
              CFGetTypeID(focusedRef) == AXUIElementGetTypeID() else {
            return FocusProbeResult(error: result, element: nil)
        }
        return FocusProbeResult(error: result, element: focusedRef as! AXUIElement)
    }

    private func resolveFocusedInput(from element: AXUIElement) -> ResolvedFocusedInput? {
        var el = element
        var pid: pid_t = 0
        AXUIElementGetPid(el, &pid)
        guard pid > 0 else { return nil }
        let frontBundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        let bundleID = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier
        let effectiveBundleID = bundleID ?? frontBundleID

        if !isFocusedElementUsableForDictation(el, bundleID: effectiveBundleID),
           let ancestor = editableAncestor(for: el),
           isFocusedElementUsableForDictation(ancestor, bundleID: effectiveBundleID) {
            el = ancestor
            AXUIElementGetPid(el, &pid)
            guard pid > 0 else { return nil }
        }

        if !isFocusedElementUsableForDictation(el, bundleID: effectiveBundleID) {
            let role = axFocusedRole(el)
            if bundleIsSystemSearchLike(bundleID)
                || bundleIsSystemSearchLike(frontBundleID)
                || isWeirdTypingAppBundle(bundleID)
                || isWeirdTypingAppBundle(frontBundleID)
                || ["AXWindow", "AXSheet", "AXScrollArea", "AXSplitGroup", "AXGroup", "AXStaticText", "AXWebArea"].contains(role) {
                if let candidate = findDictationCandidate(in: el, bundleID: effectiveBundleID) {
                    el = candidate
                    AXUIElementGetPid(el, &pid)
                    guard pid > 0 else { return nil }
                } else if !(bundleIsSystemSearchLike(bundleID)
                    || bundleIsSystemSearchLike(frontBundleID)
                    || isWeirdTypingAppBundle(bundleID)
                    || isWeirdTypingAppBundle(frontBundleID)) {
                    return nil
                }
            } else {
                return nil
            }
        }

        let snapshot = FocusedInputSnapshot(
            pid: pid,
            bundleID: NSRunningApplication(processIdentifier: pid)?.bundleIdentifier,
            elementFingerprint: makeElementFingerprint(el),
            source: .accessibility,
            windowTitle: axStringAttribute(el, kAXTitleAttribute as CFString),
            anchorPoint: nil
        )
        return ResolvedFocusedInput(element: el, snapshot: snapshot)
    }

    private func frontmostWindowContainingPoint(
        for app: NSRunningApplication,
        point: CGPoint
    ) -> FrontmostWindowCandidate? {
        let options = CGWindowListOption(arrayLiteral: .optionOnScreenOnly, .excludeDesktopElements)
        guard let infos = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return nil
        }

        for info in infos {
            guard let ownerPID = info[kCGWindowOwnerPID as String] as? Int,
                  ownerPID == app.processIdentifier else { continue }
            guard let layer = info[kCGWindowLayer as String] as? Int, layer == 0 else { continue }
            if let alpha = info[kCGWindowAlpha as String] as? Double, alpha <= 0.01 { continue }
            guard let boundsDict = info[kCGWindowBounds as String] else { continue }
            let boundsValue = boundsDict as! CFDictionary
            guard let bounds = CGRect(dictionaryRepresentation: boundsValue), !bounds.isEmpty else { continue }

            var contentBounds = bounds.insetBy(dx: 10, dy: 10)
            if contentBounds.height > 36 {
                contentBounds.size.height -= 32
            }
            guard contentBounds.contains(point) else { continue }
            let candidate = FrontmostWindowCandidate(
                title: info[kCGWindowName as String] as? String,
                contentBounds: contentBounds
            )
            if isAllowedRecentClickFallbackPoint(point, for: app, window: candidate) {
                return candidate
            }
        }
        return nil
    }

    private func isAllowedRecentClickFallbackPoint(
        _ point: CGPoint,
        for app: NSRunningApplication,
        window: FrontmostWindowCandidate
    ) -> Bool {
        guard let bundleID = app.bundleIdentifier else { return true }
        guard bundleID.lowercased().contains("wechat") || bundleID.lowercased().contains("xinwechat") else {
            return true
        }

        if let title = window.title?.lowercased() {
            let blockedMarkers = [
                "settings", "preferences", "moments", "channels", "contacts", "search",
                "设置", "偏好设置", "朋友圈", "视频号", "通讯录", "搜索", "小程序", "收藏"
            ]
            if blockedMarkers.contains(where: title.contains) {
                return false
            }
        }

        let bounds = window.contentBounds
        guard bounds.width >= 520, bounds.height >= 420 else { return false }

        let rightPaneStartX = bounds.minX + min(max(bounds.width * 0.34, 300), bounds.width * 0.52)
        let bottomBandStartY = bounds.minY + bounds.height * 0.62

        return point.x >= rightPaneStartX && point.y >= bottomBandStartY
    }

    private func recentClickTypingFallbackSnapshot() -> FocusedInputSnapshot? {
        let trusted = accessibilityTrustedSnapshot || AXIsProcessTrusted()
        if accessibilityTrustedSnapshot != trusted { accessibilityTrustedSnapshot = trusted }
        guard trusted else { return nil }
        guard let frontmostApp = NSWorkspace.shared.frontmostApplication,
              let bundleID = frontmostApp.bundleIdentifier,
              isRecentClickFallbackTypingAppBundle(bundleID),
              !bundleIsSystemSearchLike(bundleID) else {
            return nil
        }
        guard let anchor = HUDManager.shared.recentMouseDownAnchor(maxAge: 3.0) else { return nil }
        guard anchor.bundleID == nil || anchor.bundleID == bundleID else { return nil }
        guard let window = frontmostWindowContainingPoint(for: frontmostApp, point: anchor.point) else { return nil }

        return FocusedInputSnapshot(
            pid: frontmostApp.processIdentifier,
            bundleID: bundleID,
            elementFingerprint: nil,
            source: .recentClickFallback,
            windowTitle: window.title,
            anchorPoint: anchor.point
        )
    }

    private func resolveCurrentFocusedInput() -> ResolvedFocusedInput? {
        let probe = focusedElementProbe(for: AXUIElementCreateSystemWide())
        guard let element = probe.element else { return nil }
        return resolveFocusedInput(from: element)
    }

    private func currentFocusedInputSnapshot() -> FocusedInputSnapshot? {
        if shouldSuppressFocusedTypingForExplicitNonInputClick() {
            return nil
        }
        if let snapshot = resolveCurrentFocusedInput()?.snapshot {
            return snapshot
        }
        if let snapshot = recentClickTypingFallbackSnapshot() {
            armSpecialInputMode(from: snapshot)
            return snapshot
        }
        if let snapshot = activeSpecialInputModeSnapshot() {
            return snapshot
        }
        if isWeChatAppWideInputModeEnabled(),
           let frontmostApp = NSWorkspace.shared.frontmostApplication {
            return FocusedInputSnapshot(
                pid: frontmostApp.processIdentifier,
                bundleID: frontmostApp.bundleIdentifier,
                elementFingerprint: nil,
                source: .recentClickFallback,
                windowTitle: nil,
                anchorPoint: nil
            )
        }
        return nil
    }
    private func currentFocusedInputVerificationSnapshot() -> InputVerificationSnapshot? {
        guard let resolved = resolveCurrentFocusedInput() else { return nil }
        let selectedRange = axSelectedRange(resolved.element)
        return InputVerificationSnapshot(
            pid: resolved.snapshot.pid,
            bundleID: resolved.snapshot.bundleID,
            elementFingerprint: resolved.snapshot.elementFingerprint,
            valueText: axValueText(resolved.element),
            selectedRangeLocation: selectedRange?.location,
            selectedRangeLength: selectedRange?.length
        )
    }

    private func shouldUseWakeTypingFallback(
        wakeLifecycleActive: Bool,
        recognitionControlMode: RecognitionControlMode,
        featureAvailability: VoiceFeatureAvailability,
        liveTyping: Bool
    ) -> Bool {
        SpeechManager.shouldRestoreWakeTypingFallbackBeforeRouting(
            wakeLifecycleActive: wakeLifecycleActive,
            recognitionControlMode: recognitionControlMode,
            dictationEnabled: featureAvailability.dictationEnabled,
            liveTyping: liveTyping,
            pendingWakeFollowUp: pendingWakeFollowUp != nil,
            sessionTargetAvailable: sessionTargetPID != nil || sessionTargetBundleID != nil || sessionTargetElementFingerprint != nil,
            frontmostMatchesTarget: frontmostApplicationMatches(targetPID: sessionTargetPID, bundleID: sessionTargetBundleID),
            fallbackWindowActive: Date() < wakeTypingFallbackUntil,
            typingSuppressed: shouldSuppressFocusedTypingForExplicitNonInputClick()
        )
    }

    private func shouldUseWakeTypingFallback(
        recognitionControlMode: RecognitionControlMode,
        featureAvailability: VoiceFeatureAvailability,
        liveTyping: Bool
    ) -> Bool {
        shouldUseWakeTypingFallback(
            wakeLifecycleActive: false,
            recognitionControlMode: recognitionControlMode,
            featureAvailability: featureAvailability,
            liveTyping: liveTyping
        )
    }

    private func wakeFollowUpArbitrationResult(
        controlMode: HeadMotionManager.RecognitionControlMode,
        transcript: String,
        routerDecision: VoiceCommandDecision?,
        hasStableTypingEvidence: Bool,
        hasLiveTypingEvidence: Bool
    ) -> UtteranceArbitrationResult {
        let decision = routerDecision ?? commandRouter.routeDetailed(
            transcript: transcript,
            bias: .commandPreferred,
            localeIdentifier: activeLocale.identifier
        )

        return Self.resolveWakeFollowUpArbitration(
            controlMode: controlMode,
            transcript: transcript,
            routerDecision: decision,
            hasStableTypingEvidence: hasStableTypingEvidence,
            hasLiveTypingEvidence: hasLiveTypingEvidence,
            hasCommittedDictation: authoritativeInputControlSnapshot.utteranceDecision == .dictationCommitted
        )
    }

    private func isRewriteTargetStable(for job: ProcessedJob) -> Bool {
        guard let before = job.verificationSnapshot,
              let after = currentFocusedInputVerificationSnapshot() else {
            return false
        }

        return verificationSnapshotsDescribeSameTarget(before, after)
    }

    private func verificationSnapshotsDescribeSameTarget(
        _ before: InputVerificationSnapshot,
        _ after: InputVerificationSnapshot
    ) -> Bool {
        guard before.pid == after.pid,
              before.bundleID == after.bundleID else {
            return false
        }

        if before.elementFingerprint == after.elementFingerprint {
            return true
        }

        guard let beforeValue = before.valueText,
              let afterValue = after.valueText,
              beforeValue == afterValue else {
            return false
        }

        if before.selectedRangeLocation == after.selectedRangeLocation,
           before.selectedRangeLength == after.selectedRangeLength {
            return true
        }

        return before.selectedRangeLocation == nil
            || after.selectedRangeLocation == nil
    }

    private func verifyTextRewriteInjection(
        _ rewrittenText: String,
        for job: ProcessedJob
    ) async -> DictationVerificationResult {
        guard let before = job.verificationSnapshot,
              let originalValue = before.valueText else {
            return .unverified
        }

        var sawCompatibleObservation = false
        var sawContradictoryChange = false
        let retryDelays: [UInt64] = [
            180_000_000,
            280_000_000,
            420_000_000
        ]

        for delay in retryDelays {
            try? await Task.sleep(nanoseconds: delay)

            guard let after = currentFocusedInputVerificationSnapshot() else { continue }
            guard after.pid == before.pid,
                  after.bundleID == before.bundleID,
                  verificationSnapshotsDescribeSameTarget(before, after),
                  let updatedValue = after.valueText else {
                continue
            }
            sawCompatibleObservation = true

            if updatedValue == rewrittenText {
                return .success
            }

            if updatedValue != originalValue {
                sawContradictoryChange = true
            }
        }

        if sawContradictoryChange {
            return .mismatch
        }
        if sawCompatibleObservation {
            return .unverified
        }
        return .unverified
    }

    private func textRewriteFailureMessage(_ reason: TextRewriteFailureReason) -> String {
        if AppLocalization.isChinese {
            switch reason {
            case .noInputTarget:
                return "没找到可优化的输入框"
            case .unsupportedTarget:
                return "当前输入框暂不支持全文优化"
            case .llmUnavailable:
                return localizedLLMRewriteUnavailableMessage(isChinese: true)
            case .sourceEmpty:
                return "当前文本为空"
            case .sourceTooLong:
                return "文本过长，请分段优化"
            case .timedOut:
                return "优化超时，请重试"
            case .providerFailed:
                return "文本优化失败"
            case .focusChanged:
                return "焦点已变化，未替换原文"
            case .inputInvalid:
                return "输入目标已失效"
            case .commitFailed:
                return "替换失败，请重试"
            }
        }

        switch reason {
        case .noInputTarget:
            return "No editable text field found"
        case .unsupportedTarget:
            return "This field does not support full-text rewrite yet"
        case .llmUnavailable:
            return localizedLLMRewriteUnavailableMessage(isChinese: false)
        case .sourceEmpty:
            return "The current text is empty"
        case .sourceTooLong:
            return "Text is too long. Please rewrite it in chunks"
        case .timedOut:
            return "Rewrite timed out. Please try again"
        case .providerFailed:
            return "Text rewrite failed"
        case .focusChanged:
            return "Focus changed. Original text was not replaced"
        case .inputInvalid:
            return "The input target is no longer valid"
        case .commitFailed:
            return "Replacement failed. Please try again"
        }
    }

    private func localizedLLMRewriteUnavailableMessage(isChinese: Bool) -> String {
        guard isFullTextRewriteEnabled else {
            return isChinese ? "文本优化未开启" : "Text rewrite is turned off"
        }

        switch rewriteLLMServiceSource {
        case .appleOnDevice:
            let availability = AppleOnDeviceLLMProviderFactory.availability(
                localeIdentifier: effectiveLocaleIdentifier
            )
            return availability.detail(
                isChinese: isChinese,
                localeName: localizedSpeechLocaleName
            )
        case .openAICompatible:
            return isChinese ? "文本优化服务未配置" : "Text rewrite service is not configured"
        }
    }

    private var localizedSpeechLocaleName: String {
        Locale.current.localizedString(forIdentifier: effectiveLocaleIdentifier) ?? effectiveLocaleIdentifier
    }

    private func llmProviderDiagnosticsContext(
        for usage: LLMUsage,
        utteranceID: Int? = nil,
        typing: Bool? = nil,
        targetPID: pid_t? = nil,
        bundleID: String? = nil,
        payload: TextRewriteIntentPayload? = nil,
        sourceCount: Int? = nil
    ) -> String {
        let source: LLMServiceSource
        let config: LLMProviderConfiguration?
        let enabled: Bool
        switch usage {
        case .dictationEnhancement:
            source = dictationLLMServiceSource
            config = dictationLLMProviderConfig
            enabled = isAutoDictationEnhancementEnabled
        case .fullTextRewrite:
            source = rewriteLLMServiceSource
            config = rewriteLLMProviderConfig
            enabled = isFullTextRewriteEnabled
        }
        var parts: [String] = [
            "source=\(source.logValue)",
            "locale=\(effectiveLocaleIdentifier)",
            "configured=\(config != nil)",
            "enabled=\(enabled)"
        ]

        if source == .appleOnDevice {
            let availability = AppleOnDeviceLLMProviderFactory.availability(
                localeIdentifier: effectiveLocaleIdentifier
            )
            parts.append("availability=\(availability.logValue)")
        }

        if let utteranceID {
            parts.append("utterance=\(utteranceID)")
        }
        if let typing {
            parts.append("typing=\(typing)")
        }
        if let targetPID {
            parts.append("targetPID=\(targetPID)")
        }
        if let bundleID {
            parts.append("bundle=\(bundleID)")
        }

        if let payload {
            parts.append("scope=\(payload.scope.rawValue)")
            parts.append("mode=\(payload.mode.rawValue)")
        }

        if let sourceCount {
            parts.append("sourceCount=\(sourceCount)")
        }

        return parts.joined(separator: " ")
    }

    private func logTextRewriteFailure(
        _ reason: TextRewriteFailureReason,
        phase: String,
        utteranceID: Int? = nil,
        typing: Bool? = nil,
        targetPID: pid_t? = nil,
        bundleID: String? = nil,
        payload: TextRewriteIntentPayload? = nil,
        sourceCount: Int? = nil,
        error: Error? = nil,
        note: String? = nil
    ) {
        var message = "[TextRewrite] failure phase=\(phase) reason=\(reason.rawValue) \(llmProviderDiagnosticsContext(for: .fullTextRewrite, utteranceID: utteranceID, typing: typing, targetPID: targetPID, bundleID: bundleID, payload: payload, sourceCount: sourceCount))"
        if let note, !note.isEmpty {
            message += " note=\(note)"
        }
        if let error {
            message += " error=\(error.localizedDescription.replacingOccurrences(of: "\n", with: " "))"
        }
        GlobalLogger.speech.error(message)
    }

    private func logDictationEnhancementFailure(
        phase: String,
        job: IntentJob,
        textCount: Int,
        error: Error? = nil,
        note: String? = nil
    ) {
        var message = "[DictationLLM] failure phase=\(phase) \(llmProviderDiagnosticsContext(for: .dictationEnhancement, utteranceID: job.utteranceID, typing: job.typingInteraction, targetPID: job.targetPID, bundleID: job.targetBundleID, sourceCount: textCount))"
        if let note, !note.isEmpty {
            message += " note=\(note)"
        }
        if let error {
            message += " error=\(error.localizedDescription.replacingOccurrences(of: "\n", with: " "))"
        }
        GlobalLogger.speech.error(message)
    }

    private func textRewriteSuccessMessage(changed: Bool) -> String {
        if AppLocalization.isChinese {
            return changed ? "优化完成" : "无需修改"
        }
        return changed ? "Rewrite done" : "No changes"
    }

    private enum TextRewriteCommitMode: String {
        case axDirect
        case pasteFallback
    }

    private func commitTextRewriteResult(
        _ rewrittenText: String,
        for job: ProcessedJob
    ) -> TextRewriteCommitMode {
        if commitTextRewriteViaAX(rewrittenText, for: job) {
            scheduleTextRewriteCaretPlacement(atEndOf: rewrittenText, for: job)
            return .axDirect
        }

        let selectAll = HotkeyBinding(keyCode: kVK_ANSI_A, modifiers: CGEventFlags.maskCommand.rawValue)
        let injectionPID = preferredTypingInjectionTargetPID(job.targetPID, bundleID: job.targetBundleID)
        AutomationOutputs.shared.pressShortcut(selectAll, targetPID: injectionPID)
        injector.paste(rewrittenText)
        scheduleTextRewriteCaretPlacement(atEndOf: rewrittenText, for: job)
        return .pasteFallback
    }

    private func commitTextRewriteViaAX(
        _ rewrittenText: String,
        for job: ProcessedJob
    ) -> Bool {
        guard let before = job.verificationSnapshot,
              let resolved = resolveCurrentFocusedInput(),
              let liveSnapshot = currentFocusedInputVerificationSnapshot(),
              verificationSnapshotsDescribeSameTarget(before, liveSnapshot) else {
            return false
        }

        let candidates = axRewriteCommitCandidates(from: resolved.element)
        for candidate in candidates {
            guard valueAttributeIsSettable(candidate) else { continue }
            let result = AXUIElementSetAttributeValue(
                candidate,
                kAXValueAttribute as CFString,
                rewrittenText as CFTypeRef
            )
            guard result == .success else {
                GlobalLogger.speech.info(
                    "[TextRewrite] ax-set failed error=\(result.rawValue) fingerprint=\(makeElementFingerprint(candidate))"
                )
                continue
            }

            setAXSelectedRangeToEndIfPossible(
                element: candidate,
                text: rewrittenText
            )
            setAXSelectedRangeToEndIfPossible(
                element: resolved.element,
                text: rewrittenText
            )
            return true
        }

        return false
    }

    private func axRewriteCommitCandidates(from element: AXUIElement) -> [AXUIElement] {
        var candidates: [AXUIElement] = [element]
        if let ancestor = editableAncestor(for: element) {
            candidates.append(ancestor)
        }
        return candidates.reduce(into: []) { partial, candidate in
            let fingerprint = makeElementFingerprint(candidate)
            if !partial.contains(where: { makeElementFingerprint($0) == fingerprint }) {
                partial.append(candidate)
            }
        }
    }

    private func setAXSelectedRangeToEndIfPossible(
        element: AXUIElement,
        text: String
    ) {
        var range = CFRange(location: text.utf16.count, length: 0)
        guard let value = AXValueCreate(.cfRange, &range) else { return }
        _ = AXUIElementSetAttributeValue(
            element,
            kAXSelectedTextRangeAttribute as CFString,
            value
        )
    }

    private func scheduleTextRewriteCaretPlacement(
        atEndOf text: String,
        for job: ProcessedJob
    ) {
        let expectedPID = job.targetPID
        let expectedBundleID = job.targetBundleID
        let expectedFingerprint = job.verificationSnapshot?.elementFingerprint ?? job.targetElementFingerprint
        let retryDelays: [UInt64] = [
            0,
            90_000_000,
            240_000_000
        ]

        Task { @MainActor [weak self] in
            guard let self else { return }
            for delay in retryDelays {
                if delay > 0 {
                    try? await Task.sleep(nanoseconds: delay)
                }
                self.moveTextRewriteCaretToEndIfPossible(
                    text,
                    expectedPID: expectedPID,
                    expectedBundleID: expectedBundleID,
                    expectedFingerprint: expectedFingerprint
                )
            }
        }
    }

    private func moveTextRewriteCaretToEndIfPossible(
        _ text: String,
        expectedPID: pid_t?,
        expectedBundleID: String?,
        expectedFingerprint: String?
    ) {
        guard let resolved = resolveCurrentFocusedInput() else { return }
        if let expectedPID, expectedPID > 0, resolved.snapshot.pid != expectedPID {
            return
        }
        if let expectedBundleID, resolved.snapshot.bundleID != expectedBundleID {
            return
        }
        if let expectedFingerprint,
           let liveFingerprint = resolved.snapshot.elementFingerprint,
           liveFingerprint != expectedFingerprint,
           axValueText(resolved.element) != text {
            return
        }

        for candidate in axRewriteCommitCandidates(from: resolved.element) {
            setAXSelectedRangeToEndIfPossible(element: candidate, text: text)
        }
    }

    private func verifyDictationInjection(_ text: String, for job: ProcessedJob) async -> DictationVerificationResult {
        guard let before = job.verificationSnapshot,
              let originalValue = before.valueText,
              let location = before.selectedRangeLocation,
              let length = before.selectedRangeLength else {
            return .unverified
        }

        let selectedRange = NSRange(location: location, length: length)
        guard let swiftRange = Range(selectedRange, in: originalValue) else { return .unverified }
        var expectedValue = originalValue
        expectedValue.replaceSubrange(swiftRange, with: text)

        var sawCompatibleObservation = false
        var sawContradictoryChange = false
        let retryDelays: [UInt64] = [
            180_000_000,
            280_000_000,
            420_000_000
        ]

        for delay in retryDelays {
            try? await Task.sleep(nanoseconds: delay)

            guard let after = currentFocusedInputVerificationSnapshot() else { continue }
            guard after.pid == before.pid,
                  after.bundleID == before.bundleID,
                  after.elementFingerprint == before.elementFingerprint,
                  let updatedValue = after.valueText else {
                continue
            }
            sawCompatibleObservation = true

            if updatedValue == expectedValue {
                return .success
            }

            if likelyObservedCommittedDictation(
                originalValue: originalValue,
                updatedValue: updatedValue,
                expectedValue: expectedValue,
                dictatedText: text,
                beforeSelection: selectedRange,
                afterSelectionLocation: after.selectedRangeLocation
            ) {
                return .success
            }

            if updatedValue != originalValue {
                sawContradictoryChange = true
            }
        }

        if sawContradictoryChange {
            if shouldDowngradeVerificationMismatchForLockedWeirdTypingTarget(job) {
                GlobalLogger.speech.info(
                    "[TextPipeline] verification-mismatch downgraded utterance=\(job.utteranceID) targetPID=\(job.targetPID ?? 0) bundle=\(job.targetBundleID ?? "nil")"
                )
                return .unverified
            }
            return .mismatch
        }

        if sawCompatibleObservation {
            return .unverified
        }

        return .unverified
    }

    private func shouldDowngradeVerificationMismatchForLockedWeirdTypingTarget(_ job: ProcessedJob) -> Bool {
        Self.shouldTrustLockedWeirdTypingTargetWithoutLiveFocus(
            sessionTypingMode: job.typingInteraction,
            targetBundleID: job.targetBundleID,
            targetElementFingerprint: job.targetElementFingerprint,
            verificationSnapshotAvailable: job.verificationSnapshot != nil,
            frontmostMatchesTarget: frontmostApplicationMatches(targetPID: job.targetPID, bundleID: job.targetBundleID)
        )
    }

    private func likelyObservedCommittedDictation(
        originalValue: String,
        updatedValue: String,
        expectedValue: String,
        dictatedText: String,
        beforeSelection: NSRange,
        afterSelectionLocation: Int?
    ) -> Bool {
        if updatedValue == expectedValue {
            return true
        }

        guard updatedValue != originalValue else { return false }

        let normalizedUpdated = verificationNormalizedText(updatedValue)
        let normalizedExpected = verificationNormalizedText(expectedValue)
        let normalizedDictated = verificationNormalizedText(dictatedText)

        if !normalizedDictated.isEmpty && normalizedUpdated.contains(normalizedDictated) {
            return true
        }

        if !normalizedExpected.isEmpty && normalizedUpdated == normalizedExpected {
            return true
        }

        if let afterSelectionLocation,
           afterSelectionLocation >= beforeSelection.location,
           updatedValue.count >= originalValue.count {
            return true
        }

        return false
    }

    private func verificationNormalizedText(_ text: String) -> String {
        text
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)
    }
    private func lockSessionInputTarget() {
        let snap = currentFocusedInputSnapshot()
        sessionTargetPID = snap?.pid; sessionTargetBundleID = snap?.bundleID
        sessionTargetElementFingerprint = snap?.elementFingerprint
        sessionTargetSource = snap?.source
        didLogSessionTargetMismatch = false
    }
    private func syncSessionInputTargetFromCurrentFocus(resetDictationStream: Bool) {
        guard let snap = currentFocusedInputSnapshot() else { return }
        let changed = sessionTargetPID != snap.pid ||
            sessionTargetBundleID != snap.bundleID ||
            sessionTargetElementFingerprint != snap.elementFingerprint
        guard changed else { return }
        if isTypingRecoveryHoldActive {
            endTypingRecoveryHold(reason: "focus-changed")
        }
        sessionTargetPID = snap.pid
        sessionTargetBundleID = snap.bundleID
        sessionTargetElementFingerprint = snap.elementFingerprint
        sessionTargetSource = snap.source
        didLogSessionTargetMismatch = false
        if resetDictationStream {
            dictationHandler.reset(targetPID: preferredTypingInjectionTargetPID(sessionTargetPID, bundleID: sessionTargetBundleID))
        }
    }
    private func rearmInputTarget(reason: String) {
        lockSessionInputTarget(); micProgressLockedPID = sessionTargetPID; isMicProgressPausedForTarget = false
        segmentStartedAt = .distantPast
        micProgressSilentTicks = 0
        micProgressActiveTicks = 0
        latestVoiceActivity = false
        latestVoiceRMS = 0
        HUDManager.shared.updateMicProgress(progress: 0.0, visible: false)
        dictationHandler.reset(targetPID: preferredTypingInjectionTargetPID(sessionTargetPID, bundleID: sessionTargetBundleID))
    }

    // MARK: - Injection Target Validation
    private func isJobInputTargetValidForInjection(_ job: ProcessedJob) -> Bool {
        let trusted = accessibilityTrustedSnapshot || AXIsProcessTrusted()
        if accessibilityTrustedSnapshot != trusted { accessibilityTrustedSnapshot = trusted }
        if !trusted { return false }
        if bundleIsSystemSearchLike(job.targetBundleID)
            || bundleIsSystemSearchLike(NSWorkspace.shared.frontmostApplication?.bundleIdentifier) {
            return currentFocusedInputSnapshot() != nil
        }
        let frontmostMatchesTarget: Bool = {
            guard let front = NSWorkspace.shared.frontmostApplication else { return false }
            if let targetPID = job.targetPID, targetPID > 0, front.processIdentifier == targetPID {
                return true
            }
            if let targetBundleID = job.targetBundleID, !targetBundleID.isEmpty,
               front.bundleIdentifier == targetBundleID {
                return true
            }
            return false
        }()
        if Self.shouldTrustLockedWeirdTypingTargetWithoutLiveFocus(
            sessionTypingMode: job.typingInteraction,
            targetBundleID: job.targetBundleID,
            targetElementFingerprint: job.targetElementFingerprint,
            verificationSnapshotAvailable: job.verificationSnapshot != nil,
            frontmostMatchesTarget: frontmostMatchesTarget
        ) {
            return true
        }
        if Self.shouldAcceptStreamedDictationTargetWithoutLiveFocus(
            sessionTypingMode: job.typingInteraction,
            screenTypedCount: job.screenTypedCount,
            streamedTextSnapshot: job.streamedTextSnapshot,
            frontmostMatchesTarget: frontmostMatchesTarget
        ) {
            return true
        }
        if job.typingInteraction && (job.targetPID == nil || job.targetPID == 0) {
            if job.targetSource == .recentClickFallback,
               let front = NSWorkspace.shared.frontmostApplication {
                if let bundleID = job.targetBundleID, !bundleID.isEmpty {
                    return front.bundleIdentifier == bundleID
                }
                return true
            }
            return currentFocusedInputSnapshot() != nil
        }
        guard let tp = job.targetPID, tp > 0 else { return true }
        guard let front = NSWorkspace.shared.frontmostApplication else { return false }
        let matches = front.processIdentifier == tp || (job.targetBundleID.map { front.bundleIdentifier == $0 } ?? false)
        guard matches else { return false }
        return true
    }

    private func frontmostApplicationMatches(targetPID: pid_t?, bundleID: String?) -> Bool {
        guard let front = NSWorkspace.shared.frontmostApplication else { return false }
        if let targetPID, targetPID > 0, front.processIdentifier == targetPID {
            return true
        }
        if let bundleID, !bundleID.isEmpty, front.bundleIdentifier == bundleID {
            return true
        }
        return false
    }

    private func resolvedUsageAppContext(for job: ProcessedJob) -> (appName: String?, bundleIdentifier: String?) {
        if let bundleID = job.targetBundleID, !bundleID.isEmpty {
            if let pid = job.targetPID, pid > 0,
               let app = NSRunningApplication(processIdentifier: pid) {
                return (app.localizedName, bundleID)
            }
            if let app = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == bundleID }) {
                return (app.localizedName, bundleID)
            }
            return (nil, bundleID)
        }

        if let pid = job.targetPID, pid > 0,
           let app = NSRunningApplication(processIdentifier: pid),
           let bundleID = app.bundleIdentifier {
            return (app.localizedName, bundleID)
        }

        if let front = NSWorkspace.shared.frontmostApplication,
           let bundleID = front.bundleIdentifier,
           !bundleID.isEmpty {
            return (front.localizedName, bundleID)
        }
        return (nil, nil)
    }

    private func shouldSuppressFocusedTypingForExplicitNonInputClick() -> Bool {
        guard !isWeChatSpecialModeActive() else { return false }
        guard isWeirdTypingAppBundle(NSWorkspace.shared.frontmostApplication?.bundleIdentifier) else {
            return false
        }
        return HUDManager.shared.isTypingExplicitlySuppressedForCurrentApp()
    }

    private func isFocusedElementUsableForDictation(_ element: AXUIElement, bundleID: String? = nil) -> Bool {
        var roleRef: CFTypeRef?
        let role = (AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleRef) == .success)
            ? (roleRef as? String ?? "")
            : ""

        let editable = axBoolAttribute(element, "AXEditable" as CFString) == true
        let insertionContext = hasInsertionContext(element)
        let hasEditableAncestor = editableAncestor(for: element) != nil
        let hasSettableValue = valueAttributeIsSettable(element)
        let allowsLooseContainerDictation = allowsLooseContainerDictationHeuristics(bundleID)
        let directRoles: Set<String> = [kAXTextFieldRole as String, "AXSearchField", "AXComboBox", "AXHTMLTextInput"]

        if directRoles.contains(role) { return true }
        if role == kAXTextAreaRole as String {
            return insertionContext || hasEditableAncestor || hasSettableValue
        }
        if role == "AXWebArea" || role == "AXGroup" || role == "AXScrollArea" || role == "AXSplitGroup" || role == "AXStaticText" {
            if allowsLooseContainerDictation && insertionContext && (editable || hasEditableAncestor || hasSettableValue) {
                return true
            }
            return insertionContext && (editable || hasSettableValue)
        }
        if insertionContext && (editable || hasSettableValue) {
            return true
        }
        return editable && insertionContext
    }

    // MARK: - Speech Term Corrections (preserved)
    private struct SpeechTermGroup: Codable { var id: String; var name: String; var isEnabled: Bool; var applyToAllApps: Bool; var appList: String; var rulesText: String }
    private typealias SpeechCorrectionScope = RecognizedTextCorrectionScope
    private typealias SpeechReplacementRule = RecognizedTextReplacementRule
    private func shouldEnableSpeechTermCorrection() -> Bool {
        UserDefaults.standard.object(forKey: "speechTermCorrectionEnabled") as? Bool ?? false
    }
    private func groupAppWhitelist(_ raw: String) -> [String] { raw.components(separatedBy: CharacterSet(charactersIn: ",\n")).map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }.filter { !$0.isEmpty } }
    private func loadSpeechTermGroups() -> [SpeechTermGroup] {
        if let data = UserDefaults.standard.data(forKey: "speechTermGroupsV2"), let g = try? JSONDecoder().decode([SpeechTermGroup].self, from: data) { return g }; return []
    }
    private func currentContextBundleIDs() -> [String] {
        [(sessionTargetBundleID ?? "").lowercased(), (NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "").lowercased()].filter { !$0.isEmpty }
    }
    private func activeGroups(for bundleIDs: [String]) -> [SpeechTermGroup] {
        let groups = loadSpeechTermGroups()
        guard !groups.isEmpty else { return [] }

        return groups.filter { group in
            guard group.isEnabled else { return false }
            if group.applyToAllApps { return true }
            guard !bundleIDs.isEmpty else { return false }
            let whitelist = groupAppWhitelist(group.appList)
            guard !whitelist.isEmpty else { return false }
            return bundleIDs.contains { bundleID in
                whitelist.contains(where: { bundleID.contains($0) })
            }
        }
    }
    private func activeGroupsForCurrentContext() -> [SpeechTermGroup] {
        activeGroups(for: currentContextBundleIDs())
    }
    private func shouldEnableDeveloperSpeechProfile(bundleIDs: [String]? = nil) -> Bool {
        guard isDeveloperSpeechProfileEnabled else { return false }
        let ids = bundleIDs ?? currentContextBundleIDs()
        return ids.contains(where: { DeveloperSpeechProfile.matches(bundleIdentifier: $0) })
    }
    private func isGitHubCommandLikePhrase(_ text: String) -> Bool {
        let s = text.lowercased()
        let zh = ["提交","分支","仓库","代码","拉取","推送","合并","变基","开pr","issue","代码库"]
        let en = ["git","repo","repository","branch","commit","push","pull","merge","rebase","pr","issue","github"]
        if zh.contains(where: { s.contains($0) }) { return true }; if en.contains(where: { s.contains($0) }) { return true }
        return ["打开","去","到","看","搜","查","open","go to","search","check"].contains(where: { s.contains($0) })
    }
    private func replacementRules(from raw: String) -> [SpeechReplacementRule] {
        raw.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty && !$0.hasPrefix("#") }
            .compactMap { line in let p = line.components(separatedBy: "=>").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                guard p.count >= 2, !p[0].isEmpty, !p[1].isEmpty else { return nil }
                let scope: SpeechCorrectionScope? = {
                    guard p.count >= 3 else { return nil }
                    let marker = p[2].lowercased()
                    if marker.contains("cmd") || marker.contains("command") || marker.contains("control") { return .command }
                    if marker.contains("dict") || marker.contains("input") { return .dictation }
                    return nil
                }()
                return SpeechReplacementRule(from: p[0], to: p[1], scope: scope) }
    }
    private func replacementRules(for g: SpeechTermGroup) -> [SpeechReplacementRule] { replacementRules(from: g.rulesText) }
    private func contextualSpeechGlossaryText(bundleIDs: [String]? = nil) -> String? {
        guard shouldEnableSpeechTermCorrection() else { return nil }

        let activeBundleIDs = VoiceLexiconSupport.uniqueTerms(
            (bundleIDs ?? currentContextBundleIDs()).map { $0.lowercased() }
        )
        let mappings = activeGroups(for: activeBundleIDs)
            .flatMap(replacementRules(for:))
            .filter { $0.scope != .command }
            .map { "\($0.from) => \($0.to)" }
        let uniqueMappings = VoiceLexiconSupport.uniqueTerms(mappings)
        guard !uniqueMappings.isEmpty else { return nil }
        return uniqueMappings.joined(separator: "\n")
    }
    private func contextualLLMProvider(
        for usage: LLMUsage,
        bundleIDs: [String]? = nil
    ) -> LLMProvider? {
        let config: LLMProviderConfiguration?
        switch usage {
        case .dictationEnhancement:
            config = dictationLLMProviderConfig
        case .fullTextRewrite:
            config = rewriteLLMProviderConfig
        }

        guard let config else { return nil }
        switch config {
        case .openAICompatible(var effectiveConfig):
            effectiveConfig.contextualGlossaryText = contextualSpeechGlossaryText(bundleIDs: bundleIDs)
            return OpenAICompatibleProvider(config: effectiveConfig)
        case .appleOnDevice(var effectiveConfig):
            effectiveConfig.contextualGlossaryText = contextualSpeechGlossaryText(bundleIDs: bundleIDs)
            return AppleOnDeviceLLMProviderFactory.makeProvider(config: effectiveConfig)
        }
    }
    private func normalizeRecognizedText(_ raw: String, scope: SpeechCorrectionScope = .dictation) -> String {
        let corrected = applyContextualSpeechCorrections(raw, scope: scope)
        return deduplicateRepeatedTailPhrase(corrected)
    }
    private func chineseDictationEOSDeferralMs() -> Double? {
        let availability = currentVoiceFeatureAvailability()
        guard currentSessionSpeechStyle(
            for: availability,
            sessionTypingModeOverride: sessionTypingMode
        ) == .dictation else {
            return nil
        }
        if isWakeFollowUpDictationContext(sessionTypingModeOverride: sessionTypingMode) {
            return nil
        }

        let transcript = normalizeRecognizedText(lastTranscript, scope: .dictation)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !transcript.isEmpty else { return nil }

        let delay = chineseContinuationDeferralMs(
            for: transcript,
            localeIdentifier: activeLocale.identifier
        )
        if let delay {
            GlobalLogger.speech.info(
                "[EOSGuard] deferred chinese dictation EOS delayMs=\(String(format: "%.0f", delay)) transcript='\(transcript)'"
            )
        }
        return delay
    }
    private func applyChineseFinalPunctuationFallback(
        _ text: String,
        localeIdentifier: String
    ) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return trimmed }
        guard shouldApplyChinesePunctuationFallback(to: trimmed, localeIdentifier: localeIdentifier) else {
            return trimmed
        }

        let punctuated: String
        if isLikelyChineseQuestion(trimmed) {
            punctuated = trimmed + "？"
        } else if isLikelyChineseExclamation(trimmed) {
            punctuated = trimmed + "！"
        } else {
            punctuated = trimmed + "。"
        }

        GlobalLogger.speech.info(
            "[TextPipeline] final-punctuation-fallback before='\(trimmed)' after='\(punctuated)' locale=\(localeIdentifier)"
        )
        return punctuated
    }
    private func shouldApplyChinesePunctuationFallback(
        to text: String,
        localeIdentifier: String
    ) -> Bool {
        guard isChineseTextContext(text, localeIdentifier: localeIdentifier) else { return false }
        guard !hasSentenceTerminalPunctuation(text) else { return false }
        guard chineseScalarCount(in: text) >= 3 else { return false }
        guard !isLikelyIncompleteChineseSentence(text, localeIdentifier: localeIdentifier) else { return false }
        guard !isLikelyListOrPrefixEnding(text) else { return false }
        guard !endsWithAny(text, suffixes: ["，", "、", "；", "：", ",", ";", ":", "（", "(", "“", "\"", "「", "『"]) else {
            return false
        }
        guard !isLikelyCodeLikeText(text) else { return false }
        return true
    }
    private func chineseContinuationDeferralMs(
        for text: String,
        localeIdentifier: String
    ) -> Double? {
        guard isChineseTextContext(text, localeIdentifier: localeIdentifier) else { return nil }
        guard !hasSentenceTerminalPunctuation(text) else { return nil }

        if endsWithAny(text, suffixes: ["怎么", "为什么", "是否", "要不要", "能不能", "会不会", "有没有", "是不是"]) {
            return 700
        }
        if endsWithAny(text, suffixes: ["然后", "如果", "因为", "所以", "就是", "那个"]) {
            return 600
        }
        if endsWithAny(text, suffixes: ["的", "得", "地", "是", "把", "会", "还"]) {
            return 600
        }
        return nil
    }
    private func isLikelyIncompleteChineseSentence(
        _ text: String,
        localeIdentifier: String
    ) -> Bool {
        guard isChineseTextContext(text, localeIdentifier: localeIdentifier) else { return false }
        if endsWithAny(text, suffixes: [
            "的", "得", "地", "是", "把", "会", "还",
            "然后", "如果", "因为", "所以", "就是", "那个",
            "和", "跟", "与", "并且", "或者", "但是"
        ]) {
            return true
        }
        return false
    }
    private func isLikelyChineseQuestion(_ text: String) -> Bool {
        endsWithAny(text, suffixes: [
            "吗", "么", "嘛", "呢",
            "是不是", "能不能", "可不可以", "对不对",
            "好不好", "行不行", "要不要"
        ])
    }
    private func isLikelyChineseExclamation(_ text: String) -> Bool {
        endsWithAny(text, suffixes: ["啊", "呀", "啦", "哇"]) && chineseScalarCount(in: text) >= 4
    }
    private func isLikelyListOrPrefixEnding(_ text: String) -> Bool {
        endsWithAny(text, suffixes: ["第一", "第二", "比如", "例如", "包括"])
    }
    private func isChineseTextContext(_ text: String, localeIdentifier: String) -> Bool {
        if localeIdentifier.lowercased().hasPrefix("zh") { return true }
        let chineseCount = chineseScalarCount(in: text)
        let asciiCount = asciiAlphaNumericScalarCount(in: text)
        return chineseCount >= 3 && chineseCount >= asciiCount
    }
    private func hasSentenceTerminalPunctuation(_ text: String) -> Bool {
        guard let last = text.trimmingCharacters(in: .whitespacesAndNewlines).last else { return false }
        return "。！？.!?…".contains(last)
    }
    private func endsWithAny(_ text: String, suffixes: [String]) -> Bool {
        suffixes.contains { text.hasSuffix($0) }
    }
    private func chineseScalarCount(in text: String) -> Int {
        text.unicodeScalars.reduce(into: 0) { partialResult, scalar in
            let value = Int(scalar.value)
            if (0x3400...0x4DBF).contains(value) || (0x4E00...0x9FFF).contains(value) || (0xF900...0xFAFF).contains(value) {
                partialResult += 1
            }
        }
    }
    private func asciiAlphaNumericScalarCount(in text: String) -> Int {
        text.unicodeScalars.reduce(into: 0) { partialResult, scalar in
            if scalar.isASCII && CharacterSet.alphanumerics.contains(scalar) {
                partialResult += 1
            }
        }
    }
    private func isLikelyCodeLikeText(_ text: String) -> Bool {
        let markers = ["://", "/", "\\", "com.", ".swift", ".js", ".ts", "--", "⌘"]
        if markers.contains(where: { text.contains($0) }) {
            return true
        }
        let chineseCount = chineseScalarCount(in: text)
        let asciiCount = asciiAlphaNumericScalarCount(in: text)
        return asciiCount > max(chineseCount * 2, 8)
    }
    static func isWeirdTypingAppBundleIdentifier(_ bundleID: String?) -> Bool {
        let bundle = (bundleID ?? "").lowercased()
        return bundle.contains("xinwechat")
            || bundle.contains("wechat")
            || bundle.contains("codex")
            || bundle.contains("antigravity")
            || bundle.contains("telegram")
    }
    static func allowsLooseContainerDictationHeuristicsIdentifier(_ bundleID: String?) -> Bool {
        let bundle = (bundleID ?? "").lowercased()
        return bundle.contains("xinwechat") || bundle.contains("wechat")
    }
    private func isWeirdTypingAppBundle(_ bundleID: String?) -> Bool {
        Self.isWeirdTypingAppBundleIdentifier(bundleID)
    }
    private func allowsLooseContainerDictationHeuristics(_ bundleID: String?) -> Bool {
        Self.allowsLooseContainerDictationHeuristicsIdentifier(bundleID)
    }
    private func isRecentClickFallbackTypingAppBundle(_ bundleID: String?) -> Bool {
        let bundle = (bundleID ?? "").lowercased()
        return bundle.contains("xinwechat") || bundle.contains("wechat")
    }
    private func valueAttributeIsSettable(_ element: AXUIElement) -> Bool {
        var settable = DarwinBoolean(false)
        let result = AXUIElementIsAttributeSettable(element, kAXValueAttribute as CFString, &settable)
        return result == .success && settable.boolValue
    }
    private func axBoolAttribute(_ element: AXUIElement, _ attr: CFString) -> Bool? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attr, &value) == .success else { return nil }
        if let b = value as? Bool { return b }
        if let n = value as? NSNumber { return n.boolValue }
        return nil
    }
    private func hasInsertionContext(_ element: AXUIElement) -> Bool {
        var value: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &value) == .success,
           let raw = value,
           CFGetTypeID(raw) == AXValueGetTypeID() {
            let ax = raw as! AXValue
            if AXValueGetType(ax) == .cfRange {
                var range = CFRange()
                if AXValueGetValue(ax, .cfRange, &range) {
                    if range.length == 0 { return true }
                } else {
                    return true
                }
            } else {
                return true
            }
        }
        var markerRange: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, "AXSelectedTextMarkerRange" as CFString, &markerRange) == .success
    }
    private func editableAncestor(for element: AXUIElement, depth: Int = 6) -> AXUIElement? {
        for attr in ["AXEditableAncestor", "AXHighestEditableAncestor"] {
            var value: CFTypeRef?
            if AXUIElementCopyAttributeValue(element, attr as CFString, &value) == .success,
               let candidate = value,
               CFGetTypeID(candidate) == AXUIElementGetTypeID() {
                return candidate as! AXUIElement
            }
        }

        var current = element
        for _ in 0..<depth {
            var parentRef: CFTypeRef?
            guard AXUIElementCopyAttributeValue(current, kAXParentAttribute as CFString, &parentRef) == .success,
                  let parentValue = parentRef,
                  CFGetTypeID(parentValue) == AXUIElementGetTypeID() else {
                break
            }
            let parent = parentValue as! AXUIElement
            let parentRole = axStringAttribute(parent, kAXRoleAttribute as CFString) ?? ""
            let isEditableParent = (axBoolAttribute(parent, "AXEditable" as CFString) == true)
                || valueAttributeIsSettable(parent)
                || hasInsertionContext(parent)
            if isEditableParent
                || parentRole == kAXTextFieldRole as String
                || parentRole == "AXSearchField"
                || parentRole == "AXComboBox"
                || parentRole == "AXHTMLTextInput"
                || parentRole == kAXTextAreaRole as String {
                return parent
            }
            current = parent
        }
        return nil
    }
    private func trimRepeatedDictationOverlap(_ text: String, for job: ProcessedJob) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        guard Date().timeIntervalSince(lastCommittedDictationAt) <= 2.0 else { return trimmed }

        let sameFingerprint = job.targetElementFingerprint != nil
            && job.targetElementFingerprint == lastCommittedDictationElementFingerprint
        let sameBundle = job.targetBundleID != nil
            && job.targetBundleID == lastCommittedDictationBundleID
        let samePID = job.targetPID != nil
            && job.targetPID == lastCommittedDictationPID
        guard sameFingerprint || (sameBundle && samePID) else { return trimmed }

        let previous = lastCommittedDictationText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !previous.isEmpty else { return trimmed }

        let overlap = Self.repeatedTailPrefixOverlap(previous: previous, current: trimmed)
        guard overlap > 0 else { return trimmed }

        let start = trimmed.index(trimmed.startIndex, offsetBy: overlap)
        let deduped = String(trimmed[start...]).trimmingCharacters(in: .whitespacesAndNewlines)
        GlobalLogger.speech.info(
            "[TextPipeline] trimmed-cross-utterance-overlap overlap=\(overlap) previousCount=\(previous.count) currentCount=\(trimmed.count) dedupedCount=\(deduped.count)"
        )
        return deduped
    }
    private static func repeatedTailPrefixOverlap(previous: String, current: String) -> Int {
        let maxLen = min(previous.count, current.count)
        guard maxLen > 0 else { return 0 }

        for len in stride(from: maxLen, through: 2, by: -1) {
            let prevStart = previous.index(previous.endIndex, offsetBy: -len)
            let prevSuffix = String(previous[prevStart...])
            let currEnd = current.index(current.startIndex, offsetBy: len)
            let currPrefix = String(current[..<currEnd])
            guard prevSuffix == currPrefix else { continue }

            if len >= Self.minimumCrossUtteranceOverlapLength(for: currPrefix) {
                return len
            }
        }
        return 0
    }
    static func minimumCrossUtteranceOverlapLength(for text: String) -> Int {
        let scalars = text.unicodeScalars
        let containsWhitespace = scalars.contains { CharacterSet.whitespacesAndNewlines.contains($0) }
        let containsASCIIAlnum = scalars.contains { CharacterSet.alphanumerics.contains($0) && $0.isASCII }
        let containsCJK = scalars.contains {
            let value = Int($0.value)
            return (0x3400...0x4DBF).contains(value)
                || (0x4E00...0x9FFF).contains(value)
                || (0xF900...0xFAFF).contains(value)
        }

        if containsWhitespace || containsASCIIAlnum {
            return 4
        }

        // Two-character Chinese words are common enough that a 2-char overlap floor
        // causes false cross-utterance trimming, especially around wake-word splits.
        if containsCJK {
            return 4
        }

        return 3
    }
    static func fallbackTranscriptForUnexpectedEmptyFinal(
        finalTranscript: String,
        lastPartialTranscript: String
    ) -> String? {
        let finalTrimmed = finalTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard finalTrimmed.isEmpty else { return nil }

        let candidate = lastPartialTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !candidate.isEmpty else { return nil }
        guard candidate.count >= minimumCrossUtteranceOverlapLength(for: candidate) else {
            return nil
        }
        return candidate
    }

    static func fallbackTranscriptForRecoverableNoSpeechError(
        isAlwaysListeningEnabled: Bool,
        isRecoverable: Bool,
        failureReason: String,
        lastPartialTranscript: String,
        isUtteranceActive: Bool
    ) -> String? {
        guard isAlwaysListeningEnabled else { return nil }
        guard isRecoverable, failureReason == "no-speech-detected" else { return nil }
        guard isUtteranceActive else { return nil }
        return fallbackTranscriptForUnexpectedEmptyFinal(
            finalTranscript: "",
            lastPartialTranscript: lastPartialTranscript
        )
    }

    static func resolvedNoSpeechRecoveryBackoffDelay(
        reason: String,
        standbyWakeMissRecoveryActive: Bool,
        wakeActivationRecoveryActive: Bool,
        consecutiveRecoveries: Int
    ) -> (delay: TimeInterval, nextConsecutiveRecoveries: Int) {
        guard reason == "no-speech-detected" else {
            return (0.12, 0)
        }

        if standbyWakeMissRecoveryActive || wakeActivationRecoveryActive {
            return (0.05, 0)
        }

        let nextConsecutiveRecoveries = min(consecutiveRecoveries + 1, 6)
        let delay = min(0.35 * pow(1.7, Double(nextConsecutiveRecoveries - 1)), 1.5)
        return (delay, nextConsecutiveRecoveries)
    }

    static func shouldCommitCompletedOneShotFinalResult(
        isStopping: Bool,
        isAlwaysListeningEnabled: Bool,
        finalTranscript: String
    ) -> Bool {
        guard !isStopping, !isAlwaysListeningEnabled else { return false }
        return !finalTranscript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func rememberCommittedDictation(_ text: String, for job: ProcessedJob) {
        clearPostSubmitDictationSuppression()
        lastCommittedDictationText = text
        lastCommittedDictationAt = Date()
        lastCommittedDictationPID = job.targetPID
        lastCommittedDictationBundleID = job.targetBundleID
        lastCommittedDictationElementFingerprint = job.targetElementFingerprint
    }
    private func deduplicateRepeatedTailPhrase(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else { return trimmed }

        var chars = Array(trimmed)
        var changed = false

        repeat {
            changed = false
            let minUnitLen = 2
            let maxUnitLen = min(16, chars.count / 2)
            
            if maxUnitLen >= minUnitLen {
                outerBlock: for unitLen in stride(from: maxUnitLen, through: minUnitLen, by: -1) {
                    for i in 0...(chars.count - unitLen * 2) {
                        let seq1 = chars[i..<i+unitLen]
                        let seq2 = chars[i+unitLen..<i+unitLen*2]
                        
                        if seq1.elementsEqual(seq2) {
                            let segment = String(seq1)
                            let hasWhitespace = segment.unicodeScalars.contains { CharacterSet.whitespacesAndNewlines.contains($0) }
                            let hasLetterOrDigit = segment.unicodeScalars.contains { CharacterSet.alphanumerics.contains($0) }
                            let hasCJK = segment.unicodeScalars.contains { (0x4E00...0x9FFF).contains(Int($0.value)) }
                            
                            if !hasWhitespace && (hasLetterOrDigit || hasCJK) {
                                chars.removeSubrange(i+unitLen..<i+unitLen*2)
                                changed = true
                                break outerBlock
                            }
                        }
                    }
                }
            }
        } while changed

        return String(chars)
    }
    private func applyContextualSpeechCorrections(_ raw: String, scope: SpeechCorrectionScope) -> String {
        guard raw.count <= 120 else { return raw }

        let bundleIDs = currentContextBundleIDs()
        let developerProfileEnabled = shouldEnableDeveloperSpeechProfile(bundleIDs: bundleIDs)
        let groups = shouldEnableSpeechTermCorrection() ? activeGroupsForCurrentContext() : []
        guard developerProfileEnabled || !groups.isEmpty else { return raw }

        var c = raw
        if scope == .command {
            let trimmed = c.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed == "邮件" {
                c = "右键"
            }
        }

        for g in groups {
            for r in replacementRules(for: g) {
                guard c.contains(r.from) else { continue }
                if let ruleScope = r.scope, ruleScope != scope { continue }
                c = c.replacingOccurrences(of: r.from, with: r.to)
            }
        }

        if developerProfileEnabled {
            c = DeveloperSpeechProfile.correctedText(c, scope: scope, bundleIdentifiers: bundleIDs)
        }

        return c
    }
}

@MainActor
private final class HeadsetInputMuteRouter {
    private let log = GlobalLogger.speech
    private var isActive = false
    private var observer: NSObjectProtocol?
    private var activatedAt: Date = .distantPast
    private var lastDeliveredAt: Date = .distantPast
    private var lastDeliveredState: Bool?

    func activate(onSinglePress: @escaping (Bool) -> Void) {
        guard #available(macOS 14.0, *) else { return }
        guard !isActive else { return }

        observer = NotificationCenter.default.addObserver(
            forName: AVAudioApplication.inputMuteStateChangeNotification,
            object: AVAudioApplication.shared,
            queue: .main
        ) { [weak self] note in
            Task { @MainActor [weak self] in
                self?.logMuteNotification(note)
            }
        }

        do {
            try AVAudioApplication.shared.setInputMuteStateChangeHandler { inputShouldBeMuted in
                let now = Date()
                if now.timeIntervalSince(self.activatedAt) < 0.35 {
                    os_log("Input mute gesture ignored during activation warmup", log: self.log, type: .info)
                    return true
                }
                if !inputShouldBeMuted {
                    os_log("Input mute gesture ignored for unmute edge", log: self.log, type: .info)
                    return true
                }
                if let lastState = self.lastDeliveredState,
                   lastState == inputShouldBeMuted,
                   now.timeIntervalSince(self.lastDeliveredAt) < 0.9 {
                    os_log("Input mute gesture ignored as duplicate", log: self.log, type: .info)
                    return true
                }
                if now.timeIntervalSince(self.lastDeliveredAt) < 0.45 {
                    os_log("Input mute gesture ignored as rapid repeat", log: self.log, type: .info)
                    return true
                }
                self.lastDeliveredAt = now
                self.lastDeliveredState = inputShouldBeMuted
                Task { @MainActor in
                    onSinglePress(inputShouldBeMuted)
                }
                return true
            }
        } catch {
            os_log("Input mute handler registration failed: %{public}@", log: log, type: .error, error.localizedDescription)
            removeObserver()
            return
        }

        isActive = true
        activatedAt = Date()
        lastDeliveredAt = .distantPast
        lastDeliveredState = nil
        os_log("Input mute handler registered", log: log, type: .info)
    }

    func deactivate() {
        guard #available(macOS 14.0, *) else { return }

        if isActive {
            do {
                try AVAudioApplication.shared.setInputMuteStateChangeHandler(nil)
            } catch {
                os_log("Input mute handler clear failed: %{public}@", log: log, type: .error, error.localizedDescription)
            }
        }

        isActive = false
        activatedAt = .distantPast
        lastDeliveredAt = .distantPast
        lastDeliveredState = nil
        removeObserver()
    }

    @available(macOS 14.0, *)
    private func logMuteNotification(_ note: Notification) {
        let muted = (note.userInfo?[AVAudioApplication.muteStateKey] as? NSNumber)?.boolValue
        os_log("Input mute state notification: %{public}@", log: log, type: .info, muted == true ? "muted" : "unmuted")
    }

    private func removeObserver() {
        if let observer {
            NotificationCenter.default.removeObserver(observer)
            self.observer = nil
        }
    }
}

// MARK: - Global Logger (Merged)

enum GlobalLogger {
    private static let subsystem = "com.7fei.Aether"
    private static let fileQueue = DispatchQueue(label: "com.7fei.Aether.logfile", qos: .utility)
    private static let duplicateFilterQueue = DispatchQueue(label: "com.7fei.Aether.logdedupe")
    private static let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
    private static var lastNoisyLogAtByKey: [String: Date] = [:]
    private static var diagnosticsHandle: FileHandle?
    private static var diagnosticsFileSize: Int64 = 0

    static let speech = OSLog(subsystem: subsystem, category: "Speech")
    static let lifecycle = OSLog(subsystem: subsystem, category: "Lifecycle")
    static let input = OSLog(subsystem: subsystem, category: "Input")
    static let motion = OSLog(subsystem: subsystem, category: "Motion")
    static let router = OSLog(subsystem: subsystem, category: "Router")

    static func log(_ message: String, log: OSLog, type: OSLogType = .default) {
        let category: String
        if log === speech { category = "Speech" }
        else if log === lifecycle { category = "Lifecycle" }
        else if log === input { category = "Input" }
        else if log === motion { category = "Motion" }
        else if log === router { category = "Router" }
        else { category = "Aether" }

        let now = Date()
        if shouldSuppressRepeatedLog(category: category, message: message, at: now) {
            return
        }

        let formatted = "\(now) [\(category)] \(message)\n"
        fputs(formatted, stderr)
        os_log("%{public}@", log: log, type: type, message)
        appendToLogFile(timestampedMessage: formatted)
    }

    private static func appendToLogFile(timestampedMessage: String) {
        fileQueue.async {
            let url = diagnosticsLogURL()
            do {
                guard let data = timestampedMessage.data(using: .utf8) else { return }
                _ = try diagnosticsLogHandle(for: url)
                try trimLogFileIfNeeded(url: url)
                let handle = try diagnosticsLogHandle(for: url)
                try handle.seekToEnd()
                try handle.write(contentsOf: data)
                diagnosticsFileSize += Int64(data.count)
            } catch {
                closeDiagnosticsHandle()
                fputs("\(isoFormatter.string(from: Date())) [Logger] failed to append diagnostics log: \(error)\n", stderr)
            }
        }
    }

    private static func diagnosticsLogURL() -> URL {
        let base = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library", isDirectory: true)
        return base
            .appendingPathComponent("Logs", isDirectory: true)
            .appendingPathComponent("Aether", isDirectory: true)
            .appendingPathComponent("diagnostics.log", isDirectory: false)
    }

    private static func diagnosticsLogHandle(for url: URL) throws -> FileHandle {
        if let diagnosticsHandle {
            return diagnosticsHandle
        }

        let dir = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: url.path) {
            FileManager.default.createFile(atPath: url.path, contents: nil)
            diagnosticsFileSize = 0
        } else {
            let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
            diagnosticsFileSize = (attrs[.size] as? NSNumber)?.int64Value ?? 0
        }

        let handle = try FileHandle(forWritingTo: url)
        diagnosticsHandle = handle
        return handle
    }

    private static func closeDiagnosticsHandle() {
        try? diagnosticsHandle?.close()
        diagnosticsHandle = nil
    }

    private static func trimLogFileIfNeeded(url: URL) throws {
        let maxBytes: Int64 = 1_500_000
        let keepBytes: Int64 = 1_000_000
        guard diagnosticsFileSize > maxBytes else { return }
        closeDiagnosticsHandle()
        let data = try Data(contentsOf: url, options: [.mappedIfSafe])
        let sliceStart = max(0, data.count - Int(keepBytes))
        let suffix = data.subdata(in: sliceStart..<data.count)
        try suffix.write(to: url, options: .atomic)
        diagnosticsFileSize = Int64(suffix.count)
    }

    private static func shouldSuppressRepeatedLog(category: String, message: String, at now: Date) -> Bool {
        guard let rule = repeatedLogRule(category: category, message: message) else { return false }
        return duplicateFilterQueue.sync {
            if let last = lastNoisyLogAtByKey[rule.key],
               now.timeIntervalSince(last) < rule.window {
                return true
            }
            lastNoisyLogAtByKey[rule.key] = now
            if lastNoisyLogAtByKey.count > 64 {
                lastNoisyLogAtByKey = lastNoisyLogAtByKey.filter { now.timeIntervalSince($0.value) < 120 }
            }
            return false
        }
    }

    private static func repeatedLogRule(category: String, message: String) -> (key: String, window: TimeInterval)? {
        let lowered = message.lowercased()
        switch category {
        case "Speech":
            if message.contains("[ASR Session] task error"), lowered.contains("no speech detected") {
                return ("speech.no-speech-error", 5.0)
            }
            if message.hasPrefix("[AudioRoute] startOnce") {
                return ("speech.start-once", 2.0)
            }
            if message.hasPrefix("AudioCaptureSession start skipped alreadyRunning") {
                return ("speech.audio-start-skipped", 2.0)
            }
            if message.hasPrefix("[VoiceProcessingIO] prefer passthrough") {
                return ("speech.voice-processing-policy", 2.0)
            }
            if message.hasPrefix("[TypingTarget] rearm focused target reason=continuous-focus-check") {
                return ("speech.continuous-focus-check", 3.0)
            }
        case "Lifecycle":
            if message.contains("Event tap unexpectedly disabled") {
                return ("lifecycle.event-tap-disabled", 10.0)
            }
        default:
            break
        }
        return nil
    }
}

extension OSLog {
    func info(_ message: String) {
        GlobalLogger.log(message, log: self, type: .info)
    }
    func error(_ message: String) {
        GlobalLogger.log(message, log: self, type: .error)
    }
    func debug(_ message: String) {
        GlobalLogger.log(message, log: self, type: .debug)
    }
}
