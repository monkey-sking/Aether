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
        case about
        case voiceTerms
        case voiceLexicon
        case voiceAppControls
        case voiceInsights
        case headGestures
        case shortcuts
    }

    var body: some View {
        NavigationSplitView {
            ZStack {
                LinearGradient(
                    colors: [
                        Color(nsColor: .windowBackgroundColor),
                        Color(nsColor: .underPageBackgroundColor)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )

                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(Color.white.opacity(0.035))
                    .overlay(
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .stroke(Color.white.opacity(0.04), lineWidth: 1)
                    )
                    .padding(.horizontal, 12)
                    .padding(.vertical, 14)

                VStack(spacing: 0) {
                    List(selection: $selection) {
                        Section {
                            NavigationLink(value: Panel.overview) {
                                Label(panelTitle(.overview), systemImage: panelSymbol(.overview))
                            }
                        } header: {
                            Text(LocalizedStringKey("main.section.workspace"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .textCase(nil)
                        }

                        Section {
                            NavigationLink(value: Panel.headGestures) {
                                Label(panelTitle(.headGestures), systemImage: panelSymbol(.headGestures))
                            }
                            NavigationLink(value: Panel.shortcuts) {
                                Label(panelTitle(.shortcuts), systemImage: panelSymbol(.shortcuts))
                            }
                        } header: {
                            Text(LocalizedStringKey("main.section.controls"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .textCase(nil)
                        }

                        Section {
                            NavigationLink(value: Panel.voiceAppControls) {
                                Label(panelTitle(.voiceAppControls), systemImage: panelSymbol(.voiceAppControls))
                            }
                            NavigationLink(value: Panel.voiceInsights) {
                                Label(panelTitle(.voiceInsights), systemImage: panelSymbol(.voiceInsights))
                            }
                            NavigationLink(value: Panel.voiceLexicon) {
                                Label(panelTitle(.voiceLexicon), systemImage: panelSymbol(.voiceLexicon))
                            }
                        } header: {
                            Text(LocalizedStringKey("main.section.voice"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .textCase(nil)
                        }

                        Section {
                            NavigationLink(value: Panel.about) {
                                Label(panelTitle(.about), systemImage: panelSymbol(.about))
                            }
                        } header: {
                            Text(LocalizedStringKey("main.section.app"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .textCase(nil)
                        }
                    }
                    .listStyle(.sidebar)
                    .scrollContentBackground(.hidden)
                    .environment(\.defaultMinListRowHeight, 44)
                    .padding(.horizontal, 16)
                    .padding(.top, 18)
                    .padding(.bottom, 18)
                }
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 250)
        } detail: {
            switch selection {
            case .overview:
                OverviewDashboardView()
            case .about:
                AboutCenterView()
            case .voiceTerms:
                OverviewDashboardView()
            case .voiceLexicon:
                InputSettingsView(section: .lexicon)
            case .voiceAppControls:
                InputSettingsView(section: .appControls)
            case .voiceInsights:
                InputSettingsView(section: .insights)
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
                subtitle: ""
            )
        )
        .onAppear {
            if selection == .voiceTerms {
                selection = .overview
            }
        }
    }

    private func panelTitle(_ panel: Panel) -> String {
        switch panel {
        case .overview:
            return String(localized: "main.panel.overview")
        case .about:
            return String(localized: "main.panel.about")
        case .voiceTerms:
            return NSLocalizedString("settings.section.term_corrections.page_title", comment: "")
        case .voiceLexicon:
            return NSLocalizedString("settings.section.lexicon.page_title", comment: "")
        case .voiceAppControls:
            return NSLocalizedString("settings.section.app_controls.page_title", comment: "")
        case .voiceInsights:
            return NSLocalizedString("settings.section.insights.page_title", comment: "")
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
        case .about:
            return "info.circle"
        case .voiceTerms:
            return "text.magnifyingglass"
        case .voiceLexicon:
            return "text.badge.star"
        case .voiceAppControls:
            return "app.badge"
        case .voiceInsights:
            return "chart.bar.xaxis"
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
        if !window.titlebarAccessoryViewControllers.contains(where: { $0 is SidebarToggleAccessoryViewController }) {
            let accessory = SidebarToggleAccessoryViewController()
            accessory.layoutAttribute = .left
            window.addTitlebarAccessoryViewController(accessory)
        }
    }
}

private final class SidebarToggleAccessoryViewController: NSTitlebarAccessoryViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        layoutAttribute = .left

        let containerView = NSView(frame: NSRect(x: 0, y: 0, width: 42, height: 40))
        view = containerView

        let configuration = NSImage.SymbolConfiguration(pointSize: 15, weight: .semibold)
            .applying(NSImage.SymbolConfiguration(scale: .large))
        let image = NSImage(systemSymbolName: "sidebar.left", accessibilityDescription: "Toggle Sidebar")
            ?? NSImage(systemSymbolName: "sidebar.leading", accessibilityDescription: "Toggle Sidebar")
            ?? NSImage()
        let configuredImage = image.withSymbolConfiguration(configuration) ?? image

        let button = NSButton(image: configuredImage, target: self, action: #selector(toggleSidebar))
        button.isBordered = false
        button.bezelStyle = .texturedRounded
        button.controlSize = .large
        button.imageScaling = .scaleProportionallyDown
        button.contentTintColor = .labelColor
        button.translatesAutoresizingMaskIntoConstraints = false

        containerView.addSubview(button)

        NSLayoutConstraint.activate([
            button.centerYAnchor.constraint(equalTo: containerView.centerYAnchor),
            button.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 9),
            button.widthAnchor.constraint(equalToConstant: 30),
            button.heightAnchor.constraint(equalToConstant: 26)
        ])
    }

    @objc private func toggleSidebar(_ sender: Any?) {
        NSApp.keyWindow?.firstResponder?.tryToPerform(#selector(NSSplitViewController.toggleSidebar(_:)), with: sender)
    }
}

private struct OverviewDashboardView: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject private var headManager = HeadMotionManager.shared
    @State private var readinessExpanded: Bool = false
    private var isChinese: Bool { AppLocalization.isChinese }

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

    private var mouseIdlePauseMinutesBinding: Binding<String> {
        Binding(
            get: { String(headManager.mouseIdlePauseMinutes) },
            set: { newValue in
                guard let minutes = Int(newValue) else { return }
                headManager.mouseIdlePauseMinutes = minutes
            }
        )
    }

    private var mouseIdlePauseOptions: [DashboardFixedPopUpOption] {
        stride(from: 15, through: 60, by: 5).map { minutes in
            let title = isChinese ? "\(minutes) 分钟" : "\(minutes) min"
            return DashboardFixedPopUpOption(id: String(minutes), title: title)
        }
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
                EmptyView()
            }
        ) {
            Text(isChinese ? "准备度" : "Readiness")
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.secondary)

            OverviewReadinessCard(
                setupItems: setupItems,
                isCollapsed: readinessCanCollapse && !readinessExpanded,
                canCollapse: readinessCanCollapse,
                onToggle: { readinessExpanded.toggle() }
            )

            Text(isChinese ? "全局行为" : "Global Behavior")
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.secondary)

            GlassCard {
                VStack(spacing: 10) {
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(isChinese ? "鼠标静止后暂停整个 App" : "Pause App After Mouse Idle")
                                .font(AetherUI.bodyFont)
                            Text(isChinese ? "暂停头控、语音与快捷键，鼠标移动后恢复。" : "Pauses head tracking, voice, and shortcuts; resumes on movement.")
                                .font(AetherUI.captionFont)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                                .truncationMode(.tail)
                                .allowsTightening(true)
                                .minimumScaleFactor(0.88)
                        }
                        .layoutPriority(1)
                        Spacer()
                        DashboardFixedWidthPopUpMenu(
                            options: mouseIdlePauseOptions,
                            selection: mouseIdlePauseMinutesBinding
                        )
                    }

                    Divider()

                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(String(localized: "settings.app_language.title"))
                                .font(AetherUI.bodyFont)
                            Text(String(localized: "settings.app_language.restart_hint"))
                                .font(AetherUI.captionFont)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                                .truncationMode(.tail)
                                .allowsTightening(true)
                                .minimumScaleFactor(0.88)
                        }
                        .layoutPriority(1)
                        Spacer()
                        AppLanguageHeader(compact: true)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 11)
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.72))
                .cornerRadius(12)
            }

            Text(isChinese ? "核心功能" : "Core Features")
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.secondary)

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
                    VoiceBasicsTile(
                        mode: $appState.voiceActivationMode
                    )
                }

                GlassCard {
                    VoiceInputTile()
                }

                GlassCard {
                    VoiceControlTile()
                }
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
    @EnvironmentObject private var appState: AppState
    let setupItems: [OverviewSetupItem]
    let isCollapsed: Bool
    let canCollapse: Bool
    let onToggle: () -> Void

    private var realInputDevices: [AudioInputDevice] {
        appState.availableInputDevices.filter { $0.id != 0 }
    }

    private var hasMicrophoneDevice: Bool {
        !realInputDevices.isEmpty
    }

    private var readinessTotalCount: Int {
        setupItems.count + 1
    }

    private var readyCount: Int {
        setupItems.filter(\.isReady).count + (hasMicrophoneDevice ? 1 : 0)
    }

    private var microphoneButtonTitle: String {
        guard hasMicrophoneDevice else {
            return String(localized: "settings.no_microphone")
        }
        guard let selected = appState.availableInputDevices.first(where: { $0.id == appState.selectedInputDeviceID }) else {
            return String(localized: "settings.default_device")
        }
        return selected.name
    }

    private var microphoneRowDetail: String {
        hasMicrophoneDevice
            ? microphoneButtonTitle
            : String(localized: "speech.no_mic_detected")
    }

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(LocalizedStringKey("main.readiness.title"))
                            .font(.headline)
                        Text(String(localized: "main.readiness.subtitle"))
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(2)
                            .truncationMode(.tail)
                            .minimumScaleFactor(0.9)
                    }
                    Spacer()
                    OverviewStateTag(
                        title: String(format: String(localized: "main.readiness.ready_count_fmt"), readyCount, readinessTotalCount),
                        tint: readyCount == readinessTotalCount ? .green : .orange
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
                                        .buttonStyle(.bordered)
                                }
                            }
                            .padding(12)
                            .background(Color(nsColor: .controlBackgroundColor))
                            .cornerRadius(12)
                        }

                        readinessMenuRow(
                            title: String(localized: "settings.microphone"),
                            value: microphoneButtonTitle,
                            detail: microphoneRowDetail,
                            systemImage: "mic.fill",
                            isReady: hasMicrophoneDevice
                        ) {
                            if appState.availableInputDevices.isEmpty {
                                Text(L10n.settingsNoMicrophone)
                            } else {
                                ForEach(appState.availableInputDevices) { device in
                                    Button(device.name) {
                                        appState.selectedInputDeviceID = device.id
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func readinessMenuRow<Content: View>(
        title: String,
        value: String,
        detail: String,
        systemImage: String,
        isReady: Bool,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .frame(width: 20)
                .foregroundColor(isReady ? .green : .orange)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                Text(detail)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            if isReady {
                Menu {
                    content()
                } label: {
                    HStack(spacing: 6) {
                        Text(value)
                            .lineLimit(1)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.caption2)
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color(nsColor: .windowBackgroundColor).opacity(0.9))
                    .cornerRadius(10)
                }
                .menuStyle(.borderlessButton)
            } else {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .foregroundColor(.orange)
                    Text(value)
                        .lineLimit(1)
                }
                .font(.caption.weight(.medium))
                .foregroundColor(.orange)
            }
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(12)
    }
}

private struct OverviewToggleTile: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let tint: Color
    @Binding var isOn: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
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
                    .controlSize(.small)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 148, alignment: .topLeading)
    }
}

private struct PointerControlTile: View {
    @ObservedObject private var headManager = HeadMotionManager.shared
    let subtitle: String
    @Binding var isOn: Bool
    @Binding var autoStartOnConnect: Bool
    @Binding var showPostureGuide: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
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
                    .controlSize(.small)
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

            if !headManager.attitudeText.isEmpty {
                Text(headManager.attitudeText)
                    .font(AetherUI.captionFont)
                    .foregroundColor(headManager.isTracking ? .secondary : .orange)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
        .frame(maxWidth: .infinity, minHeight: AetherUI.dashboardCompactTileMinHeight, alignment: .topLeading)
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
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .allowsTightening(true)
                    .minimumScaleFactor(0.88)
            }
            .layoutPriority(1)
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

private struct DashboardFixedPopUpOption: Equatable {
    let id: String
    let title: String
}

private struct DashboardFixedWidthPopUpMenu: NSViewRepresentable {
    var options: [DashboardFixedPopUpOption]
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
        var parent: DashboardFixedWidthPopUpMenu

        init(parent: DashboardFixedWidthPopUpMenu) {
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

private struct VoiceBasicsTile: View {
    @EnvironmentObject private var appState: AppState
    @Binding var mode: AppState.VoiceActivationMode

    private let supportedVoiceLocaleIDs = [
        "zh-CN", "en-US", "ja-JP", "ko-KR", "fr-FR", "de-DE", "es-ES"
    ]

    private var selectedVoiceLocaleIDs: [String] {
        if appState.voiceService.speechLanguageMode == .bilingual {
            return [appState.voiceService.primaryLocaleIdentifier, appState.voiceService.secondaryLocaleIdentifier]
        }
        return [appState.voiceService.primaryLocaleIdentifier]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            DashboardTileHeader(
                title: String(localized: "main.voice_basics.title"),
                subtitle: String(localized: "main.voice_basics.subtitle"),
                systemImage: "waveform.badge.mic",
                iconBackground: Color.blue.opacity(0.18),
                iconForeground: .blue
            )

            VStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .center, spacing: 8) {
                        Text(L10n.settingsSpeechLanguage)
                            .font(AetherUI.bodyFont)
                        Spacer()
                        compactSelectionMenu(
                            value: selectedVoiceLocaleIDs.map(localeTitle(for:)).joined(separator: " + ")
                        ) {
                            ForEach(supportedVoiceLocaleIDs, id: \.self) { localeID in
                                Button {
                                    toggleVoiceLocaleSelection(localeID)
                                } label: {
                                    HStack {
                                        Text(localeTitle(for: localeID))
                                        Spacer()
                                        if selectedVoiceLocaleIDs.contains(localeID) {
                                            Image(systemName: "checkmark")
                                        }
                                    }
                                }
                                .disabled(selectedVoiceLocaleIDs.count == 1 && selectedVoiceLocaleIDs.contains(localeID))
                            }
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 11)
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.72))
                .cornerRadius(12)

                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .center, spacing: 8) {
                        Label(String(localized: "main.voice_activation.title"), systemImage: "bolt.badge.waveform")
                            .font(AetherUI.bodyFont)
                        Spacer()
                    }

                    HStack(spacing: 8) {
                        activationModeButton(.pushToTalk)
                        activationModeButton(.wakeWord)
                        activationModeButton(.handsFree)
                    }

                    Text(selectedModeDescription)
                        .font(AetherUI.captionFont)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .allowsTightening(true)
                        .minimumScaleFactor(0.88)
                        .frame(height: 18, alignment: .leading)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 11)
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.72))
                .cornerRadius(12)

            }
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

    private func localeTitle(for localeIdentifier: String) -> String {
        switch localeIdentifier {
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

    private func toggleVoiceLocaleSelection(_ localeID: String) {
        var selection = selectedVoiceLocaleIDs

        if let index = selection.firstIndex(of: localeID) {
            guard selection.count > 1 else { return }
            selection.remove(at: index)
        } else {
            guard selection.count < 2 else {
                selection = [selection.last ?? selection.first ?? appState.voiceService.primaryLocaleIdentifier, localeID]
                applyVoiceLocaleSelection(selection)
                return
            }
            selection.append(localeID)
        }

        applyVoiceLocaleSelection(selection)
    }

    private func applyVoiceLocaleSelection(_ selection: [String]) {
        guard let primary = selection.first else { return }
        appState.voiceService.followsSystemLanguage = false
        appState.voiceService.primaryLocaleIdentifier = primary

        if selection.count > 1, let secondary = selection.last, secondary != primary {
            appState.voiceService.speechLanguageMode = .bilingual
            appState.voiceService.secondaryLocaleIdentifier = secondary
        } else {
            appState.voiceService.speechLanguageMode = .single
        }
    }

    @ViewBuilder
    private func settingsMenuRow<Content: View>(
        title: String,
        value: String,
        systemImage: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(spacing: 10) {
            Label(title, systemImage: systemImage)
                .font(AetherUI.bodyFont)
            Spacer()
            Menu {
                content()
            } label: {
                HStack(spacing: 6) {
                    Text(value)
                        .lineLimit(1)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption2)
                }
                .font(AetherUI.captionFont)
                .foregroundColor(.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color(nsColor: .windowBackgroundColor).opacity(0.9))
                .cornerRadius(10)
            }
            .menuStyle(.borderlessButton)
        }
    }

    @ViewBuilder
    private func compactSelectionMenu<Content: View>(
        value: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        Menu {
            content()
        } label: {
            HStack(spacing: 8) {
                Text(value)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2)
            }
            .font(AetherUI.bodyFont)
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(Color(nsColor: .windowBackgroundColor).opacity(0.9))
            .cornerRadius(10)
        }
        .menuStyle(.borderlessButton)
    }

    @ViewBuilder
    private func inlineToggle(
        title: String,
        subtitle: String,
        isOn: Binding<Bool>
    ) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(AetherUI.bodyFont)
                Text(subtitle)
                    .font(AetherUI.captionFont)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .allowsTightening(true)
                    .minimumScaleFactor(0.88)
            }
            .layoutPriority(1)
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

    @ViewBuilder
    private func activationModeButton(_ item: AppState.VoiceActivationMode) -> some View {
        Button {
            mode = item
        } label: {
            Text(shortLabel(for: item))
                .font(.subheadline.weight(.semibold))
                .foregroundColor(mode == item ? .white : .primary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(
                    mode == item
                        ? Color.accentColor
                        : Color(nsColor: .windowBackgroundColor).opacity(0.98)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(
                            mode == item
                                ? Color.accentColor.opacity(0.95)
                                : Color.primary.opacity(0.14),
                            lineWidth: 1
                        )
                )
                .shadow(
                    color: mode == item ? Color.accentColor.opacity(0.22) : Color.black.opacity(0.08),
                    radius: mode == item ? 8 : 3,
                    x: 0,
                    y: 1
                )
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var selectedModeDescription: String {
        switch mode {
        case .pushToTalk:
            return String(
                format: String(localized: "main.voice_mode.push_to_talk.detail_fmt"),
                appState.voicePTTBinding.displayString
            )
        case .wakeWord:
            return String(localized: "main.voice_mode.wake_word.detail")
        case .handsFree:
            return String(localized: "main.voice_mode.hands_free.detail")
        }
    }
}

private struct VoiceInputTile: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VoiceFeatureToggleTile(
            title: String(localized: "main.voice_input.title"),
            subtitle: String(localized: "main.voice_input.subtitle"),
            systemImage: "text.cursor",
            iconBackground: appState.isVoiceInputEnabled ? Color.green.opacity(0.18) : Color.gray.opacity(0.16),
            iconForeground: appState.isVoiceInputEnabled ? .green : .secondary,
            isOn: $appState.isVoiceInputEnabled,
            autoEnableTitle: String(localized: "main.voice_input.auto_enable.title"),
            autoEnableSubtitle: String(localized: "main.voice_input.auto_enable.subtitle"),
            autoEnableOnHeadset: $appState.autoEnableVoiceInputOnHeadset
        )
    }
}

private struct VoiceControlTile: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VoiceFeatureToggleTile(
            title: String(localized: "main.voice_control.title"),
            subtitle: String(localized: "main.voice_control.subtitle"),
            systemImage: "command",
            iconBackground: appState.isVoiceControlEnabled ? Color.orange.opacity(0.18) : Color.gray.opacity(0.16),
            iconForeground: appState.isVoiceControlEnabled ? .orange : .secondary,
            isOn: $appState.isVoiceControlEnabled,
            autoEnableTitle: String(localized: "main.voice_control.auto_enable.title"),
            autoEnableSubtitle: String(localized: "main.voice_control.auto_enable.subtitle"),
            autoEnableOnHeadset: $appState.autoEnableVoiceControlOnHeadset
        )
    }
}

private struct VoiceFeatureToggleTile: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let iconBackground: Color
    let iconForeground: Color
    @Binding var isOn: Bool
    let autoEnableTitle: String
    let autoEnableSubtitle: String
    @Binding var autoEnableOnHeadset: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 16) {
                DashboardTileHeader(
                    title: title,
                    subtitle: subtitle,
                    systemImage: systemImage,
                    iconBackground: iconBackground,
                    iconForeground: iconForeground
                )
                Toggle("", isOn: $isOn)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
            }

            inlineToggle(
                title: autoEnableTitle,
                subtitle: autoEnableSubtitle,
                isOn: $autoEnableOnHeadset
            )
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
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .allowsTightening(true)
                    .minimumScaleFactor(0.88)
            }
            .layoutPriority(1)
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
    var compact: Bool = false

    var body: some View {
        if compact {
            Menu {
                ForEach(AppLanguageMode.allCases) { mode in
                    Button(AppLocalization.localizedString(mode.localizedTitleKey)) {
                        appState.appLanguageMode = mode
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "globe")
                        .foregroundColor(.secondary)
                    Text(AppLocalization.localizedString(appState.appLanguageMode.localizedTitleKey))
                        .foregroundColor(.secondary)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            .menuStyle(.borderlessButton)
            .controlSize(.small)
        } else {
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
