import Foundation

/// 一条可执行的菜单命令。
public struct MenuCommand: Codable, Equatable, Sendable {
    /// 菜单层级路径，如 ["文件", "新建文件夹"]
    public let path: [String]
    /// 末级菜单项标题（保留原文，含省略号）
    public let title: String
    /// 规范化后的按键描述，如 "shift+cmd+n"；无快捷键为 nil
    public let shortcut: String?
    /// 菜单项当前是否可点（App 未聚焦时大量项会是 false）
    public let enabled: Bool
    /// 该菜单项所属 App 的 bundle identifier
    public let bundleIdentifier: String
    /// 该菜单项所属 App 的进程号（执行时用于定向投递快捷键）
    public let processIdentifier: Int32

    public init(
        path: [String],
        title: String,
        shortcut: String?,
        enabled: Bool,
        bundleIdentifier: String,
        processIdentifier: Int32
    ) {
        self.path = path
        self.title = title
        self.shortcut = shortcut
        self.enabled = enabled
        self.bundleIdentifier = bundleIdentifier
        self.processIdentifier = processIdentifier
    }

    /// 人类可读的完整路径
    public var displayPath: String { path.joined(separator: " > ") }

    public var rootMenu: String { path.first ?? "" }

    public var depth: Int { path.count }
}
