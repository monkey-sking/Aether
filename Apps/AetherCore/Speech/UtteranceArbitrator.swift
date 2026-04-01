import Foundation

enum UtteranceTransportContext: Equatable {
    case wakeFollowUp
    case pushToTalk
    case oneShot
}

enum UtteranceArbitrationState: Equatable {
    case pending
    case dictationCommitted
    case commandCommitted
}

struct UtteranceArbitrationEvidence: Equatable {
    let controlMode: InputControlMode
    let normalizedText: String
    let routerDecision: VoiceCommandDecision
    let hasStableTypingEvidence: Bool
    let hasLiveTypingEvidence: Bool
    let transport: UtteranceTransportContext
    let hasCommittedDictation: Bool

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.controlMode == rhs.controlMode &&
        lhs.normalizedText == rhs.normalizedText &&
        lhs.routerDecision.intent == rhs.routerDecision.intent &&
        lhs.routerDecision.confidence == rhs.routerDecision.confidence &&
        lhs.routerDecision.reason == rhs.routerDecision.reason &&
        lhs.hasStableTypingEvidence == rhs.hasStableTypingEvidence &&
        lhs.hasLiveTypingEvidence == rhs.hasLiveTypingEvidence &&
        lhs.transport == rhs.transport &&
        lhs.hasCommittedDictation == rhs.hasCommittedDictation
    }
}

struct UtteranceArbitrationResult: Equatable {
    let state: UtteranceArbitrationState

    var allowsDictationStreaming: Bool {
        state == .dictationCommitted
    }
}

enum UtteranceArbitrator {
    static func resolve(evidence: UtteranceArbitrationEvidence) -> UtteranceArbitrationResult {
        switch evidence.controlMode {
        case .command:
            return .init(state: .commandCommitted)
        case .dictation:
            return .init(state: .dictationCommitted)
        case .auto:
            break
        }

        if evidence.hasCommittedDictation || evidence.hasStableTypingEvidence {
            return .init(state: .dictationCommitted)
        }

        if isCommandIntent(evidence.routerDecision.intent),
           evidence.routerDecision.confidence >= .medium
        {
            return .init(state: .commandCommitted)
        }

        return .init(state: .pending)
    }

    private static func isCommandIntent(_ intent: VoiceIntent) -> Bool {
        switch intent {
        case .dictation, .unknown:
            return false
        default:
            return true
        }
    }
}
