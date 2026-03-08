import SwiftUI
import AppKit

enum VoiceSettingsSection: Hashable {
    case basics
    case termCorrections
    case lexicon
    case appControls
    case insights

    var zhTitle: String {
        switch self {
        case .basics: return "基础"
        case .termCorrections: return "术语纠错"
        case .lexicon: return "词库"
        case .appControls: return "当前应用"
        case .insights: return "统计"
        }
    }

    var enTitle: String {
        switch self {
        case .basics: return "Basics"
        case .termCorrections: return "Term Corrections"
        case .lexicon: return "Lexicon"
        case .appControls: return "Current App"
        case .insights: return "Insights"
        }
    }

    var systemImage: String {
        switch self {
        case .basics: return "mic.fill"
        case .termCorrections: return "text.magnifyingglass"
        case .lexicon: return "text.badge.star"
        case .appControls: return "app.badge"
        case .insights: return "chart.bar.xaxis"
        }
    }

    func title(isChinese: Bool) -> String {
        isChinese ? zhTitle : enTitle
    }

    func pageTitle(isChinese: Bool) -> String {
        switch self {
        case .basics:
            return isChinese ? "语音基础" : "Voice Basics"
        case .termCorrections:
            return isChinese ? "术语纠错" : "Term Corrections"
        case .lexicon:
            return isChinese ? "语音词库" : "Voice Lexicon"
        case .appControls:
            return isChinese ? "当前应用控制" : "Current App Controls"
        case .insights:
            return isChinese ? "语音统计" : "Voice Insights"
        }
    }

    func pageSubtitle(isChinese: Bool) -> String {
        switch self {
        case .basics:
            return isChinese ? "麦克风、识别语言和触发方式。" : "Microphone, recognition language, and activation modes."
        case .termCorrections:
            return isChinese ? "听写润色、识别纠错和按 App 的术语替换规则。" : "Dictation refinement, recognition corrections, and app-specific terminology rules."
        case .lexicon:
            return isChinese ? "唤醒词和命令别名。" : "Wake words and command aliases."
        case .appControls:
            return isChinese ? "查看前台 App 可直接触发的快捷键。" : "Review shortcuts available for the frontmost app."
        case .insights:
            return isChinese ? "按 App 查看语音输入与控制使用记录。" : "Per-app voice dictation and control activity history."
        }
    }
}

// MARK: - Input Settings (Voice)
struct InputSettingsView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var frontmostAppCommandCatalog = FrontmostAppCommandCatalog.shared
    @State private var editingGroupID: String?
    @State private var commandLocaleID: String = ""
    @State private var lexiconTransferStatus: String?
    let section: VoiceSettingsSection

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

    private var isChinese: Bool {
        Locale.current.identifier.hasPrefix("zh")
    }

    private var visibleFrontmostCommands: [FrontmostAppCommand] {
        let commands = frontmostAppCommandCatalog.snapshot?.commands ?? []
        let recommended = commands.filter { $0.aliases.count > 2 }
        return Array((recommended.isEmpty ? commands : recommended).prefix(12))
    }

    private var commandAliasSections: [VoiceLexiconSection] {
        [
            VoiceLexiconSection(
                title: isChinese ? "基础控制" : "Core Controls",
                subtitle: isChinese ? "鼠标点击、滚动、拖拽与常用编辑动作。" : "Pointer clicks, scrolling, dragging, and common editing actions.",
                presets: [.clickLeft, .clickRight, .doubleClick, .scrollUp, .scrollDown, .scrollTop, .scrollBottom, .dragStart, .dragEnd, .undo, .paste]
            ),
            VoiceLexiconSection(
                title: isChinese ? "媒体与面板" : "Media & Panels",
                subtitle: isChinese ? "播放控制和快捷键面板显示控制。" : "Playback controls and shortcut panel visibility.",
                presets: [.mediaPlayPause, .mediaPrevious, .mediaNext, .showShortcutPanel, .hideShortcutPanel]
            ),
            VoiceLexiconSection(
                title: isChinese ? "指针与连接" : "Pointer & Connection",
                subtitle: isChinese ? "头控启停、回中校准与耳机连接锁定。" : "Pointer tracking, recentering, and headset connection lock.",
                presets: [.startPointer, .stopPointer, .recenter, .lockConnection, .unlockConnection]
            )
        ]
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
            title: section.pageTitle(isChinese: isChinese),
            subtitle: section.pageSubtitle(isChinese: isChinese)
        ) {
            VStack(spacing: 20) {
                if section == .basics {
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
                                if isFollowingSystemSpeechLocale {
                                    LanguageStatusTag(
                                        title: Locale.current.identifier.hasPrefix("zh")
                                            ? "跟随系统 · \(effectiveSpeechLocaleDisplayName)"
                                            : "System · \(effectiveSpeechLocaleDisplayName)",
                                        tint: .blue
                                    )
                                }
                            }

                            VoiceLanguageChipPicker(
                                options: speechLanguageOptions,
                                selection: speechLanguageSelection
                            )
                        }
                    }
                }
                }
                
                if section == .basics {
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
                }
                
                if section == .termCorrections {
                    GlassCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Label(L10n.settingsDictationMode, systemImage: "text.quote")
                            .font(.headline)

                        Text(isChinese
                             ? "对识别结果做后处理和润色，适合放在纠错页统一管理。"
                             : "Post-process and refine dictation output from one place.")
                            .font(.caption)
                            .foregroundColor(.secondary)

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

                    GlassCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Label(isChinese ? "上下文术语纠错" : "Contextual Term Corrections", systemImage: "text.magnifyingglass")
                            .font(.headline)

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
                }

                if section == .lexicon {
                    GlassCard {
                    VStack(alignment: .leading, spacing: 14) {
                        Label(L10n.voiceLexiconTitle, systemImage: "list.bullet.clipboard")
                        .font(.headline)

                        Text(String(localized: "voice_lexicon.description"))
                        .font(.caption)
                        .foregroundColor(.secondary)

                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(L10n.voiceLexiconEditingLanguage)
                                    .font(.caption.weight(.semibold))
                                    .foregroundColor(.secondary)
                                Text(Locale.current.identifier.hasPrefix("zh")
                                     ? "按语言编辑唤醒词和命令别名。"
                                     : "Edit wake words and command aliases per language.")
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
                            VoiceLexiconEditorRow(
                                title: String(localized: "voice_lexicon.wake_words"),
                                subtitle: isChinese
                                    ? "先叫醒 Aether，再说后面的命令。适合免提常驻。"
                                    : "Say these first to wake Aether before the command.",
                                example: isChinese
                                    ? "例如：Aether、阿瑟、嘿 Aether"
                                    : "Example: Aether, Hey Aether",
                                text: Binding(
                                    get: { appState.wakeWordOverrideText(for: resolvedCommandLocaleID) },
                                    set: { appState.updateWakeWordOverrideText($0, for: resolvedCommandLocaleID) }
                                ),
                                defaultValues: WakeWordDetector.defaultWakePhrases(for: resolvedCommandLocaleID),
                                onReset: {
                                    appState.updateWakeWordOverrideText("", for: resolvedCommandLocaleID)
                                }
                            )
                        }

                        Divider()

                        VStack(alignment: .leading, spacing: 12) {
                            Label(
                                isChinese ? "控制命令别名" : "Control Command Aliases",
                                systemImage: "command"
                            )
                            .font(.headline)

                            Text(
                                isChinese
                                    ? "下面这些是内置控制命令。你可以按语言改成自己更习惯的说法，留空则使用默认词库。"
                                    : "These are built-in control commands. Customize phrases per language, or leave blank to use defaults."
                            )
                            .font(.caption)
                            .foregroundColor(.secondary)

                            ForEach(commandAliasSections) { aliasSection in
                                VStack(alignment: .leading, spacing: 10) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(aliasSection.title)
                                            .font(.subheadline.weight(.semibold))
                                        Text(aliasSection.subtitle)
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }

                                    VStack(spacing: 12) {
                                        ForEach(aliasSection.presets) { preset in
                                            VoiceLexiconEditorRow(
                                                title: preset.editorTitle(),
                                                subtitle: preset.editorDescription(),
                                                example: preset.editorExample(),
                                                text: Binding(
                                                    get: { appState.commandOverrideText(for: preset, localeIdentifier: resolvedCommandLocaleID) },
                                                    set: { appState.updateCommandOverrideText($0, for: preset, localeIdentifier: resolvedCommandLocaleID) }
                                                ),
                                                defaultValues: VoiceCommandRouter.defaultAliases(for: preset, localeIdentifier: resolvedCommandLocaleID),
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
                }
                }

                if section == .appControls {
                    GlassCard {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 4) {
                                Label(
                                    Locale.current.identifier.hasPrefix("zh") ? "当前应用控制" : "Current App Controls",
                                    systemImage: "app.badge"
                                )
                                .font(.headline)

                                Text(Locale.current.identifier.hasPrefix("zh")
                                     ? "这里展示前台 App 菜单暴露出的快捷键，并补充浏览器、编辑器、终端等常见默认快捷键。语音命中后会直接触发对应组合键。"
                                     : "These commands come from the frontmost app's menu shortcuts, with common browser, editor, and terminal defaults filled in when helpful. A matched voice command triggers the corresponding key combo.")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            if let snapshot = frontmostAppCommandCatalog.snapshot {
                                LanguageStatusTag(title: snapshot.appName, tint: .green)
                            }
                            Button(String(localized: "current_app_controls.open_panel")) {
                                appState.showShortcutPanel()
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                            Button(String(localized: "generic.refresh")) {
                                _ = frontmostAppCommandCatalog.refresh(force: true)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }

                        if !appState.accessibilityTrusted {
                            Text(Locale.current.identifier.hasPrefix("zh")
                                 ? "需要先开启辅助功能权限，才能读取当前应用菜单和快捷键。"
                                 : "Accessibility permission is required to read the current app's menu shortcuts.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        } else if let snapshot = frontmostAppCommandCatalog.snapshot, !snapshot.commands.isEmpty {
                            Text(
                                Locale.current.identifier.hasPrefix("zh")
                                    ? "已读取 \(snapshot.commands.count) 条快捷键。下面是推荐用于语音控制的高频项，浏览器、编辑器和终端常用快捷键也会补进来。"
                                    : "Loaded \(snapshot.commands.count) shortcuts. The preview below highlights voice-friendly items, including common browser, editor, and terminal defaults."
                            )
                            .font(.caption)
                            .foregroundColor(.secondary)

                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 10)], spacing: 10) {
                                ForEach(visibleFrontmostCommands) { command in
                                    FrontmostAppCommandCard(command: command)
                                }
                            }
                        } else {
                            Text(Locale.current.identifier.hasPrefix("zh")
                                 ? "当前前台 App 没有可读取的菜单快捷键，或者还没有切到目标应用。"
                                 : "The frontmost app does not expose readable menu shortcuts yet, or there is no target app in focus.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                }

                if section == .insights {
                    VoiceUsageInsightsCard()
                }
            }
        }
        .onAppear {
            if commandLocaleID.isEmpty {
                let preferred = appState.voiceService.explicitLocaleIdentifier ?? Locale.current.identifier
                commandLocaleID = normalizedCommandLocaleIdentifier(preferred)
            }
            _ = frontmostAppCommandCatalog.refresh(force: true)
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

private struct HeadsetShortcutMappingCard: View {
    @ObservedObject private var motionManager = HeadMotionManager.shared

    private var isChinese: Bool {
        Locale.current.identifier.hasPrefix("zh")
    }

    private var triplePressOptions: [FixedPopUpOption] {
        HeadMotionManager.HeadsetTriplePressAction.allCases.map {
            FixedPopUpOption(id: $0.rawValue, title: $0.label)
        }
    }

    private var triplePressSelection: Binding<String> {
        Binding(
            get: { motionManager.headsetTriplePressAction.rawValue },
            set: { newValue in
                guard let action = HeadMotionManager.HeadsetTriplePressAction(rawValue: newValue) else { return }
                motionManager.headsetTriplePressAction = action
            }
        )
    }

    private var lastEventText: String {
        guard !motionManager.lastHeadsetRemoteEventText.isEmpty else {
            return isChinese ? "尚未收到耳机按钮事件" : "No headset button event received yet"
        }

        if let date = motionManager.lastHeadsetRemoteEventAt {
            let formatter = DateFormatter()
            formatter.timeStyle = .medium
            return "\(motionManager.lastHeadsetRemoteEventText) · \(formatter.string(from: date))"
        }
        return motionManager.lastHeadsetRemoteEventText
    }

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "airpodspro")
                        .foregroundColor(.secondary)
                        .frame(width: 18)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(isChinese ? "耳机按钮映射" : "Headset Button Mapping")
                            .font(.headline)
                        Text(
                            isChinese
                                ? "耳机按钮本质上也是触发器，应该和键盘快捷键放在一起看。Aether 现在固定使用单按切换输入 / 控制模式，双按开始 / 停止头控，三按执行你选择的自定义动作。"
                                : "Headset buttons are triggers too. Aether now uses single press for Dictation / Control switching, double press for tracking, and triple press for a configurable action."
                        )
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    statusRow(
                        title: isChinese ? "媒体遥控状态" : "Media Remote Status",
                        value: motionManager.headsetRemoteStatusText.isEmpty
                            ? (isChinese ? "初始化中" : "Initializing")
                            : motionManager.headsetRemoteStatusText
                    )
                    statusRow(
                        title: isChinese ? "最近一次耳机事件" : "Last Headset Event",
                        value: lastEventText
                    )
                }
                .padding(12)
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.35))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                VStack(alignment: .leading, spacing: 8) {
                    row(
                        title: isChinese ? "单按 / 单捏" : "Single Press",
                        action: isChinese ? "切换输入 / 控制模式" : "Toggle Dictation / Control",
                        detail: isChinese
                            ? "所有语音触发方式下都生效。单按只切换模式，不会直接开始录音。"
                            : "Available in all activation modes. Single press switches mode without starting voice capture."
                    )
                    row(
                        title: isChinese ? "双按 / 双捏" : "Double Press",
                        action: isChinese ? "开始 / 停止头控" : "Toggle Tracking",
                        detail: isChinese
                            ? "如果系统把“下一首”事件交给 Aether，就会用它来开始或停止头控。"
                            : "If macOS routes the Next Track event to Aether, it starts or stops head tracking."
                    )
                    row(
                        title: isChinese ? "三按 / 三捏" : "Triple Press",
                        action: motionManager.headsetTriplePressAction.label,
                        detail: isChinese
                            ? "如果系统把“上一首”事件交给 Aether，就会执行下面选定的自定义动作。"
                            : "If macOS routes the Previous Track event to Aether, it runs the action you pick below."
                    )
                }

                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(isChinese ? "三按自定义动作" : "Triple Press Action")
                            .font(.subheadline.weight(.semibold))
                        Text(motionManager.headsetTriplePressAction.helperText)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer(minLength: 16)
                    FixedWidthPopUpMenu(
                        options: triplePressOptions,
                        selection: triplePressSelection
                    )
                }
                .padding(12)
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.6))
                .cornerRadius(10)
            }
        }
    }

    @ViewBuilder
    private func row(title: String, action: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(detail)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 12)

            Text(action)
                .font(.caption.weight(.semibold))
                .foregroundColor(.accentColor)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.accentColor.opacity(0.12))
                .clipShape(Capsule())
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.6))
        .cornerRadius(10)
    }

    @ViewBuilder
    private func statusRow(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundColor(.secondary)
            Text(value)
                .font(.caption)
                .foregroundColor(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct VoiceLexiconSection: Identifiable {
    let title: String
    let subtitle: String
    let presets: [VoiceCommandPreset]

    var id: String { title }
}

private extension VoiceCommandPreset {
    func editorTitle(locale: Locale = .current) -> String {
        let isChinese = locale.identifier.hasPrefix("zh")
        switch self {
        case .clickLeft:
            return isChinese ? "单击" : "Single Click"
        case .clickRight:
            return isChinese ? "右键点击" : "Right Click"
        case .doubleClick:
            return isChinese ? "双击" : "Double Click"
        case .mediaPlayPause:
            return isChinese ? "播放 / 暂停" : "Play / Pause"
        case .mediaPrevious:
            return isChinese ? "上一首" : "Previous Track"
        case .mediaNext:
            return isChinese ? "下一首" : "Next Track"
        case .showShortcutPanel:
            return isChinese ? "显示快捷键面板" : "Show Shortcuts Panel"
        case .hideShortcutPanel:
            return isChinese ? "关闭快捷键面板" : "Hide Shortcuts Panel"
        case .startPointer:
            return isChinese ? "开启头控" : "Enable Pointer Control"
        case .stopPointer:
            return isChinese ? "关闭头控" : "Disable Pointer Control"
        case .recenter:
            return isChinese ? "回中校准" : "Recenter"
        case .scrollUp:
            return isChinese ? "向上滚动" : "Scroll Up"
        case .scrollDown:
            return isChinese ? "向下滚动" : "Scroll Down"
        case .scrollTop:
            return isChinese ? "滚到顶部" : "Scroll To Top"
        case .scrollBottom:
            return isChinese ? "滚到底部" : "Scroll To Bottom"
        case .dragStart:
            return isChinese ? "开始拖拽" : "Start Drag"
        case .dragEnd:
            return isChinese ? "结束拖拽" : "End Drag"
        case .undo:
            return isChinese ? "撤销" : "Undo"
        case .paste:
            return isChinese ? "粘贴" : "Paste"
        case .lockConnection:
            return isChinese ? "锁定耳机连接" : "Lock Headset Connection"
        case .unlockConnection:
            return isChinese ? "解锁耳机连接" : "Unlock Headset Connection"
        }
    }

    func editorDescription(locale: Locale = .current) -> String {
        let isChinese = locale.identifier.hasPrefix("zh")
        switch self {
        case .clickLeft:
            return isChinese ? "在当前鼠标位置执行一次左键点击。" : "Performs a left click at the current pointer position."
        case .clickRight:
            return isChinese ? "在当前鼠标位置打开右键菜单。" : "Opens the context menu at the current pointer position."
        case .doubleClick:
            return isChinese ? "适合打开文件、确认或激活列表项。" : "Useful for opening files or activating items."
        case .mediaPlayPause:
            return isChinese ? "控制当前系统播放源的播放或暂停。" : "Plays or pauses the current system media source."
        case .mediaPrevious:
            return isChinese ? "切换到上一首或上一段媒体内容。" : "Skips to the previous track or chapter."
        case .mediaNext:
            return isChinese ? "切换到下一首或下一段媒体内容。" : "Skips to the next track or chapter."
        case .showShortcutPanel:
            return isChinese ? "展开当前 App 的快捷键总览浮层。" : "Shows the shortcut overlay for the frontmost app."
        case .hideShortcutPanel:
            return isChinese ? "关闭当前 App 的快捷键总览浮层。" : "Closes the shortcut overlay for the frontmost app."
        case .startPointer:
            return isChinese ? "开始用头部控制鼠标移动。" : "Starts moving the pointer with head motion."
        case .stopPointer:
            return isChinese ? "停止头部控制，只保留语音。" : "Stops head-driven pointer movement."
        case .recenter:
            return isChinese ? "把当前头部姿态设为新的中心位置。" : "Sets the current head pose as the new neutral center."
        case .scrollUp:
            return isChinese ? "页面向上滚动一段距离。" : "Scrolls the page upward."
        case .scrollDown:
            return isChinese ? "页面向下滚动一段距离。" : "Scrolls the page downward."
        case .scrollTop:
            return isChinese ? "快速回到页面顶部。" : "Jumps to the top of the page."
        case .scrollBottom:
            return isChinese ? "快速跳到页面底部。" : "Jumps to the bottom of the page."
        case .dragStart:
            return isChinese ? "按住鼠标左键，进入拖拽状态。" : "Presses and holds the left mouse button."
        case .dragEnd:
            return isChinese ? "释放拖拽中的鼠标左键。" : "Releases the left mouse button to drop."
        case .undo:
            return isChinese ? "发送系统撤销操作。" : "Triggers the standard Undo shortcut."
        case .paste:
            return isChinese ? "发送系统粘贴操作。" : "Triggers the standard Paste shortcut."
        case .lockConnection:
            return isChinese ? "锁定当前耳机连接，避免误切换。" : "Locks the active headset connection."
        case .unlockConnection:
            return isChinese ? "解除耳机连接锁定。" : "Releases the active headset connection lock."
        }
    }

    func editorExample(locale: Locale = .current) -> String {
        let isChinese = locale.identifier.hasPrefix("zh")
        switch self {
        case .clickLeft:
            return isChinese ? "例如：点击、确认" : "Example: click, confirm"
        case .clickRight:
            return isChinese ? "例如：右键、打开菜单" : "Example: right click, open menu"
        case .doubleClick:
            return isChinese ? "例如：双击、打开它" : "Example: double click, open it"
        case .mediaPlayPause:
            return isChinese ? "例如：播放、暂停、继续播放" : "Example: play, pause, resume"
        case .mediaPrevious:
            return isChinese ? "例如：上一首、回到上一段" : "Example: previous track"
        case .mediaNext:
            return isChinese ? "例如：下一首、跳到下一段" : "Example: next track"
        case .showShortcutPanel:
            return isChinese ? "例如：显示快捷键、打开面板" : "Example: show shortcuts, open panel"
        case .hideShortcutPanel:
            return isChinese ? "例如：关闭快捷键、收起面板" : "Example: hide shortcuts, close panel"
        case .startPointer:
            return isChinese ? "例如：开启头控、开始控制鼠标" : "Example: enable pointer, start cursor control"
        case .stopPointer:
            return isChinese ? "例如：关闭头控、停止控制鼠标" : "Example: stop pointer, disable cursor control"
        case .recenter:
            return isChinese ? "例如：回中、重新校准" : "Example: recenter, recalibrate"
        case .scrollUp:
            return isChinese ? "例如：往上滚、向上翻" : "Example: scroll up, go up"
        case .scrollDown:
            return isChinese ? "例如：往下滚、向下翻" : "Example: scroll down, go down"
        case .scrollTop:
            return isChinese ? "例如：回到顶部" : "Example: top of page"
        case .scrollBottom:
            return isChinese ? "例如：去到底部" : "Example: bottom of page"
        case .dragStart:
            return isChinese ? "例如：开始拖、按住不放" : "Example: start drag, hold down"
        case .dragEnd:
            return isChinese ? "例如：放下、结束拖拽" : "Example: drop, end drag"
        case .undo:
            return isChinese ? "例如：撤销上一步" : "Example: undo last step"
        case .paste:
            return isChinese ? "例如：粘贴内容" : "Example: paste here"
        case .lockConnection:
            return isChinese ? "例如：锁定耳机" : "Example: lock headset"
        case .unlockConnection:
            return isChinese ? "例如：解锁耳机" : "Example: unlock headset"
        }
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

private struct FrontmostAppCommandCard: View {
    let command: FrontmostAppCommand

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(command.title)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.primary)
                .lineLimit(2)

            Text(command.menuPath.joined(separator: " > "))
                .font(.caption2)
                .foregroundColor(.secondary)
                .lineLimit(1)

            Text(command.shortcut.displayString)
                .font(.caption.weight(.medium))
                .foregroundColor(.accentColor)
                .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.72))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.black.opacity(0.05), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct VoiceUsageInsightsCard: View {
    @EnvironmentObject var appState: AppState

    private var isChinese: Bool {
        Locale.current.identifier.hasPrefix("zh")
    }

    private var recentEvents: [AppState.VoiceUsageEvent] {
        Array(appState.voiceUsageHistory.prefix(30))
    }

    private var topApps: [AppState.VoiceUsageAppSummary] {
        Array(appState.voiceUsageAppSummaries.prefix(8))
    }

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 10) {
                    VStack(alignment: .leading, spacing: 4) {
                        Label(
                            isChinese ? "使用统计与历史" : "Usage Stats & History",
                            systemImage: "chart.bar.xaxis"
                        )
                        .font(.headline)
                        Text(
                            isChinese
                                ? "默认关闭。开启后仅在本机记录“在哪个 App 进行了语音输入/控制”，用于优化词库和命令配置。"
                                : "Off by default. When enabled, Aether stores local per-app dictation/control usage to help tune lexicon and commands."
                        )
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                    Toggle("", isOn: $appState.isVoiceUsageHistoryEnabled)
                        .labelsHidden()
                }

                if !appState.isVoiceUsageHistoryEnabled {
                    Text(
                        appState.voiceUsageHistory.isEmpty
                            ? (isChinese ? "记录已关闭，当前没有历史数据。" : "Tracking is off and there is no history yet.")
                            : (isChinese
                                ? "记录已关闭，已保留 \(appState.voiceUsageHistory.count) 条历史数据。"
                                : "Tracking is off. \(appState.voiceUsageHistory.count) history items are retained.")
                    )
                    .font(.caption)
                    .foregroundColor(.secondary)
                } else {
                    let summary = appState.voiceUsageSummary
                    HStack(spacing: 10) {
                        VoiceUsageSummaryBadge(
                            title: isChinese ? "总计" : "Total",
                            value: "\(summary.total)"
                        )
                        VoiceUsageSummaryBadge(
                            title: isChinese ? "语音输入" : "Dictation",
                            value: "\(summary.dictationCount)"
                        )
                        VoiceUsageSummaryBadge(
                            title: isChinese ? "控制命令" : "Control",
                            value: "\(summary.controlCount)"
                        )
                    }

                    if summary.total == 0 {
                        Text(isChinese ? "暂无记录。先试一次语音输入或语音控制。" : "No usage yet. Try dictation or a voice control action first.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(isChinese ? "按 App 统计" : "Per-App Summary")
                                .font(.subheadline.weight(.semibold))
                            VStack(spacing: 8) {
                                ForEach(topApps) { item in
                                    VoiceUsageAppSummaryRow(summary: item)
                                }
                            }
                        }

                        Divider()

                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text(isChinese ? "最近记录" : "Recent Activity")
                                    .font(.subheadline.weight(.semibold))
                                Spacer()
                                Button(isChinese ? "清空记录" : "Clear History") {
                                    appState.clearVoiceUsageHistory()
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }

                            VStack(spacing: 8) {
                                ForEach(recentEvents) { event in
                                    VoiceUsageEventRow(event: event)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

private struct VoiceUsageSummaryBadge: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            Text(value)
                .font(.headline)
                .foregroundColor(.primary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.6))
        .cornerRadius(10)
    }
}

private struct VoiceUsageAppSummaryRow: View {
    let summary: AppState.VoiceUsageAppSummary

    private var bundleTail: String {
        summary.bundleIdentifier
    }

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(summary.appName)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text(bundleTail)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Text("\(summary.dictationCount)/\(summary.controlCount)")
                .font(.caption.monospacedDigit())
                .foregroundColor(.secondary)
            Text("\(summary.total)")
                .font(.caption.weight(.semibold).monospacedDigit())
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.accentColor.opacity(0.12))
                .foregroundColor(.accentColor)
                .clipShape(Capsule())
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
        .cornerRadius(10)
    }
}

private struct VoiceUsageEventRow: View {
    let event: AppState.VoiceUsageEvent

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()

    private static let dateTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM-dd HH:mm"
        return formatter
    }()

    private var isChinese: Bool {
        Locale.current.identifier.hasPrefix("zh")
    }

    private var eventIcon: String {
        event.kind == .dictation ? "text.bubble" : "command"
    }

    private var timeText: String {
        if Calendar.current.isDateInToday(event.timestamp) {
            return Self.timeFormatter.string(from: event.timestamp)
        }
        return Self.dateTimeFormatter.string(from: event.timestamp)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: eventIcon)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(event.action)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                Spacer()
                Text(timeText)
                    .font(.caption2.monospacedDigit())
                    .foregroundColor(.secondary)
            }

            HStack(spacing: 8) {
                Text(event.appName)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                Text(event.bundleIdentifier)
                    .font(.caption2)
                    .foregroundColor(.secondary.opacity(0.85))
                    .lineLimit(1)
            }

            if let content = event.content, !content.isEmpty {
                Text(content)
                    .font(.caption)
                    .foregroundColor(.primary)
                    .lineLimit(2)
                    .padding(.top, 1)
            } else if event.kind == .dictation {
                Text(isChinese ? "（空文本）" : "(empty text)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.45))
        .cornerRadius(10)
    }
}

private struct VoiceLexiconEditorRow: View {
    let title: String
    let subtitle: String?
    let example: String?
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

            if let subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let example, !example.isEmpty {
                Text(example)
                    .font(.caption2)
                    .foregroundColor(.secondary)
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
                Text("每行一条：`原词=>目标词`；可选 `=>cmd` 仅控制模式生效，`=>dict` 仅输入模式生效。")
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

    private var isChinese: Bool {
        Locale.current.identifier.hasPrefix("zh")
    }

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

    private var autoStartTrackingBinding: Binding<Bool> {
        Binding(
            get: { headManager.autoStartTrackingOnHeadsetConnection },
            set: { headManager.autoStartTrackingOnHeadsetConnection = $0 }
        )
    }

    private var postureGuideBinding: Binding<Bool> {
        Binding(
            get: { headManager.showPostureGuideBeforeTracking },
            set: { headManager.showPostureGuideBeforeTracking = $0 }
        )
    }
    
    var body: some View {
        SettingsPage(
            title: String(localized: "settings.page.pointer.title"),
            subtitle: String(localized: "settings.page.pointer.subtitle")
        ) {
            VStack(spacing: 20) {
                GlassCard {
                    VStack(alignment: .leading, spacing: 14) {
                        ControlCard(
                            title: L10n.commandCenterMotionMatrix, // Reusing Motion Matrix title which is appropriate
                            subtitle: headManager.isTracking ? L10n.statusActive : L10n.statusPaused,
                            icon: "viewfinder",
                            color: .green,
                            isOn: trackingBinding
                        )

                        Divider()

                        Toggle(
                            isChinese ? "连接耳机后自动开启头控" : "Auto-start tracking when headset connects",
                            isOn: autoStartTrackingBinding
                        )
                        Toggle(
                            isChinese ? "自动开启前显示姿态引导" : "Show posture guide before auto-start",
                            isOn: postureGuideBinding
                        )
                        .disabled(!headManager.autoStartTrackingOnHeadsetConnection)
                    }
                }

                GlassCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Label(L10n.settingsCalibration, systemImage: "scope")
                            .font(.headline)

                        HStack {
                            Text(L10n.settingsCurrentStatus)
                            Spacer()
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

// MARK: - Shortcuts Placeholder
struct ShortcutsSettingsView: View {
    var body: some View {
        SettingsPage(
            title: String(localized: "settings.page.shortcuts.title"),
            subtitle: String(localized: "settings.page.shortcuts.subtitle")
        ) {
            GlassCard {
                HotkeySettingsSection()
            }

            HeadsetShortcutMappingCard()
        }
    }
}
