import AppKit
import ApplicationServices

/// 执行层：直接对菜单项下发 AXPress。
///
/// 相比「先算快捷键再合成按键」，AXPress 有两个优势：
/// 1. 不依赖快捷键解析是否正确（AX 的修饰键位掩码在新系统上有已知不一致）；
/// 2. 没有快捷键的菜单项也能执行。
///
/// 前提是目标 App 已经暴露可访问的菜单项。部分 App（尤其 Electron/沙盒应用）
/// 在未聚焦时菜单不可按，此时需要先激活 App —— 交由调用方（agent / CUA）决定。
public enum MenuExecutor {

    public struct Outcome: Sendable {
        public let pressed: Bool
        public let detail: String

        public static func success(_ detail: String) -> Outcome {
            Outcome(pressed: true, detail: detail)
        }
        public static func failure(_ detail: String) -> Outcome {
            Outcome(pressed: false, detail: detail)
        }
    }

    /// 在目标 App 的菜单树里按 displayPath 找到菜单项并 AXPress。
    public static func press(path: [String], in target: MenuCatalog.AppTarget) -> Outcome {
        let axApp = AXUIElementCreateApplication(target.processIdentifier)
        guard let menuBar = AX.element(axApp, .menuBar) else {
            return .failure("读取不到菜单栏（App 可能未暴露 Accessibility 菜单）")
        }
        guard let item = findItem(path: path, in: menuBar) else {
            return .failure("菜单树里找不到路径: \(path.joined(separator: " > "))")
        }
        return press(item: item, displayPath: path.joined(separator: " > "))
    }

    /// 按标题（末级）在菜单树里查找。用于只给了命令名、没有完整路径的场景。
    public static func press(title: String, in target: MenuCatalog.AppTarget) -> Outcome {
        let axApp = AXUIElementCreateApplication(target.processIdentifier)
        guard let menuBar = AX.element(axApp, .menuBar) else {
            return .failure("读取不到菜单栏")
        }
        guard let (item, path) = findItem(title: title, in: menuBar, path: []) else {
            return .failure("菜单树里找不到标题: \(title)")
        }
        return press(item: item, displayPath: path.joined(separator: " > "))
    }

    private static func press(item: AXUIElement, displayPath: String) -> Outcome {
        let enabled = AX.bool(item, .enabled) ?? true
        guard enabled else {
            return .failure("菜单项当前不可点（disabled）：\(displayPath)。通常需要目标 App 处于激活状态，或先选中某个对象")
        }

        // 优先 AXPress；部分 App 只响应 AXOpen
        var actionNames: CFArray?
        AXUIElementCopyActionNames(item, &actionNames)
        let actions = (actionNames as? [String]) ?? []

        if actions.contains(kAXPressAction as String) {
            let result = AXUIElementPerformAction(item, kAXPressAction as CFString)
            if result == .success {
                return .success(displayPath)
            }
            return .failure("AXPress 失败（AXError \(result.rawValue)）：\(displayPath)")
        }
        if actions.contains("AXOpen") {
            let result = AXUIElementPerformAction(item, "AXOpen" as CFString)
            if result == .success {
                return .success(displayPath)
            }
            return .failure("AXOpen 失败（AXError \(result.rawValue)）：\(displayPath)")
        }
        return .failure("该菜单项不暴露可按压动作（actions=\(actions)）：\(displayPath)")
    }

    // MARK: - 树查找

    private static func findItem(path: [String], in menuBar: AXUIElement) -> AXUIElement? {
        guard let (rootTitle, rest) = splitFirst(path) else { return nil }
        guard let rootItem = childItems(of: menuBar).first(where: {
            normalized(AX.string($0, .title)) == normalized(rootTitle)
        }) else { return nil }

        guard let submenu = submenu(of: rootItem) else { return nil }
        return descend(rest, in: submenu)
    }

    private static func descend(_ remaining: [String], in menu: AXUIElement) -> AXUIElement? {
        guard let (head, tail) = splitFirst(remaining) else { return nil }
        guard let item = childItems(of: menu).first(where: {
            normalized(AX.string($0, .title)) == normalized(head)
        }) else { return nil }

        if tail.isEmpty { return item }
        guard let submenu = submenu(of: item) else { return nil }
        return descend(tail, in: submenu)
    }

    private static func findItem(
        title: String,
        in menu: AXUIElement,
        path: [String]
    ) -> (AXUIElement, [String])? {
        for item in childItems(of: menu) {
            let itemTitle = (AX.string(item, .title) ?? "").trimmingCharacters(in: .whitespaces)
            guard !itemTitle.isEmpty else { continue }
            let currentPath = path + [itemTitle]

            if let submenu = submenu(of: item) {
                if let found = findItem(title: title, in: submenu, path: currentPath) {
                    return found
                }
                continue
            }
            if normalized(itemTitle) == normalized(title) {
                return (item, currentPath)
            }
        }
        return nil
    }

    private static func childItems(of menu: AXUIElement) -> [AXUIElement] {
        AX.array(menu, .children)
    }

    private static func submenu(of item: AXUIElement) -> AXUIElement? {
        for child in AX.array(item, .children) where AX.string(child, .role) == "AXMenu" {
            return child
        }
        return AX.element(item, .menu)
    }

    private static func splitFirst(_ array: [String]) -> (String, [String])? {
        guard let first = array.first else { return nil }
        return (first, Array(array.dropFirst()))
    }

    private static func normalized(_ raw: String?) -> String {
        (raw ?? "")
            .replacingOccurrences(of: "\u{2026}", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }
}
