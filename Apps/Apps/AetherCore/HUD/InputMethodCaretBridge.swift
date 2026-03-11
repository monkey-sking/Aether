import Foundation
import AppKit

struct InputMethodCaretUpdate {
    let caretRect: CGRect
    let contextRect: CGRect?
    let bundleID: String?
    let timestamp: Date
}

final class InputMethodCaretBridge {
    static let notificationName = Notification.Name("com.7fei.aether.inputmethod.caret")

    var onCaretUpdate: ((InputMethodCaretUpdate) -> Void)?

    private var observer: NSObjectProtocol?

    func start() {
        guard observer == nil else { return }
        observer = DistributedNotificationCenter.default().addObserver(
            forName: Self.notificationName,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self else { return }
            guard let update = self.decode(notification.userInfo) else { return }
            self.onCaretUpdate?(update)
        }
    }

    func stop() {
        guard let observer else { return }
        DistributedNotificationCenter.default().removeObserver(observer)
        self.observer = nil
    }

    private func decode(_ userInfo: [AnyHashable: Any]?) -> InputMethodCaretUpdate? {
        guard let userInfo else { return nil }
        guard
            let caretX = toCGFloat(userInfo["caretX"]),
            let caretY = toCGFloat(userInfo["caretY"]),
            let caretW = toCGFloat(userInfo["caretW"]),
            let caretH = toCGFloat(userInfo["caretH"])
        else {
            return nil
        }

        let caretRect = CGRect(x: caretX, y: caretY, width: caretW, height: caretH)

        var contextRect: CGRect?
        if
            let contextX = toCGFloat(userInfo["contextX"]),
            let contextY = toCGFloat(userInfo["contextY"]),
            let contextW = toCGFloat(userInfo["contextW"]),
            let contextH = toCGFloat(userInfo["contextH"])
        {
            contextRect = CGRect(x: contextX, y: contextY, width: contextW, height: contextH)
        }

        let bundleID = userInfo["bundleID"] as? String
        let timestamp = toDouble(userInfo["timestamp"]).map { Date(timeIntervalSince1970: $0) } ?? Date()

        return InputMethodCaretUpdate(
            caretRect: caretRect,
            contextRect: contextRect,
            bundleID: bundleID,
            timestamp: timestamp
        )
    }

    private func toCGFloat(_ value: Any?) -> CGFloat? {
        if let n = value as? NSNumber { return CGFloat(truncating: n) }
        if let d = value as? Double { return CGFloat(d) }
        if let s = value as? String, let d = Double(s) { return CGFloat(d) }
        return nil
    }

    private func toDouble(_ value: Any?) -> Double? {
        if let n = value as? NSNumber { return n.doubleValue }
        if let d = value as? Double { return d }
        if let s = value as? String { return Double(s) }
        return nil
    }
}
