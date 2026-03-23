import SwiftUI
import AppKit

@MainActor
private enum AetherApplicationTerminator {
    static func terminateFromLockedUI() {
        let app = NSApplication.shared
        app.abortModal()
        app.stop(nil)
        app.sendAction(#selector(NSApplication.terminate(_:)), to: nil, from: nil)
        DispatchQueue.main.async {
            app.terminate(nil)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            _ = NSRunningApplication.current.terminate()
        }
    }
}

struct ActivationGateView: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject private var licenseManager = AetherLicenseManager.shared
    @ObservedObject private var updaterManager = AetherUpdaterManager.shared

    @State private var emailInput: String = ""
    @State private var codeInput: String = ""
    @State private var referralInput: String = ""
    @State private var devicesExpanded: Bool = true

    private var isChinese: Bool { appState.isChineseUI }
    private var isDeviceLimitReached: Bool { licenseManager.gateState == .deviceLimitReached }
    private var canActivate: Bool { licenseManager.gateState != .loading }
    private var canStartTrial: Bool { licenseManager.gateState != .loading && !isDeviceLimitReached }
    private var deviceListHintText: String {
        if licenseManager.isFetchingDevices {
            return isChinese ? "正在拉取设备列表…" : "Loading devices…"
        }
        return isChinese
            ? "当前没有可移除的设备信息。若设备占用已满但列表仍为空，通常是授权服务还没有返回旧设备记录。"
            : "No removable devices were returned. If the device count is full but the list stays empty, the licensing service did not return old device records yet."
    }

    private var titleText: String {
        switch licenseManager.gateState {
        case .loading:
            return isChinese ? "正在验证授权" : "Checking Access"
        case .expired:
            return isChinese ? "授权已过期" : "Access Expired"
        case .deviceLimitReached:
            return isChinese ? "设备数已满" : "Device Limit Reached"
        case .inactive:
            return isChinese ? "需要激活后使用" : "Activation Required"
        case .active, .trialing:
            return isChinese ? "Aether 已激活" : "Aether Unlocked"
        }
    }

    private var detailText: String {
        switch licenseManager.gateState {
        case .loading:
            return isChinese ? "请稍等，正在确认这台设备是否有可用授权。" : "Please wait while Aether verifies whether this Mac has access."
        case .expired:
            return isChinese ? "当前授权已过期。你可以刷新状态、恢复激活，或重新开始试用。" : "Your entitlement has expired. Refresh, restore activation, or start a trial to continue."
        case .deviceLimitReached:
            return isChinese ? "当前设备数已满。你可以移除旧设备后再继续使用。" : "The current device limit has been reached. Remove an old device, then try again."
        case .inactive:
            return isChinese ? "Aether 已锁定。输入邮箱和激活码恢复授权，或直接开始试用。" : "Aether is locked. Enter your email and activation code to restore access, or start a trial."
        case .active, .trialing:
            return ""
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

            VStack(spacing: 24) {
                GlassCard(padding: 24) {
                    VStack(alignment: .leading, spacing: 18) {
                        HStack(alignment: .top, spacing: 16) {
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
                                Text(detailText)
                                    .font(.body)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()
                        }

                        if licenseManager.gateState == .loading {
                            HStack(spacing: 10) {
                                ProgressView()
                                    .controlSize(.small)
                                Text(isChinese ? "正在刷新授权状态…" : "Refreshing entitlement…")
                                    .foregroundStyle(.secondary)
                            }
                        }

                        LabeledContent(isChinese ? "当前状态" : "Status", value: licenseManager.statusSummary)
                        LabeledContent(isChinese ? "方案" : "Plan", value: licenseManager.planSummary)
                        LabeledContent(isChinese ? "试用截止" : "Trial ends", value: licenseManager.trialEndsAt ?? "-")
                        LabeledContent(isChinese ? "订阅截止" : "Subscription ends", value: licenseManager.subscriptionEndsAt ?? "-")
                        LabeledContent(isChinese ? "设备占用" : "Devices", value: "\(licenseManager.devicesUsed) / \(licenseManager.maxDevices)")

                        Divider()

                        TextField(isChinese ? "邮箱" : "Email", text: $emailInput)
                            .textFieldStyle(.roundedBorder)
                            .textContentType(.emailAddress)
                        TextField(isChinese ? "激活码" : "Activation code", text: $codeInput)
                            .textFieldStyle(.roundedBorder)
                        TextField(isChinese ? "邀请码（可选）" : "Referral code (optional)", text: $referralInput)
                            .textFieldStyle(.roundedBorder)

                        HStack {
                            Button(isChinese ? "激活" : "Activate") {
                                Task { await licenseManager.activate(email: emailInput, code: codeInput) }
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(!canActivate)

                            Button(isChinese ? "开始试用" : "Start Trial") {
                                Task {
                                    await licenseManager.startTrial(email: emailInput, referralCode: referralInput.isEmpty ? nil : referralInput)
                                    codeInput = licenseManager.licenseKey
                                }
                            }
                            .buttonStyle(.bordered)
                            .disabled(!canStartTrial)

                            Button(isChinese ? "刷新状态" : "Refresh") {
                                Task { await licenseManager.refreshEntitlement() }
                            }
                            .buttonStyle(.bordered)

                            Button(isChinese ? "退出 Aether" : "Quit Aether") {
                                AetherApplicationTerminator.terminateFromLockedUI()
                            }
                            .buttonStyle(.bordered)
                            .keyboardShortcut("q", modifiers: [.command])
                        }
                        .controlSize(.small)

                        if let info = licenseManager.infoMessage, !info.isEmpty {
                            Text(info)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        if let error = licenseManager.lastErrorMessage, !error.isEmpty {
                            Text(error)
                                .font(.caption)
                                .foregroundStyle(.red)
                        }

                        if isDeviceLimitReached {
                            Divider()
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
                                HStack {
                                    Text(isChinese ? "设备管理" : "Device Management")
                                        .font(.body.weight(.semibold))
                                    Spacer()
                                    Text("\(licenseManager.devices.count)")
                                        .font(.caption.weight(.semibold).monospacedDigit())
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(Color.accentColor.opacity(0.12))
                                        .foregroundStyle(Color.accentColor)
                                        .clipShape(Capsule())
                                }
                            }
                            .controlSize(.small)
                        }
                    }
                }
                .frame(maxWidth: 760)

                GlassCard(padding: 18) {
                    HStack {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(isChinese ? "更新与恢复" : "Updates and Recovery")
                                .font(.headline)
                            Text(updaterManager.statusMessage.isEmpty ? (isChinese ? "锁定状态下仍可检查更新和恢复授权。" : "Updates and recovery stay available while locked.") : updaterManager.statusMessage)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button(isChinese ? "检查更新" : "Check for Updates") {
                            Task { await updaterManager.checkForUpdates() }
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .frame(maxWidth: 760)
            }
            .padding(32)
        }
        .onAppear {
            emailInput = licenseManager.email
            codeInput = licenseManager.licenseKey
            if isDeviceLimitReached {
                Task { await licenseManager.fetchDevices() }
            }
        }
        .onChange(of: licenseManager.gateState) { _, newValue in
            if newValue == .deviceLimitReached {
                Task { await licenseManager.fetchDevices() }
            }
        }
    }
}

struct AetherRootView: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject private var licenseManager = AetherLicenseManager.shared
    @State private var isActivationGatePresented: Bool = false

    var body: some View {
        AetherMainView()
            .sheet(isPresented: $isActivationGatePresented) {
                ActivationGateView()
                    .environmentObject(appState)
                    .interactiveDismissDisabled(true)
            }
            .onAppear {
                syncActivationGatePresentation()
            }
            .onChange(of: licenseManager.gateState) { _, _ in
                syncActivationGatePresentation()
            }
    }

    private func syncActivationGatePresentation() {
        switch licenseManager.gateState {
        case .active, .trialing:
            isActivationGatePresented = false
        case .inactive, .expired, .deviceLimitReached:
            isActivationGatePresented = true
        case .loading:
            break
        }
    }
}
