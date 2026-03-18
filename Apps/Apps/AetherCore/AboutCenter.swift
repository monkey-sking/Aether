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
        Bundle.main.object(forInfoDictionaryKey: "AetherAuthBaseURL") as? String ?? "https://auth.aether.app"
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

    @Published var channel: AetherUpdateChannel = {
        let raw = UserDefaults.standard.string(forKey: "aether.update.channel") ?? "stable"
        return AetherUpdateChannel(rawValue: raw) ?? .stable
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
    }

    func openLatestDownload() {
        let target = latestDownloadURL ?? (channel == .beta ? betaDownloadURL : stableDownloadURL)
        if let target, let url = URL(string: target) {
            NSWorkspace.shared.open(url)
        }
    }

    private func refreshFeedString() {
        feedURLString = channel == .beta ? betaFeedURL : stableFeedURL
    }

    private var stableFeedURL: String {
        Bundle.main.object(forInfoDictionaryKey: "AetherStableFeedURL") as? String ?? "https://aether.app/aether/appcast.xml"
    }

    private var betaFeedURL: String {
        Bundle.main.object(forInfoDictionaryKey: "AetherBetaFeedURL") as? String ?? "https://aether.app/aether-beta/appcast.xml"
    }

    private var stableDownloadURL: String? {
        Bundle.main.object(forInfoDictionaryKey: "AetherDownloadURL") as? String
    }

    private var betaDownloadURL: String? {
        Bundle.main.object(forInfoDictionaryKey: "AetherBetaDownloadURL") as? String
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

    private var isChinese: Bool { appState.isChineseUI }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                headerCard
                subscriptionCard
                activationCard
                devicesCard
                updatesCard
                installNotesCard
            }
            .padding(24)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            emailInput = licenseManager.email
            codeInput = licenseManager.licenseKey
        }
    }

    private var headerCard: some View {
        card(title: isChinese ? "App 信息" : "App Info") {
            LabeledContent(isChinese ? "版本" : "Version", value: appState.appVersionDisplay)
            LabeledContent(isChinese ? "系统要求" : "System", value: "macOS 15.0+")
            linkRow(title: isChinese ? "官网" : "Website", key: "AetherWebsiteURL", fallback: "https://aether.app")
            linkRow(title: isChinese ? "下载页" : "Downloads", key: "AetherDownloadPageURL", fallback: "https://aether.app/download")
            linkRow(title: isChinese ? "更新日志" : "Changelog", key: "AetherChangelogURL", fallback: "https://aether.app/changelog")
        }
    }

    private var subscriptionCard: some View {
        card(title: isChinese ? "订阅状态" : "Subscription Status") {
            LabeledContent(isChinese ? "当前状态" : "Status", value: licenseManager.statusSummary)
            LabeledContent(isChinese ? "方案" : "Plan", value: licenseManager.planSummary)
            LabeledContent(isChinese ? "试用截止" : "Trial ends", value: licenseManager.trialEndsAt ?? "-")
            LabeledContent(isChinese ? "订阅截止" : "Subscription ends", value: licenseManager.subscriptionEndsAt ?? "-")
            LabeledContent(isChinese ? "设备占用" : "Devices", value: "\(licenseManager.devicesUsed) / \(licenseManager.maxDevices)")
            if let referralCode = licenseManager.referralCode, !referralCode.isEmpty {
                LabeledContent(isChinese ? "我的邀请码" : "My referral code", value: referralCode)
            }
            Divider()
            TextField(isChinese ? "邮箱" : "Email", text: $emailInput)
                .textFieldStyle(.roundedBorder)
            TextField(isChinese ? "邀请码（可选）" : "Referral code (optional)", text: $referralInput)
                .textFieldStyle(.roundedBorder)
            HStack {
                Button(isChinese ? "开始试用" : "Start Trial") {
                    Task {
                        await licenseManager.startTrial(email: emailInput, referralCode: referralInput.isEmpty ? nil : referralInput)
                        codeInput = licenseManager.licenseKey
                    }
                }
                .buttonStyle(.borderedProminent)
                Button(isChinese ? "刷新状态" : "Refresh") {
                    Task { await licenseManager.refreshEntitlement() }
                }
            }
        }
    }

    private var activationCard: some View {
        card(title: isChinese ? "激活中心" : "Activation") {
            TextField(isChinese ? "邮箱" : "Email", text: $emailInput)
                .textFieldStyle(.roundedBorder)
            TextField(isChinese ? "激活码" : "Activation code", text: $codeInput)
                .textFieldStyle(.roundedBorder)
            HStack {
                Button(isChinese ? "激活" : "Activate") {
                    Task { await licenseManager.activate(email: emailInput, code: codeInput) }
                }
                .buttonStyle(.borderedProminent)
                Button(isChinese ? "重发邮件" : "Resend Email") {
                    Task { await licenseManager.resendActivation(email: emailInput) }
                }
            }
            if let info = licenseManager.infoMessage, !info.isEmpty {
                Text(info).foregroundStyle(.secondary)
            }
            if let error = licenseManager.lastErrorMessage, !error.isEmpty {
                Text(error).foregroundStyle(.red)
            }
        }
    }

    private var devicesCard: some View {
        card(title: isChinese ? "设备管理" : "Devices") {
            if licenseManager.devices.isEmpty {
                Text(isChinese ? "当前没有已同步的设备信息。" : "No synced devices yet.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(licenseManager.devices) { device in
                    HStack(alignment: .top) {
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
                    }
                    if device.id != licenseManager.devices.last?.id {
                        Divider()
                    }
                }
            }
            Button(isChinese ? "刷新设备列表" : "Refresh devices") {
                Task { await licenseManager.fetchDevices() }
            }
        }
    }

    private var updatesCard: some View {
        card(title: isChinese ? "更新渠道" : "Updates") {
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

            LabeledContent(isChinese ? "当前 Feed" : "Current feed", value: updaterManager.feedURLString)
            LabeledContent(isChinese ? "最新版本" : "Latest version", value: updaterManager.latestVersion ?? "-")

            HStack {
                Button(isChinese ? "检查更新" : "Check for Updates") {
                    Task { await updaterManager.checkForUpdates() }
                }
                .buttonStyle(.borderedProminent)
                Button(isChinese ? "打开下载" : "Open Download") {
                    updaterManager.openLatestDownload()
                }
            }

            if !updaterManager.statusMessage.isEmpty {
                Text(updaterManager.statusMessage).foregroundStyle(.secondary)
            }
        }
    }

    private var installNotesCard: some View {
        card(title: isChinese ? "下载与更新说明" : "Install Notes") {
            VStack(alignment: .leading, spacing: 8) {
                Text(isChinese ? "1. 首次安装请将 App 拖到 /Applications 后再授予权限。" : "1. Move the app into /Applications before granting permissions.")
                Text(isChinese ? "2. 正式版和 Beta 使用不同的 feed 与下载地址。" : "2. Stable and Beta use different feeds and download URLs.")
                Text(isChinese ? "3. Beta 面向所有用户开放，但稳定性会低于正式版。" : "3. Beta is public, but stability is lower than Stable.")
            }
            .foregroundStyle(.secondary)
        }
    }

    private func card<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(.title3.weight(.semibold))
            content()
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }

    private func linkRow(title: String, key: String, fallback: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Button(Bundle.main.object(forInfoDictionaryKey: key) as? String ?? fallback) {
                let value = Bundle.main.object(forInfoDictionaryKey: key) as? String ?? fallback
                if let url = URL(string: value) {
                    NSWorkspace.shared.open(url)
                }
            }
            .buttonStyle(.link)
        }
    }
}
