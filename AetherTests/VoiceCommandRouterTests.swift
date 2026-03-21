import XCTest
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
        XCTAssertEqual(router.route(transcript: "点击"), .clickLeft)
        XCTAssertEqual(router.route(transcript: "右键"), .clickRight)
        XCTAssertEqual(router.route(transcript: "双击"), .doubleClick)
        XCTAssertEqual(router.route(transcript: "撤销"), .undo)
        XCTAssertEqual(router.route(transcript: "粘贴"), .paste)
        XCTAssertEqual(router.route(transcript: "停止"), .stopPointer)
        XCTAssertEqual(router.route(transcript: "开始"), .startPointer)
        XCTAssertEqual(router.route(transcript: "居中"), .recenter)
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
    
    func testScrollingAndDragging() {
        XCTAssertEqual(router.route(transcript: "向上"), .scroll(0, -300))
        XCTAssertEqual(router.route(transcript: "向下"), .scroll(0, 300))
        XCTAssertEqual(router.route(transcript: "向下滚动"), .scroll(0, 300))
        XCTAssertEqual(router.route(transcript: "到底"), .scrollToWeb("bottom"))
        XCTAssertEqual(router.route(transcript: "到顶"), .scrollToWeb("top"))
        XCTAssertEqual(router.route(transcript: "拖"), .dragStart)
        XCTAssertEqual(router.route(transcript: "放"), .dragEnd)
    }

    func testShortcutPanelAliases() {
        XCTAssertEqual(router.route(transcript: "显示面板"), .showShortcutPanel)
        XCTAssertEqual(router.route(transcript: "显示快捷键面板"), .showShortcutPanel)
        XCTAssertEqual(router.route(transcript: "关闭面板"), .hideShortcutPanel)
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
        XCTAssertEqual(router.route(transcript: "邮件"), .clickRight)
        XCTAssertEqual(router.route(transcript: "有件"), .clickRight)

        // "单机" (Dan Ji -> Dian Ji roughly falling into .clickLeft using pinyin matching)
        XCTAssertEqual(router.route(transcript: "单机"), .clickLeft)
        // "双机" (Shuang Ji)
        XCTAssertEqual(router.route(transcript: "双机"), .doubleClick)
    }
    
    func testDictationParsing() {
        // Basic dictation fallback
        XCTAssertEqual(router.route(transcript: "今天天气不错"), .dictation("今天天气不错"))

        // Force dictation keyword "输入"
        XCTAssertEqual(router.route(transcript: "输入你好"), .dictation("你好"))
        XCTAssertEqual(router.route(transcript: "写一段代码"), .dictation("一段代码"))
    }
    
    func testTypingModeBehavior() {
        // In typing mode, normal words should go to dictation unless explicitly forcing command
        XCTAssertEqual(
            router.route(transcript: "点击", bias: .dictationPreferred),
            .dictation("点击")
        )

        XCTAssertEqual(
            router.route(transcript: "向下滚动", bias: .dictationPreferred),
            .scroll(0, 300)
        )
        XCTAssertEqual(
            router.route(transcript: "显示面板", bias: .dictationPreferred),
            .showShortcutPanel
        )

        // "指令点击" in typing mode should bypass dictation and trigger command
        XCTAssertEqual(
            router.route(transcript: "指令点击", bias: .dictationPreferred),
            .clickLeft
        )
        XCTAssertEqual(
            router.route(transcript: "command right click", bias: .dictationPreferred),
            .clickRight
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
            hasStreamedDictation: false,
            isUtteranceActive: false
        )

        XCTAssertFalse(resolved)
    }

    func testAutoModeKeepsTypingStickyAfterStreamingStarts() {
        let resolved = SpeechManager.resolvedUtteranceTypingMode(
            recognitionControlMode: .auto,
            sessionTypingMode: true,
            liveTyping: false,
            canType: true,
            hasStreamedDictation: true,
            isUtteranceActive: false
        )

        XCTAssertTrue(resolved)
    }

    func testAutoModeUsesLiveEditableContextImmediately() {
        let resolved = SpeechManager.resolvedUtteranceTypingMode(
            recognitionControlMode: .auto,
            sessionTypingMode: false,
            liveTyping: true,
            canType: true,
            hasStreamedDictation: false,
            isUtteranceActive: false
        )

        XCTAssertTrue(resolved)
    }

    func testAutoModeHUDControlStateOverridesStaleTypingBeforeStreaming() {
        let reconciled = SpeechManager.reconcileTypingContextWithVisibleHUD(
            recognitionControlMode: .auto,
            computedTypingContext: true,
            hasStreamedDictation: false,
            hudRecognitionControlMode: .auto,
            hudTypingContext: false,
            isUtteranceActive: false
        )

        XCTAssertFalse(reconciled)
    }

    func testAutoModeHUDTypingStateKeepsTypingWhenVisible() {
        let reconciled = SpeechManager.reconcileTypingContextWithVisibleHUD(
            recognitionControlMode: .auto,
            computedTypingContext: true,
            hasStreamedDictation: false,
            hudRecognitionControlMode: .auto,
            hudTypingContext: true,
            isUtteranceActive: false
        )

        XCTAssertTrue(reconciled)
    }

    func testAutoModeHUDControlStateStillWinsOverStreamingFlag() {
        let reconciled = SpeechManager.reconcileTypingContextWithVisibleHUD(
            recognitionControlMode: .auto,
            computedTypingContext: true,
            hasStreamedDictation: true,
            hudRecognitionControlMode: .auto,
            hudTypingContext: false,
            isUtteranceActive: false
        )

        XCTAssertFalse(reconciled)
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
}
