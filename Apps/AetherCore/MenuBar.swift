import SwiftUI

struct AetherMenuBar: Scene {
    @EnvironmentObject private var appState: AppState

    var body: some Scene {
        MenuBarExtra(String(localized: "app.project_title"), systemImage: "antenna.radiowaves.left.and.right") {
            VStack(alignment: .leading, spacing: 8) {
                Text(L10n.menuPointer) + Text(": ") + Text(appState.isMotionTracking ? L10n.on : L10n.off)
                Text(L10n.menuVoice) + Text(": \(appState.voiceStatus)")

                Text(L10n.pointerOutput) + Text(": \(appState.pointerOutputPath)")
                Text(L10n.textOutput) + Text(": \(appState.textOutputPath)")
                Text(L10n.mode) + Text(": ") + Text(appState.forceDriverOnly ? L10n.modeDriverOnly : L10n.modeAuto)
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

                Button(appState.isMotionTracking ? L10n.menuStopPointer : L10n.menuStartPointer) {
                    appState.toggleMotionTracking()
                }

                Button(L10n.menuRecenterPointer) {
                    appState.finishCalibration()
                }

                Divider()

                Toggle(L10n.dwellClick, isOn: $appState.isDwellClickEnabled)
                Toggle(L10n.forceDriverOnly, isOn: $appState.forceDriverOnly)
                Toggle(
                    L10n.alwaysListening,
                    isOn: Binding(
                        get: { appState.isAlwaysListeningEnabled },
                        set: { appState.setAlwaysListeningEnabled($0) }
                    )
                )
                Toggle(L10n.llmEnhanceDictation, isOn: $appState.isLLMEnhancementEnabled)

                Divider()

                Button(L10n.menuShowWindow) {
                    appState.showMainWindow()
                }

                Button(L10n.menuQuit) {
                    NSApp.terminate(nil)
                }
            }
            .padding(10)
        }
    }
}
