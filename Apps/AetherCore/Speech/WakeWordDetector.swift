import Foundation

enum VoiceLexiconSupport {
    static func canonicalLocaleIdentifier(_ raw: String) -> String {
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

    static func uniqueTerms(_ items: [String]) -> [String] {
        var ordered: [String] = []
        var seen = Set<String>()

        for item in items {
            let trimmed = item.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let key = trimmed.lowercased()
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            ordered.append(trimmed)
        }

        return ordered
    }

    static func isDefaultTerm(_ term: String, compatibleWith localeIdentifier: String) -> Bool {
        let canonical = canonicalLocaleIdentifier(localeIdentifier)
        switch canonical {
        case "zh-CN":
            return term.unicodeScalars.contains(where: { $0.properties.isIdeographic })
        case "ja-JP":
            return term.unicodeScalars.contains(where: {
                $0.properties.isIdeographic ||
                (0x3040...0x309F).contains($0.value) ||
                (0x30A0...0x30FF).contains($0.value)
            })
        case "ko-KR":
            return term.unicodeScalars.contains(where: { (0xAC00...0xD7AF).contains($0.value) })
        default:
            return !term.unicodeScalars.contains(where: {
                $0.properties.isIdeographic ||
                (0x3040...0x30FF).contains($0.value) ||
                (0xAC00...0xD7AF).contains($0.value)
            })
        }
    }
}

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
    private let stateQueue = DispatchQueue(label: "com.aether.wake-word-detector.state", attributes: .concurrent)
    private var storedOverrides: [VoiceLanguageTermsOverrideConfig] = []

    var overrides: [VoiceLanguageTermsOverrideConfig] {
        get { stateQueue.sync { storedOverrides } }
        set {
            stateQueue.sync(flags: .barrier) {
                storedOverrides = newValue
            }
        }
    }

    static func defaultWakePhrases(for localeIdentifier: String) -> [String] {
        guard let defaults = VoiceLexiconDefaults.load() else { return [] }
        let canonical = VoiceLexiconSupport.canonicalLocaleIdentifier(localeIdentifier)
        let entry = defaults.languageTermsOverrides.first(where: {
            VoiceLexiconSupport.canonicalLocaleIdentifier($0.localeIdentifier) == canonical
        })
        return VoiceLexiconSupport.uniqueTerms(entry?.wakeWords ?? [])
    }

    static func effectiveWakePhrases(
        for localeIdentifier: String,
        overrides: [VoiceLanguageTermsOverrideConfig]
    ) -> [String] {
        if let override = overrideEntry(for: localeIdentifier, overrides: overrides) {
            return VoiceLexiconSupport.uniqueTerms(override.wakeWords)
        }
        return defaultWakePhrases(for: localeIdentifier)
    }

    /// Detect whether text begins with a wake phrase and strip it.
    func process(_ text: String, localeIdentifier: String = Locale.current.identifier) -> WakeWordDetectionResult {
        let activeOverrides = overrides
        let phrases = Self.effectiveWakePhrases(for: localeIdentifier, overrides: activeOverrides)
            .sorted { $0.count > $1.count }
        let minimumWakePhraseLength = phrases.map(\.count).min() ?? 1

        guard text.count >= minimumWakePhraseLength else {
            return WakeWordDetectionResult(wakeDetected: false, payload: text)
        }
        let lower = text.lowercased()
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
        let activeOverrides = overrides
        let phrases = Self.effectiveWakePhrases(for: localeIdentifier, overrides: activeOverrides)
        let minimumWakePhraseLength = phrases.map(\.count).min() ?? 1

        guard text.count >= minimumWakePhraseLength else { return false }
        let lower = text.lowercased()
        return phrases.contains(where: { lower.hasPrefix($0.lowercased()) })
    }

    func contextualStrings(for localeIdentifier: String) -> [String] {
        Self.effectiveWakePhrases(for: localeIdentifier, overrides: overrides)
    }

    private static func overrideEntry(
        for localeIdentifier: String,
        overrides: [VoiceLanguageTermsOverrideConfig]
    ) -> VoiceLanguageTermsOverrideConfig? {
        let raw = localeIdentifier
        let canonical = VoiceLexiconSupport.canonicalLocaleIdentifier(localeIdentifier)
        return overrides.first(where: { $0.localeIdentifier == raw }) ??
            overrides.first(where: { $0.localeIdentifier == canonical })
    }
}
