import AVFAudio
import os.log

/// Prevents AirPods from automatically switching to other devices
/// by claiming audio routing priority via `AVAudioRoutingArbiter`.
@MainActor
final class ConnectionLockService: ObservableObject {
    private enum LockSource: Hashable {
        case manual
        case tracking
    }

    static let shared = ConnectionLockService()

    @Published private(set) var isLocked: Bool = false
    @Published private(set) var isLockRequestInFlight: Bool = false

    private let log = OSLog(subsystem: "com.7fei.Aether", category: "ConnectionLock")
    private var activeSources: Set<LockSource> = []

    private init() {}

    func lock() {
        requestLock(for: .manual)
    }

    func unlock() {
        releaseLock(for: .manual)
    }

    func toggle() {
        if activeSources.contains(.manual) {
            unlock()
        } else {
            lock()
        }
    }

    func setTrackingLockEnabled(_ enabled: Bool) {
        if enabled {
            requestLock(for: .tracking)
        } else {
            releaseLock(for: .tracking)
        }
    }

    private func requestLock(for source: LockSource) {
        let inserted = activeSources.insert(source).inserted
        guard inserted else { return }
        os_log("ConnectionLock: Source requested %{public}@", log: log, type: .info, "\(source)")
        startLockRequestIfNeeded()
    }

    private func releaseLock(for source: LockSource) {
        guard activeSources.remove(source) != nil else { return }
        os_log("ConnectionLock: Source released %{public}@", log: log, type: .info, "\(source)")

        guard activeSources.isEmpty else { return }

        AVAudioRoutingArbiter.shared.leave()
        isLockRequestInFlight = false
        isLocked = false
        os_log("ConnectionLock: Unlocked", log: log, type: .info)
    }

    private func startLockRequestIfNeeded() {
        guard !activeSources.isEmpty, !isLocked, !isLockRequestInFlight else { return }

        isLockRequestInFlight = true
        AVAudioRoutingArbiter.shared.begin(category: .playAndRecordVoice) { [weak self] deviceChanged, error in
            DispatchQueue.main.async {
                guard let self else { return }
                self.isLockRequestInFlight = false

                guard !self.activeSources.isEmpty else {
                    self.isLocked = false
                    AVAudioRoutingArbiter.shared.leave()
                    return
                }

                if let error {
                    os_log("ConnectionLock: begin failed – %{public}@", type: .error, error.localizedDescription)
                    self.isLocked = false
                    return
                }

                os_log("ConnectionLock: Locked (deviceChanged=%d)", type: .info, deviceChanged)
                self.isLocked = true
            }
        }
        os_log("ConnectionLock: Lock requested", log: log, type: .info)
    }
}
