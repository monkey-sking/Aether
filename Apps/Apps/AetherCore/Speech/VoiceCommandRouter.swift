import Foundation
import os.log
import Cocoa
import Carbon.HIToolbox

struct FrontmostAppCommand: Identifiable, Equatable {
    let processIdentifier: pid_t
    let bundleIdentifier: String
    let appName: String
    let menuPath: [String]
    let title: String
    let shortcut: HotkeyBinding
    let aliases: [String]
    let isEnabled: Bool

    init(
        processIdentifier: pid_t,
        bundleIdentifier: String,
        appName: String,
        menuPath: [String],
        title: String,
        shortcut: HotkeyBinding,
        aliases: [String],
        isEnabled: Bool = true
    ) {
        self.processIdentifier = processIdentifier
        self.bundleIdentifier = bundleIdentifier
        self.appName = appName
        self.menuPath = menuPath
        self.title = title
        self.shortcut = shortcut
        self.aliases = aliases
        self.isEnabled = isEnabled
    }

    var id: String {
        ([bundleIdentifier, menuPath.joined(separator: ">"), title, shortcut.displayString])
            .joined(separator: "::")
    }

    var displayPath: String {
        if menuPath.isEmpty { return title }
        return (menuPath + [title]).joined(separator: " > ")
    }
}

extension FrontmostAppCommand: Sendable {}

struct CustomAppShortcutRule: Codable, Identifiable, Equatable {
    var id: String
    var isEnabled: Bool
    var bundleIdentifier: String
    var title: String
    var aliases: [String]
    var shortcut: HotkeyBinding

    init(
        id: String = UUID().uuidString,
        isEnabled: Bool = true,
        bundleIdentifier: String,
        title: String,
        aliases: [String] = [],
        shortcut: HotkeyBinding
    ) {
        self.id = id
        self.isEnabled = isEnabled
        self.bundleIdentifier = bundleIdentifier
        self.title = title
        self.aliases = aliases
        self.shortcut = shortcut
    }

    func matches(bundleIdentifier candidate: String) -> Bool {
        bundleIdentifier.caseInsensitiveCompare(candidate) == .orderedSame
    }

    func makeCommand(processIdentifier: pid_t, appName: String) -> FrontmostAppCommand {
        FrontmostAppCommand(
            processIdentifier: processIdentifier,
            bundleIdentifier: bundleIdentifier,
            appName: appName,
            menuPath: [AppLocalization.isChinese ? "自定义规则" : "Custom Rules"],
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            shortcut: shortcut,
            aliases: effectiveAliases,
            isEnabled: true
        )
    }

    var effectiveAliases: [String] {
        VoiceCommandRouter.uniqueAliases(
            [title] + aliases.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        )
    }
}

extension CustomAppShortcutRule: Sendable {}

struct FrontmostAppCommandSnapshot: Equatable, Sendable {
    let processIdentifier: pid_t
    let bundleIdentifier: String
    let appName: String
    let commands: [FrontmostAppCommand]
}

func mergeFrontmostAppCommandSnapshot(
    snapshot: FrontmostAppCommandSnapshot?,
    customRules: [CustomAppShortcutRule],
    frontmostApp: NSRunningApplication? = NSWorkspace.shared.frontmostApplication
) -> FrontmostAppCommandSnapshot? {
    let processIdentifier = snapshot?.processIdentifier ?? frontmostApp?.processIdentifier ?? 0
    let bundleIdentifier = snapshot?.bundleIdentifier ?? frontmostApp?.bundleIdentifier ?? ""
    let appName = snapshot?.appName ?? frontmostApp?.localizedName ?? bundleIdentifier

    guard !bundleIdentifier.isEmpty else { return snapshot }

    let customCommands = customRules
        .filter { $0.isEnabled && $0.matches(bundleIdentifier: bundleIdentifier) }
        .map { $0.makeCommand(processIdentifier: processIdentifier, appName: appName) }

    let customKeys = Set(customCommands.map { semanticFrontmostCommandKey($0) })
    let baseCommands = (snapshot?.commands ?? []).filter { !customKeys.contains(semanticFrontmostCommandKey($0)) }
    let merged = customCommands + baseCommands

    guard !merged.isEmpty || snapshot != nil else { return nil }

    return FrontmostAppCommandSnapshot(
        processIdentifier: processIdentifier,
        bundleIdentifier: bundleIdentifier,
        appName: appName,
        commands: merged
    )
}

private func semanticFrontmostCommandKey(_ command: FrontmostAppCommand) -> String {
    let title = command.title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    return "\(command.bundleIdentifier.lowercased())::\(title)::\(command.shortcut.keyCode)::\(command.shortcut.modifiers)"
}

@MainActor
final class FrontmostAppCommandCatalog: ObservableObject {
    static let shared = FrontmostAppCommandCatalog()
    private static let axMenuAttribute = "AXMenu" as CFString
    private static let maxTraversalDepth = 12
    private static let browserBundleIdentifiers: Set<String> = [
        "com.apple.Safari",
        "com.google.Chrome",
        "com.google.Chrome.beta",
        "com.google.Chrome.canary",
        "com.brave.Browser",
        "company.thebrowser.Browser",
        "com.kagi.kagimacOS",
        "com.microsoft.edgemac",
        "com.microsoft.edgemac.Beta",
        "com.microsoft.edgemac.Dev",
        "com.microsoft.edgemac.Canary",
        "org.mozilla.firefox"
    ]
    private static let editorBundleIdentifiers: Set<String> = [
        "com.microsoft.VSCode",
        "com.microsoft.VSCodeInsiders",
        "com.todesktop.230313mzl4w4u92",
        "com.zed.Zed",
        "com.apple.dt.Xcode"
    ]
    private static let terminalBundleIdentifiers: Set<String> = [
        "com.apple.Terminal",
        "com.googlecode.iterm2",
        "com.github.wez.wezterm",
        "dev.warp.Warp-Stable"
    ]
    private static let collaborationBundleIdentifiers: Set<String> = [
        "com.tinyspeck.slackmacgap",
        "notion.id",
        "com.hnc.Discord"
    ]
    private static let jetBrainsBundlePrefixes = [
        "com.jetbrains."
    ]

    private struct AliasRule {
        let keywords: [String]
        let aliases: [String]
    }

    private struct SupplementalCommandTemplate {
        let sectionTitle: String
        let subgroupTitle: String
        let title: String
        let shortcut: HotkeyBinding
        let aliases: [String]
    }

    private static let commandCharacterKeyCodes: [String: Int] = [
        "a": kVK_ANSI_A, "b": kVK_ANSI_B, "c": kVK_ANSI_C, "d": kVK_ANSI_D,
        "e": kVK_ANSI_E, "f": kVK_ANSI_F, "g": kVK_ANSI_G, "h": kVK_ANSI_H,
        "i": kVK_ANSI_I, "j": kVK_ANSI_J, "k": kVK_ANSI_K, "l": kVK_ANSI_L,
        "m": kVK_ANSI_M, "n": kVK_ANSI_N, "o": kVK_ANSI_O, "p": kVK_ANSI_P,
        "q": kVK_ANSI_Q, "r": kVK_ANSI_R, "s": kVK_ANSI_S, "t": kVK_ANSI_T,
        "u": kVK_ANSI_U, "v": kVK_ANSI_V, "w": kVK_ANSI_W, "x": kVK_ANSI_X,
        "y": kVK_ANSI_Y, "z": kVK_ANSI_Z,
        "0": kVK_ANSI_0, "1": kVK_ANSI_1, "2": kVK_ANSI_2, "3": kVK_ANSI_3,
        "4": kVK_ANSI_4, "5": kVK_ANSI_5, "6": kVK_ANSI_6, "7": kVK_ANSI_7,
        "8": kVK_ANSI_8, "9": kVK_ANSI_9,
        "=": kVK_ANSI_Equal, "-": kVK_ANSI_Minus,
        "[": kVK_ANSI_LeftBracket, "]": kVK_ANSI_RightBracket, "\\": kVK_ANSI_Backslash,
        ";": kVK_ANSI_Semicolon, "'": kVK_ANSI_Quote, ",": kVK_ANSI_Comma,
        ".": kVK_ANSI_Period, "/": kVK_ANSI_Slash, "`": kVK_ANSI_Grave
    ]

    private static let aliasRules: [AliasRule] = [
        AliasRule(
            keywords: ["close", "tab"],
            aliases: ["close tab", "close current tab", "关闭标签", "关闭当前标签", "关掉当前标签"]
        ),
        AliasRule(
            keywords: ["next", "tab"],
            aliases: ["next tab", "switch to next tab", "下一个标签", "切换到下一个标签", "切到下个标签"]
        ),
        AliasRule(
            keywords: ["previous", "tab"],
            aliases: ["previous tab", "last tab", "上一个标签", "切换到上一个标签", "切到上个标签"]
        ),
        AliasRule(
            keywords: ["new", "tab"],
            aliases: ["new tab", "open tab", "新建标签", "打开新标签"]
        ),
        AliasRule(
            keywords: ["reopen", "tab"],
            aliases: ["reopen tab", "restore tab", "恢复标签", "重新打开标签"]
        ),
        AliasRule(
            keywords: ["reload"],
            aliases: ["reload page", "refresh page", "刷新页面", "重新加载页面"]
        ),
        AliasRule(
            keywords: ["refresh"],
            aliases: ["reload page", "refresh page", "刷新页面", "重新加载页面"]
        ),
        AliasRule(
            keywords: ["close", "window"],
            aliases: ["close window", "关闭窗口"]
        ),
        AliasRule(
            keywords: ["find"],
            aliases: ["find", "search in page", "查找", "页面查找"]
        )
    ]

    private static let bilingualAliasGroups: [[String]] = [
        ["file", "文件"],
        ["edit", "编辑"],
        ["view", "视图"],
        ["window", "窗口"],
        ["help", "帮助"],
        ["history", "历史", "历史记录"],
        ["bookmarks", "书签"],
        ["go", "跳转", "导航"],
        ["navigate", "跳转", "导航"],
        ["tab", "标签", "标签页"],
        ["tabs", "标签", "标签页"],
        ["new", "新建"],
        ["open", "打开"],
        ["close", "关闭"],
        ["copy", "复制"],
        ["cut", "剪切"],
        ["paste", "粘贴"],
        ["undo", "撤销", "撤回"],
        ["redo", "重做", "恢复上一步", "反撤销"],
        ["select all", "全选", "全部选中"],
        ["save", "保存"],
        ["save as", "另存为"],
        ["print", "打印"],
        ["delete", "删除"],
        ["rename", "重命名"],
        ["find", "查找", "搜索"],
        ["search", "搜索", "查找"],
        ["replace", "替换"],
        ["replace all", "全部替换"],
        ["refresh", "刷新", "重新加载"],
        ["reload", "刷新", "重新加载"],
        ["preferences", "settings", "偏好设置"],
        ["new file", "新建文件"],
        ["open file", "打开文件"],
        ["new document", "新建文稿", "新建文档"],
        ["new tab", "新建标签", "新建标签页"],
        ["close tab", "关闭标签", "关闭标签页", "关闭当前标签"],
        ["next tab", "下一个标签", "下一个标签页"],
        ["previous tab", "上一个标签", "上一个标签页"],
        ["reopen closed tab", "恢复已关闭标签页", "重新打开标签", "恢复标签"],
        ["refresh page", "刷新页面", "重新加载页面"],
        ["find in page", "在页面中查找", "页面查找"],
        ["focus address bar", "address bar", "聚焦地址栏", "切到地址栏"],
        ["new window", "新建窗口"],
        ["close window", "关闭窗口"],
        ["command palette", "命令面板"],
        ["quick open", "快速打开"],
        ["search everywhere", "搜索所有地方", "全局搜索"],
        ["search project", "搜索项目", "全局搜索"],
        ["replace in project", "替换项目", "全局替换", "项目替换"],
        ["quick switcher", "快速切换", "切换频道", "切换服务器"],
        ["search messages", "搜索消息", "Slack 搜索"],
        ["new message", "新建消息", "写消息"],
        ["new page", "新建页面", "创建页面"],
        ["command menu", "命令菜单", "斜杠菜单"],
        ["split pane", "垂直分屏", "终端分屏", "分屏"],
        ["command search", "命令搜索", "搜索命令"]
    ]

    private static let bilingualAliasLookup: [String: [String]] = {
        var lookup: [String: Set<String>] = [:]

        for group in bilingualAliasGroups {
            let uniqueGroup = VoiceCommandRouter.uniqueAliases(group)
            for term in uniqueGroup {
                let key = normalizedAliasLookupKey(term)
                guard !key.isEmpty else { continue }

                var related = lookup[key, default: []]
                for candidate in uniqueGroup where normalizedAliasLookupKey(candidate) != key {
                    related.insert(candidate)
                }
                lookup[key] = related
            }
        }

        return lookup.mapValues { Array($0) }
    }()

    private static let commandModifier: UInt64 = CGEventFlags.maskCommand.rawValue
    private static let commandShiftModifier: UInt64 = CGEventFlags.maskCommand.rawValue | CGEventFlags.maskShift.rawValue
    private static let commandControlModifier: UInt64 = CGEventFlags.maskCommand.rawValue | CGEventFlags.maskControl.rawValue
    private static let commandOptionModifier: UInt64 = CGEventFlags.maskCommand.rawValue | CGEventFlags.maskAlternate.rawValue
    private static let commandOptionShiftModifier: UInt64 = CGEventFlags.maskCommand.rawValue | CGEventFlags.maskAlternate.rawValue | CGEventFlags.maskShift.rawValue
    private static let controlModifier: UInt64 = CGEventFlags.maskControl.rawValue
    private static let controlShiftModifier: UInt64 = CGEventFlags.maskControl.rawValue | CGEventFlags.maskShift.rawValue
    private static let shiftModifier: UInt64 = CGEventFlags.maskShift.rawValue

    @Published private(set) var snapshot: FrontmostAppCommandSnapshot?

    private var lastRefreshAt: Date = .distantPast
    private var observedPID: pid_t = 0
    private let menuItemModifierNone = 0
    private let menuItemModifierShift = 1 << 0
    private let menuItemModifierOption = 1 << 1
    private let menuItemModifierControl = 1 << 2
    private let menuItemModifierNoCommand = 1 << 3

    private init() {
        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(
            self,
            selector: #selector(handleFrontAppChanged),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )
        refresh(force: true)
    }

    @objc private func handleFrontAppChanged() {
        refresh(force: true)
    }

    nonisolated static func refreshSnapshotFromAnyThread(force: Bool = false) -> FrontmostAppCommandSnapshot? {
        if Thread.isMainThread {
            return MainActor.assumeIsolated {
                shared.refresh(force: force)
            }
        }
        return DispatchQueue.main.sync {
            MainActor.assumeIsolated {
                shared.refresh(force: force)
            }
        }
    }

    @discardableResult
    func refresh(force: Bool = false) -> FrontmostAppCommandSnapshot? {
        guard AXIsProcessTrusted(),
              let app = NSWorkspace.shared.frontmostApplication,
              let bundleIdentifier = app.bundleIdentifier else {
            snapshot = nil
            observedPID = 0
            return nil
        }

        if bundleIdentifier == Bundle.main.bundleIdentifier {
            return snapshot
        }

        let now = Date()
        if !force,
           let snapshot,
           observedPID == app.processIdentifier,
           now.timeIntervalSince(lastRefreshAt) < 1.5 {
            return snapshot
        }

        let next = queryCommands(for: app)
        snapshot = next
        observedPID = app.processIdentifier
        lastRefreshAt = now
        return next
    }

    private func queryCommands(for app: NSRunningApplication) -> FrontmostAppCommandSnapshot {
        let bundleIdentifier = app.bundleIdentifier ?? ""
        let appName = app.localizedName ?? bundleIdentifier
        let appAX = AXUIElementCreateApplication(app.processIdentifier)
        var commands: [FrontmostAppCommand] = []
        var seen = Set<String>()

        var menuBarRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(appAX, kAXMenuBarAttribute as CFString, &menuBarRef) == .success,
           let menuBarRef,
           CFGetTypeID(menuBarRef) == AXUIElementGetTypeID() {
            let menuBar = menuBarRef as! AXUIElement
            var visited = Set<CFHashCode>()

            for topLevelItem in childElements(of: menuBar) {
                let sectionTitle = sanitizedTitle(stringAttribute(topLevelItem, kAXTitleAttribute as CFString))
                let seedPath = sectionTitle.isEmpty ? [] : [sectionTitle]

                let roots = menuRoots(for: topLevelItem)
                for child in roots {
                    collectCommands(
                        in: child,
                        seedPath: seedPath,
                        processIdentifier: app.processIdentifier,
                        bundleIdentifier: bundleIdentifier,
                        appName: appName,
                        depth: 0,
                        commands: &commands,
                        seen: &seen,
                        visited: &visited
                    )
                }
            }
        }

        mergeSupplementalCommands(
            for: app,
            bundleIdentifier: bundleIdentifier,
            appName: appName,
            commands: &commands,
            seen: &seen
        )

        return FrontmostAppCommandSnapshot(
            processIdentifier: app.processIdentifier,
            bundleIdentifier: bundleIdentifier,
            appName: appName,
            commands: commands
        )
    }

    private func collectCommands(
        in element: AXUIElement,
        seedPath: [String],
        processIdentifier: pid_t,
        bundleIdentifier: String,
        appName: String,
        depth: Int,
        commands: inout [FrontmostAppCommand],
        seen: inout Set<String>,
        visited: inout Set<CFHashCode>
    ) {
        guard depth < Self.maxTraversalDepth else { return }

        let elementHash = CFHash(element)
        guard visited.insert(elementHash).inserted else { return }

        let role = stringAttribute(element, kAXRoleAttribute as CFString) ?? ""
        let title = sanitizedTitle(stringAttribute(element, kAXTitleAttribute as CFString))
        let descendants = childElements(of: element)

        if role == kAXMenuItemRole as String,
           !title.isEmpty,
           let shortcut = shortcutBinding(for: element) {
            let command = FrontmostAppCommand(
                processIdentifier: processIdentifier,
                bundleIdentifier: bundleIdentifier,
                appName: appName,
                menuPath: seedPath,
                title: title,
                shortcut: shortcut,
                aliases: aliases(for: title, path: seedPath),
                isEnabled: boolAttribute(element, kAXEnabledAttribute as CFString) ?? true
            )
            if seen.insert(command.id).inserted {
                commands.append(command)
            }
        }

        var nextPath = seedPath
        if role == kAXMenuItemRole as String,
           !title.isEmpty,
           descendants.contains(where: isMenuContainer) {
            nextPath.append(title)
        }

        for child in descendants {
            collectCommands(
                in: child,
                seedPath: nextPath,
                processIdentifier: processIdentifier,
                bundleIdentifier: bundleIdentifier,
                appName: appName,
                depth: depth + 1,
                commands: &commands,
                seen: &seen,
                visited: &visited
            )
        }
    }

    private func mergeSupplementalCommands(
        for app: NSRunningApplication,
        bundleIdentifier: String,
        appName: String,
        commands: inout [FrontmostAppCommand],
        seen: inout Set<String>
    ) {
        for template in supplementalCommands(for: app) {
            let command = FrontmostAppCommand(
                processIdentifier: app.processIdentifier,
                bundleIdentifier: bundleIdentifier,
                appName: appName,
                menuPath: [template.sectionTitle, template.subgroupTitle],
                title: template.title,
                shortcut: template.shortcut,
                aliases: VoiceCommandRouter.uniqueAliases([template.title] + template.aliases),
                isEnabled: true
            )

            if commands.contains(where: { isSemanticDuplicate($0, of: command) }) {
                continue
            }

            let dedupeKey = supplementalDedupeKey(for: command)
            if seen.insert(dedupeKey).inserted {
                commands.append(command)
            }
        }
    }

    private func supplementalCommands(for app: NSRunningApplication) -> [SupplementalCommandTemplate] {
        guard let bundleIdentifier = app.bundleIdentifier else { return [] }
        var templates: [SupplementalCommandTemplate] = []

        if Self.browserBundleIdentifiers.contains(bundleIdentifier) {
            templates += browserSupplementalCommands()
        }
        if Self.editorBundleIdentifiers.contains(bundleIdentifier) || Self.jetBrainsBundlePrefixes.contains(where: { bundleIdentifier.hasPrefix($0) }) {
            templates += editorSupplementalCommands(for: bundleIdentifier)
        }
        if Self.terminalBundleIdentifiers.contains(bundleIdentifier) {
            templates += terminalSupplementalCommands(for: bundleIdentifier)
        }
        if Self.collaborationBundleIdentifiers.contains(bundleIdentifier) {
            templates += collaborationSupplementalCommands(for: bundleIdentifier)
        }

        return templates
    }

    private func supplementalDedupeKey(for command: FrontmostAppCommand) -> String {
        [command.bundleIdentifier, command.title.lowercased(), command.shortcut.displayString]
            .joined(separator: "::")
    }

    private func isSemanticDuplicate(_ existing: FrontmostAppCommand, of supplemental: FrontmostAppCommand) -> Bool {
        guard existing.shortcut == supplemental.shortcut else { return false }

        let existingAliases = Set(
            VoiceCommandRouter.uniqueAliases([existing.title] + existing.aliases)
                .map(Self.normalizedAliasLookupKey)
                .filter { !$0.isEmpty }
        )
        let supplementalAliases = Set(
            VoiceCommandRouter.uniqueAliases([supplemental.title] + supplemental.aliases)
                .map(Self.normalizedAliasLookupKey)
                .filter { !$0.isEmpty }
        )

        return !existingAliases.isDisjoint(with: supplementalAliases)
    }

    private func browserSupplementalCommands() -> [SupplementalCommandTemplate] {
        let isChinese = AppLocalization.isChinese
        let browserSection = isChinese ? "浏览器常用" : "Browser"
        let tabsGroup = isChinese ? "标签页" : "Tabs"
        let pageGroup = isChinese ? "页面" : "Page"

        return [
            SupplementalCommandTemplate(
                sectionTitle: browserSection,
                subgroupTitle: tabsGroup,
                title: isChinese ? "新建标签页" : "New Tab",
                shortcut: HotkeyBinding(keyCode: kVK_ANSI_T, modifiers: Self.commandModifier),
                aliases: ["new tab", "open new tab", "新建标签", "新标签页", "打开新标签"]
            ),
            SupplementalCommandTemplate(
                sectionTitle: browserSection,
                subgroupTitle: tabsGroup,
                title: isChinese ? "关闭标签页" : "Close Tab",
                shortcut: HotkeyBinding(keyCode: kVK_ANSI_W, modifiers: Self.commandModifier),
                aliases: ["close tab", "close current tab", "关闭标签", "关闭当前标签", "关掉标签页"]
            ),
            SupplementalCommandTemplate(
                sectionTitle: browserSection,
                subgroupTitle: tabsGroup,
                title: isChinese ? "恢复已关闭标签页" : "Reopen Closed Tab",
                shortcut: HotkeyBinding(keyCode: kVK_ANSI_T, modifiers: Self.commandShiftModifier),
                aliases: ["reopen tab", "restore tab", "restore closed tab", "恢复标签", "重新打开标签"]
            ),
            SupplementalCommandTemplate(
                sectionTitle: browserSection,
                subgroupTitle: tabsGroup,
                title: isChinese ? "下一个标签页" : "Next Tab",
                shortcut: HotkeyBinding(keyCode: kVK_Tab, modifiers: Self.controlModifier),
                aliases: ["next tab", "switch to next tab", "下一个标签", "切换到下一个标签", "切到下个标签"]
            ),
            SupplementalCommandTemplate(
                sectionTitle: browserSection,
                subgroupTitle: tabsGroup,
                title: isChinese ? "上一个标签页" : "Previous Tab",
                shortcut: HotkeyBinding(keyCode: kVK_Tab, modifiers: Self.controlShiftModifier),
                aliases: ["previous tab", "last tab", "上一个标签", "切换到上一个标签", "切到上个标签"]
            ),
            SupplementalCommandTemplate(
                sectionTitle: browserSection,
                subgroupTitle: pageGroup,
                title: isChinese ? "刷新页面" : "Refresh Page",
                shortcut: HotkeyBinding(keyCode: kVK_ANSI_R, modifiers: Self.commandModifier),
                aliases: ["reload page", "refresh page", "刷新页面", "重新加载页面"]
            ),
            SupplementalCommandTemplate(
                sectionTitle: browserSection,
                subgroupTitle: pageGroup,
                title: isChinese ? "在页面中查找" : "Find in Page",
                shortcut: HotkeyBinding(keyCode: kVK_ANSI_F, modifiers: Self.commandModifier),
                aliases: ["find", "find in page", "search in page", "查找", "页面查找"]
            ),
            SupplementalCommandTemplate(
                sectionTitle: browserSection,
                subgroupTitle: pageGroup,
                title: isChinese ? "聚焦地址栏" : "Focus Address Bar",
                shortcut: HotkeyBinding(keyCode: kVK_ANSI_L, modifiers: Self.commandModifier),
                aliases: ["focus address bar", "address bar", "go to address bar", "聚焦地址栏", "切到地址栏"]
            ),
            SupplementalCommandTemplate(
                sectionTitle: browserSection,
                subgroupTitle: pageGroup,
                title: isChinese ? "新建窗口" : "New Window",
                shortcut: HotkeyBinding(keyCode: kVK_ANSI_N, modifiers: Self.commandModifier),
                aliases: ["new window", "open new window", "新建窗口", "打开新窗口"]
            ),
            SupplementalCommandTemplate(
                sectionTitle: browserSection,
                subgroupTitle: pageGroup,
                title: isChinese ? "关闭窗口" : "Close Window",
                shortcut: HotkeyBinding(keyCode: kVK_ANSI_W, modifiers: Self.commandShiftModifier),
                aliases: ["close window", "关闭窗口"]
            )
        ]
    }

    private func editorSupplementalCommands(for bundleIdentifier: String) -> [SupplementalCommandTemplate] {
        let isChinese = AppLocalization.isChinese
        let editorSection = isChinese ? "编辑器常用" : "Editor"
        let navigationGroup = isChinese ? "导航" : "Navigation"
        let commandGroup = isChinese ? "命令" : "Commands"

        if bundleIdentifier == "com.apple.dt.Xcode" {
            return [
                SupplementalCommandTemplate(
                    sectionTitle: editorSection,
                    subgroupTitle: navigationGroup,
                    title: isChinese ? "快速打开" : "Open Quickly",
                    shortcut: HotkeyBinding(keyCode: kVK_ANSI_O, modifiers: Self.commandShiftModifier),
                    aliases: ["open quickly", "quick open", "快速打开", "打开文件", "切换文件"]
                ),
                SupplementalCommandTemplate(
                    sectionTitle: editorSection,
                    subgroupTitle: navigationGroup,
                    title: isChinese ? "打开跳转栏" : "Open Jump Bar",
                    shortcut: HotkeyBinding(keyCode: kVK_ANSI_J, modifiers: Self.commandControlModifier),
                    aliases: ["jump bar", "open jump bar", "跳转栏", "打开跳转栏"]
                ),
                SupplementalCommandTemplate(
                    sectionTitle: editorSection,
                    subgroupTitle: commandGroup,
                    title: isChinese ? "查找" : "Find",
                    shortcut: HotkeyBinding(keyCode: kVK_ANSI_F, modifiers: Self.commandModifier),
                    aliases: ["find", "search", "查找", "搜索"]
                )
            ]
        }

        if bundleIdentifier.hasPrefix("com.jetbrains.") {
            return [
                SupplementalCommandTemplate(
                    sectionTitle: editorSection,
                    subgroupTitle: commandGroup,
                    title: isChinese ? "搜索所有地方" : "Search Everywhere",
                    shortcut: HotkeyBinding(keyCode: kVK_Shift, modifiers: Self.shiftModifier),
                    aliases: ["search everywhere", "find anywhere", "搜索所有地方", "全局搜索"]
                ),
                SupplementalCommandTemplate(
                    sectionTitle: editorSection,
                    subgroupTitle: navigationGroup,
                    title: isChinese ? "跳转到定义" : "Go to Declaration",
                    shortcut: HotkeyBinding(keyCode: kVK_ANSI_B, modifiers: Self.commandModifier),
                    aliases: ["go to definition", "jump to definition", "跳转定义", "去定义"]
                ),
                SupplementalCommandTemplate(
                    sectionTitle: editorSection,
                    subgroupTitle: commandGroup,
                    title: isChinese ? "执行动作" : "Find Action",
                    shortcut: HotkeyBinding(keyCode: kVK_ANSI_A, modifiers: Self.commandShiftModifier),
                    aliases: ["find action", "run action", "执行动作", "查找动作"]
                )
            ]
        }

        return [
            SupplementalCommandTemplate(
                sectionTitle: editorSection,
                subgroupTitle: commandGroup,
                title: isChinese ? "命令面板" : "Command Palette",
                shortcut: HotkeyBinding(keyCode: kVK_ANSI_P, modifiers: Self.commandShiftModifier),
                aliases: ["command palette", "show commands", "命令面板", "显示命令面板"]
            ),
            SupplementalCommandTemplate(
                sectionTitle: editorSection,
                subgroupTitle: navigationGroup,
                title: isChinese ? "快速打开" : "Quick Open",
                shortcut: HotkeyBinding(keyCode: kVK_ANSI_P, modifiers: Self.commandModifier),
                aliases: ["quick open", "open file", "快速打开", "打开文件"]
            ),
            SupplementalCommandTemplate(
                sectionTitle: editorSection,
                subgroupTitle: commandGroup,
                title: isChinese ? "搜索项目" : "Search Project",
                shortcut: HotkeyBinding(keyCode: kVK_ANSI_F, modifiers: Self.commandShiftModifier),
                aliases: ["search project", "search files", "搜索项目", "全局搜索"]
            ),
            SupplementalCommandTemplate(
                sectionTitle: editorSection,
                subgroupTitle: commandGroup,
                title: isChinese ? "替换项目" : "Replace in Project",
                shortcut: HotkeyBinding(keyCode: kVK_ANSI_H, modifiers: Self.commandShiftModifier),
                aliases: ["replace in project", "replace across files", "全局替换", "项目替换"]
            )
        ]
    }

    private func terminalSupplementalCommands(for bundleIdentifier: String) -> [SupplementalCommandTemplate] {
        let isChinese = AppLocalization.isChinese
        let terminalSection = isChinese ? "终端常用" : "Terminal"
        let sessionGroup = isChinese ? "会话" : "Session"
        let layoutGroup = isChinese ? "布局" : "Layout"

        var templates: [SupplementalCommandTemplate] = [
            SupplementalCommandTemplate(
                sectionTitle: terminalSection,
                subgroupTitle: sessionGroup,
                title: isChinese ? "新建标签页" : "New Tab",
                shortcut: HotkeyBinding(keyCode: kVK_ANSI_T, modifiers: Self.commandModifier),
                aliases: ["new tab", "open terminal tab", "新建标签", "打开新终端标签"]
            ),
            SupplementalCommandTemplate(
                sectionTitle: terminalSection,
                subgroupTitle: sessionGroup,
                title: isChinese ? "新建窗口" : "New Window",
                shortcut: HotkeyBinding(keyCode: kVK_ANSI_N, modifiers: Self.commandModifier),
                aliases: ["new window", "open terminal window", "新建窗口", "打开终端窗口"]
            )
        ]

        if bundleIdentifier != "com.apple.Terminal" {
            templates += [
                SupplementalCommandTemplate(
                    sectionTitle: terminalSection,
                    subgroupTitle: layoutGroup,
                    title: isChinese ? "垂直分屏" : "Split Pane",
                    shortcut: HotkeyBinding(keyCode: kVK_ANSI_D, modifiers: Self.commandModifier),
                    aliases: ["split pane", "split terminal", "终端分屏", "分屏"]
                )
            ]
        }

        if bundleIdentifier == "dev.warp.Warp-Stable" {
            templates += [
                SupplementalCommandTemplate(
                    sectionTitle: terminalSection,
                    subgroupTitle: sessionGroup,
                    title: isChinese ? "命令搜索" : "Command Search",
                    shortcut: HotkeyBinding(keyCode: kVK_ANSI_P, modifiers: Self.commandModifier),
                    aliases: ["command search", "warp command search", "命令搜索", "搜索命令"]
                )
            ]
        }

        return templates
    }

    private func collaborationSupplementalCommands(for bundleIdentifier: String) -> [SupplementalCommandTemplate] {
        let isChinese = AppLocalization.isChinese
        let collaborationSection = isChinese ? "协作常用" : "Collaboration"
        let navigationGroup = isChinese ? "导航" : "Navigation"
        let composeGroup = isChinese ? "创建" : "Compose"

        switch bundleIdentifier {
        case "com.tinyspeck.slackmacgap":
            return [
                SupplementalCommandTemplate(
                    sectionTitle: collaborationSection,
                    subgroupTitle: navigationGroup,
                    title: isChinese ? "快速切换" : "Quick Switcher",
                    shortcut: HotkeyBinding(keyCode: kVK_ANSI_K, modifiers: Self.commandModifier),
                    aliases: ["quick switcher", "switch channel", "快速切换", "切换频道"]
                ),
                SupplementalCommandTemplate(
                    sectionTitle: collaborationSection,
                    subgroupTitle: navigationGroup,
                    title: isChinese ? "搜索消息" : "Search Messages",
                    shortcut: HotkeyBinding(keyCode: kVK_ANSI_F, modifiers: Self.commandModifier),
                    aliases: ["search messages", "search slack", "搜索消息", "Slack 搜索"]
                ),
                SupplementalCommandTemplate(
                    sectionTitle: collaborationSection,
                    subgroupTitle: composeGroup,
                    title: isChinese ? "新建消息" : "New Message",
                    shortcut: HotkeyBinding(keyCode: kVK_ANSI_N, modifiers: Self.commandModifier),
                    aliases: ["new message", "compose message", "新建消息", "写消息"]
                )
            ]
        case "notion.id":
            return [
                SupplementalCommandTemplate(
                    sectionTitle: collaborationSection,
                    subgroupTitle: commandGroupTitle(isChinese: isChinese),
                    title: isChinese ? "搜索" : "Search",
                    shortcut: HotkeyBinding(keyCode: kVK_ANSI_P, modifiers: Self.commandModifier),
                    aliases: ["search", "search notion", "搜索", "Notion 搜索"]
                ),
                SupplementalCommandTemplate(
                    sectionTitle: collaborationSection,
                    subgroupTitle: composeGroup,
                    title: isChinese ? "新建页面" : "New Page",
                    shortcut: HotkeyBinding(keyCode: kVK_ANSI_N, modifiers: Self.commandModifier),
                    aliases: ["new page", "create page", "新建页面", "创建页面"]
                ),
                SupplementalCommandTemplate(
                    sectionTitle: collaborationSection,
                    subgroupTitle: commandGroupTitle(isChinese: isChinese),
                    title: isChinese ? "命令菜单" : "Command Menu",
                    shortcut: HotkeyBinding(keyCode: kVK_ANSI_Slash, modifiers: Self.commandModifier),
                    aliases: ["command menu", "slash command", "命令菜单", "斜杠菜单"]
                )
            ]
        case "com.hnc.Discord":
            return [
                SupplementalCommandTemplate(
                    sectionTitle: collaborationSection,
                    subgroupTitle: navigationGroup,
                    title: isChinese ? "快速切换" : "Quick Switcher",
                    shortcut: HotkeyBinding(keyCode: kVK_ANSI_K, modifiers: Self.commandModifier),
                    aliases: ["quick switcher", "switch server", "快速切换", "切换服务器"]
                ),
                SupplementalCommandTemplate(
                    sectionTitle: collaborationSection,
                    subgroupTitle: commandGroupTitle(isChinese: isChinese),
                    title: isChinese ? "搜索" : "Search",
                    shortcut: HotkeyBinding(keyCode: kVK_ANSI_F, modifiers: Self.commandModifier),
                    aliases: ["search", "search discord", "搜索", "Discord 搜索"]
                )
            ]
        default:
            return []
        }
    }

    private func commandGroupTitle(isChinese: Bool) -> String {
        isChinese ? "命令" : "Commands"
    }

    private func menuRoots(for element: AXUIElement) -> [AXUIElement] {
        let descendants = childElements(of: element)
        let menus = descendants.filter(isMenuContainer)
        return menus.isEmpty ? descendants : menus
    }

    private func childElements(of element: AXUIElement) -> [AXUIElement] {
        var ordered: [AXUIElement] = []
        var seen = Set<CFHashCode>()

        if let menu = elementAttribute(element, Self.axMenuAttribute) {
            let key = CFHash(menu)
            if seen.insert(key).inserted {
                ordered.append(menu)
            }
        }

        for attribute in [kAXVisibleChildrenAttribute as CFString, kAXChildrenAttribute as CFString] {
            for child in elementArrayAttribute(element, attribute) {
                let key = CFHash(child)
                if seen.insert(key).inserted {
                    ordered.append(child)
                }
            }
        }

        return ordered
    }

    private func elementArrayAttribute(_ element: AXUIElement, _ attribute: CFString) -> [AXUIElement] {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success,
              let array = value as? [AXUIElement] else {
            return []
        }
        return array
    }

    private func elementAttribute(_ element: AXUIElement, _ attribute: CFString) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success,
              let element = value,
              CFGetTypeID(element) == AXUIElementGetTypeID() else {
            return nil
        }
        return (element as! AXUIElement)
    }

    private func stringAttribute(_ element: AXUIElement, _ attribute: CFString) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success,
              let string = value as? String else {
            return nil
        }
        return string
    }

    private func intAttribute(_ element: AXUIElement, _ attribute: CFString) -> Int? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success else { return nil }
        if let number = value as? NSNumber {
            return number.intValue
        }
        return nil
    }

    private func boolAttribute(_ element: AXUIElement, _ attribute: CFString) -> Bool? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success,
              let value else { return nil }
        if let number = value as? NSNumber {
            return number.boolValue
        }
        if CFGetTypeID(value) == CFBooleanGetTypeID() {
            return CFBooleanGetValue((value as! CFBoolean))
        }
        return nil
    }

    private func shortcutBinding(for element: AXUIElement) -> HotkeyBinding? {
        let modifiersValue = intAttribute(element, kAXMenuItemCmdModifiersAttribute as CFString) ?? menuItemModifierNone
        let keyCode = intAttribute(element, kAXMenuItemCmdVirtualKeyAttribute as CFString)
            ?? keyCode(for: stringAttribute(element, kAXMenuItemCmdCharAttribute as CFString) ?? "")
        guard let keyCode else { return nil }
        return HotkeyBinding(
            keyCode: keyCode,
            modifiers: modifiers(fromAXMenuItemModifiers: modifiersValue)
        )
    }

    private func modifiers(fromAXMenuItemModifiers value: Int) -> UInt64 {
        var flags: CGEventFlags = []
        if (value & menuItemModifierNoCommand) == 0 {
            flags.insert(.maskCommand)
        }
        if (value & menuItemModifierShift) != 0 {
            flags.insert(.maskShift)
        }
        if (value & menuItemModifierOption) != 0 {
            flags.insert(.maskAlternate)
        }
        if (value & menuItemModifierControl) != 0 {
            flags.insert(.maskControl)
        }
        return flags.rawValue
    }

    private func keyCode(for commandChar: String) -> Int? {
        Self.commandCharacterKeyCodes[commandChar.lowercased()]
    }

    private static func normalizedAliasLookupKey(_ raw: String) -> String {
        raw
            .replacingOccurrences(of: "\u{2026}", with: "")
            .lowercased()
            .components(separatedBy: .whitespacesAndNewlines)
            .joined()
    }

    private func sanitizedTitle(_ raw: String?) -> String {
        guard let raw else { return "" }
        return raw
            .replacingOccurrences(of: "\u{2026}", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func isMenuContainer(_ element: AXUIElement) -> Bool {
        let role = stringAttribute(element, kAXRoleAttribute as CFString) ?? ""
        return role == kAXMenuRole as String || role == kAXMenuBarRole as String
    }

    private func aliases(for title: String, path: [String]) -> [String] {
        let joined = (path + [title]).joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        let lowered = joined.lowercased()

        var aliases = [title, joined]

        for component in path + [title] {
            let key = Self.normalizedAliasLookupKey(component)
            if let related = Self.bilingualAliasLookup[key] {
                aliases += related
            }
        }

        for rule in Self.aliasRules where rule.keywords.allSatisfy(lowered.contains) {
            aliases += rule.aliases
        }

        return VoiceCommandRouter.uniqueAliases(aliases)
    }
}

enum VoiceCommandPreset: String, CaseIterable, Identifiable {
    case clickLeft
    case clickRight
    case doubleClick
    case toggleInputControlMode
    case toggleTracking
    case toggleLanguage
    case toggleConnectionLock
    case toggleShortcutPanel
    case mediaPlayPause
    case mediaPrevious
    case mediaNext
    case showShortcutPanel
    case hideShortcutPanel
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
    case clearInput
    case lockConnection
    case unlockConnection

    var id: String { rawValue }

    static let allCases: [VoiceCommandPreset] = [
        .clickLeft,
        .clickRight,
        .doubleClick,
        .toggleInputControlMode,
        .toggleTracking,
        .toggleLanguage,
        .toggleShortcutPanel,
        .mediaPlayPause,
        .mediaPrevious,
        .mediaNext,
        .showShortcutPanel,
        .hideShortcutPanel,
        .startPointer,
        .stopPointer,
        .recenter,
        .scrollUp,
        .scrollDown,
        .scrollTop,
        .scrollBottom,
        .dragStart,
        .dragEnd,
        .undo,
        .paste,
        .clearInput
    ]

    var intent: VoiceIntent {
        switch self {
        case .clickLeft:
            return .clickLeft
        case .clickRight:
            return .clickRight
        case .doubleClick:
            return .doubleClick
        case .toggleInputControlMode:
            return .toggleInputControlMode
        case .toggleTracking:
            return .toggleTracking
        case .toggleLanguage:
            return .toggleLanguage
        case .toggleConnectionLock:
            return .toggleConnectionLock
        case .toggleShortcutPanel:
            return .toggleShortcutPanel
        case .mediaPlayPause:
            return .mediaPlayPause
        case .mediaPrevious:
            return .mediaPrevious
        case .mediaNext:
            return .mediaNext
        case .showShortcutPanel:
            return .showShortcutPanel
        case .hideShortcutPanel:
            return .hideShortcutPanel
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
        case .clearInput:
            return .clearInput
        case .lockConnection:
            return .lockConnection
        case .unlockConnection:
            return .unlockConnection
        }
    }

    var isTypingSafe: Bool {
        switch self {
        case .toggleShortcutPanel, .showShortcutPanel, .hideShortcutPanel, .scrollUp, .scrollDown, .scrollTop, .scrollBottom, .undo, .paste, .clearInput:
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
        case .toggleInputControlMode:
            return isChinese ? "切换输入/控制模式" : "Toggle Input/Control Mode"
        case .toggleTracking:
            return isChinese ? "切换头控" : "Toggle Pointer Control"
        case .toggleLanguage:
            return isChinese ? "切换语言" : "Toggle Language"
        case .toggleConnectionLock:
            return isChinese ? "切换连接锁定" : "Toggle Connection Lock"
        case .toggleShortcutPanel:
            return isChinese ? "切换快捷键面板" : "Toggle Shortcuts Panel"
        case .mediaPlayPause:
            return isChinese ? "播放 / 暂停" : "Play / Pause"
        case .mediaPrevious:
            return isChinese ? "上一首" : "Previous Track"
        case .mediaNext:
            return isChinese ? "下一首" : "Next Track"
        case .showShortcutPanel:
            return isChinese ? "显示快捷键面板" : "Show Shortcuts Panel"
        case .hideShortcutPanel:
            return isChinese ? "关闭快捷键面板" : "Hide Shortcuts Panel"
        case .startPointer:
            return isChinese ? "开启头控" : "Start Pointer"
        case .stopPointer:
            return isChinese ? "停止头控" : "Stop Pointer"
        case .recenter:
            return isChinese ? "头控回中" : "Recenter"
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
        case .clearInput:
            return isChinese ? "清空输入" : "Clear Input"
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
    case toggleInputControlMode
    case toggleTracking
    case toggleLanguage
    case toggleConnectionLock
    case toggleShortcutPanel
    case mediaPlayPause
    case mediaPrevious
    case mediaNext
    case showShortcutPanel
    case hideShortcutPanel
    case startPointer
    case stopPointer
    case recenter
    case frontmostAppCommand(FrontmostAppCommand)
    case scroll(Int, Int) // dx, dy
    case scrollToWeb(String) // "top", "bottom"
    case dragStart
    case dragEnd
    case undo
    case paste
    case clearInput
    case deleteBackward(Int)
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
    private static let contextualAppCommandLimit = 24

    private struct CommandMatch {
        let preset: VoiceCommandPreset
        let confidence: VoiceCommandConfidence
        let reason: String
    }

    private struct AppCommandMatch {
        let command: FrontmostAppCommand
        let confidence: VoiceCommandConfidence
        let reason: String
    }

    private enum MatchStage {
        case exact
        case fuzzy
    }

    private struct State {
        var overrides: [VoiceCommandOverrideConfig] = []
        var languageTermsOverrides: [VoiceLanguageTermsOverrideConfig] = []
        var frontmostAppCommands: [FrontmostAppCommand] = []
    }

    private let stateQueue = DispatchQueue(label: "com.aether.voice-command-router.state", attributes: .concurrent)
    private var state = State()

    var overrides: [VoiceCommandOverrideConfig] {
        get { stateQueue.sync { state.overrides } }
        set {
            stateQueue.sync(flags: .barrier) {
                state.overrides = newValue
            }
        }
    }

    var frontmostAppCommands: [FrontmostAppCommand] {
        get { stateQueue.sync { state.frontmostAppCommands } }
        set {
            stateQueue.sync(flags: .barrier) {
                state.frontmostAppCommands = newValue
            }
        }
    }

    var languageTermsOverrides: [VoiceLanguageTermsOverrideConfig] {
        get { stateQueue.sync { state.languageTermsOverrides } }
        set {
            stateQueue.sync(flags: .barrier) {
                state.languageTermsOverrides = newValue
            }
        }
    }

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
        let currentState = stateSnapshot()
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return VoiceCommandDecision(intent: .unknown(raw), confidence: .low, reason: "empty")
        }

        if let explicitDictation = stripLeadingPrefix(
            from: trimmed,
            prefixes: Self.effectiveDictationPrefixes(
                for: localeIdentifier,
                overrides: currentState.languageTermsOverrides
            )
        ) {
            return VoiceCommandDecision(intent: .dictation(explicitDictation), confidence: .high, reason: "explicit-dictation-prefix")
        }

        let explicitCommandPayload = stripLeadingPrefix(
            from: trimmed,
            prefixes: Self.effectiveCommandPrefixes(
                for: localeIdentifier,
                overrides: currentState.languageTermsOverrides
            )
        )
        let commandText = explicitCommandPayload ?? trimmed

        // Normalize for command matching
        let s = commandText.lowercased().replacingOccurrences(of: " ", with: "")
        
        os_log("Router: Input [%{public}@] with Bias [%{public}@]. Normalized: [%{public}@]", 
               log: GlobalLogger.router, type: .debug, commandText, String(describing: bias), s)

        // --- 1. Explicit Overrides (Highest Priority) ---
        if bias == .forceDictation {
            return VoiceCommandDecision(intent: .dictation(trimmed), confidence: .high, reason: "forced-dictation-bias")
        }
        
        // --- 2. Explicit command forcing ---
        let isForceCommand = bias == .forceCommand || explicitCommandPayload != nil

        if isForceCommand || bias != .dictationPreferred {
            if let deleteMatch = matchDeleteBackwardCommand(
                text: commandText,
                localeIdentifier: localeIdentifier
            ) {
                return deleteMatch
            }
        }

        // --- 3. Smart Routing Logic ---
        // In an input field, bare speech should become dictation.
        // Command execution in typing context requires an explicit command prefix or force-command gesture.
        if bias == .dictationPreferred && !isForceCommand {
            return VoiceCommandDecision(intent: .dictation(trimmed), confidence: .high, reason: "typing-preferred")
        }

        // --- 4. Local Command Matching (Standard Workflow) ---
        if let match = matchCommand(
            normalized: s,
            raw: commandText,
            localeIdentifier: localeIdentifier,
            overrides: currentState.overrides,
            stage: .exact
        ) {
            return VoiceCommandDecision(intent: match.preset.intent, confidence: match.confidence, reason: match.reason)
        }

        if let appMatch = matchFrontmostAppCommand(
            normalized: s,
            raw: commandText,
            frontmostAppCommands: currentState.frontmostAppCommands,
            stage: .exact
        ) {
            return VoiceCommandDecision(intent: .frontmostAppCommand(appMatch.command), confidence: appMatch.confidence, reason: appMatch.reason)
        }

        if let appMatch = matchFrontmostAppCommand(
            normalized: s,
            raw: commandText,
            frontmostAppCommands: currentState.frontmostAppCommands,
            stage: .fuzzy
        ) {
            return VoiceCommandDecision(intent: .frontmostAppCommand(appMatch.command), confidence: appMatch.confidence, reason: appMatch.reason)
        }

        if let match = matchCommand(
            normalized: s,
            raw: commandText,
            localeIdentifier: localeIdentifier,
            overrides: currentState.overrides,
            stage: .fuzzy
        ) {
            return VoiceCommandDecision(intent: match.preset.intent, confidence: match.confidence, reason: match.reason)
        }

        // --- 5. Default Fallback ---
        if isForceCommand || bias == .commandPreferred {
            return VoiceCommandDecision(intent: .unknown(trimmed), confidence: .low, reason: "forced-command-no-match")
        }
        return VoiceCommandDecision(intent: .dictation(trimmed), confidence: .low, reason: "fallback-dictation")
    }

    static func defaultAliases(for preset: VoiceCommandPreset, localeIdentifier: String) -> [String] {
        guard let defaults = VoiceLexiconDefaults.load() else { return [] }
        let canonical = VoiceLexiconSupport.canonicalLocaleIdentifier(localeIdentifier)
        let entry = defaults.commandOverrides.first(where: {
            VoiceLexiconSupport.canonicalLocaleIdentifier($0.localeIdentifier) == canonical &&
            $0.commandID == preset.rawValue
        })
        return VoiceLexiconSupport.uniqueTerms(entry?.aliases ?? [])
    }

    static func defaultCommandPrefixes(for localeIdentifier: String) -> [String] {
        guard let defaults = VoiceLexiconDefaults.load() else { return [] }
        let canonical = VoiceLexiconSupport.canonicalLocaleIdentifier(localeIdentifier)
        let entry = defaults.languageTermsOverrides.first(where: {
            VoiceLexiconSupport.canonicalLocaleIdentifier($0.localeIdentifier) == canonical
        })
        return VoiceLexiconSupport.uniqueTerms(entry?.commandPrefixes ?? [])
    }

    static func defaultDictationPrefixes(for localeIdentifier: String) -> [String] {
        guard let defaults = VoiceLexiconDefaults.load() else { return [] }
        let canonical = VoiceLexiconSupport.canonicalLocaleIdentifier(localeIdentifier)
        let entry = defaults.languageTermsOverrides.first(where: {
            VoiceLexiconSupport.canonicalLocaleIdentifier($0.localeIdentifier) == canonical
        })
        return VoiceLexiconSupport.uniqueTerms(entry?.dictationPrefixes ?? [])
    }

    static func effectiveCommandPrefixes(
        for localeIdentifier: String,
        overrides: [VoiceLanguageTermsOverrideConfig]
    ) -> [String] {
        if let override = languageTermsOverrideEntry(for: localeIdentifier, overrides: overrides) {
            return uniqueAliases(override.commandPrefixes)
        }
        return defaultCommandPrefixes(for: localeIdentifier)
    }

    static func effectiveDictationPrefixes(
        for localeIdentifier: String,
        overrides: [VoiceLanguageTermsOverrideConfig]
    ) -> [String] {
        if let override = languageTermsOverrideEntry(for: localeIdentifier, overrides: overrides) {
            return uniqueAliases(override.dictationPrefixes)
        }
        return defaultDictationPrefixes(for: localeIdentifier)
    }

    static func defaultDeletePrefixes(for localeIdentifier: String) -> [String] {
        let raw = AppLocalization.localizedString(
            "editing.delete_prefixes_default",
            localeIdentifier: localeIdentifier
        )
        return uniqueAliases(
            raw
                .components(separatedBy: CharacterSet(charactersIn: ",\n"))
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        )
    }

    static func effectiveAliases(
        for preset: VoiceCommandPreset,
        localeIdentifier: String,
        overrides: [VoiceCommandOverrideConfig]
    ) -> [String] {
        if let override = overrideEntry(for: preset, localeIdentifier: localeIdentifier, overrides: overrides) {
            return compatibilityAliases(for: preset, localeIdentifier: localeIdentifier, base: override.aliases)
        }
        return compatibilityAliases(
            for: preset,
            localeIdentifier: localeIdentifier,
            base: defaultAliases(for: preset, localeIdentifier: localeIdentifier)
        )
    }

    private static func compatibilityAliases(
        for preset: VoiceCommandPreset,
        localeIdentifier: String,
        base: [String]
    ) -> [String] {
        let canonical = VoiceLexiconSupport.canonicalLocaleIdentifier(localeIdentifier)
        let extra: [String]
        switch (preset, canonical) {
        case (.dragStart, "zh-CN"):
            extra = ["开始拖拽", "开始拖"]
        case (.dragStart, "en-US"):
            extra = ["start drag", "drag start"]
        case (.dragEnd, "zh-CN"):
            extra = ["结束拖拽", "结束拖"]
        case (.dragEnd, "en-US"):
            extra = ["end drag", "drag end"]
        default:
            extra = []
        }
        return uniqueAliases(base + extra)
    }

    func contextualStrings(for localeIdentifier: String) -> [String] {
        let currentState = stateSnapshot()
        var ordered: [String] = []
        var seen = Set<String>()

        for preset in VoiceCommandPreset.allCases {
            for alias in Self.effectiveAliases(for: preset, localeIdentifier: localeIdentifier, overrides: currentState.overrides) {
                let normalized = alias.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !normalized.isEmpty else { continue }
                let key = normalized.lowercased()
                guard !seen.contains(key) else { continue }
                seen.insert(key)
                ordered.append(normalized)
            }
        }

        // Keep the recognizer hint set bounded so command discovery does not drown out general dictation context.
        for command in currentState.frontmostAppCommands
            .sorted(by: { $0.aliases.count > $1.aliases.count })
            .prefix(Self.contextualAppCommandLimit) {
            for alias in command.aliases {
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
        overrides: [VoiceCommandOverrideConfig],
        stage: MatchStage = .fuzzy,
        filter: (VoiceCommandPreset) -> Bool = { _ in true }
    ) -> CommandMatch? {
        let candidates = VoiceCommandPreset.allCases.filter(filter)

        if stage == .exact {
            for preset in candidates {
                for alias in normalizedAliases(for: preset, localeIdentifier: localeIdentifier, overrides: overrides) {
                    if normalized == alias {
                        return CommandMatch(preset: preset, confidence: .high, reason: "exact-\(preset.rawValue)")
                    }
                }
            }
            return nil
        }

        for preset in candidates {
            if preset == .clearInput {
                continue
            }
            for alias in normalizedAliases(for: preset, localeIdentifier: localeIdentifier, overrides: overrides) {
                if normalized.contains(alias) {
                    return CommandMatch(preset: preset, confidence: .medium, reason: "contains-\(preset.rawValue)")
                }
            }
        }

        let pinyin = raw.pinyin
        for preset in candidates {
            if preset == .clearInput {
                continue
            }
            for alias in pinyinAliases(for: preset, localeIdentifier: localeIdentifier, overrides: overrides) {
                if pinyin.contains(alias) {
                    return CommandMatch(preset: preset, confidence: .low, reason: "pinyin-\(preset.rawValue)")
                }
            }
        }

        return nil
    }

    private func matchFrontmostAppCommand(
        normalized: String,
        raw: String,
        frontmostAppCommands: [FrontmostAppCommand],
        stage: MatchStage = .fuzzy
    ) -> AppCommandMatch? {
        if stage == .exact {
            for command in frontmostAppCommands {
                for alias in normalizedAppAliases(for: command) {
                    if normalized == alias {
                        return AppCommandMatch(command: command, confidence: .high, reason: "app-exact-\(command.id)")
                    }
                }
            }
            return nil
        }

        for command in frontmostAppCommands {
            for alias in normalizedAppAliases(for: command) {
                if normalized.contains(alias) {
                    return AppCommandMatch(command: command, confidence: .medium, reason: "app-contains-\(command.id)")
                }
            }
        }

        let pinyin = raw.pinyin
        for command in frontmostAppCommands {
            for alias in pinyinAppAliases(for: command) {
                if pinyin.contains(alias) {
                    return AppCommandMatch(command: command, confidence: .low, reason: "app-pinyin-\(command.id)")
                }
            }
        }

        return nil
    }

    private func normalizedAliases(
        for preset: VoiceCommandPreset,
        localeIdentifier: String,
        overrides: [VoiceCommandOverrideConfig]
    ) -> [String] {
        Self.effectiveAliases(for: preset, localeIdentifier: localeIdentifier, overrides: overrides)
            .map(normalizeMatchString)
            .filter { !$0.isEmpty }
    }

    private func pinyinAliases(
        for preset: VoiceCommandPreset,
        localeIdentifier: String,
        overrides: [VoiceCommandOverrideConfig]
    ) -> [String] {
        Self.effectiveAliases(for: preset, localeIdentifier: localeIdentifier, overrides: overrides)
            .map { $0.pinyin }
            .map(normalizeMatchString)
            .filter { !$0.isEmpty }
    }

    private func normalizedAppAliases(for command: FrontmostAppCommand) -> [String] {
        command.aliases
            .map(normalizeMatchString)
            .filter { !$0.isEmpty }
    }

    private func pinyinAppAliases(for command: FrontmostAppCommand) -> [String] {
        command.aliases
            .map { $0.pinyin }
            .map(normalizeMatchString)
            .filter { !$0.isEmpty }
    }

    private func normalizeMatchString(_ raw: String) -> String {
        raw
            .lowercased()
            .components(separatedBy: .whitespacesAndNewlines)
            .joined()
    }

    static func uniqueAliases(_ aliases: [String]) -> [String] {
        VoiceLexiconSupport.uniqueTerms(aliases)
    }

    private static func overrideEntry(
        for preset: VoiceCommandPreset,
        localeIdentifier: String,
        overrides: [VoiceCommandOverrideConfig]
    ) -> VoiceCommandOverrideConfig? {
        let raw = localeIdentifier
        let canonical = VoiceLexiconSupport.canonicalLocaleIdentifier(localeIdentifier)
        return overrides.first(where: { $0.localeIdentifier == raw && $0.commandID == preset.rawValue }) ??
            overrides.first(where: { $0.localeIdentifier == canonical && $0.commandID == preset.rawValue })
    }

    private static func languageTermsOverrideEntry(
        for localeIdentifier: String,
        overrides: [VoiceLanguageTermsOverrideConfig]
    ) -> VoiceLanguageTermsOverrideConfig? {
        let raw = localeIdentifier
        let canonical = VoiceLexiconSupport.canonicalLocaleIdentifier(localeIdentifier)
        return overrides.first(where: { $0.localeIdentifier == raw }) ??
            overrides.first(where: { $0.localeIdentifier == canonical })
    }

    private func stripLeadingPrefix(from text: String, prefixes: [String]) -> String? {
        let lowered = text.lowercased()
        let sortedPrefixes = Self.uniqueAliases(prefixes).sorted { $0.count > $1.count }

        for prefix in sortedPrefixes {
            let loweredPrefix = prefix.lowercased()
            guard lowered.hasPrefix(loweredPrefix) else { continue }
            let remainder = String(text.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
            return remainder.isEmpty ? text : remainder
        }

        return nil
    }

    private func stateSnapshot() -> State {
        stateQueue.sync { state }
    }

    private func matchDeleteBackwardCommand(
        text raw: String,
        localeIdentifier: String
    ) -> VoiceCommandDecision? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let prefixes = Self.defaultDeletePrefixes(for: localeIdentifier)
            .sorted { $0.count > $1.count }

        for prefix in prefixes {
            guard trimmed.lowercased().hasPrefix(prefix.lowercased()) else { continue }
            let suffix = String(trimmed.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
            if suffix.isEmpty {
                return VoiceCommandDecision(intent: .deleteBackward(1), confidence: .high, reason: "delete-prefix-default")
            }
            if let count = parseDeleteCount(from: suffix) {
                return VoiceCommandDecision(intent: .deleteBackward(count), confidence: .high, reason: "delete-prefix-count")
            }
        }

        return nil
    }

    private func parseDeleteCount(from raw: String) -> Int? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return 1 }

        if let number = trimmed.firstMatch(of: #/\d+/#), let count = Int(number.0), count > 0 {
            return min(count, 200)
        }

        let normalized = trimmed
            .replacingOccurrences(of: "个字", with: "")
            .replacingOccurrences(of: "个字符", with: "")
            .replacingOccurrences(of: "字符", with: "")
            .replacingOccurrences(of: "个", with: "")
            .replacingOccurrences(of: "字", with: "")
            .replacingOccurrences(of: "chars", with: "")
            .replacingOccurrences(of: "char", with: "")
            .replacingOccurrences(of: "characters", with: "")
            .replacingOccurrences(of: "character", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if normalized.isEmpty {
            return 1
        }

        if let count = parseChineseNumeral(normalized) {
            return min(max(count, 1), 200)
        }

        return nil
    }

    private func parseChineseNumeral(_ raw: String) -> Int? {
        let digits: [Character: Int] = [
            "零": 0, "一": 1, "二": 2, "两": 2, "三": 3, "四": 4,
            "五": 5, "六": 6, "七": 7, "八": 8, "九": 9
        ]

        if raw == "十" { return 10 }
        if raw.hasSuffix("十"), let leading = raw.first, let value = digits[leading] {
            return value * 10
        }
        if raw.hasPrefix("十"), raw.count == 2, let trailing = raw.last, let value = digits[trailing] {
            return 10 + value
        }
        if raw.contains("十") {
            let parts = raw.split(separator: "十", omittingEmptySubsequences: false)
            let tens = parts.first.flatMap { $0.isEmpty ? 1 : digits[$0.first!] } ?? 0
            let ones = parts.count > 1 ? (parts[1].first.flatMap { digits[$0] } ?? 0) : 0
            if tens > 0 {
                return tens * 10 + ones
            }
        }
        if raw.count == 1, let first = raw.first, let value = digits[first] {
            return value
        }
        return nil
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
