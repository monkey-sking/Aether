import SwiftUI
import Carbon.HIToolbox
import os

// MARK: - Hotkey Settings Section

struct HotkeySettingsSection: View {
    @ObservedObject var hotkeyManager = HotkeyManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(String(localized: "hotkey.section_title"))
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Button(String(localized: "hotkey.reset_all")) {
                    hotkeyManager.resetToDefaults()
                }
                .font(.caption2)
                .controlSize(.mini)
            }

            ForEach(HotkeyAction.allCases) { action in
                KeyRecorderRow(action: action)
            }
        }
        .padding(8)
        .background(Color.black.opacity(0.06))
        .cornerRadius(8)
    }
}

// MARK: - Single Row

struct KeyRecorderRow: View {
    let action: HotkeyAction
    @ObservedObject private var hotkeyManager = HotkeyManager.shared
    @State private var isRecording = false

    var body: some View {
        HStack(spacing: 8) {
            Text(action.label)
                .font(.callout)
                .frame(minWidth: 120, alignment: .leading)

            Spacer()

            // Key display / recorder button
            Button(action: { isRecording.toggle() }) {
                Text(isRecording
                     ? String(localized: "hotkey.press_key")
                     : hotkeyManager.binding(for: action).displayString)
                    .font(.system(.caption, design: .monospaced))
                    .frame(minWidth: 60)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
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
                    onRecord: { keyCode, modifiers in
                        hotkeyManager.setBinding(action, keyCode: keyCode, modifiers: modifiers)
                        isRecording = false
                    },
                    onCancel: { isRecording = false }
                ) : nil
            )

            // Reset single action
            Button(action: { hotkeyManager.resetAction(action) }) {
                Image(systemName: "arrow.counterclockwise")
                    .font(.caption2)
            }
            .buttonStyle(.plain)
            .help(String(localized: "hotkey.reset_single"))
        }
    }
}

// MARK: - NSView-based Key Recorder

/// An invisible NSView that captures the next key event when active.
struct KeyRecorderHelper: NSViewRepresentable {
    var onRecord: (Int, UInt64) -> Void
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
        DispatchQueue.main.async { nsView.window?.makeFirstResponder(nsView) }
    }
}

final class KeyRecorderNSView: NSView {
    private let logger = Logger(subsystem: "com.7fei.Aether", category: "KeyRecorder")
    var onRecord: ((Int, UInt64) -> Void)?
    var onCancel: (() -> Void)?

    override var acceptsFirstResponder: Bool { true }

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

        logger.info("Recorded: code=\(keyCode), flags=\(cgFlags, format: .hex) (PhysCaps=\(isCapsLockDown))")
        onRecord?(keyCode, cgFlags)
    }
}
