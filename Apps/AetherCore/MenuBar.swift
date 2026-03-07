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
            return isChinese ? "需要处理设置" : "Setup Needs Attention"
        }
        if appState.isMotionTracking && appState.voiceActivationMode == .handsFree {
            return isChinese ? "语音和指针已就绪" : "Voice and Pointer Ready"
        }
        if appState.isMotionTracking {
            return isChinese ? "指针控制已开启" : "Pointer Control Active"
        }
        return isChinese ? "Aether 已待命" : "Aether Ready"
    }

    private var statusSubtitle: String {
        if !appState.accessibilityTrusted {
            return isChinese ? "辅助功能未授权" : "Accessibility permission is missing"
        }
        if !appState.microphoneAuthorized {
            return isChinese ? "麦克风未授权" : "Microphone permission is missing"
        }
        if !appState.speechAuthorized {
            return isChinese ? "语音识别未授权" : "Speech Recognition permission is missing"
        }
        if appState.driverState == .needsUserApproval {
            return isChinese ? "驱动还需要系统批准" : "The driver still needs system approval"
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
                    Button(isChinese ? "批准驱动" : "Approve Driver") {
                        appState.openPrivacyAndSecurityPane()
                    }
                } else if !driverReady && appState.isMotionTracking {
                    Button(L10n.menuActivateDriver) {
                        appState.activateDriver()
                    }
                }

                if !appState.accessibilityTrusted {
                    Button(isChinese ? "开启辅助功能权限" : "Enable Accessibility") {
                        appState.requestAccessibilityGuided()
                    }
                }

                if !appState.microphoneAuthorized {
                    Button(isChinese ? "开启麦克风权限" : "Enable Microphone") {
                        appState.requestMicrophoneGuided()
                    }
                }

                if !appState.speechAuthorized {
                    Button(isChinese ? "开启语音识别权限" : "Enable Speech Recognition") {
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

                Button(isChinese ? "打开设置" : "Open Settings") {
                    GlobalLogger.lifecycle.info("Menu action: show main window")
                    openWindow(id: "main")
                    NSApp.activate(ignoringOtherApps: true)
                }

                Menu(isChinese ? "更多控制" : "More Controls") {
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
