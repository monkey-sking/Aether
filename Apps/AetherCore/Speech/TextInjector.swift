import Foundation
import AppKit

protocol TextInjecting: AnyObject {
    func type(_ text: String, targetPID: pid_t?)
    func deleteBackward(count: Int, targetPID: pid_t?)
}

final class TextInjector: TextInjecting {
    private(set) var lastInjectedAt: Date?

    func paste(_ text: String) {
        let pasteboard = NSPasteboard.general
        let previousItems = pasteboard.pasteboardItems
        AutomationOutputs.shared.pasteText(text)
        lastInjectedAt = Date()
        guard let previousItems else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            pasteboard.clearContents()
            pasteboard.writeObjects(previousItems)
        }
    }

    func type(_ text: String, targetPID: pid_t? = nil) {
        // Use native CGEvent keystroke simulation (Zero-Clipboard)
        AutomationOutputs.shared.typeText(text, targetPID: targetPID)
        lastInjectedAt = Date()
    }

    func deleteBackward(count: Int, targetPID: pid_t? = nil) {
        AutomationOutputs.shared.backspace(count: count, targetPID: targetPID)
    }

    func undoPasteIfRecent(maxAgeSeconds: TimeInterval = 20) {
        guard let at = lastInjectedAt, Date().timeIntervalSince(at) <= maxAgeSeconds else { return }
        AutomationOutputs.shared.undo()
    }
}
