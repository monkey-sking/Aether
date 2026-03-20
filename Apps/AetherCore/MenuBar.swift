import SwiftUI

struct AetherMenuBar: Scene {
    @EnvironmentObject private var appState: AppState
    @Environment(\.openWindow) private var openWindow
    @ObservedObject private var updaterManager = AetherUpdaterManager.shared

    private var isChinese: Bool {
        AppLocalization.isChinese
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
        if appState.voiceService.playbackLeakState == .suspectedPlaybackLeak {
            return String(localized: "menu.status.playback_leak_suspected")
        }
        if appState.voiceService.playbackLeakState == .speechSuppressionActive {
            return String(localized: "menu.status.playback_leak_suppression")
        }
        return appState.voiceStatus
    }

    private var statusAccentColor: Color {
        if needsAttention { return .orange }
        if appState.voiceService.playbackLeakState == .suspectedPlaybackLeak { return .orange }
        if appState.isMotionTracking { return .green }
        return .secondary
    }

    private var statusSymbolName: String {
        if needsAttention { return "exclamationmark.triangle.fill" }
        if appState.voiceService.playbackLeakState == .suspectedPlaybackLeak { return "speaker.slash.fill" }
        if appState.voiceService.playbackLeakState == .speechSuppressionActive { return "waveform.badge.magnifyingglass" }
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

            Toggle(isOn: $appState.isVoiceInputEnabled) {
                Label(String(localized: "menu.toggle_voice_input"), systemImage: "text.cursor")
            }

            Toggle(isOn: $appState.isVoiceControlEnabled) {
                Label(String(localized: "menu.toggle_voice_control"), systemImage: "command")
            }

            Divider()

            Button(String(localized: "menu.shortcut_panel")) {
                appState.toggleShortcutPanel()
            }

            Button(String(localized: "menu.check_updates_ellipsis")) {
                Task { await updaterManager.checkForUpdates() }
            }

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
            guard let window = NSApp.windows.first(where: { $0.identifier?.rawValue.contains("main") == true || $0.title == "Aether" }) else {
                return
            }
            window.makeKeyAndOrderFront(nil)
        }
    }
}
