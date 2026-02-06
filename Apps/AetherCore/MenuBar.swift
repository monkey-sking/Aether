import SwiftUI

struct AetherMenuBar: Scene {
    @EnvironmentObject private var appState: AppState

    var body: some Scene {
        MenuBarExtra("Aether", systemImage: "antenna.radiowaves.left.and.right") {
            VStack(alignment: .leading, spacing: 8) {
                Text("Pointer: \(appState.isMotionTracking ? "ON" : "OFF")")
                Text("Voice: \(appState.voiceStatus)")

                Divider()

                Button(appState.isMotionTracking ? "Stop Pointer (⌃⌥S)" : "Start Pointer (⌃⌥S)") {
                    appState.toggleMotionTracking()
                }

                Button("Recenter Pointer") {
                    appState.finishCalibration()
                }

                Divider()

                Toggle("Dwell Click", isOn: $appState.isDwellClickEnabled)
                Toggle("Always Listening", isOn: $appState.isAlwaysListeningEnabled)
                Toggle("LLM Enhance Dictation", isOn: $appState.isLLMEnhancementEnabled)

                Divider()

                Button("Show Window") {
                    appState.showMainWindow()
                }

                Button("Quit") {
                    NSApp.terminate(nil)
                }
            }
            .padding(10)
        }
    }
}

