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

        func rewriteText(_ text: String, mode: TextRewriteMode) async throws -> String {
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

    func testRewriteEventMapsToStableDictationOutcome() {
        let record = AppState.classifyUsageInsightsEvent(
            AppState.VoiceUsageEvent(
                appName: "Notes",
                bundleIdentifier: "com.apple.Notes",
                kind: .dictation,
                action: "全文纠错优化",
                content: "优化后的文本",
                originalContent: "优化前的文本",
                eventCode: "rewrite.fullDocument.proofreadAndPolish"
            )
        )

        XCTAssertEqual(record.outcome, .dictation)
        XCTAssertEqual(record.reasonCode, .dictation)
        XCTAssertFalse(record.isIssue)
    }

    func testSanitizedWakeWordUsageContentStripsLeadingWakeWordInWakeMode() {
        let result = AppState.sanitizedWakeWordUsageContent(
            "你好，芝麻开门",
            localeIdentifier: "zh-CN",
            stripsWakeWord: true,
            overrides: [
                VoiceLanguageTermsOverrideConfig(
                    localeIdentifier: "zh-CN",
                    wakeWords: ["你好"],
                    commandPrefixes: [],
                    dictationPrefixes: []
                )
            ]
        )

        XCTAssertEqual(result, "芝麻开门")
    }

    func testSanitizedWakeWordUsageContentKeepsPrefixOutsideWakeMode() {
        let result = AppState.sanitizedWakeWordUsageContent(
            "你好，芝麻开门",
            localeIdentifier: "zh-CN",
            stripsWakeWord: false,
            overrides: [
                VoiceLanguageTermsOverrideConfig(
                    localeIdentifier: "zh-CN",
                    wakeWords: ["你好"],
                    commandPrefixes: [],
                    dictationPrefixes: []
                )
            ]
        )

        XCTAssertEqual(result, "你好，芝麻开门")
    }

}

@MainActor
final class SpeechManagerFinalResultTests: XCTestCase {
    func testCompletedOneShotFinalResultCommitsImmediately() {
        XCTAssertTrue(
            SpeechManager.shouldCommitCompletedOneShotFinalResult(
                isStopping: false,
                isAlwaysListeningEnabled: false,
                finalTranscript: "下一页"
            )
        )
    }

    func testCompletedOneShotFinalResultSkipsContinuousOrEmptyStates() {
        XCTAssertFalse(
            SpeechManager.shouldCommitCompletedOneShotFinalResult(
                isStopping: true,
                isAlwaysListeningEnabled: false,
                finalTranscript: "下一页"
            )
        )
        XCTAssertFalse(
            SpeechManager.shouldCommitCompletedOneShotFinalResult(
                isStopping: false,
                isAlwaysListeningEnabled: true,
                finalTranscript: "下一页"
            )
        )
        XCTAssertFalse(
            SpeechManager.shouldCommitCompletedOneShotFinalResult(
                isStopping: false,
                isAlwaysListeningEnabled: false,
                finalTranscript: "   "
            )
        )
    }
}

@MainActor
final class AppStateLLMConfigurationTests: XCTestCase {
    private func makeEphemeralDefaults() -> UserDefaults {
        let suiteName = "AetherTests.LLM.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    func testDefaultLLMEndpointTextPrefersStoredValueOverEnvironment() {
        let defaults = makeEphemeralDefaults()
        defaults.set("https://saved.example.com/v1", forKey: AppState.llmEndpointStorageKey)

        let value = AppState.defaultLLMEndpointText(
            environment: ["AETHER_LLM_ENDPOINT": "https://env.example.com/v1"],
            defaults: defaults
        )

        XCTAssertEqual(value, "https://saved.example.com/v1")
    }

    func testDefaultLLMModelTextPrefersStoredValueOverEnvironment() {
        let defaults = makeEphemeralDefaults()
        defaults.set("gpt-4.1-mini", forKey: AppState.llmModelStorageKey)

        let value = AppState.defaultLLMModelText(
            environment: ["AETHER_LLM_MODEL": "env-model"],
            defaults: defaults
        )

        XCTAssertEqual(value, "gpt-4.1-mini")
    }
}

final class WakeWordDetectorTests: XCTestCase {
    private func makeDetector(wakeWords: [String] = ["幻影"]) -> WakeWordDetector {
        let detector = WakeWordDetector()
        detector.overrides = [
            VoiceLanguageTermsOverrideConfig(
                localeIdentifier: "zh-CN",
                wakeWords: wakeWords,
                commandPrefixes: [],
                dictationPrefixes: []
            )
        ]
        return detector
    }

    func testStrictPrefixModeRequiresWakeWordAtBeginning() {
        let detector = makeDetector()

        let result = detector.process(
            "嗯嗯 幻影 打开设置",
            localeIdentifier: "zh-CN",
            matchMode: .strictPrefix
        )

        XCTAssertFalse(result.wakeDetected)
        XCTAssertEqual(result.payload, "嗯嗯 幻影 打开设置")
    }

    func testRetryAwareStandbyModeAcceptsLaterRetryInSameUtterance() {
        let detector = makeDetector()

        let result = detector.process(
            "嗯嗯 幻影 打开设置",
            localeIdentifier: "zh-CN",
            matchMode: .retryAwareStandby
        )

        XCTAssertTrue(result.wakeDetected)
        XCTAssertEqual(result.matchedPhrase, "幻影")
        XCTAssertEqual(result.payload, "打开设置")
    }

    func testStrictPrefixModeStripsAutoInsertedSeparatorAfterWakeWord() {
        let detector = makeDetector()

        let result = detector.process(
            "幻影，你好世界",
            localeIdentifier: "zh-CN",
            matchMode: .strictPrefix
        )

        XCTAssertTrue(result.wakeDetected)
        XCTAssertEqual(result.payload, "你好世界")
    }

    func testRetryAwareStandbyModeStripsAutoInsertedSeparatorAfterWakeWord() {
        let detector = makeDetector()

        let result = detector.process(
            "嗯嗯 幻影， 你好世界",
            localeIdentifier: "zh-CN",
            matchMode: .retryAwareStandby
        )

        XCTAssertTrue(result.wakeDetected)
        XCTAssertEqual(result.payload, "你好世界")
    }

    func testRetryAwareStandbyModeKeepsLongLeadInRejected() {
        let detector = makeDetector()

        let result = detector.process(
            "这是一个很长的前缀然后才说幻影 打开设置",
            localeIdentifier: "zh-CN",
            matchMode: .retryAwareStandby
        )

        XCTAssertFalse(result.wakeDetected)
    }

    func testRetryAwareStandbyModeDoesNotUseFuzzyMidUtteranceRetry() {
        let detector = makeDetector()

        let result = detector.process(
            "嗯嗯 幻映 打开设置",
            localeIdentifier: "zh-CN",
            matchMode: .retryAwareStandby
        )

        XCTAssertFalse(result.wakeDetected)
    }

    func testWakePayloadStripsAutoInsertedPunctuationAfterWakeWord() {
        let detector = makeDetector()

        let result = detector.process(
            "幻影，你好",
            localeIdentifier: "zh-CN",
            matchMode: .strictPrefix
        )

        XCTAssertTrue(result.wakeDetected)
        XCTAssertEqual(result.payload, "你好")
    }

    func testRetryAwareWakePayloadStripsAutoInsertedPunctuationAfterWakeWord() {
        let detector = makeDetector()

        let result = detector.process(
            "嗯嗯 幻影，你好",
            localeIdentifier: "zh-CN",
            matchMode: .retryAwareStandby
        )

        XCTAssertTrue(result.wakeDetected)
        XCTAssertEqual(result.payload, "你好")
    }

    func testRetryAwareStandbyModeAllowsWhitelistedLeadInWord() {
        let detector = makeDetector()

        let result = detector.process(
            "那个 幻影 打开设置",
            localeIdentifier: "zh-CN",
            matchMode: .retryAwareStandby
        )

        XCTAssertTrue(result.wakeDetected)
        XCTAssertEqual(result.payload, "打开设置")
    }

    func testRetryAwareStandbyModeAllowsNaturalInterjectionLeadIn() {
        let detector = makeDetector()

        let result = detector.process(
            "哎呀 幻影 打开设置",
            localeIdentifier: "zh-CN",
            matchMode: .retryAwareStandby
        )

        XCTAssertTrue(result.wakeDetected)
        XCTAssertEqual(result.payload, "打开设置")
    }

    func testRetryAwareStandbyModeAllowsShortConversationalLeadInChain() {
        let detector = makeDetector()

        let result = detector.process(
            "嗯哼这个 幻影 打开设置",
            localeIdentifier: "zh-CN",
            matchMode: .retryAwareStandby
        )

        XCTAssertTrue(result.wakeDetected)
        XCTAssertEqual(result.payload, "打开设置")
    }

    func testRetryAwareStandbyModeAllowsLongerWhitelistedChineseLeadInChain() {
        let detector = makeDetector()

        let result = detector.process(
            "嗯那个这个请问 幻影 打开设置",
            localeIdentifier: "zh-CN",
            matchMode: .retryAwareStandby
        )

        XCTAssertTrue(result.wakeDetected)
        XCTAssertEqual(result.payload, "打开设置")
    }

    func testRetryAwareStandbyModeAllowsPunctuatedLeadInChainWithinExpandedRawBudget() {
        let detector = makeDetector()

        let result = detector.process(
            "诶，那个，那个，幻影 打开设置",
            localeIdentifier: "zh-CN",
            matchMode: .retryAwareStandby
        )

        XCTAssertTrue(result.wakeDetected)
        XCTAssertEqual(result.payload, "打开设置")
    }

    func testRetryAwareStandbyModeRecoversRepeatedWakeRetryAtTail() {
        let detector = makeDetector(wakeWords: ["你好"])

        let result = detector.process(
            "这是什么你好你好",
            localeIdentifier: "zh-CN",
            matchMode: .retryAwareStandby
        )

        XCTAssertTrue(result.wakeDetected)
        XCTAssertEqual(result.matchedPhrase, "你好")
        XCTAssertEqual(result.payload, "")
    }

    func testRetryAwareStandbyModeRecoversLaterRepeatedWakeAfterEarlierMidUtteranceMiss() {
        let detector = makeDetector(wakeWords: ["你好"])

        let result = detector.process(
            "属性你好，你用的哪个？你好？",
            localeIdentifier: "zh-CN",
            matchMode: .retryAwareStandby
        )

        XCTAssertTrue(result.wakeDetected)
        XCTAssertEqual(result.matchedPhrase, "你好")
        XCTAssertEqual(result.payload, "")
    }

    func testRetryAwareStandbyModeKeepsSingleMidUtteranceWakeRejected() {
        let detector = makeDetector(wakeWords: ["你好"])

        let result = detector.process(
            "属性你好，你用的哪个浏览器啊",
            localeIdentifier: "zh-CN",
            matchMode: .retryAwareStandby
        )

        XCTAssertFalse(result.wakeDetected)
    }

    func testRetryAwareStandbyModeDoesNotRecoverRepeatedWakeWhenTailHasRealContent() {
        let detector = makeDetector(wakeWords: ["你好"])

        let result = detector.process(
            "这是什么你好你好朋友",
            localeIdentifier: "zh-CN",
            matchMode: .retryAwareStandby
        )

        XCTAssertFalse(result.wakeDetected)
    }

    func testRetryAwareStandbyModeRejectsNonFillerLeadIn() {
        let detector = makeDetector()

        let result = detector.process(
            "测试 幻影 打开设置",
            localeIdentifier: "zh-CN",
            matchMode: .retryAwareStandby
        )

        XCTAssertFalse(result.wakeDetected)
    }

    func testAwakeFollowUpModeAllowsFillerThenWakeWord() {
        let detector = makeDetector()

        let result = detector.process(
            "嗯，幻影，打开设置",
            localeIdentifier: "zh-CN",
            matchMode: .awakeFollowUp
        )

        XCTAssertTrue(result.wakeDetected)
        XCTAssertEqual(result.payload, "打开设置")
    }

    func testAwakeFollowUpModeConsumesDirectWakePrefix() {
        let detector = makeDetector()

        let result = detector.process(
            "幻影，你好",
            localeIdentifier: "zh-CN",
            matchMode: .awakeFollowUp
        )

        XCTAssertTrue(result.wakeDetected)
        XCTAssertEqual(result.payload, "你好")
    }
}

@MainActor
final class SpeechManagerGuardrailTests: XCTestCase {
    func testWakeGateBlocksTypingBeforeWake() {
        XCTAssertFalse(
            SpeechManager.shouldAllowWakeGatedTyping(
                isWakeWordEnabled: true,
                isDirectCommandEnabled: false,
                isAwake: false,
                wakeWordDetected: false
            )
        )
    }

    func testWakeGateAllowsTypingAfterWakeDetection() {
        XCTAssertTrue(
            SpeechManager.shouldAllowWakeGatedTyping(
                isWakeWordEnabled: true,
                isDirectCommandEnabled: false,
                isAwake: false,
                wakeWordDetected: true
            )
        )
    }

    func testWakeGateAllowsActiveWakeDictationAfterWakeWindowDrops() {
        XCTAssertTrue(
            SpeechManager.shouldAllowWakeGatedTyping(
                isWakeWordEnabled: true,
                isDirectCommandEnabled: false,
                isAwake: false,
                wakeWordDetected: false,
                keepActiveWakeDictation: true
            )
        )
    }

    func testWakeGatedDictationHoldStaysActiveDuringUtteranceBeforeStreaming() {
        XCTAssertTrue(
            SpeechManager.shouldKeepWakeGatedDictationActive(
                isWakeWordEnabled: true,
                isDirectCommandEnabled: false,
                sessionTypingMode: true,
                isUtteranceActive: true,
                hasStreamedDictation: false,
                pendingWakeFollowUp: false,
                fallbackWindowActive: false
            )
        )
    }

    func testWakeGatedDictationHoldDoesNotKeepIdleStandbyActive() {
        XCTAssertFalse(
            SpeechManager.shouldKeepWakeGatedDictationActive(
                isWakeWordEnabled: true,
                isDirectCommandEnabled: false,
                sessionTypingMode: true,
                isUtteranceActive: false,
                hasStreamedDictation: false,
                pendingWakeFollowUp: false,
                fallbackWindowActive: false
            )
        )
    }

    func testWakeGatedDictationHoldStaysActiveDuringLateFinalGraceWhenTextAlreadyStreamed() {
        XCTAssertTrue(
            SpeechManager.shouldKeepWakeGatedDictationActive(
                isWakeWordEnabled: true,
                isDirectCommandEnabled: false,
                sessionTypingMode: true,
                isUtteranceActive: false,
                hasStreamedDictation: true,
                pendingWakeFollowUp: false,
                fallbackWindowActive: true
            )
        )
    }

    func testSpeechActivityHoldStaysActiveBrieflyAfterRecentVoiceActivity() {
        let now = Date()

        XCTAssertTrue(
            SpeechManager.isSpeechActivityHoldActive(
                latestVoiceActivity: false,
                lastSpeechActivityAt: now.addingTimeInterval(-0.6),
                now: now,
                holdWindow: 1.1
            )
        )
    }

    func testWakeFollowUpRemainsActiveDuringRecentSpeechActivityHold() {
        XCTAssertTrue(
            SpeechManager.shouldKeepWakeFollowUpActive(
                isWakeFollowUpSessionActive: false,
                keepWakeGatedDictationHUD: false,
                speechActivityHoldActive: true
            )
        )
    }

    func testLateFinalHoldKeepsWakeFollowUpAliveDuringRecentSpeechActivity() {
        XCTAssertTrue(
            SpeechManager.shouldHoldWakeFollowUpForLateFinal(
                isUtteranceActive: false,
                hasTranscript: false,
                hasRecentTranscriptChange: false,
                speechActivityHoldActive: true
            )
        )
    }

    func testDictationOnlyHUDDoesNotHideWhileSpeechActivityHoldIsActive() {
        XCTAssertFalse(
            SpeechManager.shouldHideDictationOnlyHUDWithoutFocus(
                focusedTypingEvidence: false,
                effectiveDictating: false,
                speechActivityHoldActive: true
            )
        )
    }

    func testWakeLifecycleSuppressesPureWakePhraseTranscript() {
        XCTAssertTrue(
            SpeechManager.shouldSuppressWakeOnlyTranscriptDuringActiveWakeLifecycle(
                pendingWakePhrase: "你好",
                activeWakePhrases: ["你好", "艾瑟"],
                routedTranscript: "你好？",
                wakeLifecycleActive: true
            )
        )
    }

    func testWakeLifecycleSuppressesRepeatedWakePhraseTranscript() {
        XCTAssertTrue(
            SpeechManager.shouldSuppressWakeOnlyTranscriptDuringActiveWakeLifecycle(
                pendingWakePhrase: "你好",
                activeWakePhrases: ["你好"],
                routedTranscript: "你好你好你",
                wakeLifecycleActive: true
            )
        )
    }

    func testWakeLifecycleDoesNotSuppressWakePhraseWithRealContent() {
        XCTAssertFalse(
            SpeechManager.shouldSuppressWakeOnlyTranscriptDuringActiveWakeLifecycle(
                pendingWakePhrase: "你好",
                activeWakePhrases: ["你好"],
                routedTranscript: "你好浏览器",
                wakeLifecycleActive: true
            )
        )
    }

    func testWakeLifecycleDoesNotSuppressWakePhraseOutsideWakeLifecycle() {
        XCTAssertFalse(
            SpeechManager.shouldSuppressWakeOnlyTranscriptDuringActiveWakeLifecycle(
                pendingWakePhrase: "你好",
                activeWakePhrases: ["你好"],
                routedTranscript: "你好",
                wakeLifecycleActive: false
            )
        )
    }

    func testInlineWakePayloadPromotesTypingContextWithFocusedInputEvidence() {
        XCTAssertTrue(
            SpeechManager.shouldPromoteInlineWakePayloadToTypingContext(
                recognitionControlMode: .auto,
                dictationEnabled: true,
                wakeWordDetected: true,
                wakePayload: "今天天气不错",
                hasAuthoritativeTypingEvidence: true,
                liveTyping: false
            )
        )
    }

    func testInlineWakePayloadDoesNotPromoteTypingContextWithoutPayload() {
        XCTAssertFalse(
            SpeechManager.shouldPromoteInlineWakePayloadToTypingContext(
                recognitionControlMode: .auto,
                dictationEnabled: true,
                wakeWordDetected: true,
                wakePayload: "",
                hasAuthoritativeTypingEvidence: true,
                liveTyping: false
            )
        )
    }

    func testInlineWakePayloadDoesNotPromoteTypingContextWithoutTypingEvidence() {
        XCTAssertFalse(
            SpeechManager.shouldPromoteInlineWakePayloadToTypingContext(
                recognitionControlMode: .auto,
                dictationEnabled: true,
                wakeWordDetected: true,
                wakePayload: "今天天气不错",
                hasAuthoritativeTypingEvidence: false,
                liveTyping: false
            )
        )
    }

    func testInlineWakePayloadDoesNotPromoteTypingContextWhenPayloadLooksLikeCommand() {
        XCTAssertFalse(
            SpeechManager.shouldPromoteInlineWakePayloadToTypingContext(
                recognitionControlMode: .auto,
                dictationEnabled: true,
                wakeWordDetected: true,
                wakePayload: "打开面板",
                hasAuthoritativeTypingEvidence: true,
                liveTyping: false,
                commandLikely: true
            )
        )
    }

    func testWakeMatchModeUsesRetryAwareForAlwaysListeningWakeWordMode() {
        let mode = SpeechManager.wakeMatchMode(
            isWakeWordEnabled: true,
            isDirectCommandEnabled: false,
            isAlwaysListeningEnabled: true,
            isAwake: false
        )

        switch mode {
        case .retryAwareStandby:
            XCTAssertTrue(true)
        case .strictPrefix, .awakeFollowUp:
            XCTFail("Expected retry-aware wake matching in always-listening wake-word mode")
        }
    }

    func testWakeMatchModeUsesAwakeFollowUpInsideWakeWindow() {
        let mode = SpeechManager.wakeMatchMode(
            isWakeWordEnabled: true,
            isDirectCommandEnabled: false,
            isAlwaysListeningEnabled: true,
            isAwake: true
        )

        switch mode {
        case .awakeFollowUp:
            XCTAssertTrue(true)
        case .strictPrefix, .retryAwareStandby:
            XCTFail("Expected awake-follow-up matching while already awake")
        }
    }

    func testWakeMatchModeKeepsStrictPrefixOutsideAlwaysListeningWakeWordMode() {
        let mode = SpeechManager.wakeMatchMode(
            isWakeWordEnabled: true,
            isDirectCommandEnabled: false,
            isAlwaysListeningEnabled: false,
            isAwake: false
        )

        switch mode {
        case .strictPrefix:
            XCTAssertTrue(true)
        case .retryAwareStandby, .awakeFollowUp:
            XCTFail("Expected strict-prefix matching when always-listening is off")
        }
    }

    func testPartialWakeDoesNotSegmentImmediatelyEvenWhenWakePhraseHasNoInlinePayload() {
        XCTAssertFalse(
            SpeechManager.shouldSegmentRecognitionAfterPartialWake(
                isAlwaysListeningEnabled: true,
                isWakeWordEnabled: true,
                isDirectCommandEnabled: false,
                wakePayload: ""
            )
        )
        XCTAssertFalse(
            SpeechManager.shouldSegmentRecognitionAfterPartialWake(
                isAlwaysListeningEnabled: true,
                isWakeWordEnabled: true,
                isDirectCommandEnabled: false,
                wakePayload: "打开设置"
            )
        )
    }

    func testContinuousStandbyNoBufferStallRecoversWhenWakeStandbySessionGoesSilent() {
        XCTAssertTrue(
            SpeechManager.shouldRecoverFromContinuousStandbyNoBufferStall(
                isAlwaysListeningEnabled: true,
                isWakeWordEnabled: true,
                isDirectCommandEnabled: false,
                isAwake: false,
                isStopping: false,
                isUtteranceActive: false,
                audioCaptureRunning: true,
                recognitionRunning: true,
                pendingEngineRestart: false,
                bufferAge: 1.81,
                routeRebuildGraceActive: false,
                continuousRecoveryGraceActive: false,
                recognitionStartupGraceActive: false,
                recognitionUnavailableActive: false
            )
        )
    }

    func testContinuousStandbyNoBufferStallDoesNotRecoverWhileAlreadyAwake() {
        XCTAssertFalse(
            SpeechManager.shouldRecoverFromContinuousStandbyNoBufferStall(
                isAlwaysListeningEnabled: true,
                isWakeWordEnabled: true,
                isDirectCommandEnabled: false,
                isAwake: true,
                isStopping: false,
                isUtteranceActive: false,
                audioCaptureRunning: true,
                recognitionRunning: true,
                pendingEngineRestart: false,
                bufferAge: 1.81,
                routeRebuildGraceActive: false,
                continuousRecoveryGraceActive: false,
                recognitionStartupGraceActive: false,
                recognitionUnavailableActive: false
            )
        )
    }

    func testContinuousStandbyNoBufferStallDoesNotRecoverDuringStartupGrace() {
        XCTAssertFalse(
            SpeechManager.shouldRecoverFromContinuousStandbyNoBufferStall(
                isAlwaysListeningEnabled: true,
                isWakeWordEnabled: true,
                isDirectCommandEnabled: false,
                isAwake: false,
                isStopping: false,
                isUtteranceActive: false,
                audioCaptureRunning: true,
                recognitionRunning: true,
                pendingEngineRestart: false,
                bufferAge: 1.81,
                routeRebuildGraceActive: false,
                continuousRecoveryGraceActive: false,
                recognitionStartupGraceActive: true,
                recognitionUnavailableActive: false
            )
        )
    }

    func testWakeFollowUpTypingStatePreservedWhileAwakeAndTargetStable() {
        XCTAssertTrue(
            SpeechManager.shouldPreserveWakeFollowUpTypingState(
                isAlwaysListeningEnabled: true,
                isWakeWordEnabled: true,
                isDirectCommandEnabled: false,
                awakeWindowActive: true,
                pendingWakeFollowUp: false,
                recentExpiredWakeFollowUp: false,
                typingStateActive: true,
                sessionTargetAvailable: true,
                frontmostMatchesTarget: true,
                typingSuppressed: false
            )
        )
    }

    func testWakeFollowUpTypingStateNotPreservedAfterWakeWindowCloses() {
        XCTAssertFalse(
            SpeechManager.shouldPreserveWakeFollowUpTypingState(
                isAlwaysListeningEnabled: true,
                isWakeWordEnabled: true,
                isDirectCommandEnabled: false,
                awakeWindowActive: false,
                pendingWakeFollowUp: false,
                recentExpiredWakeFollowUp: false,
                typingStateActive: true,
                sessionTargetAvailable: true,
                frontmostMatchesTarget: true,
                typingSuppressed: false
            )
        )
    }

    func testWakeFollowUpTypingStateNotPreservedWhenFrontmostTargetChanges() {
        XCTAssertFalse(
            SpeechManager.shouldPreserveWakeFollowUpTypingState(
                isAlwaysListeningEnabled: true,
                isWakeWordEnabled: true,
                isDirectCommandEnabled: false,
                awakeWindowActive: true,
                pendingWakeFollowUp: false,
                recentExpiredWakeFollowUp: false,
                typingStateActive: true,
                sessionTargetAvailable: true,
                frontmostMatchesTarget: false,
                typingSuppressed: false
            )
        )
    }

    func testWakeFollowUpTypingStatePreservedDuringLateGraceWhenTargetStable() {
        XCTAssertTrue(
            SpeechManager.shouldPreserveWakeFollowUpTypingState(
                isAlwaysListeningEnabled: true,
                isWakeWordEnabled: true,
                isDirectCommandEnabled: false,
                awakeWindowActive: false,
                pendingWakeFollowUp: false,
                recentExpiredWakeFollowUp: true,
                typingStateActive: true,
                sessionTargetAvailable: true,
                frontmostMatchesTarget: true,
                typingSuppressed: false
            )
        )
    }

    func testValidateDictationEnhancementRejectsLanguageDrift() {
        let result = SpeechManager.validateDictationEnhancement(
            sourceText: "今天下午开会",
            candidateText: "meeting this afternoon",
            localeIdentifier: "zh-CN"
        )

        XCTAssertEqual(result, .reject("language-drift"))
    }

    func testValidateDictationEnhancementRejectsProtectedTokenChange() {
        let result = SpeechManager.validateDictationEnhancement(
            sourceText: "访问 https://example.com/docs",
            candidateText: "访问 https://example.com/blog",
            localeIdentifier: "zh-CN"
        )

        XCTAssertEqual(result, .reject("protected-token"))
    }

    func testValidateDictationEnhancementAcceptsPunctuationOnlyCorrection() {
        let result = SpeechManager.validateDictationEnhancement(
            sourceText: "你好世界",
            candidateText: "你好，世界。",
            localeIdentifier: "zh-CN"
        )

        XCTAssertEqual(result, .accept("你好，世界。", changed: false))
    }

    func testValidateDictationEnhancementAcceptsSmallShortTextFix() {
        let result = SpeechManager.validateDictationEnhancement(
            sourceText: "打字候",
            candidateText: "打字后",
            localeIdentifier: "zh-CN"
        )

        XCTAssertEqual(result, .accept("打字后", changed: true))
    }

    func testDictationEnhancementSkipReasonSkipsStructuredText() {
        XCTAssertEqual(
            SpeechManager.dictationEnhancementSkipReason(
                text: "访问 https://example.com/docs",
                localeIdentifier: "zh-CN"
            ),
            "structured-text"
        )
    }

    func testDictationEnhancementSkipReasonSkipsCodeLikeText() {
        XCTAssertEqual(
            SpeechManager.dictationEnhancementSkipReason(
                text: "func test() -> Void { return }",
                localeIdentifier: "en-US"
            ),
            "code-like"
        )
    }

    func testDictationEnhancementSkipReasonKeepsNaturalSentenceEligible() {
        XCTAssertNil(
            SpeechManager.dictationEnhancementSkipReason(
                text: "我们明天上午十点开会，然后把文档发给我。",
                localeIdentifier: "zh-CN"
            )
        )
    }

    func testResolvedSessionHardLimitsKeepsShortCapsForCommand() {
        let limits = SpeechManager.resolvedSessionHardLimits(
            isDictationStyle: false,
            commandMaxUtteranceMs: 30000,
            commandMaxSegmentSec: 32,
            dictationMaxUtteranceMs: 600000,
            dictationMaxSegmentSec: 600
        )

        XCTAssertEqual(limits.maxUtteranceMs, 30000)
        XCTAssertEqual(limits.maxSegmentSec, 32)
    }

    func testResolvedSessionHardLimitsUsesExtendedCapsForDictation() {
        let limits = SpeechManager.resolvedSessionHardLimits(
            isDictationStyle: true,
            commandMaxUtteranceMs: 30000,
            commandMaxSegmentSec: 32,
            dictationMaxUtteranceMs: 600000,
            dictationMaxSegmentSec: 600
        )

        XCTAssertEqual(limits.maxUtteranceMs, 600000)
        XCTAssertEqual(limits.maxSegmentSec, 600)
    }
}

final class AetherBuildVersionFormatterTests: XCTestCase {
    func testVersionDisplayUsesCompactMinutePrecision() {
        XCTAssertEqual(
            AetherBuildVersionFormatter.versionDisplay(
                shortVersion: "0.1.0",
                buildVersion: "20260324114540"
            ),
            "0.1.0 · 03-24 11:45"
        )
    }

    func testComparisonDisplayDropsRepeatedShortVersionForBetaBuilds() {
        let versions = AetherBuildVersionFormatter.comparisonDisplay(
            updateShortVersion: "0.1.0",
            updateBuildVersion: "20260324114540",
            updatePublicLabel: "b78",
            bundleShortVersion: "0.1.0",
            bundleBuildVersion: "20260324112148",
            bundlePublicLabel: "b77"
        )

        XCTAssertEqual(versions.update, "b78")
        XCTAssertEqual(versions.bundle, "b77")
    }

    func testComparisonDisplayFallsBackToSecondsWhenMinuteMatches() {
        let versions = AetherBuildVersionFormatter.comparisonDisplay(
            updateShortVersion: "0.1.0",
            updateBuildVersion: "20260324114540",
            bundleShortVersion: "0.1.0",
            bundleBuildVersion: "20260324114509"
        )

        XCTAssertEqual(versions.update, "03-24 11:45:40")
        XCTAssertEqual(versions.bundle, "03-24 11:45:09")
    }

    func testBetaChannelVersionDisplayUsesPublicLabelOnly() {
        XCTAssertEqual(
            AetherBuildVersionFormatter.versionDisplay(
                shortVersion: "0.1.0",
                buildVersion: "20260324114540",
                publicLabel: "b78",
                channel: .beta
            ),
            "b78"
        )
    }

    func testBetaChannelComparisonDisplayUsesBetaLabelsOnly() {
        let versions = AetherBuildVersionFormatter.comparisonDisplay(
            updateShortVersion: "0.1.1",
            updateBuildVersion: "20260324114540",
            updatePublicLabel: "b79",
            bundleShortVersion: "0.1.0",
            bundleBuildVersion: "20260324112148",
            bundlePublicLabel: "b78",
            channel: .beta
        )

        XCTAssertEqual(versions.update, "b79")
        XCTAssertEqual(versions.bundle, "b78")
    }

    func testPublicLabelPrefersExplicitAppcastLabelForDeltaUpdates() {
        XCTAssertEqual(
            AetherBuildVersionFormatter.publicLabel(
                from: "https://aether.7caifei.com/aether-beta/Aether20260325094148-20260324213703.delta",
                propertiesDictionary: [
                    AetherBuildVersionFormatter.publicVersionLabelElementName: "b86"
                ]
            ),
            "b86"
        )
    }

    func testPublicLabelAcceptsArbitraryNamespacePrefixFromSparkleProperties() {
        XCTAssertEqual(
            AetherBuildVersionFormatter.publicLabel(
                from: "https://aether.7caifei.com/aether-beta/Aether20260325130210-20260325105543.delta",
                propertiesDictionary: [
                    "ns1:publicVersionLabel": "b88"
                ]
            ),
            "b88"
        )
    }

    func testPublicVersionLabelMatchingIgnoresXMLPrefix() {
        XCTAssertTrue(AetherBuildVersionFormatter.matchesPublicVersionLabelName("aether:publicVersionLabel"))
        XCTAssertTrue(AetherBuildVersionFormatter.matchesPublicVersionLabelName("ns1:publicVersionLabel"))
        XCTAssertTrue(AetherBuildVersionFormatter.matchesPublicVersionLabelName("publicVersionLabel"))
        XCTAssertFalse(AetherBuildVersionFormatter.matchesPublicVersionLabelName("sparkle:version"))
    }

    func testPublicLabelStillFallsBackToZipName() {
        XCTAssertEqual(
            AetherBuildVersionFormatter.publicLabel(
                from: "https://aether.7caifei.com/aether-beta/Aether_0.1.0_b86.zip"
            ),
            "b86"
        )
    }

    func testPublicLabelIgnoresTrackingQueryString() {
        XCTAssertEqual(
            AetherBuildVersionFormatter.publicLabel(
                from: "https://auth.aether.7caifei.com/aether-beta/Aether_0.1.0_b86.zip?source=update&channel=beta&version=0.1.0"
            ),
            "b86"
        )
    }

    func testAppcastFeedInspectorParsesPublicLabelsByBuildVersion() {
        let xml = """
        <?xml version="1.0" encoding="utf-8"?>
        <rss version="2.0"
             xmlns:ns1="https://aether.7caifei.com/xml-namespaces/aether"
             xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
          <channel>
            <title>Aether</title>
            <item>
              <title>0.1.0</title>
              <sparkle:version>20260325135046</sparkle:version>
              <sparkle:shortVersionString>0.1.0</sparkle:shortVersionString>
              <ns1:publicVersionLabel>b89</ns1:publicVersionLabel>
              <enclosure url="https://auth.aether.7caifei.com/aether-beta/Aether_0.1.0_b89.zip" length="1" type="application/octet-stream" />
            </item>
            <item>
              <title>0.1.0</title>
              <sparkle:version>20260325130210</sparkle:version>
              <sparkle:shortVersionString>0.1.0</sparkle:shortVersionString>
              <ns1:publicVersionLabel>b88</ns1:publicVersionLabel>
              <enclosure url="https://auth.aether.7caifei.com/aether-beta/Aether_0.1.0_b88.zip" length="1" type="application/octet-stream" />
            </item>
          </channel>
        </rss>
        """

        XCTAssertEqual(
            AetherAppcastFeedInspector.publicLabelsByBuildVersion(from: Data(xml.utf8)),
            [
                "20260325135046": "b89",
                "20260325130210": "b88",
            ]
        )
    }
}

final class OpenAICompatibleProviderCompatibilityTests: XCTestCase {
    func testRequestDescriptorAcceptsBaseV1Endpoint() {
        let descriptor = OpenAICompatibleProvider.requestDescriptor(
            for: URL(string: "https://api.openai.com/v1")!
        )

        XCTAssertEqual(descriptor.flavor, .chatCompletions)
        XCTAssertEqual(descriptor.url.absoluteString, "https://api.openai.com/v1/chat/completions")
    }

    func testRequestDescriptorAcceptsLMStudioBaseEndpoint() {
        let descriptor = OpenAICompatibleProvider.requestDescriptor(
            for: URL(string: "http://127.0.0.1:1234/api/v1")!
        )

        XCTAssertEqual(descriptor.flavor, .lmStudioChat)
        XCTAssertEqual(descriptor.url.absoluteString, "http://127.0.0.1:1234/api/v1/chat")
    }

    func testRequestDescriptorAcceptsBareGatewayHost() {
        let descriptor = OpenAICompatibleProvider.requestDescriptor(
            for: URL(string: "https://sub.jlypx.de")!
        )

        XCTAssertEqual(descriptor.flavor, .chatCompletions)
        XCTAssertEqual(descriptor.url.absoluteString, "https://sub.jlypx.de/v1/chat/completions")
    }

    func testParseResponseTextSupportsChatMessageString() throws {
        let data = try jsonData([
            "choices": [
                ["message": ["content": "OK"]]
            ]
        ])

        XCTAssertEqual(try OpenAICompatibleProvider.parseResponseText(from: data), "OK")
    }

    func testParseResponseTextSupportsChatMessageContentArray() throws {
        let data = try jsonData([
            "choices": [
                [
                    "message": [
                        "content": [
                            ["type": "text", "text": "Hello"],
                            ["type": "text", "text": "World"],
                        ]
                    ]
                ]
            ]
        ])

        XCTAssertEqual(try OpenAICompatibleProvider.parseResponseText(from: data), "Hello\n\nWorld")
    }

    func testParseResponseTextSupportsLegacyCompletions() throws {
        let data = try jsonData([
            "choices": [
                ["text": "Legacy completion"]
            ]
        ])

        XCTAssertEqual(try OpenAICompatibleProvider.parseResponseText(from: data), "Legacy completion")
    }

    func testParseResponseTextSupportsResponsesOutputArray() throws {
        let data = try jsonData([
            "output": [
                [
                    "type": "message",
                    "content": [
                        ["type": "output_text", "text": "Response API"]
                    ]
                ]
            ]
        ])

        XCTAssertEqual(try OpenAICompatibleProvider.parseResponseText(from: data), "Response API")
    }

    func testParseModelListSupportsOpenAIListShape() throws {
        let data = try jsonData([
            "data": [
                ["id": "gpt-4.1"],
                ["id": "gpt-4o-mini"],
            ]
        ])

        XCTAssertEqual(
            try OpenAICompatibleProvider.parseModelList(from: data),
            ["gpt-4.1", "gpt-4o-mini"]
        )
    }

    func testParseModelListSupportsLMStudioListShape() throws {
        let data = try jsonData([
            "models": [
                ["id": "qwen2.5-7b-instruct"],
                ["id": "llama-3.2-3b-instruct"],
            ]
        ])

        XCTAssertEqual(
            try OpenAICompatibleProvider.parseModelList(from: data),
            ["llama-3.2-3b-instruct", "qwen2.5-7b-instruct"]
        )
    }

    func testRewritePromptIncludesASRExpertProfile() {
        let prompt = OpenAICompatibleProvider.rewritePrompt(
            text: "提示此我没发过去",
            mode: .proofreadAndPolish,
            profile: ASRExpertProfile(
                isEnabled: true,
                domain: "独立开发 / 图片处理 AI",
                tone: .directive,
                glossaryText: "Aether, Prompt, SwiftUI",
                extraInstructions: "修成书面指令，去掉口癖"
            )
        )

        XCTAssertTrue(prompt.contains("logic-consistency"))
        XCTAssertTrue(prompt.contains("独立开发 / 图片处理 AI"))
        XCTAssertTrue(prompt.contains("Aether, Prompt, SwiftUI"))
        XCTAssertTrue(prompt.contains("修成书面指令，去掉口癖"))
    }

    func testDictationPromptSkipsDisabledASRExpertProfile() {
        let prompt = OpenAICompatibleProvider.dictationPrompt(
            text: "hello world",
            profile: ASRExpertProfile(
                isEnabled: false,
                domain: "ignored",
                tone: .formal,
                glossaryText: "ignored",
                extraInstructions: "ignored"
            )
        )

        XCTAssertFalse(prompt.contains("ignored"))
        XCTAssertTrue(prompt.contains("hello world"))
    }

    func testRewritePromptMergesExplicitAndContextualGlossary() {
        let prompt = OpenAICompatibleProvider.rewritePrompt(
            text: "原始文本",
            mode: .proofreadAndPolish,
            profile: ASRExpertProfile(
                isEnabled: true,
                domain: "macOS development",
                tone: .formal,
                glossaryText: "Aether => Aether\nSwiftUI => SwiftUI",
                extraInstructions: ""
            ),
            contextualGlossaryText: "git hub => GitHub\nAether => Aether"
        )

        XCTAssertTrue(prompt.contains("Aether => Aether"))
        XCTAssertTrue(prompt.contains("SwiftUI => SwiftUI"))
        XCTAssertTrue(prompt.contains("git hub => GitHub"))
        XCTAssertEqual(prompt.components(separatedBy: "Aether => Aether").count, 2)
    }

    private func jsonData(_ object: Any) throws -> Data {
        try JSONSerialization.data(withJSONObject: object)
    }
}

@MainActor
final class SpeechManagerOverlapTests: XCTestCase {
    func testChineseCrossUtteranceOverlapNeedsFourCharacters() {
        XCTAssertEqual(SpeechManager.minimumCrossUtteranceOverlapLength(for: "老师"), 4)
        XCTAssertEqual(SpeechManager.minimumCrossUtteranceOverlapLength(for: "老师您好"), 4)
    }

    func testAsciiOrWhitespaceOverlapStillNeedsFourCharacters() {
        XCTAssertEqual(SpeechManager.minimumCrossUtteranceOverlapLength(for: "test"), 4)
        XCTAssertEqual(SpeechManager.minimumCrossUtteranceOverlapLength(for: "hi there"), 4)
    }

    func testSymbolOnlyOverlapUsesThreeCharacters() {
        XCTAssertEqual(SpeechManager.minimumCrossUtteranceOverlapLength(for: "--"), 3)
        XCTAssertEqual(SpeechManager.minimumCrossUtteranceOverlapLength(for: "..."), 3)
    }
}

@MainActor
final class SpeechManagerEmptyFinalFallbackTests: XCTestCase {
    func testEmptyFinalUsesMeaningfulChinesePartialFallback() {
        XCTAssertEqual(
            SpeechManager.fallbackTranscriptForUnexpectedEmptyFinal(
                finalTranscript: "",
                lastPartialTranscript: "你在认真地思索一下这个整个链条是什么样的"
            ),
            "你在认真地思索一下这个整个链条是什么样的"
        )
    }

    func testEmptyFinalIgnoresShortChinesePartial() {
        XCTAssertNil(
            SpeechManager.fallbackTranscriptForUnexpectedEmptyFinal(
                finalTranscript: "",
                lastPartialTranscript: "你好"
            )
        )
    }

    func testNonEmptyFinalDoesNotUsePartialFallback() {
        XCTAssertNil(
            SpeechManager.fallbackTranscriptForUnexpectedEmptyFinal(
                finalTranscript: "执行发送",
                lastPartialTranscript: "你在认真地思索一下这个整个链条是什么样的"
            )
        )
    }

    func testRecoverableNoSpeechUsesMeaningfulPartialFallbackDuringWakeFollowUpUtterance() {
        XCTAssertEqual(
            SpeechManager.fallbackTranscriptForRecoverableNoSpeechError(
                isAlwaysListeningEnabled: true,
                isRecoverable: true,
                failureReason: "no-speech-detected",
                lastPartialTranscript: "今天天气不错",
                isUtteranceActive: true
            ),
            "今天天气不错"
        )
    }

    func testRecoverableNoSpeechIgnoresShortWakeOnlyPartial() {
        XCTAssertNil(
            SpeechManager.fallbackTranscriptForRecoverableNoSpeechError(
                isAlwaysListeningEnabled: true,
                isRecoverable: true,
                failureReason: "no-speech-detected",
                lastPartialTranscript: "你好",
                isUtteranceActive: true
            )
        )
    }

    func testRecoverableNoSpeechRequiresActiveUtterance() {
        XCTAssertNil(
            SpeechManager.fallbackTranscriptForRecoverableNoSpeechError(
                isAlwaysListeningEnabled: true,
                isRecoverable: true,
                failureReason: "no-speech-detected",
                lastPartialTranscript: "打开面板",
                isUtteranceActive: false
            )
        )
    }

    func testRecoverableNoSpeechAllowsCommandSizedFallbackWhenCommandLikely() {
        XCTAssertEqual(
            SpeechManager.fallbackTranscriptForRecoverableNoSpeechError(
                isAlwaysListeningEnabled: true,
                isRecoverable: true,
                failureReason: "no-speech-detected",
                lastPartialTranscript: "打开面板",
                isUtteranceActive: true
            ),
            "打开面板"
        )
    }

    func testNoSpeechRecoveryBypassesBackoffDuringWakeActivationRecovery() {
        let resolution = SpeechManager.resolvedNoSpeechRecoveryBackoffDelay(
            reason: "no-speech-detected",
            standbyWakeMissRecoveryActive: false,
            wakeActivationRecoveryActive: true,
            consecutiveRecoveries: 6
        )

        XCTAssertEqual(resolution.delay, 0.05, accuracy: 0.0001)
        XCTAssertEqual(resolution.nextConsecutiveRecoveries, 0)
    }

    func testNoSpeechRecoveryUsesAccumulatedBackoffOutsideWakeRecovery() {
        let resolution = SpeechManager.resolvedNoSpeechRecoveryBackoffDelay(
            reason: "no-speech-detected",
            standbyWakeMissRecoveryActive: false,
            wakeActivationRecoveryActive: false,
            consecutiveRecoveries: 5
        )

        XCTAssertEqual(resolution.delay, 1.5, accuracy: 0.0001)
        XCTAssertEqual(resolution.nextConsecutiveRecoveries, 6)
    }
}
