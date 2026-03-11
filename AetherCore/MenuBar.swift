import SwiftUI

struct AetherMenuBar: Scene {
    @EnvironmentObject private var appState: AppState
    @Environment(\.openWindow) private var openWindow

    private var isChinese: Bool {
        Locale.current.identifier.hasPrefix("zh")
    }

    private var needsAttention: Bool {
        !appState.accessibilityTrusted ||
        !appState.microphoneAuthorized ||
        !appState.speechAuthorized
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
        return appState.voiceStatus
    }

    private var statusAccentColor: Color {
        if needsAttention { return .orange }
        if appState.isMotionTracking { return .green }
        return .secondary
    }

    private var statusSymbolName: String {
        if needsAttention { return "exclamationmark.triangle.fill" }
        if appState.isMotionTracking { return "viewfinder.circle.fill" }
        return "waveform.circle.fill"
    }

    private var statusSummary: String {
        if needsAttention {
            return statusSubtitle
        }
        if !appState.voiceStatus.isEmpty && appState.voiceStatus != statusTitle {
            return appState.voiceStatus
        }
        return statusTitle
    }

    var body: some Scene {
        MenuBarExtra {
            Text(LocalizedStringKey("Aether"))

            Label(statusSummary, systemImage: statusSymbolName)

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

            Button(String(localized: appState.isMotionTracking ? "menu.stop_pointer" : "menu.start_pointer")) {
                appState.toggleMotionTracking()
            }

            Button(String(localized: "menu.switch_mode")) {
                appState.toggleRecognitionInputControlMode()
            }

            Button(String(localized: "menu.recenter_pointer")) {
                appState.finishCalibration()
            }

            Button(String(localized: "menu.shortcut_panel")) {
                appState.toggleShortcutPanel()
            }

            Divider()

            Button(String(localized: "menu.settings_ellipsis")) {
                GlobalLogger.lifecycle.info("Menu action: show main window")
                presentMainWindow()
            }

            Divider()

            Button(String(localized: "menu.quit")) {
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
