import SwiftUI

struct AetherMenuBar: Scene {
    @EnvironmentObject private var appState: AppState
    @Environment(\.openWindow) private var openWindow

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

    var body: some Scene {
        MenuBarExtra(String(localized: "app.project_title"), systemImage: "antenna.radiowaves.left.and.right") {
            VStack(alignment: .leading, spacing: 12) {
                MenuBarHeaderCard(
                    title: statusTitle,
                    subtitle: statusSubtitle,
                    tint: needsAttention ? .orange : .green
                )

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

                Button(L10n.menuRecenterPointer) {
                    appState.finishCalibration()
                }

                Button(
                    String(
                        format: NSLocalizedString("menu.shortcut_panel_fmt", comment: ""),
                        HotkeyManager.shared.binding(for: .toggleShortcutPanel).displayString
                    )
                ) {
                    appState.toggleShortcutPanel()
                }

                Button(String(localized: "menu.open_settings")) {
                    GlobalLogger.lifecycle.info("Menu action: show main window")
                    openWindow(id: "main")
                    NSApp.activate(ignoringOtherApps: true)
                }

                Menu(String(localized: "menu.more_controls")) {
                    Toggle(
                        L10n.alwaysListening,
                        isOn: Binding(
                            get: { appState.voiceActivationMode == .handsFree },
                            set: { appState.voiceActivationMode = $0 ? .handsFree : .pushToTalk }
                        )
                    )

                    Toggle(L10n.llmEnhanceDictation, isOn: $appState.isLLMEnhancementEnabled)

                    Toggle(
                        L10n.menuAirPodsLock(HotkeyManager.shared.binding(for: .connectionLock).displayString),
                        isOn: Binding(
                            get: { appState.connectionLock.isLocked },
                            set: { _ in appState.connectionLock.toggle() }
                        )
                    )
                }

                Divider()

                Button(L10n.menuQuit) {
                    NSApp.terminate(nil)
                }
            }
            .padding(12)
            .frame(minWidth: 280)
        }
    }
}

private struct MenuBarHeaderCard: View {
    let title: String
    let subtitle: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Circle()
                    .fill(tint)
                    .frame(width: 8, height: 8)
                Text(title)
                    .font(.headline)
            }
            Text(subtitle)
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(12)
    }
}
