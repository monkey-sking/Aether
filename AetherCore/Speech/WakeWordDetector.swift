import Foundation

struct WakeWordDetectionResult {
    let wakeDetected: Bool
    /// Text that follows the wake phrase (empty string if entire utterance was the wake phrase).
    let payload: String
}

/// Stateless wake-word detector. No side effects.
final class WakeWordDetector {
    /// Phrases checked in priority order (longer matches first).
    let phrases = ["hey aether", "hi aether", "aether", "艾瑟"]

    /// Detect whether text begins with a wake phrase and strip it.
    func process(_ text: String) -> WakeWordDetectionResult {
        guard text.count >= 4 else {
            return WakeWordDetectionResult(wakeDetected: false, payload: text)
        }
        let lower = text.lowercased()
        for phrase in phrases {
            if lower.hasPrefix(phrase) {
                let payload = String(text.dropFirst(phrase.count))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                return WakeWordDetectionResult(wakeDetected: true, payload: payload)
            }
        }
        return WakeWordDetectionResult(wakeDetected: false, payload: text)
    }

    /// Strip the wake phrase if present; otherwise return text unchanged.
    func strip(_ text: String) -> String {
        return process(text).payload
    }

    /// Quick check: does this text start with any wake phrase?
    func isWakePhrase(_ text: String) -> Bool {
        guard text.count >= 4 else { return false }
        let lower = text.lowercased()
        return phrases.contains(where: { lower.hasPrefix($0) })
    }
}
