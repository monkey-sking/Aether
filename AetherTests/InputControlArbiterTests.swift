import XCTest
@testable import Aether

final class InputControlArbiterTests: XCTestCase {
    override func tearDown() {
        InputControlArbiter.shared.reset(source: "test-teardown")
        super.tearDown()
    }

    func testAutoModeSuppressedFocusWinsOverTypingSession() {
        let resolved = InputControlArbiter.resolveInteractionState(
            controlMode: .auto,
            focusState: .suppressed,
            sessionState: .typingSession
        )

        XCTAssertEqual(resolved, .suppressed)
    }

    func testAutoModeTypingSessionWinsOverNonTypingFocus() {
        let resolved = InputControlArbiter.resolveInteractionState(
            controlMode: .auto,
            focusState: .nonTyping,
            sessionState: .typingSession
        )

        XCTAssertEqual(resolved, .typing)
    }

    func testAutoModeNonTypingFocusBecomesCommand() {
        let resolved = InputControlArbiter.resolveInteractionState(
            controlMode: .auto,
            focusState: .nonTyping,
            sessionState: .idle
        )

        XCTAssertEqual(resolved, .command)
    }

    func testCommandModeForcesCommandInteraction() {
        let resolved = InputControlArbiter.resolveInteractionState(
            controlMode: .command,
            focusState: .typing,
            sessionState: .typingSession
        )

        XCTAssertEqual(resolved, .command)
    }

    func testAutoModeCommandIntentCommitsCommandThroughSharedResolver() {
        let result = InputControlArbiter.resolveUtteranceDecision(
            controlMode: .auto,
            transcript: "打开面板",
            routerDecision: .init(intent: .showShortcutPanel, confidence: .high, reason: "alias"),
            interactionState: .typing,
            hasLiveTypingEvidence: false,
            transport: .wakeFollowUp,
            hasCommittedDictation: false
        )

        XCTAssertEqual(result.state, .commandCommitted)
    }

    func testAutoModeTypingInteractionCommitsDictationThroughSharedResolver() {
        let result = InputControlArbiter.resolveUtteranceDecision(
            controlMode: .auto,
            transcript: "今天下午三点开会",
            routerDecision: .init(intent: .dictation("今天下午三点开会"), confidence: .medium, reason: "dictation"),
            interactionState: .typing,
            hasLiveTypingEvidence: false,
            transport: .wakeFollowUp,
            hasCommittedDictation: false
        )

        XCTAssertEqual(result.state, .dictationCommitted)
    }

    func testUpdateFocusStateCanClearBundleID() {
        _ = InputControlArbiter.shared.updateFocusState(
            .typing,
            bundleID: "com.example.input",
            source: "test-set-bundle"
        )
        XCTAssertEqual(InputControlArbiter.shared.currentSnapshot.bundleID, "com.example.input")

        let clearedBundleID: String? = nil
        _ = InputControlArbiter.shared.updateFocusState(
            .unknown,
            bundleID: clearedBundleID,
            source: "test-clear-bundle"
        )

        XCTAssertNil(InputControlArbiter.shared.currentSnapshot.bundleID)
    }
}
