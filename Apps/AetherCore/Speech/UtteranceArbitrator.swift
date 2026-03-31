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
    let controlMode: HeadMotionManager.RecognitionControlMode
    let normalizedText: String
    let routerDecision: VoiceCommandDecision
    let hasStableTypingEvidence: Bool
    let hasLiveTypingEvidence: Bool
    let transport: UtteranceTransportContext
    let hasCommittedDictation: Bool
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

        if isCommandIntent(evidence.routerDecision.intent),
           evidence.routerDecision.confidence >= .medium
        {
            return .init(state: .commandCommitted)
        }

        if evidence.hasCommittedDictation || evidence.hasStableTypingEvidence {
            return .init(state: .dictationCommitted)
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
