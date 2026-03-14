import SwiftUI
import Combine
import AVFoundation
import Speech
import Carbon
import UniformTypeIdentifiers
import IOKit.hidsystem

enum OnboardingStep: Equatable {
    case accessibility
    case microphone
    case speech
    case done
}

@MainActor
final class MotionService: ObservableObject {
    @Published private(set) var isTracking: Bool = false
    @Published private(set) var attitudeText: String = String(localized: "headset.status.no_data")
    @Published private(set) var calibrationStatus: String = String(localized: "calibration.normal")
    @Published private(set) var lastErrorMessage: String = ""

    private let manager: HeadMotionManager
    private var cancellables = Set<AnyCancellable>()

    init(manager: HeadMotionManager = .shared) {
        self.manager = manager

        manager.$isTracking
            .receive(on: DispatchQueue.main)
            .assign(to: &$isTracking)

        manager.$attitudeText
            .receive(on: DispatchQueue.main)
            .assign(to: &$attitudeText)

        manager.$calibrationStatus
            .receive(on: DispatchQueue.main)
            .assign(to: &$calibrationStatus)
            
        manager.onError = { [weak self] errorMsg in
            DispatchQueue.main.async {
                self?.presentError(errorMsg)
            }
        }
    }
    
    @MainActor
    private func presentError(_ message: String) {
        lastErrorMessage = message
        CurrentAppShortcutPanelManager.shared.hide()
        HUDManager.shared.showTemporary(
            message: message,
            icon: "exclamationmark.triangle.fill",
        )
    }

    func setGlobalHotkeysEnabled(_ enabled: Bool) {
        manager.setGlobalHotkeysEnabled(enabled)
    }

    func recoverFromAccessibilityTrustChange(_ trusted: Bool, source: String = "permissions-refresh") {
        manager.recoverFromAccessibilityTrustChange(trusted: trusted, source: source)
    }

    func startTracking() { manager.startTracking() }
    func stopTracking() { manager.stopTracking() }
    func finishCalibration() { manager.finishCalibration() }
    func recenter() { manager.recenter() }

    func clickLeft() { manager.clickLeft() }
    func clickRight() { manager.clickRight() }
    func doubleClick() { manager.doubleClick() }
    
    func scroll(dx: Int, dy: Int) { manager.scroll(dx: dx, dy: dy) }
    func scrollToTop() { manager.scrollToTop() }
    func scrollToBottom() { manager.scrollToBottom() }
    func dragStart() { manager.dragStart() }
    func dragEnd() { manager.dragEnd() }
}

@MainActor
final class VoiceService: ObservableObject {
    @Published private(set) var status: String = String(localized: "voice.status.idle")
    @Published private(set) var lastTranscript: String = ""
    @Published private(set) var lastError: String = ""
    @Published private(set) var lastWakeTime: Date?
    
    @Published var isAlwaysListeningEnabled: Bool = false
    @Published var isDirectCommandEnabled: Bool = false
    @Published var isPTTEnabled: Bool = true
    @Published var isWakeWordEnabled: Bool = true
    @Published var isGazeWakeEnabled: Bool = true
    @Published var isAutoPunctuationEnabled: Bool = true
    @Published var availableInputDevices: [AudioInputDevice] = []
    @Published var selectedInputDeviceID: AudioDeviceID = 0 {
        didSet {
            manager.selectedInputDeviceID = selectedInputDeviceID
        }
    }

    var onIntent: ((VoiceIntent, String?, String?) -> Void)? {
        get { manager.onIntent }
        set { manager.onIntent = newValue }
    }
    
    var onRecognitionFailure: ((String?, String?, String?, String?) -> Void)? {
        get { manager.onRecognitionFailure }
        set { manager.onRecognitionFailure = newValue }
    }

    var isDictationExecutionEnabled: (() -> Bool)? {
        get { manager.isDictationExecutionEnabled }
        set { manager.isDictationExecutionEnabled = newValue }
    }

    var isCommandExecutionEnabled: (() -> Bool)? {
        get { manager.isCommandExecutionEnabled }
        set { manager.isCommandExecutionEnabled = newValue }
    }
    
    var explicitLocaleIdentifier: String? {
        get { manager.explicitLocaleIdentifier }
        set {
            objectWillChange.send()
            manager.explicitLocaleIdentifier = newValue
        }
    }

    var speechLanguageMode: SpeechLanguageMode {
        get { manager.speechLanguageMode }
        set {
            objectWillChange.send()
            manager.speechLanguageMode = newValue
        }
    }

    var followsSystemLanguage: Bool {
        get { manager.followsSystemLanguage }
        set {
            objectWillChange.send()
            manager.followsSystemLanguage = newValue
        }
    }

    var primaryLocaleIdentifier: String {
        get { manager.primaryLocaleIdentifier }
        set {
            objectWillChange.send()
            manager.primaryLocaleIdentifier = newValue
        }
    }

    var secondaryLocaleIdentifier: String {
        get { manager.secondaryLocaleIdentifier }
        set {
            objectWillChange.send()
            manager.secondaryLocaleIdentifier = newValue
        }
    }

    var effectiveLocaleIdentifier: String {
        manager.effectiveLocaleIdentifier
    }

    var isCurrentInputHeadsetLike: Bool {
        manager.isCurrentInputHeadsetLike()
    }

    private let manager: SpeechManager
    private var cancellables = Set<AnyCancellable>()

    convenience init() {
        self.init(manager: SpeechManager())
    }

    init(manager: SpeechManager) {
        self.manager = manager

        manager.$status
            .receive(on: DispatchQueue.main)
            .assign(to: &$status)

        manager.$lastTranscript
            .receive(on: DispatchQueue.main)
            .assign(to: &$lastTranscript)

        manager.$lastError
            .receive(on: DispatchQueue.main)
            .assign(to: &$lastError)
            
        manager.$lastWakeTime
            .receive(on: DispatchQueue.main)
            .assign(to: &$lastWakeTime)
            
        manager.$isAlwaysListeningEnabled
            .receive(on: DispatchQueue.main)
            .assign(to: &$isAlwaysListeningEnabled)
            
        manager.$isWakeWordEnabled
            .receive(on: DispatchQueue.main)
            .assign(to: &$isWakeWordEnabled)
            
        manager.$isGazeWakeEnabled
            .receive(on: DispatchQueue.main)
            .assign(to: &$isGazeWakeEnabled)
            
        manager.$availableInputDevices
            .receive(on: DispatchQueue.main)
            .assign(to: &$availableInputDevices)
            
        manager.$selectedInputDeviceID
            .receive(on: DispatchQueue.main)
            .assign(to: &$selectedInputDeviceID)
            
        manager.$isDirectCommandEnabled
            .receive(on: DispatchQueue.main)
            .assign(to: &$isDirectCommandEnabled)
            
        manager.$isAutoPunctuationEnabled
            .receive(on: DispatchQueue.main)
            .assign(to: &$isAutoPunctuationEnabled)
            
        manager.$isPTTEnabled
            .receive(on: DispatchQueue.main)
            .assign(to: &$isPTTEnabled)
    }

    func refreshInputDevices() {
        manager.refreshInputDevices()
    }

    func setAlwaysListeningEnabled(_ enabled: Bool) {
        manager.isAlwaysListeningEnabled = enabled
    }
    
    func setDirectCommandEnabled(_ enabled: Bool) {
        manager.isDirectCommandEnabled = enabled
    }
    
    func setPTTEnabled(_ enabled: Bool) {
        manager.isPTTEnabled = enabled
    }

    func setWakeWordEnabled(_ enabled: Bool) {
        manager.isWakeWordEnabled = enabled
    }

    func setGazeWakeEnabled(_ enabled: Bool) {
        manager.isGazeWakeEnabled = enabled
    }

    func setAutoPunctuationEnabled(_ enabled: Bool) {
        manager.isAutoPunctuationEnabled = enabled
    }


    func setLLMEnhancementEnabled(_ enabled: Bool) {
        manager.isLLMEnhancementEnabled = enabled
    }

    func setVoiceCommandOverrides(_ overrides: [VoiceCommandOverrideConfig]) {
        manager.setVoiceCommandOverrides(overrides)
    }

    func setVoiceLanguageTermsOverrides(_ overrides: [VoiceLanguageTermsOverrideConfig]) {
        manager.setVoiceLanguageTermsOverrides(overrides)
    }

    func setCustomAppShortcutRules(_ rules: [CustomAppShortcutRule]) {
        manager.setCustomAppShortcutRules(rules)
    }

    func syncHUDState() {
        manager.syncHUDState()
    }

    func setAccessibilityTrusted(_ trusted: Bool) {
        manager.updateAccessibilityTrusted(trusted)
    }

    func undoLastInjection() {
        manager.undoLastInjection()
    }
}

@MainActor
final class NowPlayingService: ObservableObject {
    static let shared = NowPlayingService()

    @Published private(set) var appName: String = ""
    @Published private(set) var bundleIdentifier: String = ""
    @Published private(set) var title: String = ""
    @Published private(set) var artist: String = ""
    @Published private(set) var album: String = ""
    @Published private(set) var playbackRate: Double = 0
    @Published private(set) var sourcePID: Int32 = 0
    @Published private(set) var lastUpdatedAt: Date?

    private let callbackQueue = DispatchQueue(label: "com.aether.now-playing.callback", qos: .userInitiated)
    private var pollTimer: Timer?

    private typealias GetNowPlayingInfoFn = @convention(c) (DispatchQueue, @escaping @convention(block) (CFDictionary?) -> Void) -> Void
    private typealias GetNowPlayingPIDFn = @convention(c) (DispatchQueue, @escaping @convention(block) (Int32) -> Void) -> Void

    private let getNowPlayingInfoFn: GetNowPlayingInfoFn?
    private let getNowPlayingPIDFn: GetNowPlayingPIDFn?

    private let mediaRemoteTitleKey = "kMRMediaRemoteNowPlayingInfoTitle"
    private let mediaRemoteArtistKey = "kMRMediaRemoteNowPlayingInfoArtist"
    private let mediaRemoteAlbumKey = "kMRMediaRemoteNowPlayingInfoAlbum"
    private let mediaRemotePlaybackRateKey = "kMRMediaRemoteNowPlayingInfoPlaybackRate"

    init() {
        let handle = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_NOW)
        if let infoRaw = dlsym(handle, "MRMediaRemoteGetNowPlayingInfo") {
            self.getNowPlayingInfoFn = unsafeBitCast(infoRaw, to: GetNowPlayingInfoFn.self)
        } else {
            self.getNowPlayingInfoFn = nil
        }

        if let pidRaw = dlsym(handle, "MRMediaRemoteGetNowPlayingApplicationPID") {
            self.getNowPlayingPIDFn = unsafeBitCast(pidRaw, to: GetNowPlayingPIDFn.self)
        } else {
            self.getNowPlayingPIDFn = nil
        }

        refresh()
        startPolling()
    }

    deinit {
        pollTimer?.invalidate()
    }

    var isAvailable: Bool {
        sourcePID != 0 || !title.isEmpty || !appName.isEmpty
    }

    var playbackStatusText: String {
        guard isAvailable else { return "Idle" }
        return playbackRate > 0.01 ? "Playing" : "Paused"
    }

    func refresh() {
        guard let getNowPlayingInfoFn, let getNowPlayingPIDFn else {
            applySnapshot(pid: 0, info: nil)
            return
        }

        let group = DispatchGroup()
        var fetchedPID: Int32 = 0
        var fetchedInfo: NSDictionary?

        group.enter()
        getNowPlayingPIDFn(callbackQueue) { pid in
            fetchedPID = pid
            group.leave()
        }

        group.enter()
        getNowPlayingInfoFn(callbackQueue) { info in
            if let info {
                fetchedInfo = info as NSDictionary
            } else {
                fetchedInfo = nil
            }
            group.leave()
        }

        group.notify(queue: .main) { [weak self] in
            self?.applySnapshot(pid: fetchedPID, info: fetchedInfo)
        }
    }

    func togglePlayPause() {
        sendMediaKey(NX_KEYTYPE_PLAY)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            self?.refresh()
        }
    }

    func nextTrack() {
        sendMediaKey(NX_KEYTYPE_NEXT)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            self?.refresh()
        }
    }

    func previousTrack() {
        sendMediaKey(NX_KEYTYPE_PREVIOUS)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            self?.refresh()
        }
    }

    private func startPolling() {
        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            self?.refresh()
        }
    }

    private func applySnapshot(pid: Int32, info: NSDictionary?) {
        sourcePID = pid
        if let app = NSRunningApplication(processIdentifier: pid_t(pid)) {
            appName = app.localizedName ?? ""
            bundleIdentifier = app.bundleIdentifier ?? ""
        } else {
            appName = ""
            bundleIdentifier = ""
        }

        title = info?[mediaRemoteTitleKey] as? String ?? ""
        artist = info?[mediaRemoteArtistKey] as? String ?? ""
        album = info?[mediaRemoteAlbumKey] as? String ?? ""
        playbackRate = (info?[mediaRemotePlaybackRateKey] as? NSNumber)?.doubleValue ?? 0
        lastUpdatedAt = Date()
    }

    private func sendMediaKey(_ keyCode: Int32) {
        postMediaKey(keyCode, state: true)
        postMediaKey(keyCode, state: false)
    }

    private func postMediaKey(_ keyCode: Int32, state: Bool) {
        let keyState = state ? 0xA : 0xB
        let data1 = Int((keyCode << 16) | (Int32(keyState) << 8))

        guard let event = NSEvent.otherEvent(
            with: .systemDefined,
            location: .zero,
            modifierFlags: NSEvent.ModifierFlags(rawValue: 0xA00),
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: 0,
            context: nil,
            subtype: 8,
            data1: data1,
            data2: -1
        ) else {
            return
        }

        event.cgEvent?.post(tap: .cghidEventTap)
    }
}

@MainActor
final class PermissionsService: ObservableObject {
    @Published private(set) var accessibilityTrusted: Bool = false
    @Published private(set) var microphoneAuthorized: Bool = false
    @Published private(set) var speechAuthorized: Bool = false

    private let manager: PermissionsManager
    private var cancellables = Set<AnyCancellable>()

    convenience init() {
        self.init(manager: PermissionsManager())
    }

    init(manager: PermissionsManager) {
        self.manager = manager

        manager.$accessibilityTrusted
            .receive(on: DispatchQueue.main)
            .assign(to: &$accessibilityTrusted)

        manager.$microphoneAuthorized
            .receive(on: DispatchQueue.main)
            .assign(to: &$microphoneAuthorized)

        manager.$speechAuthorized
            .receive(on: DispatchQueue.main)
            .assign(to: &$speechAuthorized)
    }

    func refresh() { manager.refresh() }
    @discardableResult
    func requestAccessibility() -> Bool { manager.requestAccessibility() }
    func requestMicrophone() { manager.requestMicrophone() }
    func requestSpeech() { manager.requestSpeech() }
    func openAccessibilityPrivacyPane() { manager.openAccessibilityPrivacyPane() }
    func openMicrophonePrivacyPane() { manager.openMicrophonePrivacyPane() }
    func openSpeechPrivacyPane() { manager.openSpeechPrivacyPane() }
}

@MainActor
class AppState: ObservableObject {
    struct SpeechTermGroupConfig: Codable, Identifiable, Equatable {
        var id: String
        var name: String
        var isEnabled: Bool
        var applyToAllApps: Bool
        var appList: String
        var rulesText: String

        init(
            id: String = UUID().uuidString,
            name: String,
            isEnabled: Bool = true,
            applyToAllApps: Bool = false,
            appList: String = "",
            rulesText: String = ""
        ) {
            self.id = id
            self.name = name
            self.isEnabled = isEnabled
            self.applyToAllApps = applyToAllApps
            self.appList = appList
            self.rulesText = rulesText
        }
    }

    enum VoiceUsageEventKind: String, Codable {
        case dictation
        case control
    }

    struct VoiceUsageEvent: Codable, Identifiable, Equatable {
        var id: String
        var timestamp: Date
        var appName: String
        var bundleIdentifier: String
        var kind: VoiceUsageEventKind
        var action: String
        var content: String?

        init(
            id: String = UUID().uuidString,
            timestamp: Date = Date(),
            appName: String,
            bundleIdentifier: String,
            kind: VoiceUsageEventKind,
            action: String,
            content: String? = nil
        ) {
            self.id = id
            self.timestamp = timestamp
            self.appName = appName
            self.bundleIdentifier = bundleIdentifier
            self.kind = kind
            self.action = action
            self.content = content
        }
    }

    struct VoiceUsageSummary {
        let total: Int
        let dictationCount: Int
        let failureCount: Int
        let unrecognizedCount: Int
        let mismatchCount: Int
        let controlCount: Int
    }

    struct VoiceUsageAppSummary: Identifiable {
        var id: String { bundleIdentifier }
        let appName: String
        let bundleIdentifier: String
        let total: Int
        let dictationCount: Int
        let failureCount: Int
        let unrecognizedCount: Int
        let mismatchCount: Int
        let controlCount: Int
    }

    struct CustomAppShortcutRulesBackup: Codable {
        var version: Int = 1
        var exportedAt: Date = Date()
        var rules: [CustomAppShortcutRule]
    }

    private static let speechTermGroupsStorageKey = "speechTermGroupsV2"
    private static let voiceCommandOverridesStorageKey = "voiceCommandOverridesV1"
    private static let voiceLanguageTermsOverridesStorageKey = "voiceLanguageTermsOverridesV1"
    private static let voiceUsageHistoryEnabledStorageKey = "voiceUsageHistoryEnabledV1"
    private static let voiceUsageHistoryStorageKey = "voiceUsageHistoryV1"
    private static let voiceUsageHistoryLimitStorageKey = "voiceUsageHistoryLimitV1"
    private static let customAppShortcutRulesStorageKey = "customAppShortcutRulesV1"
    private static let defaultVoiceUsageHistoryLimit = 1000
    private static let minVoiceUsageHistoryLimit = 100
    private static let maxVoiceUsageHistoryLimit = 5000

    @Published var appLanguageMode: AppLanguageMode = AppLocalization.storedAppLanguage() {
        didSet {
            guard oldValue != appLanguageMode else { return }
            AppLocalization.setPreferredLanguage(appLanguageMode)
            HUDManager.shared.showTemporary(
                message: AppLocalization.localizedString("settings.app_language.restart_hint"),
                icon: "arrow.clockwise"
            )
        }
    }

    var isChineseUI: Bool {
        AppLocalization.isChinese
    }

    var appLocale: Locale {
        Locale(identifier: AppLocalization.resolvedLocaleIdentifier)
    }

    var appShortVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    var appBuildVersion: String {
        Bundle.main.object(forInfoDictionaryKey: kCFBundleVersionKey as String) as? String ?? "0"
    }

    var appVersionDisplay: String {
        String(format: String(localized: "app.version_fmt"), appShortVersion, appBuildVersion)
    }

    private static func defaultSpeechTermGroups() -> [SpeechTermGroupConfig] {
        [
            SpeechTermGroupConfig(
                name: "通用组",
                isEnabled: true,
                applyToAllApps: true,
                appList: "",
                rulesText: "git hub=>GitHub"
            ),
            SpeechTermGroupConfig(
                name: "开发类",
                isEnabled: true,
                applyToAllApps: false,
                appList: "com.apple.Terminal,\ncom.apple.dt.Xcode,\ncom.microsoft.VSCode,\ncom.openai.codex,\ncom.openai.chatgpt",
                rulesText: "后果=>GitHub=>cmd"
            ),
            SpeechTermGroupConfig(
                name: "办公类",
                isEnabled: true,
                applyToAllApps: false,
                appList: "com.microsoft.Word,\ncom.microsoft.Excel,\ncom.microsoft.Powerpoint,\ncom.tencent.wework,\ncom.apple.mail",
                rulesText: "飞鼠=>飞书\n叮叮=>钉钉\n定定=>钉钉\n未信=>微信"
            ),
            SpeechTermGroupConfig(
                name: "写作类",
                isEnabled: true,
                applyToAllApps: false,
                appList: "com.apple.TextEdit,\ncom.apple.Notes,\ncom.coteditor.CotEditor,\ncom.sublimetext.4,\ncom.zed.Zed",
                rulesText: "逗好=>逗号\n句好=>句号"
            )
        ]
    }

    private static func loadSpeechTermGroups() -> [SpeechTermGroupConfig] {
        if let data = UserDefaults.standard.data(forKey: speechTermGroupsStorageKey),
           let groups = try? JSONDecoder().decode([SpeechTermGroupConfig].self, from: data),
           !groups.isEmpty {
            return groups
        }
        return defaultSpeechTermGroups()
    }

    private static func saveSpeechTermGroups(_ groups: [SpeechTermGroupConfig]) {
        if let data = try? JSONEncoder().encode(groups) {
            UserDefaults.standard.set(data, forKey: speechTermGroupsStorageKey)
        }
    }

    private static func loadVoiceCommandOverrides() -> [VoiceCommandOverrideConfig] {
        guard let data = UserDefaults.standard.data(forKey: voiceCommandOverridesStorageKey),
              let overrides = try? JSONDecoder().decode([VoiceCommandOverrideConfig].self, from: data),
              !overrides.isEmpty,
              !containsMojibake(overrides) else {
            return sanitizeVoiceCommandOverrides(VoiceLexiconDefaults.load()?.commandOverrides ?? [])
        }
        return sanitizeVoiceCommandOverrides(overrides)
    }

    private static func saveVoiceCommandOverrides(_ overrides: [VoiceCommandOverrideConfig]) {
        let sanitized = sanitizeVoiceCommandOverrides(overrides)
        if let data = try? JSONEncoder().encode(sanitized) {
            UserDefaults.standard.set(data, forKey: voiceCommandOverridesStorageKey)
        }
    }

    private static func sanitizeVoiceCommandOverrides(_ overrides: [VoiceCommandOverrideConfig]) -> [VoiceCommandOverrideConfig] {
        let retiredBuiltInCommands: Set<String> = ["undo", "paste"]
        return overrides.filter { !retiredBuiltInCommands.contains($0.commandID) }
    }

    private static func loadVoiceLanguageTermsOverrides() -> [VoiceLanguageTermsOverrideConfig] {
        guard let data = UserDefaults.standard.data(forKey: voiceLanguageTermsOverridesStorageKey),
              let overrides = try? JSONDecoder().decode([VoiceLanguageTermsOverrideConfig].self, from: data),
              !overrides.isEmpty,
              !containsMojibake(overrides) else {
            return VoiceLexiconDefaults.load()?.languageTermsOverrides ?? []
        }
        return overrides
    }

    private static func containsMojibake(_ overrides: [VoiceCommandOverrideConfig]) -> Bool {
        overrides.contains { override in
            override.aliases.contains(where: containsMojibake)
        }
    }

    private static func containsMojibake(_ overrides: [VoiceLanguageTermsOverrideConfig]) -> Bool {
        overrides.contains { override in
            override.wakeWords.contains(where: containsMojibake) ||
                override.commandPrefixes.contains(where: containsMojibake) ||
                override.dictationPrefixes.contains(where: containsMojibake)
        }
    }

    private static func containsMojibake(_ value: String) -> Bool {
        value.contains("Ã") || value.contains("Â")
    }

    private static func saveVoiceLanguageTermsOverrides(_ overrides: [VoiceLanguageTermsOverrideConfig]) {
        if let data = try? JSONEncoder().encode(overrides) {
            UserDefaults.standard.set(data, forKey: voiceLanguageTermsOverridesStorageKey)
        }
    }

    private static func loadVoiceUsageHistoryLimit() -> Int {
        let stored = UserDefaults.standard.object(forKey: voiceUsageHistoryLimitStorageKey) as? Int
            ?? defaultVoiceUsageHistoryLimit
        return clampVoiceUsageHistoryLimit(stored)
    }

    private static func loadCustomAppShortcutRules() -> [CustomAppShortcutRule] {
        guard let data = UserDefaults.standard.data(forKey: customAppShortcutRulesStorageKey),
              let rules = try? JSONDecoder().decode([CustomAppShortcutRule].self, from: data) else {
            return []
        }
        return rules
    }

    private static func saveCustomAppShortcutRules(_ rules: [CustomAppShortcutRule]) {
        if let data = try? JSONEncoder().encode(rules) {
            UserDefaults.standard.set(data, forKey: customAppShortcutRulesStorageKey)
        }
    }

    private static func loadVoiceUsageHistory(limit: Int) -> [VoiceUsageEvent] {
        guard let data = UserDefaults.standard.data(forKey: voiceUsageHistoryStorageKey),
              let events = try? JSONDecoder().decode([VoiceUsageEvent].self, from: data) else {
            return []
        }
        let sorted = events.sorted { $0.timestamp > $1.timestamp }
        return trimVoiceUsageHistory(sorted, limit: limit)
    }

    private static func saveVoiceUsageHistory(_ events: [VoiceUsageEvent]) {
        if let data = try? JSONEncoder().encode(events) {
            UserDefaults.standard.set(data, forKey: voiceUsageHistoryStorageKey)
        }
    }

    private static func trimVoiceUsageHistory(_ events: [VoiceUsageEvent], limit: Int) -> [VoiceUsageEvent] {
        let resolvedLimit = clampVoiceUsageHistoryLimit(limit)
        guard events.count > resolvedLimit else { return events }
        return Array(events.prefix(resolvedLimit))
    }

    private static func clampVoiceUsageHistoryLimit(_ value: Int) -> Int {
        min(max(value, minVoiceUsageHistoryLimit), maxVoiceUsageHistoryLimit)
    }

    private static let aiPromptMaxEventsDefault = 180

    func buildAetherAIConfigPrompt(maxEvents: Int? = nil) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        let currentLexicon = VoiceLexiconBackup(
            commandOverrides: voiceCommandOverrides,
            languageTermsOverrides: voiceLanguageTermsOverrides
        )
        let lexiconJSON = (try? String(data: encoder.encode(currentLexicon), encoding: .utf8)) ?? "{}"
        let customRulesJSON = (try? String(
            data: encoder.encode(CustomAppShortcutRulesBackup(rules: customAppShortcutRules)),
            encoding: .utf8
        )) ?? "{}"

        let resolvedMaxEvents = maxEvents ?? Self.aiPromptMaxEventsDefault
        let recentEvents = Array(voiceUsageHistory.prefix(resolvedMaxEvents))
        let usageJSON = (try? String(data: encoder.encode(recentEvents), encoding: .utf8)) ?? "[]"

        let commandIDs = VoiceCommandPreset.allCases.map { $0.rawValue }.joined(separator: ", ")
        let summary = voiceUsageSummary
        let localeID = voiceService.effectiveLocaleIdentifier
        let exportedAt = ISO8601DateFormatter().string(from: Date())

        let template = AppLocalization.localizedString("ai.prompt.template")
        return template
            .replacingOccurrences(of: "{{COMMAND_IDS}}", with: commandIDs)
            .replacingOccurrences(of: "{{CURRENT_LEXICON_JSON}}", with: lexiconJSON)
            .replacingOccurrences(of: "{{CUSTOM_APP_RULES_JSON}}", with: customRulesJSON)
            .replacingOccurrences(of: "{{USAGE_JSON}}", with: usageJSON)
            .replacingOccurrences(of: "{{SUMMARY_TOTAL}}", with: String(summary.total))
            .replacingOccurrences(of: "{{SUMMARY_DICTATION}}", with: String(summary.dictationCount))
            .replacingOccurrences(of: "{{SUMMARY_CONTROL}}", with: String(summary.controlCount))
            .replacingOccurrences(of: "{{LOCALE}}", with: localeID)
            .replacingOccurrences(of: "{{EXPORTED_AT}}", with: exportedAt)
    }

    enum VoiceActivationMode: String, CaseIterable, Identifiable {
        case pushToTalk
        case wakeWord
        case handsFree
        
        var id: String { rawValue }
    }
    
    private static func loadActivationMode() -> VoiceActivationMode {
        if let raw = UserDefaults.standard.string(forKey: "voiceActivationMode"),
           let mode = VoiceActivationMode(rawValue: raw) {
            return mode
        }
        
        let always = UserDefaults.standard.bool(forKey: "isAlwaysListeningEnabled")
        let wake = UserDefaults.standard.object(forKey: "isWakeWordEnabled") as? Bool ?? true
        if always { return .handsFree }
        if wake { return .wakeWord }
        return .pushToTalk
    }

    private static func loadVoiceFeatureEnabled(_ storageKey: String) -> Bool {
        let defaults = UserDefaults.standard
        if let stored = defaults.object(forKey: storageKey) as? Bool {
            return stored
        }
        if let legacy = defaults.object(forKey: "isVoiceEnabled") as? Bool {
            return legacy
        }
        return true
    }

    private static func loadAutoEnableVoiceFeature(_ storageKey: String) -> Bool {
        let defaults = UserDefaults.standard
        if let stored = defaults.object(forKey: storageKey) as? Bool {
            return stored
        }
        if let legacy = defaults.object(forKey: "autoEnableVoiceOnHeadset") as? Bool {
            return legacy
        }
        return false
    }

    private static let hotkeyModifierMask: UInt64 =
        CGEventFlags.maskControl.rawValue |
        CGEventFlags.maskAlternate.rawValue |
        CGEventFlags.maskShift.rawValue |
        CGEventFlags.maskCommand.rawValue |
        CGEventFlags.maskAlphaShift.rawValue

    private static let defaultPTTModifiers: UInt64 = CGEventFlags.maskAlternate.rawValue

    private static func sanitizeHotkeyModifiers(_ raw: UInt64) -> UInt64 {
        raw & hotkeyModifierMask
    }

    private static func loadPTTBinding() -> HotkeyBinding {
        let defaults = UserDefaults.standard
        let keyCode = (defaults.object(forKey: "voicePTTKeyCode") as? NSNumber)?.intValue ?? Int(kVK_Space)
        let rawModifiers = (defaults.object(forKey: "voicePTTModifiers") as? NSNumber)?.uint64Value ?? defaultPTTModifiers
        let modifiers = sanitizeHotkeyModifiers(rawModifiers)
        return HotkeyBinding(keyCode: keyCode, modifiers: modifiers)
    }
    
    @Published var isMotionTracking: Bool = false
    @Published var attitudeData: String = "No Data"
    
    @Published var calibrationStatus: String = "Normal"

    @Published var voiceStatus: String = "Idle"
    @Published var lastVoiceTranscript: String = ""
    @Published var lastVoiceError: String = ""
    @Published var lastVoiceWakeTime: Date?
    @Published var nowPlayingAppName: String = ""
    @Published var nowPlayingBundleIdentifier: String = ""
    @Published var nowPlayingTitle: String = ""
    @Published var nowPlayingArtist: String = ""
    @Published var nowPlayingAlbum: String = ""
    @Published var nowPlayingStatus: String = "Idle"
    @Published var voiceActivationMode: VoiceActivationMode = AppState.loadActivationMode() {
        didSet {
            guard oldValue != voiceActivationMode else { return }
            UserDefaults.standard.set(voiceActivationMode.rawValue, forKey: "voiceActivationMode")
            HeadMotionManager.shared.setVoiceActivationMode(voiceActivationMode)
            applyVoiceActivationMode()
        }
    }

    @Published var isVoiceInputEnabled: Bool = AppState.loadVoiceFeatureEnabled("isVoiceInputEnabled") {
        didSet {
            UserDefaults.standard.set(isVoiceInputEnabled, forKey: "isVoiceInputEnabled")
            syncVoiceMasterStateFromFeatureToggles()
            voiceService.syncHUDState()
        }
    }

    @Published var isVoiceControlEnabled: Bool = AppState.loadVoiceFeatureEnabled("isVoiceControlEnabled") {
        didSet {
            UserDefaults.standard.set(isVoiceControlEnabled, forKey: "isVoiceControlEnabled")
            syncVoiceMasterStateFromFeatureToggles()
            voiceService.syncHUDState()
        }
    }

    @Published var isVoiceEnabled: Bool = UserDefaults.standard.object(forKey: "isVoiceEnabled") as? Bool ?? true {
        didSet {
            UserDefaults.standard.set(isVoiceEnabled, forKey: "isVoiceEnabled")
            if !isMutatingVoiceFeatureState {
                isMutatingVoiceFeatureState = true
                if isVoiceEnabled {
                    if !isVoiceInputEnabled && !isVoiceControlEnabled {
                        isVoiceInputEnabled = true
                        isVoiceControlEnabled = true
                    }
                } else {
                    if isVoiceInputEnabled {
                        isVoiceInputEnabled = false
                    }
                    if isVoiceControlEnabled {
                        isVoiceControlEnabled = false
                    }
                }
                isMutatingVoiceFeatureState = false
            }
            applyVoiceEnabledState()
        }
    }

    @Published var autoEnableVoiceInputOnHeadset: Bool = AppState.loadAutoEnableVoiceFeature("autoEnableVoiceInputOnHeadset") {
        didSet {
            UserDefaults.standard.set(autoEnableVoiceInputOnHeadset, forKey: "autoEnableVoiceInputOnHeadset")
            if autoEnableVoiceInputOnHeadset,
               voiceService.isCurrentInputHeadsetLike,
               !isVoiceInputEnabled {
                isVoiceInputEnabled = true
            }
        }
    }

    @Published var autoEnableVoiceControlOnHeadset: Bool = AppState.loadAutoEnableVoiceFeature("autoEnableVoiceControlOnHeadset") {
        didSet {
            UserDefaults.standard.set(autoEnableVoiceControlOnHeadset, forKey: "autoEnableVoiceControlOnHeadset")
            if autoEnableVoiceControlOnHeadset,
               voiceService.isCurrentInputHeadsetLike,
               !isVoiceControlEnabled {
                isVoiceControlEnabled = true
            }
        }
    }

    @Published var autoEnableVoiceOnHeadset: Bool = UserDefaults.standard.object(forKey: "autoEnableVoiceOnHeadset") as? Bool ?? false {
        didSet {
            UserDefaults.standard.set(autoEnableVoiceOnHeadset, forKey: "autoEnableVoiceOnHeadset")
            if autoEnableVoiceOnHeadset,
               voiceService.isCurrentInputHeadsetLike,
               !isVoiceEnabled {
                isVoiceEnabled = true
            }
        }
    }
    private var lastHeadsetLikeInput: Bool = false
    private var isMutatingVoiceFeatureState: Bool = false
    
    // Voice Triggers
    @Published var isPTTEnabled: Bool = UserDefaults.standard.object(forKey: "isPTTEnabled") as? Bool ?? true {
        didSet { 
            UserDefaults.standard.set(isPTTEnabled, forKey: "isPTTEnabled")
            guard !isApplyingActivationMode else { return }
            voiceService.setPTTEnabled(isPTTEnabled)
            HeadMotionManager.shared.isPTTEnabled = isPTTEnabled
            
            // [Fix] Dynamically Register/Unregister Hotkey
            // If disabled, remove the binding so others can use it.
            if isPTTEnabled {
                HotkeyManager.shared.registerPTT(voicePTTBinding)
            } else {
                HotkeyManager.shared.unregisterPTT()
            }
        }
    }
    @Published var voicePTTBinding: HotkeyBinding = AppState.loadPTTBinding()
    
    @Published var isWakeWordEnabled: Bool = UserDefaults.standard.object(forKey: "isWakeWordEnabled") as? Bool ?? true {
        didSet { 
            UserDefaults.standard.set(isWakeWordEnabled, forKey: "isWakeWordEnabled")
            guard !isApplyingActivationMode else { return }
            updateContinuousListeningState()
        }
    }

    // Microphone State (Proxied from VoiceService)
    @Published var availableInputDevices: [AudioInputDevice] = []
    @Published var selectedInputDeviceID: AudioDeviceID = 0 {
        didSet {
            // Push to service
            if voiceService.selectedInputDeviceID != selectedInputDeviceID {
                voiceService.selectedInputDeviceID = selectedInputDeviceID
            }
        }
    }
    
    @Published var isAlwaysListeningEnabled: Bool = UserDefaults.standard.bool(forKey: "isAlwaysListeningEnabled") {
        didSet {
            UserDefaults.standard.set(isAlwaysListeningEnabled, forKey: "isAlwaysListeningEnabled")
            guard oldValue != isAlwaysListeningEnabled else { return }
            guard !isApplyingActivationMode else { return }

            if !isMutatingAlwaysListening, isAlwaysListeningEnabled {
                if !microphoneAuthorized {
                    setAlwaysListeningEnabledInternal(false)
                    permissions.requestMicrophone()
                    refreshPermissions()
                    return
                }
                if !speechAuthorized {
                    setAlwaysListeningEnabledInternal(false)
                    permissions.requestSpeech()
                    refreshPermissions()
                    return
                }
            }
            
            updateContinuousListeningState()
        }
    }
    private var isMutatingAlwaysListening = false
    private var isApplyingActivationMode = false
    private var lastVoiceReady: Bool = {
        let mic = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        let speech = SFSpeechRecognizer.authorizationStatus() == .authorized
        return mic && speech
    }()
    
    private func updateContinuousListeningState() {
        guard isVoiceEnabled else {
            voiceService.setAlwaysListeningEnabled(false)
            voiceService.isDirectCommandEnabled = false
            voiceService.isWakeWordEnabled = false
            return
        }
        // 1. Microphone State: Should be ON if EITHER "Wake Word" OR "Always Listening" is enabled.
        let shouldListen = isAlwaysListeningEnabled || isWakeWordEnabled
        voiceService.setAlwaysListeningEnabled(shouldListen)
        
        // 2. Logic State: Direct Command Mode is ON only if "Always Listening" is ON.
        voiceService.isDirectCommandEnabled = isAlwaysListeningEnabled
        
        // 3. Logic State: Wake Word Mode is ON if "Wake Word" is ON.
        voiceService.isWakeWordEnabled = isWakeWordEnabled
    }
    
    private func applyVoiceActivationMode() {
        guard isVoiceEnabled else {
            disableVoiceFeatures()
            return
        }
        isApplyingActivationMode = true
        defer { isApplyingActivationMode = false }
        HeadMotionManager.shared.setVoiceActivationMode(voiceActivationMode)
        
        let requiresContinuousSession = voiceActivationMode != .pushToTalk
        let micAuthorizedNow = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        let speechAuthorizedNow = SFSpeechRecognizer.authorizationStatus() == .authorized
        if requiresContinuousSession {
            if !micAuthorizedNow {
                HUDManager.shared.showTemporary(
                    message: NSLocalizedString("speech.need_mic_permission", comment: ""),
                    icon: "mic.slash.fill"
                )
                permissions.requestMicrophone()
                refreshPermissions()
                // Keep user's selected mode visible in UI.
                // Runtime engine state is gated by SpeechManager permission checks.
                isPTTEnabled = true
                isWakeWordEnabled = (voiceActivationMode == .wakeWord)
                setAlwaysListeningEnabledInternal(requiresContinuousSession)
                HeadMotionManager.shared.isPTTEnabled = true
                HotkeyManager.shared.registerPTT(voicePTTBinding)
                voiceService.setPTTEnabled(true)
                voiceService.setAlwaysListeningEnabled(requiresContinuousSession)
                voiceService.setDirectCommandEnabled(voiceActivationMode == .handsFree)
                voiceService.setWakeWordEnabled(voiceActivationMode == .wakeWord)
                voiceService.syncHUDState()
                return
            }
            if !speechAuthorizedNow {
                HUDManager.shared.showTemporary(
                    message: NSLocalizedString("speech.need_recognition_permission", comment: ""),
                    icon: "waveform.badge.exclamationmark"
                )
                permissions.requestSpeech()
                refreshPermissions()
                // Keep user's selected mode visible in UI.
                // Runtime engine state is gated by SpeechManager permission checks.
                isPTTEnabled = true
                isWakeWordEnabled = (voiceActivationMode == .wakeWord)
                setAlwaysListeningEnabledInternal(requiresContinuousSession)
                HeadMotionManager.shared.isPTTEnabled = true
                HotkeyManager.shared.registerPTT(voicePTTBinding)
                voiceService.setPTTEnabled(true)
                voiceService.setAlwaysListeningEnabled(requiresContinuousSession)
                voiceService.setDirectCommandEnabled(voiceActivationMode == .handsFree)
                voiceService.setWakeWordEnabled(voiceActivationMode == .wakeWord)
                voiceService.syncHUDState()
                return
            }
        }
        
        isPTTEnabled = true
        isWakeWordEnabled = (voiceActivationMode == .wakeWord)
        isAlwaysListeningEnabled = requiresContinuousSession
        
        HeadMotionManager.shared.isPTTEnabled = true
        HotkeyManager.shared.registerPTT(voicePTTBinding)
        
        voiceService.setPTTEnabled(true)
        voiceService.setAlwaysListeningEnabled(requiresContinuousSession)
        voiceService.setDirectCommandEnabled(voiceActivationMode == .handsFree)
        voiceService.setWakeWordEnabled(voiceActivationMode == .wakeWord)
        voiceService.syncHUDState()
    }

    private func applyVoiceEnabledState() {
        if isVoiceEnabled {
            applyVoiceActivationMode()
        } else {
            disableVoiceFeatures()
        }
    }

    private func disableVoiceFeatures() {
        if isPTTEnabled {
            isPTTEnabled = false
        }
        if isWakeWordEnabled {
            isWakeWordEnabled = false
        }
        if isAlwaysListeningEnabled {
            isAlwaysListeningEnabled = false
        }

        voiceService.setPTTEnabled(false)
        voiceService.setAlwaysListeningEnabled(false)
        voiceService.setDirectCommandEnabled(false)
        voiceService.setWakeWordEnabled(false)
        voiceService.syncHUDState()

        HeadMotionManager.shared.isPTTEnabled = false
        HotkeyManager.shared.unregisterPTT()
    }

    private func syncVoiceMasterStateFromFeatureToggles() {
        guard !isMutatingVoiceFeatureState else { return }
        let shouldEnableVoice = isVoiceInputEnabled || isVoiceControlEnabled
        guard shouldEnableVoice != isVoiceEnabled else { return }
        isMutatingVoiceFeatureState = true
        isVoiceEnabled = shouldEnableVoice
        isMutatingVoiceFeatureState = false
    }

    private func handleHeadsetAutoEnable(source: String) {
        let isHeadsetLike = voiceService.isCurrentInputHeadsetLike
        if !lastHeadsetLikeInput, isHeadsetLike {
            if autoEnableVoiceInputOnHeadset && !isVoiceInputEnabled {
                isVoiceInputEnabled = true
            }
            if autoEnableVoiceControlOnHeadset && !isVoiceControlEnabled {
                isVoiceControlEnabled = true
            }
        }
        lastHeadsetLikeInput = isHeadsetLike
    }
    

    
    @Published var isGazeWakeEnabled: Bool = UserDefaults.standard.object(forKey: "isGazeWakeEnabled") as? Bool ?? true {
        didSet {
            UserDefaults.standard.set(isGazeWakeEnabled, forKey: "isGazeWakeEnabled")
            voiceService.setGazeWakeEnabled(isGazeWakeEnabled)
        }
    }
    
    @Published var isAutoPunctuationEnabled: Bool = {
        UserDefaults.standard.set(true, forKey: "isAutoPunctuationEnabled")
        return true
    }() {
        didSet {
            guard isAutoPunctuationEnabled else {
                if oldValue != true {
                    isAutoPunctuationEnabled = true
                }
                return
            }
            UserDefaults.standard.set(true, forKey: "isAutoPunctuationEnabled")
            voiceService.setAutoPunctuationEnabled(true)
        }
    }

    @Published var speechTermCorrectionEnabled: Bool = {
        UserDefaults.standard.set(false, forKey: "speechTermCorrectionEnabled")
        return false
    }() {
        didSet {
            guard !speechTermCorrectionEnabled else {
                if oldValue != false {
                    speechTermCorrectionEnabled = false
                }
                return
            }
            UserDefaults.standard.set(false, forKey: "speechTermCorrectionEnabled")
        }
    }
    @Published var speechTermGroups: [SpeechTermGroupConfig] = AppState.loadSpeechTermGroups() {
        didSet {
            AppState.saveSpeechTermGroups(speechTermGroups)
        }
    }
    @Published var isVoiceUsageHistoryEnabled: Bool = UserDefaults.standard.object(forKey: voiceUsageHistoryEnabledStorageKey) as? Bool ?? false {
        didSet {
            UserDefaults.standard.set(isVoiceUsageHistoryEnabled, forKey: Self.voiceUsageHistoryEnabledStorageKey)
        }
    }
    @Published var voiceUsageHistoryLimit: Int = AppState.loadVoiceUsageHistoryLimit() {
        didSet {
            let clamped = Self.clampVoiceUsageHistoryLimit(voiceUsageHistoryLimit)
            if clamped != voiceUsageHistoryLimit {
                voiceUsageHistoryLimit = clamped
                return
            }
            UserDefaults.standard.set(clamped, forKey: Self.voiceUsageHistoryLimitStorageKey)
            let trimmed = Self.trimVoiceUsageHistory(voiceUsageHistory, limit: clamped)
            if trimmed.count != voiceUsageHistory.count {
                voiceUsageHistory = trimmed
                return
            }
            Self.saveVoiceUsageHistory(trimmed)
        }
    }
    @Published var voiceUsageHistory: [VoiceUsageEvent] = AppState.loadVoiceUsageHistory(limit: AppState.loadVoiceUsageHistoryLimit()) {
        didSet {
            let trimmed = Self.trimVoiceUsageHistory(voiceUsageHistory, limit: voiceUsageHistoryLimit)
            if trimmed.count != voiceUsageHistory.count {
                voiceUsageHistory = trimmed
                return
            }
            Self.saveVoiceUsageHistory(trimmed)
        }
    }
    @Published var voiceCommandOverrides: [VoiceCommandOverrideConfig] = AppState.loadVoiceCommandOverrides() {
        didSet {
            AppState.saveVoiceCommandOverrides(voiceCommandOverrides)
            voiceService.setVoiceCommandOverrides(voiceCommandOverrides)
        }
    }
    @Published var voiceLanguageTermsOverrides: [VoiceLanguageTermsOverrideConfig] = AppState.loadVoiceLanguageTermsOverrides() {
        didSet {
            AppState.saveVoiceLanguageTermsOverrides(voiceLanguageTermsOverrides)
            voiceService.setVoiceLanguageTermsOverrides(voiceLanguageTermsOverrides)
        }
    }
    @Published var customAppShortcutRules: [CustomAppShortcutRule] = AppState.loadCustomAppShortcutRules() {
        didSet {
            AppState.saveCustomAppShortcutRules(customAppShortcutRules)
            voiceService.setCustomAppShortcutRules(customAppShortcutRules)
            CurrentAppShortcutPanelManager.shared.refreshIfVisible()
        }
    }

    var voiceUsageSummary: VoiceUsageSummary {
        var dictation = 0
        var failure = 0
        var unrecognized = 0
        var mismatch = 0
        var control = 0
        for entry in voiceUsageHistory {
            if isVoiceUsageSuccessfulDictation(entry) {
                dictation += 1
            } else if isVoiceUsageFailure(entry) {
                failure += 1
            } else if isVoiceUsageUnrecognized(entry) {
                unrecognized += 1
            } else if isVoiceUsageHUDControlMismatch(entry) {
                mismatch += 1
            } else if entry.kind == .control {
                control += 1
            }
        }
        return VoiceUsageSummary(
            total: voiceUsageHistory.count,
            dictationCount: dictation,
            failureCount: failure,
            unrecognizedCount: unrecognized,
            mismatchCount: mismatch,
            controlCount: control
        )
    }

    var voiceUsageAppSummaries: [VoiceUsageAppSummary] {
        let grouped = Dictionary(grouping: voiceUsageHistory) { $0.bundleIdentifier }
        let summaries = grouped.map { bundleID, entries -> VoiceUsageAppSummary in
            let dictationCount = entries.filter(isVoiceUsageSuccessfulDictation).count
            let failureCount = entries.filter(isVoiceUsageFailure).count
            let unrecognizedCount = entries.filter(isVoiceUsageUnrecognized).count
            let mismatchCount = entries.filter(isVoiceUsageHUDControlMismatch).count
            let controlCount = entries.filter { $0.kind == .control }.count
            let appName = entries.first?.appName ?? bundleID
            return VoiceUsageAppSummary(
                appName: appName,
                bundleIdentifier: bundleID,
                total: entries.count,
                dictationCount: dictationCount,
                failureCount: failureCount,
                unrecognizedCount: unrecognizedCount,
                mismatchCount: mismatchCount,
                controlCount: controlCount
            )
        }
        return summaries.sorted {
            if $0.total == $1.total {
                return $0.appName.localizedCaseInsensitiveCompare($1.appName) == .orderedAscending
            }
            return $0.total > $1.total
        }
    }

    func clearVoiceUsageHistory() {
        voiceUsageHistory = []
    }

    private func isVoiceUsageSuccessfulDictation(_ entry: VoiceUsageEvent) -> Bool {
        guard entry.kind == .dictation else { return false }
        return entry.action == "输入" || entry.action == "Dictation"
    }

    private func isVoiceUsageFailure(_ entry: VoiceUsageEvent) -> Bool {
        guard entry.kind == .dictation else { return false }
        return entry.action == "识别失败"
            || entry.action == "Recognition Failed"
            || entry.action == "注入失败"
            || entry.action == "Injection Failed"
            || entry.action == "注入未验证"
            || entry.action == "Injection Unverified"
    }

    private func isVoiceUsageUnrecognized(_ entry: VoiceUsageEvent) -> Bool {
        guard entry.kind == .dictation else { return false }
        return entry.action == "未识别" || entry.action == "Unrecognized"
    }

    private func isVoiceUsageHUDControlMismatch(_ entry: VoiceUsageEvent) -> Bool {
        guard entry.kind == .dictation else { return false }
        return entry.action == "控制模式下输入" || entry.action == "Dictation While HUD Control"
    }

    func mergedFrontmostAppCommandSnapshot(_ snapshot: FrontmostAppCommandSnapshot?) -> FrontmostAppCommandSnapshot? {
        mergeFrontmostAppCommandSnapshot(snapshot: snapshot, customRules: customAppShortcutRules)
    }

    func addCustomAppShortcutRule(prefilling bundleIdentifier: String? = nil) {
        let resolvedBundleIdentifier = bundleIdentifier
            ?? NSWorkspace.shared.frontmostApplication?.bundleIdentifier
            ?? ""
        let defaultTitle = AppLocalization.isChinese ? "新动作" : "New Action"
        customAppShortcutRules.insert(
            CustomAppShortcutRule(
                bundleIdentifier: resolvedBundleIdentifier,
                title: defaultTitle,
                shortcut: HotkeyBinding(keyCode: kVK_Return, modifiers: 0)
            ),
            at: 0
        )
    }

    func removeCustomAppShortcutRule(id: String) {
        customAppShortcutRules.removeAll { $0.id == id }
    }

    func aliasesText(for customRuleID: String) -> String {
        customAppShortcutRules
            .first(where: { $0.id == customRuleID })?
            .aliases
            .joined(separator: ", ")
            ?? ""
    }

    func updateAliasesText(_ raw: String, for customRuleID: String) {
        guard let index = customAppShortcutRules.firstIndex(where: { $0.id == customRuleID }) else { return }
        customAppShortcutRules[index].aliases = raw
            .components(separatedBy: CharacterSet(charactersIn: ",\n"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    func addSpeechTermGroup() {
        speechTermGroups.append(
            SpeechTermGroupConfig(
                name: "新分组",
                isEnabled: true,
                applyToAllApps: false,
                appList: "",
                rulesText: ""
            )
        )
    }

    func removeSpeechTermGroup(id: String) {
        speechTermGroups.removeAll { $0.id == id }
        if speechTermGroups.isEmpty {
            speechTermGroups = AppState.defaultSpeechTermGroups()
        }
    }

    func effectiveCommandAliases(for preset: VoiceCommandPreset, localeIdentifier: String) -> [String] {
        VoiceCommandRouter.effectiveAliases(
            for: preset,
            localeIdentifier: localeIdentifier,
            overrides: voiceCommandOverrides
        )
    }

    func commandOverrideText(for preset: VoiceCommandPreset, localeIdentifier: String) -> String {
        let canonical = VoiceLexiconSupport.canonicalLocaleIdentifier(localeIdentifier)
        if let override = voiceCommandOverrides.first(where: {
            VoiceLexiconSupport.canonicalLocaleIdentifier($0.localeIdentifier) == canonical &&
                $0.commandID == preset.rawValue
        }) {
            return override.aliases.joined(separator: ", ")
        }
        let defaults = VoiceCommandRouter.defaultAliases(for: preset, localeIdentifier: canonical)
        return defaults.joined(separator: ", ")
    }

    func updateCommandOverrideText(_ raw: String, for preset: VoiceCommandPreset, localeIdentifier: String) {
        let aliases = raw
            .components(separatedBy: CharacterSet(charactersIn: ",\n"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let canonical = VoiceLexiconSupport.canonicalLocaleIdentifier(localeIdentifier)
        voiceCommandOverrides.removeAll {
            VoiceLexiconSupport.canonicalLocaleIdentifier($0.localeIdentifier) == canonical &&
                $0.commandID == preset.rawValue
        }

        voiceCommandOverrides.append(
            VoiceCommandOverrideConfig(
                localeIdentifier: canonical,
                commandID: preset.rawValue,
                aliases: aliases
            )
        )
    }

    func resetCommandOverrides(for localeIdentifier: String) {
        let canonical = VoiceLexiconSupport.canonicalLocaleIdentifier(localeIdentifier)
        voiceCommandOverrides.removeAll {
            VoiceLexiconSupport.canonicalLocaleIdentifier($0.localeIdentifier) == canonical
        }
        if let defaults = VoiceLexiconDefaults.load() {
            let entries = defaults.commandOverrides.filter {
                VoiceLexiconSupport.canonicalLocaleIdentifier($0.localeIdentifier) == canonical
            }
            voiceCommandOverrides.append(contentsOf: entries)
        }
    }

    func wakeWordOverrideText(for localeIdentifier: String) -> String {
        let canonical = VoiceLexiconSupport.canonicalLocaleIdentifier(localeIdentifier)
        if let override = voiceLanguageTermsOverrides.first(where: {
            VoiceLexiconSupport.canonicalLocaleIdentifier($0.localeIdentifier) == canonical
        }) {
            return override.wakeWords.joined(separator: ", ")
        }
        let defaults = VoiceLexiconDefaults.load()?.languageTermsOverrides.first(where: {
            VoiceLexiconSupport.canonicalLocaleIdentifier($0.localeIdentifier) == canonical
        })
        return defaults?.wakeWords.joined(separator: ", ") ?? ""
    }

    func defaultWakeWordText(for localeIdentifier: String) -> String {
        let canonical = VoiceLexiconSupport.canonicalLocaleIdentifier(localeIdentifier)
        let defaults = VoiceLexiconDefaults.load()?.languageTermsOverrides.first(where: {
            VoiceLexiconSupport.canonicalLocaleIdentifier($0.localeIdentifier) == canonical
        })
        return defaults?.wakeWords.joined(separator: ", ") ?? ""
    }

    func updateWakeWordOverrideText(_ raw: String, for localeIdentifier: String) {
        updateVoiceLanguageTermsOverride(for: localeIdentifier) { config in
            config.wakeWords = parseVoiceTermsText(raw)
        }
    }

    func commandPrefixOverrideText(for localeIdentifier: String) -> String {
        let canonical = VoiceLexiconSupport.canonicalLocaleIdentifier(localeIdentifier)
        if let override = voiceLanguageTermsOverrides.first(where: {
            VoiceLexiconSupport.canonicalLocaleIdentifier($0.localeIdentifier) == canonical
        }) {
            return override.commandPrefixes.joined(separator: ", ")
        }
        let defaults = VoiceLexiconDefaults.load()?.languageTermsOverrides.first(where: {
            VoiceLexiconSupport.canonicalLocaleIdentifier($0.localeIdentifier) == canonical
        })
        return defaults?.commandPrefixes.joined(separator: ", ") ?? ""
    }

    func defaultCommandPrefixText(for localeIdentifier: String) -> String {
        let canonical = VoiceLexiconSupport.canonicalLocaleIdentifier(localeIdentifier)
        let defaults = VoiceLexiconDefaults.load()?.languageTermsOverrides.first(where: {
            VoiceLexiconSupport.canonicalLocaleIdentifier($0.localeIdentifier) == canonical
        })
        return defaults?.commandPrefixes.joined(separator: ", ") ?? ""
    }

    func updateCommandPrefixOverrideText(_ raw: String, for localeIdentifier: String) {
        updateVoiceLanguageTermsOverride(for: localeIdentifier) { config in
            config.commandPrefixes = parseVoiceTermsText(raw)
        }
    }

    func restoreDefaultCommandPrefixes(for localeIdentifier: String) {
        let defaults = defaultCommandPrefixText(for: localeIdentifier)
        updateCommandPrefixOverrideText(defaults, for: localeIdentifier)
    }

    func dictationPrefixOverrideText(for localeIdentifier: String) -> String {
        let canonical = VoiceLexiconSupport.canonicalLocaleIdentifier(localeIdentifier)
        if let override = voiceLanguageTermsOverrides.first(where: {
            VoiceLexiconSupport.canonicalLocaleIdentifier($0.localeIdentifier) == canonical
        }) {
            return override.dictationPrefixes.joined(separator: ", ")
        }
        let defaults = VoiceLexiconDefaults.load()?.languageTermsOverrides.first(where: {
            VoiceLexiconSupport.canonicalLocaleIdentifier($0.localeIdentifier) == canonical
        })
        return defaults?.dictationPrefixes.joined(separator: ", ") ?? ""
    }

    func defaultDictationPrefixText(for localeIdentifier: String) -> String {
        let canonical = VoiceLexiconSupport.canonicalLocaleIdentifier(localeIdentifier)
        let defaults = VoiceLexiconDefaults.load()?.languageTermsOverrides.first(where: {
            VoiceLexiconSupport.canonicalLocaleIdentifier($0.localeIdentifier) == canonical
        })
        return defaults?.dictationPrefixes.joined(separator: ", ") ?? ""
    }

    func updateDictationPrefixOverrideText(_ raw: String, for localeIdentifier: String) {
        updateVoiceLanguageTermsOverride(for: localeIdentifier) { config in
            config.dictationPrefixes = parseVoiceTermsText(raw)
        }
    }

    func restoreDefaultDictationPrefixes(for localeIdentifier: String) {
        let defaults = defaultDictationPrefixText(for: localeIdentifier)
        updateDictationPrefixOverrideText(defaults, for: localeIdentifier)
    }

    func resetVoiceLanguageTermsOverrides(for localeIdentifier: String) {
        let canonical = VoiceLexiconSupport.canonicalLocaleIdentifier(localeIdentifier)
        voiceLanguageTermsOverrides.removeAll {
            VoiceLexiconSupport.canonicalLocaleIdentifier($0.localeIdentifier) == canonical
        }
        if let defaults = VoiceLexiconDefaults.load() {
            let entries = defaults.languageTermsOverrides.filter {
                VoiceLexiconSupport.canonicalLocaleIdentifier($0.localeIdentifier) == canonical
            }
            voiceLanguageTermsOverrides.append(contentsOf: entries)
        }
    }

    func exportVoiceLexicon() throws -> URL? {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = "AetherVoiceLexicon.json"
        panel.prompt = String(localized: "voice_lexicon.export")

        guard panel.runModal() == .OK, let url = panel.url else { return nil }

        let payload = VoiceLexiconBackup(
            commandOverrides: voiceCommandOverrides,
            languageTermsOverrides: voiceLanguageTermsOverrides
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(payload)
        try data.write(to: url, options: .atomic)
        return url
    }

    func importVoiceLexicon() throws -> URL? {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.prompt = String(localized: "voice_lexicon.import")

        guard panel.runModal() == .OK, let url = panel.url else { return nil }

        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let payload = try decoder.decode(VoiceLexiconBackup.self, from: data)
        voiceCommandOverrides = Self.sanitizeVoiceCommandOverrides(payload.commandOverrides)
        voiceLanguageTermsOverrides = payload.languageTermsOverrides
        return url
    }

    func importVoiceLexiconFromPasteboard() throws -> Bool {
        let pasteboard = NSPasteboard.general
        guard let raw = pasteboard.string(forType: .string) else { return false }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        let data = Data(trimmed.utf8)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let payload = try decoder.decode(VoiceLexiconBackup.self, from: data)
        mergeVoiceLexicon(payload)
        return true
    }

    private func mergeVoiceLexicon(_ payload: VoiceLexiconBackup) {
        voiceCommandOverrides = Self.mergeCommandOverrides(
            existing: voiceCommandOverrides,
            incoming: payload.commandOverrides
        )
        voiceLanguageTermsOverrides = Self.mergeLanguageTermsOverrides(
            existing: voiceLanguageTermsOverrides,
            incoming: payload.languageTermsOverrides
        )
    }

    private static func mergeCommandOverrides(
        existing: [VoiceCommandOverrideConfig],
        incoming: [VoiceCommandOverrideConfig]
    ) -> [VoiceCommandOverrideConfig] {
        var result = sanitizeVoiceCommandOverrides(existing)
        var indexByKey: [String: Int] = [:]
        for (idx, item) in result.enumerated() {
            let key = voiceCommandKey(locale: item.localeIdentifier, commandID: item.commandID)
            indexByKey[key] = idx
        }

        for item in sanitizeVoiceCommandOverrides(incoming) {
            let key = voiceCommandKey(locale: item.localeIdentifier, commandID: item.commandID)
            if let idx = indexByKey[key] {
                let merged = mergeAliases(base: result[idx].aliases, extra: item.aliases)
                result[idx].aliases = merged
            } else {
                let cleaned = mergeAliases(base: [], extra: item.aliases)
                let entry = VoiceCommandOverrideConfig(
                    localeIdentifier: item.localeIdentifier,
                    commandID: item.commandID,
                    aliases: cleaned
                )
                indexByKey[key] = result.count
                result.append(entry)
            }
        }
        return result
    }

    private static func mergeLanguageTermsOverrides(
        existing: [VoiceLanguageTermsOverrideConfig],
        incoming: [VoiceLanguageTermsOverrideConfig]
    ) -> [VoiceLanguageTermsOverrideConfig] {
        var result = existing
        var indexByKey: [String: Int] = [:]
        for (idx, item) in result.enumerated() {
            let key = canonicalLocaleKey(item.localeIdentifier)
            indexByKey[key] = idx
        }

        for item in incoming {
            let key = canonicalLocaleKey(item.localeIdentifier)
            if let idx = indexByKey[key] {
                var merged = result[idx]
                merged.wakeWords = mergeAliases(base: merged.wakeWords, extra: item.wakeWords)
                merged.commandPrefixes = mergeAliases(base: merged.commandPrefixes, extra: item.commandPrefixes)
                merged.dictationPrefixes = mergeAliases(base: merged.dictationPrefixes, extra: item.dictationPrefixes)
                result[idx] = merged
            } else {
                let entry = VoiceLanguageTermsOverrideConfig(
                    localeIdentifier: item.localeIdentifier,
                    wakeWords: mergeAliases(base: [], extra: item.wakeWords),
                    commandPrefixes: mergeAliases(base: [], extra: item.commandPrefixes),
                    dictationPrefixes: mergeAliases(base: [], extra: item.dictationPrefixes)
                )
                indexByKey[key] = result.count
                result.append(entry)
            }
        }
        return result
    }

    private static func mergeAliases(base: [String], extra: [String]) -> [String] {
        VoiceLexiconSupport.uniqueTerms(base + extra)
    }

    private static func canonicalLocaleKey(_ raw: String) -> String {
        VoiceLexiconSupport.canonicalLocaleIdentifier(raw).lowercased()
    }

    private static func voiceCommandKey(locale: String, commandID: String) -> String {
        "\(canonicalLocaleKey(locale))::\(commandID)"
    }

    func exportAetherAIConfigPrompt() throws {
        let prompt = buildAetherAIConfigPrompt()
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        guard pasteboard.setString(prompt, forType: .string) else {
            throw NSError(domain: "AetherPromptExport", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to copy prompt to pasteboard."])
        }
    }

    func copyVoiceUsageHistoryForDiagnostics() throws {
        let summary = voiceUsageSummary
        let localeID = voiceService.effectiveLocaleIdentifier
        let summaryLine = AppLocalization.isChinese
            ? "使用统计（总计=\(summary.total) 输入=\(summary.dictationCount) 控制=\(summary.controlCount) locale=\(localeID)）："
            : "Usage Stats (total=\(summary.total) dictation=\(summary.dictationCount) control=\(summary.controlCount) locale=\(localeID)):"
        let payload = try voiceUsageHistoryExportString(
            summary: summaryLine,
            events: voiceUsageHistory
        )
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        guard pasteboard.setString(payload, forType: .string) else {
            throw NSError(domain: "AetherUsageHistoryExport", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to copy usage history to pasteboard."])
        }
    }

    func copyVoiceUsageEvent(_ event: VoiceUsageEvent) throws {
        let localeID = voiceService.effectiveLocaleIdentifier
        let summaryLine = AppLocalization.isChinese
            ? "使用统计（单条 locale=\(localeID)）："
            : "Usage Event (locale=\(localeID)):"
        let payload = try voiceUsageHistoryExportString(
            summary: summaryLine,
            events: [event]
        )
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        guard pasteboard.setString(payload, forType: .string) else {
            throw NSError(domain: "AetherUsageEventExport", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to copy usage event to pasteboard."])
        }
    }

    func copyCustomAppShortcutRulesToPasteboard() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(CustomAppShortcutRulesBackup(rules: customAppShortcutRules))
        guard let payload = String(data: data, encoding: .utf8) else {
            throw NSError(domain: "AetherCustomRulesCopy", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to encode custom app rules."])
        }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        guard pasteboard.setString(payload, forType: .string) else {
            throw NSError(domain: "AetherCustomRulesCopy", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to copy custom app rules to pasteboard."])
        }
    }

    func importCustomAppShortcutRulesFromPasteboard() throws -> Bool {
        let pasteboard = NSPasteboard.general
        guard let raw = pasteboard.string(forType: .string) else { return false }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let data = Data(trimmed.utf8)

        if let backup = try? decoder.decode(CustomAppShortcutRulesBackup.self, from: data) {
            mergeCustomAppShortcutRules(backup.rules)
            return true
        }

        let rules = try decoder.decode([CustomAppShortcutRule].self, from: data)
        mergeCustomAppShortcutRules(rules)
        return true
    }

    private func mergeCustomAppShortcutRules(_ incoming: [CustomAppShortcutRule]) {
        var merged = customAppShortcutRules
        var keys = Set(merged.map(customAppShortcutRuleSemanticKey(_:)))
        for rule in incoming {
            let key = customAppShortcutRuleSemanticKey(rule)
            guard !keys.contains(key) else { continue }
            keys.insert(key)
            merged.append(rule)
        }
        customAppShortcutRules = merged
    }

    private func customAppShortcutRuleSemanticKey(_ rule: CustomAppShortcutRule) -> String {
        [
            rule.bundleIdentifier.lowercased(),
            rule.title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
            String(rule.shortcut.keyCode),
            String(rule.shortcut.modifiers)
        ].joined(separator: "::")
    }

    private func parseVoiceTermsText(_ raw: String) -> [String] {
        raw
            .components(separatedBy: CharacterSet(charactersIn: ",\n"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func updateVoiceLanguageTermsOverride(
        for localeIdentifier: String,
        mutate: (inout VoiceLanguageTermsOverrideConfig) -> Void
    ) {
        let canonical = VoiceLexiconSupport.canonicalLocaleIdentifier(localeIdentifier)
        var config = voiceLanguageTermsOverrides.first(where: {
            VoiceLexiconSupport.canonicalLocaleIdentifier($0.localeIdentifier) == canonical
        }) ?? VoiceLexiconDefaults.load()?.languageTermsOverrides.first(where: {
            VoiceLexiconSupport.canonicalLocaleIdentifier($0.localeIdentifier) == canonical
        }) ?? VoiceLanguageTermsOverrideConfig(
            localeIdentifier: canonical,
            wakeWords: [],
            commandPrefixes: [],
            dictationPrefixes: []
        )

        mutate(&config)

        config.localeIdentifier = canonical
        voiceLanguageTermsOverrides.removeAll {
            VoiceLexiconSupport.canonicalLocaleIdentifier($0.localeIdentifier) == canonical
        }
        voiceLanguageTermsOverrides.append(config)
    }

    private func voiceUsageHistoryExportString(
        summary: String,
        events: [VoiceUsageEvent]
    ) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(events)
        let json = String(decoding: data, as: UTF8.self)
        return "\(summary)\n\(json)"
    }
    
    func updatePTTBinding(_ binding: HotkeyBinding) {
        let normalized = HotkeyBinding(
            keyCode: binding.keyCode,
            modifiers: Self.sanitizeHotkeyModifiers(binding.modifiers),
            mouseButton: binding.mouseButton
        )

        self.voicePTTBinding = normalized
        UserDefaults.standard.set(normalized.keyCode, forKey: "voicePTTKeyCode")
        UserDefaults.standard.set(normalized.modifiers, forKey: "voicePTTModifiers")
        
        // Update Hotkey Manager ONLY if enabled
        if isPTTEnabled {
            HotkeyManager.shared.registerPTT(normalized)
        }
    }
    
    @Published var alwaysListeningWakeWindowSeconds: Double = UserDefaults.standard.object(forKey: "alwaysListeningWakeWindowSeconds") as? Double ?? 8.0 {
        didSet {
            let clamped = min(max(alwaysListeningWakeWindowSeconds, 3.0), 30.0)
            if clamped != alwaysListeningWakeWindowSeconds {
                alwaysListeningWakeWindowSeconds = clamped
                return
            }
            UserDefaults.standard.set(clamped, forKey: "alwaysListeningWakeWindowSeconds")
        }
    }
    @Published var isLLMEnhancementEnabled: Bool = UserDefaults.standard.bool(forKey: "isLLMEnhancementEnabled") {
        didSet {
            UserDefaults.standard.set(isLLMEnhancementEnabled, forKey: "isLLMEnhancementEnabled")
            voiceService.setLLMEnhancementEnabled(isLLMEnhancementEnabled)
        }
    }

    @Published var onboardingStep: OnboardingStep = .done
    
    @Published var hudAutoHideSeconds: Double = UserDefaults.standard.object(forKey: "hudAutoHideSeconds") as? Double ?? 1.5 {
        didSet {
            let clamped = min(max(hudAutoHideSeconds, 0.5), 8.0)
            if clamped != hudAutoHideSeconds {
                hudAutoHideSeconds = clamped
                return
            }
            UserDefaults.standard.set(clamped, forKey: "hudAutoHideSeconds")
        }
    }
    
    let motionService = MotionService()
    let voiceService = VoiceService()
    let nowPlayingService = NowPlayingService.shared
    private let permissions = PermissionsService()
    let connectionLock = ConnectionLockService.shared

    private var windowController: NSWindowController?
    private var cancellables = Set<AnyCancellable>()
    private var hasShownAccessibilityHint: Bool = false
    private var hasRequestedAccessibilityPromptThisRun: Bool = false
    private var lastObservedAccessibilityTrusted: Bool?
    private var accessibilityRecoveryTimer: Timer?

    
    init() {
        CurrentAppShortcutPanelManager.shared.appState = self

        motionService.$isTracking
            .assign(to: &$isMotionTracking)
            
        motionService.$attitudeText
            .assign(to: &$attitudeData)
            
        motionService.$calibrationStatus
            .receive(on: DispatchQueue.main)
            .assign(to: &$calibrationStatus)
            
        // Voice Service Sync
        // Forward voiceService changes to AppState so SwiftUI views observing
        // appState (e.g. SettingsModules) react to nested property changes.
        voiceService.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)

        // Permissions Sync
        // Keep Settings permission rows in lockstep with runtime permission checks.
        // Without this bridge, AppState computed permission properties can appear stale in UI.
        permissions.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)

        nowPlayingService.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
        
        voiceService.$availableInputDevices
            .receive(on: DispatchQueue.main)
            .sink { [weak self] devices in
                guard let self else { return }
                self.availableInputDevices = devices
                self.handleHeadsetAutoEnable(source: "input-devices")
            }
            .store(in: &cancellables)
            
        voiceService.$selectedInputDeviceID
            .receive(on: DispatchQueue.main)
            .sink { [weak self] newVal in
                 guard let self else { return }
                 if self.selectedInputDeviceID != newVal {
                     self.selectedInputDeviceID = newVal
                 }
                 self.handleHeadsetAutoEnable(source: "input-selection")
            }
            .store(in: &cancellables)
            

            
        voiceService.$isGazeWakeEnabled
            .receive(on: DispatchQueue.main)
            .assign(to: &$isGazeWakeEnabled)
            
        // Restore voice activation state after initial SwiftUI graph setup to avoid startup re-entrancy.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            HeadMotionManager.shared.setVoiceActivationMode(self.voiceActivationMode)
            self.applyVoiceActivationMode()
            self.handleHeadsetAutoEnable(source: "startup")
        }
        
        voiceService.setLLMEnhancementEnabled(self.isLLMEnhancementEnabled)
        voiceService.setVoiceCommandOverrides(self.voiceCommandOverrides)
        voiceService.setVoiceLanguageTermsOverrides(self.voiceLanguageTermsOverrides)
        voiceService.setCustomAppShortcutRules(self.customAppShortcutRules)

        voiceService.$status
            .assign(to: &$voiceStatus)
        voiceService.$lastTranscript
            .assign(to: &$lastVoiceTranscript)
        voiceService.$lastError
            .assign(to: &$lastVoiceError)
        voiceService.$lastWakeTime
            .assign(to: &$lastVoiceWakeTime)

        nowPlayingService.$appName
            .assign(to: &$nowPlayingAppName)
        nowPlayingService.$bundleIdentifier
            .assign(to: &$nowPlayingBundleIdentifier)
        nowPlayingService.$title
            .assign(to: &$nowPlayingTitle)
        nowPlayingService.$artist
            .assign(to: &$nowPlayingArtist)
        nowPlayingService.$album
            .assign(to: &$nowPlayingAlbum)
        nowPlayingService.$playbackRate
            .map { $0 > 0.01 ? "Playing" : "Paused" }
            .assign(to: &$nowPlayingStatus)


        voiceService.onIntent = { [weak self] intent, appName, bundleIdentifier in
            guard let self else { return }
            DispatchQueue.main.async {
                self.applyVoiceIntent(intent, appName: appName, bundleIdentifier: bundleIdentifier)
            }
        }
        voiceService.isDictationExecutionEnabled = { [weak self] in
            self?.isVoiceInputEnabled ?? true
        }
        voiceService.isCommandExecutionEnabled = { [weak self] in
            self?.isVoiceControlEnabled ?? true
        }
        
        voiceService.onRecognitionFailure = { [weak self] transcript, reason, appName, bundleIdentifier in
            guard let self else { return }
            DispatchQueue.main.async {
                let trimmed = transcript?.trimmingCharacters(in: .whitespacesAndNewlines)
                let content = (trimmed?.isEmpty == false) ? trimmed : nil
                self.recordVoiceFailure(content, reason: reason, appName: appName, bundleIdentifier: bundleIdentifier)
            }
        }

        permissions.$accessibilityTrusted
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                let live = AXIsProcessTrusted()
                self.motionService.setGlobalHotkeysEnabled(live)
                self.handleAccessibilityTrustTransitionIfNeeded(trusted: live, source: "permissions-publisher")
            }
            .store(in: &cancellables)

        Publishers.CombineLatest3(
            permissions.$accessibilityTrusted,
            permissions.$microphoneAuthorized,
            permissions.$speechAuthorized
        )
        .receive(on: DispatchQueue.main)
        .sink { [weak self] _, _, _ in
            guard let self = self else { return }
            // Single source of truth: use live system permission APIs for all runtime/UI decisions.
            let liveAX = AXIsProcessTrusted()
            let liveMic = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
            let liveSpeech = SFSpeechRecognizer.authorizationStatus() == .authorized
            let voiceReadyNow = liveMic && liveSpeech

            self.handleAccessibilityTrustTransitionIfNeeded(trusted: liveAX, source: "permissions-combine")
            self.voiceService.setAccessibilityTrusted(liveAX)
            self.onboardingStep = Self.deriveOnboardingStep(
                accessibilityTrusted: liveAX,
                microphoneAuthorized: liveMic,
                speechAuthorized: liveSpeech
            )

            // Missing Accessibility breaks AX focus/caret detection, so input mode won't switch.
            if !liveAX {
                if !self.hasShownAccessibilityHint {
                    self.hasShownAccessibilityHint = true
                    HUDManager.shared.showTemporary(
                        message: String(localized: "driver.error.need_accessibility"),
                        icon: "hand.raised.fill"
                    )
                }
                if !self.hasRequestedAccessibilityPromptThisRun {
                    self.hasRequestedAccessibilityPromptThisRun = true
                    self.permissions.requestAccessibility()
                }
            } else {
                self.hasShownAccessibilityHint = false
            }

            // Safety: if Always Listening is enabled but permissions got revoked, shut it off.
            // BUGFIX: Only reset if the app has actually initialized permissions. 
            // On startup, these values might be false temporarily before refresh() is called.
            if self.isAlwaysListeningEnabled && (!liveMic || !liveSpeech) {
                // If we are authorized but the published value is still false (race condition), don't reset.
                // Re-check synchronously to be absolutely sure.
                let micAuth = AVCaptureDevice.authorizationStatus(for: AVMediaType.audio) == .authorized
                let speechAuth = SFSpeechRecognizer.authorizationStatus() == .authorized
                
                if !micAuth || !speechAuth {
                    GlobalLogger.lifecycle.info("Permissons revoked, disabling Always Listening")
                    // Keep selected mode in UI and runtime mode flags aligned.
                    // SpeechManager will surface permission guidance and avoid capture start.
                    let requiresContinuous = self.voiceActivationMode != .pushToTalk
                    self.voiceService.setAlwaysListeningEnabled(requiresContinuous)
                    self.voiceService.setDirectCommandEnabled(self.voiceActivationMode == .handsFree)
                    self.voiceService.setWakeWordEnabled(self.voiceActivationMode == .wakeWord)
                }
            }

            // If user selected a non-PTT mode earlier but voice permissions were missing,
            // auto-apply that mode once permissions transition to ready.
            if self.voiceActivationMode != .pushToTalk,
               !self.lastVoiceReady,
               voiceReadyNow {
                self.applyVoiceActivationMode()
            }
            self.lastVoiceReady = voiceReadyNow
        }
        .store(in: &cancellables)

        // Connection Lock hotkey listener
        NotificationCenter.default.publisher(for: .toggleConnectionLock)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.connectionLock.toggle()
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .toggleShortcutPanel)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.toggleShortcutPanel()
            }
            .store(in: &cancellables)

        // Refresh permissions when the app comes back to foreground (e.g. after changing System Settings).
        NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.refreshPermissions()
            }
            .store(in: &cancellables)

        // If Accessibility is missing, keep polling so UI/hotkeys/HUD state updates promptly after user grants it.
        Timer.publish(every: 1.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self else { return }
                let liveAX = AXIsProcessTrusted()
                let liveMic = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
                let liveSpeech = SFSpeechRecognizer.authorizationStatus() == .authorized
                if !liveAX || !liveMic || !liveSpeech {
                    self.refreshPermissions()
                }
            }
            .store(in: &cancellables)

        refreshPermissions()
    }

    private func handleAccessibilityTrustTransitionIfNeeded(trusted: Bool, source: String) {
        guard lastObservedAccessibilityTrusted != trusted else { return }
        lastObservedAccessibilityTrusted = trusted
        motionService.recoverFromAccessibilityTrustChange(trusted, source: source)
        HUDManager.shared.recoverFromAccessibilityTrustChange(trusted: trusted, source: source)
        if trusted {
            _ = FrontmostAppCommandCatalog.shared.refresh(force: true)
            CurrentAppShortcutPanelManager.shared.refreshIfVisible()
            stopAccessibilityRecoveryPolling()
        }
        if trusted {
            hasRequestedAccessibilityPromptThisRun = false
            hasShownAccessibilityHint = false
        }
    }

    private func startAccessibilityRecoveryPolling() {
        stopAccessibilityRecoveryPolling()
        let deadline = Date().addingTimeInterval(18)
        let timer = Timer.scheduledTimer(withTimeInterval: 0.35, repeats: true) { [weak self] timer in
            Task { @MainActor [weak self] in
                guard let self else {
                    timer.invalidate()
                    return
                }
                self.refreshPermissions()
                if AXIsProcessTrusted() || Date() >= deadline {
                    timer.invalidate()
                    self.accessibilityRecoveryTimer = nil
                }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        accessibilityRecoveryTimer = timer
    }

    private func stopAccessibilityRecoveryPolling() {
        accessibilityRecoveryTimer?.invalidate()
        accessibilityRecoveryTimer = nil
    }

    private static func deriveOnboardingStep(
        accessibilityTrusted: Bool,
        microphoneAuthorized: Bool,
        speechAuthorized: Bool
    ) -> OnboardingStep {
        if !accessibilityTrusted { return .accessibility }
        if !microphoneAuthorized { return .microphone }
        if !speechAuthorized { return .speech }
        return .done
    }
    
    func finishCalibration() {
        motionService.finishCalibration()
    }
    
    func toggleMotionTracking() {
        if isMotionTracking {
            motionService.stopTracking()
        } else {
            motionService.startTracking()
        }
    }

    func showShortcutPanel(activateApp: Bool = true, focusSearchField: Bool = true) {
        CurrentAppShortcutPanelManager.shared.show(activateApp: activateApp, focusSearchField: focusSearchField)
    }

    func hideShortcutPanel() {
        CurrentAppShortcutPanelManager.shared.hide()
    }

    func toggleShortcutPanel(activateApp: Bool = true, focusSearchField: Bool = true) {
        CurrentAppShortcutPanelManager.shared.toggle(activateApp: activateApp, focusSearchField: focusSearchField)
    }

    func toggleRecognitionInputControlMode() {
        HeadMotionManager.shared.toggleRecognitionInputControlMode(source: "menu-bar", persist: true)
    }

    func refreshNowPlaying() {
        nowPlayingService.refresh()
    }

    func toggleNowPlayingPlayback() {
        nowPlayingService.togglePlayPause()
    }

    func skipNowPlayingForward() {
        nowPlayingService.nextTrack()
    }

    func skipNowPlayingBackward() {
        nowPlayingService.previousTrack()
    }

    func recordShortcutPanelCurrentAppShortcut(_ command: FrontmostAppCommand) {
        recordVoiceUsageEvent(
            kind: .control,
            action: shortcutPanelActionTitle(command.title),
            content: nil,
            appName: command.appName,
            bundleIdentifier: command.bundleIdentifier
        )
    }

    func recordShortcutPanelGlobalShortcut(_ action: HotkeyAction) {
        let bundleIdentifier = Bundle.main.bundleIdentifier ?? "com.7fei.Aether"
        recordVoiceUsageEvent(
            kind: .control,
            action: shortcutPanelActionTitle(action.label),
            content: nil,
            appName: String(localized: "app.project_title"),
            bundleIdentifier: bundleIdentifier
        )
    }

    private func applyVoiceIntent(
        _ intent: VoiceIntent,
        appName: String? = nil,
        bundleIdentifier: String? = nil
    ) {
        GlobalLogger.lifecycle.info("[VoiceIntent] execute \(voiceIntentActionTitle(intent))")
        switch intent {
        case .clickLeft:
            GlobalLogger.lifecycle.info("[VoiceIntent] action=clickLeft")
            motionService.clickLeft()
            recordVoiceControl(intent, appName: appName, bundleIdentifier: bundleIdentifier)
        case .clickRight:
            GlobalLogger.lifecycle.info("[VoiceIntent] action=clickRight")
            motionService.clickRight()
            recordVoiceControl(intent, appName: appName, bundleIdentifier: bundleIdentifier)
        case .doubleClick:
            GlobalLogger.lifecycle.info("[VoiceIntent] action=doubleClick")
            motionService.doubleClick()
            recordVoiceControl(intent, appName: appName, bundleIdentifier: bundleIdentifier)
        case .toggleInputControlMode:
            GlobalLogger.lifecycle.info("[VoiceIntent] action=toggleInputControlMode")
            toggleRecognitionInputControlMode()
            recordVoiceControl(intent, appName: appName, bundleIdentifier: bundleIdentifier)
        case .toggleTracking:
            GlobalLogger.lifecycle.info("[VoiceIntent] action=toggleTracking")
            toggleMotionTracking()
            recordVoiceControl(intent, appName: appName, bundleIdentifier: bundleIdentifier)
        case .toggleLanguage:
            GlobalLogger.lifecycle.info("[VoiceIntent] action=toggleLanguage")
            guard isVoiceControlEnabled else { return }
            NotificationCenter.default.post(name: Notification.Name("AetherToggleLanguage"), object: nil)
            recordVoiceControl(intent, appName: appName, bundleIdentifier: bundleIdentifier)
        case .toggleConnectionLock:
            GlobalLogger.lifecycle.info("[VoiceIntent] action=toggleConnectionLock")
            connectionLock.toggle()
            recordVoiceControl(intent, appName: appName, bundleIdentifier: bundleIdentifier)
        case .toggleShortcutPanel:
            GlobalLogger.lifecycle.info("[VoiceIntent] action=toggleShortcutPanel")
            toggleShortcutPanel(activateApp: false, focusSearchField: false)
            recordVoiceControl(intent, appName: appName, bundleIdentifier: bundleIdentifier)
        case .mediaPlayPause:
            GlobalLogger.lifecycle.info("[VoiceIntent] action=mediaPlayPause")
            nowPlayingService.togglePlayPause()
            recordVoiceControl(
                intent,
                appName: nowPlayingAppName.isEmpty ? nil : nowPlayingAppName,
                bundleIdentifier: nowPlayingBundleIdentifier.isEmpty ? nil : nowPlayingBundleIdentifier
            )
        case .mediaPrevious:
            GlobalLogger.lifecycle.info("[VoiceIntent] action=mediaPrevious")
            nowPlayingService.previousTrack()
            recordVoiceControl(
                intent,
                appName: nowPlayingAppName.isEmpty ? nil : nowPlayingAppName,
                bundleIdentifier: nowPlayingBundleIdentifier.isEmpty ? nil : nowPlayingBundleIdentifier
            )
        case .mediaNext:
            GlobalLogger.lifecycle.info("[VoiceIntent] action=mediaNext")
            nowPlayingService.nextTrack()
            recordVoiceControl(
                intent,
                appName: nowPlayingAppName.isEmpty ? nil : nowPlayingAppName,
                bundleIdentifier: nowPlayingBundleIdentifier.isEmpty ? nil : nowPlayingBundleIdentifier
            )
        case .showShortcutPanel:
            GlobalLogger.lifecycle.info("[VoiceIntent] action=showShortcutPanel")
            showShortcutPanel(activateApp: false, focusSearchField: false)
            recordVoiceControl(intent, appName: appName, bundleIdentifier: bundleIdentifier)
        case .hideShortcutPanel:
            GlobalLogger.lifecycle.info("[VoiceIntent] action=hideShortcutPanel")
            hideShortcutPanel()
            recordVoiceControl(intent, appName: appName, bundleIdentifier: bundleIdentifier)
        case .startPointer:
            GlobalLogger.lifecycle.info("[VoiceIntent] action=startPointer")
            motionService.startTracking()
            recordVoiceControl(intent, appName: appName, bundleIdentifier: bundleIdentifier)
        case .stopPointer:
            GlobalLogger.lifecycle.info("[VoiceIntent] action=stopPointer")
            motionService.stopTracking()
            recordVoiceControl(intent, appName: appName, bundleIdentifier: bundleIdentifier)
        case .recenter:
            GlobalLogger.lifecycle.info("[VoiceIntent] action=recenter")
            motionService.recenter()
            recordVoiceControl(intent, appName: appName, bundleIdentifier: bundleIdentifier)
        case .frontmostAppCommand(let command):
            GlobalLogger.lifecycle.info("[VoiceIntent] action=frontmostAppCommand title=\(command.title) shortcut=\(command.shortcut.displayString) pid=\(command.processIdentifier)")
            AutomationOutputs.shared.pressShortcut(command.shortcut, targetPID: command.processIdentifier)
            recordVoiceControl(
                intent,
                appName: command.appName,
                bundleIdentifier: command.bundleIdentifier
            )
        case .scroll(let dx, let dy):
            GlobalLogger.lifecycle.info("[VoiceIntent] action=scroll dx=\(dx) dy=\(dy)")
            motionService.scroll(dx: dx, dy: dy)
            recordVoiceControl(intent, appName: appName, bundleIdentifier: bundleIdentifier)
        case .scrollToWeb(let edge):
            GlobalLogger.lifecycle.info("[VoiceIntent] action=scrollToWeb edge=\(edge)")
            if edge == "top" { motionService.scrollToTop() }
            else { motionService.scrollToBottom() }
            recordVoiceControl(intent, appName: appName, bundleIdentifier: bundleIdentifier)
        case .dragStart:
            GlobalLogger.lifecycle.info("[VoiceIntent] action=dragStart")
            motionService.dragStart()
            recordVoiceControl(intent, appName: appName, bundleIdentifier: bundleIdentifier)
        case .dragEnd:
            GlobalLogger.lifecycle.info("[VoiceIntent] action=dragEnd")
            motionService.dragEnd()
            recordVoiceControl(intent, appName: appName, bundleIdentifier: bundleIdentifier)
        case .undo:
            GlobalLogger.lifecycle.info("[VoiceIntent] action=undo")
            // Already applied inside SpeechManager. Keep this branch for usage tracking only.
            recordVoiceControl(intent, appName: appName, bundleIdentifier: bundleIdentifier)
        case .paste:
            GlobalLogger.lifecycle.info("[VoiceIntent] action=paste")
            // Already applied inside SpeechManager. Keep this branch for usage tracking only.
            recordVoiceControl(intent, appName: appName, bundleIdentifier: bundleIdentifier)
        case .clearInput:
            GlobalLogger.lifecycle.info("[VoiceIntent] action=clearInput")
            // Already applied inside SpeechManager. Keep this branch for usage tracking only.
            recordVoiceControl(intent, appName: appName, bundleIdentifier: bundleIdentifier)
        case .deleteBackward(let count):
            GlobalLogger.lifecycle.info("[VoiceIntent] action=deleteBackward count=\(count)")
            // Already applied inside SpeechManager. Keep this branch for usage tracking only.
            recordVoiceControl(intent, appName: appName, bundleIdentifier: bundleIdentifier)
        case .lockConnection:
            GlobalLogger.lifecycle.info("[VoiceIntent] action=lockConnection")
            connectionLock.lock()
            recordVoiceControl(intent, appName: appName, bundleIdentifier: bundleIdentifier)
        case .unlockConnection:
            GlobalLogger.lifecycle.info("[VoiceIntent] action=unlockConnection")
            connectionLock.unlock()
            recordVoiceControl(intent, appName: appName, bundleIdentifier: bundleIdentifier)
        case .dictation(let text):
            GlobalLogger.lifecycle.info("[VoiceIntent] action=dictation text=\(text)")
            if HUDManager.shared.state.recognitionControlMode == .command || !HUDManager.shared.state.isTypingContext {
                GlobalLogger.lifecycle.info("[VoiceIntent] hud_control_mismatch text=\(text)")
                recordVoiceDictationWhileHUDControl(text, appName: appName, bundleIdentifier: bundleIdentifier)
            } else {
                recordVoiceDictation(text, appName: appName, bundleIdentifier: bundleIdentifier)
            }
        case .unknown:
            GlobalLogger.lifecycle.info("[VoiceIntent] action=unknown")
            if case .unknown(let transcript) = intent {
                let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
                let hudState = HUDManager.shared.state
                let isControlLike = hudState.recognitionControlMode == .command || !hudState.isTypingContext
                if !trimmed.isEmpty, !isControlLike {
                    recordVoiceUnrecognized(trimmed, appName: appName, bundleIdentifier: bundleIdentifier)
                } else if !trimmed.isEmpty {
                    recordVoiceUnknownCommand(trimmed, appName: appName, bundleIdentifier: bundleIdentifier)
                } else {
                    recordVoiceControl(intent, appName: appName, bundleIdentifier: bundleIdentifier)
                }
            } else {
                recordVoiceControl(intent, appName: appName, bundleIdentifier: bundleIdentifier)
            }
        }
    }

    private func recordVoiceControl(
        _ intent: VoiceIntent,
        appName: String? = nil,
        bundleIdentifier: String? = nil
    ) {
        recordVoiceUsageEvent(
            kind: .control,
            action: voiceIntentActionTitle(intent),
            content: nil,
            appName: appName,
            bundleIdentifier: bundleIdentifier
        )
    }

    private func recordVoiceUnknownCommand(_ text: String, appName: String? = nil, bundleIdentifier: String? = nil) {
        recordVoiceUsageEvent(
            kind: .control,
            action: NSLocalizedString("intent.unknown", comment: ""),
            content: text,
            appName: appName,
            bundleIdentifier: bundleIdentifier
        )
    }

    private func recordVoiceDictation(_ text: String, appName: String? = nil, bundleIdentifier: String? = nil) {
        recordVoiceUsageEvent(
            kind: .dictation,
            action: AppLocalization.isChinese ? "输入" : "Dictation",
            content: text,
            appName: appName,
            bundleIdentifier: bundleIdentifier
        )
    }
    
    private func recordVoiceDictationWhileHUDControl(_ text: String, appName: String? = nil, bundleIdentifier: String? = nil) {
        recordVoiceUsageEvent(
            kind: .dictation,
            action: AppLocalization.isChinese ? "控制模式误输入" : "Dictation While Control Mode",
            content: text,
            appName: appName,
            bundleIdentifier: bundleIdentifier
        )
    }
    
    private func recordVoiceUnrecognized(_ text: String, appName: String? = nil, bundleIdentifier: String? = nil) {
        recordVoiceUsageEvent(
            kind: .dictation,
            action: AppLocalization.isChinese ? "未输入（无输入框）" : "No Input Target",
            content: text,
            appName: appName,
            bundleIdentifier: bundleIdentifier
        )
    }
    
    private func recordVoiceFailure(
        _ text: String?,
        reason: String? = nil,
        appName: String? = nil,
        bundleIdentifier: String? = nil
    ) {
        let action: String
        if reason == "dictation-disabled" {
            action = AppLocalization.isChinese ? "语音输入已关闭" : "Voice Input Off"
        } else if reason == "invalid-input-target" || reason == "post-injection-mismatch" {
            action = AppLocalization.isChinese ? "输入失败" : "Input Failed"
        } else if reason == "post-injection-unverified" {
            action = AppLocalization.isChinese ? "输入未确认" : "Input Unverified"
        } else {
            action = AppLocalization.isChinese ? "识别失败" : "Recognition Failed"
        }
        recordVoiceUsageEvent(
            kind: .dictation,
            action: action,
            content: text,
            appName: appName,
            bundleIdentifier: bundleIdentifier
        )
    }

    private func recordVoiceUsageEvent(
        kind: VoiceUsageEventKind,
        action: String,
        content: String?,
        appName: String?,
        bundleIdentifier: String?
    ) {
        guard isVoiceUsageHistoryEnabled else { return }
        let context = resolvedVoiceUsageAppContext(appName: appName, bundleIdentifier: bundleIdentifier)
        let entry = VoiceUsageEvent(
            appName: context.name,
            bundleIdentifier: context.bundleIdentifier,
            kind: kind,
            action: action,
            content: normalizedVoiceUsageContent(content)
        )
        voiceUsageHistory.insert(entry, at: 0)
    }

    private func resolvedVoiceUsageAppContext(
        appName: String?,
        bundleIdentifier: String?
    ) -> (name: String, bundleIdentifier: String) {
        if let appName, !appName.isEmpty, let bundleIdentifier, !bundleIdentifier.isEmpty {
            return (appName, bundleIdentifier)
        }
        if let app = NSWorkspace.shared.frontmostApplication,
           let bundleID = app.bundleIdentifier,
           !bundleID.isEmpty {
            return (app.localizedName ?? bundleID, bundleID)
        }
        let fallbackName = AppLocalization.isChinese ? "未知应用" : "Unknown App"
        return (appName ?? fallbackName, bundleIdentifier ?? "unknown.app")
    }

    private func normalizedVoiceUsageContent(_ raw: String?) -> String? {
        guard var text = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
            return nil
        }
        text = text.replacingOccurrences(of: "\n", with: " ")
        if text.count > 280 {
            text = String(text.prefix(280)) + "…"
        }
        return text
    }

    private func shortcutPanelActionTitle(_ base: String) -> String {
        AppLocalization.isChinese ? "快捷面板 · \(base)" : "Shortcut Panel · \(base)"
    }

    private func voiceIntentActionTitle(_ intent: VoiceIntent) -> String {
        switch intent {
        case .clickLeft: return NSLocalizedString("intent.click_left", comment: "")
        case .clickRight: return NSLocalizedString("intent.click_right", comment: "")
        case .doubleClick: return NSLocalizedString("intent.double_click", comment: "")
        case .toggleInputControlMode: return String(localized: "hotkey.toggle_input_control_mode")
        case .toggleTracking: return String(localized: "hotkey.toggle_tracking")
        case .toggleLanguage: return String(localized: "hotkey.toggle_language")
        case .toggleConnectionLock: return String(localized: "hotkey.connection_lock")
        case .toggleShortcutPanel: return String(localized: "hotkey.toggle_shortcut_panel")
        case .mediaPlayPause: return NSLocalizedString("intent.media_play_pause", comment: "")
        case .mediaPrevious: return NSLocalizedString("intent.media_previous", comment: "")
        case .mediaNext: return NSLocalizedString("intent.media_next", comment: "")
        case .showShortcutPanel: return NSLocalizedString("intent.show_shortcut_panel", comment: "")
        case .hideShortcutPanel: return NSLocalizedString("intent.hide_shortcut_panel", comment: "")
        case .startPointer: return NSLocalizedString("intent.start_pointer", comment: "")
        case .stopPointer: return NSLocalizedString("intent.stop_pointer", comment: "")
        case .recenter: return NSLocalizedString("intent.recenter", comment: "")
        case .frontmostAppCommand(let command):
            return "\(command.title) (\(command.shortcut.displayString))"
        case .scroll(_, let dy):
            if dy == 0 { return NSLocalizedString("intent.scroll", comment: "") }
            return dy > 0
                ? NSLocalizedString("intent.scroll_down", comment: "")
                : NSLocalizedString("intent.scroll_up", comment: "")
        case .scrollToWeb(let edge):
            return edge == "top"
                ? NSLocalizedString("intent.scroll_top", comment: "")
                : NSLocalizedString("intent.scroll_bottom", comment: "")
        case .dragStart: return NSLocalizedString("intent.drag_start", comment: "")
        case .dragEnd: return NSLocalizedString("intent.drag_end", comment: "")
        case .undo: return NSLocalizedString("intent.undo", comment: "")
        case .paste: return NSLocalizedString("intent.paste", comment: "")
        case .clearInput: return NSLocalizedString("intent.clear_input", comment: "")
        case .deleteBackward(let count):
            return AppLocalization.isChinese ? "删除\(count)个字" : "Delete \(count) chars"
        case .lockConnection: return NSLocalizedString("intent.lock_connection", comment: "")
        case .unlockConnection: return NSLocalizedString("intent.unlock_connection", comment: "")
        case .dictation: return NSLocalizedString("intent.dictation", comment: "")
        case .unknown: return NSLocalizedString("intent.unknown", comment: "")
        }
    }

    func refreshPermissions() { permissions.refresh() }
    func requestAccessibility() { permissions.requestAccessibility() }
    func requestMicrophone() { permissions.requestMicrophone() }
    func requestSpeech() { permissions.requestSpeech() }
    func openAccessibilityPane() { permissions.openAccessibilityPrivacyPane() }
    func openMicrophonePane() { permissions.openMicrophonePrivacyPane() }
    func openSpeechPane() { permissions.openSpeechPrivacyPane() }

    var accessibilityTrusted: Bool { AXIsProcessTrusted() }
    var microphoneAuthorized: Bool { AVCaptureDevice.authorizationStatus(for: .audio) == .authorized }
    var speechAuthorized: Bool { SFSpeechRecognizer.authorizationStatus() == .authorized }

    var microphoneAuthorizationStatus: AVAuthorizationStatus {
        AVCaptureDevice.authorizationStatus(for: .audio)
    }

    var speechAuthorizationStatus: SFSpeechRecognizerAuthorizationStatus {
        SFSpeechRecognizer.authorizationStatus()
    }

    var accessibilityStatusDetail: String {
        let live = AXIsProcessTrusted()
        return live
            ? NSLocalizedString("status.permission.authorized", comment: "")
            : NSLocalizedString("status.permission.unauthorized", comment: "")
    }

    var microphoneStatusDetail: String {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: return NSLocalizedString("status.permission.authorized", comment: "")
        case .denied: return NSLocalizedString("status.permission.denied", comment: "")
        case .restricted: return NSLocalizedString("status.permission.restricted", comment: "")
        case .notDetermined: return NSLocalizedString("status.permission.not_determined", comment: "")
        @unknown default: return NSLocalizedString("status.permission.unknown", comment: "")
        }
    }

    var speechStatusDetail: String {
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized: return NSLocalizedString("status.permission.authorized", comment: "")
        case .denied: return NSLocalizedString("status.permission.denied", comment: "")
        case .restricted: return NSLocalizedString("status.permission.restricted", comment: "")
        case .notDetermined: return NSLocalizedString("status.permission.not_determined", comment: "")
        @unknown default: return NSLocalizedString("status.permission.unknown", comment: "")
        }
    }

    func setAlwaysListeningEnabled(_ enabled: Bool) {
        if enabled {
            if !microphoneAuthorized {
                permissions.requestMicrophone()
                refreshPermissions()
                return
            }
            if !speechAuthorized {
                permissions.requestSpeech()
                refreshPermissions()
                return
            }
        }
        voiceActivationMode = enabled ? .handsFree : .pushToTalk
    }

    func requestAccessibilityGuided() {
        if AXIsProcessTrusted() {
            refreshPermissions()
            return
        }
        // Accessibility already has a native prompt with "Open System Settings".
        // Do not open the pane immediately, otherwise users see two windows at once.
        let didShowSystemPrompt = permissions.requestAccessibility()
        if !didShowSystemPrompt {
            permissions.openAccessibilityPrivacyPane()
        }
        startAccessibilityRecoveryPolling()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            self?.refreshPermissions()
        }
    }

    func requestMicrophoneGuided() {
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        switch status {
        case .authorized:
            refreshPermissions()
        case .notDetermined:
            // Important: do not jump to System Settings immediately.
            // Let the native TCC prompt appear first, otherwise it can be interrupted.
            permissions.requestMicrophone()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
                guard let self else { return }
                self.refreshPermissions()
                if !self.microphoneAuthorized {
                    self.permissions.openMicrophonePrivacyPane()
                }
            }
        case .denied, .restricted:
            // Recovery path for stale/broken TCC rows:
            // reset app microphone decision, then re-request to force macOS prompt and re-create list entry.
            Task { [weak self] in
                _ = await Self.resetTCCAsync(service: "Microphone")
                try? await Task.sleep(for: .milliseconds(200))
                guard let self else { return }
                self.permissions.requestMicrophone()
                try? await Task.sleep(for: .milliseconds(900))
                self.refreshPermissions()
                if !self.microphoneAuthorized {
                    self.permissions.openMicrophonePrivacyPane()
                }
            }
        @unknown default:
            permissions.openMicrophonePrivacyPane()
            refreshPermissions()
        }
    }

    func requestSpeechGuided() {
        let status = SFSpeechRecognizer.authorizationStatus()
        switch status {
        case .authorized:
            refreshPermissions()
        case .notDetermined:
            permissions.requestSpeech()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
                guard let self else { return }
                self.refreshPermissions()
                if !self.speechAuthorized {
                    self.permissions.openSpeechPrivacyPane()
                }
            }
        case .denied, .restricted:
            Task { [weak self] in
                _ = await Self.resetTCCAsync(service: "SpeechRecognition")
                try? await Task.sleep(for: .milliseconds(200))
                guard let self else { return }
                self.permissions.requestSpeech()
                try? await Task.sleep(for: .milliseconds(900))
                self.refreshPermissions()
                if !self.speechAuthorized {
                    self.permissions.openSpeechPrivacyPane()
                }
            }
        @unknown default:
            permissions.openSpeechPrivacyPane()
            refreshPermissions()
        }
    }

    nonisolated private static func resetTCCAsync(service: String) async -> Bool {
        await Task.detached(priority: .userInitiated) {
            resetTCC(service: service)
        }.value
    }

    nonisolated private static func resetTCC(service: String) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
        process.arguments = ["reset", service, "com.7fei.Aether"]
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }

    private func setAlwaysListeningEnabledInternal(_ enabled: Bool) {
        guard !isMutatingAlwaysListening else { return }
        isMutatingAlwaysListening = true
        isAlwaysListeningEnabled = enabled
        isMutatingAlwaysListening = false
    }

    func showMainWindow() {
        NSApp.activate(ignoringOtherApps: true)
        if let window = NSApp.windows.first(where: { $0.identifier?.rawValue.contains("main") == true || $0.title == "Aether" }) {
            window.makeKeyAndOrderFront(nil)
        }
    }
}

@MainActor
final class CurrentAppShortcutPanelManager: ObservableObject {
    static let shared = CurrentAppShortcutPanelManager()

    @Published private(set) var isVisible: Bool = false
    @Published private(set) var shouldFocusSearchField: Bool = true
    weak var appState: AppState?

    private var panel: NSPanel?
    private var globalEventMonitors: [Any] = []

    private init() {
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(handleFrontmostAppChanged),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )
    }

    func show(activateApp: Bool = true, focusSearchField: Bool = true) {
        _ = FrontmostAppCommandCatalog.shared.refresh(force: true)
        ensurePanel()
        updatePanelFrame()
        shouldFocusSearchField = focusSearchField
        panel?.hidesOnDeactivate = activateApp
        panel?.alphaValue = 1.0
        if activateApp {
            NSApp.activate(ignoringOtherApps: true)
            panel?.makeKeyAndOrderFront(nil)
        } else {
            panel?.orderFrontRegardless()
        }
        installDismissMonitorsIfNeeded()
        isVisible = true
    }

    func hide() {
        panel?.orderOut(nil)
        panel?.hidesOnDeactivate = true
        uninstallDismissMonitors()
        shouldFocusSearchField = false
        isVisible = false
    }

    func toggle(activateApp: Bool = true, focusSearchField: Bool = true) {
        isVisible ? hide() : show(activateApp: activateApp, focusSearchField: focusSearchField)
    }

    func hideAndRun(targetPID: pid_t? = nil, action: @escaping @MainActor () -> Void) {
        hide()
        let delay: TimeInterval = targetPID == nil ? 0.04 : 0.12

        if let targetPID, targetPID > 0,
           let app = NSRunningApplication(processIdentifier: targetPID) {
            app.activate(options: [.activateIgnoringOtherApps])
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            action()
        }
    }

    func refreshIfVisible() {
        guard isVisible else { return }
        _ = FrontmostAppCommandCatalog.shared.refresh(force: true)
        updatePanelFrame()
        panel?.contentViewController?.view.needsLayout = true
    }

    @objc private func handleFrontmostAppChanged() {
        guard isVisible else { return }
        guard let front = NSWorkspace.shared.frontmostApplication?.bundleIdentifier else { return }
        if front == Bundle.main.bundleIdentifier { return }
        _ = FrontmostAppCommandCatalog.shared.refresh(force: true)
        updatePanelFrame()
    }

    private func ensurePanel() {
        guard panel == nil else { return }

        let hostingController = FocuslessHostingController(rootView: CurrentAppShortcutPanelView())
        let panel = ShortcutOverlayPanel(
            contentRect: NSRect(x: 0, y: 0, width: 1160, height: 760),
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        panel.hidesOnDeactivate = true
        panel.isMovableByWindowBackground = true
        panel.ignoresMouseEvents = false
        panel.becomesKeyOnlyIfNeeded = false
        panel.contentViewController = hostingController
        self.panel = panel
    }

    private func installDismissMonitorsIfNeeded() {
        guard globalEventMonitors.isEmpty else { return }

        if let mouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown], handler: { [weak self] event in
            guard let self, self.isVisible, let panel else { return }
            let point = NSEvent.mouseLocation
            if !panel.frame.contains(point) {
                DispatchQueue.main.async { self.hide() }
            }
        }) {
            globalEventMonitors.append(mouseMonitor)
        }

        if let keyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown, handler: { [weak self] event in
            guard let self, self.isVisible else { return }
            if event.keyCode == UInt16(kVK_Escape) {
                DispatchQueue.main.async { self.hide() }
            }
        }) {
            globalEventMonitors.append(keyMonitor)
        }
    }

    private func uninstallDismissMonitors() {
        for monitor in globalEventMonitors {
            NSEvent.removeMonitor(monitor)
        }
        globalEventMonitors.removeAll()
    }

    private func updatePanelFrame() {
        guard let panel else { return }
        let screen = activeScreen()
        let visibleFrame = screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let preferredSize = preferredPanelSize(in: visibleFrame)
        let width = min(preferredSize.width, visibleFrame.width - 40)
        let height = min(preferredSize.height, visibleFrame.height - 40)
        let origin = CGPoint(
            x: visibleFrame.midX - width / 2,
            y: visibleFrame.midY - height / 2
        )
        panel.setFrame(NSRect(origin: origin, size: CGSize(width: width, height: height)), display: true)
    }

    private func preferredPanelSize(in visibleFrame: NSRect) -> CGSize {
        let visibleGlobalShortcutCount = (appState?.voiceActivationMode == .pushToTalk)
            ? HotkeyAction.allCases.filter { $0 != .connectionLock }.count
            : HotkeyAction.allCases.filter { $0 != .pushToTalk && $0 != .connectionLock }.count
        let globalSectionHeight = CurrentAppShortcutPanelLayout.estimatedHeight(forGlobalShortcutCount: visibleGlobalShortcutCount)
        let mergedSnapshot = appState?.mergedFrontmostAppCommandSnapshot(FrontmostAppCommandCatalog.shared.snapshot)
        guard let snapshot = mergedSnapshot, !snapshot.commands.isEmpty else {
            let width = min(max(visibleFrame.width * 0.54, 820), 980)
            let height = min(max(globalSectionHeight + 240, 460), visibleFrame.height - 40)
            return CGSize(width: width, height: height)
        }

        let sections = CurrentAppShortcutPanelLayout.makeSections(from: snapshot)
        let totalAppCommandCount = sections.reduce(0) { $0 + $1.commands.count }
        let columnCount = CurrentAppShortcutPanelLayout.preferredColumnCount(for: sections)
        let cardWidth: CGFloat = 340
        let gridSpacing: CGFloat = 18
        let outerPadding: CGFloat = 52
        let headerHeight: CGFloat = 96
        let groupHeaderHeight: CGFloat = 54
        let footerBreathingRoom: CGFloat = 28

        let width = max(
            columnCount == 1 ? 680 : 760,
            CGFloat(columnCount) * cardWidth + CGFloat(max(columnCount - 1, 0)) * gridSpacing + outerPadding
        )

        let appContentHeight = CurrentAppShortcutPanelLayout.estimatedColumnHeight(
            for: sections,
            columnCount: columnCount,
            spacing: gridSpacing
        )
        let contentHeight =
            groupHeaderHeight + globalSectionHeight +
            gridSpacing +
            groupHeaderHeight + appContentHeight
        let minimumHeight: CGFloat
        if totalAppCommandCount <= 4 {
            minimumHeight = 360
        } else if totalAppCommandCount <= 8 {
            minimumHeight = 400
        } else if totalAppCommandCount <= 14 {
            minimumHeight = 450
        } else {
            minimumHeight = 520
        }

        let height = max(minimumHeight, headerHeight + contentHeight + outerPadding + footerBreathingRoom)
        return CGSize(width: width, height: height)
    }

    private func activeScreen() -> NSScreen? {
        let mouseLocation = NSEvent.mouseLocation
        return NSScreen.screens.first(where: { $0.frame.contains(mouseLocation) })
    }
}

private final class ShortcutOverlayPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

private final class FocuslessHostingView<Content: View>: NSHostingView<Content> {
    override var focusRingType: NSFocusRingType {
        get { .none }
        set { /* ignore */ }
    }
    override var focusRingMaskBounds: NSRect { .zero }
    override func drawFocusRingMask() {}
}

private final class FocuslessHostingController<Content: View>: NSHostingController<Content> {
    override func loadView() {
        view = FocuslessHostingView(rootView: rootView)
    }
}

private struct CurrentAppShortcutPanelSection: Identifiable {
    let title: String
    let commands: [FrontmostAppCommand]

    var id: String { title }
}

private struct AetherGlobalShortcutPanelEntry: Identifiable {
    let action: HotkeyAction
    let binding: HotkeyBinding

    var id: String { action.rawValue }
}

private enum CurrentAppShortcutPanelLayout {
    static func makeSections(from snapshot: FrontmostAppCommandSnapshot) -> [CurrentAppShortcutPanelSection] {
        var ordered: [String] = []
        var grouped: [String: [FrontmostAppCommand]] = [:]

        for command in snapshot.commands {
            let title = command.menuPath.first ?? snapshot.appName
            if grouped[title] == nil {
                ordered.append(title)
                grouped[title] = []
            }
            grouped[title, default: []].append(command)
        }

        let prioritizedTitles = ordered.enumerated()
            .sorted { lhs, rhs in
                let lhsPriority = sectionPriority(for: lhs.element, appName: snapshot.appName)
                let rhsPriority = sectionPriority(for: rhs.element, appName: snapshot.appName)
                if lhsPriority != rhsPriority { return lhsPriority < rhsPriority }
                return lhs.offset < rhs.offset
            }
            .map(\.element)

        return prioritizedTitles.map { title in
            let commands = (grouped[title] ?? []).enumerated()
                .sorted { lhs, rhs in
                    let lhsPriority = commandPriority(for: lhs.element)
                    let rhsPriority = commandPriority(for: rhs.element)
                    if lhsPriority != rhsPriority { return lhsPriority < rhsPriority }

                    let lhsDepth = lhs.element.menuPath.count
                    let rhsDepth = rhs.element.menuPath.count
                    if lhsDepth != rhsDepth { return lhsDepth < rhsDepth }

                    return lhs.offset < rhs.offset
                }
                .map(\.element)
            return CurrentAppShortcutPanelSection(title: title, commands: commands)
        }
    }

    static func preferredColumnCount(for sections: [CurrentAppShortcutPanelSection]) -> Int {
        let sectionCount = sections.count
        let totalCommands = sections.reduce(0) { $0 + $1.commands.count }
        if sectionCount <= 1 { return 1 }
        if totalCommands <= 10 { return 1 }
        if sectionCount == 2 && totalCommands <= 14 { return 1 }
        return max(1, min(sectionCount, 2))
    }

    static func estimatedHeight(for section: CurrentAppShortcutPanelSection) -> CGFloat {
        let visibleCommands = min(max(section.commands.count, 1), 10)
        return 76 + CGFloat(visibleCommands) * 42
    }

    static func estimatedHeight(forGlobalShortcutCount count: Int) -> CGFloat {
        let visibleCommands = min(max(count, 1), 8)
        return 88 + CGFloat(visibleCommands) * 44
    }

    static func resolvedHeight(
        for section: CurrentAppShortcutPanelSection,
        measurements: [String: CGFloat]
    ) -> CGFloat {
        measurements[section.id] ?? estimatedHeight(for: section)
    }

    static func makeColumns(
        from sections: [CurrentAppShortcutPanelSection],
        columnCount: Int,
        spacing: CGFloat,
        measurements: [String: CGFloat] = [:]
    ) -> [[CurrentAppShortcutPanelSection]] {
        guard columnCount > 1, !sections.isEmpty else {
            return sections.isEmpty ? [] : [sections]
        }

        var columns = Array(repeating: [CurrentAppShortcutPanelSection](), count: columnCount)
        var heights = Array(repeating: CGFloat(0), count: columnCount)

        for section in sections {
            let resolved = resolvedHeight(for: section, measurements: measurements)
            let targetColumn = heights.enumerated()
                .min { lhs, rhs in
                    if lhs.element == rhs.element { return lhs.offset < rhs.offset }
                    return lhs.element < rhs.element
                }?
                .offset ?? 0

            let spacingHeight = columns[targetColumn].isEmpty ? CGFloat(0) : spacing
            columns[targetColumn].append(section)
            heights[targetColumn] += spacingHeight + resolved
        }

        return columns.filter { !$0.isEmpty }
    }

    static func estimatedColumnHeight(
        for sections: [CurrentAppShortcutPanelSection],
        columnCount: Int,
        spacing: CGFloat
    ) -> CGFloat {
        makeColumns(from: sections, columnCount: columnCount, spacing: spacing)
            .map { column in
                column.enumerated().reduce(CGFloat(0)) { partial, pair in
                    let spacingHeight = pair.offset == 0 ? CGFloat(0) : spacing
                    return partial + spacingHeight + estimatedHeight(for: pair.element)
                }
            }
            .max() ?? 0
    }

    private static func sectionPriority(for title: String, appName: String) -> Int {
        let normalized = title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let normalizedAppName = appName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        if normalized == normalizedAppName { return 900 }

        switch normalized {
        case "file", "文件":
            return 100
        case "tab", "标签", "标签页":
            return 105
        case "edit", "编辑":
            return 110
        case "selection", "选择":
            return 120
        case "view", "视图":
            return 130
        case "history", "历史记录", "历史":
            return 135
        case "bookmarks", "书签":
            return 138
        case "go", "navigate", "跳转", "导航":
            return 140
        case "run", "运行":
            return 150
        case "source control", "git", "源代码管理", "源码管理", "版本控制":
            return 155
        case "tools", "工具":
            return 160
        case "window", "窗口":
            return 170
        case "terminal", "终端":
            return 180
        case "help", "帮助":
            return 950
        default:
            return 500
        }
    }

    private static func commandPriority(for command: FrontmostAppCommand) -> Int {
        let normalizedTitle = command.title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let normalizedPath = command.menuPath.joined(separator: " ").lowercased()
        let haystack = "\(normalizedPath) \(normalizedTitle)"

        if matchesAny(in: haystack, terms: ["command palette", "命令面板", "show commands", "find action", "执行动作"]) {
            return 100
        }
        if matchesAny(in: haystack, terms: ["quick open", "快速打开", "open file", "打开文件", "go to file", "文件"]) {
            return 110
        }
        if matchesAny(in: haystack, terms: ["search", "find", "查找", "搜索"]) {
            return 120
        }
        if matchesAny(in: haystack, terms: ["new tab", "新建标签", "next tab", "previous tab", "close tab", "标签"]) {
            return 130
        }
        if matchesAny(in: haystack, terms: ["reload", "refresh", "刷新"]) {
            return 140
        }
        if matchesAny(in: haystack, terms: ["new window", "close window", "窗口"]) {
            return 150
        }
        if matchesAny(in: haystack, terms: ["new ", "open ", "新建", "打开"]) {
            return 160
        }
        if matchesAny(in: haystack, terms: ["save", "保存"]) {
            return 170
        }
        if matchesAny(in: haystack, terms: ["undo", "redo", "撤销", "重做", "copy", "paste", "剪切", "复制", "粘贴"]) {
            return 180
        }
        if matchesAny(in: haystack, terms: ["split", "terminal", "run", "debug", "运行", "调试", "终端"]) {
            return 190
        }
        if command.shortcut.displayString.isEmpty {
            return 400
        }
        return 250
    }

    private static func matchesAny(in value: String, terms: [String]) -> Bool {
        terms.contains { value.contains($0) }
    }
}

private struct CurrentAppShortcutPanelView: View {
    @StateObject private var catalog = FrontmostAppCommandCatalog.shared
    @StateObject private var hotkeyManager = HotkeyManager.shared
    @StateObject private var panelManager = CurrentAppShortcutPanelManager.shared
    @Environment(\.colorScheme) private var colorScheme
    @FocusState private var isSearchFieldFocused: Bool
    @State private var isPanelFocused: Bool = true
    @State private var blurWorkItem: DispatchWorkItem?
    @State private var searchText: String = ""
    @State private var measuredSectionHeights: [String: CGFloat] = [:]

    private var snapshot: FrontmostAppCommandSnapshot? {
        panelManager.appState?.mergedFrontmostAppCommandSnapshot(catalog.snapshot)
    }

    private var sections: [CurrentAppShortcutPanelSection] {
        guard let snapshot else { return [] }
        return CurrentAppShortcutPanelLayout.makeSections(from: snapshot)
    }

    private var globalShortcuts: [AetherGlobalShortcutPanelEntry] {
        let preferredOrder: [HotkeyAction] = [
            .toggleInputControlMode,
            .pushToTalk,
            .toggleTracking,
            .toggleLanguage,
            .toggleShortcutPanel
        ]

        return preferredOrder.filter {
            $0 != .pushToTalk || CurrentAppShortcutPanelManager.shared.appState?.voiceActivationMode == .pushToTalk
        }.map {
            AetherGlobalShortcutPanelEntry(action: $0, binding: hotkeyManager.binding(for: $0))
        }
    }

    private var appIcon: NSImage? {
        guard let snapshot else { return nil }
        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: snapshot.bundleIdentifier) else { return nil }
        return NSWorkspace.shared.icon(forFile: appURL.path)
    }

    private var isChinese: Bool {
        AppLocalization.isChinese
    }

    private var normalizedSearchText: String {
        normalizeSearchText(searchText)
    }

    private var filteredSections: [CurrentAppShortcutPanelSection] {
        guard !normalizedSearchText.isEmpty else { return sections }
        return sections.compactMap { section in
            let commands = section.commands.filter(matchesSearch)
            guard !commands.isEmpty else { return nil }
            return CurrentAppShortcutPanelSection(title: section.title, commands: commands)
        }
    }

    private var filteredGlobalShortcuts: [AetherGlobalShortcutPanelEntry] {
        guard !normalizedSearchText.isEmpty else { return globalShortcuts }
        return globalShortcuts.filter(matchesSearch)
    }

    private var filteredAppShortcutCount: Int {
        filteredSections.reduce(0) { $0 + $1.commands.count }
    }

    private var totalVisibleShortcutCount: Int {
        filteredAppShortcutCount + filteredGlobalShortcuts.count
    }

    private var sectionColumnCount: Int {
        CurrentAppShortcutPanelLayout.preferredColumnCount(for: filteredSections)
    }

    private var sectionColumns: [[CurrentAppShortcutPanelSection]] {
        CurrentAppShortcutPanelLayout.makeColumns(
            from: filteredSections,
            columnCount: sectionColumnCount,
            spacing: 18,
            measurements: measuredSectionHeights
        )
    }

    private var panelGradient: LinearGradient {
        let top = Color(nsColor: colorScheme == .dark ? .windowBackgroundColor : .controlBackgroundColor)
        let bottom = Color(nsColor: .windowBackgroundColor)
        let topOpacity = isPanelFocused ? 0.98 : 0.86
        let bottomOpacity = isPanelFocused ? 0.96 : 0.82
        return LinearGradient(colors: [top.opacity(topOpacity), bottom.opacity(bottomOpacity)], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    private var panelStroke: Color {
        Color.primary.opacity(colorScheme == .dark ? 0.12 : 0.06)
    }

    private var chromeBackground: Color {
        let base = colorScheme == .dark ? 0.12 : 0.04
        return Color.primary.opacity(isPanelFocused ? base : base * 1.35)
    }

    private var cardBackground: Color {
        let focusedOpacity = colorScheme == .dark ? 0.84 : 0.9
        let blurredOpacity = colorScheme == .dark ? 0.7 : 0.76
        return Color(nsColor: colorScheme == .dark ? .controlBackgroundColor : .textBackgroundColor)
            .opacity(isPanelFocused ? focusedOpacity : blurredOpacity)
    }

    private var cardStroke: Color {
        Color.primary.opacity(colorScheme == .dark ? 0.1 : 0.05)
    }

    private var emptyStateBackground: Color {
        Color(nsColor: colorScheme == .dark ? .underPageBackgroundColor : .controlBackgroundColor).opacity(colorScheme == .dark ? 0.75 : 0.78)
    }

    var body: some View {
        ZStack {
            VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)

            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(panelGradient)
                .overlay(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .stroke(panelStroke, lineWidth: 1)
                )
                .shadow(color: .black.opacity(isPanelFocused ? 0.12 : 0.08), radius: isPanelFocused ? 28 : 18, y: isPanelFocused ? 18 : 10)

            VStack(alignment: .leading, spacing: 20) {
                header

                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        panelGroupHeader(
                            title: snapshot?.appName ?? (isChinese ? "当前 App" : "Current App"),
                            detail: isChinese
                                ? "下面是前台应用的菜单快捷键和常见默认快捷键。"
                                : "Below are the frontmost app's menu shortcuts plus common defaults.",
                            count: filteredAppShortcutCount
                        )

                        if !AXIsProcessTrusted() && (snapshot?.commands.isEmpty ?? true) {
                            emptyState(
                                title: isChinese ? "需要辅助功能权限" : "Accessibility Permission Required",
                                detail: isChinese
                                    ? "开启辅助功能后，Aether 才能读取当前 App 的菜单和快捷键。"
                                    : "Aether needs Accessibility permission to read the current app's menus and shortcuts."
                            )
                        } else if let snapshot, !snapshot.commands.isEmpty, !filteredSections.isEmpty {
                            HStack(alignment: .top, spacing: 18) {
                                ForEach(Array(sectionColumns.enumerated()), id: \.offset) { _, column in
                                    VStack(alignment: .leading, spacing: 18) {
                                        ForEach(column) { section in
                                            CurrentAppShortcutSectionCard(
                                                section: section,
                                                onTrigger: triggerCurrentAppShortcut
                                            )
                                        }
                                    }
                                    .frame(maxWidth: .infinity, alignment: .top)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        } else if !normalizedSearchText.isEmpty {
                            emptyState(
                                title: isChinese ? "没有匹配的快捷键" : "No Matching Shortcuts",
                                detail: isChinese
                                    ? "换个关键词试试，可以搜菜单名、功能名、别名或组合键。"
                                    : "Try another keyword. Search matches titles, menu paths, aliases, and shortcut keys."
                            )
                        } else {
                            emptyState(
                                title: isChinese ? "当前 App 暂无可读快捷键" : "No Readable Shortcuts Yet",
                                detail: isChinese
                                    ? "切到目标应用后再试一次，或者手动展开该应用的菜单栏。"
                                    : "Switch back to the target app and try again, or manually open that app's menu bar once."
                            )
                        }

                        panelGroupHeader(
                            title: isChinese ? "Aether 全局" : "Aether Global",
                            detail: isChinese
                                ? "这些是 Aether 自己的全局热键，不依赖当前 App。"
                                : "These are Aether's own global shortcuts and do not depend on the frontmost app.",
                            count: filteredGlobalShortcuts.count
                        )

                        AetherGlobalShortcutSectionCard(entries: filteredGlobalShortcuts, onTrigger: triggerGlobalShortcut)
                    }
                    .padding(.bottom, 4)
                }
                .scrollIndicators(.hidden)
                .focusable(false)
                .background(SuppressEnclosingScrollFocusRing())
            }
            .padding(26)
        }
        .onPreferenceChange(CurrentAppShortcutSectionHeightPreferenceKey.self) { heights in
            guard !heights.isEmpty else { return }
            var next = measuredSectionHeights
            var changed = false
            for (id, height) in heights {
                guard height > 0 else { continue }
                if abs((next[id] ?? 0) - height) > 1 {
                    next[id] = height
                    changed = true
                }
            }
            if changed {
                measuredSectionHeights = next
            }
        }
        .opacity(isPanelFocused ? 1.0 : 0.9)
        .onAppear {
            updateSearchFieldFocus(shouldFocus: panelManager.shouldFocusSearchField)
        }
        .onChange(of: panelManager.shouldFocusSearchField) { _, shouldFocus in
            updateSearchFieldFocus(shouldFocus: shouldFocus)
        }
        .onHover { isHovering in
            if isHovering {
                blurWorkItem?.cancel()
                blurWorkItem = nil
                withAnimation(.easeOut(duration: 0.16)) {
                    isPanelFocused = true
                }
                return
            }

            let work = DispatchWorkItem {
                withAnimation(.easeInOut(duration: 0.22)) {
                    isPanelFocused = false
                }
            }
            blurWorkItem?.cancel()
            blurWorkItem = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.55, execute: work)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 14) {
                Group {
                    if let appIcon {
                        Image(nsImage: appIcon)
                            .resizable()
                            .scaledToFit()
                    } else {
                        Image(systemName: "command.square.fill")
                            .resizable()
                            .scaledToFit()
                            .padding(8)
                            .foregroundColor(.accentColor)
                    }
                }
                .frame(width: 42, height: 42)
                .background(chromeBackground)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    Text(snapshot?.appName ?? (isChinese ? "当前应用快捷键" : "Current App Shortcuts"))
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                    Text(
                        isChinese
                            ? "按顶层菜单分组展示可触发快捷键，并补充常见默认快捷键和你的自定义 App 规则。语音命中或直接点击条目，都会发送对应组合键。"
                            : "Shortcut commands grouped by top-level menu, with common defaults and your custom app rules merged in. Voice matches and direct clicks both send the corresponding key combo."
                    )
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack(alignment: .center, spacing: 12) {
                let countStr = String.localizedStringWithFormat(NSLocalizedString("panels.shortcuts.count_fmt", comment: ""), totalVisibleShortcutCount)
                Text(countStr)
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.accentColor.opacity(0.12))
                    .foregroundColor(.accentColor)
                    .clipShape(Capsule())

                Text(LocalizedStringKey("panels.shortcuts.clickable_hint"))
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(chromeBackground)
                    .foregroundColor(.secondary)
                    .clipShape(Capsule())

                Spacer(minLength: 12)

                ZStack(alignment: .trailing) {
                    NoFocusRingTextField(
                        placeholder: isChinese ? "搜索快捷键" : "Search shortcuts",
                        text: $searchText,
                        isFocused: Binding(
                            get: { isSearchFieldFocused },
                            set: { isSearchFieldFocused = $0 }
                        ),
                        font: .systemFont(ofSize: 13, weight: .regular)
                    )
                    .focusEffectDisabled()
                    .padding(.trailing, searchText.isEmpty ? 0 : 26)

                    if !searchText.isEmpty {
                        Button {
                            searchText = ""
                            isSearchFieldFocused = true
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary.opacity(0.7))
                                .font(.system(size: 14, weight: .semibold))
                                .frame(width: 22, height: 22)
                        }
                        .buttonStyle(.plain)
                        .padding(.trailing, 8)
                    }
                }
                .frame(width: 240)
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(chromeBackground)
                }

                Button(String(localized: "generic.refresh")) {
                    _ = FrontmostAppCommandCatalog.shared.refresh(force: true)
                }
                .buttonStyle(.bordered)

                Button {
                    CurrentAppShortcutPanelManager.shared.hide()
                } label: {
                    Image(systemName: "xmark")
                        .font(.headline.weight(.semibold))
                        .frame(width: 30, height: 30)
                }
                .buttonStyle(.borderless)
                .background(chromeBackground)
                .clipShape(Circle())
            }
        }
    }

    private func emptyState(title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.title3.weight(.semibold))
            Text(detail)
                .font(.body)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(24)
        .background(emptyStateBackground)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func panelGroupHeader(title: String, detail: String, count: Int) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                if isPanelFocused {
                    Text(detail)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }

            Spacer(minLength: 12)

            Text("\(count)")
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(chromeBackground)
                .clipShape(Capsule())
        }
    }

    private func matchesSearch(_ command: FrontmostAppCommand) -> Bool {
        let needle = normalizedSearchText
        guard !needle.isEmpty else { return true }
        let haystacks = [
            command.title,
            command.displayPath,
            command.shortcut.displayString,
            command.aliases.joined(separator: " "),
            command.title.pinyin,
            command.displayPath.pinyin,
            command.aliases.joined(separator: " ").pinyin
        ]
        return haystacks.contains { normalizeSearchText($0).contains(needle) }
    }

    private func matchesSearch(_ entry: AetherGlobalShortcutPanelEntry) -> Bool {
        let needle = normalizedSearchText
        guard !needle.isEmpty else { return true }
        let haystacks = [
            entry.action.label,
            entry.action.helperText,
            entry.binding.displayString
        ]
        return haystacks.contains { normalizeSearchText($0).contains(needle) }
    }

    private func normalizeSearchText(_ raw: String) -> String {
        raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .components(separatedBy: .whitespacesAndNewlines)
            .joined()
    }

    private func triggerCurrentAppShortcut(_ command: FrontmostAppCommand) {
        CurrentAppShortcutPanelManager.shared.appState?.recordShortcutPanelCurrentAppShortcut(command)
        CurrentAppShortcutPanelManager.shared.hideAndRun(targetPID: command.processIdentifier) {
            AutomationOutputs.shared.pressShortcut(command.shortcut, targetPID: command.processIdentifier)
        }
    }

    private func triggerGlobalShortcut(_ entry: AetherGlobalShortcutPanelEntry) {
        CurrentAppShortcutPanelManager.shared.appState?.recordShortcutPanelGlobalShortcut(entry.action)
        if entry.action == .toggleShortcutPanel {
            CurrentAppShortcutPanelManager.shared.hide()
            return
        }

        CurrentAppShortcutPanelManager.shared.hideAndRun {
            switch entry.action {
            case .toggleTracking:
                let manager = HeadMotionManager.shared
                manager.isTracking ? manager.stopTracking() : manager.startTracking()
            case .connectionLock:
                ConnectionLockService.shared.toggle()
            case .toggleInputControlMode:
                HeadMotionManager.shared.toggleRecognitionInputControlMode(source: "shortcut-panel", persist: false)
            case .toggleLanguage:
                let appState = CurrentAppShortcutPanelManager.shared.appState
                guard appState?.isVoiceInputEnabled == true || appState?.isVoiceControlEnabled == true else { return }
                NotificationCenter.default.post(name: Notification.Name("AetherToggleLanguage"), object: nil)
            case .toggleShortcutPanel:
                break
            case .pushToTalk:
                HUDManager.shared.showTemporary(
                    message: isChinese ? "按住说话请继续使用快捷键" : "Use the hold-to-talk hotkey",
                    recognitionControlMode: .auto,
                )
            }
        }
    }

    private func updateSearchFieldFocus(shouldFocus: Bool) {
        guard shouldFocus else {
            isSearchFieldFocused = false
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            isSearchFieldFocused = true
        }
    }
}

private struct CurrentAppShortcutSectionCard: View {
    let section: CurrentAppShortcutPanelSection
    let onTrigger: (FrontmostAppCommand) -> Void
    @Environment(\.colorScheme) private var colorScheme

    private var cardBackground: Color {
        Color(nsColor: colorScheme == .dark ? .controlBackgroundColor : .textBackgroundColor).opacity(colorScheme == .dark ? 0.84 : 0.9)
    }

    private var cardStroke: Color {
        Color.primary.opacity(colorScheme == .dark ? 0.1 : 0.05)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(section.title)
                .font(.system(size: 18, weight: .bold, design: .rounded))

            VStack(alignment: .leading, spacing: 10) {
                ForEach(section.commands) { command in
                    CurrentAppShortcutRow(command: command, onTrigger: onTrigger)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(18)
        .background(cardBackground)
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(cardStroke, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .background(
            GeometryReader { proxy in
                Color.clear.preference(
                    key: CurrentAppShortcutSectionHeightPreferenceKey.self,
                    value: [section.id: proxy.size.height]
                )
            }
        )
    }
}

private struct CurrentAppShortcutSectionHeightPreferenceKey: PreferenceKey {
    static var defaultValue: [String: CGFloat] = [:]

    static func reduce(value: inout [String: CGFloat], nextValue: () -> [String: CGFloat]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

private struct AetherGlobalShortcutSectionCard: View {
    let entries: [AetherGlobalShortcutPanelEntry]
    let onTrigger: (AetherGlobalShortcutPanelEntry) -> Void
    @Environment(\.colorScheme) private var colorScheme

    private var cardBackground: Color {
        Color(nsColor: colorScheme == .dark ? .controlBackgroundColor : .textBackgroundColor).opacity(colorScheme == .dark ? 0.84 : 0.9)
    }

    private var cardStroke: Color {
        Color.primary.opacity(colorScheme == .dark ? 0.1 : 0.05)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(entries) { entry in
                AetherGlobalShortcutRow(entry: entry, onTrigger: onTrigger)
                if entry.id != entries.last?.id {
                    Divider()
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(18)
        .background(cardBackground)
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(cardStroke, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

private struct AetherGlobalShortcutRow: View {
    let entry: AetherGlobalShortcutPanelEntry
    let onTrigger: (AetherGlobalShortcutPanelEntry) -> Void

    var body: some View {
        Button {
            onTrigger(entry)
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(entry.action.label)
                        .font(.body.weight(.semibold))
                        .foregroundColor(.primary)
                    Text(entry.action.helperText)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer(minLength: 12)

                Text(entry.binding.displayString)
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    .foregroundColor(.accentColor)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.accentColor.opacity(0.1))
                    .clipShape(Capsule())
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.vertical, 2)
    }
}

private struct CurrentAppShortcutRow: View {
    let command: FrontmostAppCommand
    let onTrigger: (FrontmostAppCommand) -> Void

    private var submenuPath: String {
        guard command.menuPath.count > 1 else { return "" }
        return command.menuPath.dropFirst().joined(separator: " > ")
    }

    var body: some View {
        Button {
            onTrigger(command)
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(command.title)
                        .font(.body.weight(.semibold))
                        .foregroundColor(.primary)
                    if !submenuPath.isEmpty {
                        Text(submenuPath)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Spacer(minLength: 12)

                Text(command.shortcut.displayString)
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    .foregroundColor(.accentColor)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.accentColor.opacity(0.1))
                    .clipShape(Capsule())
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.vertical, 2)
    }
}

class AetherAppDelegate: NSObject, NSApplicationDelegate {
    private func isRunningFromReadOnlyDiskImage() -> Bool {
        let bundleURL = Bundle.main.bundleURL
        let keys: Set<URLResourceKey> = [
            .volumeIsReadOnlyKey,
            .volumeLocalizedFormatDescriptionKey
        ]
        guard let values = try? bundleURL.resourceValues(forKeys: keys) else { return false }
        guard values.volumeIsReadOnly == true else { return false }

        // Disk image volumes are read-only by default and report "Disk Image" format.
        let format = (values.volumeLocalizedFormatDescription ?? "").lowercased()
        if format.contains("disk image") || format.contains("dmg") || format.contains("磁盘映像") {
            return true
        }
        // Conservative fallback for localized format strings we don't recognize.
        return bundleURL.path.hasPrefix("/Volumes/")
    }

    private func enforceApplicationsInstallPathIfNeeded() {
        guard isRunningFromReadOnlyDiskImage() else { return }

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "请先安装到 Applications 再运行"
        alert.informativeText = "你正在从磁盘镜像运行 Aether。为避免辅助功能权限每次重置，请先拖到 Applications 后再打开。"
        alert.addButton(withTitle: "打开 Applications")
        alert.addButton(withTitle: "退出")
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            NSWorkspace.shared.open(URL(fileURLWithPath: "/Applications", isDirectory: true))
        }
        NSApp.terminate(nil)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Menu-bar-first app: keep Dock hidden by default.
        NSApp.setActivationPolicy(.accessory)
        enforceApplicationsInstallPathIfNeeded()
    }
}

@main
struct AetherApp: App {
    @NSApplicationDelegateAdaptor(AetherAppDelegate.self) var appDelegate
    @StateObject private var appState = AppState()
    
    var body: some Scene {
        Window("Aether", id: "main") {
            AetherMainView()
                .environmentObject(appState)
                .environment(\.locale, appState.appLocale)
        }
        .defaultSize(width: 1120, height: 760)
        .commands {
            SidebarCommands() // Enable View -> Show/Hide Sidebar
        }
        
        AetherMenuBar()
            .environmentObject(appState)
            .environment(\.locale, appState.appLocale)
    }
}

// MARK: - Notification Names
extension Notification.Name {
    static let toggleConnectionLock = Notification.Name("AetherToggleConnectionLock")
    static let toggleShortcutPanel = Notification.Name("AetherToggleShortcutPanel")
}
