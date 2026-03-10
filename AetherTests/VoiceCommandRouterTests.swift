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

    func testAutoModeHUDControlStateOverridesStaleTypingBeforeStreaming() {
        let reconciled = SpeechManager.reconcileTypingContextWithVisibleHUD(
            recognitionControlMode: .auto,
            computedTypingContext: true,
            hasStreamedDictation: false,
            hudRecognitionControlMode: .auto,
            hudTypingContext: false
        )

        XCTAssertFalse(reconciled)
    }

    func testAutoModeHUDTypingStateKeepsTypingWhenVisible() {
        let reconciled = SpeechManager.reconcileTypingContextWithVisibleHUD(
            recognitionControlMode: .auto,
            computedTypingContext: true,
            hasStreamedDictation: false,
            hudRecognitionControlMode: .auto,
            hudTypingContext: true
        )

        XCTAssertTrue(reconciled)
    }

    func testAutoModeHUDControlDoesNotCancelAfterStreamingStarts() {
        let reconciled = SpeechManager.reconcileTypingContextWithVisibleHUD(
            recognitionControlMode: .auto,
            computedTypingContext: true,
            hasStreamedDictation: true,
            hudRecognitionControlMode: .auto,
            hudTypingContext: false
        )

        XCTAssertTrue(reconciled)
    }
}
