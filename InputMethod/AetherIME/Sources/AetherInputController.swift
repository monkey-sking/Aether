import Foundation
import AppKit
import InputMethodKit

@objc(AetherInputController)
final class AetherInputController: IMKInputController {
    private static let logQueue = DispatchQueue(label: "com.sevenfei.aether.ime.log")

    override func recognizedEvents(_ sender: Any!) -> Int {
        Int(NSEvent.EventTypeMask.keyDown.rawValue)
    }

    override func activateServer(_ sender: Any!) {
        super.activateServer(sender)
        Self.log("⚠️ [IME TX] activateServer")
        publishCaretIfPossible(client: sender)
    }

    override func handle(_ event: NSEvent!, client sender: Any!) -> Bool {
        let consumed = super.handle(event, client: sender)
        Self.log("⚠️ [IME TX] handle type=\(String(describing: type(of: sender as Any))) keyCode=\(event?.keyCode ?? 0)")
        publishCaretIfPossible(client: sender)
        return consumed
    }

    private func publishCaretIfPossible(client: Any?) {
        guard let textClient = resolveTextClient(from: client) else {
            Self.log("⚠️ [IME TX] no NSTextInputClient, senderType=\(String(describing: type(of: client as Any)))")
            return
        }

        let range = textClient.selectedRange()
        let caretLocation = max(0, range.location)
        let caretRange = NSRange(location: caretLocation, length: 0)
        let caretRectInScreen = textClient.firstRect(forCharacterRange: caretRange, actualRange: nil)
        guard caretRectInScreen.isNull == false, caretRectInScreen.isInfinite == false else {
            Self.log("⚠️ [IME TX] invalid firstRect")
            return
        }

        let frontBundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        let userInfo: [String: Any] = [
            "caretX": caretRectInScreen.origin.x,
            "caretY": caretRectInScreen.origin.y,
            "caretW": max(1.0, caretRectInScreen.size.width),
            "caretH": max(1.0, caretRectInScreen.size.height),
            "bundleID": frontBundleID ?? "",
            "timestamp": Date().timeIntervalSince1970
        ]

        DistributedNotificationCenter.default().postNotificationName(
            Notification.Name("com.7fei.aether.inputmethod.caret"),
            object: nil,
            userInfo: userInfo,
            deliverImmediately: true
        )
        Self.log("⚠️ [IME TX] post caret=(\(Int(caretRectInScreen.origin.x)),\(Int(caretRectInScreen.origin.y))) size=(\(Int(caretRectInScreen.size.width))x\(Int(caretRectInScreen.size.height))) bundle=\(frontBundleID ?? "nil")")
    }

    private func resolveTextClient(from candidate: Any?) -> NSTextInputClient? {
        if let tc = candidate as? NSTextInputClient {
            return tc
        }
        return nil
    }

    private static func log(_ message: String) {
        logQueue.async {
            let now = Date()
            let url = URL(fileURLWithPath: "/tmp/AetherIME_Debug.log")
            let formatter = ISO8601DateFormatter()
            let line = "\(formatter.string(from: now)) DEBUG: \(message)\n"
            if FileManager.default.fileExists(atPath: url.path),
               let handle = try? FileHandle(forWritingTo: url) {
                handle.seekToEndOfFile()
                if let data = line.data(using: .utf8) { handle.write(data) }
                try? handle.close()
            } else {
                try? line.write(to: url, atomically: true, encoding: .utf8)
            }
        }
    }
}
