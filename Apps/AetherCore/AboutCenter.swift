import SwiftUI
import AppKit
import Combine
import CryptoKit

struct AetherEntitlementDevice: Identifiable {
    let id: String
    let name: String
    let activatedAt: String?
    let lastSeenAt: String?
    let isCurrent: Bool
}

private struct AetherEntitlementSnapshot: Codable {
    var status: String
    var plan: String
    var trialEndsAt: String?
    var subscriptionEndsAt: String?
    var devicesUsed: Int
    var maxDevices: Int
    var channel: String
    var referralCode: String?
    var verifiedAt: Date
}

private struct AetherEntitlementTokenClaims: Codable {
    var sub: String?
    var email: String?
    var deviceId: String?
    var appId: String?
    var status: String
    var plan: String
    var trialEndsAt: String?
    var subscriptionEndsAt: String?
    var devicesUsed: Int?
    var maxDevices: Int?
    var channel: String?
    var referralCode: String?
    var exp: TimeInterval
    var iat: TimeInterval?
}

enum AetherUpdateChannel: String, CaseIterable, Identifiable {
    case stable
    case beta

    var id: String { rawValue }
}

enum AetherEntitlementGateState: Equatable {
    case loading
    case active
    case trialing
    case inactive
    case expired
    case deviceLimitReached

    var allowsProductAccess: Bool {
        switch self {
        case .active, .trialing:
            return true
        case .loading, .inactive, .expired, .deviceLimitReached:
            return false
        }
    }
}

@MainActor
final class AetherLicenseManager: ObservableObject {
    static let shared = AetherLicenseManager()
    private static let entitlementSnapshotStorageKey = "aether.license.snapshot.v1"
    private static let entitlementTokenStorageKey = "aether.license.token.v1"
    private static let offlineGraceInterval: TimeInterval = 7 * 24 * 60 * 60

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
    @Published private(set) var isRefreshingEntitlement: Bool = true
    @Published private(set) var gateState: AetherEntitlementGateState = .loading
    @Published private(set) var isUsingOfflineGraceAccess: Bool = false

    private init() {
        restoreTokenIfAvailable()
        restoreSnapshotIfAvailable()
        Task {
            await refreshEntitlement()
        }
    }

    var isActivated: Bool {
        ["active", "trialing", "valid", "activated"].contains(status)
    }

    var isProductUnlocked: Bool {
        gateState.allowsProductAccess
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
        isRefreshingEntitlement = true
        recomputeGateState()
        guard !email.isEmpty, !licenseKey.isEmpty else {
            status = "inactive"
            devices = []
            isRefreshingEntitlement = false
            recomputeGateState()
            return
        }
        await verifyCurrentCredentials()
    }

    func fetchDevices() async {
        guard canManageDevices else { return }
        do {
            let json = try await postJSON(path: "/devices", body: credentialBody())
            devices = parseDevices(json["devices"])
            updateSharedState(from: json)
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    func removeDevice(deviceId: String) async {
        guard canManageDevices else { return }
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

    func startTrial(email: String, referralCode: String?) async {
        self.email = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        persistCredentials()
        do {
            var body: [String: Any] = [
                "email": self.email,
                "deviceId": installationID,
                "appId": appBundleID,
                "channel": channel,
                "deviceModel": Host.current().localizedName ?? "Mac",
                "osVersion": ProcessInfo.processInfo.operatingSystemVersionString,
                "appVersion": Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0",
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
        isUsingOfflineGraceAccess = false
        isRefreshingEntitlement = true
        recomputeGateState()

        do {
            let json = try await postJSON(path: "/verify", body: credentialBody())
            updateSharedState(from: json)
            await fetchDevices()
        } catch {
            lastErrorMessage = error.localizedDescription
            if !restoreRecentUnlockedSnapshot() {
                status = "inactive"
                devices = []
            }
        }
        isRefreshingEntitlement = false
        recomputeGateState()
    }

    private var canManageDevices: Bool {
        isActivated || status == "limit_reached" || status == "device_limit_reached"
    }

    private func recomputeGateState() {
        if isRefreshingEntitlement {
            gateState = .loading
            return
        }

        switch status {
        case "active", "valid", "activated":
            gateState = .active
        case "trialing":
            gateState = .trialing
        case "expired":
            gateState = .expired
        case "limit_reached", "device_limit_reached":
            gateState = .deviceLimitReached
        default:
            gateState = .inactive
        }
    }

    private func updateSharedState(from json: [String: Any]) {
        if let token = entitlementToken(from: json),
           let claims = verifyEntitlementToken(token) {
            apply(claims: claims)
            persistEntitlementToken(token)
        } else {
            UserDefaults.standard.removeObject(forKey: Self.entitlementTokenStorageKey)
            if let value = json["status"] as? String { status = value }
            if let value = json["plan"] as? String { plan = value }
            if let value = json["trialEndsAt"] as? String, !value.isEmpty { trialEndsAt = value } else { trialEndsAt = nil }
            if let value = json["subscriptionEndsAt"] as? String, !value.isEmpty { subscriptionEndsAt = value } else { subscriptionEndsAt = nil }
            if let value = json["devicesUsed"] as? Int { devicesUsed = value }
            if let value = json["maxDevices"] as? Int { maxDevices = value }
            if let value = json["channel"] as? String { channel = value }
            if let value = json["referralCode"] as? String { referralCode = value }
        }
        if let value = json["licenseKey"] as? String, !value.isEmpty {
            licenseKey = value
            persistCredentials()
        }
        if let value = json["message"] as? String, !value.isEmpty {
            infoMessage = value
        }
        isUsingOfflineGraceAccess = false
        persistSnapshotIfEligible()
    }

    private func persistSnapshotIfEligible() {
        guard isActivated else { return }
        let snapshot = AetherEntitlementSnapshot(
            status: status,
            plan: plan,
            trialEndsAt: trialEndsAt,
            subscriptionEndsAt: subscriptionEndsAt,
            devicesUsed: devicesUsed,
            maxDevices: maxDevices,
            channel: channel,
            referralCode: referralCode,
            verifiedAt: Date()
        )
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        UserDefaults.standard.set(data, forKey: Self.entitlementSnapshotStorageKey)
    }

    private func restoreSnapshotIfAvailable() {
        guard UserDefaults.standard.string(forKey: Self.entitlementTokenStorageKey) == nil else { return }
        guard let data = UserDefaults.standard.data(forKey: Self.entitlementSnapshotStorageKey),
              let snapshot = try? JSONDecoder().decode(AetherEntitlementSnapshot.self, from: data) else {
            return
        }
        guard snapshotStillGrantsAccess(snapshot) else { return }
        apply(snapshot: snapshot)
        isRefreshingEntitlement = false
        isUsingOfflineGraceAccess = true
        recomputeGateState()
    }

    private func restoreRecentUnlockedSnapshot() -> Bool {
        if restoreRecentUnlockedToken() {
            return true
        }
        guard let data = UserDefaults.standard.data(forKey: Self.entitlementSnapshotStorageKey),
              let snapshot = try? JSONDecoder().decode(AetherEntitlementSnapshot.self, from: data),
              snapshotStillGrantsAccess(snapshot) else {
            return false
        }
        apply(snapshot: snapshot)
        isUsingOfflineGraceAccess = true
        return true
    }

    private func snapshotStillGrantsAccess(_ snapshot: AetherEntitlementSnapshot) -> Bool {
        guard ["active", "trialing", "valid", "activated"].contains(snapshot.status),
              Date().timeIntervalSince(snapshot.verifiedAt) <= Self.offlineGraceInterval else {
            return false
        }

        let formatter = ISO8601DateFormatter()
        let now = Date()
        if let trialEndsAt = snapshot.trialEndsAt,
           let trialEndDate = formatter.date(from: trialEndsAt),
           now > trialEndDate {
            return false
        }
        if let subscriptionEndsAt = snapshot.subscriptionEndsAt,
           let subscriptionEndDate = formatter.date(from: subscriptionEndsAt),
           now > subscriptionEndDate {
            return false
        }
        return true
    }

    private func apply(snapshot: AetherEntitlementSnapshot) {
        status = snapshot.status
        plan = snapshot.plan
        trialEndsAt = snapshot.trialEndsAt
        subscriptionEndsAt = snapshot.subscriptionEndsAt
        devicesUsed = snapshot.devicesUsed
        maxDevices = snapshot.maxDevices
        channel = snapshot.channel
        referralCode = snapshot.referralCode
    }

    private func apply(claims: AetherEntitlementTokenClaims) {
        status = claims.status
        plan = claims.plan
        trialEndsAt = claims.trialEndsAt
        subscriptionEndsAt = claims.subscriptionEndsAt
        devicesUsed = claims.devicesUsed ?? devicesUsed
        maxDevices = claims.maxDevices ?? maxDevices
        channel = claims.channel ?? channel
        referralCode = claims.referralCode
    }

    private func restoreTokenIfAvailable() {
        guard let token = UserDefaults.standard.string(forKey: Self.entitlementTokenStorageKey),
              let claims = verifyEntitlementToken(token) else {
            return
        }
        apply(claims: claims)
        isRefreshingEntitlement = false
        recomputeGateState()
    }

    private func restoreRecentUnlockedToken() -> Bool {
        guard let token = UserDefaults.standard.string(forKey: Self.entitlementTokenStorageKey),
              let claims = verifyEntitlementToken(token),
              ["active", "trialing", "valid", "activated"].contains(claims.status) else {
            return false
        }
        apply(claims: claims)
        isUsingOfflineGraceAccess = true
        return true
    }

    private func entitlementToken(from json: [String: Any]) -> String? {
        let candidates = ["entitlementToken", "signedEntitlementToken", "accessToken"]
        for key in candidates {
            if let token = json[key] as? String, !token.isEmpty {
                return token
            }
        }
        return nil
    }

    private func persistEntitlementToken(_ token: String) {
        UserDefaults.standard.set(token, forKey: Self.entitlementTokenStorageKey)
    }

    private func verifyEntitlementToken(_ token: String) -> AetherEntitlementTokenClaims? {
        let segments = token.split(separator: ".")
        guard segments.count == 3,
              let headerData = Data(base64URL: String(segments[0])),
              let payloadData = Data(base64URL: String(segments[1])),
              let signatureData = Data(base64URL: String(segments[2])),
              let header = try? JSONSerialization.jsonObject(with: headerData) as? [String: Any],
              let alg = header["alg"] as? String,
              alg == "ES256",
              let publicKey = entitlementTokenPublicKey(),
              let signature = try? P256.Signing.ECDSASignature(rawRepresentation: signatureData) else {
            return nil
        }

        let signingInput = Data("\(segments[0]).\(segments[1])".utf8)
        guard publicKey.isValidSignature(signature, for: signingInput),
              let claims = try? JSONDecoder().decode(AetherEntitlementTokenClaims.self, from: payloadData) else {
            return nil
        }

        guard Date().timeIntervalSince1970 <= claims.exp else { return nil }
        if let deviceId = claims.deviceId, deviceId != installationID { return nil }
        if let appId = claims.appId, appId != appBundleID { return nil }
        if let claimEmail = claims.email ?? claims.sub,
           !email.isEmpty,
           claimEmail.lowercased() != email.lowercased() {
            return nil
        }
        return claims
    }

    private func entitlementTokenPublicKey() -> P256.Signing.PublicKey? {
        guard let pem = Bundle.main.object(forInfoDictionaryKey: "AetherAuthJWTPublicKeyPEM") as? String,
              !pem.isEmpty else {
            return nil
        }
        let normalizedPEM = pem.replacingOccurrences(of: "\\n", with: "\n")
        return try? P256.Signing.PublicKey(pemRepresentation: normalizedPEM)
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
        isRefreshingEntitlement = false
        isUsingOfflineGraceAccess = false
        recomputeGateState()
        UserDefaults.standard.removeObject(forKey: "aether.license.email")
        UserDefaults.standard.removeObject(forKey: "aether.license.key")
        UserDefaults.standard.removeObject(forKey: Self.entitlementSnapshotStorageKey)
        UserDefaults.standard.removeObject(forKey: Self.entitlementTokenStorageKey)
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

private extension Data {
    init?(base64URL value: String) {
        var base64 = value
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = base64.count % 4
        if remainder != 0 {
            base64.append(String(repeating: "=", count: 4 - remainder))
        }
        self.init(base64Encoded: base64)
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
    @State private var showsLicenseSheet: Bool = false
    @State private var showsDevicesSheet: Bool = false

    private var isChinese: Bool { appState.isChineseUI }
    private var appDisplayName: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? Bundle.main.object(forInfoDictionaryKey: kCFBundleNameKey as String) as? String
            ?? "Aether"
    }

    private var appIcon: NSImage {
        NSApp.applicationIconImage
    }

    private var statusTint: Color {
        licenseManager.isActivated ? .green : .secondary
    }

    private var latestVersionDisplay: String {
        updaterManager.latestVersion ?? "-"
    }

    private var statusPillTitle: String {
        if licenseManager.isActivated {
            return isChinese ? "\(licenseManager.planSummary) 已激活" : "\(licenseManager.planSummary) Active"
        }
        return licenseManager.statusSummary
    }

    private var tagline: String {
        isChinese ? "抬头即达，开口即控" : "Hands-free control for your Mac"
    }

    var body: some View {
        SettingsPage(
            title: isChinese ? "关于" : "About",
            subtitle: isChinese ? "应用信息、授权状态与更新入口。" : "App info, license status, and update entry points."
        ) {
            VStack(spacing: 0) {
                Spacer(minLength: 20)

                Image(nsImage: appIcon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 128, height: 128)
                    .shadow(color: Color.accentColor.opacity(0.28), radius: 20, x: 0, y: 10)
                    .padding(.bottom, 22)

                Text(appDisplayName)
                    .font(.system(size: 36, weight: .bold, design: .rounded))

                Text(appState.appVersionDisplay)
                    .font(.system(.title3, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)

                Button {
                    Task { await updaterManager.checkForUpdates() }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.clockwise.circle")
                        Text(isChinese ? "检查更新" : "Check for Updates")
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
                .padding(.top, 14)

                VStack(spacing: 8) {
                    Text(tagline)
                        .font(.headline)
                        .foregroundStyle(.secondary)

                    Text("© 2026 Aether Team")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .padding(.top, 36)

                if licenseManager.isActivated {
                    HStack(spacing: 10) {
                        Image(systemName: "crown.fill")
                            .foregroundStyle(.orange)
                        Text(statusPillTitle)
                            .fontWeight(.bold)
                            .foregroundStyle(.orange)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 14)
                    .background(Color.orange.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .padding(.top, 22)
                } else {
                    HStack(spacing: 10) {
                        Image(systemName: "key.fill")
                            .foregroundStyle(.secondary)
                        Text(statusPillTitle)
                            .fontWeight(.medium)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 12)
                    .background(Color(nsColor: .controlBackgroundColor).opacity(0.55))
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .padding(.top, 22)
                }

                if !updaterManager.statusMessage.isEmpty {
                    Text(updaterManager.statusMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.top, 12)
                } else if let info = licenseManager.infoMessage, !info.isEmpty {
                    Text(info)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.top, 12)
                } else if let error = licenseManager.lastErrorMessage, !error.isEmpty {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .padding(.top, 12)
                }

                Spacer()

                Divider()
                    .padding(.horizontal, 38)

                HStack(spacing: 22) {
                    footerLink(title: isChinese ? "访问官网" : "Website", key: "AetherWebsiteURL", fallback: "https://aether.7caifei.com")

                    footerLink(title: isChinese ? "更新日志" : "Changelog", key: "AetherChangelogURL", fallback: "https://aether.7caifei.com/changelog")

                    Button(isChinese ? "管理授权" : "Manage License") {
                        showsLicenseSheet = true
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.blue)

                    Button(isChinese ? "设备管理" : "Manage Devices") {
                        showsDevicesSheet = true
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.blue)
                }
                .font(.callout)
                .padding(.vertical, 24)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .sheet(isPresented: $showsLicenseSheet) {
            AboutLicenseSheet(
                emailInput: $emailInput,
                codeInput: $codeInput,
                referralInput: $referralInput
            )
            .environmentObject(appState)
        }
        .sheet(isPresented: $showsDevicesSheet) {
            AboutDevicesSheet()
                .environmentObject(appState)
        }
        .onAppear {
            emailInput = licenseManager.email
            codeInput = licenseManager.licenseKey
        }
    }

    private func footerLink(title: String, key: String, fallback: String) -> some View {
        Button(title) {
            let value = Bundle.main.object(forInfoDictionaryKey: key) as? String ?? fallback
            if let url = URL(string: value) {
                NSWorkspace.shared.open(url)
            }
        }
        .buttonStyle(.plain)
        .foregroundStyle(.blue)
    }

    private func statusBadge(_ title: String, tint: Color) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(tint.opacity(0.14))
            .foregroundStyle(tint)
            .clipShape(Capsule())
    }
}

private struct AboutLicenseSheet: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject private var licenseManager = AetherLicenseManager.shared
    @Binding var emailInput: String
    @Binding var codeInput: String
    @Binding var referralInput: String

    private var isChinese: Bool { appState.isChineseUI }

    var body: some View {
        SettingsPage(
            title: isChinese ? "授权管理" : "License Management",
            subtitle: isChinese ? "处理激活、试用和状态刷新。" : "Manage activation, trial, and refresh actions."
        ) {
            if licenseManager.isActivated {
                activatedView
            } else {
                activationFormView
            }
        }
        .frame(minWidth: 620, minHeight: 340)
    }

    private var activatedView: some View {
        GlassCard(padding: 22) {
            VStack(spacing: 22) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 58))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.blue, .cyan],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )

                VStack(spacing: 6) {
                    Text(isChinese ? "Aether 已激活" : "Aether Activated")
                        .font(.title2.weight(.bold))
                    Text(isChinese ? "感谢支持独立开发。" : "Thank you for supporting indie development.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Label {
                        Text(licenseManager.planSummary)
                    } icon: {
                        Image(systemName: "crown")
                    }

                    Spacer()

                    Label {
                        Text("\(licenseManager.devicesUsed)/\(licenseManager.maxDevices) \(isChinese ? "台设备" : "devices")")
                    } icon: {
                        Image(systemName: "laptopcomputer")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                HStack(spacing: 10) {
                    Button(isChinese ? "刷新状态" : "Refresh") {
                        Task { await licenseManager.refreshEntitlement() }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }

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
            .frame(maxWidth: .infinity)
        }
    }

    private var activationFormView: some View {
        GlassCard(padding: 18) {
            VStack(alignment: .leading, spacing: 14) {
                Text(isChinese ? "输入邮箱与激活码进行授权；没有激活码时可以开始试用。" : "Enter your email and activation code, or start a trial if you do not have one yet.")
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
    }
}

private struct AboutDevicesSheet: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject private var licenseManager = AetherLicenseManager.shared

    private var isChinese: Bool { appState.isChineseUI }

    var body: some View {
        SettingsPage(
            title: isChinese ? "设备管理" : "Device Management",
            subtitle: isChinese ? "查看当前授权下的设备，并在需要时移除。" : "Review devices linked to the current license and remove them when needed."
        ) {
            GlassCard(padding: 18) {
                VStack(alignment: .leading, spacing: 12) {
                    if licenseManager.devices.isEmpty {
                        Text(isChinese ? "当前没有已同步的设备信息。" : "No synced devices yet.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(licenseManager.devices) { device in
                            HStack(alignment: .top, spacing: 12) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(device.name)
                                        .font(.headline)
                                    Text(device.isCurrent ? (isChinese ? "当前设备" : "Current device") : (isChinese ? "其他设备" : "Other device"))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Text("\(isChinese ? "激活于" : "Activated") \(device.activatedAt ?? "-")")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                    Text("\(isChinese ? "最近在线" : "Last seen") \(device.lastSeenAt ?? "-")")
                                        .font(.caption2)
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
            }
        }
        .frame(minWidth: 620, minHeight: 380)
    }
}
