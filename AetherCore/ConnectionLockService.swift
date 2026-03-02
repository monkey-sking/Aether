import AVFAudio
import os.log

/// Prevents AirPods from automatically switching to other devices
/// by claiming audio routing priority via `AVAudioRoutingArbiter`.
@MainActor
final class ConnectionLockService: ObservableObject {
    static let shared = ConnectionLockService()

    @Published private(set) var isLocked: Bool = false
    @Published private(set) var isLockRequestInFlight: Bool = false

    private let log = OSLog(subsystem: "com.7fei.Aether", category: "ConnectionLock")

    private init() {}

    func lock() {
        guard !isLocked, !isLockRequestInFlight else { return }
        isLockRequestInFlight = true
        AVAudioRoutingArbiter.shared.begin(category: .playAndRecordVoice) { [weak self] deviceChanged, error in
            DispatchQueue.main.async {
                guard let self else { return }
                self.isLockRequestInFlight = false
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

    func unlock() {
        guard isLocked || isLockRequestInFlight else { return }
        AVAudioRoutingArbiter.shared.leave()
        isLockRequestInFlight = false
        isLocked = false
        os_log("ConnectionLock: Unlocked", log: log, type: .info)
    }

    func toggle() {
        isLocked ? unlock() : lock()
    }
}
