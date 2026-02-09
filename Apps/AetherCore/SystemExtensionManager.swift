import Foundation
import SystemExtensions
import os.log

enum SystemExtensionActivationState: Equatable {
    case idle
    case requestingActivation
    case requestingDeactivation
    case needsUserApproval
    case activated
    case pending
    case failed(String)
}

class SystemExtensionManager: NSObject, OSSystemExtensionRequestDelegate, ObservableObject {
    static let shared = SystemExtensionManager()
    
    @Published private(set) var state: SystemExtensionActivationState = .idle
    
    private let log = OSLog(subsystem: "com.7fei.Aether", category: "ExtensionManager")

    var statusText: String {
        switch state {
        case .idle: return "Idle"
        case .requestingActivation: return "Requesting activation..."
        case .requestingDeactivation: return "Requesting deactivation..."
        case .needsUserApproval: return "Needs User Approval"
        case .activated: return "Activated"
        case .pending: return "Pending"
        case .failed(let message): return "Failed: \(message)"
        }
    }
    
    func activate(identifier: String) {
        // If the host app isn't signed with this entitlement, activation will always fail.
        if !EntitlementChecker.hasEntitlement("com.apple.developer.system-extension.install") {
            state = .failed("Missing entitlement com.apple.developer.system-extension.install")
            os_log("Activation blocked: missing system-extension.install entitlement", log: log, type: .error)
            return
        }

        let request = OSSystemExtensionRequest.activationRequest(forExtensionWithIdentifier: identifier, queue: .main)
        request.delegate = self
        OSSystemExtensionManager.shared.submitRequest(request)
        state = .requestingActivation
        os_log("Submitted activation request for %{public}@", log: log, identifier)
    }
    
    func deactivate(identifier: String) {
        let request = OSSystemExtensionRequest.deactivationRequest(forExtensionWithIdentifier: identifier, queue: .main)
        request.delegate = self
        OSSystemExtensionManager.shared.submitRequest(request)
        state = .requestingDeactivation
    }
    
    // MARK: - OSSystemExtensionRequestDelegate
    
    func request(_ request: OSSystemExtensionRequest, actionForReplacingExtension existing: OSSystemExtensionProperties, withExtension extension: OSSystemExtensionProperties) -> OSSystemExtensionRequest.ReplacementAction {
        os_log("Replacing existing extension", log: log)
        return .replace
    }
    
    func requestNeedsUserApproval(_ request: OSSystemExtensionRequest) {
        os_log("User approval required", log: log)
        state = .needsUserApproval
    }
    
    func request(_ request: OSSystemExtensionRequest, didFinishWithResult result: OSSystemExtensionRequest.Result) {
        os_log("Request finished with result: %d", log: log, result.rawValue)
        state = (result == .completed) ? .activated : .pending
    }
    
    func request(_ request: OSSystemExtensionRequest, didFailWithError error: Error) {
        os_log("Request failed with error: %{public}@", log: log, error.localizedDescription)
        state = .failed(error.localizedDescription)
    }
}
