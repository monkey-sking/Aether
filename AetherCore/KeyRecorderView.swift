import SwiftUI
import Carbon.HIToolbox
import CoreGraphics
import AppKit
import os

// MARK: - Hotkey Settings Section

struct HotkeySettingsSection: View {
    @ObservedObject var hotkeyManager = HotkeyManager.shared
    @State private var recordingAction: HotkeyAction? = nil // Exclusive recording state

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
            }

            VStack(spacing: 10) {
                ForEach(HotkeyAction.allCases) { action in
                    KeyRecorderRow(action: action, recordingAction: $recordingAction)
                }
            }
        }
        .padding(16)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(14)
    }

    private var localeAwareSubtitle: String {
        if Locale.current.identifier.hasPrefix("zh") {
            return "点击某一项后按下新的组合键，按 Esc 取消。"
        } else {
            return "Click a shortcut, then press the new key combination. Press Esc to cancel."
        }
    }
}

// MARK: - Single Row

struct KeyRecorderRow: View {
    let action: HotkeyAction
    @Binding var recordingAction: HotkeyAction? // Shared state
    @ObservedObject private var hotkeyManager = HotkeyManager.shared

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
                Text(isRecording
                     ? String(localized: "hotkey.press_key")
                     : hotkeyManager.binding(for: action).displayString)
                    .font(.system(.caption, design: .monospaced))
                    .frame(minWidth: 84)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(isRecording
                                ? Color.accentColor.opacity(0.18)
                                : Color(nsColor: .windowBackgroundColor))
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(isRecording ? Color.accentColor : Color.gray.opacity(0.25), lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            .background(
                isRecording ? KeyRecorderHelper(
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
            .buttonStyle(.plain)
            .help(String(localized: "hotkey.reset_single"))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color(nsColor: .windowBackgroundColor))
        .cornerRadius(10)
    }

    private var helperText: String {
        switch action {
        case .pushToTalk:
            return Locale.current.identifier.hasPrefix("zh") ? "语音按住说话" : "Hold to speak"
        case .toggleTracking:
            return Locale.current.identifier.hasPrefix("zh") ? "启动或停止头控" : "Start or stop pointer tracking"
        case .connectionLock:
            return Locale.current.identifier.hasPrefix("zh") ? "切换连接锁定" : "Toggle connection lock"
        case .toggleInputControlMode:
            return Locale.current.identifier.hasPrefix("zh") ? "切换输入控制模式" : "Switch input control mode"
        case .toggleLanguage:
            return Locale.current.identifier.hasPrefix("zh") ? "切换语音语言" : "Switch dictation language"
        case .toggleShortcutPanel:
            return Locale.current.identifier.hasPrefix("zh") ? "显示或关闭当前应用快捷键面板" : "Show or hide the current app shortcuts panel"
        }
    }
}

// MARK: - NSView-based Key Recorder

/// An invisible NSView that captures the next key event when active.
struct KeyRecorderHelper: NSViewRepresentable {
    var onRecord: (Int, UInt64, Int?) -> Void
    var onCancel: () -> Void

    func makeNSView(context: Context) -> KeyRecorderNSView {
        let view = KeyRecorderNSView()
        view.onRecord = onRecord
        view.onCancel = onCancel
        // Ensure it can become first responder
        DispatchQueue.main.async { view.window?.makeFirstResponder(view) }
        return view
    }

    func updateNSView(_ nsView: KeyRecorderNSView, context: Context) {
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
    var onRecord: ((Int, UInt64, Int?) -> Void)?
    var onCancel: (() -> Void)?
    
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

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
        
        // Handle Key
        if type == .keyDown {
            let keyCode = Int(event.getIntegerValueField(.keyboardEventKeycode))
            let flags = event.flags
            
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
            
            // Check for at least one modifier OR caps lock
            if activeMods.isEmpty && !isCaps {
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
        
        // If no standard modifiers and no physical caps lock, ignore (bare key)
        if activeModifiers.isEmpty && !isCapsLockDown {
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
}

// MARK: - Standalone Key Recorder

/// A standalone recorder for a single HotkeyBinding.
struct KeyRecorderView: View {
    @Binding var binding: HotkeyBinding
    var onChange: (HotkeyBinding) -> Void
    var font: Font = .body
    
    @StateObject private var hotkeyManager = HotkeyManager.shared
    @State private var isRecording: Bool = false
    
    var body: some View {
        Button(action: {
            isRecording.toggle()
        }) {
            Text(isRecording ? String(localized: "hotkey.press_key") : binding.displayString)
                .font(font.monospaced())
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(isRecording
                            ? Color.accentColor.opacity(0.2)
                            : Color(NSColor.controlBackgroundColor))
                .cornerRadius(6)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(isRecording ? Color.accentColor : Color.gray.opacity(0.3), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .background(
            isRecording ? KeyRecorderHelper(
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
