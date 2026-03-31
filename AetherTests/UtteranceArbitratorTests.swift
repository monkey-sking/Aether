import XCTest
@testable import Aether

final class UtteranceArbitratorTests: XCTestCase {
    func testExplicitCommandModeCommitsCommand() {
        let result = UtteranceArbitrator.resolve(
            evidence: .init(
                controlMode: .command,
                normalizedText: "打开面板",
                routerDecision: .init(intent: .showShortcutPanel, confidence: .high, reason: "alias"),
                hasStableTypingEvidence: true,
                hasLiveTypingEvidence: false,
                transport: .wakeFollowUp,
                hasCommittedDictation: false
            )
        )

        XCTAssertEqual(result.state, .commandCommitted)
        XCTAssertFalse(result.allowsDictationStreaming)
    }

    func testAutoModeKeepsPendingWithoutTypingEvidenceForDictationLikeText() {
        let result = UtteranceArbitrator.resolve(
            evidence: .init(
                controlMode: .auto,
                normalizedText: "今天下午三点开会",
                routerDecision: .init(intent: .dictation("今天下午三点开会"), confidence: .medium, reason: "dictation"),
                hasStableTypingEvidence: false,
                hasLiveTypingEvidence: false,
                transport: .wakeFollowUp,
                hasCommittedDictation: false
            )
        )

        XCTAssertEqual(result.state, .pending)
        XCTAssertFalse(result.allowsDictationStreaming)
    }

    func testAutoModeCommitsDictationWhenTypingEvidenceIsStable() {
        let result = UtteranceArbitrator.resolve(
            evidence: .init(
                controlMode: .auto,
                normalizedText: "今天下午三点开会",
                routerDecision: .init(intent: .dictation("今天下午三点开会"), confidence: .medium, reason: "dictation"),
                hasStableTypingEvidence: true,
                hasLiveTypingEvidence: false,
                transport: .wakeFollowUp,
                hasCommittedDictation: false
            )
        )

        XCTAssertEqual(result.state, .dictationCommitted)
        XCTAssertTrue(result.allowsDictationStreaming)
    }
}
