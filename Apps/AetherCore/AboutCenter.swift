import SwiftUI
import AppKit
import Combine

struct AetherEntitlementDevice: Identifiable {
    let id: String
    let name: String
    let activatedAt: String?
    let lastSeenAt: String?
    let isCurrent: Bool
}

enum AetherUpdateChannel: String, CaseIterable, Identifiable {
    case stable
    case beta

    var id: String { rawValue }
}

@MainActor
final class AetherLicenseManager: ObservableObject {
    static let shared = AetherLicenseManager()

    @Published var email: String = UserDefaults.standard.string(forKey: "aether.license.email") ?? ""
    @Published var licenseKey: String = UserDefaults.standard.string(forKey: "aether.license.key") ?? ""
    @Published private(set) var status: String = "inactive"
    @Published private(set) var plan: String = "trial"
    @Published private(set) var trialEndsAt: String?
    @Published private(set) var subscriptionEndsAt: String?
    @Published private(set) var devicesUsed: Int = 0
    @Published private(set) var maxDevices: Int = 1
    @Published private(set) var channel: String = "stable"
    @Published private(set) var referralCode: String?
    @Published private(set) var devices: [AetherEntitlementDevice] = []
    @Published private(set) var lastErrorMessage: String?
    @Published private(set) var infoMessage: String?

    private init() {
        Task {
            await refreshEntitlement()
        }
    }

    var isActivated: Bool {
        ["active", "trialing", "valid", "activated"].contains(status)
    }

    var statusSummary: String {
        let isChinese = AppLocalization.isChinese
        switch status {
        case "trialing":
            return isChinese ? "试用中" : "Trial active"
        case "active":
            return isChinese ? "订阅有效" : "Subscription active"
        case "expired":
            return isChinese ? "已过期" : "Expired"
        case "limit_reached":
            return isChinese ? "设备数已满" : "Device limit reached"
        case "inactive":
            return isChinese ? "尚未激活" : "Not activated"
        default:
            return status
        }
    }

    var planSummary: String {
        let isChinese = AppLocalization.isChinese
        switch plan {
        case "monthly":
            return isChinese ? "月付" : "Monthly"
        case "yearly":
            return isChinese ? "年付" : "Yearly"
        default:
            return isChinese ? "试用" : "Trial"
        }
    }

    func setChannelPreference(_ channel: AetherUpdateChannel) {
        self.channel = channel.rawValue
    }

    func activate(email: String, code: String) async {
        self.email = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        self.licenseKey = code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        persistCredentials()
        await verifyCurrentCredentials()
    }

    func refreshEntitlement() async {
        guard !email.isEmpty, !licenseKey.isEmpty else {
            status = "inactive"
            devices = []
            return
        }
        await verifyCurrentCredentials()
    }

    func fetchDevices() async {
        guard isActivated else { return }
        do {
            let json = try await postJSON(path: "/devices", body: credentialBody())
            devices = parseDevices(json["devices"])
            updateSharedState(from: json)
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    func removeDevice(deviceId: String) async {
        do {
            let payload = credentialBody().merging(["targetDeviceId": deviceId]) { _, new in new }
            let json = try await postJSON(path: "/devices/remove", body: payload)
            updateSharedState(from: json)
            if (json["removedSelf"] as? Bool) == true {
                clearCredentials()
            } else {
                await fetchDevices()
            }
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    func resendActivation(email: String?) async {
        do {
            let body: [String: Any] = [
                "email": (email ?? self.email).trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
                "licenseKey": licenseKey,
            ]
            let json = try await postJSON(path: "/activation/resend", body: body)
            updateSharedState(from: json)
            infoMessage = AppLocalization.isChinese ? "激活邮件已重发。" : "Activation email resent."
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    func startTrial(email: String, referralCode: String?) async {
        self.email = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        persistCredentials()
        do {
            var body: [String: Any] = [
                "email": self.email,
                "appId": appBundleID,
                "channel": channel,
            ]
            if let referralCode, !referralCode.isEmpty {
                body["referralCode"] = referralCode
            }
            let json = try await postJSON(path: "/trial/start", body: body)
            if let code = json["licenseKey"] as? String {
                licenseKey = code
                persistCredentials()
            }
            updateSharedState(from: json)
            infoMessage = AppLocalization.isChinese ? "试用已开通，激活码已发送到邮箱。" : "Trial started. The activation code was sent by email."
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    func credentialBody() -> [String: Any] {
        [
            "email": email,
            "licenseKey": licenseKey,
            "deviceId": installationID,
            "appId": appBundleID,
            "deviceModel": Host.current().localizedName ?? "Mac",
            "osVersion": ProcessInfo.processInfo.operatingSystemVersionString,
            "appVersion": Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0",
            "helperVersion": "",
            "channel": channel,
        ]
    }

    private func verifyCurrentCredentials() async {
        lastErrorMessage = nil
        infoMessage = nil

        do {
            let json = try await postJSON(path: "/verify", body: credentialBody())
            updateSharedState(from: json)
            await fetchDevices()
        } catch {
            status = "inactive"
            lastErrorMessage = error.localizedDescription
        }
    }

    private func updateSharedState(from json: [String: Any]) {
        if let value = json["status"] as? String { status = value }
        if let value = json["plan"] as? String { plan = value }
        if let value = json["trialEndsAt"] as? String, !value.isEmpty { trialEndsAt = value } else { trialEndsAt = nil }
        if let value = json["subscriptionEndsAt"] as? String, !value.isEmpty { subscriptionEndsAt = value } else { subscriptionEndsAt = nil }
        if let value = json["devicesUsed"] as? Int { devicesUsed = value }
        if let value = json["maxDevices"] as? Int { maxDevices = value }
        if let value = json["channel"] as? String { channel = value }
        if let value = json["referralCode"] as? String { referralCode = value }
        if let value = json["licenseKey"] as? String, !value.isEmpty {
            licenseKey = value
            persistCredentials()
        }
        if let value = json["message"] as? String, !value.isEmpty {
            infoMessage = value
        }
    }

    private func parseDevices(_ raw: Any?) -> [AetherEntitlementDevice] {
        guard let array = raw as? [[String: Any]] else { return [] }
        return array.map {
            AetherEntitlementDevice(
                id: $0["deviceId"] as? String ?? UUID().uuidString,
                name: $0["deviceName"] as? String ?? "Mac",
                activatedAt: $0["activatedAt"] as? String,
                lastSeenAt: $0["lastSeenAt"] as? String,
                isCurrent: $0["isCurrent"] as? Bool ?? false
            )
        }
    }

    private func postJSON(path: String, body: [String: Any]) async throws -> [String: Any] {
        guard let url = URL(string: authBaseURL + path) else {
            throw NSError(domain: "AetherLicense", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid auth URL"])
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw NSError(domain: "AetherLicense", code: -2, userInfo: [NSLocalizedDescriptionKey: "No HTTP response"])
        }
        let json = (try JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        if http.statusCode >= 400 {
            throw NSError(domain: "AetherLicense", code: http.statusCode, userInfo: [
                NSLocalizedDescriptionKey: (json["message"] as? String) ?? "Request failed",
            ])
        }
        return json
    }

    private func persistCredentials() {
        UserDefaults.standard.set(email, forKey: "aether.license.email")
        UserDefaults.standard.set(licenseKey, forKey: "aether.license.key")
    }

    private func clearCredentials() {
        email = ""
        licenseKey = ""
        status = "inactive"
        devices = []
        UserDefaults.standard.removeObject(forKey: "aether.license.email")
        UserDefaults.standard.removeObject(forKey: "aether.license.key")
    }

    private var authBaseURL: String {
        Bundle.main.object(forInfoDictionaryKey: "AetherAuthBaseURL") as? String ?? "https://auth.aether.7caifei.com"
    }

    private var appBundleID: String {
        Bundle.main.bundleIdentifier ?? "com.7fei.Aether"
    }

    private var installationID: String {
        let key = "aether.installation.id"
        if let stored = UserDefaults.standard.string(forKey: key), !stored.isEmpty {
            return stored
        }
        let value = UUID().uuidString
        UserDefaults.standard.set(value, forKey: key)
        return value
    }
}

@MainActor
final class AetherUpdaterManager: ObservableObject {
    static let shared = AetherUpdaterManager()
    private let sparkleController = AetherSparkleController.shared

    @Published var channel: AetherUpdateChannel = {
        AetherUpdateFeedResolver.currentChannel()
    }()
    @Published private(set) var feedURLString: String = ""
    @Published private(set) var latestVersion: String?
    @Published private(set) var latestDownloadURL: String?
    @Published private(set) var statusMessage: String = ""
    @Published private(set) var hasAvailableUpdate: Bool = false

    private init() {
        refreshFeedString()
    }

    func setUpdateChannel(_ channel: AetherUpdateChannel) {
        self.channel = channel
        UserDefaults.standard.set(channel.rawValue, forKey: "aether.update.channel")
        refreshFeedString()
        sparkleController.refreshFeedSelection()
    }

    func checkForUpdates() async {
        refreshFeedString()
        guard let feedURL = URL(string: feedURLString), !feedURLString.isEmpty else {
            statusMessage = AppLocalization.isChinese ? "未配置更新源。" : "No update feed configured."
            return
        }

        do {
            let (data, _) = try await URLSession.shared.data(from: feedURL)
            let parsed = AppcastParser.parse(data: data)
            latestVersion = parsed.version
            latestDownloadURL = parsed.downloadURL

            guard let version = parsed.version else {
                hasAvailableUpdate = false
                statusMessage = AppLocalization.isChinese ? "更新源中没有可用版本。" : "No releases found in the feed."
                return
            }

            let current = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
            if version.compare(current, options: .numeric) == .orderedDescending {
                hasAvailableUpdate = true
                statusMessage = AppLocalization.isChinese ? "发现新版本。" : "Update available."
            } else {
                hasAvailableUpdate = false
                statusMessage = AppLocalization.isChinese ? "当前已是最新版本。" : "Already on the latest version."
            }
        } catch {
            hasAvailableUpdate = false
            statusMessage = error.localizedDescription
        }

        sparkleController.checkForUpdates()
    }

    func openLatestDownload() {
        let target = latestDownloadURL ?? AetherUpdateFeedResolver.downloadURLString(for: channel)
        if let target, let url = URL(string: target) {
            NSWorkspace.shared.open(url)
        }
    }

    private func refreshFeedString() {
        feedURLString = AetherUpdateFeedResolver.feedURLString(for: channel)
    }
}

private final class AppcastParser: NSObject, XMLParserDelegate {
    private var seenItem = false
    private var currentText = ""
    var version: String?
    var downloadURL: String?

    static func parse(data: Data) -> (version: String?, downloadURL: String?) {
        let delegate = AppcastParser()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.parse()
        return (delegate.version, delegate.downloadURL)
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String : String] = [:]) {
        currentText = ""
        if elementName == "item" {
            seenItem = true
        }
        if seenItem && elementName == "enclosure" && downloadURL == nil {
            downloadURL = attributeDict["url"]
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        currentText += string
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        if seenItem && version == nil && (elementName == "sparkle:shortVersionString" || elementName == "sparkle:version") {
            let value = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
            if !value.isEmpty {
                version = value
            }
        }
    }
}

struct AboutCenterView: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject private var licenseManager = AetherLicenseManager.shared
    @ObservedObject private var updaterManager = AetherUpdaterManager.shared

    @State private var emailInput: String = ""
    @State private var codeInput: String = ""
    @State private var referralInput: String = ""
    @State private var devicesExpanded: Bool = false
    private let actionColumns = [
        GridItem(.flexible(minimum: 280), spacing: 16),
        GridItem(.flexible(minimum: 280), spacing: 16)
    ]

    private var isChinese: Bool { appState.isChineseUI }
    private var appDisplayName: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? Bundle.main.object(forInfoDictionaryKey: kCFBundleNameKey as String) as? String
            ?? "Aether"
    }

    private var statusTint: Color {
        licenseManager.isActivated ? .green : .secondary
    }

    private var latestVersionDisplay: String {
        updaterManager.latestVersion ?? "-"
    }

    var body: some View {
        SettingsPage(
            title: isChinese ? "关于" : "About",
            subtitle: isChinese ? "这里只保留状态、授权和更新，技术细节不占首屏。" : "This page keeps only status, licensing, and updates on the first screen."
        ) {
            overviewCard

            LazyVGrid(columns: actionColumns, alignment: .leading, spacing: 16) {
                licenseCard
                updatesCard
                supportCard
            }
        }
        .onAppear {
            emailInput = licenseManager.email
            codeInput = licenseManager.licenseKey
        }
    }

    private var overviewCard: some View {
        GlassCard(padding: 18) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 14) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Color.accentColor.opacity(0.14))
                            .frame(width: 52, height: 52)

                        Image(systemName: "app.connected.to.app.below.fill")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(Color.accentColor)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text(appDisplayName)
                            .font(.title2.weight(.bold))
                        Text(isChinese ? "当前应用状态" : "Current App Status")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    statusBadge(licenseManager.statusSummary, tint: statusTint)
                }

                LazyVGrid(columns: actionColumns, alignment: .leading, spacing: 10) {
                    metricTile(title: isChinese ? "版本" : "Version", value: appState.appVersionDisplay)
                    metricTile(title: isChinese ? "方案" : "Plan", value: licenseManager.planSummary)
                    metricTile(title: isChinese ? "设备占用" : "Devices", value: "\(licenseManager.devicesUsed) / \(licenseManager.maxDevices)")
                    metricTile(title: isChinese ? "最新版本" : "Latest Version", value: latestVersionDisplay)
                }
            }
        }
    }

    private var licenseCard: some View {
        infoCard(title: isChinese ? "授权" : "License") {
            HStack(alignment: .firstTextBaseline) {
                Text(isChinese ? "当前状态" : "Current Status")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                statusBadge(licenseManager.statusSummary, tint: statusTint)
            }
            LabeledContent(isChinese ? "方案" : "Plan", value: licenseManager.planSummary)
            LabeledContent(isChinese ? "试用截止" : "Trial ends", value: licenseManager.trialEndsAt ?? "-")
            LabeledContent(isChinese ? "订阅截止" : "Subscription ends", value: licenseManager.subscriptionEndsAt ?? "-")
            if let referralCode = licenseManager.referralCode, !referralCode.isEmpty {
                LabeledContent(isChinese ? "我的邀请码" : "My referral code", value: referralCode)
            }
            Divider()
            Text(isChinese ? "输入邮箱与激活码后可恢复授权；没有激活码时可直接开始试用。" : "Use your email and activation code to restore access, or start a trial if you do not have one yet.")
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField(isChinese ? "邮箱" : "Email", text: $emailInput)
                .textFieldStyle(.roundedBorder)
                .controlSize(.regular)
            TextField(isChinese ? "激活码" : "Activation code", text: $codeInput)
                .textFieldStyle(.roundedBorder)
                .controlSize(.regular)
            TextField(isChinese ? "邀请码（可选）" : "Referral code (optional)", text: $referralInput)
                .textFieldStyle(.roundedBorder)
                .controlSize(.regular)
            HStack {
                Button(isChinese ? "激活" : "Activate") {
                    Task { await licenseManager.activate(email: emailInput, code: codeInput) }
                }
                .buttonStyle(.borderedProminent)
                Button(isChinese ? "开始试用" : "Start Trial") {
                    Task {
                        await licenseManager.startTrial(email: emailInput, referralCode: referralInput.isEmpty ? nil : referralInput)
                        codeInput = licenseManager.licenseKey
                    }
                }
                .buttonStyle(.bordered)
                Button(isChinese ? "重发邮件" : "Resend Email") {
                    Task { await licenseManager.resendActivation(email: emailInput) }
                }
                .buttonStyle(.bordered)
                Button(isChinese ? "刷新状态" : "Refresh") {
                    Task { await licenseManager.refreshEntitlement() }
                }
                .buttonStyle(.bordered)
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
        }
    }

    private var updatesCard: some View {
        infoCard(title: isChinese ? "更新" : "Updates") {
            Picker(isChinese ? "渠道" : "Channel", selection: Binding(
                get: { updaterManager.channel },
                set: {
                    updaterManager.setUpdateChannel($0)
                    licenseManager.setChannelPreference($0)
                }
            )) {
                Text("Stable").tag(AetherUpdateChannel.stable)
                Text("Beta").tag(AetherUpdateChannel.beta)
            }
            .pickerStyle(.segmented)
            .controlSize(.small)

            LabeledContent(isChinese ? "最新版本" : "Latest version", value: latestVersionDisplay)
            LabeledContent(
                isChinese ? "更新状态" : "Update status",
                value: updaterManager.statusMessage.isEmpty ? "-" : updaterManager.statusMessage
            )

            HStack {
                Button(isChinese ? "检查更新" : "Check for Updates") {
                    Task { await updaterManager.checkForUpdates() }
                }
                .buttonStyle(.borderedProminent)
                Button(isChinese ? "打开下载" : "Open Download") {
                    updaterManager.openLatestDownload()
                }
                .buttonStyle(.bordered)
            }
            .controlSize(.small)
        }
    }

    private var supportCard: some View {
        infoCard(title: isChinese ? "支持" : "Support") {
            HStack(spacing: 8) {
                linkButton(title: isChinese ? "官网" : "Website", key: "AetherWebsiteURL", fallback: "https://aether.7caifei.com")
                linkButton(title: isChinese ? "下载页" : "Downloads", key: "AetherDownloadPageURL", fallback: "https://aether.7caifei.com/download")
                linkButton(title: isChinese ? "更新日志" : "Changelog", key: "AetherChangelogURL", fallback: "https://aether.7caifei.com/changelog")
            }
            .controlSize(.small)

            Divider()

            DisclosureGroup(isExpanded: $devicesExpanded) {
                VStack(alignment: .leading, spacing: 12) {
                    if licenseManager.devices.isEmpty {
                        Text(isChinese ? "当前没有已同步的设备信息。" : "No synced devices yet.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(licenseManager.devices) { device in
                            HStack(alignment: .top, spacing: 12) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(device.name).font(.headline)
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
                .padding(.top, 6)
            } label: {
                disclosureLabel(
                    title: isChinese ? "设备管理" : "Device Management",
                    trailing: "\(licenseManager.devices.count)"
                )
            }
            .controlSize(.small)
        }
    }

    private func infoCard<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        GlassCard(padding: 18) {
            VStack(alignment: .leading, spacing: 14) {
                Text(title)
                    .font(.title3.weight(.semibold))
                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(maxHeight: .infinity, alignment: .top)
        }
    }

    private func metricTile(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.headline.monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.86)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.55))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func statusBadge(_ title: String, tint: Color) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(tint.opacity(0.14))
            .foregroundStyle(tint)
            .clipShape(Capsule())
    }

    private func disclosureLabel(title: String, trailing: String) -> some View {
        HStack {
            Text(title)
                .font(.body.weight(.semibold))
            Spacer()
            Text(trailing)
                .font(.caption.weight(.semibold).monospacedDigit())
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.accentColor.opacity(0.12))
                .foregroundStyle(Color.accentColor)
                .clipShape(Capsule())
        }
    }

    private func linkButton(title: String, key: String, fallback: String) -> some View {
        Button(title) {
            let value = Bundle.main.object(forInfoDictionaryKey: key) as? String ?? fallback
            if let url = URL(string: value) {
                NSWorkspace.shared.open(url)
            }
        }
        .buttonStyle(.bordered)
    }
}
