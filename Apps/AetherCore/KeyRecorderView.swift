import SwiftUI
import Carbon.HIToolbox
import CoreGraphics
import AppKit
import os

// MARK: - Hotkey Settings Section

struct ShortcutBadgeView: View {
    enum Style {
        case detailed
        case compact
    }

    let binding: HotkeyBinding
    var isRecording: Bool = false
    var minWidth: CGFloat? = nil
    var style: Style = .detailed

    var body: some View {
        let tokens = binding.visualDisplayTokens

        Group {
            if isRecording {
                Text(String(localized: "hotkey.press_key"))
                    .font(.system(.caption, design: .rounded).weight(.semibold))
                    .foregroundColor(.accentColor)
                    .frame(minWidth: minWidth)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(Color.accentColor.opacity(0.16))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.accentColor.opacity(0.8), lineWidth: 1)
                    )
            } else {
                if style == .compact {
                    HStack(spacing: 4) {
                        ForEach(Array(tokens.enumerated()), id: \.offset) { index, token in
                            compactTokenView(token, isPrimary: index == tokens.count - 1)
                        }
                    }
                    .frame(minWidth: minWidth, alignment: .trailing)
                } else {
                    HStack(spacing: 5) {
                        ForEach(Array(tokens.enumerated()), id: \.offset) { index, token in
                            Text(token.text)
                                .font(index == tokens.count - 1
                                      ? .system(.caption, design: .rounded).weight(.semibold)
                                      : .system(.caption2, design: .rounded).weight(.bold))
                                .foregroundColor(index == tokens.count - 1 ? .primary : .secondary)
                                .padding(.horizontal, index == tokens.count - 1 ? 8 : 6)
                                .padding(.vertical, 5)
                                .background(index == tokens.count - 1
                                            ? Color.accentColor.opacity(0.14)
                                            : Color(NSColor.windowBackgroundColor))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 7)
                                        .stroke(index == tokens.count - 1
                                                ? Color.accentColor.opacity(0.35)
                                                : Color.gray.opacity(0.18),
                                                lineWidth: 1)
                                )
                                .clipShape(RoundedRectangle(cornerRadius: 7))
                        }
                    }
                    .frame(minWidth: minWidth, alignment: .trailing)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(Color(NSColor.controlBackgroundColor))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.gray.opacity(0.18), lineWidth: 1)
                    )
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .contentShape(RoundedRectangle(cornerRadius: 10))
    }

    @ViewBuilder
    private func compactTokenView(_ token: HotkeyBinding.DisplayToken, isPrimary: Bool) -> some View {
        switch token.kind {
        case .mouseButton(let number):
            HStack(spacing: 3) {
                Image(systemName: "computermouse")
                    .font(.system(size: 11, weight: .medium))
                if let number {
                    Text("\(number + 1)")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                } else {
                    Text(token.text)
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                }
            }
            .foregroundColor(isPrimary ? .primary : .secondary)
        case .text:
            Text(token.text)
                .font(isPrimary
                      ? .system(size: 12, weight: .semibold, design: .monospaced)
                      : .system(size: 11, weight: .bold, design: .monospaced))
                .foregroundColor(isPrimary ? .primary : .secondary)
        }
    }
}

struct HotkeySettingsSection: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject var hotkeyManager = HotkeyManager.shared
    @State private var recordingAction: HotkeyAction? = nil // Exclusive recording state

    private var visibleActions: [HotkeyAction] {
        HotkeyAction.allCases.filter { $0 != .pushToTalk || appState.voiceActivationMode == .pushToTalk }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(String(localized: "hotkey.section_title"))
                        .font(.headline)
                    Text(localeAwareSubtitle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Button(String(localized: "hotkey.reset_all")) {
                    hotkeyManager.resetToDefaults()
                }
                .font(.caption)
                .controlSize(.small)
                .buttonStyle(.bordered)
            }

            VStack(spacing: 10) {
                ForEach(visibleActions) { action in
                    KeyRecorderRow(action: action, recordingAction: $recordingAction)
                }
            }
        }
        .padding(16)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(14)
    }

    private var localeAwareSubtitle: String {
        if AppLocalization.isChinese {
            return "点击某一项后按下单键、特殊键或组合键，按 Esc 取消。"
        } else {
            return "Click a shortcut, then press a single key, special key, or key combination. Press Esc to cancel."
        }
    }
}

// MARK: - Single Row

struct KeyRecorderRow: View {
    let action: HotkeyAction
    @Binding var recordingAction: HotkeyAction? // Shared state
    @ObservedObject private var hotkeyManager = HotkeyManager.shared
    @State private var isHovering: Bool = false

    var isRecording: Bool { recordingAction == action }

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(action.label)
                    .font(.callout.weight(.medium))
                Text(helperText)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .frame(minWidth: 180, alignment: .leading)

            Spacer()

            Button(action: {
                if isRecording {
                    recordingAction = nil
                } else {
                    recordingAction = action
                }
            }) {
                ShortcutBadgeView(
                    binding: hotkeyManager.binding(for: action),
                    isRecording: isRecording,
                    minWidth: 96
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(action.label))
            .accessibilityHint(Text(String(localized: "hotkey.press_key")))
            .background(
                isRecording ? KeyRecorderHelper(
                    allowBareKeys: true,
                    onRecord: { keyCode, modifiers, mouseButton in
                        if let button = mouseButton {
                            hotkeyManager.setMouseBinding(action, button: button, modifiers: modifiers)
                        } else {
                            hotkeyManager.setBinding(action, keyCode: keyCode, modifiers: modifiers)
                        }
                        recordingAction = nil
                    },
                    onCancel: { recordingAction = nil }
                ) : nil
            )

            Button(action: { hotkeyManager.resetAction(action) }) {
                Image(systemName: "arrow.counterclockwise")
                    .font(.caption)
            }
            .buttonStyle(.borderless)
            .controlSize(.small)
            .accessibilityLabel(Text(String(localized: "hotkey.reset_single")))
            .help(String(localized: "hotkey.reset_single"))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(isHovering ? 0.75 : 0.55))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.black.opacity(isHovering ? 0.12 : 0.06), lineWidth: 1)
        )
        .onHover { hovering in
            isHovering = hovering
        }
    }

    private var helperText: String {
        action.helperText
    }
}

// MARK: - NSView-based Key Recorder

/// An invisible NSView that captures the next key event when active.
struct KeyRecorderHelper: NSViewRepresentable {
    var allowBareKeys: Bool = false
    var onRecord: (Int, UInt64, Int?) -> Void
    var onCancel: () -> Void

    func makeNSView(context: Context) -> KeyRecorderNSView {
        let view = KeyRecorderNSView()
        view.allowBareKeys = allowBareKeys
        view.onRecord = onRecord
        view.onCancel = onCancel
        // Ensure it can become first responder
        DispatchQueue.main.async { view.window?.makeFirstResponder(view) }
        return view
    }

    func updateNSView(_ nsView: KeyRecorderNSView, context: Context) {
        nsView.allowBareKeys = allowBareKeys
        nsView.onRecord = onRecord
        nsView.onCancel = onCancel
        // Keep focus if still valid
        if nsView.window?.firstResponder != nsView {
             DispatchQueue.main.async { nsView.window?.makeFirstResponder(nsView) }
        }
    }
}

final class KeyRecorderNSView: NSView {
    private let logger = Logger(subsystem: "com.7fei.Aether", category: "KeyRecorder")
    var allowBareKeys: Bool = false
    var onRecord: ((Int, UInt64, Int?) -> Void)?
    var onCancel: (() -> Void)?
    
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var pendingModifierOnlyRecord: (keyCode: Int, flags: UInt64)?
    private var sawNonModifierKeyAfterPendingModifier = false

    override var acceptsFirstResponder: Bool { true }
    
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let window = window {
            startMonitoring()
            // Listen for window losing focus
            NotificationCenter.default.addObserver(self, selector: #selector(handleWindowResignKey), name: NSWindow.didResignKeyNotification, object: window)
        } else {
            stopMonitoring()
            NotificationCenter.default.removeObserver(self, name: NSWindow.didResignKeyNotification, object: nil)
        }
    }
    
    deinit {
        stopMonitoring()
        NotificationCenter.default.removeObserver(self)
    }
    
    @objc private func handleWindowResignKey() {
        logger.info("Window resigned key, cancelling recording")
        onCancel?()
    }
    
    private func startMonitoring() {
        stopMonitoring()
        
        let eventsOfInterest: CGEventMask =
            (CGEventMask(1) << CGEventType.keyDown.rawValue) |
            (CGEventMask(1) << CGEventType.flagsChanged.rawValue) |
            (CGEventMask(1) << CGEventType.rightMouseDown.rawValue) |
            (CGEventMask(1) << CGEventType.otherMouseDown.rawValue)
        
        let context = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventsOfInterest,
            callback: { (proxy, type, event, refcon) -> Unmanaged<CGEvent>? in
                guard let refcon = refcon else { return Unmanaged.passUnretained(event) }
                let view = Unmanaged<KeyRecorderNSView>.fromOpaque(refcon).takeUnretainedValue()
                
                // Process on main thread to be safe with UI/State
                DispatchQueue.main.async {
                    view.handleCGEvent(type: type, event: event)
                }
                
                // Consume event if it's a target match, to prevent system side effects during recording
                return nil
            },
            userInfo: context
        ) else {
            logger.error("Failed to create event tap for recording")
            return
        }
        
        self.eventTap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        self.runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        
        logger.info("Started CGEventTap monitoring for recording")
    }
    
    private func stopMonitoring() {
        pendingModifierOnlyRecord = nil
        sawNonModifierKeyAfterPendingModifier = false
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
            runLoopSource = nil
        }
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            // CFMachPortInvalidate(tap) // Optional, but good practice
            eventTap = nil
        }
    }
    
    private func handleCGEvent(type: CGEventType, event: CGEvent) {
        // Handle Mouse
        if type == .leftMouseDown || type == .rightMouseDown || type == .otherMouseDown {
            let btn = Int(event.getIntegerValueField(.mouseEventButtonNumber))
            let flags = event.flags.rawValue
            logger.info("CGEvent Recorded Mouse: \(btn) flags: \(flags)")
            onRecord?(-1, flags, btn)
            return
        }

        if type == .flagsChanged {
            handleModifierOnlyFlagsChanged(
                keyCode: Int(event.getIntegerValueField(.keyboardEventKeycode)),
                flags: event.flags
            )
            return
        }
        
        // Handle Key
        if type == .keyDown {
            let keyCode = Int(event.getIntegerValueField(.keyboardEventKeycode))
            let flags = event.flags
            pendingModifierOnlyRecord = nil
            sawNonModifierKeyAfterPendingModifier = true
            
            // Filter bare escape
            let activeMods = flags.intersection([.maskControl, .maskAlternate, .maskShift, .maskCommand])
            let isCaps = flags.contains(.maskAlphaShift) // rough check
            
            if keyCode == kVK_Escape && activeMods.isEmpty && !isCaps {
                onCancel?()
                return
            }
            
            // We need to map CGEventFlags back to our internal usage (which matches CGEventFlags largely)
            // HotkeyManager uses CGEventFlags.rawValue.
            // But we want to ensure we capture the modifiers correctly.
            
            if !allowBareKeys && activeMods.isEmpty && !isCaps {
                logger.debug("Ignored bare key (CG): \(keyCode)")
                return
            }
            
            logger.info("CGEvent Recorded Key: \(keyCode) flags: \(flags.rawValue)")
            onRecord?(keyCode, flags.rawValue, nil)
        }
    }

    override func keyDown(with event: NSEvent) {
        let keyCode = Int(event.keyCode)

        // Bare Escape (no modifiers) cancels recording.
        // Escape WITH modifiers (e.g. Ctrl+Esc) is allowed as a hotkey.
        let stdMods: NSEvent.ModifierFlags = [.control, .option, .shift, .command]
        let hasStdMod = !event.modifierFlags.intersection(stdMods).isEmpty
        let isCapsHeld = CGEventSource.keyState(.hidSystemState, key: 57)
        if keyCode == kVK_Escape && !hasStdMod && !isCapsHeld {
            onCancel?()
            return
        }

        // Require at least one modifier
        // Strict approach: Check ONLY physical state for Caps Lock.
        // We ignore the system's Caps Lock flag (LED state) to enforce "Hold to Modify".
        // This ensures the user learns they must hold the key to trigger the hotkey later.
        
        // Exclude .capsLock from mask so we don't pick up the toggle state
        let modifierMask: NSEvent.ModifierFlags = [.control, .option, .shift, .command]
        let activeModifiers = event.modifierFlags.intersection(modifierMask)
        
        // check physical caps lock
        let isCapsLockDown = CGEventSource.keyState(.hidSystemState, key: 57)
        
        if !allowBareKeys && activeModifiers.isEmpty && !isCapsLockDown {
            logger.debug("Ignored bare key: \(keyCode), mods=\(activeModifiers.rawValue)")
            return
        }

        // Convert NSEvent modifiers to CGEventFlags
        var cgFlags: UInt64 = 0
        if activeModifiers.contains(.control)  { cgFlags |= CGEventFlags.maskControl.rawValue }
        if activeModifiers.contains(.option)   { cgFlags |= CGEventFlags.maskAlternate.rawValue }
        if activeModifiers.contains(.shift)    { cgFlags |= CGEventFlags.maskShift.rawValue }
        if activeModifiers.contains(.command)  { cgFlags |= CGEventFlags.maskCommand.rawValue }
        
        // Use strict physical state for Caps Lock flag
        if isCapsLockDown {
            cgFlags |= CGEventFlags.maskAlphaShift.rawValue
        }

        logger.info("Recorded Key: code=\(keyCode), flags=\(cgFlags, format: .hex)")
        onRecord?(keyCode, cgFlags, nil)
    }

    override func flagsChanged(with event: NSEvent) {
        handleModifierOnlyFlagsChanged(
            keyCode: Int(event.keyCode),
            flags: cgFlags(from: event.modifierFlags, includePhysicalCapsLock: true)
        )
    }
    
    private func handleMouse(_ event: NSEvent) {
        let button = event.buttonNumber
        let type = event.type
        
        // Map Right Click (type .rightMouseDown) usually button 1? 
        // Or just trust buttonNumber.
        
        logger.info("Recorded Mouse: button=\(button) type=\(type.rawValue)")
        
        // Pass to callback
        // Note: For Right Click, buttonNumber is 1.
        onRecord?(-1, 0, button)
    }
    
    // We keep overrides just in case, though LocalMonitor should catch them first.
    override func otherMouseDown(with event: NSEvent) { handleMouse(event) }
    override func rightMouseDown(with event: NSEvent) { handleMouse(event) }

    private func handleModifierOnlyFlagsChanged(keyCode: Int, flags: CGEventFlags) {
        guard allowBareKeys else {
            pendingModifierOnlyRecord = nil
            sawNonModifierKeyAfterPendingModifier = false
            return
        }

        let activeFlags = flags.intersection([.maskControl, .maskAlternate, .maskShift, .maskCommand, .maskAlphaShift])
        let isModifierDown = Self.isModifierKeyDown(eventKeyCode: keyCode, flags: activeFlags)

        if isModifierDown {
            pendingModifierOnlyRecord = (keyCode: keyCode, flags: activeFlags.rawValue)
            sawNonModifierKeyAfterPendingModifier = false
            logger.info("Pending modifier-only record: code=\(keyCode), flags=\(activeFlags.rawValue, format: .hex)")
            return
        }

        guard activeFlags.isEmpty else { return }
        guard let pending = pendingModifierOnlyRecord, !sawNonModifierKeyAfterPendingModifier else {
            pendingModifierOnlyRecord = nil
            sawNonModifierKeyAfterPendingModifier = false
            return
        }

        logger.info("Recorded modifier-only key: code=\(pending.keyCode), flags=\(pending.flags, format: .hex)")
        onRecord?(pending.keyCode, pending.flags, nil)
        pendingModifierOnlyRecord = nil
        sawNonModifierKeyAfterPendingModifier = false
    }

    private func cgFlags(from flags: NSEvent.ModifierFlags, includePhysicalCapsLock: Bool) -> CGEventFlags {
        var cgFlags: CGEventFlags = []
        let activeModifiers = flags.intersection([.control, .option, .shift, .command])
        if activeModifiers.contains(.control) { cgFlags.insert(.maskControl) }
        if activeModifiers.contains(.option) { cgFlags.insert(.maskAlternate) }
        if activeModifiers.contains(.shift) { cgFlags.insert(.maskShift) }
        if activeModifiers.contains(.command) { cgFlags.insert(.maskCommand) }
        if includePhysicalCapsLock && CGEventSource.keyState(.hidSystemState, key: 57) {
            cgFlags.insert(.maskAlphaShift)
        }
        return cgFlags
    }

    private static func isModifierKeyDown(eventKeyCode: Int, flags: CGEventFlags) -> Bool {
        switch eventKeyCode {
        case Int(kVK_Shift), Int(kVK_RightShift):
            return flags.contains(.maskShift)
        case Int(kVK_Control), Int(kVK_RightControl):
            return flags.contains(.maskControl)
        case Int(kVK_Option), Int(kVK_RightOption):
            return flags.contains(.maskAlternate)
        case Int(kVK_Command), Int(kVK_RightCommand):
            return flags.contains(.maskCommand)
        case Int(kVK_CapsLock):
            return flags.contains(.maskAlphaShift)
        default:
            return false
        }
    }
}

// MARK: - Standalone Key Recorder

/// A standalone recorder for a single HotkeyBinding.
struct KeyRecorderView: View {
    @Binding var binding: HotkeyBinding
    var allowBareKeys: Bool = false
    var onChange: (HotkeyBinding) -> Void
    var font: Font = .body
    
    @StateObject private var hotkeyManager = HotkeyManager.shared
    @State private var isRecording: Bool = false
    
    var body: some View {
        Button(action: {
            isRecording.toggle()
        }) {
            ShortcutBadgeView(
                binding: binding,
                isRecording: isRecording,
                minWidth: 120
            )
        }
        .buttonStyle(.plain)
        .background(
            isRecording ? KeyRecorderHelper(
                allowBareKeys: allowBareKeys,
                onRecord: { keyCode, modifiers, mouseButton in
                    let newBinding: HotkeyBinding
                    if let btn = mouseButton {
                        newBinding = HotkeyBinding(keyCode: 1000 + btn, modifiers: modifiers)
                    } else {
                        newBinding = HotkeyBinding(keyCode: keyCode, modifiers: modifiers)
                    }
                    
                    self.binding = newBinding
                    onChange(newBinding)
                    isRecording = false
                },
                onCancel: {
                    isRecording = false
                }
            ) : nil
        )
    }
}
