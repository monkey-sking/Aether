import SwiftUI
import AppKit

// MARK: - Input Settings (Voice)
struct InputSettingsView: View {
    @EnvironmentObject var appState: AppState
    @State private var editingGroupID: String?
    @State private var commandLocaleID: String = ""
    @State private var lexiconTransferStatus: String?

    private let supportedVoiceLocaleIDs = [
        "zh-CN", "en-US", "ja-JP", "ko-KR", "fr-FR", "de-DE", "es-ES"
    ]

    private var microphoneOptions: [FixedPopUpOption] {
        appState.availableInputDevices.map { device in
            FixedPopUpOption(id: String(device.id), title: device.name)
        }
    }

    private var microphoneSelection: Binding<String> {
        Binding(
            get: { String(appState.selectedInputDeviceID) },
            set: { newValue in
                guard let matched = appState.availableInputDevices.first(where: { String($0.id) == newValue }) else { return }
                appState.selectedInputDeviceID = matched.id
            }
        )
    }

    private var speechLanguageSelection: Binding<String> {
        Binding(
            get: { appState.voiceService.explicitLocaleIdentifier ?? "system" },
            set: { newValue in
                appState.voiceService.explicitLocaleIdentifier = (newValue == "system") ? nil : newValue
            }
        )
    }

    private var effectiveSpeechLocaleID: String {
        normalizedCommandLocaleIdentifier(appState.voiceService.explicitLocaleIdentifier ?? Locale.current.identifier)
    }

    private var effectiveSpeechLocaleDisplayName: String {
        localeTitle(for: effectiveSpeechLocaleID)
    }

    private var isFollowingSystemSpeechLocale: Bool {
        appState.voiceService.explicitLocaleIdentifier == nil
    }

    private var speechLanguageOptions: [VoiceLanguageOption] {
        [
            VoiceLanguageOption(id: "system", title: String(localized: "language.system"))
        ] + supportedVoiceLocaleIDs.map { VoiceLanguageOption(id: $0, title: localeTitle(for: $0)) }
    }

    private var lexiconLanguageOptions: [VoiceLanguageOption] {
        supportedVoiceLocaleIDs.map { VoiceLanguageOption(id: $0, title: localeTitle(for: $0)) }
    }

    private var resolvedCommandLocaleID: String {
        let preferred = commandLocaleID.isEmpty
            ? (appState.voiceService.explicitLocaleIdentifier ?? Locale.current.identifier)
            : commandLocaleID
        return normalizedCommandLocaleIdentifier(preferred)
    }

    private var commandLocaleDisplayName: String {
        Locale.current.localizedString(forIdentifier: resolvedCommandLocaleID) ?? resolvedCommandLocaleID
    }

    private func normalizedCommandLocaleIdentifier(_ raw: String) -> String {
        let candidate = raw == "system" ? Locale.current.identifier : raw
        if supportedVoiceLocaleIDs.contains(candidate) {
            return candidate
        }
        return candidate.hasPrefix("zh") ? "zh-CN" : "en-US"
    }

    private func localeTitle(for localeIdentifier: String) -> String {
        switch localeIdentifier {
        case "system":
            return String(localized: "language.system")
        case "zh-CN":
            return String(localized: "language.zh_CN")
        case "en-US":
            return String(localized: "language.en_US")
        case "ja-JP":
            return String(localized: "language.ja_JP")
        case "ko-KR":
            return String(localized: "language.ko_KR")
        case "fr-FR":
            return String(localized: "language.fr_FR")
        case "de-DE":
            return String(localized: "language.de_DE")
        case "es-ES":
            return String(localized: "language.es_ES")
        default:
            return Locale.current.localizedString(forIdentifier: localeIdentifier) ?? localeIdentifier
        }
    }

    var body: some View {
        SettingsPage(
            title: Locale.current.identifier.hasPrefix("zh") ? "语音" : "Voice",
            subtitle: Locale.current.identifier.hasPrefix("zh")
                ? "管理麦克风、唤起方式、听写增强和术语纠错。"
                : "Manage microphone input, activation mode, dictation enhancement, and terminology rules."
        ) {
            VStack(spacing: 20) {
                GlassCard {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            Label(L10n.settingsMicrophone, systemImage: "mic.fill")
                                .font(.body)
                            Spacer()
                            
                            if appState.availableInputDevices.isEmpty {
                                Text(L10n.settingsNoMicrophone)
                                    .foregroundColor(.secondary)
                            } else {
                                FixedWidthPopUpMenu(
                                    options: microphoneOptions,
                                    selection: microphoneSelection
                                )
                            }
                        }

                        Divider()

                        VStack(alignment: .leading, spacing: 10) {
                            HStack(alignment: .top) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Label(L10n.settingsSpeechLanguage, systemImage: "globe")
                                        .font(.body)
                                    Text(Locale.current.identifier.hasPrefix("zh")
                                         ? "影响语音识别和默认命令词库。"
                                         : "This controls speech recognition and the default command lexicon.")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                LanguageStatusTag(
                                    title: isFollowingSystemSpeechLocale
                                        ? (Locale.current.identifier.hasPrefix("zh")
                                            ? "跟随系统 · \(effectiveSpeechLocaleDisplayName)"
                                            : "System · \(effectiveSpeechLocaleDisplayName)")
                                        : effectiveSpeechLocaleDisplayName,
                                    tint: .blue
                                )
                            }

                            VoiceLanguageChipPicker(
                                options: speechLanguageOptions,
                                selection: speechLanguageSelection
                            )
                        }
                    }
                }
                
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

                        if appState.voiceActivationMode != .pushToTalk &&
                            (!appState.microphoneAuthorized || !appState.speechAuthorized) {
                            VStack(alignment: .leading, spacing: 8) {
                                Label("当前模式需要语音权限", systemImage: "exclamationmark.triangle.fill")
                                    .font(.caption.weight(.semibold))
                                    .foregroundColor(.orange)

                                if !appState.microphoneAuthorized {
                                    Button("去开启麦克风权限") {
                                        appState.requestMicrophoneGuided()
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                                }

                                if !appState.speechAuthorized {
                                    Button("去开启语音识别权限") {
                                        appState.requestSpeechGuided()
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                                }
                            }
                            .padding(10)
                            .background(Color.orange.opacity(0.12))
                            .cornerRadius(8)
                        }
                        
                        Divider()

                        HStack(alignment: .center) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(L10n.activationShortcut)
                                    .font(.body)
                                Text(Locale.current.identifier.hasPrefix("zh")
                                     ? "当前按键为 \(appState.voicePTTBinding.displayString)。如需修改，请到“快捷键”页面统一设置。"
                                     : "Current shortcut: \(appState.voicePTTBinding.displayString). Change it from the Shortcuts page.")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer()
                            Text(appState.voicePTTBinding.displayString)
                                .font(.system(.caption, design: .monospaced))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(Color(nsColor: .controlBackgroundColor))
                                .cornerRadius(8)
                        }
                    }
                }
                
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
                            Text("规则格式：`原词=>目标词` 或 `原词=>目标词=>cmd`")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            Spacer()
                            Button {
                                appState.addSpeechTermGroup()
                            } label: {
                                Label("添加分组", systemImage: "plus")
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                            .disabled(!appState.speechTermCorrectionEnabled)
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

                GlassCard {
                    VStack(alignment: .leading, spacing: 14) {
                        Label(L10n.voiceLexiconTitle, systemImage: "list.bullet.clipboard")
                        .font(.headline)

                        Text(L10n.voiceLexiconDescription)
                        .font(.caption)
                        .foregroundColor(.secondary)

                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(L10n.voiceLexiconEditingLanguage)
                                    .font(.caption.weight(.semibold))
                                    .foregroundColor(.secondary)
                                Text(Locale.current.identifier.hasPrefix("zh")
                                     ? "按语言编辑唤醒词、前缀和命令别名。"
                                     : "Edit wake words, prefixes, and command aliases per language.")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            LanguageStatusTag(title: commandLocaleDisplayName, tint: .blue)
                            Button(L10n.voiceLexiconResetLanguage) {
                                appState.resetCommandOverrides(for: resolvedCommandLocaleID)
                                appState.resetVoiceLanguageTermsOverrides(for: resolvedCommandLocaleID)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }

                        VoiceLanguageChipPicker(
                            options: lexiconLanguageOptions,
                            selection: Binding(
                                get: { resolvedCommandLocaleID },
                                set: { commandLocaleID = $0 }
                            )
                        )

                        HStack(spacing: 10) {
                            Button(L10n.voiceLexiconImport) {
                                do {
                                    if let url = try appState.importVoiceLexicon() {
                                        lexiconTransferStatus = "\(String(localized: "voice_lexicon.imported")): \(url.lastPathComponent)"
                                    }
                                } catch {
                                    lexiconTransferStatus = "\(String(localized: "voice_lexicon.import_failed")): \(error.localizedDescription)"
                                }
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)

                            Button(L10n.voiceLexiconExport) {
                                do {
                                    if let url = try appState.exportVoiceLexicon() {
                                        lexiconTransferStatus = "\(String(localized: "voice_lexicon.exported")): \(url.lastPathComponent)"
                                    }
                                } catch {
                                    lexiconTransferStatus = "\(String(localized: "voice_lexicon.export_failed")): \(error.localizedDescription)"
                                }
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)

                            Spacer()
                        }

                        if let lexiconTransferStatus, !lexiconTransferStatus.isEmpty {
                            Text(lexiconTransferStatus)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        VStack(spacing: 12) {
                            VoiceTermsEditorRow(
                                title: String(localized: "voice_lexicon.wake_words"),
                                text: Binding(
                                    get: { appState.wakeWordOverrideText(for: resolvedCommandLocaleID) },
                                    set: { appState.updateWakeWordOverrideText($0, for: resolvedCommandLocaleID) }
                                ),
                                defaultValues: WakeWordDetector.defaultWakePhrases(for: resolvedCommandLocaleID),
                                onReset: {
                                    appState.updateWakeWordOverrideText("", for: resolvedCommandLocaleID)
                                }
                            )

                            VoiceTermsEditorRow(
                                title: String(localized: "voice_lexicon.command_prefixes"),
                                text: Binding(
                                    get: { appState.commandPrefixOverrideText(for: resolvedCommandLocaleID) },
                                    set: { appState.updateCommandPrefixOverrideText($0, for: resolvedCommandLocaleID) }
                                ),
                                defaultValues: VoiceCommandRouter.defaultCommandPrefixes(for: resolvedCommandLocaleID),
                                onReset: {
                                    appState.updateCommandPrefixOverrideText("", for: resolvedCommandLocaleID)
                                }
                            )

                            VoiceTermsEditorRow(
                                title: String(localized: "voice_lexicon.dictation_prefixes"),
                                text: Binding(
                                    get: { appState.dictationPrefixOverrideText(for: resolvedCommandLocaleID) },
                                    set: { appState.updateDictationPrefixOverrideText($0, for: resolvedCommandLocaleID) }
                                ),
                                defaultValues: VoiceCommandRouter.defaultDictationPrefixes(for: resolvedCommandLocaleID),
                                onReset: {
                                    appState.updateDictationPrefixOverrideText("", for: resolvedCommandLocaleID)
                                }
                            )
                        }

                        Divider()

                        VStack(spacing: 12) {
                            ForEach(VoiceCommandPreset.allCases) { preset in
                                VoiceCommandAliasRow(
                                    preset: preset,
                                    text: Binding(
                                        get: { appState.commandOverrideText(for: preset, localeIdentifier: resolvedCommandLocaleID) },
                                        set: { appState.updateCommandOverrideText($0, for: preset, localeIdentifier: resolvedCommandLocaleID) }
                                    ),
                                    defaultAliases: VoiceCommandRouter.defaultAliases(for: preset, localeIdentifier: resolvedCommandLocaleID),
                                    onReset: {
                                        appState.updateCommandOverrideText("", for: preset, localeIdentifier: resolvedCommandLocaleID)
                                    }
                                )
                            }
                        }
                    }
                }
            }
        }
        .onAppear {
            if commandLocaleID.isEmpty {
                let preferred = appState.voiceService.explicitLocaleIdentifier ?? Locale.current.identifier
                commandLocaleID = normalizedCommandLocaleIdentifier(preferred)
            }
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

private struct VoiceLanguageOption: Identifiable, Equatable {
    let id: String
    let title: String
}

private struct VoiceLanguageChipPicker: View {
    let options: [VoiceLanguageOption]
    @Binding var selection: String

    private let columns = [
        GridItem(.adaptive(minimum: 112), spacing: 10)
    ]

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 10) {
            ForEach(options) { option in
                Button {
                    selection = option.id
                } label: {
                    Text(option.title)
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(selection == option.id ? .accentColor : .primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(selection == option.id ? Color.accentColor.opacity(0.14) : Color(nsColor: .controlBackgroundColor).opacity(0.72))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(selection == option.id ? Color.accentColor.opacity(0.35) : Color.black.opacity(0.05), lineWidth: 1)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
    }
}

private struct LanguageStatusTag: View {
    let title: String
    let tint: Color

    var body: some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(tint.opacity(0.12))
            .foregroundColor(tint)
            .clipShape(Capsule())
    }
}

private struct VoiceTermsEditorRow: View {
    let title: String
    @Binding var text: String
    let defaultValues: [String]
    let onReset: () -> Void

    private var hasOverride: Bool { !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.body.weight(.medium))
                Spacer()
                if hasOverride {
                    Text(L10n.voiceLexiconCustom)
                        .font(.caption)
                        .foregroundColor(.accentColor)
                }
            }

            TextField(
                String(localized: "voice_lexicon.leave_empty"),
                text: $text
            )
            .textFieldStyle(.roundedBorder)

            HStack(alignment: .firstTextBaseline) {
                Text("\(String(localized: "voice_lexicon.default")): \(defaultValues.joined(separator: ", "))")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)

                Spacer()

                Button(L10n.voiceLexiconClear) {
                    onReset()
                }
                .buttonStyle(.borderless)
                .disabled(!hasOverride)
            }
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
        .cornerRadius(10)
    }
}

private struct VoiceCommandAliasRow: View {
    let preset: VoiceCommandPreset
    @Binding var text: String
    let defaultAliases: [String]
    let onReset: () -> Void

    private var hasOverride: Bool { !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(preset.title())
                    .font(.body.weight(.medium))
                Spacer()
                if hasOverride {
                    Text(L10n.voiceLexiconCustom)
                        .font(.caption)
                        .foregroundColor(.accentColor)
                }
            }

            TextField(
                String(localized: "voice_lexicon.leave_empty"),
                text: $text
            )
            .textFieldStyle(.roundedBorder)

            HStack(alignment: .firstTextBaseline) {
                Text("\(String(localized: "voice_lexicon.default")): \(defaultAliases.joined(separator: ", "))")
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(2)

                Spacer()

                Button(L10n.voiceLexiconClear) {
                    onReset()
                }
                .buttonStyle(.borderless)
                .disabled(!hasOverride)
            }
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
        .cornerRadius(10)
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

private struct FixedPopUpOption: Equatable {
    let id: String
    let title: String
}

private struct FixedWidthPopUpMenu: NSViewRepresentable {
    var options: [FixedPopUpOption]
    @Binding var selection: String

    final class SelectedOnlyPopUpButton: NSPopUpButton {
        var horizontalPadding: CGFloat = 34

        override var intrinsicContentSize: NSSize {
            let base = super.intrinsicContentSize
            guard let title = selectedItem?.title, !title.isEmpty else { return base }
            let fontToUse = font ?? NSFont.systemFont(ofSize: NSFont.systemFontSize(for: .small))
            let titleWidth = (title as NSString).size(withAttributes: [.font: fontToUse]).width
            return NSSize(width: ceil(titleWidth + horizontalPadding), height: base.height)
        }
    }

    final class Coordinator: NSObject {
        var parent: FixedWidthPopUpMenu

        init(parent: FixedWidthPopUpMenu) {
            self.parent = parent
        }

        @objc func selectionChanged(_ sender: NSPopUpButton) {
            let idx = sender.indexOfSelectedItem
            guard idx >= 0 && idx < parent.options.count else { return }
            let selectedID = parent.options[idx].id
            if parent.selection != selectedID {
                parent.selection = selectedID
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSPopUpButton {
        let button = SelectedOnlyPopUpButton(frame: .zero, pullsDown: false)
        button.bezelStyle = .rounded
        button.controlSize = .small
        button.target = context.coordinator
        button.action = #selector(Coordinator.selectionChanged(_:))
        button.lineBreakMode = .byTruncatingTail
        button.setContentCompressionResistancePriority(.required, for: .horizontal)
        button.setContentHuggingPriority(.required, for: .horizontal)
        rebuildItems(button)
        button.sizeToFit()
        return button
    }

    func updateNSView(_ button: NSPopUpButton, context: Context) {
        context.coordinator.parent = self

        let existingTitles = button.itemTitles
        let desiredTitles = options.map(\.title)
        if existingTitles != desiredTitles {
            rebuildItems(button)
        }

        if let idx = options.firstIndex(where: { $0.id == selection }),
           button.indexOfSelectedItem != idx {
            button.selectItem(at: idx)
        } else if !options.isEmpty && button.indexOfSelectedItem < 0 {
            button.selectItem(at: 0)
        }
        button.invalidateIntrinsicContentSize()
    }

    private func rebuildItems(_ button: NSPopUpButton) {
        button.removeAllItems()
        button.addItems(withTitles: options.map(\.title))
        if let idx = options.firstIndex(where: { $0.id == selection }) {
            button.selectItem(at: idx)
        } else if !options.isEmpty {
            button.selectItem(at: 0)
        }
    }
}

// MARK: - Output Settings (Motion)
struct OutputSettingsView: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject var headManager = HeadMotionManager.shared

    private var trackingBinding: Binding<Bool> {
        Binding(
            get: { headManager.isTracking },
            set: { isOn in
                if isOn {
                    headManager.startTracking()
                } else {
                    headManager.stopTracking()
                }
            }
        )
    }
    
    var body: some View {
        SettingsPage(
            title: Locale.current.identifier.hasPrefix("zh") ? "指针" : "Pointer",
            subtitle: Locale.current.identifier.hasPrefix("zh")
                ? "集中调整头控启停、点击方式与校准状态。"
                : "Adjust tracking, click behavior, and calibration in one place."
        ) {
            VStack(spacing: 20) {
                GlassCard {
                    ControlCard(
                        title: L10n.commandCenterMotionMatrix, // Reusing Motion Matrix title which is appropriate
                        subtitle: headManager.isTracking ? L10n.statusActive : L10n.statusPaused,
                        icon: "viewfinder",
                        color: .green,
                        isOn: trackingBinding
                    )
                }
                
                GlassCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Label(L10n.settingsGesturesClicks, systemImage: "hand.point.up.left.fill")
                            .font(.headline)

                        ControlCard(
                            title: L10n.tiltScroll,
                            subtitle: L10n.settingsTiltScrollSubtitle,
                            icon: "arrow.up.arrow.down",
                            color: .indigo,
                            isOn: $headManager.isTiltScrollEnabled
                        )
                    }
                }
                
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
        }
    }
}

// MARK: - System Settings
struct SystemSettingsView: View {
    @EnvironmentObject var appState: AppState
    
    var body: some View {
        SettingsPage(
            title: Locale.current.identifier.hasPrefix("zh") ? "高级" : "Advanced",
            subtitle: Locale.current.identifier.hasPrefix("zh")
                ? "查看驱动、权限和应用级行为设置。"
                : "Review driver state, permissions, and app-level behavior."
        ) {
            VStack(spacing: 20) {
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
                
                GlassCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Label(L10n.permissionsTitle, systemImage: "lock.shield")
                            .font(.headline)
                        
                       PermissionRow(
                           icon: "hand.raised.fill",
                           title: L10n.permissionAccessibility,
                           isGranted: appState.accessibilityTrusted,
                           detail: appState.accessibilityStatusDetail
                       ) {
                           appState.requestAccessibilityGuided()
                       }
                       PermissionRow(
                           icon: "mic.fill",
                           title: L10n.permissionMicrophone,
                           isGranted: appState.microphoneAuthorized,
                           detail: appState.microphoneStatusDetail
                       ) {
                           appState.requestMicrophoneGuided()
                       }
                       PermissionRow(
                           icon: "waveform",
                           title: L10n.permissionSpeech,
                           isGranted: appState.speechAuthorized,
                           detail: appState.speechStatusDetail
                       ) {
                           appState.requestSpeechGuided()
                       }
                    }
                }
                
                GlassCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Label(L10n.settingsTabGeneral, systemImage: "gear")
                            .font(.headline)
                        
                        Toggle(L10n.showDockIcon, isOn: $appState.showDockIcon)
                    }
                }
            }
        }
    }
}

// MARK: - Shortcuts Placeholder
struct ShortcutsSettingsView: View {
    var body: some View {
        SettingsPage(
            title: Locale.current.identifier.hasPrefix("zh") ? "快捷键" : "Shortcuts",
            subtitle: Locale.current.identifier.hasPrefix("zh")
                ? "统一管理按住说话、头控和连接锁等全局快捷键。"
                : "Manage Push to Talk, pointer control, connection lock, and other global shortcuts."
        ) {
            GlassCard {
                HotkeySettingsSection()
            }
        }
    }
}
