import SwiftUI
import AppKit

enum VoiceSettingsSection: Hashable {
    case basics
    case termCorrections
    case lexicon
    case appControls
    case insights
    case wakeInsights

    var zhTitle: String { enTitle } // Deprecated

    var enTitle: String { title } // Deprecated

    var systemImage: String {
        switch self {
        case .basics: return "mic.fill"
        case .termCorrections: return "text.magnifyingglass"
        case .lexicon: return "text.badge.star"
        case .appControls: return "app.badge"
        case .insights: return "chart.bar.xaxis"
        case .wakeInsights: return "waveform.badge.mic"
        }
    }

    var title: String {
        switch self {
        case .basics: return NSLocalizedString("settings.section.basics.title", comment: "")
        case .termCorrections: return NSLocalizedString("settings.section.term_corrections.title", comment: "")
        case .lexicon: return NSLocalizedString("settings.section.lexicon.title", comment: "")
        case .appControls: return NSLocalizedString("settings.section.app_controls.title", comment: "")
        case .insights: return NSLocalizedString("settings.section.insights.title", comment: "")
        case .wakeInsights: return AppLocalization.isChinese ? "唤醒与激活" : "Wake & Activation"
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
        case .wakeInsights:
            return AppLocalization.isChinese ? "唤醒与激活" : "Wake & Activation"
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
        case .wakeInsights:
            return AppLocalization.isChinese
                ? "查看唤醒词命中、空唤醒和后续转化。"
                : "Review wake hits, empty wakes, and follow-up conversion."
        }
    }
}

// MARK: - Input Settings (Voice)
struct InputSettingsView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var frontmostAppCommandCatalog = FrontmostAppCommandCatalog.shared
    @State private var editingGroupID: String?
    @State private var editingCustomRuleID: String?
    @State private var newlyInsertedCustomRuleID: String?
    @State private var commandLocaleID: String = ""
    @State private var lexiconTransferStatus: String?
    @State private var basicLexiconSectionExpanded = true
    @State private var expandedLexiconCommandSectionIDs: Set<String> = []
    @State private var showingResetLexiconLanguageConfirm = false
    let section: VoiceSettingsSection

    private let supportedVoiceLocaleIDs = [
        "zh-CN", "en-US", "ja-JP", "ko-KR", "fr-FR", "de-DE", "es-ES"
    ]

    private var microphoneOptions: [FixedPopUpOption] {
        appState.availableInputDevices.map { device in
            FixedPopUpOption(id: String(device.id), title: device.name)
        }
    }

    private var developerTerminologyBoostBinding: Binding<Bool> {
        Binding(
            get: { appState.isDeveloperSpeechProfileEnabled },
            set: { appState.isDeveloperSpeechProfileEnabled = $0 }
        )
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

    private var lexiconResetConfirmationMessage: String {
        String(
            format: NSLocalizedString("voice_lexicon.reset_language_confirm", comment: ""),
            localeTitle(for: resolvedCommandLocaleID)
        )
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
                    ? "输入/控制模式切换、语言切换与快捷键面板。"
                    : "Input/control switching, language switching, and shortcut panels.",
                systemImage: "switch.2",
                tint: .accentColor,
                presets: [.toggleInputControlMode, .toggleTracking, .toggleLanguage, .toggleShortcutPanel, .showShortcutPanel, .hideShortcutPanel]
            ),
            VoiceLexiconSection(
                title: NSLocalizedString("lexicon.section.pointer_control.title", comment: ""),
                subtitle: NSLocalizedString("lexicon.section.pointer_control.subtitle", comment: ""),
                systemImage: "scope",
                tint: .orange,
                presets: [.startPointer, .stopPointer, .recenter]
            ),
            VoiceLexiconSection(
                title: isChinese ? "文本编辑" : "Text Editing",
                subtitle: isChinese
                    ? "清空、删除、光标移动与选择扩展都可以在这里自定义。"
                    : "Customize clear, delete, cursor movement, and selection expansion here.",
                systemImage: "character.cursor.ibeam",
                tint: .green,
                presets: [.clearInput, .deleteBackward, .moveCursorLeft, .moveCursorRight, .selectLeft, .selectRight, .rewriteFullText]
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

    private var basicLexiconSection: VoiceLexiconSection {
        VoiceLexiconSection(
            title: NSLocalizedString("lexicon.basic_terms.title", comment: ""),
            subtitle: NSLocalizedString("lexicon.basic_terms.subtitle", comment: ""),
            systemImage: "waveform.badge.mic",
            tint: .teal,
            itemCount: 3
        )
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

                        VStack(alignment: .leading, spacing: 10) {
                            Toggle(isOn: Binding(
                                get: { appState.voiceService.enhancedPlaybackLeakSuppressionEnabled },
                                set: { appState.voiceService.enhancedPlaybackLeakSuppressionEnabled = $0 }
                            )) {
                                Text(String(localized: "settings.voice.playback_leak_suppression"))
                                    .font(.body)
                            }
                            Text(String(localized: "settings.voice.playback_leak_suppression_hint"))
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
                                    Button(
                                        appState.microphoneAuthorizationStatus == .denied || appState.microphoneAuthorizationStatus == .restricted
                                            ? NSLocalizedString("permissions.fix_microphone", comment: "")
                                            : NSLocalizedString("settings.voice.open_mic_permission", comment: "")
                                    ) {
                                        if appState.microphoneAuthorizationStatus == .denied || appState.microphoneAuthorizationStatus == .restricted {
                                            appState.repairMicrophoneGuided()
                                        } else {
                                            appState.requestMicrophoneGuided()
                                        }
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                                }

                                if !appState.speechAuthorized {
                                    Button(
                                        appState.speechAuthorizationStatus == .denied || appState.speechAuthorizationStatus == .restricted
                                            ? NSLocalizedString("permissions.fix_speech", comment: "")
                                            : NSLocalizedString("settings.voice.open_speech_permission", comment: "")
                                    ) {
                                        if appState.speechAuthorizationStatus == .denied || appState.speechAuthorizationStatus == .restricted {
                                            appState.repairSpeechGuided()
                                        } else {
                                            appState.requestSpeechGuided()
                                        }
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
                            HStack(alignment: .top, spacing: 10) {
                                Text(String(localized: "settings.term_correction.developer_boost.title"))
                                    .font(.headline)
                                Spacer()
                                Toggle(
                                    String(localized: "settings.term_correction.developer_boost.toggle_label"),
                                    isOn: developerTerminologyBoostBinding
                                )
                                .toggleStyle(.switch)
                                .controlSize(.small)
                            }
                            Text(String(localized: "settings.term_correction.developer_boost.subtitle"))
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                            Text(String(localized: "settings.term_correction.developer_boost.detail"))
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        .padding(12)
                        .background(Color(nsColor: .controlBackgroundColor))
                        .cornerRadius(12)
                    }
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
                    GlassCard {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(alignment: .top, spacing: 10) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(String(localized: "settings.term_correction.title"))
                                        .font(.headline)
                                    Text(String(localized: "settings.term_correction.description"))
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }

                                Spacer()

                                Toggle("", isOn: $appState.speechTermCorrectionEnabled)
                                    .labelsHidden()
                                    .toggleStyle(.switch)
                                    .controlSize(.small)
                            }

                            if appState.speechTermCorrectionEnabled {
                                Text(String(localized: "settings.term_correction.rule_format"))
                                    .font(.caption)
                                    .foregroundColor(.secondary)

                                VStack(spacing: 8) {
                                    ForEach(appState.speechTermGroups.indices, id: \.self) { index in
                                        SpeechTermGroupCard(
                                            group: $appState.speechTermGroups[index],
                                            enabledAll: $appState.speechTermCorrectionEnabled,
                                            onEdit: {
                                                editingGroupID = appState.speechTermGroups[index].id
                                            },
                                            onDelete: {
                                                appState.removeSpeechTermGroup(id: appState.speechTermGroups[index].id)
                                            }
                                        )
                                    }
                                }

                                Button(String(localized: "settings.term_correction.add_group")) {
                                    appState.addSpeechTermGroup()
                                    editingGroupID = appState.speechTermGroups.last?.id
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }
                        }
                    }
                }

                if section == .lexicon {
                    LLMRewriteSettingsCard()
                    GlassCard {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack(alignment: .top, spacing: 12) {
                            VStack(alignment: .leading, spacing: 6) {
                                Label(L10n.voiceLexiconTitle, systemImage: "list.bullet.clipboard")
                                    .font(.headline)

                                Text(String(localized: "voice_lexicon.description"))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }

                            Spacer(minLength: 12)

                            HStack(spacing: 8) {
                                Button(L10n.voiceLexiconResetLanguage) {
                                    showingResetLexiconLanguageConfirm = true
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                                FixedWidthPopUpMenu(
                                    options: popUpOptions(from: lexiconLanguageOptions),
                                    selection: Binding(
                                        get: { resolvedCommandLocaleID },
                                        set: { commandLocaleID = $0 }
                                    )
                                )
                            }
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

                        VoiceLexiconSectionCard(
                            section: basicLexiconSection,
                            isExpanded: $basicLexiconSectionExpanded
                        ) {
                            VStack(spacing: 8) {
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
                                actionTitle: String(localized: "voice_lexicon.clear"),
                                actionEnabled: !appState.commandPrefixOverrideText(for: resolvedCommandLocaleID)
                                    .trimmingCharacters(in: .whitespacesAndNewlines)
                                    .isEmpty,
                                requiresConfirmation: true,
                                onReset: {
                                    appState.updateCommandPrefixOverrideText("", for: resolvedCommandLocaleID)
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
                                actionTitle: String(localized: "voice_lexicon.clear"),
                                actionEnabled: !appState.dictationPrefixOverrideText(for: resolvedCommandLocaleID)
                                    .trimmingCharacters(in: .whitespacesAndNewlines)
                                    .isEmpty,
                                requiresConfirmation: true,
                                onReset: {
                                    appState.updateDictationPrefixOverrideText("", for: resolvedCommandLocaleID)
                                }
                            )
                        }
                        }

                        Divider()

                        ForEach(commandAliasSections) { aliasSection in
                            VoiceLexiconSectionCard(
                                section: aliasSection,
                                isExpanded: lexiconSectionExpandedBinding(for: aliasSection)
                            ) {
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
                            }
                        }

                    }
                    .alert(
                        String(localized: "voice_lexicon.reset_language_confirm_title"),
                        isPresented: $showingResetLexiconLanguageConfirm
                    ) {
                        Button(String(localized: "voice_lexicon.reset_language"), role: .destructive) {
                            appState.resetCommandOverrides(for: resolvedCommandLocaleID)
                            appState.resetVoiceLanguageTermsOverrides(for: resolvedCommandLocaleID)
                        }
                        Button(String(localized: "lexicon.clear_confirm_cancel"), role: .cancel) {}
                    } message: {
                        Text(lexiconResetConfirmationMessage)
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

                            if let snapshot = mergedFrontmostSnapshot {
                                LanguageStatusTag(title: snapshot.appName, tint: .green)
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
                                        ? "已准备 \(snapshot.commands.count) 条快捷键。下面仅展示来自当前应用的菜单项。"
                                        : "Prepared \(snapshot.commands.count) shortcuts. The preview below shows menu items from the current app."
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
                        }
                    }

                    GlassCard {
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
                            onAddCurrent: {
                                let bundleID = mergedFrontmostSnapshot?.bundleIdentifier
                                    ?? NSWorkspace.shared.frontmostApplication?.bundleIdentifier
                                appState.addCustomAppShortcutRule(prefilling: bundleID)
                                newlyInsertedCustomRuleID = appState.customAppShortcutRules.first?.id
                                editingCustomRuleID = appState.customAppShortcutRules.first?.id
                            },
                            onAddGlobal: {
                                appState.addGlobalCustomAppShortcutRule()
                                newlyInsertedCustomRuleID = appState.customAppShortcutRules.first?.id
                                editingCustomRuleID = appState.customAppShortcutRules.first?.id
                            },
                            onEdit: { ruleID in
                                newlyInsertedCustomRuleID = nil
                                editingCustomRuleID = ruleID
                            },
                            onDelete: { ruleID in
                                appState.removeCustomAppShortcutRule(id: ruleID)
                            }
                        )
                    }
                }

                if section == .insights {
                    VoiceUsageInsightsCard()
                }

                if section == .wakeInsights {
                    WakeActivationInsightsCard()
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
                    newlyInsertedCustomRuleID = nil
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
                    rule: appState.customAppShortcutRules[idx],
                    onSave: { updatedRule in
                        if let saveIndex = appState.customAppShortcutRules.firstIndex(where: { $0.id == id }) {
                            appState.customAppShortcutRules[saveIndex] = updatedRule
                        }
                        newlyInsertedCustomRuleID = nil
                        editingCustomRuleID = nil
                    },
                    onCancel: {
                        if newlyInsertedCustomRuleID == id {
                            appState.removeCustomAppShortcutRule(id: id)
                        }
                        newlyInsertedCustomRuleID = nil
                        editingCustomRuleID = nil
                    }
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

private struct LLMRewriteSettingsCard: View {
    @EnvironmentObject private var appState: AppState
    @State private var revealsAPIKey = false
    @State private var showsExpertSettings = false
    @FocusState private var focusedField: Field?

    private enum Field: Hashable {
        case apiKey
        case model
        case endpoint
        case domain
        case glossary
        case extraInstructions
    }

    private var isChinese: Bool {
        appState.isChineseUI
    }

    private var usesAppleOnDevice: Bool {
        appState.llmServiceSource == .appleOnDevice
    }

    private var statusTitle: String {
        if usesAppleOnDevice {
            return appState.appleOnDeviceLLMAvailability.statusTitle(isChinese: isChinese)
        }

        switch appState.llmConfigurationState {
        case .ready:
            return isChinese ? "已就绪" : "Ready"
        case .missingAPIKey:
            return isChinese ? "缺少 Key" : "Missing Key"
        case .missingModel:
            return isChinese ? "缺少模型" : "Missing Model"
        case .invalidEndpoint:
            return isChinese ? "地址无效" : "Bad Endpoint"
        case .appleOnDeviceUnavailable:
            return isChinese ? "本机不可用" : "Unavailable"
        }
    }

    private var statusTint: Color {
        if usesAppleOnDevice {
            return appState.appleOnDeviceLLMAvailability == .available ? .green : .orange
        }

        switch appState.llmConfigurationState {
        case .ready:
            return .green
        case .missingAPIKey, .missingModel, .invalidEndpoint:
            return .orange
        case .appleOnDeviceUnavailable:
            return .orange
        }
    }

    private var statusDescription: String {
        if usesAppleOnDevice {
            return appState.appleOnDeviceLLMAvailability.detail(
                isChinese: isChinese,
                localeName: appState.activeSpeechLocaleDisplayName
            )
        }

        switch appState.llmConfigurationState {
        case .ready:
            return isChinese
                ? "全文优化与听写增强已可用，前后文本会记录到 Insights。"
                : "Rewrite and dictation enhancement are ready, with before/after history in Insights."
        case .missingAPIKey:
            return isChinese
                ? "请填写 API Key，密钥会写入 Keychain。"
                : "Add an API key. It is stored in Keychain."
        case .missingModel:
            return isChinese
                ? "请填写模型名，例如 gpt-4.1。"
                : "Add a model name such as gpt-4.1."
        case .invalidEndpoint:
            return isChinese
                ? "Endpoint 需要是合法 URL，填基础地址即可。"
                : "Endpoint must be a valid URL. A base URL is enough."
        case .appleOnDeviceUnavailable:
            return appState.appleOnDeviceLLMAvailability.detail(
                isChinese: isChinese,
                localeName: appState.activeSpeechLocaleDisplayName
            )
        }
    }

    private var enhancementDescription: String {
        if usesAppleOnDevice {
            if appState.isLLMEnhancementEnabled {
                return isChinese
                    ? "会优先用 Apple 本地模型做听写增强和全文优化，不需要联网。"
                    : "Uses the Apple on-device model for dictation enhancement and full-text rewrite without network access."
            }
            return isChinese
                ? "关闭后，不会使用 Apple 本地模型做文本改写优化。"
                : "When off, the Apple on-device model will not be used for rewrite enhancement."
        }

        if appState.isLLMEnhancementEnabled {
            return isChinese
                ? "听写增强和全文优化都会走这里的配置。"
                : "Used by dictation enhancement and full-text rewrite."
        }
        return isChinese
            ? "关闭后，全文纠错优化不会执行。"
            : "When off, full-text rewrite will not run."
    }

    private var feedbackColor: Color {
        switch appState.llmConfigurationFeedbackKind {
        case .neutral:
            return .secondary
        case .success:
            return .green
        case .warning:
            return .orange
        case .error:
            return .red
        }
    }

    private var modelMenuTitle: String {
        let current = appState.llmModelText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !current.isEmpty {
            return current
        }
        return isChinese ? "选择模型" : "Choose Model"
    }

    private var fieldLabelWidth: CGFloat {
        isChinese ? 52 : 68
    }

    private var expertSectionTitle: String {
        isChinese ? "个性化整理" : "Personalize Rewrite"
    }

    private var expertSectionHint: String {
        isChinese
            ? "不用写专业提示词。留空也能用；一般只要填常用词，或者写一句“去口头禅、顺一点”就够了。"
            : "You do not need a formal prompt here. Leave it blank, or just add common terms and a simple preference."
    }

    private var expertToggleTitle: String {
        isChinese ? "启用个性化整理" : "Enable personalized rewrite"
    }

    @ViewBuilder
    private func clearButton(for field: Field, text: Binding<String>) -> some View {
        if focusedField == field && !text.wrappedValue.isEmpty {
            Button {
                text.wrappedValue = ""
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.borderless)
        }
    }

    @ViewBuilder
    private func inputShell(
        focused: Bool,
        trailingPadding: CGFloat = 10,
        @ViewBuilder content: () -> some View
    ) -> some View {
        HStack(spacing: 8) {
            content()
        }
        .padding(.leading, 9)
        .padding(.trailing, trailingPadding)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(nsColor: .textBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(
                    focused
                        ? Color.accentColor.opacity(0.35)
                        : Color.primary.opacity(0.08),
                    lineWidth: 1
                )
        )
    }

    private var serviceSourcePicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(isChinese ? "服务来源" : "Provider")
                .font(.caption.weight(.semibold))
                .foregroundColor(.secondary)

            Picker("", selection: $appState.llmServiceSource) {
                Text(isChinese ? "Apple 本地" : "Apple On-Device")
                    .tag(LLMServiceSource.appleOnDevice)
                Text(isChinese ? "OpenAI 兼容" : "OpenAI-Compatible")
                    .tag(LLMServiceSource.openAICompatible)
            }
            .pickerStyle(.segmented)

            Text(
                usesAppleOnDevice
                    ? (isChinese
                        ? "更适合低延迟和隐私优先场景。"
                        : "Best for lower latency and privacy-first rewrite.")
                    : (isChinese
                        ? "适合效果优先，使用兼容 OpenAI 的远端服务。"
                        : "Best for quality-first setups using an OpenAI-compatible remote service.")
            )
            .font(.caption2)
            .foregroundColor(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var actionButtons: some View {
        HStack(spacing: 8) {
            Button(usesAppleOnDevice ? (isChinese ? "检查本机" : "Check Local Model") : (isChinese ? "测试服务" : "Test Connection")) {
                Task { await appState.testLLMProviderConfiguration() }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .disabled(appState.isLLMConnectionTestRunning)

            if !usesAppleOnDevice {
                Button(isChinese ? "获取模型" : "Fetch Models") {
                    Task { await appState.refreshLLMAvailableModels() }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(appState.isLLMModelRefreshRunning)
            }

            if appState.isLLMConnectionTestRunning || appState.isLLMModelRefreshRunning {
                ProgressView()
                    .controlSize(.small)
            }
        }
    }

    private var appleOnDeviceInfoPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(
                isChinese
                    ? "Apple 本地模式不需要 API Key、模型名或服务地址。可用时会直接调用系统模型。"
                    : "Apple on-device mode does not require an API key, model name, or endpoint. It uses the system model directly when available."
            )
            .font(.caption)
            .foregroundColor(.secondary)
            .fixedSize(horizontal: false, vertical: true)

            Text(
                isChinese
                    ? "当前语音语言：\(appState.activeSpeechLocaleDisplayName)"
                    : "Current speech language: \(appState.activeSpeechLocaleDisplayName)"
            )
            .font(.caption2)
            .foregroundColor(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.55))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var apiKeyRow: some View {
        HStack(alignment: .center, spacing: 10) {
            Text(isChinese ? "API Key" : "API Key")
                .font(.caption.weight(.semibold))
                .foregroundColor(.secondary)
                .frame(width: fieldLabelWidth, alignment: .leading)

            inputShell(focused: focusedField == .apiKey) {
                Group {
                    if revealsAPIKey {
                        TextField("sk-...", text: $appState.llmAPIKey)
                            .focused($focusedField, equals: .apiKey)
                    } else {
                        SecureField("sk-...", text: $appState.llmAPIKey)
                            .focused($focusedField, equals: .apiKey)
                    }
                }
                .textFieldStyle(.plain)
                .privacySensitive()

                Spacer(minLength: 0)

                clearButton(for: .apiKey, text: $appState.llmAPIKey)

                Button {
                    revealsAPIKey.toggle()
                } label: {
                    Image(systemName: revealsAPIKey ? "eye.slash" : "eye")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.borderless)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var modelField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(isChinese ? "模型" : "Model")
                .font(.caption.weight(.semibold))
                .foregroundColor(.secondary)

            inputShell(focused: focusedField == .model, trailingPadding: 8) {
                TextField(
                    isChinese ? "如 gpt-4.1" : "e.g. gpt-4.1",
                    text: $appState.llmModelText
                )
                .focused($focusedField, equals: .model)
                .textFieldStyle(.plain)

                Spacer(minLength: 0)
                clearButton(for: .model, text: $appState.llmModelText)

                if !appState.llmAvailableModels.isEmpty {
                    Menu {
                        ForEach(appState.llmAvailableModels, id: \.self) { model in
                            Button(model) {
                                appState.llmModelText = model
                            }
                        }
                    } label: {
                        Image(systemName: "chevron.up.chevron.down")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.borderless)
                }
            }

            if !appState.llmAvailableModels.isEmpty {
                Text(
                    isChinese
                        ? "已加载 \(appState.llmAvailableModels.count) 个模型。"
                        : "Loaded \(appState.llmAvailableModels.count) models."
                )
                .font(.caption2)
                .foregroundColor(.secondary)
                .lineLimit(1)
            }
        }
        .frame(minWidth: 220, idealWidth: 260, maxWidth: 320, alignment: .leading)
    }

    private var endpointField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(isChinese ? "服务地址" : "Endpoint")
                .font(.caption.weight(.semibold))
                .foregroundColor(.secondary)

            inputShell(focused: focusedField == .endpoint, trailingPadding: 8) {
                TextField(
                    "https://api.example.com/v1",
                    text: $appState.llmEndpointText
                )
                .focused($focusedField, equals: .endpoint)
                .textFieldStyle(.plain)

                Spacer(minLength: 0)
                clearButton(for: .endpoint, text: $appState.llmEndpointText)

                Button(isChinese ? "默认" : "Default") {
                    appState.llmEndpointText = OpenAICompatibleProvider.defaultEndpointString
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
                .foregroundColor(.secondary)
            }

            Text(
                isChinese
                    ? "填基础地址即可，常见后缀会自动适配。"
                    : "A base URL is enough. Common suffixes are adapted automatically."
            )
            .font(.caption2)
            .foregroundColor(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        .frame(minWidth: 280, idealWidth: 360, maxWidth: .infinity, alignment: .leading)
    }

    private var expertSummary: String {
        guard appState.asrExpertProfile.isEnabled else {
            return isChinese ? "已关闭" : "Off"
        }

        var parts: [String] = []
        let profile = appState.asrExpertProfile
        if !profile.domain.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            parts.append(profile.domain.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        if !profile.glossaryText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            parts.append(isChinese ? "常用词" : "Terms")
        }
        if !profile.extraInstructions.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            parts.append(isChinese ? "整理要求" : "Preferences")
        }
        if parts.isEmpty {
            return isChinese ? "可选，不填也能用" : "Optional"
        }
        return parts.prefix(2).joined(separator: " · ")
    }

    private var expertSettingsPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            DisclosureGroup(
                isExpanded: $showsExpertSettings,
                content: {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(expertSectionHint)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)

                        Toggle(isOn: Binding(
                            get: { appState.asrExpertProfile.isEnabled },
                            set: { appState.asrExpertProfile.isEnabled = $0 }
                        )) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(expertToggleTitle)
                                    .font(.body)
                                Text(
                                    isChinese
                                        ? "只会影响全文优化和听写增强，不影响测试连接。"
                                        : "Only affects rewrite and dictation enhancement, not connection tests."
                                )
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            }
                        }
                        .toggleStyle(.switch)

                        HStack(alignment: .center, spacing: 10) {
                            Text(isChinese ? "内容方向" : "Topic")
                                .font(.caption.weight(.semibold))
                                .foregroundColor(.secondary)
                                .frame(width: fieldLabelWidth, alignment: .leading)

                            inputShell(focused: focusedField == .domain) {
                                TextField(
                                    isChinese ? "例如：写代码、做产品、剪视频、记会议" : "Example: coding, product work, video editing, meetings",
                                    text: Binding(
                                        get: { appState.asrExpertProfile.domain },
                                        set: { appState.asrExpertProfile.domain = $0 }
                                    )
                                )
                                .focused($focusedField, equals: .domain)
                                .textFieldStyle(.plain)

                                Spacer(minLength: 0)
                                clearButton(
                                    for: .domain,
                                    text: Binding(
                                        get: { appState.asrExpertProfile.domain },
                                        set: { appState.asrExpertProfile.domain = $0 }
                                    )
                                )
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        HStack(alignment: .center, spacing: 10) {
                            Text(isChinese ? "整理风格" : "Style")
                                .font(.caption.weight(.semibold))
                                .foregroundColor(.secondary)
                                .frame(width: fieldLabelWidth, alignment: .leading)

                            Picker("", selection: Binding(
                                get: { appState.asrExpertProfile.tone },
                                set: { appState.asrExpertProfile.tone = $0 }
                            )) {
                                Text(isChinese ? "保留原话" : "Keep Spoken").tag(ASRExpertTone.preserveSpoken)
                                Text(isChinese ? "更书面" : "More Formal").tag(ASRExpertTone.formal)
                                Text(isChinese ? "更像指令" : "More Directive").tag(ASRExpertTone.directive)
                            }
                            .pickerStyle(.segmented)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        HStack(alignment: .center, spacing: 10) {
                            Text(isChinese ? "常用词" : "Terms")
                                .font(.caption.weight(.semibold))
                                .foregroundColor(.secondary)
                                .frame(width: fieldLabelWidth, alignment: .leading)

                            inputShell(focused: focusedField == .glossary) {
                                TextField(
                                    isChinese ? "例如：Aether、SwiftUI、Prompt、Whisper" : "Example: Aether, SwiftUI, Prompt, Whisper",
                                    text: Binding(
                                        get: { appState.asrExpertProfile.glossaryText },
                                        set: { appState.asrExpertProfile.glossaryText = $0 }
                                    )
                                )
                                .focused($focusedField, equals: .glossary)
                                .textFieldStyle(.plain)

                                Spacer(minLength: 0)
                                clearButton(
                                    for: .glossary,
                                    text: Binding(
                                        get: { appState.asrExpertProfile.glossaryText },
                                        set: { appState.asrExpertProfile.glossaryText = $0 }
                                    )
                                )
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        HStack(alignment: .center, spacing: 10) {
                            Text(isChinese ? "整理要求" : "Preferences")
                                .font(.caption.weight(.semibold))
                                .foregroundColor(.secondary)
                                .frame(width: fieldLabelWidth, alignment: .leading)

                            inputShell(focused: focusedField == .extraInstructions) {
                                TextField(
                                    isChinese ? "例如：去口头禅、断句清楚一点、保留原意" : "Example: remove filler words, split sentences clearly, keep the meaning",
                                    text: Binding(
                                        get: { appState.asrExpertProfile.extraInstructions },
                                        set: { appState.asrExpertProfile.extraInstructions = $0 }
                                    )
                                )
                                .focused($focusedField, equals: .extraInstructions)
                                .textFieldStyle(.plain)

                                Spacer(minLength: 0)
                                clearButton(
                                    for: .extraInstructions,
                                    text: Binding(
                                        get: { appState.asrExpertProfile.extraInstructions },
                                        set: { appState.asrExpertProfile.extraInstructions = $0 }
                                    )
                                )
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        Text(
                            isChinese
                                ? "这些选项会拼进全文优化和听写增强里；不知道怎么填时，直接留空就行。"
                                : "These options are merged into rewrite prompts. Leave them blank if you are unsure."
                        )
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.top, 8)
                },
                label: {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(expertSectionTitle)
                            .font(.subheadline.weight(.semibold))
                        Text(expertSummary)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }
            )
        }
    }

    var body: some View {
        GlassCard(padding: 14) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 10) {
                    VStack(alignment: .leading, spacing: 4) {
                        Label(isChinese ? "文本优化服务" : "Text Rewrite Service", systemImage: "wand.and.stars")
                            .font(.headline)
                        Text(
                            isChinese
                                ? "用于听写增强和全文优化。当前支持 OpenAI 兼容接口。"
                                : "Used by dictation enhancement and full-text rewrite. Currently supports OpenAI-compatible services."
                        )
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 12)

                    LanguageStatusTag(title: statusTitle, tint: statusTint)
                }

                serviceSourcePicker

                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 12) {
                        VStack(alignment: .leading, spacing: 6) {
                            Toggle(isOn: $appState.isLLMEnhancementEnabled) {
                                Text(isChinese ? "启用文本改写优化" : "Enable Rewrite Enhancement")
                                    .font(.body)
                            }
                            .toggleStyle(.switch)

                            Text(enhancementDescription)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        Spacer(minLength: 12)
                        actionButtons
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Toggle(isOn: $appState.isLLMEnhancementEnabled) {
                            Text(isChinese ? "启用文本改写优化" : "Enable Rewrite Enhancement")
                                .font(.body)
                        }
                        .toggleStyle(.switch)

                        Text(enhancementDescription)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)

                        actionButtons
                    }
                }

                if usesAppleOnDevice {
                    appleOnDeviceInfoPanel
                } else {
                    apiKeyRow

                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .top, spacing: 12) {
                            modelField
                            endpointField
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            modelField
                            endpointField
                        }
                    }
                }

                expertSettingsPanel

                VStack(alignment: .leading, spacing: 6) {
                    Text(statusDescription)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    if let feedback = appState.llmConfigurationFeedback,
                       !feedback.isEmpty {
                        Text(feedback)
                            .font(.caption)
                            .foregroundColor(feedbackColor)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct HeadGestureShortcutMappingCard: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject private var motionManager = HeadMotionManager.shared
    @State private var expandedGestureIDs: Set<UUID> = []
    @State private var revealInputDiagnostics = false
    private var isChinese: Bool { AppLocalization.isChinese }
    private var fixedGestures: [HeadMotionManager.RecordedHeadGesture] { motionManager.fixedHotZoneGestures }
    private var motionGestures: [HeadMotionManager.RecordedHeadGesture] { motionManager.builtInMotionGestures }

    private var gestureActionOptions: [FixedPopUpOption] {
        HeadMotionManager.HeadGestureAction.allCases.map {
            FixedPopUpOption(id: $0.rawValue, title: $0.label)
        }
    }

    private func selection(for gestureID: UUID) -> Binding<String> {
        Binding(
            get: {
                motionManager.recordedHeadGestures.first(where: { $0.id == gestureID })?.action.rawValue
                    ?? HeadMotionManager.HeadGestureAction.none.rawValue
            },
            set: { newValue in
                guard let action = HeadMotionManager.HeadGestureAction(rawValue: newValue) else { return }
                motionManager.updateRecordedHeadGestureAction(id: gestureID, action: action)
            }
        )
    }

    private func enabledBinding(for gestureID: UUID) -> Binding<Bool> {
        Binding(
            get: { motionManager.recordedHeadGestures.first(where: { $0.id == gestureID })?.enabled ?? true },
            set: { motionManager.toggleRecordedHeadGestureEnabled(id: gestureID, enabled: $0) }
        )
    }

    private func toggleHiddenInputDiagnostics() {
        revealInputDiagnostics.toggle()
        HUDManager.shared.showTemporary(
            message: revealInputDiagnostics
                ? (isChinese ? "已显示输入框诊断" : "Input diagnostics on")
                : (isChinese ? "已隐藏输入框诊断" : "Input diagnostics off"),
            icon: "ladybug"
        )
    }

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 10) {
                    TransparencyModeIcon(size: 18, color: .secondary)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(isChinese ? "热区规则" : "Hot Zone Rules")
                            .font(.headline)
                        Text(isChinese ? "固定 4 个边缘热区。为每个热区配置动作，未配置则不生效。" : "Four fixed edge zones. Assign an action to activate a zone.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 12)
                }

                if fixedGestures.isEmpty {
                    Text(isChinese ? "热区尚未就绪。" : "Hot zones are not ready yet.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(nsColor: .controlBackgroundColor).opacity(0.4))
                        .cornerRadius(12)
                } else {
                    let columns = [
                        GridItem(.adaptive(minimum: 320), spacing: 12, alignment: .leading)
                    ]
                    LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
                        ForEach(fixedGestures) { gesture in
                            gestureRow(gesture)
                        }
                    }
                }

                if !motionGestures.isEmpty {
                    Divider()

                    VStack(alignment: .leading, spacing: 8) {
                        Text(isChinese ? "头部动作（点头/摇头）" : "Head Gestures (Nod/Shake)")
                            .font(.subheadline.weight(.semibold))
                        Text(isChinese ? "点头和摇头作为独立触发，不与热区混用。" : "Nod and shake are separate triggers from hot zones.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    let columns = [
                        GridItem(.adaptive(minimum: 320), spacing: 12, alignment: .leading)
                    ]
                    LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
                        ForEach(motionGestures) { gesture in
                            gestureRow(gesture)
                        }
                    }
                }

                DisclosureGroup(
                    content: {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text(isChinese ? "热区触发历史" : "Hot Zone History")
                                .font(.subheadline.weight(.semibold))
                            Spacer()
                            Button(isChinese ? "复制调试数据" : "Copy Debug Data") {
                                do {
                                    try motionManager.copyHeadGestureDebugData()
                                    HUDManager.shared.showTemporary(
                                        message: isChinese ? "已复制调试数据" : "Debug data copied",
                                        icon: "doc.on.doc"
                                    )
                                } catch {
                                    HUDManager.shared.showTemporary(
                                        message: isChinese ? "复制调试数据失败" : "Couldn't copy debug data",
                                        icon: "xmark.circle.fill"
                                    )
                                }
                            }
                            .controlSize(.small)
                            .buttonStyle(.borderless)
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.secondary)

                            Button(isChinese ? "导出调试数据" : "Export Debug Data") {
                                do {
                                    if let _ = try motionManager.exportHeadGestureDebugData() {
                                        HUDManager.shared.showTemporary(
                                            message: isChinese ? "已导出调试数据" : "Debug data exported",
                                            icon: "square.and.arrow.up"
                                        )
                                    }
                                } catch {
                                    HUDManager.shared.showTemporary(
                                        message: isChinese ? "导出调试数据失败" : "Couldn't export debug data",
                                        icon: "xmark.circle.fill"
                                    )
                                }
                            }
                            .controlSize(.small)
                            .buttonStyle(.borderless)
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.secondary)

                            if revealInputDiagnostics {
                                Button(isChinese ? "导出输入框诊断" : "Export Input Diagnostics") {
                                    do {
                                        _ = try appState.voiceService.exportFocusedInputDiagnostics()
                                        HUDManager.shared.showTemporary(
                                            message: isChinese
                                                ? "已导出输入框诊断"
                                                : "Input diagnostics exported",
                                            icon: "waveform.path.ecg"
                                        )
                                    } catch {
                                        HUDManager.shared.showTemporary(
                                            message: isChinese
                                                ? "导出输入框诊断失败"
                                                : "Couldn't export input diagnostics",
                                            icon: "xmark.circle.fill"
                                        )
                                    }
                                }
                                .controlSize(.small)
                                .buttonStyle(.borderless)
                                .font(.caption.weight(.semibold))
                                .foregroundColor(.secondary)
                            }

                            if !motionManager.headGestureHistory.isEmpty {
                                Button(isChinese ? "复制全部" : "Copy All") {
                                    do {
                                        try motionManager.copyHeadGestureHistory()
                                        HUDManager.shared.showTemporary(
                                            message: isChinese ? "已复制动作历史" : "Gesture history copied",
                                            icon: "doc.on.doc"
                                        )
                                    } catch {
                                        HUDManager.shared.showTemporary(
                                            message: isChinese ? "复制头动历史失败" : "Couldn't copy gesture history",
                                            icon: "xmark.circle.fill"
                                        )
                                    }
                                }
                                .controlSize(.small)
                                .buttonStyle(.borderless)
                                .font(.caption.weight(.semibold))
                                .foregroundColor(.secondary)
                            }

                            Button(isChinese ? "清空记录" : "Clear History") {
                                motionManager.clearHeadGestureHistory()
                            }
                            .controlSize(.small)
                            .buttonStyle(.borderless)
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.secondary)
                        }

                        if motionManager.headGestureHistory.isEmpty {
                            Text(
                                isChinese
                                ? "还没有热区触发历史。识别成功和未匹配都会写入调试数据。"
                                : "No hot zone history yet. Matches and misses are written to debug data."
                            )
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .padding(.vertical, 4)
                        } else {
                            ForEach(Array(motionManager.headGestureHistory.prefix(10))) { entry in
                                historyRow(entry)
                            }
                        }
                    }
                },
                    label: {
                        HStack(spacing: 6) {
                            Text(isChinese ? "高级与调试" : "Advanced & Diagnostics")
                            if revealInputDiagnostics {
                                Image(systemName: "ladybug")
                                    .foregroundColor(.secondary)
                                    .font(.caption)
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture(count: 5, perform: toggleHiddenInputDiagnostics)
                    }
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func gestureRow(_ gesture: HeadMotionManager.RecordedHeadGesture) -> some View {
        let isExpanded = expandedGestureIDs.contains(gesture.id)

        DisclosureGroup(
            isExpanded: Binding(
                get: { isExpanded },
                set: { newValue in
                    if newValue {
                        expandedGestureIDs.insert(gesture.id)
                    } else {
                        expandedGestureIDs.remove(gesture.id)
                    }
                }
            )
        ) {
            VStack(alignment: .leading, spacing: 12) {
                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
                    GridRow {
                        Text(isChinese ? "执行动作" : "Action")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .frame(width: 56, alignment: .leading)
                        FixedWidthPopUpMenu(
                            options: gestureActionOptions,
                            selection: selection(for: gesture.id)
                        )
                        .controlSize(.small)
                        .frame(maxWidth: 260, alignment: .leading)
                    }
                }

                Text(gesture.action == .none
                        ? (isChinese ? "未配置动作，该触发不会生效。" : "No action assigned. This trigger is inactive.")
                        : gestureHint(for: gesture))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.top, 6)
            .padding(.bottom, 2)
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(gesture.name)
                        .font(.subheadline.weight(.semibold))
                    if !isExpanded {
                        Text(
                            gesture.action == .none
                                ? (isChinese ? "未配置动作" : "Inactive")
                                : gesture.action.label
                        )
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                Spacer(minLength: 12)
                Toggle("", isOn: enabledBinding(for: gesture.id))
                    .labelsHidden()
                    .controlSize(.small)
                    .accessibilityLabel(Text(isChinese ? "启用该动作" : "Enable gesture"))
                    .accessibilityHint(Text(isChinese ? "启用或禁用此头部动作" : "Enable or disable this head gesture"))
                    .frame(width: 36, height: 22, alignment: .center)
            }
            .padding(.vertical, 4)
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.6))
        .cornerRadius(10)
    }

    private func gestureHint(for gesture: HeadMotionManager.RecordedHeadGesture) -> String {
        if motionManager.fixedHotZoneGestures.contains(where: { $0.id == gesture.id }) {
            return isChinese ? "移入该热区并停留即可触发。" : "Move into this zone and dwell to trigger."
        }
        return isChinese ? "做出对应点头或摇头即可触发。" : "Perform the corresponding nod or shake to trigger."
    }

    @ViewBuilder
    private func historyRow(_ entry: HeadMotionManager.HeadGestureHistoryEntry) -> some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(entry.gestureName) · \(entry.result.label)")
                    .font(.caption.weight(.semibold))
                Text(entry.summary)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(entry.actionName)
                    .font(.caption2)
                    .foregroundColor(.secondary.opacity(0.85))
            }

            Spacer(minLength: 12)

            VStack(alignment: .trailing, spacing: 4) {
                Button {
                    do {
                        try motionManager.copyHeadGestureHistoryEntry(entry)
                        HUDManager.shared.showTemporary(
                            message: isChinese ? "已复制这条记录" : "Entry copied",
                            icon: "doc.on.doc"
                        )
                    } catch {
                        HUDManager.shared.showTemporary(
                            message: isChinese ? "复制记录失败" : "Couldn't copy entry",
                            icon: "xmark.circle.fill"
                        )
                    }
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.secondary)
                }
                .controlSize(.small)
                .buttonStyle(.borderless)
                .accessibilityLabel(Text(isChinese ? "复制该条历史" : "Copy this history item"))

                Text(entry.date.formatted(date: .omitted, time: .shortened))
                    .font(.caption2.weight(.medium))
                    .foregroundColor(.secondary)
                if let score = entry.score {
                    Text(String(format: "%.0f%%", score * 100))
                        .font(.caption2.monospacedDigit())
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(10)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.35))
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

private struct HeadGestureTemplatePreview: View {
    let points: [HeadMotionManager.RecordedHeadGesturePoint]

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor).opacity(0.52))
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)

                Path { path in
                    guard let first = points.first else { return }
                    path.move(to: map(first, in: proxy.size))
                    for point in points.dropFirst() {
                        path.addLine(to: map(point, in: proxy.size))
                    }
                }
                .stroke(
                    LinearGradient(colors: [Color.green.opacity(0.92), Color.cyan.opacity(0.82)], startPoint: .leading, endPoint: .trailing),
                    style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round)
                )
            }
        }
    }

    private func map(_ point: HeadMotionManager.RecordedHeadGesturePoint, in size: CGSize) -> CGPoint {
        CGPoint(
            x: 10 + CGFloat(point.x) * max(size.width - 20, 1),
            y: 10 + CGFloat(point.y) * max(size.height - 20, 1)
        )
    }
}

private struct VoiceLexiconSection: Identifiable {
    let title: String
    let subtitle: String
    let systemImage: String
    let tint: Color
    let presets: [VoiceCommandPreset]
    let itemCountOverride: Int?

    init(
        title: String,
        subtitle: String,
        systemImage: String,
        tint: Color,
        presets: [VoiceCommandPreset] = [],
        itemCount: Int? = nil
    ) {
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.tint = tint
        self.presets = presets
        self.itemCountOverride = itemCount
    }

    var itemCount: Int { itemCountOverride ?? presets.count }

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

private struct VoiceLexiconSectionHeader: View {
    let section: VoiceLexiconSection
    let isExpanded: Bool

    var body: some View {
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
                    Text("\(section.itemCount)")
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
                    .lineLimit(2)
            }

            Spacer(minLength: 12)

            Image(systemName: "chevron.down")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.secondary)
                .rotationEffect(.degrees(isExpanded ? 180 : 0))
                .animation(.easeInOut(duration: 0.18), value: isExpanded)
        }
    }
}

private struct VoiceLexiconSectionCard<Content: View>: View {
    let section: VoiceLexiconSection
    @Binding var isExpanded: Bool
    let content: Content

    init(section: VoiceLexiconSection, isExpanded: Binding<Bool>, @ViewBuilder content: () -> Content) {
        self.section = section
        _isExpanded = isExpanded
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.18)) {
                    isExpanded.toggle()
                }
            } label: {
                VoiceLexiconSectionHeader(section: section, isExpanded: isExpanded)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                content
                    .padding(.top, 8)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(12)
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
        case .deleteBackward:
            return isChinese ? "删除文本" : "Delete Text"
        case .moveCursorLeft:
            return isChinese ? "光标左移" : "Move Cursor Left"
        case .moveCursorRight:
            return isChinese ? "光标右移" : "Move Cursor Right"
        case .selectLeft:
            return isChinese ? "向左选择" : "Select Left"
        case .selectRight:
            return isChinese ? "向右选择" : "Select Right"
        case .rewriteFullText:
            return isChinese ? "全文纠错优化" : "Polish Full Text"
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
        case .deleteBackward:
            return isChinese ? "删除光标左侧文本，可带数量，比如“删除 3 个字”。" : "Deletes text before the cursor and supports counts like 'delete 3 chars'."
        case .moveCursorLeft:
            return isChinese ? "光标向左移动，可带数量，比如“向左移动 5 个字”。" : "Moves the cursor left and supports counts like 'move left 5 chars'."
        case .moveCursorRight:
            return isChinese ? "光标向右移动，可带数量，比如“向右移动 5 个字”。" : "Moves the cursor right and supports counts like 'move right 5 chars'."
        case .selectLeft:
            return isChinese ? "向左扩展选择，可带数量，比如“向左选择 4 个字”。" : "Extends selection to the left and supports counts like 'select left 4 chars'."
        case .selectRight:
            return isChinese ? "向右扩展选择，可带数量，比如“向右选择 4 个字”。" : "Extends selection to the right and supports counts like 'select right 4 chars'."
        case .rewriteFullText:
            return isChinese ? "读取当前输入框全文，交给大模型做纠错与润色，再替换原文，并在记录里保存优化前后内容。" : "Reads the full text from the current field, asks the LLM to proofread and polish it, replaces the original text, and stores both before/after versions in history."
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
        case .deleteBackward:
            return isChinese ? "例如：删除、删除 3 个字" : "Example: delete, delete 3 chars"
        case .moveCursorLeft:
            return isChinese ? "例如：向左移动、左移 2 个字" : "Example: move left, cursor left 2 chars"
        case .moveCursorRight:
            return isChinese ? "例如：向右移动、右移 2 个字" : "Example: move right, cursor right 2 chars"
        case .selectLeft:
            return isChinese ? "例如：向左选择、左选 2 个字" : "Example: select left, extend left 2 chars"
        case .selectRight:
            return isChinese ? "例如：向右选择、右选 2 个字" : "Example: select right, extend right 2 chars"
        case .rewriteFullText:
            return isChinese ? "例如：全文纠错优化、优化全文" : "Example: polish full text, rewrite full text"
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
    let onAddCurrent: () -> Void
    let onAddGlobal: () -> Void
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
                            ? "给某个App手动补一条语言命令和对应的快捷键，可以使用语音触发快捷键。"
                            : "Add a voice command and matching shortcut for a specific app, then trigger that shortcut by voice."
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
                    Menu {
                        Button(isChinese ? "新增当前 App 规则" : "Add Current App Rule", action: onAddCurrent)
                        Button(isChinese ? "新增全局规则" : "Add Global Rule", action: onAddGlobal)
                    } label: {
                        Label(isChinese ? "新增规则" : "Add Rule", systemImage: "plus")
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                }
            }

            if rules.isEmpty {
                Text(isChinese ? "还没有自定义规则。比如你可以给聊天应用补一条“发送 -> ⏎ / ⌘↩”规则，或者加一条全体 App 通用规则。" : "No custom rules yet. For example, add a \"Send -> Return / Cmd+Return\" rule for your chat app, or create one global rule for all apps.")
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

    private var iconBundleIDs: [String] {
        let bundleIDs = rule.effectiveBundleIdentifiers
        if bundleIDs.isEmpty {
            return [""]
        }
        return Array(bundleIDs.prefix(3))
    }

    private var targetSummary: String {
        let bundleIDs = rule.effectiveBundleIdentifiers
        if bundleIDs.isEmpty {
            return AppLocalization.isChinese ? "全体 App" : "All Apps"
        }
        return ""
    }

    private var targetDetail: String {
        let bundleIDs = rule.effectiveBundleIdentifiers
        if bundleIDs.count == 1 {
            return SpeechAppMetaStore.name(for: bundleIDs[0])
        }
        guard bundleIDs.count > 1 else { return "" }
        return bundleIDs.map(SpeechAppMetaStore.name(for:)).joined(separator: " · ")
    }

    private var isChinese: Bool {
        AppLocalization.isChinese
    }

    private var aliasPreview: String {
        let aliases = rule.effectiveAliases
        return aliases.prefix(3).joined(separator: " / ")
    }

    var body: some View {
        HStack(spacing: 10) {
            ZStack(alignment: .leading) {
                ForEach(Array(iconBundleIDs.enumerated()), id: \.offset) { index, bundleID in
                    SpeechAppIcon(bundleID: bundleID)
                        .frame(width: 28, height: 28)
                        .offset(x: CGFloat(index * 14))
                }
            }
            .frame(width: CGFloat(28 + max(0, iconBundleIDs.count - 1) * 14), height: 28, alignment: .leading)

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
                if !targetSummary.isEmpty {
                    Text(targetSummary)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                if !targetDetail.isEmpty {
                    Text(targetDetail)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !aliasPreview.isEmpty {
                    Text(aliasPreview)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            ShortcutBadgeView(binding: rule.shortcut, minWidth: 90)

            Button(action: onEdit) {
                Image(systemName: "pencil")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(Text(isChinese ? "编辑规则" : "Edit rule"))

            Button(action: onDelete) {
                Image(systemName: "trash")
                    .foregroundColor(.red)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(Text(isChinese ? "删除规则" : "Delete rule"))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
        .cornerRadius(10)
    }
}

private struct CustomAppShortcutRuleEditorSheet: View {
    @State private var draftRule: CustomAppShortcutRule
    let onSave: (CustomAppShortcutRule) -> Void
    let onCancel: () -> Void
    @Environment(\.dismiss) private var dismiss

    init(
        rule: CustomAppShortcutRule,
        onSave: @escaping (CustomAppShortcutRule) -> Void,
        onCancel: @escaping () -> Void
    ) {
        _draftRule = State(initialValue: rule)
        self.onSave = onSave
        self.onCancel = onCancel
    }

    private var isChinese: Bool {
        AppLocalization.isChinese
    }

    private var aliasesBinding: Binding<String> {
        Binding(
            get: { draftRule.aliases.joined(separator: ", ") },
            set: { raw in
                draftRule.aliases = raw
                    .components(separatedBy: CharacterSet(charactersIn: ",\n"))
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
            }
        )
    }

    private var bundleIdentifiersBinding: Binding<String> {
        Binding(
            get: { draftRule.effectiveBundleIdentifiers.joined(separator: ", ") },
            set: { raw in
                draftRule.bundleIdentifiers = raw
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
                Button(isChinese ? "取消" : "Cancel") {
                    onCancel()
                    dismiss()
                }
                Button(NSLocalizedString("custom_app_rule_editor.done", comment: "")) {
                    onSave(draftRule)
                    dismiss()
                }
            }

            Toggle(NSLocalizedString("custom_app_rule_editor.enable_rule", comment: ""), isOn: $draftRule.isEnabled)

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(NSLocalizedString("custom_app_rule_editor.target_app", comment: ""))
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Button(isChinese ? "设为全局" : "Use Global") {
                        draftRule.bundleIdentifiers = []
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    SpeechAppPickerMenu(
                        existingBundleIds: Set(draftRule.effectiveBundleIdentifiers.map { $0.lowercased() }),
                        onAdd: { bundleID in
                            if !draftRule.effectiveBundleIdentifiers.contains(where: { $0.caseInsensitiveCompare(bundleID) == .orderedSame }) {
                                draftRule.bundleIdentifiers = draftRule.effectiveBundleIdentifiers + [bundleID]
                            }
                        }
                    )
                }
                HStack(spacing: 10) {
                    SpeechAppIcon(bundleID: draftRule.effectiveBundleIdentifiers.first ?? "")
                        .frame(width: 28, height: 28)
                    TextField(
                        NSLocalizedString("custom_app_rule_editor.bundle_id_placeholder", comment: ""),
                        text: bundleIdentifiersBinding
                    )
                    .textFieldStyle(.roundedBorder)
                }
                Text(draftRule.effectiveBundleIdentifiers.isEmpty
                     ? (isChinese ? "留空表示这条规则对所有 App 生效。" : "Leave empty to make this rule apply to all apps.")
                     : draftRule.effectiveBundleIdentifiers.map(SpeechAppMetaStore.name(for:)).joined(separator: " · "))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(NSLocalizedString("custom_app_rule_editor.action_title", comment: ""))
                    .font(.subheadline.weight(.semibold))
                TextField(NSLocalizedString("custom_app_rule_editor.action_title_placeholder", comment: ""), text: $draftRule.title)
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
                KeyRecorderView(binding: $draftRule.shortcut, allowBareKeys: true, onChange: { newBinding in
                    draftRule.shortcut = newBinding
                })
            }
        }
        .padding(16)
        .frame(width: 560)
    }
}

private let voiceUsageInsightsShowNoSpeechEventsStorageKey = "voiceUsageInsights.showNoSpeechEvents"

private struct VoiceUsageInsightsCard: View {
    @EnvironmentObject var appState: AppState
    @State private var showingClearDataConfirm: Bool = false
    @State private var showingResetStatisticsConfirm: Bool = false
    @State private var showAdvancedTools: Bool = false
    @State private var showingAllAppsPopover: Bool = false
    @State private var showingAllRecentEventsPopover: Bool = false
    @State private var recentActivityFilter: AppState.UsageInsightsRecentActivityFilter = .all
    @State private var showNoSpeechEvents: Bool = UserDefaults.standard.object(
        forKey: voiceUsageInsightsShowNoSpeechEventsStorageKey
    ) as? Bool ?? false

    private var isChinese: Bool {
        AppLocalization.isChinese
    }

    private var snapshot: AppState.UsageInsightsSnapshot {
        appState.usageInsightsSnapshot(
            showNoSpeechEvents: showNoSpeechEvents,
            recentFilter: recentActivityFilter,
            perAppSort: .total,
            recentLimit: 5
        )
    }

    private var topAppItems: [AppState.UsageInsightsPerAppItem] {
        Array(snapshot.perAppItems.prefix(4))
    }

    private var activeAppCountText: String {
        isChinese ? "活跃 \(snapshot.perAppItems.count)" : "\(snapshot.perAppItems.count) active"
    }

    private var issueAppCountText: String {
        let count = snapshot.perAppItems.filter { $0.issueCount > 0 }.count
        return isChinese ? "问题 \(count)" : "\(count) with issues"
    }

    private var anomalyAppCountText: String {
        let count = snapshot.perAppItems.filter { $0.anomalyCount > 0 }.count
        return isChinese ? "异常 \(count)" : "\(count) anomalies"
    }

    private var topAppShareText: String {
        guard let first = snapshot.perAppItems.first, snapshot.dashboard.summary.total > 0 else {
            return isChinese ? "Top 1 0%" : "Top 1 0%"
        }
        let share = Int((Double(first.summary.total) / Double(snapshot.dashboard.summary.total) * 100).rounded())
        return "Top 1 \(share)%"
    }

    private var hasMoreRecentEvents: Bool {
        snapshot.recentMatchingCount > snapshot.recentEvents.count
    }

    private var hasStatisticsData: Bool {
        snapshot.dashboard.summary.total > 0 || !snapshot.perAppItems.isEmpty
    }

    private var hasHistoryData: Bool {
        snapshot.dashboard.retainedHistoryCount > 0
    }

    private var historyValueText: String {
        "\(snapshot.dashboard.retainedHistoryCount.formatted())/\(appState.voiceUsageHistoryLimit.formatted())"
    }

    private var dictationValueText: String {
        isChinese
            ? "\(snapshot.dashboard.summary.dictationCount.formatted())/\(snapshot.dashboard.summary.dictationCharacterCount.formatted())字"
            : "\(snapshot.dashboard.summary.dictationCount.formatted())/\(snapshot.dashboard.summary.dictationCharacterCount.formatted()) chars"
    }

    private func formattedEntries(_ value: Int) -> String {
        isChinese ? "\(value) 条" : "\(value) entries"
    }

    private func formattedPlainNumber(_ value: Int) -> String {
        value.formatted()
    }

    private func recentActivityStatusText(visibleCount: Int, matchingCount: Int) -> String {
        guard visibleCount > 0 else {
            return isChinese ? "无匹配" : "No match"
        }

        if matchingCount <= visibleCount {
            return isChinese ? "最近 \(visibleCount) 条" : "Latest \(visibleCount)"
        }

        if isChinese {
            return "最近 \(visibleCount) 条，共 \(matchingCount) 条匹配"
        }
        return "Latest \(visibleCount), \(matchingCount) matched"
    }

    private func recentFilterTitle(_ filter: AppState.UsageInsightsRecentActivityFilter) -> String {
        switch filter {
        case .all:
            return String(localized: "insights.recent.filter.all")
        case .issues:
            return String(localized: "insights.recent.filter.issues")
        case .dictation:
            return String(localized: "insights.recent.filter.dictation")
        case .control:
            return String(localized: "insights.recent.filter.control")
        }
    }

    private var appOverviewTitle: String {
        isChinese ? "常用 App" : "Top Apps"
    }

    private var appOverviewSubtitle: String {
        isChinese
            ? "看看你主要在哪些 App 使用语音。"
            : "See which apps you use voice in most."
    }

    @ViewBuilder
    private func sectionCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            content()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.42))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.primary.opacity(0.05), lineWidth: 1)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            topMetricsStrip
            mainContent
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onChange(of: showNoSpeechEvents) { _, newValue in
            UserDefaults.standard.set(newValue, forKey: voiceUsageInsightsShowNoSpeechEventsStorageKey)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in
            showingAllAppsPopover = false
            showingAllRecentEventsPopover = false
        }
        .confirmationDialog(
            String(localized: "insights.reset_statistics_confirm_title"),
            isPresented: $showingResetStatisticsConfirm,
            titleVisibility: .visible
        ) {
            Button(String(localized: "insights.reset_statistics_confirm_action"), role: .destructive) {
                appState.resetVoiceUsageStatistics()
            }
            Button(String(localized: "lexicon.clear_confirm_cancel"), role: .cancel) {}
        } message: {
            Text(String(localized: "insights.reset_statistics_confirm_message"))
        }
        .confirmationDialog(
            String(localized: "insights.clear_data_confirm_title"),
            isPresented: $showingClearDataConfirm,
            titleVisibility: .visible
        ) {
            Button(String(localized: "insights.clear_data_confirm_action"), role: .destructive) {
                appState.clearVoiceUsageHistory()
            }
            Button(String(localized: "lexicon.clear_confirm_cancel"), role: .cancel) {}
        } message: {
            Text(String(localized: "insights.clear_data_confirm_message"))
        }
    }

    private var topMetricsStrip: some View {
        ViewThatFits(in: .horizontal) {
            topMetricsRow()

            ScrollView(.horizontal, showsIndicators: false) {
                topMetricsRow(fillsAvailableWidth: false)
                    .padding(.horizontal, 1)
            }
            .scrollIndicators(.hidden)
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    @ViewBuilder
    private func topMetricsRow(fillsAvailableWidth: Bool = true) -> some View {
        let summary = snapshot.dashboard.summary

        HStack(spacing: 10) {
            VoiceUsageStatusChip(
                title: isChinese ? "记录状态" : "Tracking",
                value: appState.isVoiceUsageHistoryEnabled
                    ? (isChinese ? "开启" : "On")
                    : (isChinese ? "关闭" : "Off"),
                tint: appState.isVoiceUsageHistoryEnabled ? .green : .secondary,
                usesNeutralBackground: !appState.isVoiceUsageHistoryEnabled,
                fillsAvailableWidth: fillsAvailableWidth
            )
            VoiceUsageStatusChip(
                title: isChinese ? "历史条数" : "Saved History",
                value: historyValueText,
                tint: .accentColor,
                fillsAvailableWidth: fillsAvailableWidth
            )
            VoiceUsageStatusChip(
                title: isChinese ? "总使用次数" : "Total Activity",
                value: formattedPlainNumber(summary.total),
                tint: .accentColor,
                fillsAvailableWidth: fillsAvailableWidth
            )
            VoiceUsageStatusChip(
                title: isChinese ? "输入次数" : "Dictation",
                value: dictationValueText,
                tint: .blue,
                fillsAvailableWidth: fillsAvailableWidth
            )
            VoiceUsageStatusChip(
                title: isChinese ? "控制次数" : "Control",
                value: formattedPlainNumber(summary.controlCount),
                tint: .teal,
                fillsAvailableWidth: fillsAvailableWidth
            )
        }
    }

    private var mainContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            activityPanel
            appOverviewPanel
            advancedPanel
        }
    }

    private var activityPanel: some View {
        sectionCard {
            VStack(alignment: .leading, spacing: 6) {
                Text(isChinese ? "最近活动" : "Recent Activity")
                    .font(.subheadline.weight(.semibold))
            }

            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center, spacing: 10) {
                    Picker("", selection: $recentActivityFilter) {
                        ForEach(AppState.UsageInsightsRecentActivityFilter.allCases) { filter in
                            Text(recentFilterTitle(filter)).tag(filter)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .controlSize(.small)

                    Toggle(isOn: $showNoSpeechEvents) {
                        Text(isChinese ? "显示无人声" : "No-Speech")
                            .font(.caption)
                    }
                    .toggleStyle(.switch)
                    .controlSize(.small)

                    Text(
                        recentActivityStatusText(
                            visibleCount: snapshot.recentEvents.count,
                            matchingCount: snapshot.recentMatchingCount
                        )
                    )
                    .font(.caption)
                    .foregroundColor(.secondary)

                    Spacer(minLength: 8)

                    if hasMoreRecentEvents {
                        Button(isChinese ? "查看更多记录" : "Show More") {
                            showingAllRecentEventsPopover = true
                        }
                        .buttonStyle(.borderless)
                        .controlSize(.small)
                        .popover(isPresented: $showingAllRecentEventsPopover, arrowEdge: .bottom) {
                            VoiceUsageAllRecentEventsPopover(
                                recentFilter: recentActivityFilter,
                                showNoSpeechEvents: showNoSpeechEvents,
                                retainedHistoryCount: snapshot.dashboard.retainedHistoryCount
                            )
                            .environmentObject(appState)
                        }
                    }
                }

                HStack(alignment: .center, spacing: 10) {
                    Picker("", selection: $recentActivityFilter) {
                        ForEach(AppState.UsageInsightsRecentActivityFilter.allCases) { filter in
                            Text(recentFilterTitle(filter)).tag(filter)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .controlSize(.small)

                    Toggle(isOn: $showNoSpeechEvents) {
                        Text(isChinese ? "显示无人声" : "No-Speech")
                            .font(.caption)
                    }
                    .toggleStyle(.switch)
                    .controlSize(.small)

                    Text(
                        recentActivityStatusText(
                            visibleCount: snapshot.recentEvents.count,
                            matchingCount: snapshot.recentMatchingCount
                        )
                    )
                    .font(.caption)
                    .foregroundColor(.secondary)

                    Spacer(minLength: 8)

                    if hasMoreRecentEvents {
                        Button(isChinese ? "查看更多记录" : "Show More") {
                            showingAllRecentEventsPopover = true
                        }
                        .buttonStyle(.borderless)
                        .controlSize(.small)
                        .popover(isPresented: $showingAllRecentEventsPopover, arrowEdge: .bottom) {
                            VoiceUsageAllRecentEventsPopover(
                                recentFilter: recentActivityFilter,
                                showNoSpeechEvents: showNoSpeechEvents,
                                retainedHistoryCount: snapshot.dashboard.retainedHistoryCount
                            )
                            .environmentObject(appState)
                        }
                    }
                }
            }

            if snapshot.recentEvents.isEmpty {
                Text(LocalizedStringKey("insights.recent.no_match"))
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(snapshot.recentEvents) { record in
                        VoiceUsageEventRow(event: record.source)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var appOverviewPanel: some View {
        sectionCard {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(appOverviewTitle)
                        .font(.subheadline.weight(.semibold))
                    Text(appOverviewSubtitle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer(minLength: 8)

                if !snapshot.perAppItems.isEmpty {
                    Button(isChinese ? "查看全部 App" : "View All Apps") {
                        showingAllAppsPopover = true
                    }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                    .popover(isPresented: $showingAllAppsPopover, arrowEdge: .bottom) {
                        VoiceUsageAllAppsPopover(items: snapshot.perAppItems)
                            .environmentObject(appState)
                    }
                }
            }

            if topAppItems.isEmpty {
                Text(isChinese ? "当前还没有按 App 的使用记录。" : "No per-app activity is available yet.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                HStack(spacing: 10) {
                    Text(activeAppCountText)
                    Text(issueAppCountText)
                    Text(anomalyAppCountText)
                    Text(topAppShareText)
                }
                .font(.caption)
                .foregroundColor(.secondary)

                HStack(spacing: 10) {
                    Spacer(minLength: 0)
                    Text(isChinese ? "总数" : "Total")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .frame(width: 40, alignment: .trailing)
                    Text(isChinese ? "输入" : "Dict.")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .frame(width: 40, alignment: .trailing)
                    Text(isChinese ? "控制" : "Ctrl.")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .frame(width: 40, alignment: .trailing)
                    Text(isChinese ? "问题" : "Issue")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .frame(width: 40, alignment: .trailing)
                    Text(isChinese ? "字数" : "Chars")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .frame(width: 68, alignment: .trailing)
                }
                .padding(.horizontal, 8)

                VStack(alignment: .leading, spacing: 6) {
                    ForEach(topAppItems) { item in
                        VoiceUsageTopAppRow(item: item)
                    }
                }
            }
        }
    }

    private var advancedPanel: some View {
        sectionCard {
            Button {
                withAnimation(.easeInOut(duration: 0.15)) {
                    showAdvancedTools.toggle()
                }
            } label: {
                HStack(alignment: .center, spacing: 10) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(isChinese ? "高级与数据" : "Advanced & Data")
                            .font(.subheadline.weight(.semibold))
                        Text(
                            isChinese
                                ? "导出诊断、管理本地记录，或执行重置与清除。"
                                : "Export diagnostics, manage local history, or reset retained data."
                        )
                        .font(.caption)
                        .foregroundColor(.secondary)
                    }
                    Spacer(minLength: 8)
                    Image(systemName: showAdvancedTools ? "chevron.up" : "chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(Color(nsColor: .windowBackgroundColor).opacity(0.55))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .buttonStyle(.plain)
            .contentShape(Rectangle())

            if showAdvancedTools {
                Divider()

                VStack(alignment: .leading, spacing: 12) {
                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .center, spacing: 10) {
                            Text(isChinese ? "导出与诊断" : "Export & Diagnostics")
                                .font(.caption.weight(.semibold))
                                .foregroundColor(.secondary)

                            Spacer(minLength: 8)

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
                            .disabled(!hasHistoryData)

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
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        VStack(alignment: .leading, spacing: 8) {
                            Text(isChinese ? "导出与诊断" : "Export & Diagnostics")
                                .font(.caption.weight(.semibold))
                                .foregroundColor(.secondary)

                            HStack(spacing: 8) {
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
                                .disabled(!hasHistoryData)

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
                            }
                        }
                    }
                    .controlSize(.small)
                    .buttonStyle(.bordered)

                    Divider()

                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .center, spacing: 14) {
                            Toggle(isOn: $appState.isVoiceUsageHistoryEnabled) {
                                Text(LocalizedStringKey("insights.capture_toggle_title"))
                                    .font(.caption)
                            }
                            .toggleStyle(.switch)
                            .controlSize(.small)

                            Spacer(minLength: 8)

                            HStack(alignment: .center, spacing: 10) {
                                Text(isChinese ? "保留上限" : "Retention Limit")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text(formattedEntries(appState.voiceUsageHistoryLimit))
                                    .font(.caption.monospacedDigit())
                                    .frame(minWidth: 72, alignment: .trailing)
                                Stepper("", value: $appState.voiceUsageHistoryLimit, in: 100...5000, step: 100)
                                    .labelsHidden()
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        VStack(alignment: .leading, spacing: 8) {
                            Toggle(isOn: $appState.isVoiceUsageHistoryEnabled) {
                                Text(LocalizedStringKey("insights.capture_toggle_title"))
                                    .font(.caption)
                            }
                            .toggleStyle(.switch)
                            .controlSize(.small)

                            HStack(alignment: .center, spacing: 10) {
                                Text(isChinese ? "保留上限" : "Retention Limit")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Spacer(minLength: 8)
                                Text(formattedEntries(appState.voiceUsageHistoryLimit))
                                    .font(.caption.monospacedDigit())
                                    .frame(minWidth: 72, alignment: .trailing)
                                Stepper("", value: $appState.voiceUsageHistoryLimit, in: 100...5000, step: 100)
                                    .labelsHidden()
                            }
                        }
                    }

                    Divider()

                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .center, spacing: 10) {
                            Text(isChinese ? "重置与清除" : "Reset & Clear")
                                .font(.caption.weight(.semibold))
                                .foregroundColor(.secondary)

                            Spacer(minLength: 8)

                            Button(String(localized: "insights.reset_statistics")) {
                                showingResetStatisticsConfirm = true
                            }
                            .disabled(!hasStatisticsData)

                            Button(String(localized: "insights.clear_data"), role: .destructive) {
                                showingClearDataConfirm = true
                            }
                            .disabled(!hasHistoryData)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        VStack(alignment: .leading, spacing: 8) {
                            Text(isChinese ? "重置与清除" : "Reset & Clear")
                                .font(.caption.weight(.semibold))
                                .foregroundColor(.secondary)

                            HStack(spacing: 8) {
                                Button(String(localized: "insights.reset_statistics")) {
                                    showingResetStatisticsConfirm = true
                                }
                                .disabled(!hasStatisticsData)

                                Button(String(localized: "insights.clear_data"), role: .destructive) {
                                    showingClearDataConfirm = true
                                }
                                .disabled(!hasHistoryData)
                            }
                        }
                    }
                    .controlSize(.small)
                    .buttonStyle(.bordered)
                }
                .padding(.top, 2)
            }
        }
    }
}

private struct WakeActivationInsightsCard: View {
    @EnvironmentObject var appState: AppState
    @State private var showingClearDataConfirm: Bool = false
    @State private var showingResetStatisticsConfirm: Bool = false
    @State private var recentFilter: AppState.WakeInsightsRecentFilter = .all

    private var isChinese: Bool {
        AppLocalization.isChinese
    }

    private var snapshot: AppState.WakeInsightsSnapshot {
        appState.wakeInsightsSnapshot(recentFilter: recentFilter, recentLimit: 12)
    }

    private var topPhraseItems: [AppState.WakeInsightsPhraseItem] {
        Array(snapshot.phraseItems.prefix(6))
    }

    private var hasStatisticsData: Bool {
        snapshot.dashboard.wakeHitCount > 0
            || snapshot.dashboard.wakeEmptyCount > 0
            || snapshot.dashboard.wakeToDictationCount > 0
            || snapshot.dashboard.wakeToControlCount > 0
    }

    private var hasHistoryData: Bool {
        snapshot.dashboard.retainedHistoryCount > 0
    }

    private var modeText: String {
        switch appState.voiceActivationMode {
        case .pushToTalk:
            return isChinese ? "按住说话" : "Push to Talk"
        case .wakeWord:
            return isChinese ? "唤醒词" : "Wake Word"
        case .handsFree:
            return isChinese ? "免唤醒" : "Hands-Free"
        }
    }

    private var conversionRateText: String {
        "\(Int((snapshot.dashboard.conversionRate * 100).rounded()))%"
    }

    private var wakeWindowText: String {
        let seconds = Int(snapshot.wakeWindowSeconds.rounded())
        return isChinese ? "\(seconds) 秒" : "\(seconds)s"
    }

    private var localeText: String {
        Locale.current.localizedString(forIdentifier: snapshot.currentLocaleIdentifier)
            ?? snapshot.currentLocaleIdentifier
    }

    private var recentStatusText: String {
        let visibleCount = snapshot.recentEvents.count
        let matchingCount = snapshot.recentMatchingCount
        guard visibleCount > 0 else {
            return isChinese ? "无匹配" : "No match"
        }
        if matchingCount <= visibleCount {
            return isChinese ? "最近 \(visibleCount) 条" : "Latest \(visibleCount)"
        }
        return isChinese
            ? "最近 \(visibleCount) 条，共 \(matchingCount) 条匹配"
            : "Latest \(visibleCount), \(matchingCount) matched"
    }

    private func formattedEntries(_ value: Int) -> String {
        isChinese ? "\(value) 条" : "\(value) entries"
    }

    private func recentFilterTitle(_ filter: AppState.WakeInsightsRecentFilter) -> String {
        switch filter {
        case .all:
            return isChinese ? "全部" : "All"
        case .hits:
            return isChinese ? "命中" : "Hits"
        case .conversions:
            return isChinese ? "转化" : "Conversions"
        case .empty:
            return isChinese ? "空唤醒" : "Empty"
        }
    }

    @ViewBuilder
    private func sectionCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            content()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.42))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.primary.opacity(0.05), lineWidth: 1)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            topMetricsStrip
            if appState.voiceActivationMode != .wakeWord {
                modeHintPanel
            }
            configurationPanel
            phrasePanel
            recentPanel
            managementPanel
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .confirmationDialog(
            String(localized: "insights.reset_statistics_confirm_title"),
            isPresented: $showingResetStatisticsConfirm,
            titleVisibility: .visible
        ) {
            Button(String(localized: "insights.reset_statistics_confirm_action"), role: .destructive) {
                appState.resetVoiceUsageStatistics()
            }
            Button(String(localized: "lexicon.clear_confirm_cancel"), role: .cancel) {}
        } message: {
            Text(String(localized: "insights.reset_statistics_confirm_message"))
        }
        .confirmationDialog(
            String(localized: "insights.clear_data_confirm_title"),
            isPresented: $showingClearDataConfirm,
            titleVisibility: .visible
        ) {
            Button(String(localized: "insights.clear_data_confirm_action"), role: .destructive) {
                appState.clearVoiceUsageHistory()
            }
            Button(String(localized: "lexicon.clear_confirm_cancel"), role: .cancel) {}
        } message: {
            Text(String(localized: "insights.clear_data_confirm_message"))
        }
    }

    private var topMetricsStrip: some View {
        ViewThatFits(in: .horizontal) {
            topMetricsRow()

            ScrollView(.horizontal, showsIndicators: false) {
                topMetricsRow(fillsAvailableWidth: false)
                    .padding(.horizontal, 1)
            }
            .scrollIndicators(.hidden)
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    @ViewBuilder
    private func topMetricsRow(fillsAvailableWidth: Bool = true) -> some View {
        HStack(spacing: 10) {
            VoiceUsageStatusChip(
                title: isChinese ? "当前模式" : "Mode",
                value: modeText,
                tint: appState.voiceActivationMode == .wakeWord ? .green : .secondary,
                usesNeutralBackground: appState.voiceActivationMode != .wakeWord,
                fillsAvailableWidth: fillsAvailableWidth
            )
            VoiceUsageStatusChip(
                title: isChinese ? "唤醒次数" : "Wake Hits",
                value: snapshot.dashboard.wakeHitCount.formatted(),
                tint: .green,
                fillsAvailableWidth: fillsAvailableWidth
            )
            VoiceUsageStatusChip(
                title: isChinese ? "转化率" : "Conversion",
                value: conversionRateText,
                tint: .accentColor,
                fillsAvailableWidth: fillsAvailableWidth
            )
            VoiceUsageStatusChip(
                title: isChinese ? "转输入" : "To Dictation",
                value: snapshot.dashboard.wakeToDictationCount.formatted(),
                tint: .blue,
                fillsAvailableWidth: fillsAvailableWidth
            )
            VoiceUsageStatusChip(
                title: isChinese ? "转控制" : "To Control",
                value: snapshot.dashboard.wakeToControlCount.formatted(),
                tint: .teal,
                fillsAvailableWidth: fillsAvailableWidth
            )
            VoiceUsageStatusChip(
                title: isChinese ? "空唤醒" : "Empty Wake",
                value: snapshot.dashboard.wakeEmptyCount.formatted(),
                tint: .orange,
                fillsAvailableWidth: fillsAvailableWidth
            )
        }
    }

    private var modeHintPanel: some View {
        sectionCard {
            Label(
                isChinese ? "当前不在唤醒词模式" : "Wake Word Mode Is Off",
                systemImage: "info.circle"
            )
            .font(.subheadline.weight(.semibold))

            Text(
                isChinese
                    ? "这个页面显示的是历史唤醒记录。切回“唤醒词”模式后会继续记录新的唤醒与转化。"
                    : "This page shows historical wake records. Switch back to Wake Word mode to keep collecting new wake and conversion events."
            )
            .font(.caption)
            .foregroundColor(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var configurationPanel: some View {
        sectionCard {
            VStack(alignment: .leading, spacing: 6) {
                Text(isChinese ? "当前配置" : "Current Setup")
                    .font(.subheadline.weight(.semibold))
                Text(
                    isChinese
                        ? "这里显示当前使用的语言、唤醒窗口和有效唤醒词。"
                        : "See the active locale, wake window, and effective wake phrases."
                )
                .font(.caption)
                .foregroundColor(.secondary)
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 140, maximum: 220), spacing: 10)], spacing: 10) {
                VoiceUsageSummaryBadge(
                    title: isChinese ? "当前语言" : "Locale",
                    value: localeText
                )
                VoiceUsageSummaryBadge(
                    title: isChinese ? "唤醒窗口" : "Wake Window",
                    value: wakeWindowText
                )
                VoiceUsageSummaryBadge(
                    title: isChinese ? "记录状态" : "Tracking",
                    value: appState.isVoiceUsageHistoryEnabled
                        ? (isChinese ? "开启" : "On")
                        : (isChinese ? "关闭" : "Off"),
                    valueColor: appState.isVoiceUsageHistoryEnabled ? .green : .secondary
                )
            }

            if snapshot.activeWakePhrases.isEmpty {
                Text(isChinese ? "当前语言还没有可用唤醒词。" : "No wake phrases are configured for the active locale.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 120, maximum: 180), spacing: 8)], spacing: 8) {
                    ForEach(snapshot.activeWakePhrases, id: \.self) { phrase in
                        WakePhrasePill(phrase: phrase)
                    }
                }
            }
        }
    }

    private var phrasePanel: some View {
        sectionCard {
            VStack(alignment: .leading, spacing: 6) {
                Text(isChinese ? "唤醒词分布" : "Wake Phrase Distribution")
                    .font(.subheadline.weight(.semibold))
                Text(
                    isChinese
                        ? "看看哪些唤醒词更常被命中，以及它们后续转化情况。"
                        : "See which wake phrases are hit most often and how they convert."
                )
                .font(.caption)
                .foregroundColor(.secondary)
            }

            if topPhraseItems.isEmpty {
                Text(isChinese ? "还没有可用的唤醒统计。" : "No wake statistics are available yet.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(topPhraseItems) { item in
                        WakePhraseDistributionRow(item: item)
                    }
                }
            }
        }
    }

    private var recentPanel: some View {
        sectionCard {
            VStack(alignment: .leading, spacing: 6) {
                Text(isChinese ? "最近唤醒" : "Recent Wake Events")
                    .font(.subheadline.weight(.semibold))
            }

            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center, spacing: 10) {
                    Picker("", selection: $recentFilter) {
                        ForEach(AppState.WakeInsightsRecentFilter.allCases) { filter in
                            Text(recentFilterTitle(filter)).tag(filter)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .controlSize(.small)

                    Text(recentStatusText)
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Spacer(minLength: 8)
                }

                HStack(alignment: .center, spacing: 10) {
                    Picker("", selection: $recentFilter) {
                        ForEach(AppState.WakeInsightsRecentFilter.allCases) { filter in
                            Text(recentFilterTitle(filter)).tag(filter)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .controlSize(.small)

                    Text(recentStatusText)
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Spacer(minLength: 8)
                }
            }

            if snapshot.recentEvents.isEmpty {
                Text(isChinese ? "当前筛选下没有唤醒记录。" : "No wake records match the current filter.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(snapshot.recentEvents) { record in
                        VoiceUsageEventRow(event: record.source)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var managementPanel: some View {
        sectionCard {
            VStack(alignment: .leading, spacing: 6) {
                Text(isChinese ? "记录管理" : "Record Management")
                    .font(.subheadline.weight(.semibold))
                Text(
                    isChinese
                        ? "这里管理的是与语音统计共用的一套历史数据和摘要。"
                        : "These controls manage the shared history and summary used by voice insights."
                )
                .font(.caption)
                .foregroundColor(.secondary)
            }

            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center, spacing: 14) {
                    Toggle(isOn: $appState.isVoiceUsageHistoryEnabled) {
                        Text(LocalizedStringKey("insights.capture_toggle_title"))
                            .font(.caption)
                    }
                    .toggleStyle(.switch)
                    .controlSize(.small)

                    Spacer(minLength: 8)

                    HStack(alignment: .center, spacing: 10) {
                        Text(isChinese ? "保留上限" : "Retention Limit")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(formattedEntries(appState.voiceUsageHistoryLimit))
                            .font(.caption.monospacedDigit())
                            .frame(minWidth: 72, alignment: .trailing)
                        Stepper("", value: $appState.voiceUsageHistoryLimit, in: 100...5000, step: 100)
                            .labelsHidden()
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .leading, spacing: 8) {
                    Toggle(isOn: $appState.isVoiceUsageHistoryEnabled) {
                        Text(LocalizedStringKey("insights.capture_toggle_title"))
                            .font(.caption)
                    }
                    .toggleStyle(.switch)
                    .controlSize(.small)

                    HStack(alignment: .center, spacing: 10) {
                        Text(isChinese ? "保留上限" : "Retention Limit")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer(minLength: 8)
                        Text(formattedEntries(appState.voiceUsageHistoryLimit))
                            .font(.caption.monospacedDigit())
                            .frame(minWidth: 72, alignment: .trailing)
                        Stepper("", value: $appState.voiceUsageHistoryLimit, in: 100...5000, step: 100)
                            .labelsHidden()
                    }
                }
            }

            Divider()

            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center, spacing: 10) {
                    Text(isChinese ? "重置与清除" : "Reset & Clear")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.secondary)

                    Spacer(minLength: 8)

                    Button(String(localized: "insights.reset_statistics")) {
                        showingResetStatisticsConfirm = true
                    }
                    .disabled(!hasStatisticsData)

                    Button(String(localized: "insights.clear_data"), role: .destructive) {
                        showingClearDataConfirm = true
                    }
                    .disabled(!hasHistoryData)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .leading, spacing: 8) {
                    Text(isChinese ? "重置与清除" : "Reset & Clear")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.secondary)

                    HStack(spacing: 8) {
                        Button(String(localized: "insights.reset_statistics")) {
                            showingResetStatisticsConfirm = true
                        }
                        .disabled(!hasStatisticsData)

                        Button(String(localized: "insights.clear_data"), role: .destructive) {
                            showingClearDataConfirm = true
                        }
                        .disabled(!hasHistoryData)
                    }
                }
            }
            .controlSize(.small)
            .buttonStyle(.bordered)
        }
    }
}

private struct WakePhrasePill: View {
    let phrase: String

    var body: some View {
        Text(phrase)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.green.opacity(0.12))
            .foregroundColor(.green)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct WakePhraseDistributionRow: View {
    let item: AppState.WakeInsightsPhraseItem

    private var conversionRateText: String {
        "\(Int((item.conversionRate * 100).rounded()))%"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(item.phrase)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text(conversionRateText)
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundColor(.accentColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.accentColor.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }

            HStack(spacing: 8) {
                WakePhraseMetricChip(title: AppLocalization.isChinese ? "命中" : "Hits", value: item.hitCount, tint: .green)
                WakePhraseMetricChip(title: AppLocalization.isChinese ? "转化" : "Conv.", value: item.conversionCount, tint: .accentColor)
                WakePhraseMetricChip(title: AppLocalization.isChinese ? "空唤醒" : "Empty", value: item.emptyCount, tint: .orange)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.46))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
        }
    }
}

private struct WakePhraseMetricChip: View {
    let title: String
    let value: Int
    let tint: Color

    var body: some View {
        HStack(spacing: 6) {
            Text(title)
                .lineLimit(1)
            Spacer(minLength: 4)
            Text(value.formatted())
                .monospacedDigit()
        }
        .font(.caption)
        .foregroundColor(tint)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct VoiceUsageStatusChip: View {
    let title: String
    let value: String
    var detail: String? = nil
    var tint: Color = .accentColor
    var usesNeutralBackground: Bool = false
    var fillsAvailableWidth: Bool = true

    var body: some View {
        VStack(alignment: .center, spacing: 3) {
            Text(title)
                .font(.caption2)
                .foregroundColor(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .multilineTextAlignment(.center)
            Text(value)
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .foregroundColor(usesNeutralBackground ? .primary : tint)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            if let detail, !detail.isEmpty {
                Text(detail)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(minWidth: fillsAvailableWidth ? nil : 92, alignment: .center)
        .frame(minHeight: 56, alignment: .center)
        .frame(maxWidth: fillsAvailableWidth ? .infinity : nil, alignment: .center)
        .background(
            (usesNeutralBackground ? Color(nsColor: .controlBackgroundColor) : tint)
                .opacity(usesNeutralBackground ? 0.72 : 0.08)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.primary.opacity(usesNeutralBackground ? 0.05 : 0.03), lineWidth: 1)
        }
    }
}

private struct VoiceUsageTopAppRow: View {
    let item: AppState.UsageInsightsPerAppItem

    private var bundleText: String {
        item.summary.bundleIdentifier
    }

    private var showsBundleHelp: Bool {
        !bundleText.isEmpty && bundleText != item.summary.appName
    }

    var body: some View {
        HStack(spacing: 10) {
            SpeechAppIcon(bundleID: item.summary.bundleIdentifier)
                .frame(width: 22, height: 22)

            Text(item.summary.appName)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .help(showsBundleHelp ? bundleText : "")
                .frame(maxWidth: .infinity, alignment: .leading)

            Spacer(minLength: 8)

            Text(item.summary.total.formatted())
                .font(.caption.monospacedDigit())
                .foregroundColor(.secondary)
                .frame(width: 40, alignment: .trailing)

            Text(item.summary.dictationCount.formatted())
                .font(.caption.monospacedDigit())
                .foregroundColor(.secondary)
                .frame(width: 40, alignment: .trailing)

            Text(item.summary.controlCount.formatted())
                .font(.caption.monospacedDigit())
                .foregroundColor(.secondary)
                .frame(width: 40, alignment: .trailing)

            Text(item.issueCount.formatted())
                .font(.caption.monospacedDigit())
                .foregroundColor(item.issueCount > 0 ? .orange : .secondary)
                .frame(width: 40, alignment: .trailing)

            Text(item.summary.dictationCharacterCount.formatted())
                .font(.caption.monospacedDigit())
                .foregroundColor(.secondary)
                .frame(width: 68, alignment: .trailing)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.46))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
        }
    }
}

private struct VoiceUsageAllRecentEventsPopover: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss
    let recentFilter: AppState.UsageInsightsRecentActivityFilter
    let showNoSpeechEvents: Bool
    let retainedHistoryCount: Int

    private var isChinese: Bool {
        AppLocalization.isChinese
    }

    private var snapshot: AppState.UsageInsightsSnapshot {
        appState.usageInsightsSnapshot(
            showNoSpeechEvents: showNoSpeechEvents,
            recentFilter: recentFilter,
            perAppSort: .total,
            recentLimit: max(retainedHistoryCount, 30)
        )
    }

    private func formattedEntries(_ value: Int) -> String {
        isChinese ? "\(value) 条" : "\(value) entries"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(isChinese ? "全部记录" : "All Activity")
                        .font(.title3.weight(.semibold))
                    Text(
                        isChinese
                            ? "当前筛选下共有 \(formattedEntries(snapshot.recentMatchingCount))。"
                            : "\(formattedEntries(snapshot.recentMatchingCount)) match the current filter."
                    )
                    .font(.caption)
                    .foregroundColor(.secondary)
                }

                Spacer(minLength: 8)

                Button(isChinese ? "关闭" : "Close") {
                    dismiss()
                }
                .controlSize(.small)
                .keyboardShortcut(.cancelAction)
            }

            Divider()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(snapshot.recentEvents) { record in
                        VoiceUsageEventRow(event: record.source)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(16)
        .frame(width: 760, height: 500)
    }
}

private struct VoiceUsageAllAppsPopover: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss
    let items: [AppState.UsageInsightsPerAppItem]

    private var isChinese: Bool {
        AppLocalization.isChinese
    }

    private func formattedEntries(_ value: Int) -> String {
        isChinese ? "\(value) 个 App" : "\(value) apps"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(isChinese ? "全部 App" : "All Apps")
                        .font(.title3.weight(.semibold))
                    Text(
                        isChinese
                            ? "当前共有 \(formattedEntries(items.count))。"
                            : "Showing \(formattedEntries(items.count))."
                    )
                    .font(.caption)
                    .foregroundColor(.secondary)
                }

                Spacer(minLength: 8)

                Button(isChinese ? "关闭" : "Close") {
                    dismiss()
                }
                .controlSize(.small)
                .keyboardShortcut(.cancelAction)
            }

            Divider()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 6) {
                    ForEach(items) { item in
                        VoiceUsageAppSummaryRow(summary: item.summary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(16)
        .frame(width: 700, height: 560)
    }
}

private struct VoiceUsageSummaryBadge: View {
    let title: String
    let value: String
    var detail: String? = nil
    var valueColor: Color = .primary
    var fillColor: Color = Color(nsColor: .controlBackgroundColor).opacity(0.6)

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            Text(value)
                .font(.headline)
                .foregroundColor(valueColor)
            if let detail, !detail.isEmpty {
                Text(detail)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 10)
        .frame(minHeight: 82, alignment: .topLeading)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(fillColor)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.primary.opacity(0.04), lineWidth: 1)
        }
    }
}

private struct VoiceUsageAppSummaryRow: View {
    let summary: AppState.VoiceUsageAppSummary

    private let metricColumns = [
        GridItem(.adaptive(minimum: 92, maximum: 160), spacing: 6, alignment: .leading)
    ]

    private var isChinese: Bool {
        AppLocalization.isChinese
    }

    private var bundleText: String {
        summary.bundleIdentifier
    }

    private var showsBundleHelp: Bool {
        !bundleText.isEmpty && bundleText != summary.appName
    }

    private var issueCount: Int {
        summary.failureCount + summary.unrecognizedCount + summary.mismatchCount
    }

    private var anomalyCount: Int {
        summary.noSpeechCount
    }

    private var characterText: String {
        if isChinese {
            return "输入字数 \(summary.dictationCharacterCount) 字"
        }
        return "Input characters: \(summary.dictationCharacterCount)"
    }

    private var secondaryText: String {
        if issueCount > 0 {
            if isChinese {
                return "输入字数 \(summary.dictationCharacterCount) 字 · 问题 \(issueCount) 条"
            }
            return "\(summary.dictationCharacterCount) chars · \(issueCount) issues"
        }
        if anomalyCount > 0 {
            if isChinese {
                return "输入字数 \(summary.dictationCharacterCount) 字 · 异常 \(anomalyCount) 条"
            }
            return "\(summary.dictationCharacterCount) chars · \(anomalyCount) anomalies"
        }
        return characterText
    }

    private var secondaryTextColor: Color {
        if issueCount > 0 {
            return .orange
        }
        if anomalyCount > 0 {
            return .yellow
        }
        return .secondary
    }

    private var totalText: String {
        isChinese ? "总\(summary.total)条" : "\(summary.total) entries"
    }

    @ViewBuilder
    private func metricChip(_ title: String, value: Int, emphasized: Bool = false) -> some View {
        HStack(spacing: 6) {
            Text(title)
                .lineLimit(1)
            Spacer(minLength: 4)
            Text("\(value)")
                .monospacedDigit()
        }
        .font(.caption)
        .foregroundColor(emphasized ? .orange : .secondary)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            (emphasized ? Color.orange : Color(nsColor: .controlBackgroundColor))
                .opacity(emphasized ? 0.14 : 0.7)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                SpeechAppIcon(bundleID: summary.bundleIdentifier)
                    .frame(width: 28, height: 28)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 10) {
                        Text(summary.appName)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                            .help(showsBundleHelp ? bundleText : "")
                            .layoutPriority(1)
                        Spacer()
                        Text(totalText)
                            .font(.caption.weight(.semibold).monospacedDigit())
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.accentColor.opacity(0.12))
                            .foregroundColor(.accentColor)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }

                    Text(secondaryText)
                        .font(.caption)
                        .foregroundColor(secondaryTextColor)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            LazyVGrid(columns: metricColumns, alignment: .leading, spacing: 6) {
                metricChip(isChinese ? "输入" : "Dictation", value: summary.dictationCount)
                metricChip(isChinese ? "控制" : "Control", value: summary.controlCount)
                metricChip(isChinese ? "失败" : "Failed", value: summary.failureCount, emphasized: summary.failureCount > 0)
                metricChip(isChinese ? "未匹配" : "Unmatched", value: summary.unrecognizedCount, emphasized: summary.unrecognizedCount > 0)
                metricChip(isChinese ? "误输" : "Mismatch", value: summary.mismatchCount, emphasized: summary.mismatchCount > 0)
                metricChip(isChinese ? "异常" : "Anomaly", value: summary.noSpeechCount, emphasized: summary.noSpeechCount > 0)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.primary.opacity(0.04), lineWidth: 1)
        }
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
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter
    }()

    private var isChinese: Bool {
        AppLocalization.isChinese
    }

    private var classifiedEvent: AppState.UsageInsightsEventRecord {
        AppState.classifyUsageInsightsEvent(event)
    }

    private var eventIcon: String {
        switch classifiedEvent.outcome {
        case .activation:
            switch classifiedEvent.reasonCode {
            case .wakeHit:
                return "waveform.badge.mic"
            case .wakeToDictation:
                return "text.bubble"
            case .wakeToControl:
                return "command"
            case .wakeEmpty:
                return "pause.circle"
            default:
                return "dot.radiowaves.left.and.right"
            }
        case .dictation:
            return "text.bubble"
        case .control:
            return "command"
        case .failure:
            return "exclamationmark.circle"
        case .unmatched:
            return "questionmark.bubble"
        case .mismatch:
            return "arrow.trianglehead.2.clockwise.rotate.90"
        case .anomaly:
            return "waveform.badge.exclamationmark"
        case .other:
            return event.kind == .dictation ? "text.bubble" : "dot.radiowaves.left.and.right"
        }
    }

    private var eventTint: Color {
        switch classifiedEvent.outcome {
        case .activation:
            switch classifiedEvent.reasonCode {
            case .wakeHit:
                return .green
            case .wakeToDictation:
                return .accentColor
            case .wakeToControl:
                return .teal
            case .wakeEmpty:
                return .orange
            default:
                return .secondary
            }
        case .dictation:
            return .accentColor
        case .control:
            return .blue
        case .failure, .unmatched, .mismatch:
            return .orange
        case .anomaly:
            return .yellow
        case .other:
            return .secondary
        }
    }

    private var displayAction: String {
        switch event.action {
        case "未识别":
            return "未匹配"
        case "Unrecognized":
            return "Unmatched"
        default:
            return event.action
        }
    }

    private var timeText: String {
        if Calendar.current.isDateInToday(event.timestamp) {
            return Self.timeFormatter.string(from: event.timestamp)
        }
        return Self.dateTimeFormatter.string(from: event.timestamp)
    }

    private var bundleText: String {
        event.bundleIdentifier
    }

    private var showsBundleHelp: Bool {
        !bundleText.isEmpty && bundleText != event.appName
    }

    private var previewText: String {
        if showsRewritePreview {
            return rewriteAfterText
        }
        if event.kind == .activation {
            let phrase = event.wakePhrase?.replacingOccurrences(of: "\n", with: " ")
            let followUp = event.content?.replacingOccurrences(of: "\n", with: " ")
            switch event.eventCode {
            case "wake.hit":
                if let phrase, !phrase.isEmpty {
                    return isChinese ? "唤醒词：\(phrase)" : "Wake phrase: \(phrase)"
                }
                return isChinese ? "等待后续语音" : "Waiting for follow-up"
            case "wake.to_dictation", "wake.to_control":
                if let phrase, !phrase.isEmpty, let followUp, !followUp.isEmpty {
                    return "\(phrase) -> \(followUp)"
                }
                if let followUp, !followUp.isEmpty {
                    return isChinese ? "后续：\(followUp)" : "Follow-up: \(followUp)"
                }
                if let phrase, !phrase.isEmpty {
                    return isChinese ? "唤醒词：\(phrase)" : "Wake phrase: \(phrase)"
                }
                return isChinese ? "已转入后续动作" : "Converted to follow-up action"
            case "wake.empty":
                if let phrase, !phrase.isEmpty {
                    return isChinese ? "唤醒词：\(phrase) · 未继续说话" : "Wake phrase: \(phrase) · no follow-up"
                }
                return isChinese ? "唤醒后未继续说话" : "No follow-up after wake"
            default:
                break
            }
        }
        if let content = event.content, !content.isEmpty {
            return content.replacingOccurrences(of: "\n", with: " ")
        }
        if let spokenText = event.spokenText, !spokenText.isEmpty {
            return isChinese ? "原词：\(spokenText)" : "Heard: \(spokenText)"
        }
        if event.kind == .dictation {
            return isChinese ? "（空文本）" : "(empty text)"
        }
        return displayAction
    }

    private var showsRewritePreview: Bool {
        guard let original = event.originalContent,
              !original.isEmpty,
              let rewritten = event.content,
              !rewritten.isEmpty else {
            return false
        }
        return true
    }

    private var rewriteBeforeText: String {
        let prefix = isChinese ? "前：" : "Before: "
        let value = event.originalContent ?? ""
        return prefix + value.replacingOccurrences(of: "\n", with: " ")
    }

    private var rewriteAfterText: String {
        let prefix = isChinese ? "后：" : "After: "
        let value = event.content ?? ""
        return prefix + value.replacingOccurrences(of: "\n", with: " ")
    }

    private var previewColor: Color {
        switch event.kind {
        case .activation, .dictation:
            return .primary
        case .control:
            return .secondary
        }
    }

    private var dictationStatusText: String? {
        guard event.kind == .dictation,
              let eventCode = event.eventCode,
              eventCode.hasPrefix("dictation.llm.") else {
            return nil
        }

        let status = String(eventCode.dropFirst("dictation.llm.".count))
        switch status {
        case "applied":
            return isChinese ? "LLM 已应用" : "LLM applied"
        case "unchanged":
            return isChinese ? "LLM 未改动" : "LLM unchanged"
        case "disabled":
            return isChinese ? "LLM 已关闭" : "LLM disabled"
        case "skipped-no-typing":
            return isChinese ? "LLM 跳过（非输入场景）" : "LLM skipped (non-typing)"
        case "skipped-structured-text":
            return isChinese ? "LLM 跳过（结构化文本）" : "LLM skipped (structured text)"
        case "skipped-numeric-dense":
            return isChinese ? "LLM 跳过（数字密集）" : "LLM skipped (numeric dense)"
        case "skipped-code-like":
            return isChinese ? "LLM 跳过（代码样式）" : "LLM skipped (code-like)"
        case "provider-unavailable":
            return isChinese ? "LLM 不可用" : "LLM unavailable"
        case "provider-failed":
            return isChinese ? "LLM 调用失败" : "LLM failed"
        case "rejected-language-drift":
            return isChinese ? "LLM 已拒绝（语言漂移）" : "LLM rejected (language drift)"
        case "rejected-protected-token":
            return isChinese ? "LLM 已拒绝（保护字段）" : "LLM rejected (protected tokens)"
        case "rejected-short-text-rewrite":
            return isChinese ? "LLM 已拒绝（短句改动过大）" : "LLM rejected (short text)"
        case "rejected-over-rewrite":
            return isChinese ? "LLM 已拒绝（改动过大）" : "LLM rejected (rewrite too large)"
        case "rejected-empty":
            return isChinese ? "LLM 已拒绝（空结果）" : "LLM rejected (empty output)"
        default:
            return nil
        }
    }

    private var dictationCandidateText: String? {
        guard event.kind == .dictation,
              let enhanced = event.enhancedContent?.replacingOccurrences(of: "\n", with: " "),
              !enhanced.isEmpty else {
            return nil
        }
        let committed = event.committedContent ?? event.content ?? ""
        guard !committed.isEmpty,
              enhanced != committed.replacingOccurrences(of: "\n", with: " ") else {
            return nil
        }
        let prefix = isChinese ? "候选：" : "Candidate: "
        return prefix + enhanced
    }

    private func copyEvent() {
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
    }

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            SpeechAppIcon(bundleID: event.bundleIdentifier)
                .frame(width: 22, height: 22)

            Text(event.appName)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .help(showsBundleHelp ? bundleText : "")
                .frame(minWidth: 84, idealWidth: 110, maxWidth: 140, alignment: .leading)

            Label(displayAction, systemImage: eventIcon)
                .font(.caption.weight(.semibold))
                .foregroundColor(eventTint)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(eventTint.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .frame(minWidth: 78, alignment: .leading)

            Group {
                if showsRewritePreview {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(rewriteBeforeText)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .lineLimit(2)
                            .truncationMode(.tail)
                        Text(rewriteAfterText)
                            .font(.caption)
                            .foregroundColor(previewColor)
                            .lineLimit(2)
                            .truncationMode(.tail)
                    }
                } else {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(previewText)
                            .font(.caption)
                            .foregroundColor(previewColor)
                            .lineLimit(1)
                            .truncationMode(.tail)
                        if let dictationStatusText {
                            Text(dictationStatusText)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                        if let dictationCandidateText {
                            Text(dictationCandidateText)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(timeText)
                .font(.caption2.monospacedDigit())
                .foregroundColor(.secondary)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .frame(minWidth: 58, alignment: .trailing)

            Button {
                copyEvent()
            } label: {
                Image(systemName: "doc.on.doc")
                    .font(.caption2)
                    .frame(width: 16, height: 16)
            }
            .buttonStyle(.borderless)
            .help(String(localized: "insights.copy_event"))
            .opacity(isHovering ? 1 : 0)
            .allowsHitTesting(isHovering)
            .accessibilityHidden(!isHovering)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color(nsColor: .controlBackgroundColor).opacity(isHovering ? 0.58 : 0.46))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
        }
        .contextMenu {
            Button(LocalizedStringKey("insights.copy_event")) {
                copyEvent()
            }
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
    @State private var draftText: String = ""
    @FocusState private var isFocused: Bool

    private var hasDraftContent: Bool {
        !draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func normalizedDraft(_ raw: String) -> String {
        raw.replacingOccurrences(of: "，", with: ",")
    }

    private func commitDraft() {
        let normalized = normalizedDraft(draftText)
        if draftText != normalized {
            draftText = normalized
        }
        if text != normalized {
            text = normalized
        }
    }

    private func performReset() {
        onReset()
        draftText = text
    }

    @ViewBuilder
    private var headerText: some View {
        if let subtitle, !subtitle.isEmpty {
            (
                Text(title)
                    .font(.body.weight(.medium))
                +
                Text("  ")
                +
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
            )
            .lineSpacing(1)
        } else {
            Text(title)
                .font(.body.weight(.medium))
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            headerText
                .fixedSize(horizontal: false, vertical: true)

            ZStack(alignment: .trailing) {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color(nsColor: .textBackgroundColor))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                    )

                TextField(
                    String(localized: "voice_lexicon.leave_empty"),
                    text: $draftText
                )
                .focused($isFocused)
                .textFieldStyle(.plain)
                .padding(.leading, 12)
                .padding(.trailing, (actionEnabled || hasDraftContent) ? 54 : 12)
                .padding(.vertical, 8)
                .onSubmit {
                    commitDraft()
                }

                Button(actionTitle) {
                    if requiresConfirmation {
                        showConfirm = true
                    } else {
                        performReset()
                    }
                }
                .buttonStyle(.borderless)
                .controlSize(.mini)
                .font(.caption.weight(.medium))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(Capsule())
                .padding(.trailing, 8)
                .disabled(!(actionEnabled || hasDraftContent))
                .opacity(isHovering && (actionEnabled || hasDraftContent) ? 1 : 0)
                .allowsHitTesting(isHovering && (actionEnabled || hasDraftContent))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
        .cornerRadius(10)
        .onAppear {
            draftText = text
        }
        .onChange(of: text) { _, newValue in
            guard !isFocused else { return }
            if draftText != newValue {
                draftText = newValue
            }
        }
        .onChange(of: isFocused) { _, focused in
            if !focused {
                commitDraft()
            }
        }
        .onHover { hovering in
            isHovering = hovering
        }
        .confirmationDialog(
            String(localized: "lexicon.clear_confirm_title"),
            isPresented: $showConfirm,
            titleVisibility: .visible
        ) {
            Button(String(localized: "lexicon.clear_confirm_action"), role: .destructive) {
                performReset()
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
        if bundleID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return AppLocalization.isChinese ? "全体 App" : "All Apps"
        }
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
            if bundleID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Image(systemName: "square.grid.2x2.fill")
                    .resizable()
                    .scaledToFit()
                    .foregroundColor(.secondary)
                    .padding(4)
            } else if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
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
    private var isChinese: Bool { AppLocalization.isChinese }

    private var headGestureToggleBinding: Binding<Bool> {
        Binding(
            get: { headManager.headGestureToggleEnabled },
            set: { headManager.headGestureToggleEnabled = $0 }
        )
    }

    private var hotZoneHeadInputBinding: Binding<Bool> {
        Binding(
            get: { headManager.headHotZoneHeadInputEnabled },
            set: { headManager.headHotZoneHeadInputEnabled = $0 }
        )
    }

    private var hotZoneMouseInputBinding: Binding<Bool> {
        Binding(
            get: { headManager.headHotZoneMouseInputEnabled },
            set: { headManager.headHotZoneMouseInputEnabled = $0 }
        )
    }

    private var hotZoneSizeBinding: Binding<Double> {
        Binding(
            get: { headManager.headHotZoneSizeScale },
            set: { headManager.headHotZoneSizeScale = $0 }
        )
    }

    private var hotZoneTriggerDurationBinding: Binding<Double> {
        Binding(
            get: { headManager.headHotZoneTriggerDuration },
            set: { headManager.headHotZoneTriggerDuration = $0 }
        )
    }

    var body: some View {
        SettingsPage(
            title: String(localized: "settings.page.head_gestures.title"),
            subtitle: String(localized: "settings.page.head_gestures.subtitle")
        ) {
            VStack(spacing: 16) {
                GlassCard(padding: 16) {
                    HStack(alignment: .top, spacing: 10) {
                        TransparencyModeIcon(size: 22, color: .secondary)

                        VStack(alignment: .leading, spacing: 4) {
                            Text(isChinese ? "启用热区触发" : "Enable Hot Zones")
                                .font(.subheadline.weight(.semibold))
                            Text(isChinese ? "四个边缘热区固定在当前显示器，移入即可触发。" : "Four edge zones stay on the active display and trigger on entry.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        Spacer(minLength: 12)

                        Toggle("", isOn: headGestureToggleBinding)
                            .labelsHidden()
                            .controlSize(.small)
                            .accessibilityLabel(Text(isChinese ? "启用热区触发" : "Enable Hot Zones"))
                            .accessibilityHint(Text(isChinese ? "启用基于屏幕边缘的热区触发" : "Enable edge hot zone triggers"))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                GlassCard(padding: 16) {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(alignment: .top, spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(isChinese ? "触发来源" : "Trigger Sources")
                                    .font(.subheadline.weight(.semibold))
                                Text(isChinese ? "头控开启时可用头控指针触发；关闭时可用鼠标触发。" : "Use the head cursor when tracking is on, or the mouse when it's off.")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer(minLength: 12)
                            VStack(alignment: .leading, spacing: 8) {
                                Toggle(isChinese ? "允许头控触发" : "Allow Head Tracking", isOn: hotZoneHeadInputBinding)
                                    .toggleStyle(.switch)
                                Toggle(isChinese ? "允许鼠标触发" : "Allow Mouse", isOn: hotZoneMouseInputBinding)
                                    .toggleStyle(.switch)
                            }
                            .controlSize(.small)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .disabled(!headManager.headGestureToggleEnabled)
                .opacity(headManager.headGestureToggleEnabled ? 1.0 : 0.55)

                GlassCard(padding: 16) {
                    HStack(alignment: .top, spacing: 18) {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text(isChinese ? "热区大小" : "Zone Size")
                                    .font(.subheadline.weight(.semibold))
                                Spacer()
                                Text("\(Int(headManager.headHotZoneSizeScale * 100))%")
                                    .font(.caption.weight(.semibold).monospacedDigit())
                                    .foregroundColor(.secondary)
                            }

                            Slider(value: hotZoneSizeBinding, in: 0.4...1.8, step: 0.05)
                                .controlSize(.small)

                            Text(isChinese ? "调大更容易进入热区，也更明显。" : "Larger zones are easier to enter and more visible.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        Divider()

                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text(isChinese ? "触发停留时间" : "Dwell Time")
                                    .font(.subheadline.weight(.semibold))
                                Spacer()
                                Text(String(format: isChinese ? "%.0f 毫秒" : "%.0f ms", headManager.headHotZoneTriggerDuration * 1000))
                                    .font(.caption.weight(.semibold).monospacedDigit())
                                    .foregroundColor(.secondary)
                            }

                            Slider(value: hotZoneTriggerDurationBinding, in: 0.08...1.2, step: 0.02)
                                .controlSize(.small)

                            Text(isChinese ? "进入热区后停留这么久才触发。调大可减少误触，调小更快。" : "How long to dwell before triggering. Increase to reduce false triggers.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .disabled(!headManager.headGestureToggleEnabled)
                .opacity(headManager.headGestureToggleEnabled ? 1.0 : 0.55)

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
