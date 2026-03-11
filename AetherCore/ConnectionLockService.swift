import Combine
import os.log

/// Legacy placeholder kept for compatibility after removing headset connection lock as a product feature.
@MainActor
final class ConnectionLockService: ObservableObject {
    static let shared = ConnectionLockService()

    @Published private(set) var isLocked: Bool = false
    @Published private(set) var isLockRequestInFlight: Bool = false

    private let log = OSLog(subsystem: "com.7fei.Aether", category: "ConnectionLock")

    private init() {}

    func lock() {
        os_log("ConnectionLock: ignored lock request (feature removed)", log: log, type: .info)
    }

    func unlock() {
        os_log("ConnectionLock: ignored unlock request (feature removed)", log: log, type: .info)
    }

    func toggle() {
        os_log("ConnectionLock: ignored toggle request (feature removed)", log: log, type: .info)
    }

    func setTrackingLockEnabled(_ enabled: Bool) {
        os_log("ConnectionLock: ignored tracking request enabled=%{public}@", log: log, type: .debug, String(enabled))
    }
}
