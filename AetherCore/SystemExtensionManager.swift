import Foundation
import SystemExtensions
import os.log

class SystemExtensionManager: NSObject, OSSystemExtensionRequestDelegate, ObservableObject {
    static let shared = SystemExtensionManager()
    
    @Published var status: String = "Idle"
    
    private let log = OSLog(subsystem: "com.yourname.Aether", category: "ExtensionManager")
    
    func activate(identifier: String) {
        let request = OSSystemExtensionRequest.activationRequest(forExtensionWithIdentifier: identifier, queue: .main)
        request.delegate = self
        OSSystemExtensionManager.shared.submitRequest(request)
        status = "Requesting activation..."
        os_log("Submitted activation request for %{public}@", log: log, identifier)
    }
    
    func deactivate(identifier: String) {
        let request = OSSystemExtensionRequest.deactivationRequest(forExtensionWithIdentifier: identifier, queue: .main)
        request.delegate = self
        OSSystemExtensionManager.shared.submitRequest(request)
        status = "Requesting deactivation..."
    }
    
    // MARK: - OSSystemExtensionRequestDelegate
    
    func request(_ request: OSSystemExtensionRequest, actionForReplacingExtension existing: OSSystemExtensionProperties, withExtension extension: OSSystemExtensionProperties) -> OSSystemExtensionRequest.ReplacementAction {
        os_log("Replacing existing extension", log: log)
        return .replace
    }
    
    func requestNeedsUserApproval(_ request: OSSystemExtensionRequest) {
        os_log("User approval required", log: log)
        status = "Needs User Approval"
    }
    
    func request(_ request: OSSystemExtensionRequest, didFinishWithResult result: OSSystemExtensionRequest.Result) {
        os_log("Request finished with result: %d", log: log, result.rawValue)
        status = (result == .completed) ? "Activated" : "Pending"
    }
    
    func request(_ request: OSSystemExtensionRequest, didFailWithError error: Error) {
        os_log("Request failed with error: %{public}@", log: log, error.localizedDescription)
        status = "Failed: \(error.localizedDescription)"
    }
}
