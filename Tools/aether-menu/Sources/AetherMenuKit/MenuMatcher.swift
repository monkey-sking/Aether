import Foundation

public struct MatchResult: Sendable {
    public let command: MenuCommand
    public let score: Double
    public let reason: String

    public init(command: MenuCommand, score: Double, reason: String) {
        self.command = command
        self.score = score
        self.reason = reason
    }

    /// 0.85 以上视为高置信，可直接执行；0.6–0.85 建议向用户确认；以下不建议执行。
    public var confidence: Confidence {
        switch score {
        case 0.85...: return .high
        case 0.60..<0.85: return .medium
        default: return .low
        }
    }

    public enum Confidence: String, Sendable {
        case high
        case medium
        case low
    }
}

/// 把一句人类/agent 的意图，映射到某个 App 的具体菜单命令。
///
/// 打分阶梯（从强到弱）：
///   1.00  规范化后完全相等
///   0.94  概念相同（跨语言/同义词，如「清空废纸篓」→「清倒废纸篓」）
///   0.90  前缀匹配
///   0.84  词边界包含
///   0.78  包含
///   0.70  拼音包含
///   0.60  拼音首字母
///   0.45  子序列
///
/// 之后叠加微调：可点击 / 有快捷键 / 层级浅 / 标题长度接近，并惩罚动态项。
public enum MenuMatcher {

    public static func match(
        _ query: String,
        in commands: [MenuCommand],
        limit: Int = 10
    ) -> [MatchResult] {
        let normalizedQuery = MenuText.normalize(query)
        guard !normalizedQuery.isEmpty else { return [] }

        let queryConcept = MenuConcept.conceptID(for: query)
        let queryPinyin = MenuText.pinyin(normalizedQuery)
        let queryCompact = normalizedQuery.replacingOccurrences(of: " ", with: "")

        var results: [MatchResult] = []

        for command in commands {
            guard let (base, reason) = baseScore(
                command: command,
                normalizedQuery: normalizedQuery,
                queryCompact: queryCompact,
                queryConcept: queryConcept,
                queryPinyin: queryPinyin
            ) else { continue }

            var score = base
            score += adjustments(
                command: command,
                normalizedQuery: normalizedQuery,
                queryCompact: queryCompact
            )
            score = min(score, 1.0)

            results.append(MatchResult(command: command, score: score, reason: reason))
        }

        return results
            .sorted { lhs, rhs in
                if abs(lhs.score - rhs.score) > 0.001 { return lhs.score > rhs.score }
                if lhs.command.depth != rhs.command.depth { return lhs.command.depth < rhs.command.depth }
                return lhs.command.displayPath < rhs.command.displayPath
            }
            .prefix(limit)
            .map { $0 }
    }

    // MARK: - 基础得分

    private static func baseScore(
        command: MenuCommand,
        normalizedQuery: String,
        queryCompact: String,
        queryConcept: String?,
        queryPinyin: MenuText.PinyinForm
    ) -> (Double, String)? {
        let titleRaw = command.title
        let normalizedTitle = MenuText.normalize(titleRaw)
        let compactTitle = normalizedTitle.replacingOccurrences(of: " ", with: "")
        guard !normalizedTitle.isEmpty else { return nil }

        if normalizedTitle == normalizedQuery || compactTitle == queryCompact {
            return (1.00, "exact")
        }

        if let queryConcept, let titleConcept = MenuConcept.conceptID(for: titleRaw),
           queryConcept == titleConcept {
            return (0.94, "concept:\(queryConcept)")
        }

        if normalizedTitle.hasPrefix(normalizedQuery) || compactTitle.hasPrefix(queryCompact) {
            return (0.90, "prefix")
        }

        if hasWordBoundaryMatch(title: normalizedTitle, query: normalizedQuery) {
            return (0.84, "word-boundary")
        }

        if normalizedTitle.contains(normalizedQuery) || compactTitle.contains(queryCompact) {
            return (0.78, "contains")
        }

        let titlePinyin = MenuText.pinyin(normalizedTitle)
        if queryPinyin.full.count >= 2, titlePinyin.full.contains(queryPinyin.full) {
            return (0.70, "pinyin")
        }

        // 首字母缩写（"xjwjj" → 新建文件夹、"nf" → New Folder）。
        // 查询本身是纯字母时才启用，避免中文短词误走这条路径。
        let queryIsLatin = !queryCompact.isEmpty
            && queryCompact.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber) }
        if queryIsLatin, queryCompact.count >= 2 {
            if titlePinyin.initials == queryCompact {
                return (0.62, "initials-exact")
            }
            if titlePinyin.initials.hasPrefix(queryCompact) {
                return (0.58, "initials-prefix")
            }
            if titlePinyin.initials.contains(queryCompact) {
                return (0.50, "initials-contains")
            }
        }

        if normalizedQuery.count >= 2, MenuText.isSubsequence(normalizedQuery, of: normalizedTitle) {
            return (0.45, "subsequence")
        }

        return nil
    }

    /// 英文按空格分词 / 中文按整体，判断 query 是否落在标题的某个词边界上。
    private static func hasWordBoundaryMatch(title: String, query: String) -> Bool {
        guard title.contains(query) else { return false }
        guard let range = title.range(of: query) else { return false }
        let isAtStart = range.lowerBound == title.startIndex
        let isAtEnd = range.upperBound == title.endIndex
        let charBefore = isAtStart ? nil : title[title.index(before: range.lowerBound)]
        let charAfter = isAtEnd ? nil : title[range.upperBound]
        let boundary: (Character?) -> Bool = { char in
            guard let char else { return true }
            return char == " " || char == "(" || char == "["
        }
        return boundary(charBefore) || boundary(charAfter)
    }

    // MARK: - 微调

    private static func adjustments(
        command: MenuCommand,
        normalizedQuery: String,
        queryCompact: String
    ) -> Double {
        var delta = 0.0

        if command.enabled { delta += 0.04 }
        if command.shortcut != nil { delta += 0.03 }

        // 层级越浅越可能是用户意图
        delta += Double(max(0, 3 - command.depth)) * 0.015

        // 标题长度与查询接近时加分（避免「新建文件夹」被「使用“X”新建文件夹」抢走）
        let titleCompact = MenuText.normalize(command.title).replacingOccurrences(of: " ", with: "")
        let lengthDiff = abs(titleCompact.count - queryCompact.count)
        if lengthDiff <= 2 { delta += 0.03 }
        else if lengthDiff >= 6 { delta -= 0.04 }

        // 动态菜单项（含实体名/路径）通常是噪音
        if MenuText.looksDynamic(command.title) { delta -= 0.12 }

        // Apple 菜单里的系统级命令，除非查询本身就指向它们，否则降权
        if command.rootMenu == "Apple" || command.rootMenu == "苹果菜单" { delta -= 0.10 }

        return delta
    }
}
