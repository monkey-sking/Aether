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

    static func load() -> VoiceLexiconBackup? {
        cacheQueue.sync {
            if let cached { return cached }
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601

            if let url = Bundle.main.url(forResource: "VoiceLexiconDefaults", withExtension: "json"),
               let data = try? Data(contentsOf: url),
               let decoded = try? decoder.decode(VoiceLexiconBackup.self, from: data) {
                cached = decoded
                return decoded
            }

            let raw = NSLocalizedString("voice_lexicon.default_config", comment: "Default lexicon JSON in VoiceLexiconBackup format.")
            guard raw.contains("{") else { return nil }
            let data = Data(raw.utf8)
            guard let decoded = try? decoder.decode(VoiceLexiconBackup.self, from: data) else { return nil }
            cached = decoded
            return decoded
        }
    }
}
