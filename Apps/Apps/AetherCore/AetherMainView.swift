import AppKit
import SwiftUI

private struct OverviewSetupItem: Identifiable {
    let id: String
    let icon: String
    let title: String
    let detail: String
    let isReady: Bool
    let actionTitle: String?
    let action: (() -> Void)?
}

struct AetherMainView: View {
    @State private var selection: Panel? = .overview

    enum Panel: Hashable {
        case overview
        case voiceBasics
        case voiceTerms
        case voiceLexicon
        case voiceAppControls
        case voiceInsights
        case pointer
        case headGestures
        case shortcuts
    }

    private var currentPanel: Panel {
        selection ?? .overview
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Section {
                    NavigationLink(value: Panel.overview) {
                        panelLabel(.overview)
                    }
                } header: {
                    SidebarSectionHeader(title: LocalizedStringKey("main.section.workspace"))
                }

                Section {
                    NavigationLink(value: Panel.voiceBasics) {
                        panelLabel(.voiceBasics)
                    }
                    NavigationLink(value: Panel.voiceTerms) {
                        panelLabel(.voiceTerms)
                    }
                    NavigationLink(value: Panel.voiceLexicon) {
                        panelLabel(.voiceLexicon)
                    }
                    NavigationLink(value: Panel.voiceAppControls) {
                        panelLabel(.voiceAppControls)
                    }
                    NavigationLink(value: Panel.voiceInsights) {
                        panelLabel(.voiceInsights)
                    }
                } header: {
                    SidebarSectionHeader(title: LocalizedStringKey("main.section.voice"))
                }

                Section {
                    NavigationLink(value: Panel.pointer) {
                        panelLabel(.pointer)
                    }
                    NavigationLink(value: Panel.headGestures) {
                        panelLabel(.headGestures)
                    }
                    NavigationLink(value: Panel.shortcuts) {
                        panelLabel(.shortcuts)
                    }
                } header: {
                    SidebarSectionHeader(title: LocalizedStringKey("main.section.controls"))
                }

            }
            .listStyle(.sidebar)
            .environment(\.defaultMinListRowHeight, 46)
            .navigationSplitViewColumnWidth(min: 220, ideal: 240, max: 280)
        } detail: {
            switch selection {
            case .overview:
                OverviewDashboardView()
            case .voiceBasics:
                InputSettingsView(section: .basics)
            case .voiceTerms:
                InputSettingsView(section: .termCorrections)
            case .voiceLexicon:
                InputSettingsView(section: .lexicon)
            case .voiceAppControls:
                InputSettingsView(section: .appControls)
            case .voiceInsights:
                InputSettingsView(section: .insights)
            case .pointer:
                OutputSettingsView()
            case .headGestures:
                HeadGestureSettingsView()
            case .shortcuts:
                ShortcutsSettingsView()
            case .none:
                Text(L10n.selectItem)
            }
        }
        .navigationSplitViewStyle(.balanced)
        .background(
            StandardWindowConfigurator(
                title: "Aether",
                subtitle: panelTitle(currentPanel)
            )
        )
    }

    @ViewBuilder
    private func panelLabel(_ panel: Panel) -> some View {
        if panel == .headGestures {
            SidebarItemLabel(title: panelTitle(panel)) {
                TransparencyModeIcon(size: AetherUI.sidebarIconSize, color: .primary)
            }
        } else {
            SidebarItemLabel(
                title: panelTitle(panel),
                systemImage: panelSymbol(panel)
            )
        }
    }

    private func panelTitle(_ panel: Panel) -> String {
        switch panel {
        case .overview:
            return String(localized: "main.panel.overview")
        case .voiceBasics:
            return NSLocalizedString("settings.section.basics.page_title", comment: "")
        case .voiceTerms:
            return NSLocalizedString("settings.section.term_corrections.page_title", comment: "")
        case .voiceLexicon:
            return NSLocalizedString("settings.section.lexicon.page_title", comment: "")
        case .voiceAppControls:
            return NSLocalizedString("settings.section.app_controls.page_title", comment: "")
        case .voiceInsights:
            return NSLocalizedString("settings.section.insights.page_title", comment: "")
        case .pointer:
            return String(localized: "main.panel.pointer")
        case .headGestures:
            return String(localized: "main.panel.head_gestures")
        case .shortcuts:
            return String(localized: "main.panel.shortcuts")
        }
    }

    private func panelSymbol(_ panel: Panel) -> String {
        switch panel {
        case .overview:
            return "square.grid.2x2.fill"
        case .voiceBasics:
            return "mic.fill"
        case .voiceTerms:
            return "text.magnifyingglass"
        case .voiceLexicon:
            return "text.badge.star"
        case .voiceAppControls:
            return "app.badge"
        case .voiceInsights:
            return "chart.bar.xaxis"
        case .pointer:
            return "cursorarrow.and.square.on.square.dashed"
        case .headGestures:
            return "person.crop.circle"
        case .shortcuts:
            return "keyboard"
        }
    }
}

private struct StandardWindowConfigurator: NSViewRepresentable {
    let title: String
    let subtitle: String

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async {
            applyConfiguration(for: view.window)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            applyConfiguration(for: nsView.window)
        }
    }

    private func applyConfiguration(for window: NSWindow?) {
        guard let window else { return }
        window.identifier = NSUserInterfaceItemIdentifier("AetherMainWindow")
        window.title = title
        window.subtitle = subtitle
        window.titleVisibility = .visible
        window.titlebarAppearsTransparent = false
        window.toolbarStyle = .unified
        if #available(macOS 11.0, *) {
            window.titlebarSeparatorStyle = .automatic
        }
    }
}

private struct OverviewDashboardView: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject private var headManager = HeadMotionManager.shared
    @State private var readinessExpanded: Bool = false

    private let columns = [
        GridItem(.flexible(minimum: 280), spacing: 16),
        GridItem(.flexible(minimum: 280), spacing: 16)
    ]

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

    private var setupItems: [OverviewSetupItem] {
        [
            OverviewSetupItem(
                id: "accessibility",
                icon: "hand.raised.fill",
                title: String(localized: "permissions.accessibility"),
                detail: appState.accessibilityTrusted
                    ? String(localized: "main.permission.accessibility.detail.ready")
                    : String(localized: "main.permission.accessibility.detail.missing"),
                isReady: appState.accessibilityTrusted,
                actionTitle: appState.accessibilityTrusted ? nil : String(localized: "main.action.enable"),
                action: appState.accessibilityTrusted ? nil : { appState.requestAccessibilityGuided() }
            ),
            OverviewSetupItem(
                id: "microphone",
                icon: "mic.fill",
                title: String(localized: "permissions.microphone"),
                detail: appState.microphoneAuthorized
                    ? String(localized: "main.permission.microphone.detail.ready")
                    : String(localized: "main.permission.microphone.detail.missing"),
                isReady: appState.microphoneAuthorized,
                actionTitle: appState.microphoneAuthorized ? nil : String(localized: "main.action.enable"),
                action: appState.microphoneAuthorized ? nil : { appState.requestMicrophoneGuided() }
            ),
            OverviewSetupItem(
                id: "speech",
                icon: "waveform",
                title: String(localized: "permissions.speech"),
                detail: appState.speechAuthorized
                    ? String(localized: "main.permission.speech.detail.ready")
                    : String(localized: "main.permission.speech.detail.missing"),
                isReady: appState.speechAuthorized,
                actionTitle: appState.speechAuthorized ? nil : String(localized: "main.action.enable"),
                action: appState.speechAuthorized ? nil : { appState.requestSpeechGuided() }
            )
        ]
    }

    private var blockingIssuesCount: Int {
        setupItems.filter { !$0.isReady }.count
    }

    private var readinessCanCollapse: Bool {
        blockingIssuesCount == 0
    }

    private var overviewSubtitle: String {
        if blockingIssuesCount == 0 {
            return String(localized: "main.overview.subtitle.ready")
        }
        return String(format: String(localized: "main.overview.subtitle.pending_fmt"), blockingIssuesCount)
    }

    var body: some View {
        SettingsPage(
            title: String(localized: "main.overview.title"),
            subtitle: overviewSubtitle,
            headerTrailing: {
                AppLanguageHeader()
            }
        ) {
            OverviewReadinessCard(
                setupItems: setupItems,
                isCollapsed: readinessCanCollapse && !readinessExpanded,
                canCollapse: readinessCanCollapse,
                onToggle: { readinessExpanded.toggle() }
            )

            LazyVGrid(columns: columns, spacing: 16) {
                GlassCard {
                    PointerControlTile(
                        subtitle: headManager.isTracking
                            ? String(localized: "main.pointer.subtitle.active")
                            : String(localized: "main.pointer.subtitle.idle"),
                        isOn: trackingBinding,
                        autoStartOnConnect: autoStartTrackingBinding,
                        showPostureGuide: postureGuideBinding
                    )
                }

                GlassCard {
                    VoiceModeTile(
                        mode: $appState.voiceActivationMode
                    )
                }
            }

            HStack {
                Spacer()
                Text(appState.appVersionDisplay)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .textSelection(.enabled)
            }
        }
        .onAppear {
            readinessExpanded = !readinessCanCollapse
        }
        .onChange(of: readinessCanCollapse) { _, canCollapse in
            readinessExpanded = !canCollapse
        }
    }
}

private struct OverviewReadinessCard: View {
    let setupItems: [OverviewSetupItem]
    let isCollapsed: Bool
    let canCollapse: Bool
    let onToggle: () -> Void

    private var readyCount: Int {
        setupItems.filter(\.isReady).count
    }

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(LocalizedStringKey("main.readiness.title"))
                            .font(.headline)
                        Text(LocalizedStringKey("main.readiness.subtitle"))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    OverviewStateTag(
                        title: String(format: String(localized: "main.readiness.ready_count_fmt"), readyCount, setupItems.count),
                        tint: readyCount == setupItems.count ? .green : .orange
                    )
                    if canCollapse {
                        Button(action: onToggle) {
                            Image(systemName: isCollapsed ? "chevron.down" : "chevron.up")
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }

                if isCollapsed {
                    Text(LocalizedStringKey("main.readiness.collapsed"))
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 2)
                } else {
                    VStack(spacing: 10) {
                        ForEach(setupItems) { item in
                            HStack(spacing: 12) {
                                Image(systemName: item.icon)
                                    .frame(width: 20)
                                    .foregroundColor(item.isReady ? .green : .orange)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.title)
                                        .font(.subheadline.weight(.medium))
                                    Text(item.detail)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }

                                Spacer()

                                if item.isReady {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.green)
                                } else if let actionTitle = item.actionTitle, let action = item.action {
                                    Button(actionTitle, action: action)
                                        .controlSize(.small)
                                }
                            }
                            .padding(12)
                            .background(Color(nsColor: .controlBackgroundColor))
                            .cornerRadius(12)
                        }

                    }
                }
            }
        }
    }
}

private struct OverviewToggleTile: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let tint: Color
    @Binding var isOn: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                ZStack {
                    Circle()
                        .fill(isOn ? tint : Color.gray.opacity(0.16))
                        .frame(width: 40, height: 40)
                    Image(systemName: systemImage)
                        .foregroundColor(isOn ? .white : .secondary)
                }
                Spacer()
                Toggle("", isOn: $isOn)
                    .labelsHidden()
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 148, alignment: .topLeading)
    }
}

private struct PointerControlTile: View {
    let subtitle: String
    @Binding var isOn: Bool
    @Binding var autoStartOnConnect: Bool
    @Binding var showPostureGuide: Bool

    private var isChinese: Bool {
        AppLocalization.isChinese
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 16) {
                DashboardTileHeader(
                    title: String(localized: "main.pointer.title"),
                    subtitle: subtitle,
                    systemImage: "cursorarrow.and.square.on.square.dashed",
                    iconBackground: isOn ? Color.green : Color.gray.opacity(0.16),
                    iconForeground: isOn ? .white : .secondary
                )
                Toggle("", isOn: $isOn)
                    .labelsHidden()
                    .toggleStyle(.switch)
            }

            VStack(spacing: 10) {
                inlineToggle(
                    title: String(localized: "main.pointer.auto_start.title"),
                    subtitle: String(localized: "main.pointer.auto_start.subtitle"),
                    isOn: $autoStartOnConnect
                )
                inlineToggle(
                    title: String(localized: "main.pointer.posture_guide.title"),
                    subtitle: String(localized: "main.pointer.posture_guide.subtitle"),
                    isOn: $showPostureGuide
                )
                .disabled(!autoStartOnConnect)
                .opacity(autoStartOnConnect ? 1 : 0.55)
            }

            Text(LocalizedStringKey("main.pointer.footnote"))
                .font(AetherUI.captionFont)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: AetherUI.dashboardTileMinHeight, alignment: .topLeading)
    }

    @ViewBuilder
    private func inlineToggle(title: String, subtitle: String, isOn: Binding<Bool>) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(AetherUI.bodyFont)
                Text(subtitle)
                    .font(AetherUI.captionFont)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Toggle("", isOn: isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.72))
        .cornerRadius(12)
    }
}

private struct VoiceModeTile: View {
    @Binding var mode: AppState.VoiceActivationMode

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            DashboardTileHeader(
                title: String(localized: "main.voice_activation.title"),
                subtitle: String(localized: "main.voice_activation.subtitle"),
                systemImage: "waveform.badge.mic",
                iconBackground: Color.blue.opacity(0.18),
                iconForeground: .blue
            )

            Picker("", selection: $mode) {
                ForEach(AppState.VoiceActivationMode.allCases, id: \.self) { item in
                    Text(shortLabel(for: item)).tag(item)
                }
            }
            .pickerStyle(.segmented)

            Text(selectedModeDescription)
                .font(AetherUI.captionFont)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, minHeight: AetherUI.dashboardTileMinHeight, alignment: .topLeading)
    }

    private func shortLabel(for mode: AppState.VoiceActivationMode) -> String {
        switch mode {
        case .pushToTalk:
            return String(localized: "main.voice_mode.push_to_talk.short")
        case .wakeWord:
            return String(localized: "main.voice_mode.wake_word.short")
        case .handsFree:
            return String(localized: "main.voice_mode.hands_free.short")
        }
    }

    private var selectedModeDescription: String {
        switch mode {
        case .pushToTalk:
            return String(localized: "main.voice_mode.push_to_talk.detail")
        case .wakeWord:
            return String(localized: "main.voice_mode.wake_word.detail")
        case .handsFree:
            return String(localized: "main.voice_mode.hands_free.detail")
        }
    }
}

private struct AppLanguageTile: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(String(localized: "settings.app_language.title"), systemImage: "globe")
                    .font(.headline)
                Spacer()
                Picker("", selection: $appState.appLanguageMode) {
                    ForEach(AppLanguageMode.allCases) { mode in
                        Text(AppLocalization.localizedString(mode.localizedTitleKey))
                            .tag(mode)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
            }

            Text(String(localized: "settings.app_language.subtitle"))
                .font(.caption)
                .foregroundColor(.secondary)

            Text(String(localized: "settings.app_language.restart_hint"))
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: AetherUI.dashboardTileMinHeight, alignment: .topLeading)
    }
}

private struct AppLanguageHeader: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(alignment: .trailing, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "globe")
                    .foregroundColor(.secondary)
                Text(String(localized: "settings.app_language.title"))
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.secondary)
            }

            Picker("", selection: $appState.appLanguageMode) {
                ForEach(AppLanguageMode.allCases) { mode in
                    Text(AppLocalization.localizedString(mode.localizedTitleKey))
                        .tag(mode)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)

            Text(String(localized: "settings.app_language.restart_hint"))
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }
}

private struct OverviewStateTag: View {
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
