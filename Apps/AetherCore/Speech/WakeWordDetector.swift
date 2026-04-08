import Foundation

fileprivate let wakePayloadSeparatorScalars = CharacterSet(charactersIn: ",.!?;:，。！？；：、…")

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
    var appLaunchPrefixes: [String]

    init(
        localeIdentifier: String,
        wakeWords: [String],
        commandPrefixes: [String],
        dictationPrefixes: [String],
        appLaunchPrefixes: [String] = []
    ) {
        self.localeIdentifier = localeIdentifier
        self.wakeWords = wakeWords
        self.commandPrefixes = commandPrefixes
        self.dictationPrefixes = dictationPrefixes
        self.appLaunchPrefixes = appLaunchPrefixes
    }

    private enum CodingKeys: String, CodingKey {
        case localeIdentifier
        case wakeWords
        case commandPrefixes
        case dictationPrefixes
        case appLaunchPrefixes
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        localeIdentifier = try container.decode(String.self, forKey: .localeIdentifier)
        wakeWords = try container.decodeIfPresent([String].self, forKey: .wakeWords) ?? []
        commandPrefixes = try container.decodeIfPresent([String].self, forKey: .commandPrefixes) ?? []
        dictationPrefixes = try container.decodeIfPresent([String].self, forKey: .dictationPrefixes) ?? []
        appLaunchPrefixes = try container.decodeIfPresent([String].self, forKey: .appLaunchPrefixes) ?? []
    }

    var id: String { localeIdentifier }
}

enum WakeWordMatchMode {
    case strictPrefix
    case retryAwareStandby
    case awakeFollowUp
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
        let leadingRawDiscardCount: Int
        let consumeRawCount: Int

        var totalConsumedRawCount: Int { leadingRawDiscardCount + consumeRawCount }
    }

    private struct WakeOccurrenceBlock {
        let start: String.Index
        let end: String.Index
        let count: Int
        let occurrencesBeforeBlock: Int
    }

    private static let fuzzyWakeDetectionThreshold = 0.88
    private static let retryWakeDetectionThreshold = 0.93
    private static let retryLeadInRawCharacterBudget = 12
    private static let retryTrailingClauseRawCharacterBudget = 16
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

    static var diagnosticsThreshold: Double { fuzzyWakeDetectionThreshold }

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
    func process(
        _ text: String,
        localeIdentifier: String = Locale.current.identifier,
        matchMode: WakeWordMatchMode = .strictPrefix
    ) -> WakeWordDetectionResult {
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

        let strictMatch = Self.bestMatchAcrossPhrases(
            phrases,
            in: trimmedLeading,
            leadingRawDiscardCount: 0
        )
        if let strictMatch, strictMatch.score >= Self.fuzzyWakeDetectionThreshold {
            let payload = String(trimmedLeading.dropFirst(strictMatch.totalConsumedRawCount))
                .trimmingLeadingWakePayloadSeparators()
            return WakeWordDetectionResult(
                wakeDetected: true,
                payload: payload,
                score: strictMatch.score,
                matchedPhrase: strictMatch.phrase
            )
        }

        if matchMode == .retryAwareStandby,
           let retryMatch = Self.bestRetryAwareMatch(
            phrases: phrases,
            in: trimmedLeading,
            localeIdentifier: localeIdentifier
           ) {
            let payload = String(trimmedLeading.dropFirst(retryMatch.totalConsumedRawCount))
                .trimmingLeadingWakePayloadSeparators()
            return WakeWordDetectionResult(
                wakeDetected: true,
                payload: payload,
                score: retryMatch.score,
                matchedPhrase: retryMatch.phrase
            )
        }

        if matchMode == .retryAwareStandby,
           let trailingRecoveryMatch = Self.bestTrailingClauseRecoveryMatch(
            phrases: phrases,
            in: trimmedLeading,
            localeIdentifier: localeIdentifier
           ) {
            let payload = String(trimmedLeading.dropFirst(trailingRecoveryMatch.totalConsumedRawCount))
                .trimmingLeadingWakePayloadSeparators()
            return WakeWordDetectionResult(
                wakeDetected: true,
                payload: payload,
                score: trailingRecoveryMatch.score,
                matchedPhrase: trailingRecoveryMatch.phrase
            )
        }

        if matchMode == .retryAwareStandby,
           let repeatedRetryMatch = Self.bestRepeatedWakeRetryMatch(
            phrases: phrases,
            in: trimmedLeading
           ) {
            let payload = String(trimmedLeading.dropFirst(repeatedRetryMatch.totalConsumedRawCount))
                .trimmingLeadingWakePayloadSeparators()
            return WakeWordDetectionResult(
                wakeDetected: true,
                payload: payload,
                score: repeatedRetryMatch.score,
                matchedPhrase: repeatedRetryMatch.phrase
            )
        }

        return WakeWordDetectionResult(
            wakeDetected: false,
            payload: text,
            score: strictMatch?.score ?? 0,
            matchedPhrase: strictMatch?.phrase
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

    func diagnosticsSummary(for localeIdentifier: String) -> String {
        let phrases = contextualStrings(for: localeIdentifier)
        let joined = phrases.isEmpty ? "[]" : "[" + phrases.joined(separator: " | ") + "]"
        return "locale=\(localeIdentifier) threshold=\(String(format: "%.2f", Self.diagnosticsThreshold)) phrases=\(joined)"
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

    private static func bestMatchAcrossPhrases(
        _ phrases: [String],
        in text: String,
        leadingRawDiscardCount: Int
    ) -> WakePhraseMatch? {
        var bestCandidate: WakePhraseMatch?
        for phrase in phrases {
            guard let match = bestMatch(for: phrase, in: text, leadingRawDiscardCount: leadingRawDiscardCount) else {
                continue
            }
            if let currentBest = bestCandidate {
                if match.score > currentBest.score
                    || (match.score == currentBest.score && match.phrase.count > currentBest.phrase.count)
                    || (match.score == currentBest.score
                        && match.phrase.count == currentBest.phrase.count
                        && match.leadingRawDiscardCount < currentBest.leadingRawDiscardCount) {
                    bestCandidate = match
                }
            } else {
                bestCandidate = match
            }
        }
        return bestCandidate
    }

    private static func bestMatch(for phrase: String, in text: String) -> WakePhraseMatch? {
        bestMatch(for: phrase, in: text, leadingRawDiscardCount: 0)
    }

    private static func bestMatch(
        for phrase: String,
        in text: String,
        leadingRawDiscardCount: Int
    ) -> WakePhraseMatch? {
        let loweredText = text.lowercased()
        let loweredPhrase = phrase.lowercased()
        if loweredText.hasPrefix(loweredPhrase) {
            return WakePhraseMatch(
                phrase: phrase,
                score: 1.0,
                leadingRawDiscardCount: leadingRawDiscardCount,
                consumeRawCount: phrase.count
            )
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

            let match = WakePhraseMatch(
                phrase: phrase,
                score: score,
                leadingRawDiscardCount: leadingRawDiscardCount,
                consumeRawCount: rawCount
            )
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

    private static func bestSuffixMatch(for phrase: String, in text: String) -> WakePhraseMatch? {
        let loweredText = text.lowercased()
        let loweredPhrase = phrase.lowercased()
        if loweredText.hasSuffix(loweredPhrase) {
            return WakePhraseMatch(
                phrase: phrase,
                score: 1.0,
                leadingRawDiscardCount: max(0, text.count - phrase.count),
                consumeRawCount: phrase.count
            )
        }

        let normalizedPhrase = normalizeForWakeMatching(phrase)
        guard !normalizedPhrase.isEmpty else { return nil }
        let pinyinPhrase = phrase.pinyin

        let maxRawSuffix = min(text.count, max(phrase.count + 4, phrase.count))
        var best: WakePhraseMatch?

        for rawCount in 1...maxRawSuffix {
            let candidate = String(text.suffix(rawCount))
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

            let match = WakePhraseMatch(
                phrase: phrase,
                score: score,
                leadingRawDiscardCount: max(0, text.count - rawCount),
                consumeRawCount: rawCount
            )
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

    private static func bestRetryAwareMatch(
        phrases: [String],
        in text: String,
        localeIdentifier: String
    ) -> WakePhraseMatch? {
        guard text.count > 1 else { return nil }

        var bestRetryMatch: WakePhraseMatch?
        let maxDiscard = min(text.count - 1, retryLeadInRawCharacterBudget)

        for discardCount in 1...maxDiscard {
            let skipped = String(text.prefix(discardCount))
            guard isRetryLeadInEligible(skipped, localeIdentifier: localeIdentifier) else {
                continue
            }

            let suffix = String(text.dropFirst(discardCount))
            guard !suffix.isEmpty,
                  let candidate = bestMatchAcrossPhrases(
                    phrases,
                    in: suffix,
                    leadingRawDiscardCount: discardCount
                  ),
                  candidate.score >= retryWakeDetectionThreshold,
                  isRetryExactMatch(
                    candidate: String(suffix.prefix(candidate.consumeRawCount)),
                    phrase: candidate.phrase
                  ) else {
                continue
            }

            if let currentBest = bestRetryMatch {
                if candidate.score > currentBest.score
                    || (candidate.score == currentBest.score
                        && candidate.leadingRawDiscardCount < currentBest.leadingRawDiscardCount)
                    || (candidate.score == currentBest.score
                        && candidate.leadingRawDiscardCount == currentBest.leadingRawDiscardCount
                        && candidate.phrase.count > currentBest.phrase.count) {
                    bestRetryMatch = candidate
                }
            } else {
                bestRetryMatch = candidate
            }
        }

        return bestRetryMatch
    }

    private static func bestTrailingClauseRecoveryMatch(
        phrases: [String],
        in text: String,
        localeIdentifier: String
    ) -> WakePhraseMatch? {
        guard text.count > 1 else { return nil }

        var bestRecoveryMatch: WakePhraseMatch?

        for phrase in phrases {
            guard let candidate = bestSuffixMatch(for: phrase, in: text),
                  candidate.score >= retryWakeDetectionThreshold,
                  isRetryExactMatch(
                    candidate: String(text.suffix(candidate.consumeRawCount)),
                    phrase: candidate.phrase
                  ) else {
                continue
            }

            let leadingRaw = String(text.prefix(candidate.leadingRawDiscardCount))
            guard isTrailingWakeLeadInEligible(leadingRaw, localeIdentifier: localeIdentifier) else {
                continue
            }

            if let currentBest = bestRecoveryMatch {
                if candidate.score > currentBest.score
                    || (candidate.score == currentBest.score
                        && candidate.leadingRawDiscardCount < currentBest.leadingRawDiscardCount)
                    || (candidate.score == currentBest.score
                        && candidate.leadingRawDiscardCount == currentBest.leadingRawDiscardCount
                        && candidate.phrase.count > currentBest.phrase.count) {
                    bestRecoveryMatch = candidate
                }
            } else {
                bestRecoveryMatch = candidate
            }
        }

        return bestRecoveryMatch
    }

    private static func bestRepeatedWakeRetryMatch(
        phrases: [String],
        in text: String
    ) -> WakePhraseMatch? {
        guard text.count > 1 else { return nil }

        var bestRetryMatch: WakePhraseMatch?

        for phrase in phrases {
            let occurrences = exactOccurrenceRanges(of: phrase, in: text)
            guard occurrences.count >= 2,
                  let block = trailingRepeatedWakeBlock(in: text, occurrences: occurrences),
                  isRepeatedWakeRetryBlockEligible(block, in: text) else {
                continue
            }

            let candidate = WakePhraseMatch(
                phrase: phrase,
                score: 1.0,
                leadingRawDiscardCount: text.distance(from: text.startIndex, to: block.start),
                consumeRawCount: text.distance(from: block.start, to: block.end)
            )

            if let currentBest = bestRetryMatch {
                if candidate.score > currentBest.score
                    || (candidate.score == currentBest.score
                        && candidate.phrase.count > currentBest.phrase.count)
                    || (candidate.score == currentBest.score
                        && candidate.phrase.count == currentBest.phrase.count
                        && candidate.leadingRawDiscardCount > currentBest.leadingRawDiscardCount) {
                    bestRetryMatch = candidate
                }
            } else {
                bestRetryMatch = candidate
            }
        }

        return bestRetryMatch
    }

    private static func isRetryLeadInEligible(
        _ text: String,
        localeIdentifier: String
    ) -> Bool {
        let normalized = normalizeForWakeMatching(text)
        guard !normalized.isEmpty else { return false }

        let canonicalLocale = VoiceLexiconSupport.canonicalLocaleIdentifier(localeIdentifier)
        let maxNormalizedLength: Int
        switch canonicalLocale {
        case "zh-CN", "ja-JP", "ko-KR":
            maxNormalizedLength = (canonicalLocale == "zh-CN") ? 8 : 4
        default:
            maxNormalizedLength = 6
        }
        guard normalized.count <= maxNormalizedLength else {
            return false
        }

        let leadInTerms = retryLeadInTerms(for: canonicalLocale)
            .map(normalizeForWakeMatching)
            .filter { !$0.isEmpty }
            .sorted { $0.count > $1.count }
        guard !leadInTerms.isEmpty else { return false }

        return canComposeRetryLeadIn(normalized, terms: leadInTerms)
    }

    private static func isTrailingWakeLeadInEligible(
        _ text: String,
        localeIdentifier: String
    ) -> Bool {
        let trimmedTrailing = text.trimmingTrailingWakePayloadSeparators()
        let normalized = normalizeForWakeMatching(trimmedTrailing)
        guard !normalized.isEmpty else { return false }

        if isRetryLeadInEligible(trimmedTrailing, localeIdentifier: localeIdentifier) {
            return true
        }

        let hadClauseBoundary = trimmedTrailing.count != text.count
        guard hadClauseBoundary else { return false }
        guard trimmedTrailing.count <= retryTrailingClauseRawCharacterBudget else { return false }

        let canonicalLocale = VoiceLexiconSupport.canonicalLocaleIdentifier(localeIdentifier)
        let maxNormalizedLength: Int
        switch canonicalLocale {
        case "zh-CN":
            maxNormalizedLength = 8
        case "ja-JP", "ko-KR":
            maxNormalizedLength = 6
        default:
            maxNormalizedLength = 8
        }

        return normalized.count <= maxNormalizedLength
    }

    private static func exactOccurrenceRanges(
        of phrase: String,
        in text: String
    ) -> [Range<String.Index>] {
        guard !phrase.isEmpty, !text.isEmpty else { return [] }

        var ranges: [Range<String.Index>] = []
        var searchStart = text.startIndex

        while searchStart < text.endIndex,
              let range = text.range(
                of: phrase,
                options: [.caseInsensitive, .diacriticInsensitive],
                range: searchStart..<text.endIndex,
                locale: .current
              ) {
            ranges.append(range)
            searchStart = range.upperBound
        }

        return ranges
    }

    private static func trailingRepeatedWakeBlock(
        in text: String,
        occurrences: [Range<String.Index>]
    ) -> WakeOccurrenceBlock? {
        guard let lastIndex = occurrences.indices.last else { return nil }

        var blockStartIndex = lastIndex
        let blockEnd = occurrences[lastIndex].upperBound

        while blockStartIndex > 0 {
            let previous = occurrences[blockStartIndex - 1]
            let current = occurrences[blockStartIndex]
            let gap = text[previous.upperBound..<current.lowerBound]
            guard containsOnlyWakeSeparators(gap) else { break }
            blockStartIndex -= 1
        }

        return WakeOccurrenceBlock(
            start: occurrences[blockStartIndex].lowerBound,
            end: blockEnd,
            count: lastIndex - blockStartIndex + 1,
            occurrencesBeforeBlock: blockStartIndex
        )
    }

    private static func isRepeatedWakeRetryBlockEligible(
        _ block: WakeOccurrenceBlock,
        in text: String
    ) -> Bool {
        let trailingRemainder = String(text[block.end...]).trimmingLeadingWakePayloadSeparators()
        guard normalizeForWakeMatching(trailingRemainder).count <= 1 else {
            return false
        }

        if block.count >= 2 {
            return true
        }

        guard block.occurrencesBeforeBlock > 0 else {
            return false
        }

        return hasClauseBoundaryBeforeRepeatedWakeBlock(in: text, at: block.start)
    }

    private static func hasClauseBoundaryBeforeRepeatedWakeBlock(
        in text: String,
        at blockStart: String.Index
    ) -> Bool {
        guard blockStart > text.startIndex else { return false }

        var index = blockStart
        var sawClauseBoundary = false

        while index > text.startIndex {
            let previous = text.index(before: index)
            let scalarView = text[previous].unicodeScalars
            let isIgnorable = scalarView.allSatisfy {
                CharacterSet.whitespacesAndNewlines.contains($0)
                    || wakePayloadSeparatorScalars.contains($0)
            }
            if !isIgnorable { break }
            if scalarView.contains(where: { wakePayloadSeparatorScalars.contains($0) }) {
                sawClauseBoundary = true
            }
            index = previous
        }

        return sawClauseBoundary
    }

    private static func containsOnlyWakeSeparators<S: StringProtocol>(_ text: S) -> Bool {
        text.unicodeScalars.allSatisfy {
            CharacterSet.whitespacesAndNewlines.contains($0)
                || wakePayloadSeparatorScalars.contains($0)
        }
    }

    private static func retryLeadInTerms(for canonicalLocaleIdentifier: String) -> [String] {
        switch canonicalLocaleIdentifier {
        case "zh-CN":
            return [
                "嗯", "嗯哼", "啊", "呃", "诶", "欸", "哎", "唉", "哎呀", "嘿", "喂",
                "那个", "这个", "就是", "真的", "还有", "然后", "那就", "那么", "请问", "麻烦",
                "能不能", "你能不能", "可不可以", "你可不可以"
            ]
        case "ja-JP":
            return ["えっと", "あの", "えー", "ねえ"]
        case "ko-KR":
            return ["음", "어", "저기", "있잖아"]
        case "fr-FR":
            return ["euh", "eh", "salut"]
        case "de-DE":
            return ["äh", "hm", "hey"]
        case "es-ES":
            return ["eh", "oye", "hola"]
        default:
            return ["um", "uh", "ah", "er", "hey", "okay", "ok"]
        }
    }

    private static func canComposeRetryLeadIn(_ text: String, terms: [String]) -> Bool {
        guard !text.isEmpty else { return false }

        let characters = Array(text)
        var reachable = Array(repeating: false, count: characters.count + 1)
        reachable[0] = true

        for start in 0..<characters.count where reachable[start] {
            let suffix = String(characters[start...])
            for term in terms where suffix.hasPrefix(term) {
                reachable[start + term.count] = true
            }
        }

        return reachable[characters.count]
    }

    private static func isRetryExactMatch(candidate: String, phrase: String) -> Bool {
        if candidate.lowercased() == phrase.lowercased() {
            return true
        }
        return normalizeForWakeMatching(candidate) == normalizeForWakeMatching(phrase)
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
    func trimmingLeadingWakePayloadSeparators() -> String {
        var index = startIndex
        while index < endIndex {
            let scalarView = self[index].unicodeScalars
            let isIgnorable = scalarView.allSatisfy {
                CharacterSet.whitespacesAndNewlines.contains($0)
                    || wakePayloadSeparatorScalars.contains($0)
            }
            if !isIgnorable { break }
            index = self.index(after: index)
        }
        return String(self[index...])
    }

    func trimmingTrailingWakePayloadSeparators() -> String {
        var index = endIndex
        while index > startIndex {
            let previous = self.index(before: index)
            let scalarView = self[previous].unicodeScalars
            let isIgnorable = scalarView.allSatisfy {
                CharacterSet.whitespacesAndNewlines.contains($0)
                    || wakePayloadSeparatorScalars.contains($0)
            }
            if !isIgnorable { break }
            index = previous
        }
        return String(self[..<index])
    }

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
