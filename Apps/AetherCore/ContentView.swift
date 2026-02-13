import SwiftUI

struct ContentView: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject var headManager = HeadMotionManager.shared
    @Environment(\.scenePhase) private var scenePhase
    
    var body: some View {
        VStack(spacing: 14) {
            headerView
            ScrollView {
                VStack(spacing: 12) {
                    quickStartCard
                    if appState.onboardingStep != .done {
                        OnboardingCard().environmentObject(appState)
                    }
                    runtimeCard
                    permissionsCard
                    voiceCard
                    hudCard
                    advancedCard
                    warningCard
                }
                .padding(2)
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

    private var headerView: some View {
        VStack(spacing: 8) {
            Image(systemName: "antenna.radiowaves.left.and.right")
                .font(.system(size: 48))
                .foregroundColor(.blue)
            Text(L10n.projectTitle)
                .font(.title)
                .fontWeight(.bold)
            Text(L10n.perceptionNetwork) + Text(": \(appState.driverStatus)")
                .font(.subheadline)
                .foregroundColor(.secondary)
            Text(L10n.pointerOutput) + Text(": \(appState.pointerOutputPath)  •  ") + Text(L10n.textOutput) + Text(": \(appState.textOutputPath)  •  ") + Text(L10n.mode) + Text(": ") + Text(appState.forceDriverOnly ? L10n.modeDriverOnly : L10n.modeAuto)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    private var quickStartCard: some View {
        GroupBox {
            VStack(spacing: 10) {
                Button(action: { appState.activateDriver() }) {
                    Text(L10n.activatePerception).frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)

                Button(action: { appState.toggleMotionTracking() }) {
                    Text(appState.isMotionTracking ? L10n.stopMotionMatrix : L10n.startMotionMatrix)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                if appState.isMotionTracking && appState.calibrationStatus != "Normal" {
                    Button(action: { appState.finishCalibration() }) {
                        Text(L10n.finishRangeCalibration).frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                    Text(appState.calibrationStatus)
                        .font(.caption)
                        .foregroundColor(.orange)
                }
            }
        } label: {
            Label(L10n.quickStart, systemImage: "bolt.circle")
        }
    }

    private var runtimeCard: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                StatusRow(icon: "magicmouse", title: String(localized: "row.virtual_hid"), status: appState.driverStatus)
                StatusRow(icon: "airpods", title: String(localized: "row.airpods_matrix"), status: appState.isMotionTracking ? String(localized: "generic.tracking") : String(localized: "generic.ready"))
                StatusRow(icon: "mic", title: String(localized: "row.voice"), status: appState.voiceStatus)
                if appState.isMotionTracking {
                    Text(appState.attitudeData)
                        .font(.system(.caption, design: .monospaced))
                        .padding(6)
                        .background(Color.black.opacity(0.08))
                        .cornerRadius(6)
                }
                if !appState.lastVoiceError.isEmpty {
                    Text(appState.lastVoiceError)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(3)
                }
            }
        } label: {
            Label(L10n.runtimeStatus, systemImage: "waveform.path.ecg")
        }
    }

    private var permissionsCard: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    PermissionPill(title: String(localized: "permissions.accessibility"), ok: appState.accessibilityTrusted)
                    PermissionPill(title: String(localized: "permissions.microphone"), ok: appState.microphoneAuthorized)
                    PermissionPill(title: String(localized: "permissions.speech"), ok: appState.speechAuthorized)
                }
                if !appState.accessibilityTrusted {
                    permissionActionRow(fix: L10n.fixAccessibility, open: { appState.openAccessibilityPane() }, request: { appState.requestAccessibility() })
                }
                if !appState.microphoneAuthorized {
                    permissionActionRow(fix: L10n.fixMicrophone, open: { appState.openMicrophonePane() }, request: { appState.requestMicrophone() })
                }
                if !appState.speechAuthorized {
                    permissionActionRow(fix: L10n.fixSpeech, open: { appState.openSpeechPane() }, request: { appState.requestSpeech() })
                }
            }
        } label: {
            Label(L10n.permissionsTitle, systemImage: "lock.shield")
        }
    }

    private func permissionActionRow(fix: LocalizedStringKey, open: @escaping () -> Void, request: @escaping () -> Void) -> some View {
        HStack(spacing: 10) {
            Button(fix) { request() }
            Button(L10n.openPane) { open() }
            Button(L10n.recheck) { appState.refreshPermissions() }
        }
        .controlSize(.small)
    }

    private var voiceCard: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(String(localized: "voice.state_now"))
                    Spacer()
                    Text(currentVoiceStateText)
                        .foregroundColor(.secondary)
                }
                HStack {
                    Text(String(localized: "voice.wakeword_required_now"))
                    Spacer()
                    Text(wakeWordRequiredNow ? String(localized: "voice.yes") : String(localized: "voice.no"))
                        .foregroundColor(wakeWordRequiredNow ? .orange : .green)
                }
                Toggle(L10n.dwellClick, isOn: $appState.isDwellClickEnabled)
                Toggle(
                    L10n.alwaysListening,
                    isOn: Binding(
                        get: { appState.isAlwaysListeningEnabled },
                        set: { appState.setAlwaysListeningEnabled($0) }
                    )
                )
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(L10n.alwaysListeningWakeWindow)
                        Spacer()
                        Text(String(format: "%.0fs", appState.alwaysListeningWakeWindowSeconds))
                            .foregroundColor(.secondary)
                    }
                    Slider(value: $appState.alwaysListeningWakeWindowSeconds, in: 3...20, step: 1)
                    Text(L10n.alwaysListeningWakeWindowHint)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                Text(L10n.pushToTalkHint)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        } label: {
            Label(L10n.voiceAndListening, systemImage: "mic")
        }
    }

    private var currentVoiceStateText: String {
        if !appState.isAlwaysListeningEnabled {
            return String(localized: "speech.idle")
        }
        return wakeWordRequiredNow ? String(localized: "speech.waiting_wakeword") : String(localized: "speech.waiting_command")
    }

    private var wakeWordRequiredNow: Bool {
        guard appState.isAlwaysListeningEnabled else { return false }
        if headManager.isTracking && headManager.isLookingAtScreen {
            return false
        }
        if let last = appState.lastVoiceWakeTime {
            return Date().timeIntervalSince(last) >= appState.alwaysListeningWakeWindowSeconds
        }
        return true
    }

    private var hudCard: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(L10n.hudAutoHide)
                    Spacer()
                    Text(String(format: "%.1fs", appState.hudAutoHideSeconds))
                        .foregroundColor(.secondary)
                }
                Slider(value: $appState.hudAutoHideSeconds, in: 0.5...5.0, step: 0.5)
                Text(L10n.hudAutoHideHint)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        } label: {
            Label(L10n.hudSettings, systemImage: "rectangle.inset.filled.and.person.filled")
        }
    }

    private var advancedCard: some View {
        DisclosureGroup(L10n.advancedSettings) {
            VStack(alignment: .leading, spacing: 8) {
                Toggle(L10n.llmEnhanceDictation, isOn: $appState.isLLMEnhancementEnabled)
                Toggle(L10n.preferInputMethodCaret, isOn: $appState.preferInputMethodCaret)
                Toggle(L10n.caretEngineCompare, isOn: $appState.caretEngineCompareEnabled)
                Toggle(L10n.showDockIcon, isOn: $appState.showDockIcon)
                Toggle(L10n.tiltScroll, isOn: $headManager.isTiltScrollEnabled)
                Toggle(L10n.debugMode, isOn: $headManager.isDebugModeEnabled)
                HotkeySettingsSection()
                Text(L10n.controlToggleTracking(HotkeyManager.shared.binding(for: .toggleTracking).displayString))
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .padding(.top, 6)
        }
        .padding(10)
        .background(Color.black.opacity(0.05))
        .cornerRadius(8)
    }

    @ViewBuilder
    private var warningCard: some View {
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
            if shouldShow {
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
        .animation(.spring(), value: shouldShow)
    }
    
    private var isAwake: Bool {
        // Gaze Wake
        if headManager.isTracking && headManager.isLookingAtScreen {
            return true
        }
        // Timeout Wake
        if let last = appState.lastVoiceWakeTime {
            return Date().timeIntervalSince(last) < appState.alwaysListeningWakeWindowSeconds
        }
        return false
    }

    private var shouldShow: Bool {
        appState.isAlwaysListeningEnabled || isAwake
    }
    
    private var displayCookie: String {
        if appState.isAlwaysListeningEnabled {
            return isAwake ? String(localized: "speech.waiting_command") : String(localized: "speech.waiting_wakeword")
        }
        if headManager.isLookingAtScreen && headManager.isTracking {
            return "Listening (Gaze)"
        }
        return "Listening..."
    }
}
