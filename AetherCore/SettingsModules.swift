import SwiftUI

// MARK: - Input Settings (Voice)
struct InputSettingsView: View {
    @EnvironmentObject var appState: AppState
    
    var body: some View {
        ScrollView(.vertical) {
            VStack(spacing: 20) {
                // Microphone Section
                GlassCard {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Label(L10n.settingsMicrophone, systemImage: "mic.fill")
                                .font(.headline)
                            Spacer()
                            Button(action: { appState.voiceService.refreshInputDevices() }) {
                                Image(systemName: "arrow.triangle.2.circlepath")
                            }
                            .buttonStyle(.borderless)
                        }
                        
                        if appState.availableInputDevices.isEmpty {
                            Text(L10n.settingsNoMicrophone)
                                .foregroundColor(.secondary)
                        } else {
                            Picker("", selection: $appState.selectedInputDeviceID) {
                                ForEach(appState.availableInputDevices) { device in
                                    Text(device.name).tag(device.id)
                                }
                            }
                            .labelsHidden()
                        }
                    }
                }
                        
                // Activation Section
                GlassCard {
                    VStack(alignment: .leading, spacing: 16) {
                        Label(L10n.activationMethods, systemImage: "bolt.fill")
                            .font(.headline)
                        
                        // 1. Shortcut (PTT)
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Toggle(isOn: $appState.isPTTEnabled) {
                                    Text(L10n.activationShortcut)
                                        .font(.headline)
                                }
                                Spacer()
                                // Key Recorder here
                                // Key Recorder here
                                KeyRecorderView(
                                    binding: $appState.voicePTTBinding,
                                    onChange: { newBind in
                                        appState.updatePTTBinding(newBind)
                                    },
                                    font: .title3
                                )
                                
                                Button(action: {
                                    appState.updatePTTBinding(HotkeyAction.pushToTalk.defaultBinding)
                                }) {
                                    Image(systemName: "arrow.counterclockwise")
                                        .foregroundColor(.secondary)
                                }
                                .buttonStyle(.plain)
                                .help(L10n.hotkeyResetSingle)
                            }
                            Text(L10n.activationShortcutHint)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        
                        Divider()
                        
                        // 2. Wake Word
                        VStack(alignment: .leading, spacing: 8) {
                            Toggle(isOn: $appState.isWakeWordEnabled) {
                                Text(L10n.settingsActivationWakeWord)
                                    .font(.headline)
                            }
                            Text(L10n.activationWakeWordHint)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        Divider()

                        // 3. Always Listening
                        VStack(alignment: .leading, spacing: 8) {
                            Toggle(isOn: $appState.isAlwaysListeningEnabled) {
                                Text(L10n.settingsActivationHandsFree) // Reused "Hands-Free" text for "Always Listening"?
                                // Or use L10n.alwaysListening? 
                                // Let's use specific L10n.alwaysListening if available, or just "Always Listening"
                                Text(L10n.alwaysListening)
                                    .font(.headline)
                            }
                            Text(L10n.activationAlwaysHint)
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            if appState.isAlwaysListeningEnabled {
                                Text(L10n.activationAlwaysWarning)
                                    .font(.caption)
                                    .foregroundColor(.orange)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
                
                // Dictation Mode Settings
                GlassCard {
                        VStack(alignment: .leading, spacing: 12) {
                            Label(L10n.settingsDictationMode, systemImage: "text.quote")
                                .font(.headline)
                            
                            ControlCard(
                                title: L10n.llmEnhanceDictation,
                                subtitle: L10n.settingsSmarterDictation,
                                icon: "sparkles",
                                color: .purple,
                                isOn: $appState.isLLMEnhancementEnabled
                            )
                            
                            Toggle(isOn: $appState.isAutoPunctuationEnabled) {
                                Text(L10n.settingsAutoPunctuation)
                            }
                        }
                    }
                }
            }
            .padding()
        }
    }

// MARK: - Output Settings (Motion)
struct OutputSettingsView: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject var headManager = HeadMotionManager.shared
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Tracking Toggle
                GlassCard {
                    ControlCard(
                        title: L10n.commandCenterMotionMatrix, // Reusing Motion Matrix title which is appropriate
                        subtitle: headManager.isTracking ? L10n.statusActive : L10n.statusPaused,
                        icon: "viewfinder",
                        color: .green,
                        isOn: $headManager.isTracking
                    )
                }
                
                // Gestures
                GlassCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Label(L10n.settingsGesturesClicks, systemImage: "hand.point.up.left.fill")
                            .font(.headline)
                        
                        ControlCard(
                            title: L10n.dwellClick,
                            subtitle: L10n.settingsDwellClickSubtitle,
                            icon: "timer",
                            color: .orange,
                            isOn: $appState.isDwellClickEnabled
                        )
                        
                        ControlCard(
                            title: L10n.tiltScroll,
                            subtitle: L10n.settingsTiltScrollSubtitle,
                            icon: "arrow.up.arrow.down",
                            color: .indigo,
                            isOn: $headManager.isTiltScrollEnabled
                        )
                    }
                }
                
                // Calibration
                GlassCard {
                    VStack(alignment: .leading, spacing: 12) {
                         Label(L10n.settingsCalibration, systemImage: "scope")
                            .font(.headline)
                        
                        HStack {
                            Text(L10n.settingsCurrentStatus)
                            Spacer()
                            // Text accepts LocalizedStringKey, but ternary with string literal might be tricky if one branch is String and other is LocalizedStringKey.
                            // headManager.calibrationStatus is String.
                            // We need to wrap it in Text() to handle localization vs string.
                            // But here we are inside Text(). Text(LocalizedStringKey) vs Text(String). 
                            // Text(condition ? L10n.x : String(y)) -> Type mismatch.
                            // We should cast both to LocalizedStringKey? String can be converted to LocalizedStringKey but it won't be localized if it's dynamic.
                            // Optimally:
                            if headManager.calibrationStatus == "Normal" {
                                Text(L10n.calibrationNormal)
                                    .foregroundColor(.green)
                            } else {
                                Text(headManager.calibrationStatus)
                                    .foregroundColor(.orange)
                            }
                        }
                        
                        Button(action: { headManager.recenter() }) {
                            Text(L10n.actionRecenterMatrix)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                        }
                        .controlSize(.large)
                    }
                }
            }
            .padding()
        }
    }
}

// MARK: - System Settings
struct SystemSettingsView: View {
    @EnvironmentObject var appState: AppState
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Driver Status
                GlassCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Label(L10n.settingsDriverStatus, systemImage: "cpu")
                            .font(.headline)
                        
                        HStack {
                            Text(appState.driverStatus)
                                .font(.monospaced(.body)())
                            Spacer()
                            Circle()
                                .fill(appState.driverStatus.contains("Connected") || appState.driverStatus.contains("Ready") ? Color.green : Color.orange)
                                .frame(width: 10, height: 10)
                        }
                        
                        if !(appState.driverStatus.contains("Connected") || appState.driverStatus.contains("Ready")) {
                            Button(action: {
                                appState.activateDriver()
                            }) {
                                Text(L10n.menuActivateDriver)
                            }
                        }
                    }
                }
                
                // Permissions
                GlassCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Label(L10n.permissionsTitle, systemImage: "lock.shield")
                            .font(.headline)
                        
                       PermissionRow(icon: "hand.raised.fill", title: L10n.permissionAccessibility, isGranted: appState.accessibilityTrusted) {
                           appState.requestAccessibility()
                       }
                       PermissionRow(icon: "mic.fill", title: L10n.permissionMicrophone, isGranted: appState.microphoneAuthorized) {
                           appState.requestMicrophone()
                       }
                       PermissionRow(icon: "waveform", title: L10n.permissionSpeech, isGranted: appState.speechAuthorized) {
                           appState.requestSpeech()
                       }
                    }
                }
                
                // General
                GlassCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Label(L10n.settingsTabGeneral, systemImage: "gear")
                            .font(.headline)
                        
                        Toggle(L10n.showDockIcon, isOn: $appState.showDockIcon)
                    }
                }
            }
            .padding()
        }
    }
}

// MARK: - Shortcuts Placeholder
struct ShortcutsSettingsView: View {
    var body: some View {
         ScrollView {
             VStack(spacing: 20) {
                 GlassCard {
                     HotkeySettingsSection()
                 }
             }
             .padding()
         }
    }
}
