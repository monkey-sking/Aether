import Foundation
import AppKit

final class TextInjector {
    private(set) var lastInjectedAt: Date?

    func paste(_ text: String) {
        AutomationOutputs.shared.pasteText(text)
        lastInjectedAt = Date()
    }

    func type(_ text: String, targetPID: pid_t? = nil) {
        // [Fix] Keystroke simulation via CGEvent(key: 0) is prone to failure on macOS. 
        // For the active window, fallback to a robust clipboard paste (Cmd+V) and restore clipboard.
        let isBackground = targetPID != nil && targetPID != NSWorkspace.shared.frontmostApplication?.processIdentifier
        
        if isBackground {
            AutomationOutputs.shared.typeText(text, targetPID: targetPID)
            lastInjectedAt = Date()
        } else {
            safePaste(text)
        }
    }

    private func safePaste(_ text: String) {
        let pb = NSPasteboard.general
        
        // Save current pasteboard items
        let oldItems = pb.pasteboardItems?.compactMap { item -> NSPasteboardItem in
            let newItem = NSPasteboardItem()
            for type in item.types {
                if let data = item.data(forType: type) {
                    newItem.setData(data, forType: type)
                }
            }
            return newItem
        }
        
        // Execute Cmd+V injection
        AutomationOutputs.shared.pasteText(text)
        lastInjectedAt = Date()
        
        // Restore pasteboard after a delay, allowing the OS to process the CGEvent
        if let oldItems = oldItems, !oldItems.isEmpty {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                pb.clearContents()
                pb.writeObjects(oldItems)
            }
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                pb.clearContents()
            }
        }
    }

    func undoPasteIfRecent(maxAgeSeconds: TimeInterval = 20) {
        guard let at = lastInjectedAt, Date().timeIntervalSince(at) <= maxAgeSeconds else { return }
        AutomationOutputs.shared.undo()
    }
}
