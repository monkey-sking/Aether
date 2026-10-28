import Foundation

/// 文本规范化与拼音辅助。
public enum MenuText {

    /// 基础规范化：小写、去省略号、去弯引号、折叠空白。
    /// 保留中文与字母数字，不做分词。
    public static func normalize(_ raw: String) -> String {
        var s = raw.lowercased()

        // 省略号 / 省略号变体
        for token in ["…", "...", "⋯"] {
            s = s.replacingOccurrences(of: token, with: "")
        }
        // 弯引号（动态菜单项常含「拷贝“文件名”」这类内容）
        for token in ["\u{201C}", "\u{201D}", "\u{2018}", "\u{2019}", "\"", "'"] {
            s = s.replacingOccurrences(of: token, with: "")
        }
        // 全角空格、不间断空格
        s = s.replacingOccurrences(of: "\u{00A0}", with: " ")
        s = s.replacingOccurrences(of: "\u{3000}", with: " ")
        // 折叠连续空白
        s = s.split(whereSeparator: { $0 == " " || $0 == "\t" || $0 == "\n" })
            .joined(separator: " ")

        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public struct PinyinForm: Sendable {
        /// 连写全拼，如 "xinjianwenjianjia"
        public let full: String
        /// 每音节首字母，如 "xjwjj"
        public let initials: String
    }

    /// 转拼音。`toLatin` 会按音节插入空格，正好可以用来取首字母。
    public static func pinyin(_ raw: String) -> PinyinForm {
        let lowered = raw.lowercased()
        guard
            let latin = lowered.applyingTransform(.toLatin, reverse: false),
            let plain = latin.applyingTransform(.stripDiacritics, reverse: false)
        else {
            let compact = lowered.replacingOccurrences(of: " ", with: "")
            return PinyinForm(full: compact, initials: compact)
        }

        let tokens = plain
            .split(whereSeparator: { $0 == " " || $0 == "\t" || $0 == "\n" })
            .map(String.init)
        let full = tokens.joined()
        let initials = tokens.compactMap { $0.first }.map(String.init).joined()
        return PinyinForm(full: full, initials: initials)
    }

    /// 判断 `needle` 是否作为**独立词**出现在 `haystack` 中。
    ///
    /// 纯 ASCII 词要求前后是非字母数字边界，避免 "save" 命中 "SnapSave"。
    /// 中文（非 ASCII）词退化为普通包含判断。
    public static func containsAsTerm(_ haystack: String, _ needle: String) -> Bool {
        guard !needle.isEmpty, !haystack.isEmpty else { return false }
        let asciiOnly = needle.allSatisfy { $0.isASCII }
        guard asciiOnly else { return haystack.contains(needle) }

        var searchStart = haystack.startIndex
        while let range = haystack.range(of: needle, range: searchStart..<haystack.endIndex) {
            let leftOK: Bool = {
                guard range.lowerBound > haystack.startIndex else { return true }
                let previous = haystack[haystack.index(before: range.lowerBound)]
                return !(previous.isLetter || previous.isNumber)
            }()
            let rightOK: Bool = {
                guard range.upperBound < haystack.endIndex else { return true }
                let next = haystack[range.upperBound]
                return !(next.isLetter || next.isNumber)
            }()
            if leftOK && rightOK { return true }
            searchStart = haystack.index(range.lowerBound, offsetBy: 1)
        }
        return false
    }

    /// 判断 `small` 是否为 `big` 的子序列（按字符顺序）。
    public static func isSubsequence(_ small: String, of big: String) -> Bool {
        guard !small.isEmpty else { return false }
        var index = small.startIndex
        for character in big {
            if character == small[index] {
                index = small.index(after: index)
                if index == small.endIndex { return true }
            }
        }
        return false
    }

    /// 是否像「动态生成的菜单项」：含引号包裹的实体名，或含路径分隔符。
    public static func looksDynamic(_ raw: String) -> Bool {
        if raw.contains("\u{201C}") || raw.contains("\u{201D}") { return true }
        if raw.contains("/") && raw.count > 12 { return true }
        return false
    }
}
