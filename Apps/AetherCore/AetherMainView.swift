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
        case voice
        case pointer
        case shortcuts
        case advanced
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Section {
                    NavigationLink(value: Panel.overview) {
                        Label(localeText(zh: "总览", en: "Overview"), systemImage: "square.grid.2x2.fill")
                    }
                } header: {
                    Text(localeText(zh: "工作区", en: "Workspace"))
                }

                Section {
                    NavigationLink(value: Panel.voice) {
                        Label(localeText(zh: "语音", en: "Voice"), systemImage: "mic.fill")
                    }
                    NavigationLink(value: Panel.pointer) {
                        Label(localeText(zh: "指针", en: "Pointer"), systemImage: "viewfinder")
                    }
                    NavigationLink(value: Panel.shortcuts) {
                        Label(localeText(zh: "快捷键", en: "Shortcuts"), systemImage: "keyboard")
                    }
                } header: {
                    Text(localeText(zh: "核心控制", en: "Core Controls"))
                }

                Section {
                    NavigationLink(value: Panel.advanced) {
                        Label(localeText(zh: "高级", en: "Advanced"), systemImage: "slider.horizontal.3")
                    }
                } header: {
                    Text(localeText(zh: "配置", en: "Configuration"))
                }
            }
            .navigationTitle("Aether")
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 220, ideal: 240, max: 280)
        } detail: {
            switch selection {
            case .overview:
                OverviewDashboardView()
            case .voice:
                InputSettingsView()
            case .pointer:
                OutputSettingsView()
            case .shortcuts:
                ShortcutsSettingsView()
            case .advanced:
                SystemSettingsView()
            case .none:
                Text(L10n.selectItem)
            }
        }
        .navigationSplitViewStyle(.balanced)
    }

    private func localeText(zh: String, en: String) -> String {
        Locale.current.identifier.hasPrefix("zh") ? zh : en
    }
}

private struct OverviewDashboardView: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject private var headManager = HeadMotionManager.shared

    private let columns = [
        GridItem(.adaptive(minimum: 220), spacing: 16)
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

    private var activationModeSummary: String {
        switch appState.voiceActivationMode {
        case .pushToTalk:
            return isChinese ? "按住说话" : "Push to Talk"
        case .wakeWord:
            return isChinese ? "唤醒词" : "Wake Word"
        case .handsFree:
            return isChinese ? "免提常驻" : "Hands-Free"
        }
    }

    private var selectedMicrophoneName: String {
        appState.availableInputDevices.first(where: { $0.id == appState.selectedInputDeviceID })?.name
            ?? (isChinese ? "系统默认" : "System Default")
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
                openPrivacyAndSecurity: appState.openPrivacyAndSecurityPane
            )

            LazyVGrid(columns: columns, spacing: 16) {
                GlassCard {
                    OverviewToggleTile(
                        title: isChinese ? "头控指针" : "Pointer Control",
                        subtitle: headManager.isTracking
                            ? (isChinese ? "AirPods 头控正在运行" : "AirPods tracking is running")
                            : (isChinese ? "开启后可使用头部控制指针" : "Start tracking to move the pointer"),
                        systemImage: "viewfinder",
                        tint: .green,
                        isOn: trackingBinding
                    )
                }

                GlassCard {
                    VoiceModeTile(
                        isChinese: isChinese,
                        mode: $appState.voiceActivationMode
                    )
                }
            }

            GlassCard {
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(isChinese ? "实时状态" : "Live Status")
                                .font(.headline)
                            Text(isChinese ? "检查当前模式、最近转写和设备运行情况。" : "Check the current mode, latest transcript, and device state.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        OverviewStateTag(
                            title: blockingIssuesCount == 0
                                ? (isChinese ? "已就绪" : "Ready")
                                : (isChinese ? "需处理" : "Needs Attention"),
                            tint: blockingIssuesCount == 0 ? .green : .orange
                        )
                    }

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        OverviewMetricCard(
                            title: isChinese ? "语音模式" : "Voice Mode",
                            value: activationModeSummary,
                            detail: isChinese ? "当前输入策略" : "Current input strategy"
                        )
                        OverviewMetricCard(
                            title: isChinese ? "语音状态" : "Voice Status",
                            value: appState.voiceStatus,
                            detail: selectedMicrophoneName
                        )
                        OverviewMetricCard(
                            title: isChinese ? "校准状态" : "Calibration",
                            value: headManager.calibrationStatus == "Normal"
                                ? (isChinese ? "正常" : "Normal")
                                : headManager.calibrationStatus,
                            detail: isChinese ? "指针控制稳定性" : "Pointer control stability"
                        )
                        OverviewMetricCard(
                            title: isChinese ? "按住说话快捷键" : "Push to Talk Shortcut",
                            value: HotkeyManager.shared.binding(for: .pushToTalk).displayString,
                            detail: isChinese ? "可在快捷键页修改" : "Editable in the Shortcuts page"
                        )
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text(isChinese ? "最近一次识别" : "Latest Transcript")
                            .font(.subheadline.weight(.medium))
                        Text(appState.lastVoiceTranscript.isEmpty
                             ? (isChinese ? "还没有识别内容" : "No transcript captured yet")
                             : appState.lastVoiceTranscript)
                            .font(.body)
                            .foregroundColor(appState.lastVoiceTranscript.isEmpty ? .secondary : .primary)
                            .lineLimit(2)
                    }
                    .padding(14)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .cornerRadius(14)
                }
            }
        }
    }
}

private struct OverviewReadinessCard: View {
    let isChinese: Bool
    let setupItems: [OverviewSetupItem]
    let showDriverApproval: Bool
    let openPrivacyAndSecurity: () -> Void

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
                }

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

private struct OverviewMetricCard: View {
    let title: String
    let value: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            Text(value)
                .font(.system(.body, design: .rounded).weight(.semibold))
                .lineLimit(1)
            Text(detail)
                .font(.caption2)
                .foregroundColor(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(14)
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
