import Foundation
import AppKit
import InputMethodKit

@objc(AetherInputController)
final class AetherInputController: IMKInputController {
    private static let logQueue = DispatchQueue(label: "com.sevenfei.aether.ime.log")
    private static let verbose = ProcessInfo.processInfo.environment["AETHER_IME_VERBOSE_LOG"] == "1"
    private static var lastLogAt: Date = .distantPast
    private var caretPollTimer: Timer?
    private var consecutiveMisses: Int = 0

    override func recognizedEvents(_ sender: Any!) -> Int {
        Int(NSEvent.EventTypeMask.keyDown.rawValue)
    }

    override func activateServer(_ sender: Any!) {
        super.activateServer(sender)
        Self.log("⚠️ [IME TX] activateServer axTrusted=\(AXIsProcessTrusted())", force: true)
        publishCaretIfPossible(client: sender)
        startCaretPolling()
    }

    override func deactivateServer(_ sender: Any!) {
        super.deactivateServer(sender)
        Self.log("⚠️ [IME TX] deactivateServer", force: true)
        stopCaretPolling()
    }

    override func handle(_ event: NSEvent!, client sender: Any!) -> Bool {
        let consumed = super.handle(event, client: sender)
        Self.log("⚠️ [IME TX] handle keyCode=\(event?.keyCode ?? 0)")
        publishCaretIfPossible(client: sender)
        return consumed
    }

    override func inputText(_ string: String!, client sender: Any!) -> Bool {
        let consumed = super.inputText(string, client: sender)
        Self.log("⚠️ [IME TX] inputText len=\(string?.count ?? 0)")
        publishCaretIfPossible(client: sender)
        return consumed
    }

    private func publishCaretIfPossible(client: Any?) {
        let caretRectInScreen: CGRect
        if let textClient = resolveTextClient(from: client) {
            consecutiveMisses = 0
            let range = textClient.selectedRange()
            let caretLocation = max(0, range.location)
            let caretRange = NSRange(location: caretLocation, length: 0)
            let r = textClient.firstRect(forCharacterRange: caretRange, actualRange: nil)
            guard r.isNull == false, r.isInfinite == false else {
                Self.log("⚠️ [IME TX] invalid firstRect")
                return
            }
            caretRectInScreen = r
        } else if let r = fallbackCaretRectFromAX() {
            consecutiveMisses = 0
            caretRectInScreen = r
            Self.log("⚠️ [IME TX] fallback AX caret")
        } else {
            consecutiveMisses += 1
            if consecutiveMisses % 20 == 1 {
                Self.log("⚠️ [IME TX] no client/caret source (misses=\(consecutiveMisses))", force: true)
            }
            // Back off aggressively when caret source is unavailable to avoid CPU + log spam.
            if consecutiveMisses >= 60 {
                stopCaretPolling()
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                    self?.consecutiveMisses = 0
                    self?.startCaretPolling()
                }
            }
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
        if let obj = self.perform(NSSelectorFromString("client"))?.takeUnretainedValue(),
           let tc = obj as? NSTextInputClient {
            return tc
        }
        return nil
    }

    private func startCaretPolling() {
        guard caretPollTimer == nil else { return }
        // Keep polling frequency low by default to avoid CPU spikes.
        caretPollTimer = Timer.scheduledTimer(withTimeInterval: 0.20, repeats: true) { [weak self] _ in
            self?.publishCaretIfPossible(client: nil)
        }
    }

    private func stopCaretPolling() {
        caretPollTimer?.invalidate()
        caretPollTimer = nil
    }

    private func fallbackCaretRectFromAX() -> CGRect? {
        let systemWide = AXUIElementCreateSystemWide()
        var focusedRef: CFTypeRef?
        let focusStatus = AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &focusedRef)
        guard focusStatus == .success,
              let element = focusedRef
        else {
            Self.log("⚠️ [IME TX AX] focusedElement status=\(focusStatus.rawValue)")
            return nil
        }
        var selectedRangeRef: CFTypeRef?
        let rangeStatus = AXUIElementCopyAttributeValue(element as! AXUIElement, kAXSelectedTextRangeAttribute as CFString, &selectedRangeRef)
        guard rangeStatus == .success,
              let selectedRangeRef
        else {
            Self.log("⚠️ [IME TX AX] selectedRange status=\(rangeStatus.rawValue)")
            return nil
        }
        var boundsRef: CFTypeRef?
        let boundsStatus = AXUIElementCopyParameterizedAttributeValue(
            element as! AXUIElement,
            kAXBoundsForRangeParameterizedAttribute as CFString,
            selectedRangeRef,
            &boundsRef
        )
        guard boundsStatus == .success,
        let boundsRef
        else {
            Self.log("⚠️ [IME TX AX] boundsForRange status=\(boundsStatus.rawValue)")
            return nil
        }
        var raw = CGRect.zero
        guard AXValueGetValue(boundsRef as! AXValue, .cgRect, &raw) else {
            Self.log("⚠️ [IME TX AX] AXValueGetValue failed")
            return nil
        }
        if raw.width <= 1 || raw.height <= 1 {
            Self.log("⚠️ [IME TX AX] raw rect too small \(raw.debugDescription)")
            return nil
        }
        guard let rect = appKitRectFromAX(raw) else {
            Self.log("⚠️ [IME TX AX] no screen")
            return nil
        }
        return rect
    }

    private func appKitRectFromAX(_ axRect: CGRect) -> CGRect? {
        let desktopMaxY = NSScreen.screens.map(\.frame.maxY).max() ?? 0
        guard desktopMaxY > 0 else { return nil }
        return CGRect(
            x: axRect.origin.x,
            y: desktopMaxY - axRect.origin.y - axRect.size.height,
            width: axRect.size.width,
            height: axRect.size.height
        )
    }

    private static func log(_ message: String, force: Bool = false) {
        if !force && !verbose { return }
        logQueue.async {
            let now = Date()
            if !force && now.timeIntervalSince(lastLogAt) < 0.25 {
                return
            }
            lastLogAt = now
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
