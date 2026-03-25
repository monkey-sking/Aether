import XCTest
import Carbon.HIToolbox
@testable import Aether

final class VoiceCommandRouterTests: XCTestCase {
    var router: VoiceCommandRouter!

    override func setUp() {
        super.setUp()
        router = VoiceCommandRouter()
    }

    override func tearDown() {
        router = nil
        super.tearDown()
    }

    func testEmptyTranscript() {
        XCTAssertEqual(router.route(transcript: ""), .unknown(""))
        XCTAssertEqual(router.route(transcript: "   \n "), .unknown("   \n "))
    }

    func testBasicCommands() {
        XCTAssertEqual(router.route(transcript: "点击", localeIdentifier: "zh-CN"), .clickLeft)
        XCTAssertEqual(router.route(transcript: "右键", localeIdentifier: "zh-CN"), .clickRight)
        XCTAssertEqual(router.route(transcript: "双击", localeIdentifier: "zh-CN"), .doubleClick)
        XCTAssertEqual(router.route(transcript: "撤销", localeIdentifier: "zh-CN"), .undo)
        XCTAssertEqual(router.route(transcript: "粘贴", localeIdentifier: "zh-CN"), .paste)
        XCTAssertEqual(router.route(transcript: "停止", localeIdentifier: "zh-CN"), .stopPointer)
        XCTAssertEqual(router.route(transcript: "开始", localeIdentifier: "zh-CN"), .startPointer)
        XCTAssertEqual(router.route(transcript: "居中", localeIdentifier: "zh-CN"), .recenter)
    }

    func testCursorMoveAndSelectionCommands() {
        XCTAssertEqual(
            router.route(transcript: "命令向左移动3个字", bias: .dictationPreferred, localeIdentifier: "zh-CN"),
            .moveCursorHorizontally(-3)
        )
        XCTAssertEqual(
            router.route(transcript: "命令向右移动十个字", bias: .dictationPreferred, localeIdentifier: "zh-CN"),
            .moveCursorHorizontally(10)
        )
        XCTAssertEqual(
            router.route(transcript: "命令向左选择2个字", bias: .dictationPreferred, localeIdentifier: "zh-CN"),
            .selectHorizontally(-2)
        )
        XCTAssertEqual(
            router.route(transcript: "命令向右选择3个字符", bias: .dictationPreferred, localeIdentifier: "zh-CN"),
            .selectHorizontally(3)
        )
        XCTAssertEqual(
            router.route(transcript: "左移", bias: .forceCommand, localeIdentifier: "zh-CN"),
            .moveCursorHorizontally(-1)
        )
        XCTAssertEqual(
            router.route(transcript: "右选", bias: .forceCommand, localeIdentifier: "zh-CN"),
            .selectHorizontally(1)
        )
    }

    func testTypingModeRewriteCommandBypassesDictation() {
        XCTAssertEqual(
            router.route(transcript: "优化全文", bias: .dictationPreferred, localeIdentifier: "zh-CN"),
            .rewriteText(
                TextRewriteIntentPayload(
                    scope: .fullDocument,
                    mode: .proofreadAndPolish
                )
            )
        )
        XCTAssertEqual(
            router.route(transcript: "帮我全文纠错优化一下", bias: .dictationPreferred, localeIdentifier: "zh-CN"),
            .rewriteText(
                TextRewriteIntentPayload(
                    scope: .fullDocument,
                    mode: .proofreadAndPolish
                )
            )
        )
    }
    
    func testScrollingAndDragging() {
        XCTAssertEqual(router.route(transcript: "向上", localeIdentifier: "zh-CN"), .scroll(0, -300))
        XCTAssertEqual(router.route(transcript: "向下", localeIdentifier: "zh-CN"), .scroll(0, 300))
        XCTAssertEqual(router.route(transcript: "向下滚动", localeIdentifier: "zh-CN"), .scroll(0, 300))
        XCTAssertEqual(router.route(transcript: "到底", localeIdentifier: "zh-CN"), .scrollToWeb("bottom"))
        XCTAssertEqual(router.route(transcript: "到顶", localeIdentifier: "zh-CN"), .scrollToWeb("top"))
        XCTAssertEqual(router.route(transcript: "拖", localeIdentifier: "zh-CN"), .dragStart)
        XCTAssertEqual(router.route(transcript: "放", localeIdentifier: "zh-CN"), .dragEnd)
    }

    func testShortcutPanelAliases() {
        XCTAssertEqual(router.route(transcript: "显示面板", localeIdentifier: "zh-CN"), .showShortcutPanel)
        XCTAssertEqual(router.route(transcript: "显示快捷键面板", localeIdentifier: "zh-CN"), .showShortcutPanel)
        XCTAssertEqual(router.route(transcript: "关闭面板", localeIdentifier: "zh-CN"), .hideShortcutPanel)
    }

    func testShortcutPanelOverridePreservesDefaultAliases() {
        router.overrides = [
            VoiceCommandOverrideConfig(
                localeIdentifier: "zh-CN",
                commandID: VoiceCommandPreset.showShortcutPanel.rawValue,
                aliases: ["显示面板"]
            )
        ]

        XCTAssertEqual(router.route(transcript: "显示面板", localeIdentifier: "zh-CN"), .showShortcutPanel)
        XCTAssertEqual(router.route(transcript: "显示快捷键面板", localeIdentifier: "zh-CN"), .showShortcutPanel)
    }

    func testFrontmostTabCommandsBeatGenericPreviousNextTrackAliases() {
        let previousTab = FrontmostAppCommand(
            processIdentifier: 42,
            bundleIdentifier: "com.google.Chrome",
            appName: "Chrome",
            menuPath: ["Window"],
            title: "Previous Tab",
            shortcut: HotkeyBinding(keyCode: 33, modifiers: UInt64(NSEvent.ModifierFlags.command.rawValue | NSEvent.ModifierFlags.shift.rawValue)),
            aliases: ["上一个标签", "选择上一个标签", "切换到上一个标签"]
        )
        let nextTab = FrontmostAppCommand(
            processIdentifier: 42,
            bundleIdentifier: "com.google.Chrome",
            appName: "Chrome",
            menuPath: ["Window"],
            title: "Next Tab",
            shortcut: HotkeyBinding(keyCode: 30, modifiers: UInt64(NSEvent.ModifierFlags.command.rawValue | NSEvent.ModifierFlags.shift.rawValue)),
            aliases: ["下一个标签", "选择下一个标签", "切换到下一个标签"]
        )
        router.frontmostAppCommands = [previousTab, nextTab]

        XCTAssertEqual(router.route(transcript: "选择上一个标签"), .frontmostAppCommand(previousTab))
        XCTAssertEqual(router.route(transcript: "选择下一个标签"), .frontmostAppCommand(nextTab))
    }

    func testReopenClosedTabBeatsCloseTabForLongerAlias() {
        let closeTab = FrontmostAppCommand(
            processIdentifier: 42,
            bundleIdentifier: "com.google.Chrome",
            appName: "Chrome",
            menuPath: ["File"],
            title: "Close Tab",
            shortcut: HotkeyBinding(keyCode: 13, modifiers: UInt64(NSEvent.ModifierFlags.command.rawValue)),
            aliases: ["关闭标签", "关闭当前标签", "关掉标签页"]
        )
        let reopenClosedTab = FrontmostAppCommand(
            processIdentifier: 42,
            bundleIdentifier: "com.google.Chrome",
            appName: "Chrome",
            menuPath: ["History"],
            title: "Reopen Closed Tab",
            shortcut: HotkeyBinding(keyCode: 17, modifiers: UInt64(NSEvent.ModifierFlags.command.rawValue | NSEvent.ModifierFlags.shift.rawValue)),
            aliases: ["恢复标签", "重新打开标签", "重新打开关闭的标签", "恢复已关闭的标签"]
        )
        router.frontmostAppCommands = [closeTab, reopenClosedTab]

        XCTAssertEqual(router.route(transcript: "重新打开关闭的标签"), .frontmostAppCommand(reopenClosedTab))
    }

    func testPinyinFallback() {
        // "右键" / "邮件" / "有件" (You Jian)
        XCTAssertEqual(router.route(transcript: "邮件", localeIdentifier: "zh-CN"), .clickRight)
        XCTAssertEqual(router.route(transcript: "有件", localeIdentifier: "zh-CN"), .clickRight)

        // "单机" (Dan Ji -> Dian Ji roughly falling into .clickLeft using pinyin matching)
        XCTAssertEqual(router.route(transcript: "单机", localeIdentifier: "zh-CN"), .clickLeft)
        // "双机" (Shuang Ji)
        XCTAssertEqual(router.route(transcript: "双机", localeIdentifier: "zh-CN"), .doubleClick)
    }
    
    func testDictationParsing() {
        // Basic dictation fallback
        XCTAssertEqual(router.route(transcript: "今天天气不错", localeIdentifier: "zh-CN"), .dictation("今天天气不错"))

        // Force dictation keyword "输入"
        XCTAssertEqual(router.route(transcript: "输入你好", localeIdentifier: "zh-CN"), .dictation("你好"))
        XCTAssertEqual(router.route(transcript: "写一段代码", localeIdentifier: "zh-CN"), .dictation("一段代码"))
    }
    
    func testTypingModeBehavior() {
        // In typing mode, normal words should go to dictation unless explicitly forcing command
        XCTAssertEqual(
            router.route(transcript: "点击", bias: .dictationPreferred, localeIdentifier: "zh-CN"),
            .dictation("点击")
        )

        XCTAssertEqual(
            router.route(transcript: "向下滚动", bias: .dictationPreferred, localeIdentifier: "zh-CN"),
            .dictation("向下滚动")
        )
        XCTAssertEqual(
            router.route(transcript: "显示面板", bias: .dictationPreferred, localeIdentifier: "zh-CN"),
            .dictation("显示面板")
        )
        XCTAssertEqual(
            router.route(transcript: "显示面板。", bias: .dictationPreferred, localeIdentifier: "zh-CN"),
            .dictation("显示面板。")
        )
        XCTAssertEqual(
            router.route(transcript: "请显示面板设计稿", bias: .dictationPreferred, localeIdentifier: "zh-CN"),
            .dictation("请显示面板设计稿")
        )
        XCTAssertEqual(
            router.route(transcript: "把这段文字粘贴到下面", bias: .dictationPreferred, localeIdentifier: "zh-CN"),
            .dictation("把这段文字粘贴到下面")
        )
        XCTAssertEqual(
            router.route(transcript: "我想撤销昨天那段说明", bias: .dictationPreferred, localeIdentifier: "zh-CN"),
            .dictation("我想撤销昨天那段说明")
        )

        // "指令点击" in typing mode should bypass dictation and trigger command
        XCTAssertEqual(
            router.route(transcript: "指令点击", bias: .dictationPreferred, localeIdentifier: "zh-CN"),
            .clickLeft
        )
        XCTAssertEqual(
            router.route(transcript: "命令粘贴", bias: .dictationPreferred, localeIdentifier: "zh-CN"),
            .paste
        )
        XCTAssertEqual(
            router.route(transcript: "command right click", bias: .dictationPreferred, localeIdentifier: "en-US"),
            .clickRight
        )
    }

    func testTypingModeExecutionPrefixRunsCommands() {
        XCTAssertEqual(
            router.route(transcript: "执行粘贴", bias: .dictationPreferred, localeIdentifier: "zh-CN"),
            .paste
        )
        XCTAssertEqual(
            router.route(transcript: "执行，帮我粘贴一下吧", bias: .dictationPreferred, localeIdentifier: "zh-CN"),
            .paste
        )
    }

    func testTypingModeExecutionPrefixRunsFrontmostAppCommands() {
        let sendCommand = FrontmostAppCommand(
            processIdentifier: 7,
            bundleIdentifier: "com.openai.codex",
            appName: "Codex",
            menuPath: ["Custom Rules"],
            title: "Send",
            shortcut: HotkeyBinding(
                keyCode: kVK_Return,
                modifiers: UInt64(NSEvent.ModifierFlags.command.rawValue)
            ),
            aliases: ["发送", "确认发送"]
        )
        router.frontmostAppCommands = [sendCommand]

        XCTAssertEqual(
            router.route(transcript: "执行发送", bias: .dictationPreferred, localeIdentifier: "zh-CN"),
            .frontmostAppCommand(sendCommand)
        )
        XCTAssertEqual(
            router.route(transcript: "，执行发送", bias: .dictationPreferred, localeIdentifier: "zh-CN"),
            .frontmostAppCommand(sendCommand)
        )
        XCTAssertEqual(
            router.route(transcript: "执行，请帮我确认发送一下", bias: .dictationPreferred, localeIdentifier: "zh-CN"),
            .frontmostAppCommand(sendCommand)
        )
    }

    func testSuggestedCommandPhrasesPreferClosestContextualAlias() {
        let sendCommand = FrontmostAppCommand(
            processIdentifier: 7,
            bundleIdentifier: "com.openai.codex",
            appName: "Codex",
            menuPath: ["Custom Rules"],
            title: "Send",
            shortcut: HotkeyBinding(
                keyCode: kVK_Return,
                modifiers: UInt64(NSEvent.ModifierFlags.command.rawValue)
            ),
            aliases: ["发送", "确认发送"]
        )
        router.frontmostAppCommands = [sendCommand]

        XCTAssertEqual(
            router.suggestedCommandPhrases(for: "执行确认发", localeIdentifier: "zh-CN").first,
            "确认发送"
        )
    }

    func testSuggestedCommandPhrasesStripPrefixNoise() {
        let sendCommand = FrontmostAppCommand(
            processIdentifier: 7,
            bundleIdentifier: "com.openai.codex",
            appName: "Codex",
            menuPath: ["Custom Rules"],
            title: "Send",
            shortcut: HotkeyBinding(
                keyCode: kVK_Return,
                modifiers: UInt64(NSEvent.ModifierFlags.command.rawValue)
            ),
            aliases: ["发送", "确认发送"]
        )
        router.frontmostAppCommands = [sendCommand]

        XCTAssertEqual(
            router.suggestedCommandPhrases(for: "执行，帮我发送给他一下", localeIdentifier: "zh-CN").first,
            "发送"
        )
    }

    func testSuggestedCommandPhrasesUsePinyinSimilarity() {
        XCTAssertEqual(
            router.suggestedCommandPhrases(for: "执行粘帖", localeIdentifier: "zh-CN").first,
            "粘贴"
        )
    }

    func testCommandPreferredUnknownDoesNotFallBackToDictation() {
        XCTAssertEqual(
            router.route(transcript: "测试", bias: .commandPreferred),
            .unknown("测试")
        )
    }

    func testBiasOverrides() {
        XCTAssertEqual(
            router.route(transcript: "随便说什么", bias: .forceDictation),
            .dictation("随便说什么")
        )
        XCTAssertEqual(
            router.route(transcript: "你好", bias: .forceCommand),
            .unknown("你好")
        )
    }
}

final class DictationSafetyTests: XCTestCase {
    func testUtteranceExecutionGuardDeduplicatesSameUtterance() {
        var guardState = UtteranceExecutionGuard(maxHistory: 8)
        XCTAssertTrue(guardState.shouldExecute(sessionGeneration: 7, utteranceID: 42))
        XCTAssertFalse(guardState.shouldExecute(sessionGeneration: 7, utteranceID: 42))
    }

    func testUtteranceExecutionGuardAllowsSameUtteranceAcrossSessions() {
        var guardState = UtteranceExecutionGuard(maxHistory: 8)
        XCTAssertTrue(guardState.shouldExecute(sessionGeneration: 7, utteranceID: 42))
        XCTAssertTrue(guardState.shouldExecute(sessionGeneration: 8, utteranceID: 42))
    }
}

final class DeveloperSpeechProfileTests: XCTestCase {
    func testDeveloperSpeechProfileMatchesKnownDeveloperApps() {
        XCTAssertTrue(DeveloperSpeechProfile.matches(bundleIdentifier: "com.apple.terminal"))
        XCTAssertTrue(DeveloperSpeechProfile.matches(bundleIdentifier: "com.apple.dt.xcode"))
        XCTAssertTrue(DeveloperSpeechProfile.matches(bundleIdentifier: "com.cursor.Editor"))
        XCTAssertFalse(DeveloperSpeechProfile.matches(bundleIdentifier: "com.apple.mail"))
    }

    func testDeveloperSpeechProfileProvidesScopedContextualTerms() {
        let terminalTerms = DeveloperSpeechProfile.contextualTerms(for: ["com.apple.terminal"])
        XCTAssertTrue(terminalTerms.contains("新包"))
        XCTAssertTrue(terminalTerms.contains("brew"))

        let mailTerms = DeveloperSpeechProfile.contextualTerms(for: ["com.apple.mail"])
        XCTAssertTrue(mailTerms.isEmpty)
    }

    func testDeveloperSpeechProfileCorrectsHighConfidenceDeveloperPhrases() {
        XCTAssertEqual(
            DeveloperSpeechProfile.correctedText(
                "帮我打个心包",
                scope: .dictation,
                bundleIdentifiers: ["com.apple.terminal"]
            ),
            "帮我打个新包"
        )
        XCTAssertEqual(
            DeveloperSpeechProfile.correctedText(
                "打开后果 issue",
                scope: .command,
                bundleIdentifiers: ["com.apple.dt.xcode"]
            ),
            "打开GitHub issue"
        )
        XCTAssertEqual(
            DeveloperSpeechProfile.correctedText(
                "帮我打个心包",
                scope: .dictation,
                bundleIdentifiers: ["com.apple.mail"]
            ),
            "帮我打个心包"
        )
    }
}

@MainActor
final class SpeechManagerTypingModeTests: XCTestCase {
    func testForcedCommandHUDPreviewAppearsForInlinePrefixInTypingMode() {
        XCTAssertTrue(
            SpeechManager.shouldPreviewForcedCommandHUD(
                typingContext: true,
                intent: .scroll(0, 300),
                routingBias: .dictationPreferred,
                consumedExplicitCommandPrefix: false,
                inlineExplicitCommandPrefix: true
            )
        )
    }

    func testForcedCommandHUDPreviewDoesNotAppearForPlainDictation() {
        XCTAssertFalse(
            SpeechManager.shouldPreviewForcedCommandHUD(
                typingContext: true,
                intent: .dictation("你好"),
                routingBias: .dictationPreferred,
                consumedExplicitCommandPrefix: false,
                inlineExplicitCommandPrefix: true
            )
        )
    }

    func testCommandHUDPreviewMessageUsesLocalizedPresetTitle() {
        XCTAssertEqual(
            SpeechManager.commandHUDPreviewMessage(
                for: .moveCursorHorizontally(-3),
                localeIdentifier: "zh-CN"
            ),
            "向左移动"
        )
    }

    func testCommandHUDPreviewMessageUsesFrontmostAppCommandPath() {
        let command = FrontmostAppCommand(
            processIdentifier: 42,
            bundleIdentifier: "com.google.Chrome",
            appName: "Chrome",
            menuPath: ["File"],
            title: "Close Tab",
            shortcut: HotkeyBinding(keyCode: 13, modifiers: UInt64(NSEvent.ModifierFlags.command.rawValue)),
            aliases: ["关闭标签"]
        )

        XCTAssertEqual(
            SpeechManager.commandHUDPreviewMessage(
                for: .frontmostAppCommand(command),
                localeIdentifier: "en-US"
            ),
            "File > Close Tab"
        )
    }

    func testCommandHUDPreviewMessageUsesTitleForLongMenuPath() {
        let command = FrontmostAppCommand(
            processIdentifier: 42,
            bundleIdentifier: "com.apple.Safari",
            appName: "Safari",
            menuPath: ["File", "Share", "Export"],
            title: "Save as PDF",
            shortcut: HotkeyBinding(keyCode: 1, modifiers: UInt64(NSEvent.ModifierFlags.command.rawValue)),
            aliases: ["保存为 PDF"]
        )

        XCTAssertEqual(
            SpeechManager.commandHUDPreviewMessage(
                for: .frontmostAppCommand(command),
                localeIdentifier: "en-US"
            ),
            "Save as PDF"
        )
    }

    func testLeadingExplicitCommandPrefixIgnoresAutoInsertedPunctuation() {
        XCTAssertTrue(
            SpeechManager.hasLeadingExplicitCommandPrefix(
                "，执行发送",
                localeIdentifier: "zh-CN",
                overrides: []
            )
        )
    }

    func testSubmitLikeFrontmostAppCommandRequiresReturnLikeShortcutAndSendAlias() {
        let sendCommand = FrontmostAppCommand(
            processIdentifier: 7,
            bundleIdentifier: "com.openai.codex",
            appName: "Codex",
            menuPath: ["Custom Rules"],
            title: "Send",
            shortcut: HotkeyBinding(
                keyCode: kVK_Return,
                modifiers: UInt64(NSEvent.ModifierFlags.command.rawValue)
            ),
            aliases: ["发送", "确认发送"]
        )

        XCTAssertTrue(SpeechManager.isSubmitLikeFrontmostAppCommand(sendCommand))
    }

    func testSubmitLikeFrontmostAppCommandRejectsNonSubmitShortcut() {
        let closeTab = FrontmostAppCommand(
            processIdentifier: 42,
            bundleIdentifier: "com.google.Chrome",
            appName: "Chrome",
            menuPath: ["File"],
            title: "Close Tab",
            shortcut: HotkeyBinding(
                keyCode: kVK_ANSI_W,
                modifiers: UInt64(NSEvent.ModifierFlags.command.rawValue)
            ),
            aliases: ["关闭标签"]
        )

        XCTAssertFalse(SpeechManager.isSubmitLikeFrontmostAppCommand(closeTab))
    }

    func testResidualDictationSuppressionTreatsPunctuationVariantsAsEquivalent() {
        XCTAssertTrue(
            SpeechManager.shouldSuppressResidualDictationAfterSubmit(
                previous: "你好，麻烦处理一下。",
                current: "你好麻烦处理一下"
            )
        )
    }

    func testResidualDictationSuppressionHandlesContainedRepeat() {
        XCTAssertTrue(
            SpeechManager.shouldSuppressResidualDictationAfterSubmit(
                previous: "请帮我把这个发给他们确认一下",
                current: "发给他们确认一下"
            )
        )
    }

    func testResidualDictationSuppressionDoesNotBlockNewSentence() {
        XCTAssertFalse(
            SpeechManager.shouldSuppressResidualDictationAfterSubmit(
                previous: "请帮我把这个发给他们确认一下",
                current: "然后提醒我明天继续跟进"
            )
        )
    }

    private func assertRoutingBias(
        _ actual: VoiceCommandRouter.RoutingBias,
        equals expected: VoiceCommandRouter.RoutingBias,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        switch (actual, expected) {
        case (.neutral, .neutral),
             (.dictationPreferred, .dictationPreferred),
             (.commandPreferred, .commandPreferred),
             (.forceDictation, .forceDictation),
             (.forceCommand, .forceCommand):
            return
        default:
            XCTFail("Expected bias \(expected) but got \(actual)", file: file, line: line)
        }
    }

    func testEngineRestartDiscardsTranscriptForMicrophoneSwitch() {
        XCTAssertTrue(SpeechManager.shouldDiscardTranscriptOnEngineRestart(reason: "input-device-selection"))
        XCTAssertTrue(SpeechManager.shouldDiscardTranscriptOnEngineRestart(reason: "default-input-device-changed"))
    }

    func testEngineRestartKeepsTranscriptForNonDeviceReasons() {
        XCTAssertFalse(SpeechManager.shouldDiscardTranscriptOnEngineRestart(reason: "continuous-health-check-engine-down"))
    }

    func testAutoModeDropsStaleTypingStateWithoutLiveEditableContext() {
        let resolved = SpeechManager.resolvedUtteranceTypingMode(
            recognitionControlMode: .auto,
            sessionTypingMode: true,
            liveTyping: false,
            canType: true,
            hasStreamedDictation: false
        )

        XCTAssertFalse(resolved)
    }

    func testAutoModeKeepsTypingStickyAfterStreamingStarts() {
        let resolved = SpeechManager.resolvedUtteranceTypingMode(
            recognitionControlMode: .auto,
            sessionTypingMode: true,
            liveTyping: false,
            canType: true,
            hasStreamedDictation: true
        )

        XCTAssertTrue(resolved)
    }

    func testAutoModeUsesLiveEditableContextImmediately() {
        let resolved = SpeechManager.resolvedUtteranceTypingMode(
            recognitionControlMode: .auto,
            sessionTypingMode: false,
            liveTyping: true,
            canType: true,
            hasStreamedDictation: false
        )

        XCTAssertTrue(resolved)
    }

    func testWakeTypingFallbackRestoresTypingDuringWakeFollowUp() {
        XCTAssertTrue(
            SpeechManager.shouldUseWakeTypingFallback(
                recognitionControlMode: .auto,
                dictationEnabled: true,
                liveTyping: false,
                pendingWakeFollowUp: true,
                sessionTargetAvailable: true,
                frontmostMatchesTarget: true,
                fallbackWindowActive: true,
                typingSuppressed: false
            )
        )
    }

    func testWakeTypingFallbackDoesNotOverrideWithoutPendingWakeFollowUp() {
        XCTAssertFalse(
            SpeechManager.shouldUseWakeTypingFallback(
                recognitionControlMode: .auto,
                dictationEnabled: true,
                liveTyping: false,
                pendingWakeFollowUp: false,
                sessionTargetAvailable: true,
                frontmostMatchesTarget: true,
                fallbackWindowActive: true,
                typingSuppressed: false
            )
        )
    }

    func testWakeTypingFallbackDoesNotOverrideSuppressedTypingContext() {
        XCTAssertFalse(
            SpeechManager.shouldUseWakeTypingFallback(
                recognitionControlMode: .auto,
                dictationEnabled: true,
                liveTyping: false,
                pendingWakeFollowUp: true,
                sessionTargetAvailable: true,
                frontmostMatchesTarget: true,
                fallbackWindowActive: true,
                typingSuppressed: true
            )
        )
    }

    func testWakeFollowUpEchoSuppressionDropsTranscriptMatchingPendingWakePhrase() {
        XCTAssertTrue(
            SpeechManager.shouldSuppressWakeFollowUpEcho(
                pendingWakePhrase: "你好",
                routedTranscript: "你好",
                hasStreamedDictation: false
            )
        )
    }

    func testWakeFollowUpEchoSuppressionKeepsTranscriptAfterStreamingStarts() {
        XCTAssertFalse(
            SpeechManager.shouldSuppressWakeFollowUpEcho(
                pendingWakePhrase: "你好",
                routedTranscript: "你好",
                hasStreamedDictation: true
            )
        )
    }

    func testImmediateWakeFollowUpDuplicateSuppressionIgnoresSentencePunctuation() {
        XCTAssertTrue(
            SpeechManager.shouldSuppressImmediateWakeFollowUpDuplicate(
                previousText: "你好。",
                currentText: "你好"
            )
        )
    }

    func testAutoModeReconciliationKeepsComputedTypingWhenTrue() {
        let reconciled = SpeechManager.reconcileTypingContextWithVisibleHUD(
            recognitionControlMode: .auto,
            computedTypingContext: true
        )

        XCTAssertTrue(reconciled)
    }

    func testAutoModeReconciliationKeepsComputedTypingWhenFalse() {
        let reconciled = SpeechManager.reconcileTypingContextWithVisibleHUD(
            recognitionControlMode: .auto,
            computedTypingContext: false
        )

        XCTAssertFalse(reconciled)
    }

    func testCommandModeReconciliationStillPassesThroughComputedTyping() {
        let reconciled = SpeechManager.reconcileTypingContextWithVisibleHUD(
            recognitionControlMode: .command,
            computedTypingContext: false
        )

        XCTAssertFalse(reconciled)
    }

    func testAutoHUDDictationModeForcesTypingContext() {
        let resolved = HUDManager.resolvedTypingContext(
            recognitionControlMode: .auto,
            inferredTypingContext: false,
            hudMode: .dictation,
            previousTypingContext: false
        )

        XCTAssertTrue(resolved)
    }

    func testAutoHUDProcessingKeepsPreviousTypingContext() {
        let resolved = HUDManager.resolvedTypingContext(
            recognitionControlMode: .auto,
            inferredTypingContext: false,
            hudMode: .processing,
            previousTypingContext: true
        )

        XCTAssertTrue(resolved)
    }

    func testAutoModeIgnoresAirPodsPostureBiasWithoutTypingContext() {
        let decision = SpeechManager.resolvedRoutingBias(
            recognitionControlMode: .auto,
            typingContext: false,
            dictationEnabled: true,
            commandEnabled: true,
            consumeExplicitCommandPrefix: false
        )

        assertRoutingBias(decision.bias, equals: .commandPreferred)
        XCTAssertFalse(decision.blockDictationWithoutInput)
    }

    func testAutoModeUsesTypingContextWithoutPostureBias() {
        let decision = SpeechManager.resolvedRoutingBias(
            recognitionControlMode: .auto,
            typingContext: true,
            dictationEnabled: true,
            commandEnabled: true,
            consumeExplicitCommandPrefix: false
        )

        assertRoutingBias(decision.bias, equals: .dictationPreferred)
        XCTAssertFalse(decision.blockDictationWithoutInput)
    }

    func testDictationModeStillBlocksWithoutInputContext() {
        let decision = SpeechManager.resolvedRoutingBias(
            recognitionControlMode: .dictation,
            typingContext: false,
            dictationEnabled: true,
            commandEnabled: true,
            consumeExplicitCommandPrefix: false
        )

        assertRoutingBias(decision.bias, equals: .forceCommand)
        XCTAssertTrue(decision.blockDictationWithoutInput)
    }

    func testStreamedDictationTargetIsTrustedWithoutLiveFocusWhenFrontmostMatches() {
        XCTAssertTrue(
            SpeechManager.shouldAcceptStreamedDictationTargetWithoutLiveFocus(
                sessionTypingMode: true,
                screenTypedCount: 3,
                streamedTextSnapshot: "",
                frontmostMatchesTarget: true
            )
        )
    }

    func testStreamedDictationTargetStillRequiresMatchingFrontmostTarget() {
        XCTAssertFalse(
            SpeechManager.shouldAcceptStreamedDictationTargetWithoutLiveFocus(
                sessionTypingMode: true,
                screenTypedCount: 3,
                streamedTextSnapshot: "",
                frontmostMatchesTarget: false
            )
        )
    }

    func testLockedWeirdTypingTargetIsTrustedWithoutLiveFocusWhenFrontmostMatches() {
        XCTAssertTrue(
            SpeechManager.shouldTrustLockedWeirdTypingTargetWithoutLiveFocus(
                sessionTypingMode: true,
                targetBundleID: "com.openai.codex",
                targetElementFingerprint: "AXWebArea|editor",
                verificationSnapshotAvailable: true,
                frontmostMatchesTarget: true
            )
        )
    }

    func testLockedWeirdTypingTargetStillRequiresWeirdBundleOrLockedEvidence() {
        XCTAssertFalse(
            SpeechManager.shouldTrustLockedWeirdTypingTargetWithoutLiveFocus(
                sessionTypingMode: true,
                targetBundleID: "com.apple.TextEdit",
                targetElementFingerprint: "AXTextArea|editor",
                verificationSnapshotAvailable: true,
                frontmostMatchesTarget: true
            )
        )

        XCTAssertFalse(
            SpeechManager.shouldTrustLockedWeirdTypingTargetWithoutLiveFocus(
                sessionTypingMode: true,
                targetBundleID: "com.openai.codex",
                targetElementFingerprint: nil,
                verificationSnapshotAvailable: false,
                frontmostMatchesTarget: true
            )
        )
    }
}

final class HUDExplicitTypingSuppressionTests: XCTestCase {
    func testCodexLikeAppsRequireExplicitClickReentry() {
        XCTAssertTrue(HUDManager.shouldHoldExplicitTypingSuppressionUntilClickReentry(bundleID: "com.openai.codex"))
        XCTAssertTrue(HUDManager.shouldHoldExplicitTypingSuppressionUntilClickReentry(bundleID: "com.antigravity.editor"))
    }

    func testNormalAppsDoNotHoldExplicitTypingSuppressionUntilClickReentry() {
        XCTAssertFalse(HUDManager.shouldHoldExplicitTypingSuppressionUntilClickReentry(bundleID: "com.google.Chrome"))
        XCTAssertFalse(HUDManager.shouldHoldExplicitTypingSuppressionUntilClickReentry(bundleID: "com.apple.TextEdit"))
        XCTAssertFalse(HUDManager.shouldHoldExplicitTypingSuppressionUntilClickReentry(bundleID: nil))
    }

    func testChangedFocusedInputAllowsSingleClickReentry() {
        XCTAssertTrue(
            HUDManager.shouldAllowExplicitTypingReentryAfterFocusChange(
                sourceFingerprint: "AXTextArea|-|-|-|-|Codex|1154x905|594x40",
                sourceRect: CGRect(x: 1154, y: 135, width: 594, height: 40),
                currentFingerprint: "AXTextArea|-|-|-|-|Codex|829x880|269x30",
                currentRect: CGRect(x: 829, y: 160, width: 269, height: 30),
                clickPoint: CGPoint(x: 941, y: 173),
                clickAge: 0.2
            )
        )
    }

    func testStaleFocusedInputDoesNotReleaseSuppression() {
        XCTAssertFalse(
            HUDManager.shouldAllowExplicitTypingReentryAfterFocusChange(
                sourceFingerprint: "AXTextArea|-|-|-|-|Codex|1154x905|594x40",
                sourceRect: CGRect(x: 1154, y: 135, width: 594, height: 40),
                currentFingerprint: "AXTextArea|-|-|-|-|Codex|1154x905|594x40",
                currentRect: CGRect(x: 1154, y: 135, width: 594, height: 40),
                clickPoint: CGPoint(x: 938, y: 271),
                clickAge: 0.2
            )
        )
    }
}
