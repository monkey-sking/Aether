import Foundation

struct VoiceLanguageTermsOverrideConfig: Codable, Identifiable, Equatable {
    var localeIdentifier: String
    var wakeWords: [String]
    var commandPrefixes: [String]
    var dictationPrefixes: [String]

    var id: String { localeIdentifier }
}

struct WakeWordDetectionResult {
    let wakeDetected: Bool
    /// Text that follows the wake phrase (empty string if entire utterance was the wake phrase).
    let payload: String
}

/// Stateless wake-word detector. No side effects.
final class WakeWordDetector {
    var overrides: [VoiceLanguageTermsOverrideConfig] = []

    static func defaultWakePhrases(for localeIdentifier: String) -> [String] {
        let locale = canonicalLocaleIdentifier(localeIdentifier).lowercased()
        if locale.hasPrefix("zh") {
            return ["艾瑟", "hey aether", "hi aether", "aether"]
        }
        return ["hey aether", "hi aether", "aether", "艾瑟"]
    }

    static func effectiveWakePhrases(
        for localeIdentifier: String,
        overrides: [VoiceLanguageTermsOverrideConfig]
    ) -> [String] {
        if let override = overrideEntry(for: localeIdentifier, overrides: overrides),
           !override.wakeWords.isEmpty {
            return uniquePhrases(override.wakeWords)
        }
        return defaultWakePhrases(for: localeIdentifier)
    }

    /// Detect whether text begins with a wake phrase and strip it.
    func process(_ text: String, localeIdentifier: String = Locale.current.identifier) -> WakeWordDetectionResult {
        guard text.count >= 4 else {
            return WakeWordDetectionResult(wakeDetected: false, payload: text)
        }
        let lower = text.lowercased()
        let phrases = Self.effectiveWakePhrases(for: localeIdentifier, overrides: overrides)
            .sorted { $0.count > $1.count }
        for phrase in phrases {
            if lower.hasPrefix(phrase.lowercased()) {
                let payload = String(text.dropFirst(phrase.count))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                return WakeWordDetectionResult(wakeDetected: true, payload: payload)
            }
        }
        return WakeWordDetectionResult(wakeDetected: false, payload: text)
    }

    /// Strip the wake phrase if present; otherwise return text unchanged.
    func strip(_ text: String, localeIdentifier: String = Locale.current.identifier) -> String {
        return process(text, localeIdentifier: localeIdentifier).payload
    }

    /// Quick check: does this text start with any wake phrase?
    func isWakePhrase(_ text: String, localeIdentifier: String = Locale.current.identifier) -> Bool {
        guard text.count >= 4 else { return false }
        let lower = text.lowercased()
        return Self.effectiveWakePhrases(for: localeIdentifier, overrides: overrides)
            .contains(where: { lower.hasPrefix($0.lowercased()) })
    }

    func contextualStrings(for localeIdentifier: String) -> [String] {
        Self.effectiveWakePhrases(for: localeIdentifier, overrides: overrides)
    }

    private static func overrideEntry(
        for localeIdentifier: String,
        overrides: [VoiceLanguageTermsOverrideConfig]
    ) -> VoiceLanguageTermsOverrideConfig? {
        let raw = localeIdentifier
        let canonical = canonicalLocaleIdentifier(localeIdentifier)
        return overrides.first(where: { $0.localeIdentifier == raw }) ??
            overrides.first(where: { $0.localeIdentifier == canonical })
    }

    private static func canonicalLocaleIdentifier(_ raw: String) -> String {
        let locale = raw.lowercased()
        if locale.hasPrefix("zh") { return "zh-CN" }
        if locale.hasPrefix("en") { return "en-US" }
        if locale.hasPrefix("ja") { return "ja-JP" }
        if locale.hasPrefix("ko") { return "ko-KR" }
        if locale.hasPrefix("fr") { return "fr-FR" }
        if locale.hasPrefix("de") { return "de-DE" }
        if locale.hasPrefix("es") { return "es-ES" }
        return raw
    }

    private static func uniquePhrases(_ phrases: [String]) -> [String] {
        var ordered: [String] = []
        var seen = Set<String>()

        for phrase in phrases {
            let trimmed = phrase.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let key = trimmed.lowercased()
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            ordered.append(trimmed)
        }

        return ordered
    }
}
