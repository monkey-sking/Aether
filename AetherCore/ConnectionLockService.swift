import AVFAudio
import os.log

/// Prevents AirPods from automatically switching to other devices
/// by claiming audio routing priority via `AVAudioRoutingArbiter`.
@MainActor
final class ConnectionLockService: ObservableObject {
    static let shared = ConnectionLockService()

    @Published private(set) var isLocked: Bool = false

    private let log = OSLog(subsystem: "com.7fei.Aether", category: "ConnectionLock")

    private init() {}

    func lock() {
        guard !isLocked else { return }
        AVAudioRoutingArbiter.shared.begin(category: .playAndRecordVoice) { [weak self] deviceChanged, error in
            DispatchQueue.main.async {
                if let error {
                    os_log("ConnectionLock: begin failed – %{public}@", type: .error, error.localizedDescription)
                    return
                }
                os_log("ConnectionLock: Locked (deviceChanged=%d)", type: .info, deviceChanged)
            }
        }
        isLocked = true
        os_log("ConnectionLock: Lock requested", log: log, type: .info)
    }

    func unlock() {
        guard isLocked else { return }
        AVAudioRoutingArbiter.shared.leave()
        isLocked = false
        os_log("ConnectionLock: Unlocked", log: log, type: .info)
    }

    func toggle() {
        isLocked ? unlock() : lock()
    }
}
