import SwiftUI

struct ActivationGateView: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject private var licenseManager = AetherLicenseManager.shared

    @State private var emailInput: String = ""
    @State private var codeInput: String = ""
    @State private var referralInput: String = ""
    @State private var showsActivationForm: Bool = false
    @State private var devicesExpanded: Bool = true

    private var isChinese: Bool { appState.isChineseUI }
    private var isDeviceLimitReached: Bool { licenseManager.gateState == .deviceLimitReached }
    private var canActivate: Bool { licenseManager.gateState != .loading }
    private var canStartTrial: Bool { licenseManager.gateState != .loading && !isDeviceLimitReached }
    private var shouldShowTrialSection: Bool { !isDeviceLimitReached }

    private var statusChipText: String {
        switch licenseManager.gateState {
        case .loading:
            return isChinese ? "正在验证" : "Checking"
        case .expired:
            return isChinese ? "已过期" : "Expired"
        case .deviceLimitReached:
            return isChinese ? "设备已满" : "Devices Full"
        case .inactive:
            return isChinese ? "可开始试用" : "Trial Available"
        case .active:
            return isChinese ? "已激活" : "Unlocked"
        case .trialing:
            return isChinese ? "试用中" : "Trial Active"
        }
    }

    private var titleText: String {
        switch licenseManager.gateState {
        case .loading:
            return isChinese ? "正在确认这台 Mac 的访问权限" : "Checking access on this Mac"
        case .expired:
            return isChinese ? "继续使用 Aether" : "Get back into Aether"
        case .deviceLimitReached:
            return isChinese ? "先释放一个设备" : "Free up a device first"
        case .inactive:
            return isChinese ? "先开始试用" : "Start with a trial"
        case .active, .trialing:
            return isChinese ? "Aether 已可用" : "Aether is ready"
        }
    }

    private var detailText: String {
        switch licenseManager.gateState {
        case .loading:
            return isChinese ? "稍等一下，我们正在确认这台设备是否已经有可用资格。" : "Please wait while Aether checks whether this Mac already has access."
        case .expired:
            return isChinese ? "你可以重新开始试用，或用已有激活码恢复访问。" : "Start a new trial, or restore access with an activation code you already have."
        case .deviceLimitReached:
            return isChinese ? "这台 Mac 需要一个可用席位。移除旧设备后，就可以继续进入 Aether。" : "This Mac needs an available seat. Remove an old device, then continue into Aether."
        case .inactive:
            return isChinese ? "大多数用户都会先从试用开始。输入邮箱即可进入 Aether。" : "Most people start with a trial. Enter your email to get into Aether."
        case .active, .trialing:
            return ""
        }
    }

    private var trialSectionTitle: String {
        switch licenseManager.gateState {
        case .expired:
            return isChinese ? "重新开始试用" : "Start a new trial"
        default:
            return isChinese ? "开始试用" : "Start Trial"
        }
    }

    private var trialSectionDetail: String {
        isChinese
            ? "只需要邮箱即可。邀请码选填；开始后，激活信息会发到你的邮箱。"
            : "Just enter your email. A referral code is optional, and your activation details will be emailed after you start."
    }

    private var activationToggleText: String {
        showsActivationForm
            ? (isChinese ? "收起激活入口" : "Hide activation")
            : (isChinese ? "输入激活码" : "Use activation code")
    }

    private var activationPromptText: String {
        isChinese ? "已有激活码？" : "Already have an activation code?"
    }

    private var activationSectionTitle: String {
        isChinese ? "激活 Aether" : "Activate Aether"
    }

    private var activationSectionDetail: String {
        isChinese ? "如果你已经拿到激活码，在这里恢复访问。" : "If you already have a code, restore access here."
    }

    private var deviceListHintText: String {
        if licenseManager.isFetchingDevices {
            return isChinese ? "正在拉取设备列表…" : "Loading devices…"
        }
        return isChinese
            ? "当前没有可移除的设备信息。若设备占用已满但列表仍为空，通常是授权服务还没有返回旧设备记录。"
            : "No removable devices were returned. If the device count is full but the list stays empty, the licensing service did not return old device records yet."
    }

    private var statusChipColor: Color {
        switch licenseManager.gateState {
        case .loading:
            return .secondary
        case .expired, .deviceLimitReached:
            return .orange
        case .inactive:
            return Color.accentColor
        case .active, .trialing:
            return .green
        }
    }

    private var feedbackMessage: String? {
        if let error = licenseManager.lastErrorMessage, !error.isEmpty {
            return error
        }
        if let info = licenseManager.infoMessage, !info.isEmpty {
            return info
        }
        return nil
    }

    private var isFeedbackError: Bool {
        if let error = licenseManager.lastErrorMessage, !error.isEmpty {
            return true
        }
        return false
    }

    private var trialSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(trialSectionTitle)
                    .font(.headline)
                Text(trialSectionDetail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            TextField(isChinese ? "邮箱" : "Email", text: $emailInput)
                .textFieldStyle(.roundedBorder)
                .textContentType(.emailAddress)
                .controlSize(.large)

            TextField(isChinese ? "邀请码（可选）" : "Referral code (optional)", text: $referralInput)
                .textFieldStyle(.roundedBorder)
                .controlSize(.large)

            Button {
                Task {
                    await licenseManager.startTrial(email: emailInput, referralCode: referralInput.isEmpty ? nil : referralInput)
                    codeInput = licenseManager.licenseKey
                }
            } label: {
                Text(trialSectionTitle)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!canStartTrial)
        }
    }

    private var activationSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(activationSectionTitle)
                    .font(.headline)
                Text(activationSectionDetail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            TextField(isChinese ? "激活码" : "Activation code", text: $codeInput)
                .textFieldStyle(.roundedBorder)
                .controlSize(.large)

            HStack(spacing: 10) {
                Button(isChinese ? "激活" : "Activate") {
                    Task { await licenseManager.activate(email: emailInput, code: codeInput) }
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
                .disabled(!canActivate)

                if !emailInput.isEmpty {
                    Text(emailInput)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .padding(16)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.55))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var feedbackSection: some View {
        Group {
            if let feedbackMessage {
                Text(feedbackMessage)
                    .font(.caption)
                    .foregroundStyle(isFeedbackError ? .red : .secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(isFeedbackError ? Color.red.opacity(0.08) : Color.accentColor.opacity(0.08))
                    )
            }
        }
    }

    private var deviceManagementSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(isChinese ? "设备管理" : "Device Management")
                        .font(.headline)
                    Text(isChinese ? "移除一个旧设备后，这台 Mac 就能继续使用。" : "Remove an old device and this Mac can continue.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text("\(licenseManager.devicesUsed) / \(licenseManager.maxDevices)")
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(statusChipColor.opacity(0.14))
                    .foregroundStyle(statusChipColor)
                    .clipShape(Capsule())
            }

            DisclosureGroup(isExpanded: $devicesExpanded) {
                VStack(alignment: .leading, spacing: 12) {
                    if licenseManager.devices.isEmpty {
                        Text(deviceListHintText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(licenseManager.devices) { device in
                            HStack(alignment: .top, spacing: 12) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(device.name)
                                        .font(.headline)
                                    Text(device.isCurrent ? (isChinese ? "当前设备" : "Current device") : (isChinese ? "其他设备" : "Other device"))
                                        .foregroundStyle(.secondary)
                                    Text("\(isChinese ? "激活于" : "Activated") \(device.activatedAt ?? "-")")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Text("\(isChinese ? "最近在线" : "Last seen") \(device.lastSeenAt ?? "-")")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button(isChinese ? "移除" : "Remove") {
                                    Task { await licenseManager.removeDevice(deviceId: device.id) }
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }
                            if device.id != licenseManager.devices.last?.id {
                                Divider()
                            }
                        }
                    }

                    Button(isChinese ? "刷新设备列表" : "Refresh devices") {
                        Task { await licenseManager.fetchDevices() }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                .padding(.top, 8)
            } label: {
                Text(isChinese ? "查看设备列表" : "Show devices")
                    .font(.body.weight(.semibold))
            }
        }
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color.accentColor.opacity(0.12),
                    Color(nsColor: .windowBackgroundColor)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 20) {
                GlassCard(padding: 24) {
                    VStack(alignment: .leading, spacing: 20) {
                        HStack(alignment: .top, spacing: 18) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .fill(Color.accentColor.opacity(0.14))
                                    .frame(width: 60, height: 60)

                                Image(systemName: licenseManager.gateState == .loading ? "hourglass" : "lock.shield.fill")
                                    .font(.system(size: 24, weight: .semibold))
                                    .foregroundStyle(Color.accentColor)
                            }

                            VStack(alignment: .leading, spacing: 6) {
                                Text(titleText)
                                    .font(.system(size: 28, weight: .bold))
                                    .fixedSize(horizontal: false, vertical: true)
                                Text(detailText)
                                    .font(.body)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }

                            Spacer()

                            Text(statusChipText)
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(statusChipColor.opacity(0.14))
                                .foregroundStyle(statusChipColor)
                                .clipShape(Capsule())
                        }

                        if licenseManager.gateState == .loading {
                            HStack(spacing: 10) {
                                ProgressView()
                                    .controlSize(.small)
                                Text(isChinese ? "正在刷新授权状态…" : "Refreshing entitlement…")
                                    .foregroundStyle(.secondary)
                            }
                        }

                        if shouldShowTrialSection {
                            trialSection

                            Divider()

                            HStack(spacing: 6) {
                                Text(activationPromptText)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                Button(activationToggleText) {
                                    withAnimation(.easeInOut(duration: 0.18)) {
                                        showsActivationForm.toggle()
                                    }
                                }
                                .buttonStyle(.link)
                            }

                            if showsActivationForm {
                                activationSection
                                    .transition(.move(edge: .top).combined(with: .opacity))
                            }
                        }

                        feedbackSection

                        if isDeviceLimitReached {
                            Divider()
                            deviceManagementSection
                        }
                    }
                }
                .frame(maxWidth: 720)
            }
            .padding(32)
        }
        .onAppear {
            emailInput = licenseManager.email
            codeInput = licenseManager.licenseKey
            showsActivationForm = !codeInput.isEmpty || licenseManager.gateState == .expired
            if isDeviceLimitReached {
                Task { await licenseManager.fetchDevices() }
            }
        }
        .onChange(of: licenseManager.gateState) { _, newValue in
            if newValue == .expired, !showsActivationForm {
                showsActivationForm = true
            }
            if newValue == .deviceLimitReached {
                Task { await licenseManager.fetchDevices() }
            }
        }
    }
}

struct AetherRootView: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject private var licenseManager = AetherLicenseManager.shared

    var body: some View {
        Group {
            switch licenseManager.gateState {
            case .active, .trialing:
                AetherMainView()
            case .loading, .inactive, .expired, .deviceLimitReached:
                ActivationGateView()
                    .environmentObject(appState)
            }
        }
    }
}
