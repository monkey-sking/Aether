import Foundation
import Security

enum EntitlementChecker {
    static func hasEntitlement(_ key: String) -> Bool {
        guard let task = SecTaskCreateFromSelf(nil) else { return false }
        let value = SecTaskCopyValueForEntitlement(task, key as CFString, nil)

        if let b = value as? Bool { return b }
        if let n = value as? NSNumber { return n.boolValue }
        return value != nil
    }
}

