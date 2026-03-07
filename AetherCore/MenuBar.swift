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

    private var activationModeTitle: String {
        switch appState.voiceActivationMode {
        case .pushToTalk:
            return isChinese ? "按住说话" : "Push To Talk"
        case .wakeWord:
            return isChinese ? "唤醒词" : "Wake Word"
        case .handsFree:
            return isChinese ? "免提醒常驻" : "Hands-Free"
        }
    }

    private var speechLanguageTitle: String {
        let raw = UserDefaults.standard.string(forKey: "speechLocaleIdentifier") ?? Locale.current.identifier
        if raw == "system" {
            return isChinese ? "系统语言" : "System"
        }
        return Locale.current.localizedString(forIdentifier: raw) ?? raw
    }

    private var shortcutPanelVisible: Bool {
        CurrentAppShortcutPanelManager.shared.isVisible
    }

    private var hasNowPlayingSource: Bool {
        !appState.nowPlayingAppName.isEmpty || !appState.nowPlayingTitle.isEmpty
    }

    private var nowPlayingSummary: String {
        let appName = appState.nowPlayingAppName.isEmpty
            ? (isChinese ? "未检测到" : "Not Detected")
            : appState.nowPlayingAppName
        let title = appState.nowPlayingTitle.isEmpty
            ? (isChinese ? "没有读取到标题" : "No title")
            : appState.nowPlayingTitle
        return "\(appName) · \(title)"
    }

    var body: some Scene {
        MenuBarExtra {
            VStack(alignment: .leading, spacing: 12) {
                MenuBarStatusHeader(
                    title: String(localized: "app.project_title"),
                    subtitle: statusTitle,
                    detail: "\(activationModeTitle) · \(speechLanguageTitle)",
                    tint: needsAttention ? .orange : .green
                )

                Text(statusSubtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Divider()

                VStack(alignment: .leading, spacing: 6) {
                    Button(appState.isMotionTracking
                        ? L10n.menuStopPointer(HotkeyManager.shared.binding(for: .toggleTracking).displayString)
                        : L10n.menuStartPointer(HotkeyManager.shared.binding(for: .toggleTracking).displayString)) {
                        appState.toggleMotionTracking()
                    }

                    Button(isChinese ? "切换输入 / 控制模式" : "Toggle Input / Control Mode") {
                        appState.toggleRecognitionInputControlMode()
                    }

                    Button(
                        shortcutPanelVisible
                            ? (isChinese ? "隐藏快捷键面板" : "Hide Shortcut Panel")
                            : String(
                                format: NSLocalizedString("menu.shortcut_panel_fmt", comment: ""),
                                HotkeyManager.shared.binding(for: .toggleShortcutPanel).displayString
                            )
                    ) {
                        appState.toggleShortcutPanel()
                    }

                    Button(isChinese ? "打开主窗口" : "Open Main Window") {
                        GlobalLogger.lifecycle.info("Menu action: show main window")
                        openWindow(id: "main")
                        NSApp.activate(ignoringOtherApps: true)
                    }
                }

                if hasNowPlayingSource {
                    Divider()

                    VStack(alignment: .leading, spacing: 8) {
                        Text(isChinese ? "当前播放" : "Now Playing")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.secondary)
                        Text(nowPlayingSummary)
                            .font(.caption)
                            .fixedSize(horizontal: false, vertical: true)

                        HStack(spacing: 8) {
                            Button {
                                appState.skipNowPlayingBackward()
                            } label: {
                                Image(systemName: "backward.fill")
                            }
                            .help(isChinese ? "上一首" : "Previous")

                            Button {
                                appState.toggleNowPlayingPlayback()
                            } label: {
                                Image(systemName: appState.nowPlayingStatus == "Playing" ? "pause.fill" : "play.fill")
                            }
                            .help(appState.nowPlayingStatus == "Playing"
                                  ? (isChinese ? "暂停" : "Pause")
                                  : (isChinese ? "播放" : "Play"))

                            Button {
                                appState.skipNowPlayingForward()
                            } label: {
                                Image(systemName: "forward.fill")
                            }
                            .help(isChinese ? "下一首" : "Next")

                            Spacer(minLength: 0)

                            Button(isChinese ? "刷新" : "Refresh") {
                                appState.refreshNowPlaying()
                            }
                        }
                        .buttonStyle(.bordered)
                    }
                }

                if needsAttention || (appState.driverState == .needsUserApproval || (!driverReady && appState.isMotionTracking)) {
                    Divider()

                    VStack(alignment: .leading, spacing: 6) {
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
                    }
                }

                Divider()

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

                    Divider()

                    Button(L10n.menuRecenterPointer) {
                        appState.finishCalibration()
                    }
                }

                Divider()

                Button(L10n.menuQuit) {
                    NSApp.terminate(nil)
                }
            }
            .padding(12)
            .frame(minWidth: 300)
        } label: {
            Image("MenuBarIcon")
                .renderingMode(.template)
        }
    }
}

private struct MenuBarStatusHeader: View {
    let title: String
    let subtitle: String
    let detail: String
    let tint: Color

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(tint)
                .frame(width: 10, height: 10)
                .padding(.top, 3)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline.weight(.semibold))
                Text(subtitle)
                    .font(.subheadline.weight(.medium))
                Text(detail)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
