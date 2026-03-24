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

            return nil
        }
    }

    private static func normalize(_ backup: VoiceLexiconBackup) -> VoiceLexiconBackup {
        let mergedOverrides = mergeSupplementalCommandOverrides(into: backup.commandOverrides)
        return VoiceLexiconBackup(
            version: backup.version,
            exportedAt: backup.exportedAt,
            commandOverrides: mergedOverrides.map { item in
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

    private static func mergeSupplementalCommandOverrides(into existing: [VoiceCommandOverrideConfig]) -> [VoiceCommandOverrideConfig] {
        var merged = existing

        for item in supplementalCommandOverrides() {
            if let index = merged.firstIndex(where: {
                $0.localeIdentifier == item.localeIdentifier && $0.commandID == item.commandID
            }) {
                merged[index].aliases = VoiceLexiconSupport.uniqueTerms(merged[index].aliases + item.aliases)
            } else {
                merged.append(item)
            }
        }

        return merged
    }

    private static func supplementalCommandOverrides() -> [VoiceCommandOverrideConfig] {
        [
            VoiceCommandOverrideConfig(localeIdentifier: "zh-CN", commandID: VoiceCommandPreset.deleteBackward.rawValue, aliases: ["删除", "删掉", "退格"]),
            VoiceCommandOverrideConfig(localeIdentifier: "en-US", commandID: VoiceCommandPreset.deleteBackward.rawValue, aliases: ["delete", "erase", "backspace"]),
            VoiceCommandOverrideConfig(localeIdentifier: "zh-CN", commandID: VoiceCommandPreset.moveCursorLeft.rawValue, aliases: ["向左移动", "往左移动", "左移"]),
            VoiceCommandOverrideConfig(localeIdentifier: "en-US", commandID: VoiceCommandPreset.moveCursorLeft.rawValue, aliases: ["move left", "cursor left", "go left"]),
            VoiceCommandOverrideConfig(localeIdentifier: "zh-CN", commandID: VoiceCommandPreset.moveCursorRight.rawValue, aliases: ["向右移动", "往右移动", "右移"]),
            VoiceCommandOverrideConfig(localeIdentifier: "en-US", commandID: VoiceCommandPreset.moveCursorRight.rawValue, aliases: ["move right", "cursor right", "go right"]),
            VoiceCommandOverrideConfig(localeIdentifier: "zh-CN", commandID: VoiceCommandPreset.selectLeft.rawValue, aliases: ["向左选择", "往左选择", "左选"]),
            VoiceCommandOverrideConfig(localeIdentifier: "en-US", commandID: VoiceCommandPreset.selectLeft.rawValue, aliases: ["select left", "extend left", "highlight left"]),
            VoiceCommandOverrideConfig(localeIdentifier: "zh-CN", commandID: VoiceCommandPreset.selectRight.rawValue, aliases: ["向右选择", "往右选择", "右选"]),
            VoiceCommandOverrideConfig(localeIdentifier: "en-US", commandID: VoiceCommandPreset.selectRight.rawValue, aliases: ["select right", "extend right", "highlight right"]),
            VoiceCommandOverrideConfig(localeIdentifier: "zh-CN", commandID: VoiceCommandPreset.rewriteFullText.rawValue, aliases: ["全文纠错优化", "优化全文", "全文润色"]),
            VoiceCommandOverrideConfig(localeIdentifier: "en-US", commandID: VoiceCommandPreset.rewriteFullText.rawValue, aliases: ["polish full text", "rewrite full text", "proofread full text"])
        ]
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
