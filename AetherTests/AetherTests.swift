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
    private func makeDetector() -> WakeWordDetector {
        let detector = WakeWordDetector()
        detector.overrides = [
            VoiceLanguageTermsOverrideConfig(
                localeIdentifier: "zh-CN",
                wakeWords: ["幻影"],
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
