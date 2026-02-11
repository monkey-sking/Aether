import Foundation
import Carbon.HIToolbox
import os

// MARK: - Data Model

struct HotkeyBinding: Codable, Equatable {
    var keyCode: Int       // CGKeyCode value
    var modifiers: UInt64  // CGEventFlags.rawValue (masked)

    /// Human-readable string like "⌃⌥S"
    var displayString: String {
        var parts: [String] = []
        let flags = CGEventFlags(rawValue: modifiers)
        if flags.contains(.maskControl)   { parts.append("⌃") }
        if flags.contains(.maskAlternate) { parts.append("⌥") }
        if flags.contains(.maskShift)     { parts.append("⇧") }
        if flags.contains(.maskCommand)   { parts.append("⌘") }
        if flags.contains(.maskAlphaShift) { parts.append("⇪") }
        parts.append(Self.keyName(for: keyCode))
        return parts.joined()
    }

    // Convert keyCode to a readable name
    static func keyName(for code: Int) -> String {
        switch code {
        case kVK_ANSI_A: return "A"
        case kVK_ANSI_B: return "B"
        case kVK_ANSI_C: return "C"
        case kVK_ANSI_D: return "D"
        case kVK_ANSI_E: return "E"
        case kVK_ANSI_F: return "F"
        case kVK_ANSI_G: return "G"
        case kVK_ANSI_H: return "H"
        case kVK_ANSI_I: return "I"
        case kVK_ANSI_J: return "J"
        case kVK_ANSI_K: return "K"
        case kVK_ANSI_L: return "L"
        case kVK_ANSI_M: return "M"
        case kVK_ANSI_N: return "N"
        case kVK_ANSI_O: return "O"
        case kVK_ANSI_P: return "P"
        case kVK_ANSI_Q: return "Q"
        case kVK_ANSI_R: return "R"
        case kVK_ANSI_S: return "S"
        case kVK_ANSI_T: return "T"
        case kVK_ANSI_U: return "U"
        case kVK_ANSI_V: return "V"
        case kVK_ANSI_W: return "W"
        case kVK_ANSI_X: return "X"
        case kVK_ANSI_Y: return "Y"
        case kVK_ANSI_Z: return "Z"
        case kVK_ANSI_0: return "0"
        case kVK_ANSI_1: return "1"
        case kVK_ANSI_2: return "2"
        case kVK_ANSI_3: return "3"
        case kVK_ANSI_4: return "4"
        case kVK_ANSI_5: return "5"
        case kVK_ANSI_6: return "6"
        case kVK_ANSI_7: return "7"
        case kVK_ANSI_8: return "8"
        case kVK_ANSI_9: return "9"
        case kVK_F1:  return "F1"
        case kVK_F2:  return "F2"
        case kVK_F3:  return "F3"
        case kVK_F4:  return "F4"
        case kVK_F5:  return "F5"
        case kVK_F6:  return "F6"
        case kVK_F7:  return "F7"
        case kVK_F8:  return "F8"
        case kVK_F9:  return "F9"
        case kVK_F10: return "F10"
        case kVK_F11: return "F11"
        case kVK_F12: return "F12"
        case kVK_Space:  return "Space"
        case kVK_Return: return "Return"
        case kVK_Tab:    return "Tab"
        case kVK_Delete: return "Delete"
        case kVK_Escape: return "Esc"
        case kVK_LeftArrow:  return "←"
        case kVK_RightArrow: return "→"
        case kVK_UpArrow:    return "↑"
        case kVK_DownArrow:  return "↓"
        default: return "Key(\(code))"
        }
    }
}

// MARK: - Actions

enum HotkeyAction: String, CaseIterable, Codable, Identifiable {
    case toggleTracking
    case connectionLock
    case pushToTalk

    var id: String { rawValue }

    var label: String {
        switch self {
        case .toggleTracking: return String(localized: "hotkey.toggle_tracking")
        case .connectionLock: return String(localized: "hotkey.connection_lock")
        case .pushToTalk:     return String(localized: "hotkey.push_to_talk")
        }
    }

    var defaultBinding: HotkeyBinding {
        switch self {
        case .toggleTracking:
            return HotkeyBinding(keyCode: kVK_ANSI_S, modifiers: Self.ctrlAlt)
        case .connectionLock:
            return HotkeyBinding(keyCode: kVK_ANSI_A, modifiers: Self.ctrlAlt)
        case .pushToTalk:
            return HotkeyBinding(keyCode: kVK_ANSI_V, modifiers: Self.ctrlAlt)
        }
    }

    private static let ctrlAlt: UInt64 =
        CGEventFlags.maskControl.rawValue | CGEventFlags.maskAlternate.rawValue
}

// MARK: - Manager

@MainActor
final class HotkeyManager: ObservableObject {
    static let shared = HotkeyManager()
    
    // Logger for debugging hotkey matches
    private let logger = Logger(subsystem: "com.7fei.Aether", category: "Hotkeys")

    @Published var bindings: [HotkeyAction: HotkeyBinding] {
        didSet { save() }
    }

    private static let storageKey = "AetherHotkeyBindings"
    private static let modifierMask: UInt64 =
        CGEventFlags.maskControl.rawValue |
        CGEventFlags.maskAlternate.rawValue |
        CGEventFlags.maskShift.rawValue |
        CGEventFlags.maskCommand.rawValue |
        CGEventFlags.maskAlphaShift.rawValue

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.storageKey),
           let saved = try? JSONDecoder().decode([HotkeyAction: HotkeyBinding].self, from: data) {
            self.bindings = saved
        } else {
            var defaults: [HotkeyAction: HotkeyBinding] = [:]
            for action in HotkeyAction.allCases {
                defaults[action] = action.defaultBinding
            }
            self.bindings = defaults
        }
    }

    /// Called from Event Tap to match a keyDown event.
    /// Thread-safe: only reads data, and bindings dict is value-type snapshot.
    nonisolated func matchKeyDown(keyCode: Int64, flags: CGEventFlags) -> HotkeyAction? {
        // Capture bindings snapshot — this is safe because Dictionary is a value type
        // and @Published writes happen on MainActor.
        let snapshot = MainActor.assumeIsolated { bindings }
        
        // Setup local logger (thread-safe struct) since we are nonisolated
        let log = Logger(subsystem: "com.7fei.Aether", category: "Hotkeys")
        
        // Basic mask for standard modifiers
        let maskedFlags = flags.rawValue & Self.modifierMask
        
        // Check physical state of Caps Lock (0x39 / 57)
        // This solves the "toggle" issue where users must turn the LED on/off to trigger.
        // true if physically held down, false otherwise.
        let isCapsLockPhysicallyDown = CGEventSource.keyState(.hidSystemState, key: 57) // kVK_CapsLock
        
        // Debug Log
        log.debug("EventTap KeyDown: code=\(keyCode), flags=\(flags.rawValue, format: .hex), capsPhys=\(isCapsLockPhysicallyDown)")

        for (action, binding) in snapshot {
            // 1. Check KeyCode
            guard binding.keyCode == Int(keyCode) else { continue }
            
            // 2. Check Modifiers
            // We need to compare the binding's modifiers with the event's flags,
            // BUT we handle Caps Lock specially.
            
            let bindingFlags = CGEventFlags(rawValue: binding.modifiers)
            let bindingHasCapsLock = bindingFlags.contains(.maskAlphaShift)
            
            // Removing Caps Lock from both sides for comparison of other modifiers
            let bindingWithoutCaps = binding.modifiers & ~CGEventFlags.maskAlphaShift.rawValue
            let eventWithoutCaps = maskedFlags & ~CGEventFlags.maskAlphaShift.rawValue
            
            // Check standard modifiers (Ctrl, Opt, Cmd, Shift)
            guard bindingWithoutCaps == eventWithoutCaps else { continue }
            
            // Check Caps Lock:
            // If binding needs it -> Physical key must be DOWN
            // If binding doesn't need it -> Physical key must be UP (strict matching)
            // Note: Use '!=' so false != true (pass) only if states match
            if bindingHasCapsLock != isCapsLockPhysicallyDown {
                 log.debug("Mismatch Caps: binding needs \(bindingHasCapsLock), physical is \(isCapsLockPhysicallyDown)")
                continue
            }
            
            log.info("Matched Action: \(action.rawValue)")
            return action
        }
        return nil
    }

    func setBinding(_ action: HotkeyAction, keyCode: Int, modifiers: UInt64) {
        let maskedModifiers = modifiers & Self.modifierMask
        bindings[action] = HotkeyBinding(keyCode: keyCode, modifiers: maskedModifiers)
        logger.info("Set binding for \(action.rawValue): code=\(keyCode), mods=\(maskedModifiers, format: .hex)")
    }

    func resetToDefaults() {
        var defaults: [HotkeyAction: HotkeyBinding] = [:]
        for action in HotkeyAction.allCases {
            defaults[action] = action.defaultBinding
        }
        bindings = defaults
        logger.info("Reset all bindings to defaults")
    }

    func resetAction(_ action: HotkeyAction) {
        bindings[action] = action.defaultBinding
        logger.info("Reset binding for \(action.rawValue)")
    }

    func binding(for action: HotkeyAction) -> HotkeyBinding {
        bindings[action] ?? action.defaultBinding
    }

    /// The keyCode of the current PTT binding, for keyUp matching.
    /// Nonisolated so it can be called from the Event Tap callback.
    nonisolated var pttKeyCode: Int {
        MainActor.assumeIsolated { binding(for: .pushToTalk).keyCode }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(bindings) {
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        }
    }
}
