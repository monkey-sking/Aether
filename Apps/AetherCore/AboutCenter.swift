import SwiftUI
import AppKit
import Combine
import CryptoKit
import Security

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

    var versionDisplayChannel: AetherBuildVersionFormatter.DisplayChannel {
        switch self {
        case .stable:
            return .stable
        case .beta:
            return .beta
        }
    }
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
    private static let installationIDStorageKey = "aether.installation.id"
    private static let installationIDKeychainService = "com.7fei.Aether.installation"
    private static let installationIDKeychainAccount = "default-device-id"
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
    @Published private(set) var isFetchingDevices: Bool = false
    @Published private(set) var isRefreshingEntitlement: Bool = false
    @Published private(set) var gateState: AetherEntitlementGateState = .loading
    @Published private(set) var isUsingOfflineGraceAccess: Bool = false

    private var cachedInstallationID: String?

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
        guard !isRefreshingEntitlement else { return }
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
        guard canManageDevices, !isFetchingDevices else { return }
        lastErrorMessage = nil
        isFetchingDevices = true
        defer { isFetchingDevices = false }
        do {
            let json = try await postDeviceManagementJSON(path: "/devices")
            devices = parseDevices(json["devices"])
            updateSharedState(from: json)
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    func removeDevice(deviceId: String) async {
        guard canManageDevices else { return }
        lastErrorMessage = nil
        do {
            let json = try await postDeviceManagementJSON(path: "/devices/remove", targetDeviceId: deviceId)
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

    private func postDeviceManagementJSON(path: String, targetDeviceId: String? = nil) async throws -> [String: Any] {
        do {
            return try await postJSON(path: path, body: deviceManagementBody(includeCurrentDeviceID: true, targetDeviceId: targetDeviceId))
        } catch {
            guard shouldRetryDeviceManagementWithoutCurrentDevice(after: error) else {
                throw error
            }
            return try await postJSON(path: path, body: deviceManagementBody(includeCurrentDeviceID: false, targetDeviceId: targetDeviceId))
        }
    }

    private func deviceManagementBody(includeCurrentDeviceID: Bool, targetDeviceId: String? = nil) -> [String: Any] {
        var body = credentialBody()
        if !includeCurrentDeviceID {
            body.removeValue(forKey: "deviceId")
        }
        if let targetDeviceId {
            body["targetDeviceId"] = targetDeviceId
        }
        return body
    }

    private func shouldRetryDeviceManagementWithoutCurrentDevice(after error: Error) -> Bool {
        let nsError = error as NSError
        if nsError.code == 401 {
            return true
        }
        let message = nsError.localizedDescription.lowercased()
        return message.contains("device not authorized")
            || message.contains("device unauthorized")
            || message.contains("设备未授权")
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
        if let cachedInstallationID, !cachedInstallationID.isEmpty {
            return cachedInstallationID
        }
        if let stored = AetherInstallationIDKeychain.load(
            service: Self.installationIDKeychainService,
            account: Self.installationIDKeychainAccount
        ) {
            cachedInstallationID = stored
            UserDefaults.standard.set(stored, forKey: Self.installationIDStorageKey)
            return stored
        }
        if let legacy = UserDefaults.standard.string(forKey: Self.installationIDStorageKey),
           !legacy.isEmpty {
            cachedInstallationID = legacy
            _ = AetherInstallationIDKeychain.save(
                legacy,
                service: Self.installationIDKeychainService,
                account: Self.installationIDKeychainAccount
            )
            return legacy
        }

        let value = UUID().uuidString
        cachedInstallationID = value
        UserDefaults.standard.set(value, forKey: Self.installationIDStorageKey)
        _ = AetherInstallationIDKeychain.save(
            value,
            service: Self.installationIDKeychainService,
            account: Self.installationIDKeychainAccount
        )
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

private enum AetherInstallationIDKeychain {
    static func load(service: String, account: String) -> String? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne,
        ]

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess else {
            return nil
        }
        guard let data = result as? Data,
              let value = String(data: data, encoding: .utf8),
              !value.isEmpty else {
            return nil
        }
        return value
    }

    static func save(_ value: String, service: String, account: String) -> Bool {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
        ]
        let attributes: [CFString: Any] = [
            kSecValueData: Data(value.utf8),
        ]

        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        switch updateStatus {
        case errSecSuccess:
            return true
        case errSecItemNotFound:
            var addQuery = query
            addQuery.merge(attributes) { _, new in new }
            return SecItemAdd(addQuery as CFDictionary, nil) == errSecSuccess
        default:
            return false
        }
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
    @Published private(set) var statusMessage: String = ""
    @Published private(set) var hasAvailableUpdate: Bool = false

    private init() {
        refreshFeedString()
    }

    private var currentShortVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    private var currentBuildVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
    }

    private var currentPublicLabel: String? {
        Bundle.main.object(forInfoDictionaryKey: "AetherPublicVersionLabel") as? String
    }

    func setUpdateChannel(_ channel: AetherUpdateChannel) {
        self.channel = channel
        AetherUpdateFeedResolver.setChannel(channel)
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
            latestVersion = AetherBuildVersionFormatter.versionDisplay(
                shortVersion: parsed.shortVersion,
                buildVersion: parsed.buildVersion,
                publicLabel: parsed.publicLabel,
                channel: channel.versionDisplayChannel
            )

            guard let remoteShort = parsed.shortVersion, !remoteShort.isEmpty else {
                hasAvailableUpdate = false
                statusMessage = AppLocalization.isChinese ? "更新源中没有可用版本。" : "No releases found in the feed."
                return
            }

            let currentDisplay = AetherBuildVersionFormatter.versionDisplay(
                shortVersion: currentShortVersion,
                buildVersion: currentBuildVersion,
                publicLabel: currentPublicLabel,
                channel: channel.versionDisplayChannel
            ) ?? currentShortVersion
            let comparedVersions = AetherBuildVersionFormatter.comparisonDisplay(
                updateShortVersion: parsed.shortVersion,
                updateBuildVersion: parsed.buildVersion,
                updatePublicLabel: parsed.publicLabel,
                bundleShortVersion: currentShortVersion,
                bundleBuildVersion: currentBuildVersion,
                bundlePublicLabel: currentPublicLabel,
                channel: channel.versionDisplayChannel
            )

            let shortCompare = remoteShort.compare(currentShortVersion, options: .numeric)
            let buildCompare: ComparisonResult
            if shortCompare == .orderedSame, let remoteBuild = parsed.buildVersion, !remoteBuild.isEmpty {
                buildCompare = remoteBuild.compare(currentBuildVersion, options: .numeric)
            } else {
                buildCompare = .orderedSame
            }

            if shortCompare == .orderedDescending || buildCompare == .orderedDescending {
                hasAvailableUpdate = true
                let updateDisplay = comparedVersions.update ?? latestVersion ?? remoteShort
                let bundleDisplay = comparedVersions.bundle ?? currentDisplay
                statusMessage = AppLocalization.isChinese
                    ? "发现新版本：\(updateDisplay)（当前 \(bundleDisplay)）"
                    : "Update available: \(updateDisplay) (current: \(bundleDisplay))."
            } else {
                hasAvailableUpdate = false
                let bundleDisplay = comparedVersions.bundle ?? currentDisplay
                statusMessage = AppLocalization.isChinese
                    ? "当前已是最新：\(bundleDisplay)"
                    : "Already on the latest version: \(bundleDisplay)."
            }
        } catch {
            hasAvailableUpdate = false
            statusMessage = error.localizedDescription
        }

        sparkleController.checkForUpdates()
    }

    func openLatestDownload() {
        // Sparkle feeds may point to versioned ZIP archives intended for auto-update.
        // For manual downloads, prefer the app's configured DMG URL (or page) instead.
        let target = (Bundle.main.object(forInfoDictionaryKey: "AetherDownloadPageURL") as? String)
            ?? AetherUpdateFeedResolver.downloadURLString(for: channel)
        if let target, let url = URL(string: target) { NSWorkspace.shared.open(url) }
    }

    private func refreshFeedString() {
        feedURLString = AetherUpdateFeedResolver.feedURLString(for: channel)
    }
}

private final class AppcastParser: NSObject, XMLParserDelegate {
    private var seenItem = false
    private var currentText = ""
    var shortVersion: String?
    var buildVersion: String?
    var publicLabel: String?

    static func parse(data: Data) -> (shortVersion: String?, buildVersion: String?, publicLabel: String?) {
        let delegate = AppcastParser()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.parse()
        return (delegate.shortVersion, delegate.buildVersion, delegate.publicLabel)
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String : String] = [:]) {
        currentText = ""
        if elementName == "item" {
            seenItem = true
        } else if seenItem, elementName == "enclosure", publicLabel == nil, let url = attributeDict["url"] {
            publicLabel = Self.extractPublicLabel(from: url)
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        currentText += string
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        guard seenItem else { return }
        let value = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.isEmpty { return }
        if elementName == "sparkle:shortVersionString", shortVersion == nil {
            shortVersion = value
        } else if elementName == "sparkle:version", buildVersion == nil {
            buildVersion = value
        }
    }

    private static func extractPublicLabel(from url: String) -> String? {
        AetherBuildVersionFormatter.publicLabel(from: url)
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

    private var isChinese: Bool { appState.isChineseUI }
    private var appDisplayName: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? Bundle.main.object(forInfoDictionaryKey: kCFBundleNameKey as String) as? String
            ?? "Aether"
    }

    private var appIcon: NSImage {
        NSApp.applicationIconImage
    }

    private var statusPillTitle: String {
        switch licenseManager.gateState {
        case .trialing:
            return isChinese ? "试用中" : "Trial Active"
        case .active:
            return isChinese ? "\(licenseManager.planSummary) 已激活" : "\(licenseManager.planSummary) Active"
        case .expired:
            return isChinese ? "授权已过期" : "License Expired"
        case .deviceLimitReached:
            return isChinese ? "设备数量已满" : "Device Limit Reached"
        case .inactive:
            return isChinese ? "尚未激活" : "Not Activated"
        case .loading:
            return isChinese ? "正在检查授权" : "Checking License"
        }
    }

    private var tagline: String {
        isChinese ? "首动意之所向，言出事之既成。" : "Move with intent. Command with a word."
    }

    private var compactStatusDetail: String {
        switch licenseManager.gateState {
        case .trialing:
            if let endsAt = formattedEntitlementDate(licenseManager.trialEndsAt) {
                return isChinese ? "试用至 \(endsAt)" : "Trial until \(endsAt)"
            }
            return isChinese ? "试用已启用" : "Trial is active"
        case .active:
            if let endsAt = formattedEntitlementDate(licenseManager.subscriptionEndsAt) {
                return isChinese ? "有效期至 \(endsAt)" : "Valid until \(endsAt)"
            }
            return isChinese ? "\(licenseManager.planSummary) 已激活" : "\(licenseManager.planSummary) active"
        case .expired:
            if let endsAt = formattedEntitlementDate(licenseManager.subscriptionEndsAt ?? licenseManager.trialEndsAt) {
                return isChinese ? "已于 \(endsAt) 到期" : "Expired on \(endsAt)"
            }
            return isChinese ? "授权已过期" : "License expired"
        case .deviceLimitReached:
            return isChinese ? "设备数量已满" : "Device limit reached"
        case .inactive:
            return isChinese ? "尚未激活" : "Not activated"
        case .loading:
            return isChinese ? "正在同步授权状态" : "Refreshing license state"
        }
    }

    private var statusDetail: String {
        switch licenseManager.gateState {
        case .trialing:
            if let endsAt = formattedEntitlementDate(licenseManager.trialEndsAt) {
                return isChinese ? "试用至 \(endsAt)" : "Trial until \(endsAt)"
            }
            return isChinese ? "试用已启用，可在授权管理中查看详情。" : "Trial is active. Open License Management for details."
        case .active:
            if let endsAt = formattedEntitlementDate(licenseManager.subscriptionEndsAt) {
                return isChinese ? "\(licenseManager.planSummary) · 有效期至 \(endsAt)" : "\(licenseManager.planSummary) · Valid until \(endsAt)"
            }
            return isChinese ? "\(licenseManager.planSummary) · 已激活" : "\(licenseManager.planSummary) · Active"
        case .expired:
            if let endsAt = formattedEntitlementDate(licenseManager.subscriptionEndsAt ?? licenseManager.trialEndsAt) {
                return isChinese ? "已于 \(endsAt) 到期" : "Expired on \(endsAt)"
            }
            return isChinese ? "可在授权管理中恢复授权或开始试用。" : "Restore your license or start a trial in License Management."
        case .deviceLimitReached:
            return isChinese ? "请在授权管理中移除旧设备后再继续使用。" : "Remove an old device in License Management to continue."
        case .inactive:
            return isChinese ? "可在授权管理中开始试用或输入激活码。" : "Start a trial or enter an activation code in License Management."
        case .loading:
            return isChinese ? "正在同步授权状态。" : "Refreshing license state."
        }
    }

    private var showsTrialStyling: Bool {
        licenseManager.gateState == .trialing
    }

    private func channelLabel(_ channel: AetherUpdateChannel) -> String {
        switch channel {
        case .stable:
            return isChinese ? "稳定版" : "Stable"
        case .beta:
            return isChinese ? "测试版" : "Beta"
        }
    }

    var body: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)

            RadialGradient(
                colors: [
                    Color(red: 0.20, green: 0.45, blue: 0.92).opacity(0.16),
                    Color.clear
                ],
                center: .top,
                startRadius: 40,
                endRadius: 300
            )
            .frame(width: 520, height: 360)
            .offset(y: -140)

            VStack(spacing: 0) {
                Spacer(minLength: 34)

                VStack(spacing: 0) {
                    Image(nsImage: appIcon)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 108, height: 108)
                        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                        .shadow(color: Color(red: 0.22, green: 0.54, blue: 0.98).opacity(0.28), radius: 24, y: 8)

                    VStack(spacing: 6) {
                        Text(appDisplayName)
                            .font(.system(size: 34, weight: .bold))

                        HStack(spacing: 8) {
                            Text(appState.appVersionDisplay)
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)

                            Button {
                                Task { await updaterManager.checkForUpdates() }
                            } label: {
                                Image(systemName: "arrow.clockwise")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(.secondary)
                                    .frame(width: 18, height: 18)
                            }
                            .buttonStyle(.plain)
                            .help(isChinese ? "检查更新" : "Check for updates")
                            .accessibilityLabel(isChinese ? "检查更新" : "Check for updates")
                        }
                    }
                    .padding(.top, 16)
                }

                Spacer(minLength: 70)

                VStack(spacing: 10) {
                    Text(tagline)
                        .font(.system(size: 18, weight: .medium))
                        .tracking(1.5)
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)

                    Text("© 2026 Aether Team")
                        .font(.system(size: 11))
                        .foregroundStyle(Color(nsColor: .tertiaryLabelColor))
                }
                .frame(maxWidth: 520)
                .padding(.horizontal, 40)

                Spacer()

                VStack(spacing: 18) {
                    VStack(spacing: 8) {
                        statusBadge(statusPillTitle, tint: badgeTint)

                        Text(compactStatusDetail)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .lineLimit(1)
                    }

                    Divider()
                        .opacity(0.32)

                    VStack(spacing: 12) {
                        HStack(spacing: 22) {
                            footerLink(title: isChinese ? "访问官网" : "Website", key: "AetherWebsiteURL", fallback: "https://aether.7caifei.com")
                            footerLink(title: isChinese ? "更新日志" : "Changelog", key: "AetherChangelogURL", fallback: "https://aether.7caifei.com/changelog")

                            if let emailURL = URL(string: "mailto:aether@7caifei.com") {
                                Link(destination: emailURL) {
                                    FooterLinkText(text: isChinese ? "邮箱" : "Email")
                                }
                            }

                            if let tgURL = URL(string: "https://t.me/+qmXSaOVwAeE4NDcx") {
                                Link(destination: tgURL) {
                                    FooterLinkText(text: "Telegram")
                                }
                            }
                        }

                        HStack(spacing: 22) {
                            Menu {
                                ForEach(AetherUpdateChannel.allCases) { channel in
                                    Button(channelLabel(channel)) {
                                        updaterManager.setUpdateChannel(channel)
                                    }
                                }
                            } label: {
                                FooterLinkText(text: isChinese ? "更新通道 · \(channelLabel(updaterManager.channel))" : "Channel · \(channelLabel(updaterManager.channel))")
                            }
                            .buttonStyle(.plain)

                            Button {
                                showsLicenseSheet = true
                            } label: {
                                FooterLinkText(text: isChinese ? "管理授权" : "Manage License")
                            }
                            .buttonStyle(.plain)
                            .accessibilityHint(isChinese ? "打开授权管理窗口" : "Opens license management")
                        }
                    }
                    .font(.system(size: 11))
                }
                .frame(maxWidth: 560)
                .padding(.horizontal, 36)
                .padding(.bottom, 22)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .toolbar(removing: .title)
        .sheet(isPresented: $showsLicenseSheet) {
            AboutLicenseSheet(
                emailInput: $emailInput,
                codeInput: $codeInput,
                referralInput: $referralInput
            )
            .environmentObject(appState)
        }
        .onAppear {
            emailInput = licenseManager.email
            codeInput = licenseManager.licenseKey
        }
    }

    private var badgeTint: Color {
        switch licenseManager.gateState {
        case .trialing:
            return Color(red: 0.20, green: 0.41, blue: 0.82)
        case .active:
            return .orange
        case .expired, .deviceLimitReached:
            return .red
        case .inactive, .loading:
            return .secondary
        }
    }

    private func formattedEntitlementDate(_ rawValue: String?) -> String? {
        guard let rawValue, !rawValue.isEmpty else { return nil }
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let fallbackISOFormatter = ISO8601DateFormatter()
        fallbackISOFormatter.formatOptions = [.withInternetDateTime]

        let date = isoFormatter.date(from: rawValue) ?? fallbackISOFormatter.date(from: rawValue)
        guard let date else { return rawValue }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: isChinese ? "zh_Hans_CN" : Locale.current.identifier)
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }

    private func footerLink(title: String, key: String, fallback: String) -> some View {
        let value = Bundle.main.object(forInfoDictionaryKey: key) as? String ?? fallback
        return Group {
            if let url = URL(string: value) {
                Link(destination: url) {
                    FooterLinkText(text: title)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func statusBadge(_ title: String, tint: Color) -> some View {
        Text(title)
            .font(.caption2.weight(.bold))
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .background(tint.opacity(showsTrialStyling ? 0.22 : 0.12))
            .foregroundStyle(showsTrialStyling ? Color.white : tint)
            .clipShape(Capsule())
    }
}

private struct FooterLinkText: View {
    let text: String
    @State private var isHovering: Bool = false

    var body: some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundStyle(isHovering ? Color.accentColor.opacity(0.95) : Color.accentColor)
            .underline(isHovering)
            .onHover { hovering in
                isHovering = hovering
            }
    }
}

private struct AboutLicenseSheet: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var licenseManager = AetherLicenseManager.shared
    @Binding var emailInput: String
    @Binding var codeInput: String
    @Binding var referralInput: String

    private var isChinese: Bool { appState.isChineseUI }
    private var isTrialing: Bool { licenseManager.gateState == .trialing }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                if licenseManager.isActivated {
                    activatedView
                } else {
                    activationFormView
                }
            }
        }
        .padding(20)
        .background(Color(nsColor: .windowBackgroundColor))
        .frame(minWidth: 620, minHeight: 340)
    }

    private var activatedView: some View {
        GlassCard(padding: 22) {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top, spacing: 14) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 28, weight: .semibold))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.green)
                        .frame(width: 36, height: 36)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(isTrialing ? (isChinese ? "Aether 试用中" : "Aether Trial Active") : (isChinese ? "Aether 已激活" : "Aether Activated"))
                            .font(.title3.weight(.semibold))
                        Text(licenseDetailLine)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                HStack(spacing: 12) {
                    licenseStat(
                        title: isChinese ? "方案" : "Plan",
                        value: licenseManager.planSummary,
                        systemImage: "crown"
                    )
                    licenseStat(
                        title: isChinese ? "到期时间" : "Expires",
                        value: expirationDisplay,
                        systemImage: "calendar"
                    )
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text(isChinese ? "设备" : "Devices")
                        .font(.headline)

                    if licenseManager.devices.isEmpty {
                        Text(isChinese ? "当前没有已同步的设备信息。" : "No synced devices yet.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(licenseManager.devices) { device in
                            HStack(alignment: .top, spacing: 12) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(device.name)
                                        .font(.subheadline.weight(.semibold))
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

                HStack(spacing: 10) {
                    Button(isChinese ? "刷新状态" : "Refresh") {
                        Task { await licenseManager.refreshEntitlement() }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Spacer()

                    Button(isChinese ? "完成" : "Done") {
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .keyboardShortcut(.defaultAction)
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
                Text(isChinese ? "输入邮箱和激活码以启用授权；如果还没有激活码，可以先开始试用。" : "Enter your email and activation code to activate your license. If you do not have one yet, you can start a trial first.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

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
                    .controlSize(.small)

                    Spacer(minLength: 0)

                    Button(isChinese ? "取消" : "Cancel") {
                        dismiss()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .keyboardShortcut(.cancelAction)
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

    private func licenseStat(title: String, value: String, systemImage: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.secondary)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.subheadline.weight(.semibold))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.45))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var licenseDetailLine: String {
        if isTrialing {
            return isChinese
                ? "试用已启用，可在这里查看到期时间和设备占用。"
                : "Your trial is active. Review the expiration date and device usage here."
        }
        if let expiresAt = formattedEntitlementDate(licenseManager.subscriptionEndsAt) {
            return isChinese
                ? "当前订阅有效，可使用至 \(expiresAt)。"
                : "Your subscription is active through \(expiresAt)."
        }
        return isChinese
            ? "当前授权可用，可在这里查看设备占用并管理设备。"
            : "Your license is active. You can review device usage and manage devices here."
    }

    private var expirationDisplay: String {
        if isTrialing {
            return formattedEntitlementDate(licenseManager.trialEndsAt) ?? (isChinese ? "试用中" : "Active")
        }
        return formattedEntitlementDate(licenseManager.subscriptionEndsAt) ?? (isChinese ? "未设到期" : "No expiry")
    }

    private func formattedEntitlementDate(_ rawValue: String?) -> String? {
        guard let rawValue, !rawValue.isEmpty else { return nil }
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let fallbackISOFormatter = ISO8601DateFormatter()
        fallbackISOFormatter.formatOptions = [.withInternetDateTime]

        let date = isoFormatter.date(from: rawValue) ?? fallbackISOFormatter.date(from: rawValue)
        guard let date else { return rawValue }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: isChinese ? "zh_Hans_CN" : Locale.current.identifier)
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }
}
