import Foundation
import AppKit

protocol TextInjecting: AnyObject {
    func type(_ text: String, targetPID: pid_t?)
    func deleteBackward(count: Int, targetPID: pid_t?)
}

final class TextInjector: TextInjecting {
    private struct PasteboardSnapshot {
        let items: [[NSPasteboard.PasteboardType: Data]]

        init?(pasteboard: NSPasteboard) {
            guard let pasteboardItems = pasteboard.pasteboardItems else { return nil }
            let captured = pasteboardItems.compactMap { item -> [NSPasteboard.PasteboardType: Data]? in
                let pairs = item.types.compactMap { type -> (NSPasteboard.PasteboardType, Data)? in
                    guard let data = item.data(forType: type) else { return nil }
                    return (type, data)
                }
                guard !pairs.isEmpty else { return nil }
                return Dictionary(uniqueKeysWithValues: pairs)
            }
            guard !captured.isEmpty else { return nil }
            self.items = captured
        }

        func restore(to pasteboard: NSPasteboard) {
            pasteboard.clearContents()
            for capturedItem in items {
                let item = NSPasteboardItem()
                for (type, data) in capturedItem {
                    item.setData(data, forType: type)
                }
                pasteboard.writeObjects([item])
            }
        }
    }

    private(set) var lastInjectedAt: Date?

    func paste(_ text: String) {
        let pasteboard = NSPasteboard.general
        let snapshot = PasteboardSnapshot(pasteboard: pasteboard)
        AutomationOutputs.shared.pasteText(text)
        lastInjectedAt = Date()
        guard let snapshot else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            snapshot.restore(to: pasteboard)
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
