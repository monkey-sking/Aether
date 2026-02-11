import SwiftUI

struct ContentView: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject var headManager = HeadMotionManager.shared
    @Environment(\.scenePhase) private var scenePhase
    
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "antenna.radiowaves.left.and.right")
                .font(.system(size: 60))
                .foregroundColor(.blue)
            
            Text(L10n.projectTitle)
                .font(.largeTitle)
                .fontWeight(.bold)
            
            Text(L10n.perceptionNetwork) + Text(": \(appState.driverStatus)")
                .font(.headline)
                .foregroundColor(.secondary)

            Text(L10n.pointerOutput) + Text(": \(appState.pointerOutputPath)  •  ") + Text(L10n.textOutput) + Text(": \(appState.textOutputPath)  •  ") + Text(L10n.mode) + Text(": ") + Text(appState.forceDriverOnly ? L10n.modeDriverOnly : L10n.modeAuto)
                .font(.caption)
                .foregroundColor(.secondary)
            
            Divider()
            
            VStack(alignment: .leading, spacing: 10) {
                Group {
                    if appState.onboardingStep != .done {
                        OnboardingCard()
                            .environmentObject(appState)
                    }

                    StatusRow(icon: "magicmouse", title: String(localized: "row.virtual_hid"), status: appState.driverStatus)
                    if appState.driverState == .needsUserApproval {
                        HStack(spacing: 10) {
                            Text(L10n.systemExtensionNeedsApproval)
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Spacer()
                            Button(L10n.openPrivacyAndSecurity) { appState.openPrivacyAndSecurityPane() }
                                .controlSize(.small)
                        }
                        .padding(8)
                        .background(Color.orange.opacity(0.10))
                        .cornerRadius(8)
                    }
                    if case .failed(let message) = appState.driverState, message.contains("Missing entitlement") {
                        HStack(spacing: 10) {
                            Text(String(localized: "system_extension.missing_entitlement_hint"))
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Spacer()
                        }
                        .padding(8)
                        .background(Color.orange.opacity(0.10))
                        .cornerRadius(8)
                    }
                    StatusRow(icon: "airpods", title: String(localized: "row.airpods_matrix"), status: appState.isMotionTracking ? String(localized: "generic.tracking") : String(localized: "generic.ready"))
                    StatusRow(icon: "mic", title: String(localized: "row.voice"), status: appState.voiceStatus)
                    if !appState.lastVoiceError.isEmpty {
                        Text(appState.lastVoiceError)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .lineLimit(3)
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text(L10n.permissionsTitle)
                        .font(.caption)
                        .foregroundColor(.secondary)

                    HStack(spacing: 8) {
                        PermissionPill(title: String(localized: "permissions.accessibility"), ok: appState.accessibilityTrusted)
                        PermissionPill(title: String(localized: "permissions.microphone"), ok: appState.microphoneAuthorized)
                        PermissionPill(title: String(localized: "permissions.speech"), ok: appState.speechAuthorized)
                    }

                    if !appState.accessibilityTrusted {
                        HStack(spacing: 10) {
                            Button(L10n.fixAccessibility) { appState.requestAccessibility() }
                            Button(L10n.openPane) { appState.openAccessibilityPane() }
                            Button(L10n.recheck) { appState.refreshPermissions() }
                        }
                        .controlSize(.small)
                    }

                    if !appState.microphoneAuthorized {
                        HStack(spacing: 10) {
                            Button(L10n.fixMicrophone) { appState.requestMicrophone() }
                            Button(L10n.openPane) { appState.openMicrophonePane() }
                            Button(L10n.recheck) { appState.refreshPermissions() }
                        }
                        .controlSize(.small)
                    }

                    if !appState.speechAuthorized {
                        HStack(spacing: 10) {
                            Button(L10n.fixSpeech) { appState.requestSpeech() }
                            Button(L10n.openPane) { appState.openSpeechPane() }
                            Button(L10n.recheck) { appState.refreshPermissions() }
                        }
                        .controlSize(.small)
                    }
                }
                .padding(8)
                .background(Color.black.opacity(0.06))
                .cornerRadius(8)
                
                Group {
                    if appState.isMotionTracking {
                        Text(appState.attitudeData)
                            .font(.system(.caption, design: .monospaced))
                            .padding(8)
                            .background(Color.black.opacity(0.1))
                            .cornerRadius(5)
                    }

                    if !appState.lastVoiceTranscript.isEmpty {
                        Text(appState.lastVoiceTranscript)
                            .font(.system(.caption, design: .monospaced))
                            .padding(8)
                            .background(Color.black.opacity(0.1))
                            .cornerRadius(5)
                    }
                    
                    StatusRow(icon: "laptopcomputer", title: String(localized: "row.lid_sensor"), status: String(localized: "generic.ready"))
                    
                    Toggle(L10n.dwellClick, isOn: $appState.isDwellClickEnabled)
                        .padding(.top, 5)

                    Toggle(
                        L10n.alwaysListening,
                        isOn: Binding(
                            get: { appState.isAlwaysListeningEnabled },
                            set: { appState.setAlwaysListeningEnabled($0) }
                        )
                    )

                    Toggle(L10n.llmEnhanceDictation, isOn: $appState.isLLMEnhancementEnabled)

                    Text(L10n.pushToTalkHint)
                        .font(.caption2)
                        .foregroundColor(.secondary)

                    HotkeySettingsSection()
                }
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(10)
            
            Spacer()
            
            VStack(spacing: 12) {
                Button(action: {
                    appState.activateDriver()
                }) {
                    Text(L10n.activatePerception)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                
                Button(action: {
                    appState.toggleMotionTracking()
                }) {
                    Text(appState.isMotionTracking ? L10n.stopMotionMatrix : L10n.startMotionMatrix)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                
                if appState.isMotionTracking && appState.calibrationStatus != "Normal" {
                    Button(action: {
                        appState.finishCalibration()
                    }) {
                        Text(L10n.finishRangeCalibration)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                    .controlSize(.large)
                    
                    Text(appState.calibrationStatus)
                        .font(.caption)
                        .foregroundColor(.orange)
                }
                
                Toggle("Tilt Scroll", isOn: $headManager.isTiltScrollEnabled)
                    .toggleStyle(.switch)
                    .controlSize(.large)
                    .tint(.blue)
                    .padding(.horizontal)

                Toggle("Debug Mode", isOn: $headManager.isDebugModeEnabled)
                    .toggleStyle(.switch)
                    .controlSize(.large)
                    .tint(.red)
                    .padding(.horizontal)

                VStack(spacing: 4) {
                    Text("切换追踪: \(HotkeyManager.shared.binding(for: .toggleTracking).displayString)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .padding(.top, 5)
            }
        }
        .padding()
        .overlay(alignment: .top) {
            VoiceHUD()
        }
        .onAppear {
            // Trigger deferred permission check
            appState.refreshPermissions()
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                appState.refreshPermissions()
            }
        }
    }
}

private struct OnboardingCard: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L10n.setupRequired)
                .font(.headline)

            Text(description)
                .font(.subheadline)
                .foregroundColor(.secondary)

            HStack(spacing: 10) {
                Button(primaryTitle) { primaryAction() }
                Button(L10n.openPane) { openPaneAction() }
                Button(L10n.recheck) { appState.refreshPermissions() }
            }
            .controlSize(.small)
        }
        .padding(10)
        .background(Color.orange.opacity(0.12))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.orange.opacity(0.35), lineWidth: 1)
        )
        .cornerRadius(10)
    }

    private var description: String {
        switch appState.onboardingStep {
        case .accessibility:
            return String(localized: "onboarding.accessibility")
        case .microphone:
            return String(localized: "onboarding.microphone")
        case .speech:
            return String(localized: "onboarding.speech")
        case .done:
            return ""
        }
    }

    private var primaryTitle: String {
        switch appState.onboardingStep {
        case .accessibility: return String(localized: "permissions.fix_accessibility")
        case .microphone: return String(localized: "permissions.fix_microphone")
        case .speech: return String(localized: "permissions.fix_speech")
        case .done: return ""
        }
    }

    private func primaryAction() {
        switch appState.onboardingStep {
        case .accessibility: appState.requestAccessibility()
        case .microphone: appState.requestMicrophone()
        case .speech: appState.requestSpeech()
        case .done: break
        }
    }

    private func openPaneAction() {
        switch appState.onboardingStep {
        case .accessibility: appState.openAccessibilityPane()
        case .microphone: appState.openMicrophonePane()
        case .speech: appState.openSpeechPane()
        case .done: break
        }
    }
}

struct PermissionPill: View {
    let title: String
    let ok: Bool

    var body: some View {
        Text("\(ok ? "✓" : "•") \(title)")
            .font(.caption2)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(ok ? Color.green.opacity(0.2) : Color.orange.opacity(0.2))
            .cornerRadius(999)
    }
}

struct StatusRow: View {
    let icon: String
    let title: String
    let status: String
    
    var body: some View {
        HStack {
            Image(systemName: icon)
            .frame(width: 24)
            Text(title)
            Spacer()
            Text(status)
            .foregroundColor(.secondary)
        }
    }
}

struct VoiceHUD: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject var headManager = HeadMotionManager.shared
    
    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { context in
            if isAwake {
                HStack(spacing: 8) {
                    Image(systemName: "mic.fill")
                        .foregroundColor(.green)
                        .imageScale(.medium)
                        // Simple pulse animation could go here
                    
                    Text(displayCookie)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.white)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Material.regularMaterial)
                .cornerRadius(20)
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(Color.white.opacity(0.2), lineWidth: 1)
                )
                .padding(.top, 60)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.spring(), value: isAwake)
    }
    
    private var isAwake: Bool {
        // Gaze Wake
        if headManager.isTracking && headManager.isLookingAtScreen {
            return true
        }
        // Timeout Wake
        if let last = appState.lastVoiceWakeTime {
            return Date().timeIntervalSince(last) < 8.0
        }
        return false
    }
    
    private var displayCookie: String {
        if headManager.isLookingAtScreen && headManager.isTracking {
            return "Listening (Gaze)"
        }
        return "Listening..."
    }
}
