import Foundation

enum InputControlMode: String, Equatable, Sendable {
    case auto
    case command
    case dictation

    init(_ mode: HeadMotionManager.RecognitionControlMode) {
        switch mode {
        case .auto:
            self = .auto
        case .command:
            self = .command
        case .dictation:
            self = .dictation
        }
    }

    init(_ mode: HUDRecognitionControlMode) {
        switch mode {
        case .auto:
            self = .auto
        case .command:
            self = .command
        case .dictation:
            self = .dictation
        }
    }

    var recognitionControlMode: HeadMotionManager.RecognitionControlMode {
        switch self {
        case .auto:
            return .auto
        case .command:
            return .command
        case .dictation:
            return .dictation
        }
    }

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

enum InputControlFocusState: String, Equatable, Sendable {
    case typing
    case nonTyping
    case suppressed
    case unknown

    var indicatesTyping: Bool {
        self == .typing
    }
}

enum InputControlSessionState: String, Equatable, Sendable {
    case idle
    case typingSession
    case commandSession
    case recoveryHold

    var keepsTypingInteraction: Bool {
        self == .typingSession || self == .recoveryHold
    }
}

enum InputControlInteractionState: String, Equatable, Sendable {
    case command
    case typing
    case suppressed
    case pending

    var isTyping: Bool {
        self == .typing
    }
}

enum InputControlUtteranceDecision: String, Equatable, Sendable {
    case pending
    case commandCommitted
    case dictationCommitted

    init(_ state: UtteranceArbitrationState) {
        switch state {
        case .pending:
            self = .pending
        case .commandCommitted:
            self = .commandCommitted
        case .dictationCommitted:
            self = .dictationCommitted
        }
    }

    var arbitrationState: UtteranceArbitrationState {
        switch self {
        case .pending:
            return .pending
        case .commandCommitted:
            return .commandCommitted
        case .dictationCommitted:
            return .dictationCommitted
        }
    }
}

struct InputControlSnapshot: Equatable, Sendable {
    let controlMode: InputControlMode
    let focusState: InputControlFocusState
    let sessionState: InputControlSessionState
    let interactionState: InputControlInteractionState
    let utteranceDecision: InputControlUtteranceDecision
    let hasCommittedDictation: Bool
    let hasStreamedDictation: Bool
    let bundleID: String?
    let source: String

    var resolvedTypingInteraction: Bool {
        switch utteranceDecision {
        case .dictationCommitted:
            return true
        case .commandCommitted:
            return false
        case .pending:
            return interactionState.isTyping
        }
    }
}

final class InputControlArbiter {
    static let shared = InputControlArbiter()

    private let lock = NSLock()
    private var controlMode: InputControlMode = .auto
    private var focusState: InputControlFocusState = .unknown
    private var sessionState: InputControlSessionState = .idle
    private var utteranceDecision: InputControlUtteranceDecision = .pending
    private var hasCommittedDictation: Bool = false
    private var hasStreamedDictation: Bool = false
    private var bundleID: String?
    private var source: String = "bootstrap"

    private init() {}

    static func resolveInteractionState(
        controlMode: InputControlMode,
        focusState: InputControlFocusState,
        sessionState: InputControlSessionState
    ) -> InputControlInteractionState {
        switch controlMode {
        case .command:
            return .command
        case .dictation:
            return .typing
        case .auto:
            break
        }

        switch focusState {
        case .suppressed:
            return .suppressed
        case .typing:
            return .typing
        case .nonTyping:
            if sessionState.keepsTypingInteraction {
                return .typing
            }
            return .command
        case .unknown:
            break
        }

        switch sessionState {
        case .typingSession, .recoveryHold:
            return .typing
        case .commandSession:
            return .command
        case .idle:
            return .pending
        }
    }

    static func resolveUtteranceDecision(
        controlMode: InputControlMode,
        transcript: String,
        routerDecision: VoiceCommandDecision,
        interactionState: InputControlInteractionState,
        hasLiveTypingEvidence: Bool,
        transport: UtteranceTransportContext,
        hasCommittedDictation: Bool
    ) -> UtteranceArbitrationResult {
        UtteranceArbitrator.resolve(
            evidence: .init(
                controlMode: controlMode,
                normalizedText: transcript,
                routerDecision: routerDecision,
                hasStableTypingEvidence: interactionState == .typing,
                hasLiveTypingEvidence: hasLiveTypingEvidence,
                transport: transport,
                hasCommittedDictation: hasCommittedDictation
            )
        )
    }

    var currentSnapshot: InputControlSnapshot {
        lock.lock()
        defer { lock.unlock() }
        return snapshotLocked()
    }

    @discardableResult
    func updateControlMode(_ mode: InputControlMode, source: String) -> InputControlSnapshot {
        sync(controlMode: mode, source: source)
    }

    @discardableResult
    func updateFocusState(
        _ state: InputControlFocusState,
        bundleID: String?? = nil,
        source: String
    ) -> InputControlSnapshot {
        sync(focusState: state, bundleID: bundleID, source: source)
    }

    @discardableResult
    func updateSessionState(
        _ state: InputControlSessionState,
        hasCommittedDictation: Bool? = nil,
        hasStreamedDictation: Bool? = nil,
        source: String
    ) -> InputControlSnapshot {
        sync(
            sessionState: state,
            hasCommittedDictation: hasCommittedDictation,
            hasStreamedDictation: hasStreamedDictation,
            source: source
        )
    }

    @discardableResult
    func updateUtteranceDecision(
        _ decision: InputControlUtteranceDecision,
        source: String
    ) -> InputControlSnapshot {
        sync(utteranceDecision: decision, source: source)
    }

    @discardableResult
    func reset(source: String) -> InputControlSnapshot {
        lock.lock()
        defer { lock.unlock() }
        controlMode = .auto
        focusState = .unknown
        sessionState = .idle
        utteranceDecision = .pending
        hasCommittedDictation = false
        hasStreamedDictation = false
        bundleID = nil
        self.source = source
        return snapshotLocked()
    }

    @discardableResult
    func sync(
        controlMode: InputControlMode? = nil,
        focusState: InputControlFocusState? = nil,
        sessionState: InputControlSessionState? = nil,
        utteranceDecision: InputControlUtteranceDecision? = nil,
        hasCommittedDictation: Bool? = nil,
        hasStreamedDictation: Bool? = nil,
        bundleID: String?? = nil,
        source: String
    ) -> InputControlSnapshot {
        lock.lock()
        defer { lock.unlock() }
        if let controlMode {
            self.controlMode = controlMode
        }
        if let focusState {
            self.focusState = focusState
        }
        if let sessionState {
            self.sessionState = sessionState
        }
        if let utteranceDecision {
            self.utteranceDecision = utteranceDecision
        }
        if let hasCommittedDictation {
            self.hasCommittedDictation = hasCommittedDictation
        }
        if let hasStreamedDictation {
            self.hasStreamedDictation = hasStreamedDictation
        }
        if let bundleID {
            self.bundleID = bundleID
        }
        self.source = source
        return snapshotLocked()
    }

    private func snapshotLocked() -> InputControlSnapshot {
        InputControlSnapshot(
            controlMode: controlMode,
            focusState: focusState,
            sessionState: sessionState,
            interactionState: Self.resolveInteractionState(
                controlMode: controlMode,
                focusState: focusState,
                sessionState: sessionState
            ),
            utteranceDecision: utteranceDecision,
            hasCommittedDictation: hasCommittedDictation,
            hasStreamedDictation: hasStreamedDictation,
            bundleID: bundleID,
            source: source
        )
    }
}
