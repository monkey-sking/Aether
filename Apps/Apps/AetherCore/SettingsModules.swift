import SwiftUI
import AppKit

enum VoiceSettingsSection: Hashable {
    case basics
    case termCorrections
    case lexicon
    case appControls
    case insights

    var zhTitle: String { enTitle } // Deprecated

    var enTitle: String { title } // Deprecated

    var systemImage: String {
        switch self {
        case .basics: return "mic.fill"
        case .termCorrections: return "text.magnifyingglass"
        case .lexicon: return "text.badge.star"
        case .appControls: return "app.badge"
        case .insights: return "chart.bar.xaxis"
        }
    }

    var title: String {
        switch self {
        case .basics: return NSLocalizedString("settings.section.basics.title", comment: "")
        case .termCorrections: return NSLocalizedString("settings.section.term_corrections.title", comment: "")
        case .lexicon: return NSLocalizedString("settings.section.lexicon.title", comment: "")
        case .appControls: return NSLocalizedString("settings.section.app_controls.title", comment: "")
        case .insights: return NSLocalizedString("settings.section.insights.title", comment: "")
        }
    }

    func title(isChinese: Bool) -> String {
        title
    }

    func pageTitle(isChinese: Bool) -> String {
        switch self {
        case .basics:
            return NSLocalizedString("settings.section.basics.page_title", comment: "")
        case .termCorrections:
            return NSLocalizedString("settings.section.term_corrections.page_title", comment: "")
        case .lexicon:
            return NSLocalizedString("settings.section.lexicon.page_title", comment: "")
        case .appControls:
            return NSLocalizedString("settings.section.app_controls.page_title", comment: "")
        case .insights:
            return NSLocalizedString("settings.section.insights.page_title", comment: "")
        }
    }

    func pageSubtitle(isChinese: Bool) -> String {
        switch self {
        case .basics:
            return NSLocalizedString("settings.section.basics.subtitle", comment: "")
        case .termCorrections:
            return NSLocalizedString("settings.section.term_corrections.subtitle", comment: "")
        case .lexicon:
            return NSLocalizedString("settings.section.lexicon.subtitle", comment: "")
        case .appControls:
            return NSLocalizedString("settings.section.app_controls.subtitle", comment: "")
        case .insights:
            return NSLocalizedString("settings.section.insights.subtitle", comment: "")
        }
    }
}

// MARK: - Input Settings (Voice)
struct InputSettingsView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var frontmostAppCommandCatalog = FrontmostAppCommandCatalog.shared
    @State private var editingGroupID: String?
    @State private var editingCustomRuleID: String?
    @State private var commandLocaleID: String = ""
    @State private var lexiconTransferStatus: String?
    @State private var expandedLexiconCommandSectionIDs: Set<String> = []
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

    private var speechLanguageModeSelection: Binding<SpeechLanguageMode> {
        Binding(
            get: { appState.voiceService.speechLanguageMode },
            set: { appState.voiceService.speechLanguageMode = $0 }
        )
    }

    private var singleSpeechLanguageSelection: Binding<String> {
        Binding(
            get: {
                appState.voiceService.followsSystemLanguage
                    ? "system"
                    : appState.voiceService.primaryLocaleIdentifier
            },
            set: { newValue in
                if newValue == "system" {
                    appState.voiceService.followsSystemLanguage = true
                } else {
                    appState.voiceService.followsSystemLanguage = false
                    appState.voiceService.primaryLocaleIdentifier = newValue
                }
            }
        )
    }

    private var bilingualPrimarySelection: Binding<String> {
        Binding(
            get: { appState.voiceService.primaryLocaleIdentifier },
            set: {
                appState.voiceService.followsSystemLanguage = false
                appState.voiceService.primaryLocaleIdentifier = $0
            }
        )
    }

    private var bilingualSecondarySelection: Binding<String> {
        Binding(
            get: { appState.voiceService.secondaryLocaleIdentifier },
            set: { appState.voiceService.secondaryLocaleIdentifier = $0 }
        )
    }

    private var effectiveSpeechLocaleID: String {
        normalizedCommandLocaleIdentifier(appState.voiceService.effectiveLocaleIdentifier)
    }

    private var effectiveSpeechLocaleDisplayName: String {
        localeTitle(for: effectiveSpeechLocaleID)
    }

    private var isFollowingSystemSpeechLocale: Bool {
        appState.voiceService.speechLanguageMode == .single && appState.voiceService.followsSystemLanguage
    }

    private var speechLanguageOptions: [VoiceLanguageOption] {
        [
            VoiceLanguageOption(id: "system", title: String(localized: "language.system"))
        ] + supportedVoiceLocaleIDs.map { VoiceLanguageOption(id: $0, title: localeTitle(for: $0)) }
    }

    private func popUpOptions(from options: [VoiceLanguageOption]) -> [FixedPopUpOption] {
        options.map { FixedPopUpOption(id: $0.id, title: $0.title) }
    }

    private var bilingualLanguageOptions: [VoiceLanguageOption] {
        supportedVoiceLocaleIDs.map { VoiceLanguageOption(id: $0, title: localeTitle(for: $0)) }
    }

    private var bilingualSecondaryOptions: [VoiceLanguageOption] {
        bilingualLanguageOptions.filter { $0.id != appState.voiceService.primaryLocaleIdentifier }
    }

    private var lexiconLanguageOptions: [VoiceLanguageOption] {
        supportedVoiceLocaleIDs.map { VoiceLanguageOption(id: $0, title: localeTitle(for: $0)) }
    }

    private var resolvedCommandLocaleID: String {
        let preferred = commandLocaleID.isEmpty
            ? appState.voiceService.effectiveLocaleIdentifier
            : commandLocaleID
        return normalizedCommandLocaleIdentifier(preferred)
    }

    private var commandLocaleDisplayName: String {
        Locale.current.localizedString(forIdentifier: resolvedCommandLocaleID) ?? resolvedCommandLocaleID
    }

    private var mergedFrontmostSnapshot: FrontmostAppCommandSnapshot? {
        appState.mergedFrontmostAppCommandSnapshot(frontmostAppCommandCatalog.snapshot)
    }

    private var isChinese: Bool {
        appState.isChineseUI
    }

    private var visibleFrontmostCommands: [FrontmostAppCommand] {
        let commands = mergedFrontmostSnapshot?.commands ?? []
        let recommended = commands.filter { $0.aliases.count > 2 }
        return Array((recommended.isEmpty ? commands : recommended).prefix(12))
    }

    private var commandAliasSections: [VoiceLexiconSection] {
        [
            VoiceLexiconSection(
                title: NSLocalizedString("lexicon.section.core_controls.title", comment: ""),
                subtitle: NSLocalizedString("lexicon.section.core_controls.subtitle", comment: ""),
                systemImage: "cursorarrow.click.2",
                tint: .blue,
                presets: [.clickLeft, .clickRight, .doubleClick, .scrollUp, .scrollDown, .scrollTop, .scrollBottom, .dragStart, .dragEnd]
            ),
            VoiceLexiconSection(
                title: isChinese ? "模式与面板" : "Modes & Panels",
                subtitle: isChinese
                    ? "输入/控制模式切换、语言切换、快捷键面板与清空输入。"
                    : "Input/control switching, language switching, shortcut panels, and clear input.",
                systemImage: "switch.2",
                tint: .accentColor,
                presets: [.toggleInputControlMode, .toggleTracking, .toggleLanguage, .toggleShortcutPanel, .showShortcutPanel, .hideShortcutPanel, .clearInput]
            ),
            VoiceLexiconSection(
                title: NSLocalizedString("lexicon.section.pointer_control.title", comment: ""),
                subtitle: NSLocalizedString("lexicon.section.pointer_control.subtitle", comment: ""),
                systemImage: "scope",
                tint: .orange,
                presets: [.startPointer, .stopPointer, .recenter]
            ),
            VoiceLexiconSection(
                title: isChinese ? "媒体控制" : "Media Controls",
                subtitle: isChinese
                    ? "低频媒体桥接动作默认折叠，需要时再展开配置。"
                    : "Lower-frequency media bridge actions stay collapsed until needed.",
                systemImage: "play.square",
                tint: .pink,
                presets: [.mediaPlayPause, .mediaPrevious, .mediaNext]
            )
        ]
    }

    private func lexiconSectionExpandedBinding(for section: VoiceLexiconSection) -> Binding<Bool> {
        Binding(
            get: { expandedLexiconCommandSectionIDs.contains(section.id) },
            set: { isExpanded in
                if isExpanded {
                    expandedLexiconCommandSectionIDs.insert(section.id)
                } else {
                    expandedLexiconCommandSectionIDs.remove(section.id)
                }
            }
        )
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

                        VStack(alignment: .leading, spacing: 10) {
                            HStack(alignment: .top) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Label(L10n.settingsSpeechLanguage, systemImage: "globe")
                                        .font(.body)
                                    Text(NSLocalizedString("settings.voice.language_hint", comment: ""))
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                if appState.voiceService.speechLanguageMode == .single, isFollowingSystemSpeechLocale {
                                    LanguageStatusTag(
                                        title: String(format: NSLocalizedString("settings.voice.system_lang_status_fmt", comment: ""),
                                                      effectiveSpeechLocaleDisplayName),
                                        tint: .blue
                                    )
                                } else if appState.voiceService.speechLanguageMode == .bilingual {
                                    LanguageStatusTag(
                                        title: String(format: NSLocalizedString("settings.voice.bilingual_lang_status_fmt", comment: ""),
                                                      localeTitle(for: appState.voiceService.primaryLocaleIdentifier),
                                                      localeTitle(for: appState.voiceService.secondaryLocaleIdentifier)),
                                        tint: .blue
                                    )
                                }
                            }

                            HStack(spacing: 10) {
                                languageModeButton(.single, title: NSLocalizedString("settings.voice.mode_single", comment: ""))
                                languageModeButton(.bilingual, title: NSLocalizedString("settings.voice.mode_bilingual", comment: ""))
                            }

                            if appState.voiceService.speechLanguageMode == .single {
                                FixedWidthPopUpMenu(
                                    options: popUpOptions(from: speechLanguageOptions),
                                    selection: singleSpeechLanguageSelection
                                )
                            } else {
                                VStack(alignment: .leading, spacing: 12) {
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text(NSLocalizedString("settings.voice.primary_lang", comment: ""))
                                            .font(.caption.weight(.semibold))
                                            .foregroundColor(.secondary)
                                        FixedWidthPopUpMenu(
                                            options: popUpOptions(from: bilingualLanguageOptions),
                                            selection: bilingualPrimarySelection
                                        )
                                    }

                                    VStack(alignment: .leading, spacing: 6) {
                                        Text(NSLocalizedString("settings.voice.secondary_lang", comment: ""))
                                            .font(.caption.weight(.semibold))
                                            .foregroundColor(.secondary)
                                        FixedWidthPopUpMenu(
                                            options: popUpOptions(from: bilingualSecondaryOptions),
                                            selection: bilingualSecondarySelection
                                        )
                                    }

                                        Text(NSLocalizedString("settings.voice.bilingual_hint", comment: ""))
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                    }
                }
                }
                
                if section == .basics {
                    GlassCard {
                    VStack(alignment: .leading, spacing: 20) {
                        ControlCard(
                            title: LocalizedStringKey("main.voice_activation.title"),
                            subtitle: appState.isVoiceEnabled ? L10n.statusActive : L10n.statusPaused,
                            icon: "waveform.badge.mic",
                            color: .blue,
                            isOn: $appState.isVoiceEnabled
                        )

                        Text(L10n.settingsVoiceEnabledHint)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)

                        Divider()

                        VStack(alignment: .leading, spacing: 10) {
                            Toggle(isOn: $appState.autoEnableVoiceOnHeadset) {
                                Text(L10n.settingsVoiceAutoEnableHeadset)
                                    .font(.body)
                            }
                            Text(L10n.settingsVoiceAutoEnableHeadsetHint)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        
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
                        .disabled(!appState.isVoiceEnabled)
                        .opacity(appState.isVoiceEnabled ? 1.0 : 0.5)
                        
                        if appState.isVoiceEnabled && appState.voiceActivationMode == .handsFree {
                            Text(L10n.activationAlwaysWarning)
                                .font(.caption)
                                .foregroundColor(.orange)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        if appState.isVoiceEnabled && appState.voiceActivationMode != .pushToTalk &&
                            (!appState.microphoneAuthorized || !appState.speechAuthorized) {
                            VStack(alignment: .leading, spacing: 8) {
                                Label(NSLocalizedString("settings.voice.permission_required", comment: ""), systemImage: "exclamationmark.triangle.fill")
                                    .font(.caption.weight(.semibold))
                                    .foregroundColor(.orange)

                                if !appState.microphoneAuthorized {
                                    Button(NSLocalizedString("settings.voice.open_mic_permission", comment: "")) {
                                        appState.requestMicrophoneGuided()
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                                }

                                if !appState.speechAuthorized {
                                    Button(NSLocalizedString("settings.voice.open_speech_permission", comment: "")) {
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
                                 Text(String(format: NSLocalizedString("settings.voice.ptt_status_hint_fmt", comment: ""),
                                               appState.voicePTTBinding.displayString))
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
                        .disabled(!appState.isVoiceEnabled)
                        .opacity(appState.isVoiceEnabled ? 1.0 : 0.5)

                    }
                }
                }
                
                if section == .termCorrections {
                    GlassCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Label(L10n.settingsAutoPunctuation, systemImage: "textformat.abc.dottedunderline")
                            .font(.headline)

                        Text(isChinese ? "自动标点已固定开启。" : "Auto punctuation stays on.")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        HStack(spacing: 12) {
                            ZStack {
                                Circle()
                                    .fill(Color.green.opacity(0.16))
                                    .frame(width: 40, height: 40)

                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundColor(.green)
                            }

                            VStack(alignment: .leading, spacing: 2) {
                                Text(L10n.settingsAutoPunctuation)
                                    .font(.subheadline.weight(.medium))
                                Text(isChinese ? "当前版本始终保持开启。" : "Always on in the current build.")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }

                            Spacer()

                            Text(L10n.statusActive)
                                .font(.caption.weight(.semibold))
                                .foregroundColor(.green)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(Color.green.opacity(0.12))
                                .clipShape(Capsule())
                        }
                        .padding(12)
                        .background(Color(nsColor: .controlBackgroundColor))
                        .cornerRadius(12)
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

                        HStack(alignment: .center, spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(L10n.voiceLexiconEditingLanguage)
                                    .font(.caption.weight(.semibold))
                                    .foregroundColor(.secondary)
                                Text(NSLocalizedString("lexicon.editing_language.hint", comment: ""))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            FixedWidthPopUpMenu(
                                options: popUpOptions(from: lexiconLanguageOptions),
                                selection: Binding(
                                    get: { resolvedCommandLocaleID },
                                    set: { commandLocaleID = $0 }
                                )
                            )
                            Button(L10n.voiceLexiconResetLanguage) {
                                appState.resetCommandOverrides(for: resolvedCommandLocaleID)
                                appState.resetVoiceLanguageTermsOverrides(for: resolvedCommandLocaleID)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }

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

                            Button(LocalizedStringKey("voice_lexicon.import_clipboard")) {
                                do {
                                    let ok = try appState.importVoiceLexiconFromPasteboard()
                                    if ok {
                                        lexiconTransferStatus = String(localized: "voice_lexicon.import_clipboard_done")
                                    } else {
                                        lexiconTransferStatus = String(localized: "voice_lexicon.import_clipboard_empty")
                                    }
                                } catch {
                                    lexiconTransferStatus = "\(String(localized: "voice_lexicon.import_clipboard_failed")): \(error.localizedDescription)"
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

                        VStack(alignment: .leading, spacing: 10) {
                            Label(
                                NSLocalizedString("lexicon.basic_terms.title", comment: ""),
                                systemImage: "waveform.badge.mic"
                            )
                            .font(.headline)

                            Text(NSLocalizedString("lexicon.basic_terms.subtitle", comment: ""))
                                .font(.caption)
                                .foregroundColor(.secondary)

                            VoiceLexiconEditorRow(
                                title: String(localized: "voice_lexicon.wake_words"),
                                subtitle: NSLocalizedString("lexicon.wake_words.subtitle", comment: ""),
                                text: Binding(
                                    get: { appState.wakeWordOverrideText(for: resolvedCommandLocaleID) },
                                    set: { appState.updateWakeWordOverrideText($0, for: resolvedCommandLocaleID) }
                                ),
                                actionTitle: String(localized: "voice_lexicon.clear"),
                                actionEnabled: !appState.wakeWordOverrideText(for: resolvedCommandLocaleID)
                                    .trimmingCharacters(in: .whitespacesAndNewlines)
                                    .isEmpty,
                                requiresConfirmation: true,
                                onReset: {
                                    appState.updateWakeWordOverrideText("", for: resolvedCommandLocaleID)
                                }
                            )

                            Divider()

                            VoiceLexiconEditorRow(
                                title: String(localized: "voice_lexicon.command_prefixes"),
                                subtitle: NSLocalizedString("lexicon.command_prefixes.subtitle", comment: ""),
                                text: Binding(
                                    get: { appState.commandPrefixOverrideText(for: resolvedCommandLocaleID) },
                                    set: { appState.updateCommandPrefixOverrideText($0, for: resolvedCommandLocaleID) }
                                ),
                                actionTitle: String(localized: "hotkey.reset_single"),
                                actionEnabled: appState.commandPrefixOverrideText(for: resolvedCommandLocaleID)
                                    != appState.defaultCommandPrefixText(for: resolvedCommandLocaleID),
                                requiresConfirmation: false,
                                onReset: {
                                    appState.restoreDefaultCommandPrefixes(for: resolvedCommandLocaleID)
                                }
                            )

                            Divider()

                            VoiceLexiconEditorRow(
                                title: String(localized: "voice_lexicon.dictation_prefixes"),
                                subtitle: NSLocalizedString("lexicon.dictation_prefixes.subtitle", comment: ""),
                                text: Binding(
                                    get: { appState.dictationPrefixOverrideText(for: resolvedCommandLocaleID) },
                                    set: { appState.updateDictationPrefixOverrideText($0, for: resolvedCommandLocaleID) }
                                ),
                                actionTitle: String(localized: "hotkey.reset_single"),
                                actionEnabled: appState.dictationPrefixOverrideText(for: resolvedCommandLocaleID)
                                    != appState.defaultDictationPrefixText(for: resolvedCommandLocaleID),
                                requiresConfirmation: false,
                                onReset: {
                                    appState.restoreDefaultDictationPrefixes(for: resolvedCommandLocaleID)
                                }
                            )
                        }

                        Divider()

                        VStack(alignment: .leading, spacing: 12) {
                            Label(
                                NSLocalizedString("lexicon.command_aliases.title", comment: ""),
                                systemImage: "command"
                            )
                            .font(.headline)

                            Text(
                                NSLocalizedString("lexicon.command_aliases.subtitle", comment: "")
                            )
                            .font(.caption)
                            .foregroundColor(.secondary)

                            ForEach(commandAliasSections) { aliasSection in
                                DisclosureGroup(
                                    isExpanded: lexiconSectionExpandedBinding(for: aliasSection),
                                    content: {
                                        VStack(spacing: 8) {
                                            ForEach(Array(aliasSection.presets.enumerated()), id: \.element.id) { index, preset in
                                                VoiceLexiconEditorRow(
                                                    title: preset.editorTitle(),
                                                    subtitle: preset.editorDescription(),
                                                    text: Binding(
                                                        get: { appState.commandOverrideText(for: preset, localeIdentifier: resolvedCommandLocaleID) },
                                                        set: { appState.updateCommandOverrideText($0, for: preset, localeIdentifier: resolvedCommandLocaleID) }
                                                    ),
                                                    actionTitle: String(localized: "voice_lexicon.clear"),
                                                    actionEnabled: !appState.commandOverrideText(for: preset, localeIdentifier: resolvedCommandLocaleID)
                                                        .trimmingCharacters(in: .whitespacesAndNewlines)
                                                        .isEmpty,
                                                    requiresConfirmation: true,
                                                    onReset: {
                                                        appState.updateCommandOverrideText("", for: preset, localeIdentifier: resolvedCommandLocaleID)
                                                    }
                                                )
                                                if index < aliasSection.presets.count - 1 {
                                                    Divider()
                                                }
                                            }
                                        }
                                        .padding(.top, 6)
                                    },
                                    label: {
                                        HStack(alignment: .top, spacing: 12) {
                                            ZStack {
                                                Circle()
                                                    .fill(aliasSection.tint.opacity(0.14))
                                                    .frame(width: 34, height: 34)

                                                Image(systemName: aliasSection.systemImage)
                                                    .font(.system(size: 14, weight: .semibold))
                                                    .foregroundColor(aliasSection.tint)
                                            }

                                            VStack(alignment: .leading, spacing: 4) {
                                                HStack(spacing: 8) {
                                                    Text(aliasSection.title)
                                                        .font(.subheadline.weight(.semibold))
                                                    Text("\(aliasSection.presets.count)")
                                                        .font(.caption2.weight(.bold))
                                                        .foregroundColor(aliasSection.tint)
                                                        .padding(.horizontal, 6)
                                                        .padding(.vertical, 2)
                                                        .background(aliasSection.tint.opacity(0.14))
                                                        .clipShape(Capsule())
                                                }

                                                Text(aliasSection.subtitle)
                                                    .font(.caption)
                                                    .foregroundColor(.secondary)
                                                    .fixedSize(horizontal: false, vertical: true)
                                            }

                                            Spacer(minLength: 12)
                                        }
                                    }
                                )
                                .padding(14)
                                .background(Color(nsColor: .controlBackgroundColor).opacity(0.42))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .stroke(aliasSection.tint.opacity(0.08), lineWidth: 1)
                                )
                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
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
                                    NSLocalizedString("panels.shortcuts.current_app", comment: ""),
                                    systemImage: "app.badge"
                                )
                                .font(.headline)

                                Text(NSLocalizedString("panels.shortcuts.current_app.description", comment: ""))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            if let snapshot = mergedFrontmostSnapshot {
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

                        if !appState.accessibilityTrusted && (mergedFrontmostSnapshot?.commands.isEmpty ?? true) {
                            Text(AppLocalization.isChinese
                                 ? "需要先开启辅助功能权限，才能读取当前应用菜单和快捷键。"
                                 : "Accessibility permission is required to read the current app's menu shortcuts.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        } else if let snapshot = mergedFrontmostSnapshot, !snapshot.commands.isEmpty {
                            Text(
                                AppLocalization.isChinese
                                    ? "已准备 \(snapshot.commands.count) 条快捷键。除了读取到的菜单项，下面还会并入你手动补充的自定义 App 规则。"
                                    : "Prepared \(snapshot.commands.count) shortcuts. The preview below includes menu shortcuts plus your custom app rules."
                            )
                            .font(.caption)
                            .foregroundColor(.secondary)

                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 10)], spacing: 10) {
                                ForEach(visibleFrontmostCommands) { command in
                                    FrontmostAppCommandCard(command: command)
                                }
                            }
                        } else {
                             Text(NSLocalizedString("panels.shortcuts.no_readable", comment: ""))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        CustomAppShortcutRulesCard(
                            rules: $appState.customAppShortcutRules,
                            onCopy: {
                                do {
                                    try appState.copyCustomAppShortcutRulesToPasteboard()
                                    HUDManager.shared.showTemporary(
                                        message: String(localized: "custom_app_rules.copy_done"),
                                        icon: "doc.on.doc"
                                    )
                                } catch {
                                    HUDManager.shared.showTemporary(
                                        message: String(localized: "custom_app_rules.copy_failed"),
                                        icon: "xmark.circle.fill"
                                    )
                                }
                            },
                            onPaste: {
                                do {
                                    let imported = try appState.importCustomAppShortcutRulesFromPasteboard()
                                    HUDManager.shared.showTemporary(
                                        message: imported
                                            ? String(localized: "custom_app_rules.paste_done")
                                            : String(localized: "custom_app_rules.paste_empty"),
                                        icon: imported ? "tray.and.arrow.down.fill" : "doc.text"
                                    )
                                } catch {
                                    HUDManager.shared.showTemporary(
                                        message: String(localized: "custom_app_rules.paste_failed"),
                                        icon: "xmark.circle.fill"
                                    )
                                }
                            },
                            onAdd: {
                                let bundleID = mergedFrontmostSnapshot?.bundleIdentifier
                                    ?? NSWorkspace.shared.frontmostApplication?.bundleIdentifier
                                appState.addCustomAppShortcutRule(prefilling: bundleID)
                                editingCustomRuleID = appState.customAppShortcutRules.first?.id
                            },
                            onEdit: { ruleID in
                                editingCustomRuleID = ruleID
                            },
                            onDelete: { ruleID in
                                appState.removeCustomAppShortcutRule(id: ruleID)
                            }
                        )
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
                let preferred = appState.voiceService.effectiveLocaleIdentifier
                commandLocaleID = normalizedCommandLocaleIdentifier(preferred)
            }
            _ = frontmostAppCommandCatalog.refresh(force: true)
        }
        .sheet(isPresented: Binding(
            get: { editingGroupID != nil || editingCustomRuleID != nil },
            set: {
                if !$0 {
                    editingGroupID = nil
                    editingCustomRuleID = nil
                }
            }
        )) {
            if let id = editingGroupID,
               let idx = appState.speechTermGroups.firstIndex(where: { $0.id == id }) {
                SpeechTermGroupEditorSheet(
                    group: $appState.speechTermGroups[idx],
                    enabledAll: appState.speechTermCorrectionEnabled
                )
            } else if let id = editingCustomRuleID,
                      let idx = appState.customAppShortcutRules.firstIndex(where: { $0.id == id }) {
                CustomAppShortcutRuleEditorSheet(
                    rule: $appState.customAppShortcutRules[idx]
                )
            } else {
                EmptyView()
            }
        }
    }
    
    @ViewBuilder
    private func languageModeButton(_ mode: SpeechLanguageMode, title: String) -> some View {
        Button {
            speechLanguageModeSelection.wrappedValue = mode
            if mode == .single {
                commandLocaleID = normalizedCommandLocaleIdentifier(appState.voiceService.effectiveLocaleIdentifier)
            }
        } label: {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(appState.voiceService.speechLanguageMode == mode ? .accentColor : .primary)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    appState.voiceService.speechLanguageMode == mode
                        ? Color.accentColor.opacity(0.14)
                        : Color(nsColor: .controlBackgroundColor).opacity(0.72)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(
                            appState.voiceService.speechLanguageMode == mode
                                ? Color.accentColor.opacity(0.35)
                                : Color.black.opacity(0.05),
                            lineWidth: 1
                        )
                )
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
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

private struct HeadGestureShortcutMappingCard: View {
    @ObservedObject private var motionManager = HeadMotionManager.shared

    private var gestureActionOptions: [FixedPopUpOption] {
        HeadMotionManager.HeadGestureAction.allCases.map {
            FixedPopUpOption(id: $0.rawValue, title: $0.label)
        }
    }

    private func selection(for kind: HeadMotionManager.HeadGestureKind) -> Binding<String> {
        Binding(
            get: { action(for: kind).rawValue },
            set: { newValue in
                guard let action = HeadMotionManager.HeadGestureAction(rawValue: newValue) else { return }
                setAction(action, for: kind)
            }
        )
    }

    private func action(for kind: HeadMotionManager.HeadGestureKind) -> HeadMotionManager.HeadGestureAction {
        switch kind {
        case .nod:
            return motionManager.headGestureNodAction
        case .shake:
            return motionManager.headGestureShakeAction
        }
    }

    private func setAction(_ action: HeadMotionManager.HeadGestureAction, for kind: HeadMotionManager.HeadGestureKind) {
        switch kind {
        case .nod:
            motionManager.headGestureNodAction = action
        case .shake:
            motionManager.headGestureShakeAction = action
        }
    }

    private var lastEventText: String {
        guard !motionManager.lastHeadGestureEventText.isEmpty else {
            return String(localized: "head_gesture.status.no_event")
        }

        if let date = motionManager.lastHeadGestureEventAt {
            let formatter = DateFormatter()
            formatter.timeStyle = .medium
            return "\(motionManager.lastHeadGestureEventText) · \(formatter.string(from: date))"
        }
        return motionManager.lastHeadGestureEventText
    }

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 10) {
                    TransparencyModeIcon(size: 18, color: .secondary)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(String(localized: "head_gesture.mapping.title"))
                            .font(.headline)
                        Text(String(localized: "head_gesture.mapping.subtitle"))
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    statusRow(
                        title: String(localized: "head_gesture.status.last_event"),
                        value: lastEventText
                    )
                }
                .padding(12)
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.35))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                VStack(alignment: .leading, spacing: 8) {
                    actionRow(
                        kind: .nod,
                        detail: String(localized: "head_gesture.detail.nod")
                    )
                    actionRow(
                        kind: .shake,
                        detail: String(localized: "head_gesture.detail.shake")
                    )
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func actionRow(kind: HeadMotionManager.HeadGestureKind, detail: String) -> some View {
        let currentAction = action(for: kind)
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(kind.label)
                    .font(.subheadline.weight(.semibold))
                Text(detail)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(currentAction.helperText)
                    .font(.caption)
                    .foregroundColor(.secondary.opacity(0.9))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 12)

            FixedWidthPopUpMenu(
                options: gestureActionOptions,
                selection: selection(for: kind)
            )
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
    let systemImage: String
    let tint: Color
    let presets: [VoiceCommandPreset]

    var id: String { title }
}

private struct VoiceLexiconSectionChip: View {
    let title: String
    let count: Int
    let tint: Color

    var body: some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
            Text("\(count)")
                .font(.caption2.weight(.bold))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(tint.opacity(0.18))
                .clipShape(Capsule())
        }
        .foregroundColor(tint)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.62))
        .clipShape(Capsule())
    }
}

private struct VoiceLexiconSectionCard<Content: View>: View {
    let section: VoiceLexiconSection
    let content: Content

    init(section: VoiceLexiconSection, @ViewBuilder content: () -> Content) {
        self.section = section
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    Circle()
                        .fill(section.tint.opacity(0.14))
                        .frame(width: 34, height: 34)

                    Image(systemName: section.systemImage)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(section.tint)
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(section.title)
                            .font(.subheadline.weight(.semibold))
                        Text("\(section.presets.count)")
                            .font(.caption2.weight(.bold))
                            .foregroundColor(section.tint)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(section.tint.opacity(0.14))
                            .clipShape(Capsule())
                    }

                    Text(section.subtitle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 12)
            }

            content
        }
        .padding(14)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.42))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(section.tint.opacity(0.14), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
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
        case .toggleInputControlMode:
            return isChinese ? "切换输入/控制模式" : "Toggle Input/Control Mode"
        case .toggleTracking:
            return isChinese ? "切换头控" : "Toggle Pointer Control"
        case .toggleLanguage:
            return isChinese ? "切换语言" : "Toggle Language"
        case .toggleConnectionLock:
            return isChinese ? "切换连接锁定" : "Toggle Connection Lock"
        case .toggleShortcutPanel:
            return isChinese ? "切换快捷键面板" : "Toggle Shortcuts Panel"
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
        case .clearInput:
            return isChinese ? "清空输入" : "Clear Input"
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
        case .toggleInputControlMode:
            return isChinese ? "在输入模式和控制模式之间切换，适合耳机单按或语音快速切换。" : "Switches between dictation and control mode."
        case .toggleTracking:
            return isChinese ? "开启中的头控会停止，停止中的头控会直接开启。" : "Toggles pointer tracking on or off."
        case .toggleLanguage:
            return isChinese ? "在已启用的语音语言之间循环切换。" : "Cycles through the enabled speech languages."
        case .toggleConnectionLock:
            return isChinese ? "切换耳机连接锁定状态，避免在多设备之间误切换。" : "Toggles the headset connection lock."
        case .toggleShortcutPanel:
            return isChinese ? "展开中的快捷键面板会收起，收起中的面板会展开。" : "Toggles the shortcut overlay for the current app."
        case .mediaPlayPause:
            return isChinese ? "控制当前系统播放源的播放或暂停。" : "Plays or pauses the current system media source."
        case .mediaPrevious:
            return isChinese ? "切换到上一首或上一段媒体内容。" : "Skips to the previous track or chapter."
        case .mediaNext:
            return isChinese ? "切换到下一首或下一段媒体内容。" : "Skips to the next track or chapter."
        case .showShortcutPanel:
            return isChinese ? "展开当前 App 的快捷键面板。" : "Shows the shortcut overlay for the frontmost app."
        case .hideShortcutPanel:
            return isChinese ? "关闭当前 App 的快捷键面板。" : "Closes the shortcut overlay for the frontmost app."
        case .startPointer:
            return isChinese ? "开启头控，开始控制指针移动。" : "Starts moving the pointer with head motion."
        case .stopPointer:
            return isChinese ? "停止头控，只保留语音。" : "Stops head-driven pointer movement."
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
        case .clearInput:
            return isChinese ? "先全选再删除当前输入框内容。" : "Selects all content in the current field, then deletes it."
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
        case .toggleInputControlMode:
            return isChinese ? "例如：切换输入模式、切换控制模式" : "Example: toggle input mode"
        case .toggleTracking:
            return isChinese ? "例如：切换头控、切换指针控制" : "Example: toggle pointer control"
        case .toggleLanguage:
            return isChinese ? "例如：切换语言、切换语音语言" : "Example: toggle language"
        case .toggleConnectionLock:
            return isChinese ? "例如：切换连接锁定、切换耳机锁定" : "Example: toggle connection lock"
        case .toggleShortcutPanel:
            return isChinese ? "例如：切换快捷键面板、切换命令面板" : "Example: toggle shortcuts panel"
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
            return isChinese ? "例如：开启头控、开始控制指针" : "Example: enable pointer, start cursor control"
        case .stopPointer:
            return isChinese ? "例如：关闭头控、停止控制指针" : "Example: stop pointer, disable cursor control"
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
        case .clearInput:
            return isChinese ? "例如：清空输入、清空文本" : "Example: clear input, clear field"
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

private struct CustomAppShortcutRulesCard: View {
    @Binding var rules: [CustomAppShortcutRule]
    let onCopy: () -> Void
    let onPaste: () -> Void
    let onAdd: () -> Void
    let onEdit: (String) -> Void
    let onDelete: (String) -> Void

    private var isChinese: Bool {
        AppLocalization.isChinese
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Label(
                        isChinese ? "自定义 App 规则" : "Custom App Rules",
                        systemImage: "slider.horizontal.3"
                    )
                    .font(.headline)
                    Text(
                        isChinese
                            ? "给某个 App 手动补一条语音命令和对应快捷键。它会同时出现在语音路由、设置预览和快捷键面板里。"
                            : "Manually add voice-triggered shortcuts for a specific app. They appear in routing, settings preview, and the shortcut panel."
                    )
                    .font(.caption)
                    .foregroundColor(.secondary)
                }
                Spacer()
                HStack(spacing: 8) {
                    Button(isChinese ? "复制规则" : "Copy Rules", action: onCopy)
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    Button(isChinese ? "粘贴规则" : "Paste Rules", action: onPaste)
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    Button(isChinese ? "新增规则" : "Add Rule", action: onAdd)
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                }
            }

            if rules.isEmpty {
                Text(isChinese ? "还没有自定义规则。比如你可以给聊天应用补一条“发送 -> ⏎ / ⌘↩”规则。" : "No custom rules yet. For example, add a \"Send -> Return / Cmd+Return\" rule for your chat app.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                VStack(spacing: 8) {
                    ForEach(rules) { rule in
                        CustomAppShortcutRuleRow(rule: rule, onEdit: {
                            onEdit(rule.id)
                        }, onDelete: {
                            onDelete(rule.id)
                        })
                    }
                }
            }
        }
    }
}

private struct CustomAppShortcutRuleRow: View {
    let rule: CustomAppShortcutRule
    let onEdit: () -> Void
    let onDelete: () -> Void

    private var aliasPreview: String {
        let aliases = rule.effectiveAliases
        return aliases.prefix(3).joined(separator: " / ")
    }

    var body: some View {
        HStack(spacing: 10) {
            SpeechAppIcon(bundleID: rule.bundleIdentifier)
                .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(rule.title.isEmpty ? "Untitled" : rule.title)
                        .font(.subheadline.weight(.semibold))
                    if !rule.isEnabled {
                        Text("OFF")
                            .font(.caption2.weight(.bold))
                            .foregroundColor(.secondary)
                    }
                }
                Text(SpeechAppMetaStore.name(for: rule.bundleIdentifier))
                    .font(.caption)
                    .foregroundColor(.secondary)
                if !aliasPreview.isEmpty {
                    Text(aliasPreview)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            Text(rule.shortcut.displayString)
                .font(.caption.monospaced())
                .foregroundColor(.accentColor)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(Color.accentColor.opacity(0.12))
                .clipShape(Capsule())

            Button(action: onEdit) {
                Image(systemName: "pencil")
            }
            .buttonStyle(.borderless)

            Button(action: onDelete) {
                Image(systemName: "trash")
                    .foregroundColor(.red)
            }
            .buttonStyle(.borderless)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
        .cornerRadius(10)
    }
}

private struct CustomAppShortcutRuleEditorSheet: View {
    @Binding var rule: CustomAppShortcutRule
    @Environment(\.dismiss) private var dismiss

    private var isChinese: Bool {
        AppLocalization.isChinese
    }

    private var aliasesBinding: Binding<String> {
        Binding(
            get: { rule.aliases.joined(separator: ", ") },
            set: { raw in
                rule.aliases = raw
                    .components(separatedBy: CharacterSet(charactersIn: ",\n"))
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
            }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(NSLocalizedString("custom_app_rule_editor.title", comment: ""))
                    .font(.headline)
                Spacer()
                Button(NSLocalizedString("custom_app_rule_editor.done", comment: "")) { dismiss() }
            }

            Toggle(NSLocalizedString("custom_app_rule_editor.enable_rule", comment: ""), isOn: $rule.isEnabled)

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(NSLocalizedString("custom_app_rule_editor.target_app", comment: ""))
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    SpeechAppPickerMenu(
                        existingBundleIds: Set(rule.bundleIdentifier.isEmpty ? [] : [rule.bundleIdentifier.lowercased()]),
                        onAdd: { bundleID in
                            rule.bundleIdentifier = bundleID
                        }
                    )
                }
                HStack(spacing: 10) {
                    SpeechAppIcon(bundleID: rule.bundleIdentifier)
                        .frame(width: 28, height: 28)
                    TextField(
                        NSLocalizedString("custom_app_rule_editor.bundle_id_placeholder", comment: ""),
                        text: $rule.bundleIdentifier
                    )
                    .textFieldStyle(.roundedBorder)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(NSLocalizedString("custom_app_rule_editor.action_title", comment: ""))
                    .font(.subheadline.weight(.semibold))
                TextField(NSLocalizedString("custom_app_rule_editor.action_title_placeholder", comment: ""), text: $rule.title)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(NSLocalizedString("custom_app_rule_editor.voice_aliases", comment: ""))
                    .font(.subheadline.weight(.semibold))
                Text(NSLocalizedString("custom_app_rule_editor.voice_aliases_hint", comment: ""))
                    .font(.caption)
                    .foregroundColor(.secondary)
                TextField(
                    NSLocalizedString("custom_app_rule_editor.voice_aliases_placeholder", comment: ""),
                    text: aliasesBinding
                )
                .textFieldStyle(.roundedBorder)
                .font(.system(.caption, design: .monospaced))
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(NSLocalizedString("custom_app_rule_editor.shortcut", comment: ""))
                    .font(.subheadline.weight(.semibold))
                Text(NSLocalizedString("custom_app_rule_editor.shortcut_hint", comment: ""))
                    .font(.caption)
                    .foregroundColor(.secondary)
                KeyRecorderView(binding: $rule.shortcut, allowBareKeys: true, onChange: { newBinding in
                    rule.shortcut = newBinding
                })
            }
        }
        .padding(16)
        .frame(width: 560)
    }
}

private struct VoiceUsageInsightsCard: View {
    @EnvironmentObject var appState: AppState

    private var isChinese: Bool {
        AppLocalization.isChinese
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
                        Text(LocalizedStringKey("insights.usage_description"))
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                    Toggle("", isOn: $appState.isVoiceUsageHistoryEnabled)
                        .labelsHidden()
                }

                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(isChinese ? "保留上限" : "Retention Limit")
                            .font(.subheadline.weight(.semibold))
                        Text(
                            isChinese
                                ? "默认保留最近 1000 条，可按 100 条为单位调整。"
                                : "Defaults to the latest 1000 entries and can be adjusted in steps of 100."
                        )
                        .font(.caption)
                        .foregroundColor(.secondary)
                    }
                    Spacer()
                    Stepper(
                        value: $appState.voiceUsageHistoryLimit,
                        in: 100...5000,
                        step: 100
                    ) {
                        Text("\(appState.voiceUsageHistoryLimit)")
                            .font(.subheadline.monospacedDigit())
                            .frame(minWidth: 48, alignment: .trailing)
                    }
                    .frame(width: 150)
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
                            title: isChinese ? "输入" : "Dictation",
                            value: "\(summary.dictationCount)"
                        )
                        VoiceUsageSummaryBadge(
                            title: isChinese ? "失败" : "Failed",
                            value: "\(summary.failureCount)"
                        )
                        VoiceUsageSummaryBadge(
                            title: isChinese ? "未识别" : "Unrecognized",
                            value: "\(summary.unrecognizedCount)"
                        )
                        VoiceUsageSummaryBadge(
                            title: isChinese ? "控制命令" : "Control",
                            value: "\(summary.controlCount)"
                        )
                    }

                    if summary.total == 0 {
                        Text(isChinese ? "暂无记录。先试一次输入或语音控制。" : "No usage yet. Try dictation or a voice control action first.")
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
                                Button(LocalizedStringKey("insights.copy_diagnostic_history")) {
                                    do {
                                        try appState.copyVoiceUsageHistoryForDiagnostics()
                                        HUDManager.shared.showTemporary(
                                            message: String(localized: "insights.copy_diagnostic_history_done"),
                                            icon: "doc.on.doc"
                                        )
                                    } catch {
                                        HUDManager.shared.showTemporary(
                                            message: String(localized: "insights.copy_diagnostic_history_failed"),
                                            icon: "xmark.circle.fill"
                                        )
                                    }
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                                Button(LocalizedStringKey("insights.export_ai_prompt")) {
                                    do {
                                        try appState.exportAetherAIConfigPrompt()
                                        HUDManager.shared.showTemporary(
                                            message: String(localized: "insights.export_ai_prompt_done"),
                                            icon: "doc.on.doc"
                                        )
                                    } catch {
                                        HUDManager.shared.showTemporary(
                                            message: String(localized: "insights.export_ai_prompt_failed"),
                                            icon: "xmark.circle.fill"
                                        )
                                    }
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
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
            Text("\(summary.dictationCount)/\(summary.failureCount)/\(summary.controlCount)")
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
    @EnvironmentObject var appState: AppState
    let event: AppState.VoiceUsageEvent
    @State private var isHovering: Bool = false

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
        AppLocalization.isChinese
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
        .overlay(alignment: .topTrailing) {
            Button {
                do {
                    try appState.copyVoiceUsageEvent(event)
                    HUDManager.shared.showTemporary(
                        message: String(localized: "insights.copy_event_done"),
                        icon: "doc.on.doc"
                    )
                } catch {
                    HUDManager.shared.showTemporary(
                        message: String(localized: "insights.copy_event_failed"),
                        icon: "xmark.circle.fill"
                    )
                }
            } label: {
                Image(systemName: "doc.on.doc")
                    .font(.caption2)
                    .padding(6)
            }
            .buttonStyle(.borderless)
            .controlSize(.mini)
            .help(String(localized: "insights.copy_event"))
            .opacity(isHovering ? 1 : 0)
            .allowsHitTesting(isHovering)
            .padding(.top, 2)
            .padding(.trailing, 2)
        }
        .onHover { hovering in
            isHovering = hovering
        }
    }
}

private struct VoiceLexiconEditorRow: View {
    let title: String
    let subtitle: String?
    @Binding var text: String
    let actionTitle: String
    let actionEnabled: Bool
    let requiresConfirmation: Bool
    let onReset: () -> Void
    @State private var isHovering: Bool = false
    @State private var showConfirm: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top) {
                Text(title)
                    .font(.body.weight(.medium))
                Spacer()
            }

            if let subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            ZStack(alignment: .trailing) {
                TextField(
                    String(localized: "voice_lexicon.leave_empty"),
                    text: $text
                )
                .textFieldStyle(.roundedBorder)
                .padding(.trailing, 60)

                Button(actionTitle) {
                    if requiresConfirmation {
                        showConfirm = true
                    } else {
                        onReset()
                    }
                }
                .buttonStyle(.borderless)
                .controlSize(.mini)
                .disabled(!actionEnabled)
                .opacity(isHovering && actionEnabled ? 1 : 0)
                .allowsHitTesting(isHovering && actionEnabled)
            }
        }
        .padding(10)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
        .cornerRadius(10)
        .onHover { hovering in
            isHovering = hovering
        }
        .confirmationDialog(
            String(localized: "lexicon.clear_confirm_title"),
            isPresented: $showConfirm,
            titleVisibility: .visible
        ) {
            Button(String(localized: "lexicon.clear_confirm_action"), role: .destructive) {
                onReset()
            }
            Button(String(localized: "lexicon.clear_confirm_cancel"), role: .cancel) {}
        } message: {
            Text(String(localized: "lexicon.clear_confirm_message"))
        }
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
            Button(LocalizedStringKey("settings.term_correction.edit")) { onEdit() }
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
                Text(LocalizedStringKey("settings.term_correction.edit_group"))
                    .font(.headline)
                Spacer()
                Button(LocalizedStringKey("settings.term_correction.done")) { dismiss() }
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
                        Text(LocalizedStringKey("settings.term_correction.effective_apps"))
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
                Text(LocalizedStringKey("settings.term_correction.entry_rules"))
                    .font(.subheadline.weight(.semibold))
                Text(LocalizedStringKey("settings.term_correction.entry_rules_hint"))
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
                Text(LocalizedStringKey("settings.term_correction.no_apps_to_add"))
            } else {
                Text(LocalizedStringKey("settings.term_correction.running_apps"))
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

            Button(LocalizedStringKey("settings.term_correction.select_app_manually")) {
                chooseApplication()
            }
        } label: {
            Label(LocalizedStringKey("settings.term_correction.add_app"), systemImage: "plus")
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
        AppLocalization.isChinese
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
                            icon: "cursorarrow.and.square.on.square.dashed",
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

                        Divider()

                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(isChinese ? "回中" : "Recenter")
                                    .font(.subheadline.weight(.semibold))
                                Text(
                                    isChinese
                                        ? "把当前头部朝向重新设为中心，适合姿态变化后快速校正。"
                                        : "Use the current head position as the new center after your posture changes."
                                )
                                .font(.caption)
                                .foregroundColor(.secondary)
                            }
                            Spacer(minLength: 16)
                            Button(action: { headManager.recenter() }) {
                                Text(isChinese ? "重新取中心" : "Recenter Now")
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 8)
                            }
                            .buttonStyle(.plain)
                            .background(Color(nsColor: .controlBackgroundColor).opacity(headManager.isTracking ? 0.72 : 0.42))
                            .cornerRadius(10)
                            .disabled(!headManager.isTracking)
                        }
                    }
                }
            }
        }
    }
}

struct HeadGestureSettingsView: View {
    @ObservedObject private var headManager = HeadMotionManager.shared

    private var headGestureToggleBinding: Binding<Bool> {
        Binding(
            get: { headManager.headGestureToggleEnabled },
            set: { headManager.headGestureToggleEnabled = $0 }
        )
    }

    var body: some View {
        SettingsPage(
            title: String(localized: "settings.page.head_gestures.title"),
            subtitle: String(localized: "settings.page.head_gestures.subtitle")
        ) {
            VStack(spacing: 20) {
                GlassCard {
                    HStack(alignment: .top, spacing: 12) {
                        TransparencyModeIcon(size: 22, color: .secondary)

                        VStack(alignment: .leading, spacing: 6) {
                            Text(String(localized: "head_gesture.toggle.enable"))
                                .font(.headline)
                            Text(String(localized: "head_gesture.toggle.detail"))
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        Spacer(minLength: 12)

                        Toggle("", isOn: headGestureToggleBinding)
                            .labelsHidden()
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                HeadGestureShortcutMappingCard()
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
        }
    }
}
