import Foundation
import IOKit

// Keep Swift definitions in sync with `Shared/AetherShared.h`.
private let kAetherUserClientType_Main: UInt32 = 0
private let kAetherCommand_PostHIDEvent: UInt32 = 0

private struct AetherHIDEvent {
    var dx: Int32
    var dy: Int32
    var buttons: UInt32
}

final class DriverClient {
    enum Error: Swift.Error, Equatable {
        case serviceNotFound
        case serviceOpenFailed(kern_return_t)
        case callFailed(kern_return_t)
    }

    private let bundleID: String
    private var connect: io_connect_t = 0
    private var lastConnectAttemptAt: TimeInterval = 0

    init(bundleID: String = kAetherDriverBundleID) {
        self.bundleID = bundleID
    }

    deinit {
        disconnect()
    }

    func disconnect() {
        if connect != 0 {
            IOServiceClose(connect)
            connect = 0
        }
    }

    var isConnected: Bool { connect != 0 }

    func connectIfNeeded(throttleSeconds: TimeInterval = 2.0) -> Result<Void, Error> {
        if connect != 0 { return .success(()) }

        let now = Date().timeIntervalSince1970
        if now - lastConnectAttemptAt < throttleSeconds {
            return .failure(.serviceNotFound)
        }
        lastConnectAttemptAt = now

        guard let matching = IOServiceMatching("IOUserServer") else {
            return .failure(.serviceNotFound)
        }
        // Match the DriverKit user server by IOUserServerName (usually the extension bundle identifier).
        (matching as NSMutableDictionary)["IOUserServerName"] = bundleID

        var iterator: io_iterator_t = 0
        let kr = IOServiceGetMatchingServices(kIOMasterPortDefault, matching, &iterator)
        guard kr == KERN_SUCCESS else {
            return .failure(.serviceNotFound)
        }
        defer { IOObjectRelease(iterator) }

        let service = IOIteratorNext(iterator)
        guard service != 0 else {
            return .failure(.serviceNotFound)
        }
        defer { IOObjectRelease(service) }

        var opened: io_connect_t = 0
        let openKr = IOServiceOpen(service, mach_task_self_, UInt32(kAetherUserClientType_Main), &opened)
        guard openKr == KERN_SUCCESS else {
            return .failure(.serviceOpenFailed(openKr))
        }

        connect = opened
        return .success(())
    }

    func postHIDEvent(dx: Int32, dy: Int32, buttons: UInt32) -> Result<Void, Error> {
        let connected = connectIfNeeded()
        guard case .success = connected else { return connected.map { _ in () } }

        var event = AetherHIDEvent(dx: dx, dy: dy, buttons: buttons)
        var outSize: Int = 0
        let kr = withUnsafePointer(to: &event) { ptr in
            IOConnectCallStructMethod(
                connect,
                UInt32(kAetherCommand_PostHIDEvent),
                ptr,
                MemoryLayout<AetherHIDEvent>.size,
                nil,
                &outSize
            )
        }

        guard kr == KERN_SUCCESS else {
            // If the connection becomes invalid, force reconnect next time.
            disconnect()
            return .failure(.callFailed(kr))
        }

        return .success(())
    }
}

final class DriverAutomationOutput {
    private let client = DriverClient()
    private var lastPoint: CGPoint?

    func resetRelativeOrigin(to point: CGPoint) {
        lastPoint = point
    }

    func moveCursor(to point: CGPoint) -> Bool {
        guard let lastPoint else {
            self.lastPoint = point
            return false
        }

        let dx = point.x - lastPoint.x
        let dy = point.y - lastPoint.y
        self.lastPoint = point

        // Ignore tiny jitter.
        if abs(dx) < 0.25, abs(dy) < 0.25 {
            // Only claim we handled it (blocking fallback) if we are actually connected.
            return client.isConnected
        }

        let r = client.postHIDEvent(dx: Int32(dx.rounded()), dy: Int32(dy.rounded()), buttons: 0)
        if case .success = r {
            return true
        }
        return false
    }

    func mouseClick(clickCount: Int) -> Bool {
        // Left button state bit 0.
        let down = client.postHIDEvent(dx: 0, dy: 0, buttons: 1)
        guard case .success = down else { return false }

        let up = client.postHIDEvent(dx: 0, dy: 0, buttons: 0)
        guard case .success = up else { return false }

        if clickCount >= 2 {
            let down2 = client.postHIDEvent(dx: 0, dy: 0, buttons: 1)
            guard case .success = down2 else { return false }
            let up2 = client.postHIDEvent(dx: 0, dy: 0, buttons: 0)
            guard case .success = up2 else { return false }
        }

        return true
    }

    func pasteFromClipboard() {
        // Not implemented for Driver yet
    }
}
