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
    let score: Double
    let matchedPhrase: String?
}

/// Stateless wake-word detector. No side effects.
final class WakeWordDetector {
    private struct WakePhraseMatch {
        let phrase: String
        let score: Double
        let consumeRawCount: Int
    }

    private static let fuzzyWakeDetectionThreshold = 0.88
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
            return WakeWordDetectionResult(wakeDetected: false, payload: text, score: 0, matchedPhrase: nil)
        }

        let trimmedLeading = text.trimmingLeadingWakeIgnorables()
        guard !trimmedLeading.isEmpty else {
            return WakeWordDetectionResult(wakeDetected: false, payload: text, score: 0, matchedPhrase: nil)
        }

        var bestMatch: WakePhraseMatch?
        for phrase in phrases {
            guard let match = Self.bestMatch(for: phrase, in: trimmedLeading) else { continue }
            if let currentBest = bestMatch {
                if match.score > currentBest.score || (match.score == currentBest.score && match.phrase.count > currentBest.phrase.count) {
                    bestMatch = match
                }
            } else {
                bestMatch = match
            }
        }

        guard let bestMatch, bestMatch.score >= Self.fuzzyWakeDetectionThreshold else {
            return WakeWordDetectionResult(wakeDetected: false, payload: text, score: bestMatch?.score ?? 0, matchedPhrase: bestMatch?.phrase)
        }

        let payload = String(trimmedLeading.dropFirst(bestMatch.consumeRawCount))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return WakeWordDetectionResult(
            wakeDetected: true,
            payload: payload,
            score: bestMatch.score,
            matchedPhrase: bestMatch.phrase
        )
    }

    /// Strip the wake phrase if present; otherwise return text unchanged.
    func strip(_ text: String, localeIdentifier: String = Locale.current.identifier) -> String {
        return process(text, localeIdentifier: localeIdentifier).payload
    }

    /// Quick check: does this text start with any wake phrase?
    func isWakePhrase(_ text: String, localeIdentifier: String = Locale.current.identifier) -> Bool {
        process(text, localeIdentifier: localeIdentifier).wakeDetected
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

    private static func bestMatch(for phrase: String, in text: String) -> WakePhraseMatch? {
        let loweredText = text.lowercased()
        let loweredPhrase = phrase.lowercased()
        if loweredText.hasPrefix(loweredPhrase) {
            return WakePhraseMatch(phrase: phrase, score: 1.0, consumeRawCount: phrase.count)
        }

        let normalizedPhrase = normalizeForWakeMatching(phrase)
        guard !normalizedPhrase.isEmpty else { return nil }
        let pinyinPhrase = phrase.pinyin

        let maxRawPrefix = min(text.count, max(phrase.count + 4, phrase.count))
        var best: WakePhraseMatch?

        for rawCount in 1...maxRawPrefix {
            let candidate = String(text.prefix(rawCount))
            let normalizedCandidate = normalizeForWakeMatching(candidate)
            guard !normalizedCandidate.isEmpty else { continue }
            guard normalizedCandidate.count <= normalizedPhrase.count + 2 else { continue }

            let score = wakeMatchScore(
                candidate: candidate,
                normalizedCandidate: normalizedCandidate,
                pinyinCandidate: candidate.pinyin,
                phrase: phrase,
                normalizedPhrase: normalizedPhrase,
                pinyinPhrase: pinyinPhrase
            )
            guard score > 0 else { continue }

            let match = WakePhraseMatch(phrase: phrase, score: score, consumeRawCount: rawCount)
            if let currentBest = best {
                if match.score > currentBest.score || (match.score == currentBest.score && match.consumeRawCount > currentBest.consumeRawCount) {
                    best = match
                }
            } else {
                best = match
            }
        }

        return best
    }

    private static func wakeMatchScore(
        candidate: String,
        normalizedCandidate: String,
        pinyinCandidate: String,
        phrase: String,
        normalizedPhrase: String,
        pinyinPhrase: String
    ) -> Double {
        if normalizedCandidate == normalizedPhrase {
            return 0.98
        }
        if !pinyinPhrase.isEmpty, pinyinCandidate == pinyinPhrase {
            return 0.93
        }

        let distance = levenshtein(normalizedCandidate, normalizedPhrase)
        let maxLen = max(normalizedCandidate.count, normalizedPhrase.count)
        guard maxLen > 0 else { return 0 }

        if distance == 1 {
            if maxLen <= 3, pinyinCandidate == pinyinPhrase {
                return 0.91
            }
            if maxLen >= 4 {
                return 0.89
            }
        } else if distance == 2, maxLen >= 6 {
            return 0.88
        }

        return 0
    }

    private static func normalizeForWakeMatching(_ text: String) -> String {
        text
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .unicodeScalars
            .filter { !CharacterSet.whitespacesAndNewlines.contains($0) && !CharacterSet.punctuationCharacters.contains($0) }
            .map(String.init)
            .joined()
            .lowercased()
    }

    private static func levenshtein(_ lhs: String, _ rhs: String) -> Int {
        let lhsChars = Array(lhs)
        let rhsChars = Array(rhs)
        guard !lhsChars.isEmpty else { return rhsChars.count }
        guard !rhsChars.isEmpty else { return lhsChars.count }

        var previous = Array(0...rhsChars.count)
        var current = Array(repeating: 0, count: rhsChars.count + 1)

        for (i, lc) in lhsChars.enumerated() {
            current[0] = i + 1
            for (j, rc) in rhsChars.enumerated() {
                let cost = lc == rc ? 0 : 1
                current[j + 1] = min(
                    previous[j + 1] + 1,
                    current[j] + 1,
                    previous[j] + cost
                )
            }
            swap(&previous, &current)
        }

        return previous[rhsChars.count]
    }
}

private extension String {
    func trimmingLeadingWakeIgnorables() -> String {
        var index = startIndex
        while index < endIndex {
            let scalarView = self[index].unicodeScalars
            let isIgnorable = scalarView.allSatisfy {
                CharacterSet.whitespacesAndNewlines.contains($0)
                    || CharacterSet.punctuationCharacters.contains($0)
            }
            if !isIgnorable { break }
            index = self.index(after: index)
        }
        return String(self[index...])
    }
}
