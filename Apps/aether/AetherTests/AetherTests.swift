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
