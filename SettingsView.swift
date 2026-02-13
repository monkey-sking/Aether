import SwiftUI
import AVFoundation
import Speech

struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    
    var body: some View {
        TabView {
            OverviewSettingsView()
                .tabItem {
                    Label(String(localized: "settings.tab.overview", defaultValue: "Overview"), systemImage: "house")
                }
            
            GeneralSettingsView()
                .tabItem {
                    Label(String(localized: "settings.tab.general"), systemImage: "gear")
                }
            
            InputSettingsView()
                .tabItem {
                    Label(String(localized: "settings.tab.input"), systemImage: "keyboard")
                }
            
            FeedbackSettingsView()
                .tabItem {
                    Label(String(localized: "settings.tab.feedback"), systemImage: "macwindow")
                }
            
            AdvancedSettingsView()
                .tabItem {
                    Label(String(localized: "settings.tab.advanced"), systemImage: "wrench.and.screwdriver")
                }
        }
        .frame(width: 500, height: 400)
        .padding()
    }
}

// MARK: - Subviews

struct GeneralSettingsView: View {
    @EnvironmentObject var appState: AppState
    
    var body: some View {
        Form {
            Section {
                Toggle(L10n.showDockIcon, isOn: $appState.showDockIcon)
                
                Button(L10n.setupRequired) {
                    appState.refreshPermissions()
                    // Logic to open permissions pane if needed
                }
                .disabled(appState.onboardingStep == .done)
            }
        }
        .formStyle(.grouped)
    }
}

struct InputSettingsView: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject var headManager = HeadMotionManager.shared
    
    var body: some View {
        Form {
            Section(header: Text(L10n.voiceAndListening)) {
                Toggle(L10n.alwaysListening, isOn: $appState.isAlwaysListeningEnabled)
                
                if appState.isAlwaysListeningEnabled {
                    VStack(alignment: .leading) {
                        Text(L10n.alwaysListeningWakeWindow)
                        Slider(value: $appState.alwaysListeningWakeWindowSeconds, in: 3...30, step: 1) {
                            Text("Seconds")
                        } minimumValueLabel: {
                            Text("3s")
                        } maximumValueLabel: {
                            Text("30s")
                        }
                        Text("\(Int(appState.alwaysListeningWakeWindowSeconds))s")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            Section(header: Text(String(localized: "settings.header.shortcuts", defaultValue: "Shortcuts"))) {
                HotkeySettingsSection()
            }
            
            Section(header: Text(String(localized: "settings.header.motion", defaultValue: "Motion Control"))) {
                 Toggle(L10n.dwellClick, isOn: $appState.isDwellClickEnabled)
                 Toggle(L10n.tiltScroll, isOn: $headManager.isTiltScrollEnabled)
            }
        }
        .formStyle(.grouped)
    }
}

struct FeedbackSettingsView: View {
    @EnvironmentObject var appState: AppState
    
    var body: some View {
        Form {
            Section(header: Text(L10n.hudSettings)) {
                VStack(alignment: .leading) {
                    Text(L10n.hudAutoHide)
                    Slider(value: $appState.hudAutoHideSeconds, in: 0.5...5.0, step: 0.5) {
                        Text("Seconds")
                    } minimumValueLabel: {
                        Text("0.5s")
                    } maximumValueLabel: {
                        Text("5.0s")
                    }
                    Text(String(format: "%.1fs", appState.hudAutoHideSeconds))
                }
                Text(L10n.hudAutoHideHint)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

struct AdvancedSettingsView: View {
    @EnvironmentObject var appState: AppState
    
    var body: some View {
        Form {
            Section(header: Text(L10n.advancedSettings)) { // Reused advancedSettings key, check if appropriate
                Toggle(L10n.llmEnhanceDictation, isOn: $appState.isLLMEnhancementEnabled)
            }
            
            Section(header: Text(L10n.menuDriver)) {
                Toggle(L10n.forceDriverOnly, isOn: $appState.forceDriverOnly)
                
                // Binding need to be careful here if properties are not directly on AppState
                Toggle(L10n.preferInputMethodCaret, isOn: $appState.preferInputMethodCaret)
                Toggle(L10n.caretEngineCompare, isOn: $appState.caretEngineCompareEnabled)
            }
            
             Section(header: Text(L10n.debugMode)) {
                // Accessing HeadMotionManager via AppState would be cleaner, but for now we might need a workaround or update AppState
                // Assuming AppState has access or we adding it.
                // For now, let's leave out direct HeadMotionManager access if not exposed in AppState, 
                // BUT ContentView accessed `headManager` separately.
                // We should expose it in AppState or Environment.
            }
        }
        .formStyle(.grouped)
    }
}
