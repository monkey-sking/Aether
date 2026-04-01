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

    func testAutoModeTypingInteractionCommitsDictationThroughSharedResolver() {
        let result = InputControlArbiter.resolveUtteranceDecision(
            controlMode: .auto,
            transcript: "打开面板",
            routerDecision: .init(intent: .showShortcutPanel, confidence: .high, reason: "alias"),
            interactionState: .typing,
            hasLiveTypingEvidence: false,
            transport: .wakeFollowUp,
            hasCommittedDictation: false
        )

        XCTAssertEqual(result.state, .dictationCommitted)
    }

    func testAutoModeCommandInteractionCommitsCommandThroughSharedResolver() {
        let result = InputControlArbiter.resolveUtteranceDecision(
            controlMode: .auto,
            transcript: "打开面板",
            routerDecision: .init(intent: .showShortcutPanel, confidence: .high, reason: "alias"),
            interactionState: .command,
            hasLiveTypingEvidence: false,
            transport: .wakeFollowUp,
            hasCommittedDictation: false
        )

        XCTAssertEqual(result.state, .commandCommitted)
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

    func testResolvedTypingInteractionPrefersCommittedCommandDecision() {
        let snapshot = InputControlSnapshot(
            controlMode: .auto,
            focusState: .typing,
            sessionState: .typingSession,
            interactionState: .typing,
            utteranceDecision: .commandCommitted,
            hasCommittedDictation: false,
            hasStreamedDictation: true,
            bundleID: "com.example.input",
            source: "test"
        )

        XCTAssertFalse(snapshot.resolvedTypingInteraction)
    }
}
