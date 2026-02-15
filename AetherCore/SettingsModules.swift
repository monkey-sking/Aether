import SwiftUI
import AppKit

// MARK: - Input Settings (Voice)
struct InputSettingsView: View {
    @EnvironmentObject var appState: AppState
    @State private var editingGroupID: String?
    
    var body: some View {
        ScrollView(.vertical) {
            VStack(spacing: 20) {
                // Microphone Section
                GlassCard {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Label(L10n.settingsMicrophone, systemImage: "mic.fill")
                                .font(.body)
                            Spacer()
                            
                            if appState.availableInputDevices.isEmpty {
                                Text(L10n.settingsNoMicrophone)
                                    .foregroundColor(.secondary)
                            } else {
                                Menu {
                                    ForEach(appState.availableInputDevices) { device in
                                        Button(device.name) {
                                            appState.selectedInputDeviceID = device.id
                                        }
                                    }
                                } label: {
                                    HStack {
                                        if let device = appState.availableInputDevices.first(where: { $0.id == appState.selectedInputDeviceID }) {
                                            Text(LocalizedStringKey(device.name))
                                                .truncationMode(.tail)
                                                .lineLimit(1)
                                        } else {
                                            Text(L10n.settingsNoMicrophone)
                                                .truncationMode(.tail)
                                                .lineLimit(1)
                                        }
                                        Spacer()
                                        Image(systemName: "chevron.up.chevron.down")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .frame(width: 200, alignment: .leading)
                                    .background(Color(nsColor: .controlBackgroundColor))
                                    .cornerRadius(6)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 6)
                                            .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                                    )
                                }

                                .menuStyle(.borderlessButton)
                                .buttonStyle(.plain)
                                .fixedSize()
                            }
                        }
                        
                        Divider()
                        
                        HStack {
                            Label(L10n.settingsSpeechLanguage, systemImage: "globe")
                                .font(.body)
                            Spacer()
                            Menu {
                                Button(L10n.languageSystem) { appState.voiceService.explicitLocaleIdentifier = nil }
                                Divider()
                                Button(L10n.languageChineseSC) { appState.voiceService.explicitLocaleIdentifier = "zh-CN" }
                                Button(L10n.languageEnglishUS) { appState.voiceService.explicitLocaleIdentifier = "en-US" }
                                Button(L10n.languageJapanese) { appState.voiceService.explicitLocaleIdentifier = "ja-JP" }
                                Button(L10n.languageKorean) { appState.voiceService.explicitLocaleIdentifier = "ko-KR" }
                                Button(L10n.languageFrench) { appState.voiceService.explicitLocaleIdentifier = "fr-FR" }
                                Button(L10n.languageGerman) { appState.voiceService.explicitLocaleIdentifier = "de-DE" }
                                Button(L10n.languageSpanish) { appState.voiceService.explicitLocaleIdentifier = "es-ES" }
                            } label: {
                                HStack {
                                    Text(localeName(for: appState.voiceService.explicitLocaleIdentifier))
                                        .truncationMode(.tail)
                                        .lineLimit(1)
                                    Spacer()
                                    Image(systemName: "chevron.up.chevron.down")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .frame(width: 200, alignment: .leading)
                                .background(Color(nsColor: .controlBackgroundColor))
                                .cornerRadius(6)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6)
                                        .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                                )
                            }

                            .menuStyle(.borderlessButton)
                            .buttonStyle(.plain)
                            .fixedSize()
                        }
                    }
                }
                
                // Activation Section
                GlassCard {
                    VStack(alignment: .leading, spacing: 20) {
                        Label(L10n.activationMethods, systemImage: "bolt.fill")
                            .font(.headline)
                        
                        // Activation mode (single choice)
                        VStack(spacing: 10) {
                            activationModeRow(
                                mode: .pushToTalk,
                                title: L10n.settingsActivationPushToTalk,
                                subtitle: L10n.activationShortcutHint,
                                icon: "keyboard"
                            )
                            activationModeRow(
                                mode: .wakeWord,
                                title: L10n.settingsActivationWakeWord,
                                subtitle: L10n.activationWakeWordHint,
                                icon: "waveform.badge.mic"
                            )
                            activationModeRow(
                                mode: .handsFree,
                                title: L10n.settingsActivationHandsFree,
                                subtitle: L10n.activationAlwaysHint,
                                icon: "ear.and.waveform"
                            )
                        }
                        
                        if appState.voiceActivationMode == .handsFree {
                            Text(L10n.activationAlwaysWarning)
                                .font(.caption)
                                .foregroundColor(.orange)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        
                        Divider()
                        
                        // PTT shortcut configuration
                        HStack(alignment: .center) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(L10n.activationShortcut)
                                    .font(.body)
                                Text(L10n.activationShortcutHint)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer()
                            
                            HStack(spacing: 12) {
                                HStack(spacing: 4) {
                                    KeyRecorderView(
                                        binding: $appState.voicePTTBinding,
                                        onChange: { newBind in
                                            appState.updatePTTBinding(newBind)
                                        },
                                        font: .body
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

                        Divider()

                        Toggle("上下文术语纠错", isOn: $appState.speechTermCorrectionEnabled)
                        Text("支持通用组与自定义分组。每组可独立启停、绑定 App、编辑词条规则。")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        HStack {
                            Button {
                                appState.addSpeechTermGroup()
                            } label: {
                                Label("添加分组", systemImage: "plus")
                            }
                            .buttonStyle(.borderless)
                            .disabled(!appState.speechTermCorrectionEnabled)
                            Spacer()
                            Text("规则格式：`原词=>目标词` 或 `原词=>目标词=>cmd`")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }

                        ForEach($appState.speechTermGroups) { $group in
                            SpeechTermGroupCard(
                                group: $group,
                                enabledAll: $appState.speechTermCorrectionEnabled,
                                onEdit: { editingGroupID = group.id },
                                onDelete: { appState.removeSpeechTermGroup(id: group.id) }
                            )
                        }
                    }
                }
            }
            .padding()
        }
        .sheet(isPresented: Binding(
            get: { editingGroupID != nil },
            set: { if !$0 { editingGroupID = nil } }
        )) {
            if let id = editingGroupID,
               let idx = appState.speechTermGroups.firstIndex(where: { $0.id == id }) {
                SpeechTermGroupEditorSheet(
                    group: $appState.speechTermGroups[idx],
                    enabledAll: appState.speechTermCorrectionEnabled
                )
            } else {
                EmptyView()
            }
        }
    }
    
    private func localeName(for identifier: String?) -> LocalizedStringKey {
        guard let identifier = identifier else { return L10n.languageSystem }
        switch identifier {
        case "zh-CN": return L10n.languageChineseSC
        case "en-US": return L10n.languageEnglishUS
        case "ja-JP": return L10n.languageJapanese
        case "ko-KR": return L10n.languageKorean
        case "fr-FR": return L10n.languageFrench
        case "de-DE": return L10n.languageGerman
        case "es-ES": return L10n.languageSpanish
        default: return LocalizedStringKey(identifier)
        }
    }
    
    @ViewBuilder
    private func activationModeRow(
        mode: AppState.VoiceActivationMode,
        title: LocalizedStringKey,
        subtitle: LocalizedStringKey,
        icon: String
    ) -> some View {
        Button {
            appState.voiceActivationMode = mode
        } label: {
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: icon)
                    .foregroundColor(.secondary)
                    .frame(width: 18)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.body)
                        .foregroundColor(.primary)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.leading)
                }
                
                Spacer()
                
                Image(systemName: appState.voiceActivationMode == mode ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(appState.voiceActivationMode == mode ? .accentColor : .secondary.opacity(0.5))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.6))
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
    }
}

private enum SpeechGroupAppCodec {
    static func parse(_ raw: String) -> [String] {
        raw
            .components(separatedBy: CharacterSet(charactersIn: ",\n"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    static func join(_ items: [String]) -> String {
        items.joined(separator: "\n")
    }
}

private struct SpeechTermGroupCard: View {
    @Binding var group: AppState.SpeechTermGroupConfig
    @Binding var enabledAll: Bool
    let onEdit: () -> Void
    let onDelete: () -> Void

    private var appItems: [String] { SpeechGroupAppCodec.parse(group.appList) }

    var body: some View {
        HStack(spacing: 10) {
            SpeechGroupAppPreview(apps: appItems, applyToAll: group.applyToAllApps)
            VStack(alignment: .leading, spacing: 2) {
                Text(group.name)
                    .font(.body.weight(.semibold))
                Text(group.applyToAllApps ? "全部 App 生效" : "\(appItems.count) 个 App")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
            Toggle("", isOn: $group.isEnabled)
                .disabled(!enabledAll)
            Button("编辑") { onEdit() }
                .buttonStyle(.borderless)
                .disabled(!enabledAll)
            Button(action: onDelete) {
                Image(systemName: "trash")
                    .foregroundColor(.red)
            }
            .buttonStyle(.borderless)
            .disabled(!enabledAll)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.4))
        .cornerRadius(8)
    }
}

private struct SpeechTermGroupEditorSheet: View {
    @Binding var group: AppState.SpeechTermGroupConfig
    let enabledAll: Bool
    @Environment(\.dismiss) private var dismiss

    private var appItems: [String] { SpeechGroupAppCodec.parse(group.appList) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("编辑分组")
                    .font(.headline)
                Spacer()
                Button("完成") { dismiss() }
            }

            TextField("分组名", text: $group.name)
                .textFieldStyle(.roundedBorder)
                .disabled(!enabledAll)

            Toggle("启用此分组", isOn: $group.isEnabled)
                .disabled(!enabledAll)
            Toggle("通用组（全部 App 生效）", isOn: $group.applyToAllApps)
                .disabled(!enabledAll || !group.isEnabled)

            if !group.applyToAllApps {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("生效 App")
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        SpeechAppPickerMenu(
                            existingBundleIds: Set(appItems.map { $0.lowercased() }),
                            onAdd: { bid in
                                var items = appItems
                                if !items.map({ $0.lowercased() }).contains(bid.lowercased()) {
                                    items.append(bid)
                                }
                                group.appList = SpeechGroupAppCodec.join(items)
                            }
                        )
                        .disabled(!enabledAll || !group.isEnabled)
                    }
                    ScrollView {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(appItems, id: \.self) { bundleID in
                                SpeechAppChip(bundleID: bundleID) {
                                    var items = appItems
                                    items.removeAll { $0 == bundleID }
                                    group.appList = SpeechGroupAppCodec.join(items)
                                }
                            }
                        }
                    }
                    .frame(minHeight: 88, maxHeight: 130)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("词条规则")
                    .font(.subheadline.weight(.semibold))
                Text("每行一条：`原词=>目标词`，可选 `=>cmd` 仅命令语境生效。")
                    .font(.caption)
                    .foregroundColor(.secondary)
                TextEditor(text: $group.rulesText)
                    .font(.system(.caption, design: .monospaced))
                    .frame(minHeight: 120)
                    .padding(6)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .cornerRadius(6)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                    )
                    .disabled(!enabledAll || !group.isEnabled)
            }
        }
        .padding(16)
        .frame(width: 560, height: 520)
    }
}

private struct SpeechGroupAppPreview: View {
    let apps: [String]
    let applyToAll: Bool

    var body: some View {
        HStack(spacing: -6) {
            if applyToAll {
                Image(systemName: "square.stack.3d.up.fill")
                    .font(.system(size: 14))
                    .frame(width: 26, height: 26)
                    .background(Color.accentColor.opacity(0.18))
                    .clipShape(Circle())
            } else {
                ForEach(Array(apps.prefix(3)), id: \.self) { bid in
                    SpeechAppIcon(bundleID: bid)
                        .frame(width: 26, height: 26)
                }
                if apps.count > 3 {
                    Text("+\(apps.count - 3)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .padding(.leading, 4)
                }
            }
        }
    }
}

private struct SpeechAppChip: View {
    let bundleID: String
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            SpeechAppIcon(bundleID: bundleID)
                .frame(width: 20, height: 20)
            Text(SpeechAppMetaStore.name(for: bundleID))
                .lineLimit(1)
            Spacer()
            Text(bundleID)
                .font(.caption2)
                .foregroundColor(.secondary)
                .lineLimit(1)
            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.borderless)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
        .cornerRadius(6)
    }
}

private enum SpeechAppMetaStore {
    static func name(for bundleID: String) -> String {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID),
           let bundle = Bundle(url: url),
           let name = bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
                ?? bundle.object(forInfoDictionaryKey: "CFBundleName") as? String {
            return name
        }
        return bundleID
    }
}

private struct SpeechAppIcon: View {
    let bundleID: String

    var body: some View {
        Group {
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                    .resizable()
                    .interpolation(.high)
            } else {
                Image(systemName: "app.fill")
                    .resizable()
                    .scaledToFit()
                    .foregroundColor(.secondary)
                    .padding(4)
            }
        }
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 5))
        .overlay(
            RoundedRectangle(cornerRadius: 5)
                .stroke(Color.secondary.opacity(0.25), lineWidth: 1)
        )
    }
}

private struct SpeechAppPickerMenu: View {
    let existingBundleIds: Set<String>
    let onAdd: (String) -> Void

    private struct Candidate: Identifiable {
        let id: String
        let name: String
        let bundleId: String
    }

    private var runningCandidates: [Candidate] {
        var seen = Set<String>()
        let apps = NSWorkspace.shared.runningApplications.compactMap { app -> Candidate? in
            guard app.activationPolicy == .regular else { return nil }
            guard let bid = app.bundleIdentifier, !bid.isEmpty else { return nil }
            let key = bid.lowercased()
            guard !existingBundleIds.contains(key) else { return nil }
            guard !seen.contains(key) else { return nil }
            seen.insert(key)
            return Candidate(id: bid, name: app.localizedName ?? bid, bundleId: bid)
        }
        return apps.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        Menu {
            if runningCandidates.isEmpty {
                Text("无可添加的运行中应用")
            } else {
                Text("运行中应用")
                ForEach(runningCandidates) { app in
                    Button {
                        onAdd(app.bundleId)
                    } label: {
                        HStack(spacing: 8) {
                            SpeechAppIcon(bundleID: app.bundleId)
                                .frame(width: 16, height: 16)
                            Text(app.name)
                            Text("(\(app.bundleId))")
                                .foregroundColor(.secondary)
                        }
                    }
                }
                Divider()
            }

            Button("手动选择应用…") {
                chooseApplication()
            }
        } label: {
            Label("添加程序", systemImage: "plus")
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    private func chooseApplication() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.prompt = "添加"

        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            guard let bundle = Bundle(url: url), let bid = bundle.bundleIdentifier, !bid.isEmpty else { return }
            onAdd(bid)
        }
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
