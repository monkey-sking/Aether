import SwiftUI

struct AetherMenuBar: Scene {
    @EnvironmentObject private var appState: AppState
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        MenuBarExtra(String(localized: "app.project_title"), systemImage: "antenna.radiowaves.left.and.right") {
            VStack(alignment: .leading, spacing: 8) {
                Text(L10n.menuPointer) + Text(": ") + Text(appState.isMotionTracking ? L10n.on : L10n.off)
                Text(L10n.menuVoice) + Text(": \(appState.voiceStatus)")
                if appState.driverState == .needsUserApproval {
                    Text(L10n.menuDriver) + Text(": ") + Text(L10n.systemExtensionNeedsApproval)
                    Button(L10n.openPrivacyAndSecurity) {
                        appState.openPrivacyAndSecurityPane()
                    }
                }

                Divider()

                Text(L10n.menuDriver) + Text(": \(appState.driverStatus)")
                Button(L10n.menuActivateDriver) {
                    appState.activateDriver()
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

                Divider()

                Toggle(L10n.dwellClick, isOn: $appState.isDwellClickEnabled)
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

                Button(L10n.menuShowWindow) {
                    GlobalLogger.lifecycle.info("Menu action: show main window")
                    openWindow(id: "main")
                    NSApp.activate(ignoringOtherApps: true)
                }

                Divider()

                Button("v\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0") (\(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"))") {
                    // No action, just display
                }
                .disabled(true)

                Button(L10n.menuQuit) {
                    NSApp.terminate(nil)
                }
            }
            .padding(10)
        }
    }
}
