import XCTest
@testable import Aether

final class VoiceActivityHoldPolicyTests: XCTestCase {
    func testRecentVoiceActivityIsTrueWhileVoiceIsStillActive() {
        XCTAssertTrue(
            VoiceActivityHoldPolicy.hasRecentVoiceActivity(
                latestVoiceActivity: true,
                lastVoiceActivityAge: nil,
                holdWindow: 1.1
            )
        )
    }

    func testRecentVoiceActivityKeepsShortGraceAfterVoiceDrops() {
        XCTAssertTrue(
            VoiceActivityHoldPolicy.hasRecentVoiceActivity(
                latestVoiceActivity: false,
                lastVoiceActivityAge: 0.45,
                holdWindow: 1.1
            )
        )
    }

    func testWakeFollowUpTimeoutExtendsWhileSpeechIsStillActive() {
        XCTAssertTrue(
            VoiceActivityHoldPolicy.shouldExtendWakeFollowUp(
                latestVoiceActivity: true,
                lastVoiceActivityAge: nil,
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
                latestVoiceActivity: true,
                lastVoiceActivityAge: nil,
                holdWindow: 1.1,
                recognitionRunning: false,
                audioRunning: true,
                isStopping: false
            )
        )
    }

    func testDictationHUDHoldRequiresTypingInteraction() {
        XCTAssertFalse(
            VoiceActivityHoldPolicy.shouldHoldDictationHUD(
                dictationEnabled: true,
                typingInteraction: false,
                wakeGated: true,
                wakeFollowUpActive: true,
                latestVoiceActivity: true,
                lastVoiceActivityAge: nil,
                holdWindow: 1.1
            )
        )
    }

    func testDictationHUDHoldKeepsWakeFollowUpTypingHUDDuringRecentVoiceActivity() {
        XCTAssertTrue(
            VoiceActivityHoldPolicy.shouldHoldDictationHUD(
                dictationEnabled: true,
                typingInteraction: true,
                wakeGated: true,
                wakeFollowUpActive: true,
                latestVoiceActivity: false,
                lastVoiceActivityAge: 0.35,
                holdWindow: 1.1
            )
        )
    }

    func testDictationHUDHoldDoesNotBypassClosedWakeWindow() {
        XCTAssertFalse(
            VoiceActivityHoldPolicy.shouldHoldDictationHUD(
                dictationEnabled: true,
                typingInteraction: true,
                wakeGated: true,
                wakeFollowUpActive: false,
                latestVoiceActivity: true,
                lastVoiceActivityAge: nil,
                holdWindow: 1.1
            )
        )
    }
}
