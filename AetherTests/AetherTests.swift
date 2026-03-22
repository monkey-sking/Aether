import XCTest
@testable import Aether

@MainActor
class DictationHandlerTests: XCTestCase {
    
    class MockTextInjector: TextInjecting {
        var typedText = ""
        var deletedCount = 0
        
        func type(_ text: String, targetPID: pid_t?) {
            typedText.append(text)
        }
        
        func deleteBackward(count: Int, targetPID: pid_t?) {
            deletedCount += count
            if count <= typedText.count {
                typedText.removeLast(count)
            }
        }
    }

    struct MockSlowLLM: LLMProvider {
        let delayNs: UInt64

        func enhanceDictation(_ text: String) async throws -> String {
            try await Task.sleep(nanoseconds: delayNs)
            return text
        }

        func interpretCommand(_ text: String) async throws -> VoiceIntent {
            .unknown(text)
        }
    }
    
    var handler: DictationHandler!
    var mockInjector: MockTextInjector!
    
    override func setUp() {
        super.setUp()
        mockInjector = MockTextInjector()
        handler = DictationHandler(injector: mockInjector)
        handler.reset(targetPID: nil)
    }
    
    func testPartialExtension() {
        handler.onPartial("hello")
        XCTAssertEqual(mockInjector.typedText, "hello")
        XCTAssertEqual(handler.screenTypedText, "hello")
        
        handler.onPartial("hello world")
        XCTAssertEqual(mockInjector.typedText, "hello world")
        XCTAssertEqual(handler.screenTypedText, "hello world")
    }
    
    func testPartialSkippedIfChangedPrefix() {
        handler.onPartial("hello")
        // Engine corrected the word mid-stream
        handler.onPartial("help")
        // Should ignore and wait for onFinal
        XCTAssertEqual(mockInjector.typedText, "hello")
        XCTAssertEqual(handler.screenTypedText, "hello")
    }
    
    func testFinalDiffCorrection() async {
        handler.onPartial("hello")
        XCTAssertEqual(mockInjector.typedText, "hello")
        
        // Final corrected it to "help me"
        await handler.onFinal("help me")
        XCTAssertEqual(mockInjector.deletedCount, 2) // "lo" -> 2
        XCTAssertEqual(mockInjector.typedText, "help me")
    }
    
    func testRaceConditionOnReset() async {
        handler.onPartial("hello")

        handler.isLLMEnhancementEnabled = true
        handler.llmProvider = MockSlowLLM(delayNs: 100_000_000) // 100ms

        // Start finalization for the previous utterance, then reset immediately.
        // onFinal should observe utterance ID mismatch after async LLM returns.
        let finalizeTask = Task {
            await handler.onFinal("hello delayed")
        }
        await Task.yield()
        handler.reset(targetPID: nil)
        await finalizeTask.value

        XCTAssertEqual(mockInjector.typedText, "hello")
        XCTAssertEqual(mockInjector.deletedCount, 0)
        XCTAssertEqual(handler.screenTypedText, "")
    }
}

@MainActor
final class AppStateLockScreenTests: XCTestCase {
    func testLoginWindowFrontmostIsConsideredLocked() {
        XCTAssertTrue(AppState.isScreenLocked(frontmostBundleIdentifier: "com.apple.loginwindow"))
    }

    func testNonLoginWindowFrontmostIsNotConsideredLocked() {
        XCTAssertFalse(AppState.isScreenLocked(frontmostBundleIdentifier: "com.apple.TextEdit"))
        XCTAssertFalse(AppState.isScreenLocked(frontmostBundleIdentifier: nil))
    }

    func testLockStateOverridesVoiceExecutionGates() {
        XCTAssertFalse(
            AppState.shouldAllowVoiceIntent(
                isScreenLocked: true,
                isProductUnlocked: true,
                isIdlePaused: false
            )
        )
        XCTAssertFalse(
            AppState.shouldAllowVoiceFeature(
                isScreenLocked: true,
                isProductUnlocked: true,
                isFeatureEnabled: true,
                isIdlePaused: false
            )
        )
    }
}

@MainActor
final class AppStateUsageInsightsTests: XCTestCase {
    private func makeEvent(
        kind: AppState.VoiceUsageEventKind,
        action: String,
        content: String? = nil
    ) -> AppState.VoiceUsageEvent {
        AppState.VoiceUsageEvent(
            appName: "Notes",
            bundleIdentifier: "com.apple.Notes",
            kind: kind,
            action: action,
            content: content
        )
    }

    func testSuccessfulDictationMapsToStableDictationOutcome() {
        let record = AppState.classifyUsageInsightsEvent(
            makeEvent(kind: .dictation, action: "Dictation", content: "hello world")
        )

        XCTAssertEqual(record.outcome, .dictation)
        XCTAssertEqual(record.reasonCode, .dictation)
        XCTAssertFalse(record.isIssue)
    }

    func testNoSpeechMapsToAnomalyOutcome() {
        let record = AppState.classifyUsageInsightsEvent(
            makeEvent(kind: .dictation, action: "No Speech Detected")
        )

        XCTAssertEqual(record.outcome, .anomaly)
        XCTAssertEqual(record.reasonCode, .noSpeech)
        XCTAssertTrue(record.isIssue)
        XCTAssertTrue(record.isNoSpeech)
    }

    func testNoInputTargetMapsToUnmatchedReason() {
        let record = AppState.classifyUsageInsightsEvent(
            makeEvent(kind: .dictation, action: "No Input Target")
        )

        XCTAssertEqual(record.outcome, .unmatched)
        XCTAssertEqual(record.reasonCode, .noInputTarget)
        XCTAssertTrue(record.isIssue)
    }

    func testUnknownControlMapsToStableUnknownCommandReason() {
        let record = AppState.classifyUsageInsightsEvent(
            makeEvent(kind: .control, action: "No Matching Command")
        )

        XCTAssertEqual(record.outcome, .control)
        XCTAssertEqual(record.reasonCode, .unknownCommand)
        XCTAssertFalse(record.isIssue)
    }
}
