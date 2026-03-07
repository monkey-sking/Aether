import Foundation
import os.log
import Cocoa

enum VoiceCommandPreset: String, CaseIterable, Identifiable {
    case clickLeft
    case clickRight
    case doubleClick
    case startPointer
    case stopPointer
    case recenter
    case scrollUp
    case scrollDown
    case scrollTop
    case scrollBottom
    case dragStart
    case dragEnd
    case undo
    case paste
    case lockConnection
    case unlockConnection

    var id: String { rawValue }

    var intent: VoiceIntent {
        switch self {
        case .clickLeft:
            return .clickLeft
        case .clickRight:
            return .clickRight
        case .doubleClick:
            return .doubleClick
        case .startPointer:
            return .startPointer
        case .stopPointer:
            return .stopPointer
        case .recenter:
            return .recenter
        case .scrollUp:
            return .scroll(0, -300)
        case .scrollDown:
            return .scroll(0, 300)
        case .scrollTop:
            return .scrollToWeb("top")
        case .scrollBottom:
            return .scrollToWeb("bottom")
        case .dragStart:
            return .dragStart
        case .dragEnd:
            return .dragEnd
        case .undo:
            return .undo
        case .paste:
            return .paste
        case .lockConnection:
            return .lockConnection
        case .unlockConnection:
            return .unlockConnection
        }
    }

    var isTypingSafe: Bool {
        switch self {
        case .undo, .paste:
            return true
        default:
            return false
        }
    }

    func title(locale: Locale = .current) -> String {
        let isChinese = locale.identifier.hasPrefix("zh")
        switch self {
        case .clickLeft:
            return isChinese ? "点击" : "Click"
        case .clickRight:
            return isChinese ? "右键" : "Right Click"
        case .doubleClick:
            return isChinese ? "双击" : "Double Click"
        case .startPointer:
            return isChinese ? "开始指针" : "Start Pointer"
        case .stopPointer:
            return isChinese ? "停止指针" : "Stop Pointer"
        case .recenter:
            return isChinese ? "回中 / 校准" : "Recenter"
        case .scrollUp:
            return isChinese ? "向上滚动" : "Scroll Up"
        case .scrollDown:
            return isChinese ? "向下滚动" : "Scroll Down"
        case .scrollTop:
            return isChinese ? "滚动到顶部" : "Scroll To Top"
        case .scrollBottom:
            return isChinese ? "滚动到底部" : "Scroll To Bottom"
        case .dragStart:
            return isChinese ? "开始拖拽" : "Start Drag"
        case .dragEnd:
            return isChinese ? "结束拖拽" : "End Drag"
        case .undo:
            return isChinese ? "撤销" : "Undo"
        case .paste:
            return isChinese ? "粘贴" : "Paste"
        case .lockConnection:
            return isChinese ? "锁定连接" : "Lock Connection"
        case .unlockConnection:
            return isChinese ? "解锁连接" : "Unlock Connection"
        }
    }
}

struct VoiceCommandOverrideConfig: Codable, Identifiable, Equatable {
    var localeIdentifier: String
    var commandID: String
    var aliases: [String]

    var id: String { "\(localeIdentifier)::\(commandID)" }
}

enum VoiceIntent: Equatable {
    case clickLeft
    case clickRight
    case doubleClick
    case startPointer
    case stopPointer
    case recenter
    case scroll(Int, Int) // dx, dy
    case scrollToWeb(String) // "top", "bottom"
    case dragStart
    case dragEnd
    case undo
    case paste
    case lockConnection
    case unlockConnection
    case dictation(String)
    case unknown(String)
}

extension VoiceIntent: Sendable {}

enum VoiceCommandConfidence: Int, Comparable {
    case low = 0
    case medium = 1
    case high = 2

    static func < (lhs: VoiceCommandConfidence, rhs: VoiceCommandConfidence) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

struct VoiceCommandDecision {
    let intent: VoiceIntent
    let confidence: VoiceCommandConfidence
    let reason: String
}

final class VoiceCommandRouter {
    private struct CommandMatch {
        let preset: VoiceCommandPreset
        let confidence: VoiceCommandConfidence
        let reason: String
    }

    var overrides: [VoiceCommandOverrideConfig] = []
    var languageTermsOverrides: [VoiceLanguageTermsOverrideConfig] = []

    enum RoutingBias {
        case neutral
        case dictationPreferred // Cursor in input field
        case commandPreferred   // Cursor not in input field
        case forceDictation     // Explicit user gesture (Tilt Left)
        case forceCommand      // Explicit user gesture (Tilt Right)
    }

    func route(transcript raw: String, bias: RoutingBias = .neutral, localeIdentifier: String = Locale.current.identifier) -> VoiceIntent {
        routeDetailed(transcript: raw, bias: bias, localeIdentifier: localeIdentifier).intent
    }

    func routeDetailed(transcript raw: String, bias: RoutingBias = .neutral, localeIdentifier: String = Locale.current.identifier) -> VoiceCommandDecision {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return VoiceCommandDecision(intent: .unknown(raw), confidence: .low, reason: "empty")
        }

        // Normalize for command matching
        let s = trimmed.lowercased().replacingOccurrences(of: " ", with: "")
        
        os_log("Router: Input [%{public}@] with Bias [%{public}@]. Normalized: [%{public}@]", 
               log: GlobalLogger.router, type: .debug, trimmed, String(describing: bias), s)

        // --- 1. Explicit Overrides (Highest Priority) ---
        if bias == .forceDictation {
            return VoiceCommandDecision(intent: .dictation(trimmed), confidence: .high, reason: "forced-dictation-bias")
        }
        
        // --- 2. Normalized Force Prefixes ---
        let isForceCommand = hasCommandPrefix(s, localeIdentifier: localeIdentifier) || bias == .forceCommand
        let isForceDictation = hasDictationPrefix(s, localeIdentifier: localeIdentifier)

        if isForceDictation {
            let payload = stripDictationPrefix(from: trimmed, localeIdentifier: localeIdentifier)
            return VoiceCommandDecision(intent: .dictation(payload.isEmpty ? trimmed : payload), confidence: .high, reason: "forced-dictation-prefix")
        }

        // --- 3. Smart Routing Logic ---
        // If we are in an input field (dictationPreferred) and NOT explicitly forcing a command,
        // we should be very conservative about executing commands.
        if bias == .dictationPreferred && !isForceCommand {
            if let safeMatch = matchCommand(
                normalized: s,
                raw: trimmed,
                localeIdentifier: localeIdentifier,
                filter: { $0.isTypingSafe }
            ) {
                return VoiceCommandDecision(
                    intent: safeMatch.preset.intent,
                    confidence: safeMatch.confidence,
                    reason: "typing-safe-\(safeMatch.reason)"
                )
            }

            // Otherwise, everything is treated as dictation in an input field
            if !isForceDictation {
                return VoiceCommandDecision(intent: .dictation(trimmed), confidence: .high, reason: "typing-preferred")
            }
        }

        // --- 4. Local Command Matching (Standard Workflow) ---
        if let match = matchCommand(normalized: s, raw: trimmed, localeIdentifier: localeIdentifier) {
            return VoiceCommandDecision(intent: match.preset.intent, confidence: match.confidence, reason: match.reason)
        }

        // --- 5. Default Fallback ---
        if isForceCommand {
            return VoiceCommandDecision(intent: .unknown(trimmed), confidence: .low, reason: "forced-command-no-match")
        }
        return VoiceCommandDecision(intent: .dictation(trimmed), confidence: .low, reason: "fallback-dictation")
    }

    static func defaultAliases(for preset: VoiceCommandPreset, localeIdentifier: String) -> [String] {
        let locale = canonicalLocaleIdentifier(localeIdentifier).lowercased()
        let useChinese = locale.hasPrefix("zh")

        let chinese: [String]
        let english: [String]

        switch preset {
        case .clickLeft:
            chinese = ["点击", "单击"]
            english = ["click"]
        case .clickRight:
            chinese = ["右键"]
            english = ["right click", "rightclick", "context"]
        case .doubleClick:
            chinese = ["双击"]
            english = ["double click", "doubleclick"]
        case .startPointer:
            chinese = ["开始", "继续"]
            english = ["start", "resume"]
        case .stopPointer:
            chinese = ["停止", "暂停控制"]
            english = ["stop", "pause control"]
        case .recenter:
            chinese = ["校准", "居中", "重置"]
            english = ["recenter", "reset"]
        case .scrollUp:
            chinese = ["向上", "上滚"]
            english = ["scroll up", "up"]
        case .scrollDown:
            chinese = ["向下", "下滚"]
            english = ["scroll down", "down"]
        case .scrollTop:
            chinese = ["到顶"]
            english = ["top", "scroll top"]
        case .scrollBottom:
            chinese = ["到底"]
            english = ["bottom", "scroll bottom"]
        case .dragStart:
            chinese = ["拖", "抓住"]
            english = ["drag"]
        case .dragEnd:
            chinese = ["放", "松开"]
            english = ["drop", "release"]
        case .undo:
            chinese = ["撤销", "撤回"]
            english = ["undo"]
        case .paste:
            chinese = ["粘贴"]
            english = ["paste"]
        case .lockConnection:
            chinese = ["锁定"]
            english = ["lock", "lock airpods", "lockairpods"]
        case .unlockConnection:
            chinese = ["解锁"]
            english = ["unlock", "unlock airpods", "unlockairpods"]
        }

        return uniqueAliases((useChinese ? chinese + english : english) + (useChinese ? [] : chinese))
    }

    static func effectiveAliases(
        for preset: VoiceCommandPreset,
        localeIdentifier: String,
        overrides: [VoiceCommandOverrideConfig]
    ) -> [String] {
        if let override = overrideEntry(for: preset, localeIdentifier: localeIdentifier, overrides: overrides),
           !override.aliases.isEmpty {
            return uniqueAliases(override.aliases)
        }
        return defaultAliases(for: preset, localeIdentifier: localeIdentifier)
    }

    func contextualStrings(for localeIdentifier: String) -> [String] {
        var ordered: [String] = []
        var seen = Set<String>()

        for prefix in commandPrefixes(localeIdentifier: localeIdentifier) + dictationPrefixes(localeIdentifier: localeIdentifier) {
            let normalized = prefix.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalized.isEmpty else { continue }
            let key = normalized.lowercased()
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            ordered.append(normalized)
        }

        for preset in VoiceCommandPreset.allCases {
            for alias in Self.effectiveAliases(for: preset, localeIdentifier: localeIdentifier, overrides: overrides) {
                let normalized = alias.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !normalized.isEmpty else { continue }
                let key = normalized.lowercased()
                guard !seen.contains(key) else { continue }
                seen.insert(key)
                ordered.append(normalized)
            }
        }

        return ordered
    }

    private func matchCommand(
        normalized: String,
        raw: String,
        localeIdentifier: String,
        filter: (VoiceCommandPreset) -> Bool = { _ in true }
    ) -> CommandMatch? {
        let candidates = VoiceCommandPreset.allCases.filter(filter)

        for preset in candidates {
            for alias in normalizedAliases(for: preset, localeIdentifier: localeIdentifier) {
                if normalized == alias {
                    return CommandMatch(preset: preset, confidence: .high, reason: "exact-\(preset.rawValue)")
                }
            }
        }

        for preset in candidates {
            for alias in normalizedAliases(for: preset, localeIdentifier: localeIdentifier) {
                if normalized.contains(alias) {
                    return CommandMatch(preset: preset, confidence: .medium, reason: "contains-\(preset.rawValue)")
                }
            }
        }

        let pinyin = raw.pinyin
        for preset in candidates {
            for alias in pinyinAliases(for: preset, localeIdentifier: localeIdentifier) {
                if pinyin.contains(alias) {
                    return CommandMatch(preset: preset, confidence: .low, reason: "pinyin-\(preset.rawValue)")
                }
            }
        }

        return nil
    }

    private func normalizedAliases(for preset: VoiceCommandPreset, localeIdentifier: String) -> [String] {
        Self.effectiveAliases(for: preset, localeIdentifier: localeIdentifier, overrides: overrides)
            .map(normalizeMatchString)
            .filter { !$0.isEmpty }
    }

    private func pinyinAliases(for preset: VoiceCommandPreset, localeIdentifier: String) -> [String] {
        Self.effectiveAliases(for: preset, localeIdentifier: localeIdentifier, overrides: overrides)
            .map { $0.pinyin }
            .map(normalizeMatchString)
            .filter { !$0.isEmpty }
    }

    private func hasCommandPrefix(_ normalized: String, localeIdentifier: String) -> Bool {
        commandPrefixes(localeIdentifier: localeIdentifier).contains { normalized.hasPrefix(normalizeMatchString($0)) }
    }

    private func hasDictationPrefix(_ normalized: String, localeIdentifier: String) -> Bool {
        dictationPrefixes(localeIdentifier: localeIdentifier).contains { normalized.hasPrefix(normalizeMatchString($0)) }
    }

    private func stripDictationPrefix(from raw: String, localeIdentifier: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowercase = trimmed.lowercased()
        let prefixes = dictationPrefixes(localeIdentifier: localeIdentifier)

        for prefix in prefixes {
            if lowercase.hasPrefix(prefix) {
                let dropCount = prefix.count
                let suffix = trimmed.dropFirst(dropCount).trimmingCharacters(in: .whitespacesAndNewlines)
                return String(suffix)
            }
        }

        return trimmed
    }

    private func commandPrefixes(localeIdentifier: String) -> [String] {
        if let override = languageTermsOverride(for: localeIdentifier),
           !override.commandPrefixes.isEmpty {
            return uniqueLanguageTerms(override.commandPrefixes)
        }
        return Self.defaultCommandPrefixes(for: localeIdentifier)
    }

    private func dictationPrefixes(localeIdentifier: String) -> [String] {
        if let override = languageTermsOverride(for: localeIdentifier),
           !override.dictationPrefixes.isEmpty {
            return uniqueLanguageTerms(override.dictationPrefixes)
        }
        return Self.defaultDictationPrefixes(for: localeIdentifier)
    }

    private func normalizeMatchString(_ raw: String) -> String {
        raw
            .lowercased()
            .components(separatedBy: .whitespacesAndNewlines)
            .joined()
    }

    private static func uniqueAliases(_ aliases: [String]) -> [String] {
        var ordered: [String] = []
        var seen = Set<String>()

        for alias in aliases {
            let trimmed = alias.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let key = trimmed.lowercased()
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            ordered.append(trimmed)
        }

        return ordered
    }

    private static func overrideEntry(
        for preset: VoiceCommandPreset,
        localeIdentifier: String,
        overrides: [VoiceCommandOverrideConfig]
    ) -> VoiceCommandOverrideConfig? {
        let raw = localeIdentifier
        let canonical = canonicalLocaleIdentifier(localeIdentifier)
        return overrides.first(where: { $0.localeIdentifier == raw && $0.commandID == preset.rawValue }) ??
            overrides.first(where: { $0.localeIdentifier == canonical && $0.commandID == preset.rawValue })
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

    static func defaultCommandPrefixes(for localeIdentifier: String) -> [String] {
        canonicalLocaleIdentifier(localeIdentifier).lowercased().hasPrefix("zh")
            ? ["指令", "command"]
            : ["command", "指令"]
    }

    static func defaultDictationPrefixes(for localeIdentifier: String) -> [String] {
        canonicalLocaleIdentifier(localeIdentifier).lowercased().hasPrefix("zh")
            ? ["输入", "写", "input", "type"]
            : ["input", "type", "输入", "写"]
    }

    private func languageTermsOverride(for localeIdentifier: String) -> VoiceLanguageTermsOverrideConfig? {
        let raw = localeIdentifier
        let canonical = Self.canonicalLocaleIdentifier(localeIdentifier)
        return languageTermsOverrides.first(where: { $0.localeIdentifier == raw }) ??
            languageTermsOverrides.first(where: { $0.localeIdentifier == canonical })
    }

    private func uniqueLanguageTerms(_ items: [String]) -> [String] {
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
}

// MARK: - Pinyin Helper
extension String {
    var pinyin: String {
        // "你好" -> "nǐ hǎo" -> "ni hao" -> "nihao"
        return self
            .applyingTransform(.toLatin, reverse: false)?
            .applyingTransform(.stripDiacritics, reverse: false)?
            .lowercased()
            .replacingOccurrences(of: " ", with: "") ?? self.lowercased()
    }
}
