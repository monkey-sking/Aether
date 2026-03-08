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
        case headset
        case shortcuts
    }

    private var isChinese: Bool {
        Locale.current.identifier.hasPrefix("zh")
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
                    Text(localeText(zh: "工作区", en: "Workspace"))
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
                    Text(localeText(zh: "语音", en: "Voice"))
                }

                Section {
                    NavigationLink(value: Panel.pointer) {
                        panelLabel(.pointer)
                    }
                    NavigationLink(value: Panel.headset) {
                        panelLabel(.headset)
                    }
                    NavigationLink(value: Panel.shortcuts) {
                        panelLabel(.shortcuts)
                    }
                } header: {
                    Text(localeText(zh: "其他控制", en: "Other Controls"))
                }

            }
            .listStyle(.sidebar)
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
            case .headset:
                HeadsetSettingsView()
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

    private func localeText(zh: String, en: String) -> String {
        Locale.current.identifier.hasPrefix("zh") ? zh : en
    }

    @ViewBuilder
    private func panelLabel(_ panel: Panel) -> some View {
        Label(panelTitle(panel), systemImage: panelSymbol(panel))
    }

    private func panelTitle(_ panel: Panel) -> String {
        switch panel {
        case .overview:
            return localeText(zh: "总览", en: "Overview")
        case .voiceBasics:
            return localeText(zh: "基础", en: "Basics")
        case .voiceTerms:
            return localeText(zh: "术语纠错", en: "Term Corrections")
        case .voiceLexicon:
            return localeText(zh: "词库", en: "Lexicon")
        case .voiceAppControls:
            return localeText(zh: "当前应用", en: "Current App")
        case .voiceInsights:
            return localeText(zh: "统计", en: "Insights")
        case .pointer:
            return localeText(zh: "指针", en: "Pointer")
        case .headset:
            return localeText(zh: "耳机按钮", en: "Headset Buttons")
        case .shortcuts:
            return localeText(zh: "快捷键", en: "Shortcuts")
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
            return "viewfinder"
        case .headset:
            return "airpodspro"
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

    private var isChinese: Bool {
        Locale.current.identifier.hasPrefix("zh")
    }

    private var setupItems: [OverviewSetupItem] {
        [
            OverviewSetupItem(
                id: "accessibility",
                icon: "hand.raised.fill",
                title: isChinese ? "辅助功能" : "Accessibility",
                detail: appState.accessibilityTrusted ? (isChinese ? "已允许控制系统输入" : "Allowed to control system input") : (isChinese ? "未授权，头控和快捷键会受限" : "Required for pointer control and global shortcuts"),
                isReady: appState.accessibilityTrusted,
                actionTitle: appState.accessibilityTrusted ? nil : (isChinese ? "去开启" : "Enable"),
                action: appState.accessibilityTrusted ? nil : { appState.requestAccessibilityGuided() }
            ),
            OverviewSetupItem(
                id: "microphone",
                icon: "mic.fill",
                title: isChinese ? "麦克风" : "Microphone",
                detail: appState.microphoneAuthorized ? (isChinese ? "可以开始语音输入" : "Ready for voice capture") : (isChinese ? "未授权，无法监听语音" : "Required for voice capture"),
                isReady: appState.microphoneAuthorized,
                actionTitle: appState.microphoneAuthorized ? nil : (isChinese ? "去开启" : "Enable"),
                action: appState.microphoneAuthorized ? nil : { appState.requestMicrophoneGuided() }
            ),
            OverviewSetupItem(
                id: "speech",
                icon: "waveform",
                title: isChinese ? "语音识别" : "Speech Recognition",
                detail: appState.speechAuthorized ? (isChinese ? "识别引擎已可用" : "Recognition engine is available") : (isChinese ? "未授权，无法转写语音" : "Required for dictation and commands"),
                isReady: appState.speechAuthorized,
                actionTitle: appState.speechAuthorized ? nil : (isChinese ? "去开启" : "Enable"),
                action: appState.speechAuthorized ? nil : { appState.requestSpeechGuided() }
            )
        ]
    }

    private var blockingIssuesCount: Int {
        setupItems.filter { !$0.isReady }.count + (appState.driverState == .needsUserApproval ? 1 : 0)
    }

    private var readinessCanCollapse: Bool {
        blockingIssuesCount == 0
    }

    private var overviewSubtitle: String {
        if blockingIssuesCount == 0 {
            return isChinese
                ? "核心权限已经就绪，这里保留你最常用的控制和运行状态。"
                : "Core permissions are ready. This page keeps the controls and runtime state you use most."
        }
        return isChinese
            ? "还差 \(blockingIssuesCount) 项设置完成即可更稳定地使用 Aether。"
            : "\(blockingIssuesCount) setup item(s) still need attention before Aether is fully ready."
    }

    var body: some View {
        SettingsPage(
            title: isChinese ? "总览" : "Overview",
            subtitle: overviewSubtitle
        ) {
            OverviewReadinessCard(
                isChinese: isChinese,
                setupItems: setupItems,
                showDriverApproval: appState.driverState == .needsUserApproval,
                openPrivacyAndSecurity: appState.openPrivacyAndSecurityPane,
                isCollapsed: readinessCanCollapse && !readinessExpanded,
                canCollapse: readinessCanCollapse,
                onToggle: { readinessExpanded.toggle() }
            )

            LazyVGrid(columns: columns, spacing: 16) {
                GlassCard {
                    PointerControlTile(
                        isChinese: isChinese,
                        subtitle: headManager.isTracking
                            ? (isChinese ? "AirPods 头控正在运行" : "AirPods tracking is running")
                            : (isChinese ? "开启后可使用头部控制指针" : "Start tracking to move the pointer"),
                        isOn: trackingBinding,
                        autoStartOnConnect: autoStartTrackingBinding,
                        showPostureGuide: postureGuideBinding
                    )
                }

                GlassCard {
                    VoiceModeTile(
                        isChinese: isChinese,
                        mode: $appState.voiceActivationMode
                    )
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
    let isChinese: Bool
    let setupItems: [OverviewSetupItem]
    let showDriverApproval: Bool
    let openPrivacyAndSecurity: () -> Void
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
                        Text(isChinese ? "准备情况" : "Readiness")
                            .font(.headline)
                        Text(isChinese
                             ? "先把必需权限拉齐，再去调语音和指针体验。"
                             : "Make the required permissions green first, then tune voice and pointer behavior.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    OverviewStateTag(
                        title: "\(readyCount)/\(setupItems.count) \(isChinese ? "已完成" : "Ready")",
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
                    Text(
                        isChinese
                            ? "核心权限都已就绪。需要时可展开查看详情。"
                            : "All core permissions are ready. Expand if you need details."
                    )
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

                        if showDriverApproval {
                            HStack(spacing: 12) {
                                Image(systemName: "lock.shield.fill")
                                    .frame(width: 20)
                                    .foregroundColor(.orange)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(isChinese ? "驱动审批" : "Driver Approval")
                                        .font(.subheadline.weight(.medium))
                                    Text(isChinese ? "系统扩展还需要在“隐私与安全性”里允许。" : "The system extension still needs approval in Privacy & Security.")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }

                                Spacer()

                                Button(isChinese ? "打开设置" : "Open Settings", action: openPrivacyAndSecurity)
                                    .controlSize(.small)
                            }
                            .padding(12)
                            .background(Color.orange.opacity(0.08))
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
    let isChinese: Bool
    let subtitle: String
    @Binding var isOn: Bool
    @Binding var autoStartOnConnect: Bool
    @Binding var showPostureGuide: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                ZStack {
                    Circle()
                        .fill(isOn ? Color.green : Color.gray.opacity(0.16))
                        .frame(width: 40, height: 40)
                    Image(systemName: "viewfinder")
                        .foregroundColor(isOn ? .white : .secondary)
                }
                Spacer()
                Toggle("", isOn: $isOn)
                    .labelsHidden()
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(isChinese ? "头控指针" : "Pointer Control")
                    .font(.headline)
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(spacing: 8) {
                inlineToggle(
                    title: isChinese ? "连接耳机后自动开启" : "Auto-start when headset connects",
                    isOn: $autoStartOnConnect
                )
                inlineToggle(
                    title: isChinese ? "显示姿态引导" : "Show posture guide",
                    isOn: $showPostureGuide
                )
                .disabled(!autoStartOnConnect)
                .opacity(autoStartOnConnect ? 1 : 0.55)
            }

            Text(
                isChinese
                    ? "仅支持带头部姿态传感器的耳机；不支持的设备连接后不会自动开启。"
                    : "Auto-start only works with head-motion-capable headsets."
            )
            .font(.caption2)
            .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 172, alignment: .topLeading)
    }

    @ViewBuilder
    private func inlineToggle(title: String, isOn: Binding<Bool>) -> some View {
        HStack(spacing: 10) {
            Text(title)
                .font(.caption.weight(.medium))
            Spacer()
            Toggle("", isOn: isOn)
                .labelsHidden()
                .controlSize(.small)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.72))
        .cornerRadius(10)
    }
}

private struct VoiceModeTile: View {
    let isChinese: Bool
    @Binding var mode: AppState.VoiceActivationMode

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                ZStack {
                    Circle()
                        .fill(Color.blue.opacity(0.18))
                        .frame(width: 40, height: 40)
                    Image(systemName: "waveform.badge.mic")
                        .foregroundColor(.blue)
                }
                Spacer()
                OverviewStateTag(
                    title: label(for: mode),
                    tint: mode == .handsFree ? .green : .blue
                )
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(isChinese ? "语音唤起" : "Voice Activation")
                    .font(.headline)
                Text(isChinese ? "在这里切换最常用的输入方式。" : "Switch between the voice modes you use most.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            HStack(spacing: 8) {
                ForEach(AppState.VoiceActivationMode.allCases, id: \.self) { item in
                    Button {
                        mode = item
                    } label: {
                        Text(shortLabel(for: item))
                            .font(.caption.weight(.medium))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(mode == item ? Color.accentColor.opacity(0.16) : Color(nsColor: .controlBackgroundColor))
                            .foregroundColor(mode == item ? .accentColor : .primary)
                            .cornerRadius(10)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 148, alignment: .topLeading)
    }

    private func label(for mode: AppState.VoiceActivationMode) -> String {
        switch mode {
        case .pushToTalk:
            return isChinese ? "按住说话" : "Push to Talk"
        case .wakeWord:
            return isChinese ? "唤醒词" : "Wake Word"
        case .handsFree:
            return isChinese ? "免提常驻" : "Hands-Free"
        }
    }

    private func shortLabel(for mode: AppState.VoiceActivationMode) -> String {
        switch mode {
        case .pushToTalk:
            return isChinese ? "按住说话" : "PTT"
        case .wakeWord:
            return isChinese ? "唤醒词" : "Wake"
        case .handsFree:
            return isChinese ? "免提" : "Hands-Free"
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
