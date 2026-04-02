import XCTest
@testable import Aether

final class VoiceActivityHoldPolicyTests: XCTestCase {
    func testSpeechActivityHoldIsTrueWhileVoiceIsStillActive() {
        XCTAssertTrue(
            VoiceActivityHoldPolicy.isSpeechActivityHoldActive(
                latestVoiceActivity: true,
                lastSpeechActivityAge: nil,
                holdWindow: 1.1
            )
        )
    }

    func testSpeechActivityHoldKeepsShortGraceAfterVoiceDrops() {
        XCTAssertTrue(
            VoiceActivityHoldPolicy.isSpeechActivityHoldActive(
                latestVoiceActivity: false,
                lastSpeechActivityAge: 0.45,
                holdWindow: 1.1
            )
        )
    }

    func testWakeGatedDictationStayActiveWhileSpeechHoldIsLive() {
        XCTAssertTrue(
            VoiceActivityHoldPolicy.shouldKeepWakeGatedDictationActive(
                isWakeWordEnabled: true,
                isDirectCommandEnabled: false,
                sessionTypingMode: true,
                isUtteranceActive: false,
                hasStreamedDictation: false,
                pendingWakeFollowUp: false,
                fallbackWindowActive: false,
                speechActivityHoldActive: true
            )
        )
    }

    func testWakeFollowUpTimeoutExtendsWhileSpeechHoldIsStillActive() {
        XCTAssertTrue(
            VoiceActivityHoldPolicy.shouldExtendWakeFollowUp(
                speechActivityHoldActive: true,
                holdWindow: 1.1,
                recognitionRunning: true,
                audioRunning: true,
                isStopping: false
            )
        )
    }

    func testWakeFollowUpTimeoutDoesNotExtendWithoutActiveSession() {
        XCTAssertFalse(
            VoiceActivityHoldPolicy.shouldExtendWakeFollowUp(
                speechActivityHoldActive: true,
                holdWindow: 1.1,
                recognitionRunning: false,
                audioRunning: true,
                isStopping: false
            )
        )
    }

    func testWakeFollowUpLateFinalHoldKeepsSessionAliveForRecentTranscript() {
        XCTAssertTrue(
            VoiceActivityHoldPolicy.shouldHoldWakeFollowUpForLateFinal(
                isUtteranceActive: false,
                hasTranscript: false,
                hasRecentTranscriptChange: true,
                speechActivityHoldActive: false
            )
        )
    }

    func testDictationOnlyHUDCanHideWithoutFocusOnlyWhenNoHoldIsActive() {
        XCTAssertTrue(
            VoiceActivityHoldPolicy.shouldHideDictationOnlyHUDWithoutFocus(
                focusedTypingEvidence: false,
                effectiveDictating: false,
                speechActivityHoldActive: false
            )
        )
    }

    func testDictationOnlyHUDStaysVisibleDuringSpeechHoldEvenWithoutFocus() {
        XCTAssertFalse(
            VoiceActivityHoldPolicy.shouldHideDictationOnlyHUDWithoutFocus(
                focusedTypingEvidence: false,
                effectiveDictating: false,
                speechActivityHoldActive: true
            )
        )
    }
}
