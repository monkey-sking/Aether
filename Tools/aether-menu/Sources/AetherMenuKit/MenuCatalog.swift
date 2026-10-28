import AppKit
import ApplicationServices

/// 从运行中的 macOS App 读取完整菜单栏命令目录。
///
/// 这是 Aether `FrontmostAppCommandCatalog` 里最有价值的部分抽出来的：
/// 用 Accessibility API 递归遍历 AXMenuBar，产出结构化的命令清单。
/// Computer Use 类工具能"执行"菜单命令（invoke_menu），但要求先知道确切路径；
/// 这一层负责"发现"——把任意 App 的菜单变成 agent 可检索的目录。
public enum MenuCatalog {

    // MARK: - 查找目标 App

    public struct AppTarget {
        public let processIdentifier: pid_t
        public let bundleIdentifier: String
        public let displayName: String
    }

    /// 常见 App 的英文/中文别名 → bundle id。
    /// 系统 App 的 localizedName 会随系统语言变化（Finder 在中文系统叫「访达」），
    /// 只按显示名查找会失败，所以先过一层稳定别名。
    private static let bundleAliases: [String: String] = [
        "finder": "com.apple.finder", "访达": "com.apple.finder",
        "safari": "com.apple.Safari", "浏览器": "com.apple.Safari",
        "chrome": "com.google.Chrome", "谷歌浏览器": "com.google.Chrome",
        "terminal": "com.apple.Terminal", "终端": "com.apple.Terminal",
        "iterm": "com.googlecode.iterm2",
        "textedit": "com.apple.TextEdit", "文本编辑": "com.apple.TextEdit",
        "xcode": "com.apple.dt.Xcode",
        "notes": "com.apple.Notes", "备忘录": "com.apple.Notes",
        "mail": "com.apple.mail", "邮件": "com.apple.mail",
        "calendar": "com.apple.iCal", "日历": "com.apple.iCal",
        "music": "com.apple.Music", "音乐": "com.apple.Music",
        "photos": "com.apple.Photos", "照片": "com.apple.Photos",
        "preview": "com.apple.Preview", "预览": "com.apple.Preview",
        "system settings": "com.apple.systempreferences",
        "系统设置": "com.apple.systempreferences",
        "vscode": "com.microsoft.VSCode", "code": "com.microsoft.VSCode",
        "chatgpt": "com.openai.codex",
        "slack": "com.tinyspeck.slackmacgap",
        "wechat": "com.tencent.xinWeChat", "微信": "com.tencent.xinWeChat",
        "feishu": "com.electron.lark", "lark": "com.electron.lark", "飞书": "com.electron.lark",
        "figma": "com.figma.Desktop",
        "notion": "notion.id",
        "obsidian": "md.obsidian",
    ]

    /// 按 bundle id / 进程号 / 别名 / 名称片段查找运行中的应用。
    public static func resolveApp(_ query: String) -> AppTarget? {
        if let pid = Int32(query) {
            guard let app = NSRunningApplication(processIdentifier: pid) else { return nil }
            return appTarget(from: app)
        }

        let apps = NSWorkspace.shared.runningApplications.filter {
            $0.activationPolicy == .regular && !$0.isTerminated
        }

        if let app = apps.first(where: { $0.bundleIdentifier == query }) {
            return appTarget(from: app)
        }

        // 别名 → bundle id
        if let bundleID = bundleAliases[query.lowercased()],
           let app = apps.first(where: { $0.bundleIdentifier == bundleID }) {
            return appTarget(from: app)
        }
        let lowered = query.lowercased()
        if let app = apps.first(where: { ($0.localizedName ?? "").lowercased() == lowered }) {
            return appTarget(from: app)
        }
        if let app = apps.first(where: { ($0.localizedName ?? "").lowercased().contains(lowered) }) {
            return appTarget(from: app)
        }
        return nil
    }

    /// 当前前台 App。
    public static func frontmostApp() -> AppTarget? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        return appTarget(from: app)
    }

    public static func allRunningApps() -> [AppTarget] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && !$0.isTerminated }
            .map(appTarget(from:))
    }

    private static func appTarget(from app: NSRunningApplication) -> AppTarget {
        AppTarget(
            processIdentifier: app.processIdentifier,
            bundleIdentifier: app.bundleIdentifier ?? "",
            displayName: app.localizedName ?? app.bundleIdentifier ?? "?"
        )
    }

    // MARK: - 读取目录

    public struct Options {
        /// 是否包含 Apple 菜单（关于本机 / 系统设置 / 睡眠 等）。默认包含，但匹配时降权。
        public var includeAppleMenu: Bool
        /// 是否包含「服务」子菜单。默认排除（噪音极大且多为第三方注入项）。
        public var includeServices: Bool
        /// 是否包含「最近使用」类动态子菜单。默认排除。
        public var includeRecentItems: Bool
        /// 是否排除窗口菜单里的动态窗口标题。默认排除。
        public var excludeDynamicWindowTitles: Bool
        /// 是否只保留可点击项。默认保留全部（app 未聚焦时 enabled 不可靠）。
        public var onlyEnabled: Bool

        public init(
            includeAppleMenu: Bool = true,
            includeServices: Bool = false,
            includeRecentItems: Bool = false,
            excludeDynamicWindowTitles: Bool = true,
            onlyEnabled: Bool = false
        ) {
            self.includeAppleMenu = includeAppleMenu
            self.includeServices = includeServices
            self.includeRecentItems = includeRecentItems
            self.excludeDynamicWindowTitles = excludeDynamicWindowTitles
            self.onlyEnabled = onlyEnabled
        }

        public static let `default` = Options()
    }

    /// 读取指定 App 的完整菜单命令目录。
    public static func commands(
        for target: AppTarget,
        options: Options = .default
    ) -> [MenuCommand] {
        let axApp = AXUIElementCreateApplication(target.processIdentifier)

        guard let menuBar = AX.element(axApp, .menuBar) else {
            return []
        }

        // 先取窗口标题，用于剔除「窗口」菜单里的动态条目
        var windowTitles: Set<String> = []
        if options.excludeDynamicWindowTitles {
            for window in AX.array(axApp, .windows) {
                if let title = AX.string(window, .title), !title.isEmpty {
                    windowTitles.insert(title)
                }
            }
        }

        var results: [MenuCommand] = []
        walk(
            menu: menuBar,
            path: [],
            target: target,
            options: options,
            windowTitles: windowTitles,
            into: &results
        )
        return results
    }

    // MARK: - 递归遍历

    private static func walk(
        menu: AXUIElement,
        path: [String],
        target: AppTarget,
        options: Options,
        windowTitles: Set<String>,
        into results: inout [MenuCommand]
    ) {
        for item in AX.array(menu, .children) {
            let rawTitle = AX.string(item, .title) ?? ""
            let title = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
            // 空标题 = 分隔线
            guard !title.isEmpty else { continue }

            let currentPath = path + [title]

            if let submenu = submenu(of: item) {
                if shouldSkipSubmenu(currentPath, options: options) { continue }
                walk(
                    menu: submenu,
                    path: currentPath,
                    target: target,
                    options: options,
                    windowTitles: windowTitles,
                    into: &results
                )
                continue
            }

            if isNoise(currentPath, windowTitles: windowTitles, options: options) { continue }

            let enabled = AX.bool(item, .enabled) ?? true
            if options.onlyEnabled && !enabled { continue }

            results.append(
                MenuCommand(
                    path: currentPath,
                    title: title,
                    shortcut: shortcut(for: item),
                    enabled: enabled,
                    bundleIdentifier: target.bundleIdentifier,
                    processIdentifier: target.processIdentifier
                )
            )
        }
    }

    private static func submenu(of item: AXUIElement) -> AXUIElement? {
        for child in AX.array(item, .children) where AX.string(child, .role) == "AXMenu" {
            return child
        }
        return AX.element(item, .menu)
    }

    // MARK: - 噪音过滤

    private static func shouldSkipSubmenu(_ path: [String], options: Options) -> Bool {
        guard let root = path.first else { return false }

        if !options.includeAppleMenu, root == "Apple" || root == "苹果菜单" {
            return true
        }
        if !options.includeServices {
            if path.contains("服务") || path.contains("Services") { return true }
        }
        if !options.includeRecentItems {
            if path.contains("最近使用") || path.contains("Recent Items")
                || path.contains("打开最近使用") || path.contains("Open Recent") {
                return true
            }
        }
        return false
    }

    private static func isNoise(
        _ path: [String],
        windowTitles: Set<String>,
        options: Options
    ) -> Bool {
        guard let root = path.first else { return true }

        if !options.includeAppleMenu, root == "Apple" || root == "苹果菜单" { return true }

        if !options.includeServices, path.contains("服务") || path.contains("Services") {
            return true
        }

        if !options.includeRecentItems,
           path.contains("最近使用") || path.contains("Recent Items")
            || path.contains("打开最近使用") || path.contains("Open Recent") {
            return true
        }

        // 「窗口」菜单里混入的动态窗口标题：层级恰好是 [窗口, 标题] 且与某个真实窗口标题一致
        if options.excludeDynamicWindowTitles,
           root == "窗口" || root == "Window",
           path.count == 2 {
            if windowTitles.contains(path[1]) { return true }
        }

        return false
    }

    // MARK: - 快捷键解析

    /// AXMenuItemCmdModifiers 语义（已实测验证）：
    /// 0 = 只有 ⌘；1<<0 = ⇧；1<<1 = ⌥；1<<2 = ⌃；1<<3 = 完全无修饰键
    static func shortcutText(char: String, modifiers: Int?, virtualKey: Int?) -> String? {
        guard !char.isEmpty || virtualKey != nil else { return nil }
        let m = modifiers ?? 0

        var parts: [String] = []
        let suppressCommand = (m & 8) != 0
        if m & 4 != 0 { parts.append("ctrl") }
        if m & 2 != 0 { parts.append("opt") }
        if m & 1 != 0 { parts.append("shift") }
        if !suppressCommand { parts.append("cmd") }

        let key: String
        if let vk = virtualKey, let name = virtualKeyNames[vk] {
            key = name
        } else if !char.isEmpty {
            key = char.lowercased()
        } else {
            return nil
        }
        parts.append(key)
        return parts.joined(separator: "+")
    }

    private static func shortcut(for element: AXUIElement) -> String? {
        let char = AX.string(element, .menuItemCmdChar) ?? ""
        let modifiers = AX.int(element, .menuItemCmdModifiers)
        let virtualKey = AX.int(element, .menuItemCmdVirtualKey)
        return shortcutText(char: char, modifiers: modifiers, virtualKey: virtualKey)
    }

    /// macOS 虚拟键码 → 可读名称（与 CGEvent / 快捷键投递侧保持一致）
    static let virtualKeyNames: [Int: String] = [
        0: "a", 1: "s", 2: "d", 3: "f", 4: "h", 5: "g", 6: "z", 7: "x",
        8: "c", 9: "v", 11: "b", 12: "q", 13: "w", 14: "e", 15: "r",
        16: "y", 17: "t", 18: "1", 19: "2", 20: "3", 21: "4", 22: "6",
        23: "5", 24: "=", 25: "9", 26: "7", 27: "-", 28: "8", 29: "0",
        30: "]", 31: "o", 32: "u", 33: "[", 34: "i", 35: "p", 36: "return",
        37: "l", 38: "j", 39: "'", 40: "k", 41: ";", 42: "\\", 43: ",",
        44: "/", 45: "n", 46: "m", 47: ".", 48: "tab", 49: "space", 50: "`",
        51: "delete", 53: "escape", 96: "f5", 97: "f6", 98: "f7", 99: "f3",
        100: "f8", 101: "f9", 103: "f11", 105: "f13", 107: "f14", 109: "f10",
        111: "f12", 113: "f15", 115: "home", 116: "pageup", 117: "forwarddelete",
        118: "f4", 119: "end", 120: "f2", 121: "pagedown", 122: "f1",
        123: "left", 124: "right", 125: "down", 126: "up",
    ]
}
