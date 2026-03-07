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

struct FrontmostAppCommandSnapshot: Equatable, Sendable {
    let processIdentifier: pid_t
    let bundleIdentifier: String
    let appName: String
    let commands: [FrontmostAppCommand]
}

@MainActor
final class FrontmostAppCommandCatalog: ObservableObject {
    static let shared = FrontmostAppCommandCatalog()
    private static let axMenuAttribute = "AXMenu" as CFString
    private static let maxTraversalDepth = 12

    private struct AliasRule {
        let keywords: [String]
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

        var menuBarRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appAX, kAXMenuBarAttribute as CFString, &menuBarRef) == .success,
              let menuBarRef,
              CFGetTypeID(menuBarRef) == AXUIElementGetTypeID() else {
            return FrontmostAppCommandSnapshot(
                processIdentifier: app.processIdentifier,
                bundleIdentifier: bundleIdentifier,
                appName: appName,
                commands: []
            )
        }

        let menuBar = menuBarRef as! AXUIElement
        var commands: [FrontmostAppCommand] = []
        var seen = Set<String>()
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
                aliases: aliases(for: title, path: seedPath)
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
        case .showShortcutPanel:
            return isChinese ? "显示快捷键面板" : "Show Shortcuts Panel"
        case .hideShortcutPanel:
            return isChinese ? "关闭快捷键面板" : "Hide Shortcuts Panel"
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

    var languageTermsOverrides: [VoiceLanguageTermsOverrideConfig] {
        get { stateQueue.sync { state.languageTermsOverrides } }
        set {
            stateQueue.sync(flags: .barrier) {
                state.languageTermsOverrides = newValue
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

        // Normalize for command matching
        let s = trimmed.lowercased().replacingOccurrences(of: " ", with: "")
        
        os_log("Router: Input [%{public}@] with Bias [%{public}@]. Normalized: [%{public}@]", 
               log: GlobalLogger.router, type: .debug, trimmed, String(describing: bias), s)

        // --- 1. Explicit Overrides (Highest Priority) ---
        if bias == .forceDictation {
            return VoiceCommandDecision(intent: .dictation(trimmed), confidence: .high, reason: "forced-dictation-bias")
        }
        
        // --- 2. Normalized Force Prefixes ---
        let isForceCommand = hasCommandPrefix(
            s,
            localeIdentifier: localeIdentifier,
            languageTermsOverrides: currentState.languageTermsOverrides
        ) || bias == .forceCommand
        let isForceDictation = hasDictationPrefix(
            s,
            localeIdentifier: localeIdentifier,
            languageTermsOverrides: currentState.languageTermsOverrides
        )

        if isForceDictation {
            let payload = stripDictationPrefix(
                from: trimmed,
                localeIdentifier: localeIdentifier,
                languageTermsOverrides: currentState.languageTermsOverrides
            )
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
                overrides: currentState.overrides,
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
        if let match = matchCommand(
            normalized: s,
            raw: trimmed,
            localeIdentifier: localeIdentifier,
            overrides: currentState.overrides
        ) {
            return VoiceCommandDecision(intent: match.preset.intent, confidence: match.confidence, reason: match.reason)
        }

        if let appMatch = matchFrontmostAppCommand(
            normalized: s,
            raw: trimmed,
            frontmostAppCommands: currentState.frontmostAppCommands
        ) {
            return VoiceCommandDecision(intent: .frontmostAppCommand(appMatch.command), confidence: appMatch.confidence, reason: appMatch.reason)
        }

        // --- 5. Default Fallback ---
        if isForceCommand {
            return VoiceCommandDecision(intent: .unknown(trimmed), confidence: .low, reason: "forced-command-no-match")
        }
        return VoiceCommandDecision(intent: .dictation(trimmed), confidence: .low, reason: "fallback-dictation")
    }

    static func defaultAliases(for preset: VoiceCommandPreset, localeIdentifier: String) -> [String] {
        let locale = VoiceLexiconSupport.canonicalLocaleIdentifier(localeIdentifier).lowercased()
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
        case .showShortcutPanel:
            chinese = ["显示快捷键面板", "打开快捷键面板", "显示当前应用快捷键", "打开当前应用快捷键", "显示命令面板"]
            english = ["show shortcuts panel", "open shortcuts panel", "show app shortcuts", "show current app shortcuts"]
        case .hideShortcutPanel:
            chinese = ["关闭快捷键面板", "隐藏快捷键面板", "收起快捷键面板", "关闭当前应用快捷键"]
            english = ["hide shortcuts panel", "close shortcuts panel", "dismiss shortcuts panel", "hide app shortcuts"]
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
        let currentState = stateSnapshot()
        var ordered: [String] = []
        var seen = Set<String>()

        for prefix in commandPrefixes(
            localeIdentifier: localeIdentifier,
            languageTermsOverrides: currentState.languageTermsOverrides
        ) + dictationPrefixes(
            localeIdentifier: localeIdentifier,
            languageTermsOverrides: currentState.languageTermsOverrides
        ) {
            let normalized = prefix.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalized.isEmpty else { continue }
            let key = normalized.lowercased()
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            ordered.append(normalized)
        }

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
        filter: (VoiceCommandPreset) -> Bool = { _ in true }
    ) -> CommandMatch? {
        let candidates = VoiceCommandPreset.allCases.filter(filter)

        for preset in candidates {
            for alias in normalizedAliases(for: preset, localeIdentifier: localeIdentifier, overrides: overrides) {
                if normalized == alias {
                    return CommandMatch(preset: preset, confidence: .high, reason: "exact-\(preset.rawValue)")
                }
            }
        }

        for preset in candidates {
            for alias in normalizedAliases(for: preset, localeIdentifier: localeIdentifier, overrides: overrides) {
                if normalized.contains(alias) {
                    return CommandMatch(preset: preset, confidence: .medium, reason: "contains-\(preset.rawValue)")
                }
            }
        }

        let pinyin = raw.pinyin
        for preset in candidates {
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
        frontmostAppCommands: [FrontmostAppCommand]
    ) -> AppCommandMatch? {
        for command in frontmostAppCommands {
            for alias in normalizedAppAliases(for: command) {
                if normalized == alias {
                    return AppCommandMatch(command: command, confidence: .high, reason: "app-exact-\(command.id)")
                }
            }
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

    private func hasCommandPrefix(
        _ normalized: String,
        localeIdentifier: String,
        languageTermsOverrides: [VoiceLanguageTermsOverrideConfig]
    ) -> Bool {
        commandPrefixes(localeIdentifier: localeIdentifier, languageTermsOverrides: languageTermsOverrides)
            .contains { normalized.hasPrefix(normalizeMatchString($0)) }
    }

    private func hasDictationPrefix(
        _ normalized: String,
        localeIdentifier: String,
        languageTermsOverrides: [VoiceLanguageTermsOverrideConfig]
    ) -> Bool {
        dictationPrefixes(localeIdentifier: localeIdentifier, languageTermsOverrides: languageTermsOverrides)
            .contains { normalized.hasPrefix(normalizeMatchString($0)) }
    }

    private func stripDictationPrefix(
        from raw: String,
        localeIdentifier: String,
        languageTermsOverrides: [VoiceLanguageTermsOverrideConfig]
    ) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowercase = trimmed.lowercased()
        let prefixes = dictationPrefixes(localeIdentifier: localeIdentifier, languageTermsOverrides: languageTermsOverrides)

        for prefix in prefixes {
            if lowercase.hasPrefix(prefix.lowercased()) {
                let dropCount = prefix.count
                let suffix = trimmed.dropFirst(dropCount).trimmingCharacters(in: .whitespacesAndNewlines)
                return String(suffix)
            }
        }

        return trimmed
    }

    private func commandPrefixes(
        localeIdentifier: String,
        languageTermsOverrides: [VoiceLanguageTermsOverrideConfig]
    ) -> [String] {
        if let override = languageTermsOverride(for: localeIdentifier, languageTermsOverrides: languageTermsOverrides),
           !override.commandPrefixes.isEmpty {
            return VoiceLexiconSupport.uniqueTerms(override.commandPrefixes)
        }
        return Self.defaultCommandPrefixes(for: localeIdentifier)
    }

    private func dictationPrefixes(
        localeIdentifier: String,
        languageTermsOverrides: [VoiceLanguageTermsOverrideConfig]
    ) -> [String] {
        if let override = languageTermsOverride(for: localeIdentifier, languageTermsOverrides: languageTermsOverrides),
           !override.dictationPrefixes.isEmpty {
            return VoiceLexiconSupport.uniqueTerms(override.dictationPrefixes)
        }
        return Self.defaultDictationPrefixes(for: localeIdentifier)
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

    static func defaultCommandPrefixes(for localeIdentifier: String) -> [String] {
        VoiceLexiconSupport.canonicalLocaleIdentifier(localeIdentifier).lowercased().hasPrefix("zh")
            ? ["指令", "command"]
            : ["command", "指令"]
    }

    static func defaultDictationPrefixes(for localeIdentifier: String) -> [String] {
        VoiceLexiconSupport.canonicalLocaleIdentifier(localeIdentifier).lowercased().hasPrefix("zh")
            ? ["输入", "写", "input", "type"]
            : ["input", "type", "输入", "写"]
    }

    private func languageTermsOverride(
        for localeIdentifier: String,
        languageTermsOverrides: [VoiceLanguageTermsOverrideConfig]
    ) -> VoiceLanguageTermsOverrideConfig? {
        let raw = localeIdentifier
        let canonical = VoiceLexiconSupport.canonicalLocaleIdentifier(localeIdentifier)
        return languageTermsOverrides.first(where: { $0.localeIdentifier == raw }) ??
            languageTermsOverrides.first(where: { $0.localeIdentifier == canonical })
    }

    private func stateSnapshot() -> State {
        stateQueue.sync { state }
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
