import Foundation

struct VoiceLexiconBackup: Codable {
    var version: Int = 1
    var exportedAt: Date = Date()
    var commandOverrides: [VoiceCommandOverrideConfig]
    var languageTermsOverrides: [VoiceLanguageTermsOverrideConfig]
}

enum VoiceLexiconDefaults {
    private static let cacheQueue = DispatchQueue(label: "com.aether.voice-lexicon-defaults.cache")
    private static var cached: VoiceLexiconBackup?
    private static let maxDefaultTermsPerField = 5

    static func load() -> VoiceLexiconBackup? {
        cacheQueue.sync {
            if let cached { return cached }
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601

            if let url = Bundle.main.url(forResource: "VoiceLexiconDefaults", withExtension: "json"),
               let data = try? Data(contentsOf: url),
               let decoded = try? decoder.decode(VoiceLexiconBackup.self, from: data) {
                let normalized = normalize(decoded)
                cached = normalized
                return normalized
            }

            let raw = NSLocalizedString("voice_lexicon.default_config", comment: "Default lexicon JSON in VoiceLexiconBackup format.")
            guard raw.contains("{") else { return nil }
            let data = Data(raw.utf8)
            guard let decoded = try? decoder.decode(VoiceLexiconBackup.self, from: data) else { return nil }
            let normalized = normalize(decoded)
            cached = normalized
            return normalized
        }
    }

    private static func normalize(_ backup: VoiceLexiconBackup) -> VoiceLexiconBackup {
        VoiceLexiconBackup(
            version: backup.version,
            exportedAt: backup.exportedAt,
            commandOverrides: backup.commandOverrides.map { item in
                VoiceCommandOverrideConfig(
                    localeIdentifier: item.localeIdentifier,
                    commandID: item.commandID,
                    aliases: sanitizeDefaults(item.aliases, localeIdentifier: item.localeIdentifier)
                )
            },
            languageTermsOverrides: backup.languageTermsOverrides.map { item in
                VoiceLanguageTermsOverrideConfig(
                    localeIdentifier: item.localeIdentifier,
                    wakeWords: sanitizeDefaults(item.wakeWords, localeIdentifier: item.localeIdentifier),
                    commandPrefixes: sanitizeDefaults(item.commandPrefixes, localeIdentifier: item.localeIdentifier),
                    dictationPrefixes: sanitizeDefaults(item.dictationPrefixes, localeIdentifier: item.localeIdentifier)
                )
            }
        )
    }

    private static func sanitizeDefaults(_ values: [String], localeIdentifier: String) -> [String] {
        Array(
            VoiceLexiconSupport.uniqueTerms(
                values.filter { VoiceLexiconSupport.isDefaultTerm($0, compatibleWith: localeIdentifier) }
            )
            .prefix(maxDefaultTermsPerField)
        )
    }
}
