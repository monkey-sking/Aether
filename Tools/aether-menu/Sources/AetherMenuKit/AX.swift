import ApplicationServices

/// AX 属性读取的小封装。
///
/// 注意：属性名用字符串字面量而不是 `kAX*` 常量。实测在纯 SwiftPM
/// 命令行目标里，`kAX*` 常量会被推断成 `String` 而非 `CFString`，
/// 导致编译期类型不匹配；字符串字面量 `as CFString` 是稳定做法。
public enum AX {
    public enum Attr {
        case role
        case title
        case enabled
        case children
        case windows
        case menuBar
        case menu
        case menuItemCmdChar
        case menuItemCmdModifiers
        case menuItemCmdVirtualKey

        public var name: CFString {
            switch self {
            case .role: return "AXRole" as CFString
            case .title: return "AXTitle" as CFString
            case .enabled: return "AXEnabled" as CFString
            case .children: return "AXChildren" as CFString
            case .windows: return "AXWindows" as CFString
            case .menuBar: return "AXMenuBar" as CFString
            case .menu: return "AXMenu" as CFString
            case .menuItemCmdChar: return "AXMenuItemCmdChar" as CFString
            case .menuItemCmdModifiers: return "AXMenuItemCmdModifiers" as CFString
            case .menuItemCmdVirtualKey: return "AXMenuItemCmdVirtualKey" as CFString
            }
        }
    }

    public static func string(_ element: AXUIElement, _ attr: Attr) -> String? {
        var value: AnyObject?
        guard AXUIElementCopyAttributeValue(element, attr.name, &value) == .success else {
            return nil
        }
        return value as? String
    }

    public static func int(_ element: AXUIElement, _ attr: Attr) -> Int? {
        var value: AnyObject?
        guard AXUIElementCopyAttributeValue(element, attr.name, &value) == .success else {
            return nil
        }
        if let number = value as? NSNumber { return number.intValue }
        return value as? Int
    }

    public static func bool(_ element: AXUIElement, _ attr: Attr) -> Bool? {
        var value: AnyObject?
        guard AXUIElementCopyAttributeValue(element, attr.name, &value) == .success else {
            return nil
        }
        if let number = value as? NSNumber { return number.boolValue }
        return value as? Bool
    }

    public static func element(_ element: AXUIElement, _ attr: Attr) -> AXUIElement? {
        var value: AnyObject?
        guard AXUIElementCopyAttributeValue(element, attr.name, &value) == .success else {
            return nil
        }
        guard let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    public static func array(_ element: AXUIElement, _ attr: Attr) -> [AXUIElement] {
        var value: AnyObject?
        guard AXUIElementCopyAttributeValue(element, attr.name, &value) == .success else {
            return []
        }
        return (value as? [AXUIElement]) ?? []
    }

    /// 访问辅助功能（Accessibility）是否已授权。
    public static var isTrusted: Bool { AXIsProcessTrusted() }

    /// 请求辅助功能授权（会弹系统对话框）。
    @discardableResult
    public static func requestTrust() -> Bool {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }
}
