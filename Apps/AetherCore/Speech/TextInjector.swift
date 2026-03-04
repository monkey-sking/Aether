import Foundation

final class TextInjector {
    private(set) var lastInjectedAt: Date?

    func paste(_ text: String) {
        AutomationOutputs.shared.pasteText(text)
        lastInjectedAt = Date()
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
