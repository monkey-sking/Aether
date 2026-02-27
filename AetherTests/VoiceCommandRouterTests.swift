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
        XCTAssertEqual(router.route(transcript: "打开悬停"), .setDwell(true))
        XCTAssertEqual(router.route(transcript: "关闭悬停"), .setDwell(false))
    }
    
    func testScrollingAndDragging() {
        XCTAssertEqual(router.route(transcript: "向上"), .scroll(0, -300))
        XCTAssertEqual(router.route(transcript: "向下"), .scroll(0, 300))
        XCTAssertEqual(router.route(transcript: "到底"), .scrollToWeb("bottom"))
        XCTAssertEqual(router.route(transcript: "到顶"), .scrollToWeb("top"))
        XCTAssertEqual(router.route(transcript: "拖"), .dragStart)
        XCTAssertEqual(router.route(transcript: "放"), .dragEnd)
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
        XCTAssertEqual(router.route(transcript: "写一段代码"), .dictation("段代码"))
    }
    
    func testTypingModeBehavior() {
        // In typing mode, normal words should go to dictation unless forced command
        XCTAssertEqual(router.route(transcript: "点击", isTypingMode: true), .dictation("点击"))
        
        // "指令 点击" in typing mode should bypass dictation and trigger the command
        XCTAssertEqual(router.route(transcript: "指令点击", isTypingMode: true), .clickLeft)
        XCTAssertEqual(router.route(transcript: "command right click", isTypingMode: true), .clickRight)
    }
}
