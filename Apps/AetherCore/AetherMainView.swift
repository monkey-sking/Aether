import AppKit
import ServiceManagement
import SwiftUI

private extension Notification.Name {
    static let aetherToggleMainSidebar = Notification.Name("AetherToggleMainSidebar")
}

private enum SidebarMetrics {
    static let itemFont = NSFont.systemFont(ofSize: 16, weight: .semibold)
    static let headerFont = NSFont.systemFont(ofSize: 12.5, weight: .bold)

    static func preferredWidth() -> CGFloat {
        let itemTitles = [
            String(localized: "main.panel.overview"),
            String(localized: "main.panel.head_gestures"),
            String(localized: "main.panel.shortcuts"),
            String(localized: "settings.section.app_controls.page_title"),
            String(localized: "settings.section.lexicon.page_title"),
            String(localized: "settings.section.insights.page_title"),
            String(localized: "main.panel.about")
        ]

        let widestItem = itemTitles
            .map { ($0 as NSString).size(withAttributes: [.font: itemFont]).width }
            .max() ?? 0

        let widestHeader = [
            String(localized: "main.section.workspace"),
            String(localized: "main.section.controls"),
            String(localized: "main.section.voice"),
            String(localized: "main.section.app")
        ]
        .map { ($0 as NSString).size(withAttributes: [.font: headerFont]).width }
        .max() ?? 0

        let itemWidth = widestItem + 72
        let headerWidth = widestHeader + 32
        return min(max(196, ceil(max(itemWidth, headerWidth))), 300)
    }
}

private struct OverviewSetupItem: Identifiable {
    let id: String
    let icon: String
    let title: String
    let detail: String
    let isReady: Bool
    let actionTitle: String?
    let action: (() -> Void)?
}

@MainActor
private final class LaunchAtLoginManager: ObservableObject {
    @Published private(set) var isRequested: Bool = false
    @Published private(set) var isEnabled: Bool = false
    @Published private(set) var requiresApproval: Bool = false
    @Published private(set) var isBusy: Bool = false

    private let service = SMAppService.mainApp

    init() {
        refreshStatus()
    }

    func refreshStatus() {
        applyStatus(service.status)
    }

    func setEnabled(_ enabled: Bool) {
        guard !isBusy else { return }
        isBusy = true
        defer {
            isBusy = false
            refreshStatus()
        }

        do {
            if enabled {
                try service.register()
            } else {
                try service.unregister()
            }
        } catch {
            GlobalLogger.log(
                "LaunchAtLogin toggle failed enabled=\(enabled) status=\(service.status.rawValue) error=\(error.localizedDescription)",
                log: GlobalLogger.lifecycle,
                type: .error
            )
            showFailureHUD(enabled: enabled)
            return
        }

        let status = service.status
        applyStatus(status)

        if enabled {
            switch status {
            case .enabled:
                HUDManager.shared.showTemporary(
                    message: AppLocalization.isChinese ? "Aether 将随登录启动" : "Aether will launch at login",
                    icon: "checkmark.circle.fill"
                )
            case .requiresApproval:
                HUDManager.shared.showTemporary(
                    message: AppLocalization.isChinese ? "请在登录项里允许 Aether" : "Allow Aether in Login Items",
                    icon: "arrow.up.forward.app"
                )
            default:
                break
            }
        } else if status == .notRegistered {
            HUDManager.shared.showTemporary(
                message: AppLocalization.isChinese ? "已关闭登录启动" : "Launch at login turned off",
                icon: "checkmark.circle.fill"
            )
        }
    }

    func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    private func applyStatus(_ status: SMAppService.Status) {
        switch status {
        case .enabled:
            isEnabled = true
            requiresApproval = false
            isRequested = true
        case .requiresApproval:
            isEnabled = false
            requiresApproval = true
            isRequested = true
        case .notRegistered, .notFound:
            isEnabled = false
            requiresApproval = false
            isRequested = false
        @unknown default:
            isEnabled = false
            requiresApproval = false
            isRequested = false
        }
    }

    private func showFailureHUD(enabled: Bool) {
        HUDManager.shared.showTemporary(
            message: enabled
                ? (AppLocalization.isChinese ? "开机启动开启失败" : "Couldn't turn on launch at login")
                : (AppLocalization.isChinese ? "开机启动关闭失败" : "Couldn't turn off launch at login"),
            icon: "exclamationmark.triangle.fill"
        )
    }
}

struct AetherMainView: View {
    @State private var selection: Panel? = .overview
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    enum Panel: Hashable {
        case overview
        case about
        case voiceTerms
        case voiceLexicon
        case voiceAppControls
        case voiceInsights
        case wakeInsights
        case headGestures
        case shortcuts
    }
    private var sidebarWidth: CGFloat {
        SidebarMetrics.preferredWidth()
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            List(selection: $selection) {
                Section {
                    sidebarItem(.overview)
                        .tag(Panel.overview)
                } header: {
                    sidebarHeader("main.section.workspace", topPadding: 8)
                }

                Section {
                    sidebarItem(.headGestures)
                        .tag(Panel.headGestures)
                    sidebarItem(.shortcuts)
                        .tag(Panel.shortcuts)
                    sidebarItem(.voiceAppControls)
                        .tag(Panel.voiceAppControls)
                } header: {
                    sidebarHeader("main.section.controls")
                }

                Section {
                    sidebarItem(.voiceLexicon)
                        .tag(Panel.voiceLexicon)
                    sidebarItem(.voiceInsights)
                        .tag(Panel.voiceInsights)
                    sidebarItem(.wakeInsights)
                        .tag(Panel.wakeInsights)
                } header: {
                    sidebarHeader("main.section.voice")
                }

                Section {
                    sidebarItem(.about)
                        .tag(Panel.about)
                } header: {
                    sidebarHeader("main.section.app")
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: max(180, sidebarWidth - 12), ideal: sidebarWidth, max: min(320, sidebarWidth + 20))
            .toolbar(removing: .sidebarToggle)
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
            case .wakeInsights:
                InputSettingsView(section: .wakeInsights)
            case .headGestures:
                HeadGestureSettingsView()
            case .shortcuts:
                ShortcutsSettingsView()
            case .none:
                Text(L10n.selectItem)
            }
        }
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
        .onReceive(NotificationCenter.default.publisher(for: .aetherToggleMainSidebar)) { _ in
            withAnimation(.easeInOut(duration: 0.18)) {
                columnVisibility = (columnVisibility == .detailOnly) ? .all : .detailOnly
            }
        }
    }

    private func sidebarHeader(_ key: String, topPadding: CGFloat = 16) -> some View {
        Text(LocalizedStringKey(key))
            .font(.system(size: 12.5, weight: .bold))
            .foregroundStyle(.secondary)
            .textCase(nil)
            .padding(.top, topPadding)
            .padding(.bottom, 8)
    }

    private func sidebarItem(_ panel: Panel) -> some View {
        Label {
            Text(panelTitle(panel))
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.primary)
        } icon: {
            Image(systemName: panelSymbol(panel))
                .font(.system(size: 16, weight: .semibold))
                .frame(width: 22)
        }
        .symbolRenderingMode(.monochrome)
            .listRowInsets(EdgeInsets(top: 8, leading: 10, bottom: 8, trailing: 10))
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
        case .wakeInsights:
            return AppLocalization.isChinese ? "唤醒与激活" : "Wake & Activation"
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
            return "info.circle.fill"
        case .voiceTerms:
            return "text.magnifyingglass"
        case .voiceLexicon:
            return "text.book.closed.fill"
        case .voiceAppControls:
            return "command.square.fill"
        case .voiceInsights:
            return "waveform.path.ecg"
        case .wakeInsights:
            return "waveform.badge.mic"
        case .headGestures:
            return "person.fill.viewfinder"
        case .shortcuts:
            return "keyboard.fill"
        }
    }
}

private struct StandardWindowConfigurator: NSViewRepresentable {
    let title: String
    let subtitle: String

    func makeNSView(context: Context) -> NSView {
        let view = WindowConfiguratorView()
        view.update(title: title, subtitle: subtitle)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let view = nsView as? WindowConfiguratorView else { return }
        view.update(title: title, subtitle: subtitle)
        view.configureIfNeeded()
    }

    private final class WindowConfiguratorView: NSView {
        private var didConfigure = false
        private var title: String = ""
        private var subtitle: String = ""

        func update(title: String, subtitle: String) {
            self.title = title
            self.subtitle = subtitle
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            configureIfNeeded()
        }

        func configureIfNeeded() {
            guard let window else { return }
            if !didConfigure {
                StandardWindowConfigurator.applyConfiguration(for: window, title: title, subtitle: subtitle)
                didConfigure = true
            } else {
                StandardWindowConfigurator.applyTitle(for: window, title: title, subtitle: subtitle)
            }
        }
    }

    private static func applyTitle(for window: NSWindow, title: String, subtitle: String) {
        window.title = title
        window.subtitle = subtitle
    }

    private static func applyConfiguration(for window: NSWindow, title: String, subtitle: String) {
        window.identifier = NSUserInterfaceItemIdentifier("AetherMainWindow")
        applyTitle(for: window, title: title, subtitle: subtitle)
        window.styleMask.insert(.fullSizeContentView)
        window.titleVisibility = .visible
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.toolbarStyle = .unified
        window.backgroundColor = .windowBackgroundColor
        let toolbarIdentifier = NSToolbar.Identifier("AetherMainWindowToolbar")
        if window.toolbar?.identifier != toolbarIdentifier {
            let toolbar = NSToolbar(identifier: toolbarIdentifier)
            toolbar.delegate = MainWindowToolbarDelegate.shared
            toolbar.displayMode = .iconOnly
            toolbar.allowsUserCustomization = false
            window.toolbar = toolbar
        }
        if #available(macOS 11.0, *) {
            window.titlebarSeparatorStyle = .none
        }
        if !window.titlebarAccessoryViewControllers.contains(where: { $0 is SidebarToggleAccessoryViewController }) {
            let accessory = SidebarToggleAccessoryViewController()
            accessory.layoutAttribute = .left
            window.addTitlebarAccessoryViewController(accessory)
        }
    }
}

private final class MainWindowToolbarDelegate: NSObject, NSToolbarDelegate {
    static let shared = MainWindowToolbarDelegate()

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.flexibleSpace, .flexibleSpace]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.flexibleSpace, .sidebarTrackingSeparator]
    }

    func toolbar(
        _ toolbar: NSToolbar,
        itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar flag: Bool
    ) -> NSToolbarItem? {
        nil
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
        button.toolTip = "Toggle Sidebar"
        button.setAccessibilityLabel("Toggle Sidebar")
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
        NotificationCenter.default.post(name: .aetherToggleMainSidebar, object: nil)
    }
}

private struct OverviewDashboardView: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject private var headManager = HeadMotionManager.shared
    @StateObject private var launchAtLogin = LaunchAtLoginManager()
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

    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { launchAtLogin.isRequested },
            set: { launchAtLogin.setEnabled($0) }
        )
    }

    private var launchAtLoginDetailText: String {
        if launchAtLogin.requiresApproval {
            return isChinese
                ? "需要到系统设置 > 登录项里批准后才会生效。"
                : "Approval is still needed in System Settings > Login Items."
        }
        if launchAtLogin.isEnabled {
            return isChinese
                ? "登录 macOS 后会自动启动 Aether。"
                : "Aether will open automatically after you log in to macOS."
        }
        return isChinese
            ? "让 Aether 在登录后自动启动。"
            : "Launch Aether automatically after you log in."
    }

    private var microphoneSetupActionTitle: String? {
        guard !appState.microphoneAuthorized else { return nil }
        switch appState.microphoneAuthorizationStatus {
        case .denied, .restricted:
            return String(localized: "permissions.fix_microphone")
        default:
            return String(localized: "main.action.enable")
        }
    }

    private func handleMicrophoneSetupAction() {
        switch appState.microphoneAuthorizationStatus {
        case .denied, .restricted:
            appState.repairMicrophoneGuided()
        default:
            appState.requestMicrophoneGuided()
        }
    }

    private var speechSetupActionTitle: String? {
        guard !appState.speechAuthorized else { return nil }
        switch appState.speechAuthorizationStatus {
        case .denied, .restricted:
            return String(localized: "permissions.fix_speech")
        default:
            return String(localized: "main.action.enable")
        }
    }

    private func handleSpeechSetupAction() {
        switch appState.speechAuthorizationStatus {
        case .denied, .restricted:
            appState.repairSpeechGuided()
        default:
            appState.requestSpeechGuided()
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
                actionTitle: microphoneSetupActionTitle,
                action: appState.microphoneAuthorized ? nil : handleMicrophoneSetupAction
            ),
            OverviewSetupItem(
                id: "speech",
                icon: "waveform",
                title: String(localized: "permissions.speech"),
                detail: appState.speechAuthorized
                    ? String(localized: "main.permission.speech.detail.ready")
                    : String(localized: "main.permission.speech.detail.missing"),
                isReady: appState.speechAuthorized,
                actionTitle: speechSetupActionTitle,
                action: appState.speechAuthorized ? nil : handleSpeechSetupAction
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

                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 10) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(isChinese ? "登录后自动启动 Aether" : "Launch Aether At Login")
                                    .font(AetherUI.bodyFont)
                                Text(launchAtLoginDetailText)
                                    .font(AetherUI.captionFont)
                                    .foregroundColor(launchAtLogin.requiresApproval ? .orange : .secondary)
                                    .lineLimit(2)
                                    .truncationMode(.tail)
                            }
                            .layoutPriority(1)
                            Spacer()
                            Toggle("", isOn: launchAtLoginBinding)
                                .labelsHidden()
                                .toggleStyle(.switch)
                                .disabled(launchAtLogin.isBusy)
                        }

                        if launchAtLogin.requiresApproval {
                            HStack {
                                Button(isChinese ? "前往登录项" : "Open Login Items") {
                                    launchAtLogin.openSystemSettings()
                                }
                                .controlSize(.small)
                                .buttonStyle(.bordered)
                                Spacer()
                            }
                        }
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
            launchAtLogin.refreshStatus()
        }
        .onChange(of: readinessCanCollapse) { _, canCollapse in
            readinessExpanded = !canCollapse
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            launchAtLogin.refreshStatus()
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
