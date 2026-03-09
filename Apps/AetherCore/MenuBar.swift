import SwiftUI

struct AetherMenuBar: Scene {
    @EnvironmentObject private var appState: AppState
    @Environment(\.openWindow) private var openWindow

    private var isChinese: Bool {
        Locale.current.identifier.hasPrefix("zh")
    }

    private var driverReady: Bool {
        appState.driverStatus.contains("Connected") || appState.driverStatus.contains("Ready")
    }

    private var needsAttention: Bool {
        !appState.accessibilityTrusted ||
        !appState.microphoneAuthorized ||
        !appState.speechAuthorized ||
        appState.driverState == .needsUserApproval
    }

    private var statusTitle: String {
        if needsAttention {
            return String(localized: "menu.status.setup_attention")
        }
        if appState.isMotionTracking && appState.voiceActivationMode == .handsFree {
            return String(localized: "menu.status.voice_pointer_ready")
        }
        if appState.isMotionTracking {
            return String(localized: "menu.status.pointer_active")
        }
        return String(localized: "menu.status.ready")
    }

    private var statusSubtitle: String {
        if !appState.accessibilityTrusted {
            return String(localized: "menu.status.accessibility_missing")
        }
        if !appState.microphoneAuthorized {
            return String(localized: "menu.status.microphone_missing")
        }
        if !appState.speechAuthorized {
            return String(localized: "menu.status.speech_missing")
        }
        if appState.driverState == .needsUserApproval {
            return String(localized: "menu.status.driver_approval_needed")
        }
        return appState.voiceStatus
    }

    private var statusAccentColor: Color {
        if needsAttention { return .orange }
        if appState.isMotionTracking { return .green }
        return .secondary
    }

    var body: some Scene {
        MenuBarExtra {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Circle()
                        .fill(statusAccentColor)
                        .frame(width: 8, height: 8)
                    Text("Aether")
                        .font(.headline.weight(.semibold))
                }

                Text(statusTitle)
                    .font(.subheadline.weight(.medium))

                Text(statusSubtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, 4)

            if appState.driverState == .needsUserApproval {
                Button(String(localized: "menu.approve_driver")) {
                    appState.openPrivacyAndSecurityPane()
                }
            } else if !driverReady && appState.isMotionTracking {
                Button(L10n.menuActivateDriver) {
                    appState.activateDriver()
                }
            }

            if !appState.accessibilityTrusted {
                Button(String(localized: "menu.enable_accessibility")) {
                    appState.requestAccessibilityGuided()
                }
            }

            if !appState.microphoneAuthorized {
                Button(String(localized: "menu.enable_microphone")) {
                    appState.requestMicrophoneGuided()
                }
            }

            if !appState.speechAuthorized {
                Button(String(localized: "menu.enable_speech")) {
                    appState.requestSpeechGuided()
                }
            }

            Divider()

            Button(appState.isMotionTracking
                ? L10n.menuStopPointer(HotkeyManager.shared.binding(for: .toggleTracking).displayString)
                : L10n.menuStartPointer(HotkeyManager.shared.binding(for: .toggleTracking).displayString)) {
                appState.toggleMotionTracking()
            }

            Button(String(localized: "menu.toggle_input_control_mode")) {
                appState.toggleRecognitionInputControlMode()
            }

            Button(L10n.menuRecenterPointer) {
                appState.finishCalibration()
            }

            Button(
                CurrentAppShortcutPanelManager.shared.isVisible
                    ? String(localized: "menu.hide_shortcut_panel")
                    : String(
                        format: NSLocalizedString("menu.shortcut_panel_fmt", comment: ""),
                        HotkeyManager.shared.binding(for: .toggleShortcutPanel).displayString
                    )
            ) {
                appState.toggleShortcutPanel()
            }

            Button(String(localized: "menu.open_settings")) {
                GlobalLogger.lifecycle.info("Menu action: show main window")
                presentMainWindow()
            }

            Divider()

            Button(L10n.menuQuit) {
                NSApp.terminate(nil)
            }
        } label: {
            Image("MenuBarIcon")
                .renderingMode(.template)
        }
        .menuBarExtraStyle(.menu)
    }

    private func presentMainWindow() {
        openWindow(id: "main")
        NSApp.activate(ignoringOtherApps: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            guard let window = NSApp.windows.first(where: { $0.identifier?.rawValue == "AetherMainWindow" }) else {
                return
            }
            window.makeKeyAndOrderFront(nil)
        }
    }
}
