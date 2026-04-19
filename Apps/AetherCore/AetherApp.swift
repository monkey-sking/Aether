import SwiftUI
import Combine
import AVFoundation
import Speech
import Carbon
import UniformTypeIdentifiers
import IOKit.hidsystem
import Security

enum AetherBuildVersionFormatter {
    enum DisplayChannel {
        case stable
        case beta
    }

    static let publicVersionLabelElementName = "aether:publicVersionLabel"
    static let publicVersionLabelLocalName = "publicVersionLabel"
    static let publicVersionLabelNamespace = "https://aether.7caifei.com/xml-namespaces/aether"

    private static func normalized(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    static func fileLabel(from buildVersion: String) -> String {
        let digits = buildVersion.filter(\.isNumber)
        let characters = Array(digits)
        switch characters.count {
        case 14:
            return "\(String(characters[4..<8]))-\(String(characters[8..<14]))"
        case 12:
            return "\(String(characters[2..<6]))-\(String(characters[6..<12]))"
        default:
            return buildVersion
        }
    }

    static func matchesPublicVersionLabelName(_ name: String?) -> Bool {
        guard let name = normalized(name) else { return false }
        return name == publicVersionLabelElementName
            || name == publicVersionLabelLocalName
            || name.hasSuffix(":\(publicVersionLabelLocalName)")
    }

    static func explicitPublicLabel(from propertiesDictionary: [AnyHashable: Any]?) -> String? {
        guard let propertiesDictionary else { return nil }

        if let explicitLabel = normalized(propertiesDictionary[publicVersionLabelElementName] as? String) {
            return explicitLabel
        }

        if let explicitLabel = normalized(propertiesDictionary[publicVersionLabelLocalName] as? String) {
            return explicitLabel
        }

        for (key, value) in propertiesDictionary {
            guard matchesPublicVersionLabelName(String(describing: key)),
                  let explicitLabel = normalized(value as? String) else {
                continue
            }
            return explicitLabel
        }

        return nil
    }

    static func publicLabel(
        from downloadURL: String?,
        propertiesDictionary: [AnyHashable: Any]? = nil
    ) -> String? {
        if let explicitLabel = explicitPublicLabel(from: propertiesDictionary) {
            return explicitLabel
        }

        guard let downloadURL = normalized(downloadURL) else { return nil }
        let fileName = URL(string: downloadURL)?.lastPathComponent ?? (downloadURL as NSString).lastPathComponent
        guard fileName.hasSuffix(".zip") else { return nil }
        let stem = String(fileName.dropLast(4))
        guard let candidate = stem.split(separator: "_").last else { return nil }
        let label = String(candidate)
        guard let prefix = label.first, (prefix == "b" || prefix == "B"), label.dropFirst().allSatisfy(\.isNumber) else { return nil }
        return label
    }

    static func displayLabel(from buildVersion: String, includeSeconds: Bool = false) -> String {
        let digits = buildVersion.filter(\.isNumber)
        let characters = Array(digits)
        switch characters.count {
        case 14:
            let time = includeSeconds
                ? "\(String(characters[8..<10])):\(String(characters[10..<12])):\(String(characters[12..<14]))"
                : "\(String(characters[8..<10])):\(String(characters[10..<12]))"
            return "\(String(characters[4..<6]))-\(String(characters[6..<8])) \(time)"
        case 12:
            let time = includeSeconds
                ? "\(String(characters[6..<8])):\(String(characters[8..<10])):\(String(characters[10..<12]))"
                : "\(String(characters[6..<8])):\(String(characters[8..<10]))"
            return "\(String(characters[2..<4]))-\(String(characters[4..<6])) \(time)"
        default:
            return buildVersion
        }
    }

    static func detailLabel(buildVersion: String?, publicLabel: String? = nil, includeSeconds: Bool = false) -> String? {
        if let publicLabel = normalized(publicLabel) {
            return publicLabel
        }
        guard let buildVersion = normalized(buildVersion) else { return nil }
        return displayLabel(from: buildVersion, includeSeconds: includeSeconds)
    }

    private static func joinedVersion(shortVersion: String?, detail: String?) -> String? {
        if let shortVersion = normalized(shortVersion) {
            guard let detail = normalized(detail) else { return shortVersion }
            return "\(shortVersion) · \(detail)"
        }
        return normalized(detail)
    }

    private static func comparisonDetailLabels(
        updateBuildVersion: String?,
        updatePublicLabel: String?,
        bundleBuildVersion: String?,
        bundlePublicLabel: String?
    ) -> (update: String?, bundle: String?) {
        var updateDetail = detailLabel(
            buildVersion: updateBuildVersion,
            publicLabel: updatePublicLabel
        )
        var bundleDetail = detailLabel(
            buildVersion: bundleBuildVersion,
            publicLabel: bundlePublicLabel
        )

        guard updateDetail != nil, bundleDetail != nil else {
            return (updateDetail, bundleDetail)
        }

        if updateDetail == bundleDetail {
            let preciseUpdate = detailLabel(
                buildVersion: updateBuildVersion,
                publicLabel: updatePublicLabel,
                includeSeconds: true
            )
            let preciseBundle = detailLabel(
                buildVersion: bundleBuildVersion,
                publicLabel: bundlePublicLabel,
                includeSeconds: true
            )

            if let preciseUpdate, let preciseBundle, preciseUpdate != preciseBundle {
                updateDetail = preciseUpdate
                bundleDetail = preciseBundle
            } else if let updateBuildVersion = normalized(updateBuildVersion),
                      let bundleBuildVersion = normalized(bundleBuildVersion),
                      updateBuildVersion != bundleBuildVersion {
                updateDetail = updateBuildVersion
                bundleDetail = bundleBuildVersion
            }
        }

        return (updateDetail, bundleDetail)
    }

    static func versionDisplay(shortVersion: String?, buildVersion: String?, publicLabel: String? = nil) -> String? {
        guard normalized(shortVersion) != nil else {
            return detailLabel(buildVersion: buildVersion, publicLabel: publicLabel)
        }
        return joinedVersion(
            shortVersion: shortVersion,
            detail: detailLabel(buildVersion: buildVersion, publicLabel: publicLabel)
        )
    }

    static func versionDisplay(
        shortVersion: String?,
        buildVersion: String?,
        publicLabel: String? = nil,
        channel: DisplayChannel
    ) -> String? {
        switch channel {
        case .stable:
            return versionDisplay(
                shortVersion: shortVersion,
                buildVersion: buildVersion,
                publicLabel: publicLabel
            )
        case .beta:
            return detailLabel(buildVersion: buildVersion, publicLabel: publicLabel)
                ?? versionDisplay(
                    shortVersion: shortVersion,
                    buildVersion: buildVersion,
                    publicLabel: publicLabel
                )
        }
    }

    static func comparisonDisplay(
        updateShortVersion: String?,
        updateBuildVersion: String?,
        updatePublicLabel: String? = nil,
        bundleShortVersion: String?,
        bundleBuildVersion: String?,
        bundlePublicLabel: String? = nil
    ) -> (update: String?, bundle: String?) {
        let updateShortVersion = normalized(updateShortVersion)
        let bundleShortVersion = normalized(bundleShortVersion)

        if updateShortVersion != nil, updateShortVersion == bundleShortVersion {
            let details = comparisonDetailLabels(
                updateBuildVersion: updateBuildVersion,
                updatePublicLabel: updatePublicLabel,
                bundleBuildVersion: bundleBuildVersion,
                bundlePublicLabel: bundlePublicLabel
            )
            if details.update != nil || details.bundle != nil {
                return details
            }
        }

        return (
            versionDisplay(
                shortVersion: updateShortVersion,
                buildVersion: updateBuildVersion,
                publicLabel: updatePublicLabel
            ),
            versionDisplay(
                shortVersion: bundleShortVersion,
                buildVersion: bundleBuildVersion,
                publicLabel: bundlePublicLabel
            )
        )
    }

    static func comparisonDisplay(
        updateShortVersion: String?,
        updateBuildVersion: String?,
        updatePublicLabel: String? = nil,
        bundleShortVersion: String?,
        bundleBuildVersion: String?,
        bundlePublicLabel: String? = nil,
        channel: DisplayChannel
    ) -> (update: String?, bundle: String?) {
        switch channel {
        case .stable:
            return comparisonDisplay(
                updateShortVersion: updateShortVersion,
                updateBuildVersion: updateBuildVersion,
                updatePublicLabel: updatePublicLabel,
                bundleShortVersion: bundleShortVersion,
                bundleBuildVersion: bundleBuildVersion,
                bundlePublicLabel: bundlePublicLabel
            )
        case .beta:
            let details = comparisonDetailLabels(
                updateBuildVersion: updateBuildVersion,
                updatePublicLabel: updatePublicLabel,
                bundleBuildVersion: bundleBuildVersion,
                bundlePublicLabel: bundlePublicLabel
            )
            return (
                details.update
                    ?? detailLabel(buildVersion: updateBuildVersion, publicLabel: updatePublicLabel)
                    ?? versionDisplay(
                        shortVersion: updateShortVersion,
                        buildVersion: updateBuildVersion,
                        publicLabel: updatePublicLabel
                    ),
                details.bundle
                    ?? detailLabel(buildVersion: bundleBuildVersion, publicLabel: bundlePublicLabel)
                    ?? versionDisplay(
                        shortVersion: bundleShortVersion,
                        buildVersion: bundleBuildVersion,
                        publicLabel: bundlePublicLabel
                    )
            )
        }
    }
}

struct AetherAppcastFeedEntry: Equatable {
    var shortVersion: String?
    var buildVersion: String?
    var publicLabel: String?
}

enum AetherAppcastFeedInspector {
    static func firstRelease(from data: Data) -> AetherAppcastFeedEntry? {
        parseEntries(from: data).first
    }

    static func publicLabelsByBuildVersion(from data: Data) -> [String: String] {
        var labels: [String: String] = [:]
        for entry in parseEntries(from: data) {
            guard let buildVersion = entry.buildVersion,
                  let publicLabel = entry.publicLabel else {
                continue
            }
            labels[buildVersion] = publicLabel
        }
        return labels
    }

    static func parseEntries(from data: Data) -> [AetherAppcastFeedEntry] {
        let delegate = AetherAppcastFeedXMLParser()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.parse()
        return delegate.entries
    }
}

private final class AetherAppcastFeedXMLParser: NSObject, XMLParserDelegate {
    private(set) var entries: [AetherAppcastFeedEntry] = []
    private var currentText = ""
    private var currentEntry: AetherAppcastFeedEntry?

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        currentText = ""

        if elementName == "item" {
            currentEntry = AetherAppcastFeedEntry()
        } else if currentEntry != nil,
                  elementName == "enclosure",
                  currentEntry?.publicLabel == nil,
                  let url = attributeDict["url"] {
            currentEntry?.publicLabel = AetherBuildVersionFormatter.publicLabel(from: url)
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        currentText += string
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        guard var entry = currentEntry else { return }

        let resolvedElementName = qName ?? elementName
        let value = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !value.isEmpty {
            if resolvedElementName == "sparkle:shortVersionString", entry.shortVersion == nil {
                entry.shortVersion = value
            } else if resolvedElementName == "sparkle:version", entry.buildVersion == nil {
                entry.buildVersion = value
            } else if (
                AetherBuildVersionFormatter.matchesPublicVersionLabelName(resolvedElementName)
                    || AetherBuildVersionFormatter.matchesPublicVersionLabelName(elementName)
            ), entry.publicLabel == nil {
                entry.publicLabel = value
            }
        }

        if elementName == "item" {
            entries.append(entry)
            currentEntry = nil
        } else {
            currentEntry = entry
        }
    }
}

final class HeadsetRouteState {
    static let shared = HeadsetRouteState()
    private init() {}

    var isConnected: Bool = false
}

enum PermissionSetupStage: Equatable {
    case accessibility
    case microphone
    case speech
    case done
}

enum WakeAnalyticsFollowUpKind: String, Codable {
    case dictation
    case control
}

enum WakeAnalyticsFailureReason: String, Codable {
    case belowThreshold = "below-threshold"
    case phraseNotAtPrefix = "phrase-not-at-prefix"
    case prefixRejected = "prefix-rejected"
    case noPhraseMatch = "no-phrase-match"
}

enum WakeAnalyticsSignal {
    case hit(groupID: String, phrase: String?, localeIdentifier: String)
    case converted(
        groupID: String,
        followUp: WakeAnalyticsFollowUpKind,
        phrase: String?,
        localeIdentifier: String,
        transcript: String?
    )
    case empty(groupID: String, phrase: String?, localeIdentifier: String)
    case miss(
        phase: String,
        reason: WakeAnalyticsFailureReason,
        phrase: String?,
        localeIdentifier: String,
        transcript: String?
    )
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

    func setTrackingExecutionEnabled(_ check: (() -> Bool)?) {
        manager.isTrackingExecutionEnabled = check
    }

    func setTrackingExecutionDeniedHandler(_ handler: (() -> Void)?) {
        manager.onTrackingExecutionDenied = handler
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
    typealias PlaybackLeakState = SpeechManager.PlaybackLeakState

    @Published private(set) var status: String = String(localized: "voice.status.idle")
    @Published private(set) var lastTranscript: String = ""
    @Published private(set) var lastError: String = ""
    @Published private(set) var lastWakeTime: Date?
    @Published private(set) var playbackLeakState: PlaybackLeakState = .none
    
    @Published var isAlwaysListeningEnabled: Bool = false
    @Published var isDirectCommandEnabled: Bool = false
    @Published var isPTTEnabled: Bool = true
    @Published var isWakeWordEnabled: Bool = false
    @Published var isGazeWakeEnabled: Bool = false
    @Published var isAutoPunctuationEnabled: Bool = true
    @Published var availableInputDevices: [AudioInputDevice] = []
    @Published var selectedInputDeviceID: AudioDeviceID = 0 {
        didSet {
            manager.selectedInputDeviceID = selectedInputDeviceID
        }
    }

    var onIntent: ((VoiceIntent, String?, String?, String?, String?, String?, String?, String?) -> Void)? {
        get { manager.onIntent }
        set { manager.onIntent = newValue }
    }
    
    var onRecognitionFailure: ((String?, String?, String?, String?) -> Void)? {
        get { manager.onRecognitionFailure }
        set { manager.onRecognitionFailure = newValue }
    }

    var onWakeAnalyticsSignal: ((WakeAnalyticsSignal) -> Void)? {
        get { manager.onWakeAnalyticsSignal }
        set { manager.onWakeAnalyticsSignal = newValue }
    }

    var onIdlePauseResumeRequest: ((String) -> Void)? {
        get { manager.onIdlePauseResumeRequest }
        set { manager.onIdlePauseResumeRequest = newValue }
    }

    var isDictationExecutionEnabled: (() -> Bool)? {
        get { manager.isDictationExecutionEnabled }
        set { manager.isDictationExecutionEnabled = newValue }
    }

    var isCommandExecutionEnabled: (() -> Bool)? {
        get { manager.isCommandExecutionEnabled }
        set { manager.isCommandExecutionEnabled = newValue }
    }

    var isAppIdlePaused: (() -> Bool)? {
        get { manager.isAppIdlePaused }
        set { manager.isAppIdlePaused = newValue }
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

    var enhancedPlaybackLeakSuppressionEnabled: Bool {
        get { manager.enhancedPlaybackLeakSuppressionEnabled }
        set {
            objectWillChange.send()
            manager.enhancedPlaybackLeakSuppressionEnabled = newValue
        }
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

        manager.$playbackLeakState
            .receive(on: DispatchQueue.main)
            .assign(to: &$playbackLeakState)
            
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

    func setIdlePauseSuspended(_ suspended: Bool) {
        manager.setIdlePauseSuspended(suspended)
    }

    func setGazeWakeEnabled(_ enabled: Bool) {
        manager.isGazeWakeEnabled = false
    }

    func setAutoPunctuationEnabled(_ enabled: Bool) {
        manager.isAutoPunctuationEnabled = enabled
    }


    func setAutoDictationEnhancementEnabled(_ enabled: Bool) {
        manager.isAutoDictationEnhancementEnabled = enabled
    }

    func setFullTextRewriteEnabled(_ enabled: Bool) {
        manager.isFullTextRewriteEnabled = enabled
    }

    func setLLMProviderConfiguration(
        dictationConfig: LLMProviderConfiguration?,
        dictationSource: LLMServiceSource,
        rewriteConfig: LLMProviderConfiguration?,
        rewriteSource: LLMServiceSource
    ) {
        manager.setLLMProviderConfiguration(
            dictationConfig: dictationConfig,
            dictationSource: dictationSource,
            rewriteConfig: rewriteConfig,
            rewriteSource: rewriteSource
        )
    }

    func setDeveloperSpeechProfileEnabled(_ enabled: Bool) {
        manager.isDeveloperSpeechProfileEnabled = enabled
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

    func setCustomAppLaunchAliasRules(_ rules: [CustomAppLaunchAliasRule]) {
        manager.setCustomAppLaunchAliasRules(rules)
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

    @MainActor
    func exportFocusedInputDiagnostics() throws -> URL {
        try manager.exportFocusedInputDiagnostics()
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

private enum AetherSecretKeychain {
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
        guard status == errSecSuccess else { return nil }
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

    static func remove(service: String, account: String) -> Bool {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
        ]
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }
}

@MainActor
class AppState: ObservableObject {
    private static let screenIsLockedNotificationName = Notification.Name("com.apple.screenIsLocked")
    private static let screenIsUnlockedNotificationName = Notification.Name("com.apple.screenIsUnlocked")
    private static let loginWindowBundleIdentifier = "com.apple.loginwindow"
    private static let permissionRecoveryArgumentPrefix = "--permission-recovery="
    private static let defaultBundleIdentifier = "com.7fei.Aether"
    static let autoDictationLLMProviderSourceStorageKey = "autoDictationLLMProvider.source"
    static let fullTextRewriteLLMProviderSourceStorageKey = "fullTextRewriteLLMProvider.source"
    private static let legacyLLMProviderSourceStorageKey = "llmProvider.source"
    static let llmEndpointStorageKey = "llmProvider.endpoint"
    static let llmModelStorageKey = "llmProvider.model"
    static let autoDictationEnhancementStorageKey = "isAutoDictationEnhancementEnabled"
    static let fullTextRewriteStorageKey = "isFullTextRewriteEnabled"
    private static let legacyLLMEnhancementStorageKey = "isLLMEnhancementEnabled"
    private static let llmKeychainService = defaultBundleIdentifier + ".llm"
    private static let llmKeychainAccount = "api-key"
    private static let asrExpertProfileStorageKey = "asrExpertProfileV1"

    enum LLMConfigurationState: Equatable {
        case ready
        case missingAPIKey
        case missingModel
        case invalidEndpoint
        case appleOnDeviceUnavailable
    }

    enum LLMConfigurationFeedbackKind {
        case neutral
        case success
        case warning
        case error
    }

    private enum PendingPermissionRecovery: String {
        case microphone
        case speech
    }

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
        case activation
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
        var originalContent: String?
        var spokenText: String?
        var enhancedContent: String?
        var committedContent: String?
        var enhancementStatus: String?
        var eventCode: String?
        var wakeGroupID: String?
        var wakePhrase: String?
        var localeIdentifier: String?
        var rewriteScope: String?
        var rewriteMode: String?

        init(
            id: String = UUID().uuidString,
            timestamp: Date = Date(),
            appName: String,
            bundleIdentifier: String,
            kind: VoiceUsageEventKind,
            action: String,
            content: String? = nil,
            originalContent: String? = nil,
            spokenText: String? = nil,
            enhancedContent: String? = nil,
            committedContent: String? = nil,
            enhancementStatus: String? = nil,
            eventCode: String? = nil,
            wakeGroupID: String? = nil,
            wakePhrase: String? = nil,
            localeIdentifier: String? = nil,
            rewriteScope: String? = nil,
            rewriteMode: String? = nil
        ) {
            self.id = id
            self.timestamp = timestamp
            self.appName = appName
            self.bundleIdentifier = bundleIdentifier
            self.kind = kind
            self.action = action
            self.content = content
            self.originalContent = originalContent
            self.spokenText = spokenText
            self.enhancedContent = enhancedContent
            self.committedContent = committedContent
            self.enhancementStatus = enhancementStatus
            self.eventCode = eventCode
            self.wakeGroupID = wakeGroupID
            self.wakePhrase = wakePhrase
            self.localeIdentifier = localeIdentifier
            self.rewriteScope = rewriteScope
            self.rewriteMode = rewriteMode
        }
    }

    struct VoiceUsageSummary: Codable {
        let total: Int
        let dictationCount: Int
        let dictationCharacterCount: Int
        let failureCount: Int
        let unrecognizedCount: Int
        let mismatchCount: Int
        let noSpeechCount: Int
        let controlCount: Int
        let wakeHitCount: Int
        let wakeEmptyCount: Int
        let wakeToDictationCount: Int
        let wakeToControlCount: Int

        enum CodingKeys: String, CodingKey {
            case total
            case dictationCount
            case dictationCharacterCount
            case failureCount
            case unrecognizedCount
            case mismatchCount
            case noSpeechCount
            case controlCount
            case wakeHitCount
            case wakeEmptyCount
            case wakeToDictationCount
            case wakeToControlCount
        }

        init(
            total: Int,
            dictationCount: Int,
            dictationCharacterCount: Int,
            failureCount: Int,
            unrecognizedCount: Int,
            mismatchCount: Int,
            noSpeechCount: Int = 0,
            controlCount: Int,
            wakeHitCount: Int = 0,
            wakeEmptyCount: Int = 0,
            wakeToDictationCount: Int = 0,
            wakeToControlCount: Int = 0
        ) {
            self.total = total
            self.dictationCount = dictationCount
            self.dictationCharacterCount = dictationCharacterCount
            self.failureCount = failureCount
            self.unrecognizedCount = unrecognizedCount
            self.mismatchCount = mismatchCount
            self.noSpeechCount = noSpeechCount
            self.controlCount = controlCount
            self.wakeHitCount = wakeHitCount
            self.wakeEmptyCount = wakeEmptyCount
            self.wakeToDictationCount = wakeToDictationCount
            self.wakeToControlCount = wakeToControlCount
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            total = try container.decode(Int.self, forKey: .total)
            dictationCount = try container.decode(Int.self, forKey: .dictationCount)
            dictationCharacterCount = try container.decode(Int.self, forKey: .dictationCharacterCount)
            failureCount = try container.decode(Int.self, forKey: .failureCount)
            unrecognizedCount = try container.decode(Int.self, forKey: .unrecognizedCount)
            mismatchCount = try container.decode(Int.self, forKey: .mismatchCount)
            noSpeechCount = try container.decodeIfPresent(Int.self, forKey: .noSpeechCount) ?? 0
            controlCount = try container.decode(Int.self, forKey: .controlCount)
            wakeHitCount = try container.decodeIfPresent(Int.self, forKey: .wakeHitCount) ?? 0
            wakeEmptyCount = try container.decodeIfPresent(Int.self, forKey: .wakeEmptyCount) ?? 0
            wakeToDictationCount = try container.decodeIfPresent(Int.self, forKey: .wakeToDictationCount) ?? 0
            wakeToControlCount = try container.decodeIfPresent(Int.self, forKey: .wakeToControlCount) ?? 0
        }

        static let zero = VoiceUsageSummary(
            total: 0,
            dictationCount: 0,
            dictationCharacterCount: 0,
            failureCount: 0,
            unrecognizedCount: 0,
            mismatchCount: 0,
            noSpeechCount: 0,
            controlCount: 0,
            wakeHitCount: 0,
            wakeEmptyCount: 0,
            wakeToDictationCount: 0,
            wakeToControlCount: 0
        )
    }

    struct VoiceUsageAppSummary: Identifiable, Codable {
        var id: String { bundleIdentifier }
        let appName: String
        let bundleIdentifier: String
        let total: Int
        let dictationCount: Int
        let dictationCharacterCount: Int
        let failureCount: Int
        let unrecognizedCount: Int
        let mismatchCount: Int
        let noSpeechCount: Int
        let controlCount: Int

        enum CodingKeys: String, CodingKey {
            case appName
            case bundleIdentifier
            case total
            case dictationCount
            case dictationCharacterCount
            case failureCount
            case unrecognizedCount
            case mismatchCount
            case noSpeechCount
            case controlCount
        }

        init(
            appName: String,
            bundleIdentifier: String,
            total: Int,
            dictationCount: Int,
            dictationCharacterCount: Int,
            failureCount: Int,
            unrecognizedCount: Int,
            mismatchCount: Int,
            noSpeechCount: Int = 0,
            controlCount: Int
        ) {
            self.appName = appName
            self.bundleIdentifier = bundleIdentifier
            self.total = total
            self.dictationCount = dictationCount
            self.dictationCharacterCount = dictationCharacterCount
            self.failureCount = failureCount
            self.unrecognizedCount = unrecognizedCount
            self.mismatchCount = mismatchCount
            self.noSpeechCount = noSpeechCount
            self.controlCount = controlCount
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            appName = try container.decode(String.self, forKey: .appName)
            bundleIdentifier = try container.decode(String.self, forKey: .bundleIdentifier)
            total = try container.decode(Int.self, forKey: .total)
            dictationCount = try container.decode(Int.self, forKey: .dictationCount)
            dictationCharacterCount = try container.decode(Int.self, forKey: .dictationCharacterCount)
            failureCount = try container.decode(Int.self, forKey: .failureCount)
            unrecognizedCount = try container.decode(Int.self, forKey: .unrecognizedCount)
            mismatchCount = try container.decode(Int.self, forKey: .mismatchCount)
            noSpeechCount = try container.decodeIfPresent(Int.self, forKey: .noSpeechCount) ?? 0
            controlCount = try container.decode(Int.self, forKey: .controlCount)
        }
    }

    enum UsageInsightsTab: String, CaseIterable, Identifiable {
        case overview
        case activity
        case diagnostics
        case data

        var id: String { rawValue }
    }

    enum UsageInsightsPerAppSortOption: String, CaseIterable, Identifiable {
        case issuePriority
        case total

        var id: String { rawValue }
    }

    enum UsageInsightsRecentActivityFilter: String, CaseIterable, Identifiable {
        case all
        case issues
        case dictation
        case control

        var id: String { rawValue }
    }

    enum UsageInsightsEventOutcome: String, Equatable {
        case activation
        case dictation
        case control
        case failure
        case unmatched
        case mismatch
        case anomaly
        case other
    }

    enum UsageInsightsReasonCode: String, Equatable {
        case dictation
        case command
        case unknownCommand
        case recognitionFailed
        case recognitionInterrupted
        case recognitionUnavailable
        case inputFailed
        case inputUnverified
        case dictationDisabled
        case noSpeech
        case unmatched
        case noInputTarget
        case dictationWhileControl
        case wakeHit
        case wakeEmpty
        case wakeToDictation
        case wakeToControl
        case wakeMiss
        case wakeFollowUpContent
        case wakeLateAfterTimeout
        case other
    }

    struct UsageInsightsEventRecord: Identifiable, Equatable {
        let source: VoiceUsageEvent
        let outcome: UsageInsightsEventOutcome
        let reasonCode: UsageInsightsReasonCode

        var id: String { source.id }
        var isIssue: Bool {
            switch outcome {
                case .failure, .unmatched, .mismatch, .anomaly:
                    return true
                case .activation, .dictation, .control, .other:
                    return false
            }
        }

        var isNoSpeech: Bool {
            outcome == .anomaly && reasonCode == .noSpeech
        }
    }

    struct UsageInsightsDashboardSnapshot {
        let summary: VoiceUsageSummary
        let issueEventCount: Int
        let issueRate: Double
        let retainedHistoryCount: Int
        let retentionLimit: Int
    }

    struct UsageInsightsPerAppItem: Identifiable {
        let summary: VoiceUsageAppSummary

        var id: String { summary.id }
        var issueCount: Int {
            summary.failureCount + summary.unrecognizedCount + summary.mismatchCount
        }
        var anomalyCount: Int {
            summary.noSpeechCount
        }
    }

    struct UsageInsightsDiagnosticsSnapshot {
        let localeIdentifier: String
        let retainedHistoryCount: Int
        let aiPromptEventCount: Int
        let aiPromptEventLimit: Int
        let customRuleCount: Int
    }

    struct UsageInsightsSnapshot {
        let dashboard: UsageInsightsDashboardSnapshot
        let perAppItems: [UsageInsightsPerAppItem]
        let recentEvents: [UsageInsightsEventRecord]
        let recentMatchingCount: Int
        let diagnostics: UsageInsightsDiagnosticsSnapshot
    }

    enum WakeInsightsRecentFilter: String, CaseIterable, Identifiable {
        case all
        case hits
        case conversions
        case empty
        case failures
        case followUp
        case lateAfterTimeout

        var id: String { rawValue }
    }

    struct WakeInsightsDashboardSnapshot {
        let wakeHitCount: Int
        let wakeEmptyCount: Int
        let wakeToDictationCount: Int
        let wakeToControlCount: Int
        let wakeMissCount: Int
        let wakeFollowUpCount: Int
        let wakeLateAfterTimeoutCount: Int
        let conversionRate: Double
        let retainedHistoryCount: Int
    }

    struct WakeInsightsPhraseItem: Identifiable {
        let phrase: String
        let hitCount: Int
        let conversionCount: Int
        let emptyCount: Int

        var id: String { phrase }
        var conversionRate: Double {
            guard hitCount > 0 else { return 0 }
            return Double(conversionCount) / Double(hitCount)
        }
    }

    struct WakeInsightsSnapshot {
        let dashboard: WakeInsightsDashboardSnapshot
        let activeWakePhrases: [String]
        let currentLocaleIdentifier: String
        let wakeWindowSeconds: Double
        let recentEvents: [UsageInsightsEventRecord]
        let recentMatchingCount: Int
        let phraseItems: [WakeInsightsPhraseItem]
    }

    struct CustomAppShortcutRulesBackup: Codable {
        var version: Int = 1
        var exportedAt: Date = Date()
        var rules: [CustomAppShortcutRule]
    }

    struct CustomAppLaunchAliasRulesBackup: Codable {
        var version: Int = 1
        var exportedAt: Date = Date()
        var rules: [CustomAppLaunchAliasRule]
    }

    private static let speechTermGroupsStorageKey = "speechTermGroupsV2"
    private static let developerSpeechProfileEnabledStorageKey = "developerSpeechProfileEnabledV1"
    private static let voiceCommandOverridesStorageKey = "voiceCommandOverridesV1"
    private static let voiceLanguageTermsOverridesStorageKey = "voiceLanguageTermsOverridesV1"
    private static let voiceUsageHistoryEnabledStorageKey = "voiceUsageHistoryEnabledV1"
    private static let voiceUsageHistoryStorageKey = "voiceUsageHistoryV1"
    private static let voiceUsageHistoryLimitStorageKey = "voiceUsageHistoryLimitV1"
    private static let wakeLateFollowUpWindowSeconds: TimeInterval = 2.0
    private static let voiceUsageSummaryStorageKey = "voiceUsageSummaryV1"
    private static let voiceUsageAppSummariesStorageKey = "voiceUsageAppSummariesV1"
    private static let customAppShortcutRulesStorageKey = "customAppShortcutRulesV1"
    private static let customAppLaunchAliasRulesStorageKey = "customAppLaunchAliasRulesV1"
    private static let defaultVoiceUsageHistoryLimit = 1000
    private static let minVoiceUsageHistoryLimit = 100
    private static let maxVoiceUsageHistoryLimit = 5000

    @Published var appLanguageMode: AppLanguageMode = AppLocalization.storedAppLanguage() {
        didSet {
            guard oldValue != appLanguageMode else { return }
            AppLocalization.setPreferredLanguage(appLanguageMode)
            HUDManager.shared.showTemporary(
                message: AppLocalization.isChinese ? "重启后生效" : "Restart to apply",
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

    var appPublicVersionLabel: String? {
        Bundle.main.object(forInfoDictionaryKey: "AetherPublicVersionLabel") as? String
    }

    var appVersionDisplay: String {
        AetherBuildVersionFormatter.versionDisplay(
            shortVersion: appShortVersion,
            buildVersion: appBuildVersion,
            publicLabel: appPublicVersionLabel
        ) ?? appShortVersion
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

    private static func loadASRExpertProfile() -> ASRExpertProfile {
        if let data = UserDefaults.standard.data(forKey: asrExpertProfileStorageKey),
           let profile = try? JSONDecoder().decode(ASRExpertProfile.self, from: data) {
            return profile
        }
        return ASRExpertProfile()
    }

    private static func saveASRExpertProfile(_ profile: ASRExpertProfile) {
        if let data = try? JSONEncoder().encode(profile) {
            UserDefaults.standard.set(data, forKey: asrExpertProfileStorageKey)
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

    private static func loadCustomAppLaunchAliasRules() -> [CustomAppLaunchAliasRule] {
        guard let data = UserDefaults.standard.data(forKey: customAppLaunchAliasRulesStorageKey),
              let rules = try? JSONDecoder().decode([CustomAppLaunchAliasRule].self, from: data) else {
            return []
        }
        return normalizeCustomAppLaunchAliasRules(rules)
    }

    private static func saveCustomAppLaunchAliasRules(_ rules: [CustomAppLaunchAliasRule]) {
        let normalized = normalizeCustomAppLaunchAliasRules(rules)
        if let data = try? JSONEncoder().encode(normalized) {
            UserDefaults.standard.set(data, forKey: customAppLaunchAliasRulesStorageKey)
        }
    }

    private static func normalizeCustomAppLaunchAliasRules(_ rules: [CustomAppLaunchAliasRule]) -> [CustomAppLaunchAliasRule] {
        var normalized: [CustomAppLaunchAliasRule] = []
        var indexByBundle: [String: Int] = [:]

        for rule in rules {
            let bundleIdentifier = rule.effectiveBundleIdentifier
            let aliases = rule.effectiveAliases
            guard !bundleIdentifier.isEmpty, !aliases.isEmpty else { continue }

            let bundleKey = bundleIdentifier.lowercased()
            if let idx = indexByBundle[bundleKey] {
                normalized[idx].aliases = VoiceCommandRouter.uniqueAliases(normalized[idx].effectiveAliases + aliases)
                normalized[idx].isEnabled = normalized[idx].isEnabled || rule.isEnabled
            } else {
                normalized.append(
                    CustomAppLaunchAliasRule(
                        id: rule.id,
                        isEnabled: rule.isEnabled,
                        bundleIdentifier: bundleIdentifier,
                        aliases: aliases
                    )
                )
                indexByBundle[bundleKey] = normalized.count - 1
            }
        }

        return normalized
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

    private static func loadVoiceUsageSummary(seedEvents: [VoiceUsageEvent]) -> VoiceUsageSummary {
        if let data = UserDefaults.standard.data(forKey: voiceUsageSummaryStorageKey),
           let summary = try? JSONDecoder().decode(VoiceUsageSummary.self, from: data) {
            guard summaryDataNeedsNoSpeechMigration(data) else { return summary }
            let migratedNoSpeechCount = seedEvents.reduce(0) { partialResult, entry in
                partialResult + (isVoiceUsageNoSpeech(entry) ? 1 : 0)
            }
            return VoiceUsageSummary(
                total: summary.total,
                dictationCount: summary.dictationCount,
                dictationCharacterCount: summary.dictationCharacterCount,
                failureCount: max(summary.failureCount - migratedNoSpeechCount, 0),
                unrecognizedCount: summary.unrecognizedCount,
                mismatchCount: summary.mismatchCount,
                noSpeechCount: migratedNoSpeechCount,
                controlCount: summary.controlCount
            )
        }
        return rebuildVoiceUsageSummary(from: seedEvents)
    }

    private static func saveVoiceUsageSummary(_ summary: VoiceUsageSummary) {
        if let data = try? JSONEncoder().encode(summary) {
            UserDefaults.standard.set(data, forKey: voiceUsageSummaryStorageKey)
        }
    }

    private static func loadVoiceUsageAppSummaries(seedEvents: [VoiceUsageEvent]) -> [VoiceUsageAppSummary] {
        if let data = UserDefaults.standard.data(forKey: voiceUsageAppSummariesStorageKey),
           let summaries = try? JSONDecoder().decode([VoiceUsageAppSummary].self, from: data) {
            guard appSummaryDataNeedsNoSpeechMigration(data) else { return summaries }
            let migratedNoSpeechByBundle = Dictionary(grouping: seedEvents.filter(isVoiceUsageNoSpeech), by: \.bundleIdentifier)
                .mapValues(\.count)
            return summaries.map { summary in
                let migratedNoSpeechCount = migratedNoSpeechByBundle[summary.bundleIdentifier] ?? 0
                return VoiceUsageAppSummary(
                    appName: summary.appName,
                    bundleIdentifier: summary.bundleIdentifier,
                    total: summary.total,
                    dictationCount: summary.dictationCount,
                    dictationCharacterCount: summary.dictationCharacterCount,
                    failureCount: max(summary.failureCount - migratedNoSpeechCount, 0),
                    unrecognizedCount: summary.unrecognizedCount,
                    mismatchCount: summary.mismatchCount,
                    noSpeechCount: migratedNoSpeechCount,
                    controlCount: summary.controlCount
                )
            }
        }
        return rebuildVoiceUsageAppSummaries(from: seedEvents)
    }

    private static func summaryDataNeedsNoSpeechMigration(_ data: Data) -> Bool {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return false
        }
        return object["noSpeechCount"] == nil
    }

    private static func appSummaryDataNeedsNoSpeechMigration(_ data: Data) -> Bool {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
              let first = object.first else {
            return false
        }
        return first["noSpeechCount"] == nil
    }

    private static func saveVoiceUsageAppSummaries(_ summaries: [VoiceUsageAppSummary]) {
        if let data = try? JSONEncoder().encode(summaries) {
            UserDefaults.standard.set(data, forKey: voiceUsageAppSummariesStorageKey)
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

    private struct AppLaunchAliasPromptTarget: Codable {
        let bundleIdentifier: String
        let appName: String
        let aliases: [String]
    }

    private static let aiPromptMaxEventsDefault = 180
    private static let appLaunchAliasPromptMaxEventsDefault = 120

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
        let recentEvents = Array(
            voiceUsageHistory
                .filter { $0.kind != .activation }
                .prefix(resolvedMaxEvents)
        )
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

    func buildAppLaunchAliasAIPrompt(maxEvents: Int? = nil) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        let normalizedRules = Self.normalizeCustomAppLaunchAliasRules(customAppLaunchAliasRules)
        let currentRulesJSON = (try? String(
            data: encoder.encode(CustomAppLaunchAliasRulesBackup(rules: normalizedRules)),
            encoding: .utf8
        )) ?? "{}"

        let candidateTargets = AppLaunchResolver.contextualTargets(customRules: normalizedRules, limit: 48)
            .map {
                AppLaunchAliasPromptTarget(
                    bundleIdentifier: $0.bundleIdentifier,
                    appName: $0.displayName,
                    aliases: Array(VoiceCommandRouter.uniqueAliases([$0.displayName] + $0.aliases).prefix(8))
                )
            }
        let candidateTargetsJSON = (try? String(data: encoder.encode(candidateTargets), encoding: .utf8)) ?? "[]"

        let resolvedMaxEvents = maxEvents ?? Self.appLaunchAliasPromptMaxEventsDefault
        let recentEvents = Array(
            voiceUsageHistory
                .filter(Self.isRelevantForAppLaunchAliasPrompt)
                .prefix(resolvedMaxEvents)
        )
        let recentEventsJSON = (try? String(data: encoder.encode(recentEvents), encoding: .utf8)) ?? "[]"

        let exportedAt = ISO8601DateFormatter().string(from: Date())

        if AppLocalization.isChinese {
            return """
你是 Aether 的 App 打开别名顾问。目标：基于下面的历史与候选 App，生成可直接导入 Aether 的 App 打开别名配置，用于提升“打开 XX / 启动 XX / 切到 XX / 切换到 XX”这类语音指令的识别成功率。

只输出 JSON（不要 Markdown、不要解释）。JSON 必须严格符合 CustomAppLaunchAliasRulesBackup 格式：
{
  "version": 1,
  "exportedAt": "\(exportedAt)",
  "rules": [
    {
      "id": "chrome-launch-aliases",
      "isEnabled": true,
      "bundleIdentifier": "com.google.Chrome",
      "aliases": ["谷歌浏览器", "谷歌", "chrome"]
    }
  ]
}

说明：
- 每个 bundleIdentifier 最多输出一条规则。
- aliases 里放这一个 App 的完整建议别名集合，不要只给增量。
- 只输出“打开/启动/切到/切换到 App”相关别名，不要输出 App 内动作、菜单动作、提交/发送等快捷操作。
- 优先使用候选可打开 App 列表里的 bundleIdentifier。
- 如果历史证据不足，不要猜。
- 如果某个 App 当前已经有别名，而你建议补充更多叫法，请输出该 App 的完整合并后 aliases。

当前 App 打开别名（JSON）：
\(currentRulesJSON)

候选可打开 App（JSON）：
\(candidateTargetsJSON)

最近与“打开 App”相关的历史（JSON）：
\(recentEventsJSON)
"""
        }

        return """
You are an Aether app-launch alias assistant. Goal: based on the history and candidate apps below, generate an app-launch alias config that can be imported directly into Aether to improve recognition for commands like “open X”, “launch X”, and “switch to X”.

Output JSON only (no Markdown, no explanations). JSON must strictly follow the CustomAppLaunchAliasRulesBackup format:
{
  "version": 1,
  "exportedAt": "\(exportedAt)",
  "rules": [
    {
      "id": "chrome-launch-aliases",
      "isEnabled": true,
      "bundleIdentifier": "com.google.Chrome",
      "aliases": ["google chrome", "chrome", "google browser"]
    }
  ]
}

Notes:
- Output at most one rule per bundleIdentifier.
- Put the full suggested alias set for that app in aliases, not just incremental additions.
- Only output aliases for opening or switching to an app. Do not include in-app actions, menu actions, send/submit actions, or shortcuts.
- Prefer bundleIdentifier values from the candidate app list below.
- Do not guess when the evidence is weak.
- If an app already has aliases and you want to add more, output the fully merged alias set for that app.

Current app launch aliases (JSON):
\(currentRulesJSON)

Candidate launchable apps (JSON):
\(candidateTargetsJSON)

Recent history relevant to app-launch commands (JSON):
\(recentEventsJSON)
"""
    }

    private static func isRelevantForAppLaunchAliasPrompt(_ event: VoiceUsageEvent) -> Bool {
        guard event.kind != .activation else { return false }
        if looksLikeAppLaunchAction(event.action) {
            return true
        }

        return [
            event.content,
            event.originalContent,
            event.spokenText,
            event.committedContent
        ].contains(where: looksLikeAppLaunchPhrase)
    }

    private static func looksLikeAppLaunchAction(_ raw: String?) -> Bool {
        guard let raw else { return false }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        if trimmed.hasPrefix("打开 ") || trimmed.hasPrefix("启动 ") || trimmed.hasPrefix("切到 ") || trimmed.hasPrefix("切换到 ") {
            return true
        }

        let lowered = trimmed.lowercased()
        return lowered.hasPrefix("open ") || lowered.hasPrefix("launch ") || lowered.hasPrefix("switch to ")
    }

    private static func looksLikeAppLaunchPhrase(_ raw: String?) -> Bool {
        guard let raw else { return false }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        if trimmed.hasPrefix("打开") || trimmed.hasPrefix("启动") || trimmed.hasPrefix("切到") || trimmed.hasPrefix("切换到") {
            return true
        }

        let lowered = trimmed.lowercased()
        return lowered.hasPrefix("open ")
            || lowered.hasPrefix("launch ")
            || lowered.hasPrefix("switch to ")
            || lowered.hasPrefix("switch ")
    }

    enum VoiceActivationMode: String, CaseIterable, Identifiable {
        case pushToTalk
        case wakeWord
        case handsFree
        
        var id: String { rawValue }
    }
    
    private static func loadActivationMode() -> VoiceActivationMode {
        let defaults = UserDefaults.standard

        if let raw = defaults.string(forKey: "voiceActivationMode"),
           let mode = VoiceActivationMode(rawValue: raw) {
            return mode
        }

        // Only migrate the legacy booleans when they were explicitly written.
        let hasAlways = defaults.object(forKey: "isAlwaysListeningEnabled") != nil
        let hasWake = defaults.object(forKey: "isWakeWordEnabled") != nil
        if hasAlways || hasWake {
            let always = defaults.bool(forKey: "isAlwaysListeningEnabled")
            let wake = defaults.object(forKey: "isWakeWordEnabled") as? Bool ?? false
            if always { return .handsFree }
            if wake { return .wakeWord }
        }

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
        CGEventFlags.maskAlphaShift.rawValue |
        CGEventFlags.maskSecondaryFn.rawValue

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
    @Published var isIdlePaused: Bool = false
    @Published private(set) var isScreenLocked: Bool = false
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
    
    @Published var isWakeWordEnabled: Bool = UserDefaults.standard.object(forKey: "isWakeWordEnabled") as? Bool ?? false {
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
                    requestMicrophoneGuided()
                    return
                }
                if !speechAuthorized {
                    setAlwaysListeningEnabledInternal(false)
                    requestSpeechGuided()
                    return
                }
            }
            
            updateContinuousListeningState()
        }
    }
    private var isMutatingAlwaysListening = false
    private var isApplyingActivationMode = false
    private var didSuspendVoiceRuntimeForIdlePause: Bool = false
    private var screenLockObserverTokens: [NSObjectProtocol] = []
    private var workspaceObserverTokens: [NSObjectProtocol] = []
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
                requestMicrophoneGuided()
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
                requestSpeechGuided()
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
        let isStartupCheck = source == "startup"
        let shouldAutoEnableForCurrentRoute = isHeadsetLike && (!lastHeadsetLikeInput || isStartupCheck)
        if shouldAutoEnableForCurrentRoute {
            if autoEnableVoiceInputOnHeadset && !isVoiceInputEnabled {
                isVoiceInputEnabled = true
            }
            if autoEnableVoiceControlOnHeadset && !isVoiceControlEnabled {
                isVoiceControlEnabled = true
            }
            if autoEnableVoiceOnHeadset && !isVoiceEnabled {
                isVoiceEnabled = true
            }
        }
        lastHeadsetLikeInput = isHeadsetLike
        HeadsetRouteState.shared.isConnected = isHeadsetLike
        NotificationCenter.default.post(
            name: .aetherHeadsetRouteChanged,
            object: nil,
            userInfo: [
                "connected": isHeadsetLike,
                "source": source
            ]
        )
    }
    

    
    @Published var isGazeWakeEnabled: Bool = {
        UserDefaults.standard.set(false, forKey: "isGazeWakeEnabled")
        return false
    }() {
        didSet {
            if isGazeWakeEnabled {
                isGazeWakeEnabled = false
                return
            }
            UserDefaults.standard.set(false, forKey: "isGazeWakeEnabled")
            voiceService.setGazeWakeEnabled(false)
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
        UserDefaults.standard.object(forKey: "speechTermCorrectionEnabled") as? Bool ?? false
    }() {
        didSet {
            UserDefaults.standard.set(speechTermCorrectionEnabled, forKey: "speechTermCorrectionEnabled")
        }
    }
    @Published var isDeveloperSpeechProfileEnabled: Bool = UserDefaults.standard.object(
        forKey: developerSpeechProfileEnabledStorageKey
    ) as? Bool ?? true {
        didSet {
            UserDefaults.standard.set(
                isDeveloperSpeechProfileEnabled,
                forKey: Self.developerSpeechProfileEnabledStorageKey
            )
            voiceService.setDeveloperSpeechProfileEnabled(isDeveloperSpeechProfileEnabled)
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
    @Published private var storedVoiceUsageSummary: VoiceUsageSummary = {
        let seedEvents = AppState.loadVoiceUsageHistory(limit: AppState.loadVoiceUsageHistoryLimit())
        return AppState.loadVoiceUsageSummary(seedEvents: seedEvents)
    }() {
        didSet {
            Self.saveVoiceUsageSummary(storedVoiceUsageSummary)
        }
    }
    @Published private var storedVoiceUsageAppSummaries: [VoiceUsageAppSummary] = {
        let seedEvents = AppState.loadVoiceUsageHistory(limit: AppState.loadVoiceUsageHistoryLimit())
        return AppState.loadVoiceUsageAppSummaries(seedEvents: seedEvents)
    }() {
        didSet {
            Self.saveVoiceUsageAppSummaries(storedVoiceUsageAppSummaries)
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
    @Published var customAppLaunchAliasRules: [CustomAppLaunchAliasRule] = AppState.loadCustomAppLaunchAliasRules() {
        didSet {
            let normalized = AppState.normalizeCustomAppLaunchAliasRules(customAppLaunchAliasRules)
            guard normalized == customAppLaunchAliasRules else {
                customAppLaunchAliasRules = normalized
                return
            }
            AppState.saveCustomAppLaunchAliasRules(customAppLaunchAliasRules)
            voiceService.setCustomAppLaunchAliasRules(customAppLaunchAliasRules)
        }
    }

    var voiceUsageSummary: VoiceUsageSummary {
        storedVoiceUsageSummary
    }

    var voiceUsageAppSummaries: [VoiceUsageAppSummary] {
        storedVoiceUsageAppSummaries
    }

    var usageInsightsAIPromptMaxEvents: Int {
        Self.aiPromptMaxEventsDefault
    }

    func usageInsightsSnapshot(
        showNoSpeechEvents: Bool,
        recentFilter: UsageInsightsRecentActivityFilter,
        perAppSort: UsageInsightsPerAppSortOption,
        recentLimit: Int = 30
    ) -> UsageInsightsSnapshot {
        let summary = voiceUsageSummary
        let issueEventCount = summary.failureCount + summary.unrecognizedCount + summary.mismatchCount
        let issueRate = summary.total > 0 ? Double(issueEventCount) / Double(summary.total) : 0

        let classifiedEvents = voiceUsageHistory
            .filter { $0.kind != .activation }
            .map(Self.classifyUsageInsightsEvent)
        let filteredEvents = classifiedEvents.filter { record in
            if !showNoSpeechEvents && record.isNoSpeech {
                return false
            }
            switch recentFilter {
            case .all:
                return true
            case .issues:
                return record.isIssue
            case .dictation:
                return record.source.kind == .dictation
            case .control:
                return record.source.kind == .control
            }
        }

        let perAppItems = sortedUsageInsightsPerAppItems(
            storedVoiceUsageAppSummaries.map { UsageInsightsPerAppItem(summary: $0) },
            by: perAppSort
        )

        return UsageInsightsSnapshot(
            dashboard: UsageInsightsDashboardSnapshot(
                summary: summary,
                issueEventCount: issueEventCount,
                issueRate: issueRate,
                retainedHistoryCount: classifiedEvents.count,
                retentionLimit: voiceUsageHistoryLimit
            ),
            perAppItems: perAppItems,
            recentEvents: Array(filteredEvents.prefix(recentLimit)),
            recentMatchingCount: filteredEvents.count,
            diagnostics: UsageInsightsDiagnosticsSnapshot(
                localeIdentifier: voiceService.effectiveLocaleIdentifier,
                retainedHistoryCount: classifiedEvents.count,
                aiPromptEventCount: min(classifiedEvents.count, Self.aiPromptMaxEventsDefault),
                aiPromptEventLimit: Self.aiPromptMaxEventsDefault,
                customRuleCount: customAppShortcutRules.count
            )
        )
    }

    func wakeInsightsSnapshot(
        recentFilter: WakeInsightsRecentFilter,
        recentLimit: Int = 30
    ) -> WakeInsightsSnapshot {
        let activationRecords = voiceUsageHistory
            .filter { $0.kind == .activation }
            .map(Self.classifyUsageInsightsEvent)

        let filteredEvents = activationRecords.filter { record in
            switch recentFilter {
            case .all:
                return true
            case .hits:
                return record.reasonCode == .wakeHit
            case .conversions:
                return record.reasonCode == .wakeToDictation || record.reasonCode == .wakeToControl
            case .empty:
                return record.reasonCode == .wakeEmpty
            case .failures:
                return record.reasonCode == .wakeMiss
            case .followUp:
                return record.reasonCode == .wakeFollowUpContent
            case .lateAfterTimeout:
                return record.reasonCode == .wakeLateAfterTimeout
            }
        }

        var phraseStats: [String: (hits: Int, conversions: Int, empty: Int)] = [:]
        for entry in voiceUsageHistory where entry.kind == .activation {
            let phrase = Self.normalizedWakePhrase(entry.wakePhrase) ?? (AppLocalization.isChinese ? "未记录" : "Unknown")
            let current = phraseStats[phrase] ?? (hits: 0, conversions: 0, empty: 0)
            switch entry.eventCode {
            case "wake.hit":
                phraseStats[phrase] = (hits: current.hits + 1, conversions: current.conversions, empty: current.empty)
            case "wake.to_dictation", "wake.to_control":
                phraseStats[phrase] = (hits: current.hits, conversions: current.conversions + 1, empty: current.empty)
            case "wake.empty":
                phraseStats[phrase] = (hits: current.hits, conversions: current.conversions, empty: current.empty + 1)
            default:
                phraseStats[phrase] = current
            }
        }

        let phraseItems = phraseStats.map { phrase, stats in
            WakeInsightsPhraseItem(
                phrase: phrase,
                hitCount: stats.hits,
                conversionCount: stats.conversions,
                emptyCount: stats.empty
            )
        }
        .sorted {
            if $0.hitCount == $1.hitCount {
                return $0.phrase.localizedCaseInsensitiveCompare($1.phrase) == .orderedAscending
            }
            return $0.hitCount > $1.hitCount
        }

        let summary = voiceUsageSummary
        let wakeHitCount = summary.wakeHitCount
        let conversionCount = summary.wakeToDictationCount + summary.wakeToControlCount
        let wakeMissCount = activationRecords.reduce(into: 0) { partialResult, record in
            if record.reasonCode == .wakeMiss {
                partialResult += 1
            }
        }
        let wakeFollowUpCount = activationRecords.reduce(into: 0) { partialResult, record in
            if record.reasonCode == .wakeFollowUpContent {
                partialResult += 1
            }
        }
        let wakeLateAfterTimeoutCount = activationRecords.reduce(into: 0) { partialResult, record in
            if record.reasonCode == .wakeLateAfterTimeout {
                partialResult += 1
            }
        }
        let conversionRate = wakeHitCount > 0 ? Double(conversionCount) / Double(wakeHitCount) : 0

        return WakeInsightsSnapshot(
            dashboard: WakeInsightsDashboardSnapshot(
                wakeHitCount: wakeHitCount,
                wakeEmptyCount: summary.wakeEmptyCount,
                wakeToDictationCount: summary.wakeToDictationCount,
                wakeToControlCount: summary.wakeToControlCount,
                wakeMissCount: wakeMissCount,
                wakeFollowUpCount: wakeFollowUpCount,
                wakeLateAfterTimeoutCount: wakeLateAfterTimeoutCount,
                conversionRate: conversionRate,
                retainedHistoryCount: activationRecords.count
            ),
            activeWakePhrases: WakeWordDetector.effectiveWakePhrases(
                for: voiceService.effectiveLocaleIdentifier,
                overrides: voiceLanguageTermsOverrides
            ),
            currentLocaleIdentifier: voiceService.effectiveLocaleIdentifier,
            wakeWindowSeconds: alwaysListeningWakeWindowSeconds,
            recentEvents: Array(filteredEvents.prefix(recentLimit)),
            recentMatchingCount: filteredEvents.count,
            phraseItems: phraseItems
        )
    }

    /// Clears event history and all derived voice-usage aggregates in one operation.
    func clearVoiceUsageData() {
        voiceUsageHistory = []
        storedVoiceUsageSummary = .zero
        storedVoiceUsageAppSummaries = []
    }

    func clearVoiceUsageHistory() {
        voiceUsageHistory = []
    }

    func resetVoiceUsageStatistics() {
        storedVoiceUsageSummary = .zero
        storedVoiceUsageAppSummaries = []
    }

    private static func isVoiceUsageSuccessfulDictation(_ entry: VoiceUsageEvent) -> Bool {
        guard entry.kind == .dictation else { return false }
        return entry.action == "输入"
            || entry.action == "Dictation"
            || (entry.eventCode?.hasPrefix("rewrite.") ?? false)
    }

    private static func voiceUsageCharacterCount(for entry: VoiceUsageEvent) -> Int {
        entry.content?.count ?? 0
    }

    private static func localizedVoiceUsageAction(_ key: String, fallback: String) -> String {
        let value = NSLocalizedString(key, comment: "")
        return value == key ? fallback : value
    }

    private static func normalizedWakePhrase(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    static func sanitizedWakeWordUsageContent(
        _ raw: String?,
        localeIdentifier: String,
        stripsWakeWord: Bool,
        overrides: [VoiceLanguageTermsOverrideConfig]
    ) -> String? {
        let normalized = normalizedVoiceUsageExcerpt(raw)
        guard stripsWakeWord, let normalized else { return normalized }

        let detector = WakeWordDetector()
        detector.overrides = overrides
        let result = detector.process(normalized, localeIdentifier: localeIdentifier)
        guard result.wakeDetected else { return normalized }

        return normalizedVoiceUsageExcerpt(result.payload) ?? normalized
    }

    static func classifyUsageInsightsEvent(_ entry: VoiceUsageEvent) -> UsageInsightsEventRecord {
        let recognitionFailed = localizedVoiceUsageAction(
            "voice_usage.failure.recognition_failed",
            fallback: "Recognition Failed"
        )
        let recognitionInterrupted = localizedVoiceUsageAction(
            "voice_usage.failure.interrupted",
            fallback: "Recognition Interrupted"
        )
        let recognitionUnavailable = localizedVoiceUsageAction(
            "voice_usage.failure.unavailable",
            fallback: "Recognition Unavailable"
        )
        let inputFailed = localizedVoiceUsageAction(
            "voice_usage.failure.injection_failed",
            fallback: "Input Failed"
        )
        let inputUnverified = localizedVoiceUsageAction(
            "voice_usage.failure.injection_unverified",
            fallback: "Input Unverified"
        )
        let dictationDisabled = localizedVoiceUsageAction(
            "voice_usage.failure.dictation_disabled",
            fallback: "Voice Input Off"
        )
        let noSpeech = localizedVoiceUsageAction(
            "voice_usage.failure.no_speech",
            fallback: "No Speech Detected"
        )
        let unknownCommand = NSLocalizedString("intent.unknown", comment: "")

        if entry.kind == .activation {
            let reasonCode: UsageInsightsReasonCode
            switch entry.eventCode {
            case "wake.hit":
                reasonCode = .wakeHit
            case "wake.to_dictation":
                reasonCode = .wakeToDictation
            case "wake.to_control":
                reasonCode = .wakeToControl
            case "wake.empty":
                reasonCode = .wakeEmpty
            case "wake.followup.content":
                reasonCode = .wakeFollowUpContent
            case "wake.followup.late":
                reasonCode = .wakeLateAfterTimeout
            case let code where code?.hasPrefix("wake.miss.") == true:
                reasonCode = .wakeMiss
            default:
                reasonCode = .other
            }
            return UsageInsightsEventRecord(source: entry, outcome: .activation, reasonCode: reasonCode)
        }

        if isVoiceUsageSuccessfulDictation(entry) {
            return UsageInsightsEventRecord(source: entry, outcome: .dictation, reasonCode: .dictation)
        }

        if isVoiceUsageNoSpeech(entry) {
            return UsageInsightsEventRecord(source: entry, outcome: .anomaly, reasonCode: .noSpeech)
        }

        if isVoiceUsageFailure(entry) {
            let reasonCode: UsageInsightsReasonCode
            switch entry.action {
            case recognitionInterrupted, "Recognition Interrupted", "识别已中断":
                reasonCode = .recognitionInterrupted
            case recognitionUnavailable, "Recognition Unavailable", "识别服务不可用":
                reasonCode = .recognitionUnavailable
            case inputFailed, "Input Failed", "输入失败":
                reasonCode = .inputFailed
            case inputUnverified, "Input Unverified", "输入未确认":
                reasonCode = .inputUnverified
            case dictationDisabled, "Voice Input Off", "语音输入已关闭":
                reasonCode = .dictationDisabled
            case noSpeech, "No Speech Detected", "未识别到人声":
                reasonCode = .noSpeech
            case recognitionFailed, "Recognition Failed", "识别失败":
                reasonCode = .recognitionFailed
            default:
                reasonCode = .other
            }
            return UsageInsightsEventRecord(source: entry, outcome: .failure, reasonCode: reasonCode)
        }

        if isVoiceUsageUnrecognized(entry) {
            let reasonCode: UsageInsightsReasonCode
            switch entry.action {
            case "未输入（无输入框）", "No Input Target":
                reasonCode = .noInputTarget
            default:
                reasonCode = .unmatched
            }
            return UsageInsightsEventRecord(source: entry, outcome: .unmatched, reasonCode: reasonCode)
        }

        if isVoiceUsageHUDControlMismatch(entry) {
            return UsageInsightsEventRecord(
                source: entry,
                outcome: .mismatch,
                reasonCode: .dictationWhileControl
            )
        }

        if entry.kind == .control {
            let reasonCode: UsageInsightsReasonCode
            switch entry.action {
            case unknownCommand, "No Matching Command", "未匹配命令":
                reasonCode = .unknownCommand
            default:
                reasonCode = .command
            }
            return UsageInsightsEventRecord(source: entry, outcome: .control, reasonCode: reasonCode)
        }

        return UsageInsightsEventRecord(source: entry, outcome: .other, reasonCode: .other)
    }

    private static func isVoiceUsageFailure(_ entry: VoiceUsageEvent) -> Bool {
        guard entry.kind == .dictation else { return false }
        let failureActions = Set([
            Self.localizedVoiceUsageAction("voice_usage.failure.recognition_failed", fallback: "Recognition Failed"),
            Self.localizedVoiceUsageAction("voice_usage.failure.interrupted", fallback: "Recognition Interrupted"),
            Self.localizedVoiceUsageAction("voice_usage.failure.unavailable", fallback: "Recognition Unavailable"),
            Self.localizedVoiceUsageAction("voice_usage.failure.injection_failed", fallback: "Input Failed"),
            Self.localizedVoiceUsageAction("voice_usage.failure.injection_unverified", fallback: "Input Unverified"),
            Self.localizedVoiceUsageAction("voice_usage.failure.dictation_disabled", fallback: "Voice Input Off")
        ])
        return failureActions.contains(entry.action)
    }

    private static func isVoiceUsageNoSpeech(_ entry: VoiceUsageEvent) -> Bool {
        guard entry.kind == .dictation else { return false }
        let noSpeechActions = Set([
            Self.localizedVoiceUsageAction("voice_usage.failure.no_speech", fallback: "No Speech Detected"),
            "No Speech Detected",
            "未识别到人声"
        ])
        return noSpeechActions.contains(entry.action)
    }

    private static func isVoiceUsageUnrecognized(_ entry: VoiceUsageEvent) -> Bool {
        guard entry.kind == .dictation else { return false }
        // Backward-compatible: older builds recorded different labels for the same bucket.
        return entry.action == "未匹配" ||
            entry.action == "Unmatched" ||
            entry.action == "未识别" ||
            entry.action == "Unrecognized" ||
            entry.action == "未输入（无输入框）" ||
            entry.action == "No Input Target"
    }

    private static func isVoiceUsageHUDControlMismatch(_ entry: VoiceUsageEvent) -> Bool {
        guard entry.kind == .dictation else { return false }
        // Backward-compatible: older builds used different labels.
        return entry.action == "控制模式下输入" ||
            entry.action == "Dictation While HUD Control" ||
            entry.action == "控制模式误输入" ||
            entry.action == "Dictation While Control Mode"
    }

    private static func rebuildVoiceUsageSummary(from events: [VoiceUsageEvent]) -> VoiceUsageSummary {
        events.reduce(.zero) { partialResult, entry in
            updatedVoiceUsageSummary(partialResult, byAdding: entry)
        }
    }

    private static func rebuildVoiceUsageAppSummaries(from events: [VoiceUsageEvent]) -> [VoiceUsageAppSummary] {
        var summariesByBundle: [String: VoiceUsageAppSummary] = [:]
        for entry in events {
            guard entry.kind != .activation else { continue }
            let current = summariesByBundle[entry.bundleIdentifier] ?? VoiceUsageAppSummary(
                appName: entry.appName,
                bundleIdentifier: entry.bundleIdentifier,
                total: 0,
                dictationCount: 0,
                dictationCharacterCount: 0,
                failureCount: 0,
                unrecognizedCount: 0,
                mismatchCount: 0,
                noSpeechCount: 0,
                controlCount: 0
            )
            summariesByBundle[entry.bundleIdentifier] = updatedVoiceUsageAppSummary(current, byAdding: entry)
        }
        return sortVoiceUsageAppSummaries(Array(summariesByBundle.values))
    }

    private static func updatedVoiceUsageSummary(_ summary: VoiceUsageSummary, byAdding entry: VoiceUsageEvent) -> VoiceUsageSummary {
        let countsTowardVoiceTotals = entry.kind != .activation
        let total = summary.total + (countsTowardVoiceTotals ? 1 : 0)
        var dictationCount = summary.dictationCount
        var dictationCharacterCount = summary.dictationCharacterCount
        var failureCount = summary.failureCount
        var unrecognizedCount = summary.unrecognizedCount
        var mismatchCount = summary.mismatchCount
        var noSpeechCount = summary.noSpeechCount
        var controlCount = summary.controlCount
        var wakeHitCount = summary.wakeHitCount
        var wakeEmptyCount = summary.wakeEmptyCount
        var wakeToDictationCount = summary.wakeToDictationCount
        var wakeToControlCount = summary.wakeToControlCount

        if entry.kind == .activation {
            switch entry.eventCode {
            case "wake.hit":
                wakeHitCount += 1
            case "wake.empty":
                wakeEmptyCount += 1
            case "wake.to_dictation":
                wakeToDictationCount += 1
            case "wake.to_control":
                wakeToControlCount += 1
            default:
                break
            }
        }

        if isVoiceUsageSuccessfulDictation(entry) {
            dictationCount += 1
            dictationCharacterCount += voiceUsageCharacterCount(for: entry)
        } else if isVoiceUsageNoSpeech(entry) {
            noSpeechCount += 1
        } else if isVoiceUsageFailure(entry) {
            failureCount += 1
        } else if isVoiceUsageUnrecognized(entry) {
            unrecognizedCount += 1
        } else if isVoiceUsageHUDControlMismatch(entry) {
            mismatchCount += 1
        } else if entry.kind == .control {
            controlCount += 1
        }

        return VoiceUsageSummary(
            total: total,
            dictationCount: dictationCount,
            dictationCharacterCount: dictationCharacterCount,
            failureCount: failureCount,
            unrecognizedCount: unrecognizedCount,
            mismatchCount: mismatchCount,
            noSpeechCount: noSpeechCount,
            controlCount: controlCount,
            wakeHitCount: wakeHitCount,
            wakeEmptyCount: wakeEmptyCount,
            wakeToDictationCount: wakeToDictationCount,
            wakeToControlCount: wakeToControlCount
        )
    }

    private static func updatedVoiceUsageAppSummary(_ summary: VoiceUsageAppSummary, byAdding entry: VoiceUsageEvent) -> VoiceUsageAppSummary {
        guard entry.kind != .activation else { return summary }
        let total = summary.total + 1
        var dictationCount = summary.dictationCount
        var dictationCharacterCount = summary.dictationCharacterCount
        var failureCount = summary.failureCount
        var unrecognizedCount = summary.unrecognizedCount
        var mismatchCount = summary.mismatchCount
        var noSpeechCount = summary.noSpeechCount
        var controlCount = summary.controlCount

        if isVoiceUsageSuccessfulDictation(entry) {
            dictationCount += 1
            dictationCharacterCount += voiceUsageCharacterCount(for: entry)
        } else if isVoiceUsageNoSpeech(entry) {
            noSpeechCount += 1
        } else if isVoiceUsageFailure(entry) {
            failureCount += 1
        } else if isVoiceUsageUnrecognized(entry) {
            unrecognizedCount += 1
        } else if isVoiceUsageHUDControlMismatch(entry) {
            mismatchCount += 1
        } else if entry.kind == .control {
            controlCount += 1
        }

        return VoiceUsageAppSummary(
            appName: entry.appName.isEmpty ? summary.appName : entry.appName,
            bundleIdentifier: summary.bundleIdentifier,
            total: total,
            dictationCount: dictationCount,
            dictationCharacterCount: dictationCharacterCount,
            failureCount: failureCount,
            unrecognizedCount: unrecognizedCount,
            mismatchCount: mismatchCount,
            noSpeechCount: noSpeechCount,
            controlCount: controlCount
        )
    }

    private static func sortVoiceUsageAppSummaries(_ summaries: [VoiceUsageAppSummary]) -> [VoiceUsageAppSummary] {
        summaries.sorted {
            if $0.total == $1.total {
                return $0.appName.localizedCaseInsensitiveCompare($1.appName) == .orderedAscending
            }
            return $0.total > $1.total
        }
    }

    private func sortedUsageInsightsPerAppItems(
        _ items: [UsageInsightsPerAppItem],
        by sort: UsageInsightsPerAppSortOption
    ) -> [UsageInsightsPerAppItem] {
        switch sort {
        case .issuePriority:
            return items.sorted { lhs, rhs in
                if lhs.issueCount == rhs.issueCount {
                    if lhs.anomalyCount != rhs.anomalyCount {
                        return lhs.anomalyCount > rhs.anomalyCount
                    }
                    if lhs.summary.total == rhs.summary.total {
                        return lhs.summary.appName.localizedCaseInsensitiveCompare(rhs.summary.appName) == .orderedAscending
                    }
                    return lhs.summary.total > rhs.summary.total
                }
                return lhs.issueCount > rhs.issueCount
            }
        case .total:
            return items.sorted { lhs, rhs in
                if lhs.summary.total == rhs.summary.total {
                    return lhs.summary.appName.localizedCaseInsensitiveCompare(rhs.summary.appName) == .orderedAscending
                }
                return lhs.summary.total > rhs.summary.total
            }
        }
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

    func addGlobalCustomAppShortcutRule() {
        let defaultTitle = AppLocalization.isChinese ? "新全局动作" : "New Global Action"
        customAppShortcutRules.insert(
            CustomAppShortcutRule(
                bundleIdentifier: "",
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

    func makeCustomAppLaunchAliasDraft(prefilling bundleIdentifier: String? = nil) -> CustomAppLaunchAliasRule {
        CustomAppLaunchAliasRule(
            bundleIdentifier: bundleIdentifier ?? "",
            aliases: []
        )
    }

    func removeCustomAppLaunchAlias(id: String) {
        customAppLaunchAliasRules.removeAll { $0.id == id }
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
            if override.aliases.isEmpty {
                return ""
            }
            return effectiveCommandAliases(for: preset, localeIdentifier: canonical).joined(separator: ", ")
        }
        let defaults = VoiceCommandRouter.defaultAliases(for: preset, localeIdentifier: canonical)
        return defaults.joined(separator: ", ")
    }

    func commandCustomAliasText(for preset: VoiceCommandPreset, localeIdentifier: String) -> String {
        let canonical = VoiceLexiconSupport.canonicalLocaleIdentifier(localeIdentifier)
        if let override = voiceCommandOverrides.first(where: {
            VoiceLexiconSupport.canonicalLocaleIdentifier($0.localeIdentifier) == canonical &&
                $0.commandID == preset.rawValue
        }) {
            return override.aliases.joined(separator: ", ")
        }
        return ""
    }

    func updateCommandOverrideText(_ raw: String, for preset: VoiceCommandPreset, localeIdentifier: String) {
        let aliases = parseVoiceTermsText(raw)

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

    func appLaunchPrefixOverrideText(for localeIdentifier: String) -> String {
        let canonical = VoiceLexiconSupport.canonicalLocaleIdentifier(localeIdentifier)
        if let override = voiceLanguageTermsOverrides.first(where: {
            VoiceLexiconSupport.canonicalLocaleIdentifier($0.localeIdentifier) == canonical
        }) {
            return override.appLaunchPrefixes.joined(separator: ", ")
        }
        let defaults = VoiceLexiconDefaults.load()?.languageTermsOverrides.first(where: {
            VoiceLexiconSupport.canonicalLocaleIdentifier($0.localeIdentifier) == canonical
        })
        return defaults?.appLaunchPrefixes.joined(separator: ", ") ?? ""
    }

    func defaultAppLaunchPrefixText(for localeIdentifier: String) -> String {
        let canonical = VoiceLexiconSupport.canonicalLocaleIdentifier(localeIdentifier)
        let defaults = VoiceLexiconDefaults.load()?.languageTermsOverrides.first(where: {
            VoiceLexiconSupport.canonicalLocaleIdentifier($0.localeIdentifier) == canonical
        })
        return defaults?.appLaunchPrefixes.joined(separator: ", ") ?? ""
    }

    func updateAppLaunchPrefixOverrideText(_ raw: String, for localeIdentifier: String) {
        updateVoiceLanguageTermsOverride(for: localeIdentifier) { config in
            config.appLaunchPrefixes = parseVoiceTermsText(raw)
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
                merged.appLaunchPrefixes = mergeAliases(base: merged.appLaunchPrefixes, extra: item.appLaunchPrefixes)
                result[idx] = merged
            } else {
                let entry = VoiceLanguageTermsOverrideConfig(
                    localeIdentifier: item.localeIdentifier,
                    wakeWords: mergeAliases(base: [], extra: item.wakeWords),
                    commandPrefixes: mergeAliases(base: [], extra: item.commandPrefixes),
                    dictationPrefixes: mergeAliases(base: [], extra: item.dictationPrefixes),
                    appLaunchPrefixes: mergeAliases(base: [], extra: item.appLaunchPrefixes)
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

    func exportAppLaunchAliasAIPrompt() throws {
        let prompt = buildAppLaunchAliasAIPrompt()
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        guard pasteboard.setString(prompt, forType: .string) else {
            throw NSError(domain: "AetherAppLaunchAliasPromptExport", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to copy app launch alias prompt to pasteboard."])
        }
    }

    func copyVoiceUsageHistoryForDiagnostics() throws {
        let summary = voiceUsageSummary
        let localeID = voiceService.effectiveLocaleIdentifier
        let summaryLine = AppLocalization.isChinese
            ? "使用统计（总计=\(summary.total) 输入=\(summary.dictationCount) 控制=\(summary.controlCount) 唤醒=\(summary.wakeHitCount) 空唤醒=\(summary.wakeEmptyCount) locale=\(localeID)）："
            : "Usage Stats (total=\(summary.total) dictation=\(summary.dictationCount) control=\(summary.controlCount) wake=\(summary.wakeHitCount) emptyWake=\(summary.wakeEmptyCount) locale=\(localeID)):"
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

    func copyCustomAppLaunchAliasRulesToPasteboard() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let normalizedRules = Self.normalizeCustomAppLaunchAliasRules(customAppLaunchAliasRules)
        let data = try encoder.encode(CustomAppLaunchAliasRulesBackup(rules: normalizedRules))
        guard let payload = String(data: data, encoding: .utf8) else {
            throw NSError(domain: "AetherAppLaunchAliasesCopy", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to encode app launch aliases."])
        }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        guard pasteboard.setString(payload, forType: .string) else {
            throw NSError(domain: "AetherAppLaunchAliasesCopy", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to copy app launch aliases to pasteboard."])
        }
    }

    func importCustomAppLaunchAliasRulesFromPasteboard() throws -> Bool {
        let pasteboard = NSPasteboard.general
        guard let raw = pasteboard.string(forType: .string) else { return false }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let data = Data(trimmed.utf8)

        if let backup = try? decoder.decode(CustomAppLaunchAliasRulesBackup.self, from: data) {
            mergeCustomAppLaunchAliasRules(backup.rules)
            return true
        }

        let rules = try decoder.decode([CustomAppLaunchAliasRule].self, from: data)
        mergeCustomAppLaunchAliasRules(rules)
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

    private func mergeCustomAppLaunchAliasRules(_ incoming: [CustomAppLaunchAliasRule]) {
        customAppLaunchAliasRules = Self.normalizeCustomAppLaunchAliasRules(customAppLaunchAliasRules + incoming)
    }

    private func customAppShortcutRuleSemanticKey(_ rule: CustomAppShortcutRule) -> String {
        [
            rule.effectiveBundleIdentifiers.map { $0.lowercased() }.sorted().joined(separator: ","),
            rule.title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
            String(rule.shortcut.keyCode),
            String(rule.shortcut.modifiers)
        ].joined(separator: "::")
    }

    private func customAppLaunchAliasRuleSemanticKey(_ rule: CustomAppLaunchAliasRule) -> String {
        [
            rule.effectiveBundleIdentifier.lowercased(),
            rule.effectiveAliases.map { $0.lowercased() }.sorted().joined(separator: ",")
        ].joined(separator: "::")
    }

    private func parseVoiceTermsText(_ raw: String) -> [String] {
        raw
            .components(separatedBy: ",")
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
            dictationPrefixes: [],
            appLaunchPrefixes: []
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

    private static func normalizedStoredLLMValue(
        forKey key: String,
        defaults: UserDefaults
    ) -> String? {
        guard let value = defaults.string(forKey: key)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else {
            return nil
        }
        return value
    }

    private static func llmKeychainServicesToRead(bundleIdentifier: String? = Bundle.main.bundleIdentifier) -> [String] {
        let currentBundleService = (bundleIdentifier ?? defaultBundleIdentifier) + ".llm"
        return [llmKeychainService, currentBundleService].reduce(into: []) { partial, service in
            guard !partial.contains(service) else { return }
            partial.append(service)
        }
    }

    private static func llmKeychainServicesToWrite(bundleIdentifier: String? = Bundle.main.bundleIdentifier) -> [String] {
        llmKeychainServicesToRead(bundleIdentifier: bundleIdentifier)
    }

    static func defaultLLMEndpointText(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        defaults: UserDefaults = .standard
    ) -> String {
        normalizedStoredLLMValue(forKey: llmEndpointStorageKey, defaults: defaults)
            ?? environment["AETHER_LLM_ENDPOINT"]
            ?? environment["OPENAI_BASE_URL"]
            ?? OpenAICompatibleProvider.defaultEndpointString
    }

    static func defaultLLMModelText(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        defaults: UserDefaults = .standard
    ) -> String {
        normalizedStoredLLMValue(forKey: llmModelStorageKey, defaults: defaults)
            ?? environment["AETHER_LLM_MODEL"]
            ?? environment["OPENAI_MODEL"]
            ?? ""
    }

    private static func loadStoredLLMAPIKey() -> String? {
        for service in llmKeychainServicesToRead() {
            if let key = AetherSecretKeychain.load(service: service, account: llmKeychainAccount) {
                return key
            }
        }
        return nil
    }

    private static func saveStoredLLMAPIKey(_ value: String) {
        for service in llmKeychainServicesToWrite() {
            _ = AetherSecretKeychain.save(value, service: service, account: llmKeychainAccount)
        }
    }

    private static func removeStoredLLMAPIKey() {
        for service in llmKeychainServicesToRead() {
            _ = AetherSecretKeychain.remove(service: service, account: llmKeychainAccount)
        }
    }

    private static func defaultLLMAPIKey(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> String {
        loadStoredLLMAPIKey()
            ?? environment["AETHER_LLM_API_KEY"]
            ?? environment["OPENAI_API_KEY"]
            ?? ""
    }

    static func defaultLLMServiceSource(
        storageKey: String,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        defaults: UserDefaults = .standard
    ) -> LLMServiceSource {
        if let stored = defaults.string(forKey: storageKey),
           let source = LLMServiceSource(rawValue: stored) {
            return source
        }

        if let stored = defaults.string(forKey: legacyLLMProviderSourceStorageKey),
           let source = LLMServiceSource(rawValue: stored) {
            return source
        }

        let hasRemoteConfiguration =
            normalizedStoredLLMValue(forKey: llmEndpointStorageKey, defaults: defaults) != nil ||
            normalizedStoredLLMValue(forKey: llmModelStorageKey, defaults: defaults) != nil ||
            loadStoredLLMAPIKey() != nil ||
            environment["AETHER_LLM_ENDPOINT"] != nil ||
            environment["OPENAI_BASE_URL"] != nil ||
            environment["AETHER_LLM_MODEL"] != nil ||
            environment["OPENAI_MODEL"] != nil ||
            environment["AETHER_LLM_API_KEY"] != nil ||
            environment["OPENAI_API_KEY"] != nil

        if !hasRemoteConfiguration,
           AppleOnDeviceLLMProviderFactory.availability(localeIdentifier: Locale.current.identifier) == .available {
            return .appleOnDevice
        }

        return .openAICompatible
    }

    var appleOnDeviceLLMAvailability: AppleOnDeviceLLMAvailability {
        AppleOnDeviceLLMProviderFactory.availability(
            localeIdentifier: voiceService.effectiveLocaleIdentifier
        )
    }

    var activeSpeechLocaleDisplayName: String {
        let identifier = voiceService.effectiveLocaleIdentifier
        return Locale.current.localizedString(forIdentifier: identifier) ?? identifier
    }

    func llmConfigurationState(for source: LLMServiceSource) -> LLMConfigurationState {
        if source == .appleOnDevice {
            return appleOnDeviceLLMAvailability == .available
                ? .ready
                : .appleOnDeviceUnavailable
        }

        let endpoint = llmEndpointText.trimmingCharacters(in: .whitespacesAndNewlines)
        let model = llmModelText.trimmingCharacters(in: .whitespacesAndNewlines)
        let apiKey = llmAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !apiKey.isEmpty else { return .missingAPIKey }
        guard !model.isEmpty else { return .missingModel }
        guard !endpoint.isEmpty, URL(string: endpoint) != nil else { return .invalidEndpoint }
        return .ready
    }

    var isLLMProviderConfigured: Bool {
        llmConfigurationState(for: preferredLLMConfigurationTestSource) == .ready
    }

    @Published private(set) var llmAvailableModels: [String] = []
    @Published private(set) var isLLMConnectionTestRunning: Bool = false
    @Published private(set) var isLLMModelRefreshRunning: Bool = false
    @Published var llmConfigurationFeedback: String?
    @Published var llmConfigurationFeedbackKind: LLMConfigurationFeedbackKind = .neutral
    @Published var autoDictationLLMServiceSource: LLMServiceSource = AppState.defaultLLMServiceSource(
        storageKey: AppState.autoDictationLLMProviderSourceStorageKey
    ) {
        didSet {
            UserDefaults.standard.set(
                autoDictationLLMServiceSource.rawValue,
                forKey: Self.autoDictationLLMProviderSourceStorageKey
            )
            llmAvailableModels = []
            llmConfigurationFeedback = nil
            llmConfigurationFeedbackKind = .neutral
            syncLLMProviderConfiguration()
        }
    }

    @Published var fullTextRewriteLLMServiceSource: LLMServiceSource = AppState.defaultLLMServiceSource(
        storageKey: AppState.fullTextRewriteLLMProviderSourceStorageKey
    ) {
        didSet {
            UserDefaults.standard.set(
                fullTextRewriteLLMServiceSource.rawValue,
                forKey: Self.fullTextRewriteLLMProviderSourceStorageKey
            )
            llmAvailableModels = []
            llmConfigurationFeedback = nil
            llmConfigurationFeedbackKind = .neutral
            syncLLMProviderConfiguration()
        }
    }

    @Published var llmEndpointText: String = AppState.defaultLLMEndpointText() {
        didSet {
            let trimmed = llmEndpointText.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed != llmEndpointText {
                llmEndpointText = trimmed
                return
            }
            if trimmed.isEmpty {
                UserDefaults.standard.removeObject(forKey: Self.llmEndpointStorageKey)
            } else {
                UserDefaults.standard.set(trimmed, forKey: Self.llmEndpointStorageKey)
            }
            llmAvailableModels = []
            llmConfigurationFeedback = nil
            llmConfigurationFeedbackKind = .neutral
            syncLLMProviderConfiguration()
        }
    }

    @Published var llmModelText: String = AppState.defaultLLMModelText() {
        didSet {
            let trimmed = llmModelText.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed != llmModelText {
                llmModelText = trimmed
                return
            }
            if trimmed.isEmpty {
                UserDefaults.standard.removeObject(forKey: Self.llmModelStorageKey)
            } else {
                UserDefaults.standard.set(trimmed, forKey: Self.llmModelStorageKey)
            }
            llmConfigurationFeedback = nil
            llmConfigurationFeedbackKind = .neutral
            syncLLMProviderConfiguration()
        }
    }

    @Published var llmAPIKey: String = AppState.defaultLLMAPIKey() {
        didSet {
            let trimmed = llmAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed != llmAPIKey {
                llmAPIKey = trimmed
                return
            }
            if trimmed.isEmpty {
                Self.removeStoredLLMAPIKey()
            } else {
                Self.saveStoredLLMAPIKey(trimmed)
            }
            llmAvailableModels = []
            llmConfigurationFeedback = nil
            llmConfigurationFeedbackKind = .neutral
            syncLLMProviderConfiguration()
        }
    }

    @Published var asrExpertProfile: ASRExpertProfile = AppState.loadASRExpertProfile() {
        didSet {
            AppState.saveASRExpertProfile(asrExpertProfile)
            llmConfigurationFeedback = nil
            llmConfigurationFeedbackKind = .neutral
            syncLLMProviderConfiguration()
        }
    }
    
    @Published var alwaysListeningWakeWindowSeconds: Double = UserDefaults.standard.object(forKey: "alwaysListeningWakeWindowSeconds") as? Double ?? VoiceDefaults.alwaysListeningWakeWindowSeconds {
        didSet {
            let clamped = min(
                max(alwaysListeningWakeWindowSeconds, VoiceDefaults.minAlwaysListeningWakeWindowSeconds),
                VoiceDefaults.maxAlwaysListeningWakeWindowSeconds
            )
            if clamped != alwaysListeningWakeWindowSeconds {
                alwaysListeningWakeWindowSeconds = clamped
                return
            }
            UserDefaults.standard.set(clamped, forKey: "alwaysListeningWakeWindowSeconds")
        }
    }
    @Published var isAutoDictationEnhancementEnabled: Bool = {
        if UserDefaults.standard.object(forKey: AppState.autoDictationEnhancementStorageKey) != nil {
            return UserDefaults.standard.bool(forKey: AppState.autoDictationEnhancementStorageKey)
        }
        if UserDefaults.standard.object(forKey: AppState.legacyLLMEnhancementStorageKey) != nil {
            return UserDefaults.standard.bool(forKey: AppState.legacyLLMEnhancementStorageKey)
        }
        return false
    }() {
        didSet {
            UserDefaults.standard.set(
                isAutoDictationEnhancementEnabled,
                forKey: Self.autoDictationEnhancementStorageKey
            )
            voiceService.setAutoDictationEnhancementEnabled(isAutoDictationEnhancementEnabled)
        }
    }

    @Published var isFullTextRewriteEnabled: Bool = {
        if UserDefaults.standard.object(forKey: AppState.fullTextRewriteStorageKey) != nil {
            return UserDefaults.standard.bool(forKey: AppState.fullTextRewriteStorageKey)
        }
        if UserDefaults.standard.object(forKey: AppState.legacyLLMEnhancementStorageKey) != nil {
            return UserDefaults.standard.bool(forKey: AppState.legacyLLMEnhancementStorageKey)
        }
        return false
    }() {
        didSet {
            UserDefaults.standard.set(
                isFullTextRewriteEnabled,
                forKey: Self.fullTextRewriteStorageKey
            )
            voiceService.setFullTextRewriteEnabled(isFullTextRewriteEnabled)
        }
    }

    @Published var permissionStage: PermissionSetupStage = .done
    
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
    let licenseManager = AetherLicenseManager.shared
    private let permissions = PermissionsService()

    private var windowController: NSWindowController?
    private var cancellables = Set<AnyCancellable>()
    private var hasShownAccessibilityHint: Bool = false
    private var hasRequestedAccessibilityPromptThisRun: Bool = false
    private var lastObservedAccessibilityTrusted: Bool?
    private var accessibilityRecoveryTimer: Timer?

    var entitlementGateState: AetherEntitlementGateState {
        licenseManager.gateState
    }

    var isProductUnlocked: Bool {
        licenseManager.isProductUnlocked
    }

    private var preferredLLMConfigurationTestSource: LLMServiceSource {
        if autoDictationLLMServiceSource == .openAICompatible || fullTextRewriteLLMServiceSource == .openAICompatible {
            return .openAICompatible
        }
        return .appleOnDevice
    }

    private func makeConfiguredLLMProviderConfiguration(for source: LLMServiceSource) -> LLMProviderConfiguration? {
        switch source {
        case .appleOnDevice:
            guard appleOnDeviceLLMAvailability == .available else { return nil }
            return .appleOnDevice(
                AppleOnDeviceLLMConfig(
                    rewriteProfile: asrExpertProfile,
                    contextualGlossaryText: nil,
                    localeIdentifier: voiceService.effectiveLocaleIdentifier
                )
            )
        case .openAICompatible:
            guard let config = OpenAICompatibleProvider.makeConfig(
                endpointString: llmEndpointText,
                apiKey: llmAPIKey,
                model: llmModelText,
                rewriteProfile: asrExpertProfile
            ) else {
                return nil
            }
            return .openAICompatible(config)
        }
    }

    private func makeConfiguredLLMProvider(for source: LLMServiceSource) -> LLMHealthCheckProvider? {
        guard let configuration = makeConfiguredLLMProviderConfiguration(for: source) else {
            return nil
        }

        switch configuration {
        case .appleOnDevice(let config):
            return AppleOnDeviceLLMProviderFactory.makeProvider(config: config)
        case .openAICompatible(let config):
            return OpenAICompatibleProvider(config: config)
        }
    }

    private func makeModelDiscoveryLLMProvider() -> OpenAICompatibleProvider? {
        let endpoint = llmEndpointText.trimmingCharacters(in: .whitespacesAndNewlines)
        let apiKey = llmAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !endpoint.isEmpty,
              let endpointURL = URL(string: endpoint),
              !apiKey.isEmpty else {
            return nil
        }
        let model = llmModelText.trimmingCharacters(in: .whitespacesAndNewlines)
        return OpenAICompatibleProvider(
            config: OpenAICompatibleProvider.Config(
                endpoint: endpointURL,
                apiKey: apiKey,
                model: model.isEmpty ? "model-discovery" : model,
                rewriteProfile: nil
            )
        )
    }

    private func syncLLMProviderConfiguration() {
        voiceService.setLLMProviderConfiguration(
            dictationConfig: makeConfiguredLLMProviderConfiguration(for: autoDictationLLMServiceSource),
            dictationSource: autoDictationLLMServiceSource,
            rewriteConfig: makeConfiguredLLMProviderConfiguration(for: fullTextRewriteLLMServiceSource),
            rewriteSource: fullTextRewriteLLMServiceSource
        )
    }

    func testLLMProviderConfiguration() async {
        let source = preferredLLMConfigurationTestSource
        guard let provider = makeConfiguredLLMProvider(for: source) else {
            llmConfigurationFeedbackKind = .warning
            switch llmConfigurationState(for: source) {
            case .appleOnDeviceUnavailable:
                llmConfigurationFeedback = appleOnDeviceLLMAvailability.detail(
                    isChinese: isChineseUI,
                    localeName: activeSpeechLocaleDisplayName
                )
            case .missingAPIKey:
                llmConfigurationFeedback = isChineseUI ? "请先填写 API Key" : "Add an API key first"
            case .missingModel:
                llmConfigurationFeedback = isChineseUI ? "请先填写模型名" : "Add a model name first"
            case .invalidEndpoint:
                llmConfigurationFeedback = isChineseUI ? "请先修正 Endpoint" : "Fix the endpoint first"
            case .ready:
                llmConfigurationFeedback = nil
            }
            return
        }

        isLLMConnectionTestRunning = true
        llmConfigurationFeedback = source == .appleOnDevice
            ? (isChineseUI ? "正在检查 Apple 本地模型…" : "Checking the Apple on-device model...")
            : (isChineseUI ? "正在测试连接…" : "Testing connection...")
        llmConfigurationFeedbackKind = .neutral
        defer { isLLMConnectionTestRunning = false }

        do {
            try await provider.testConfiguration()
            llmConfigurationFeedback = source == .appleOnDevice
                ? (isChineseUI ? "Apple 本地模型可用" : "The Apple on-device model is available.")
                : (isChineseUI ? "连接成功，当前模型可用" : "Connection succeeded. The configured model is available.")
            llmConfigurationFeedbackKind = .success
        } catch {
            llmConfigurationFeedback = error.localizedDescription
            llmConfigurationFeedbackKind = .error
        }
    }

    func refreshLLMAvailableModels() async {
        guard preferredLLMConfigurationTestSource == .openAICompatible else {
            llmConfigurationFeedbackKind = .neutral
            llmConfigurationFeedback = isChineseUI
                ? "Apple 本地模式不需要拉取模型列表。"
                : "Apple on-device mode does not need model discovery."
            return
        }

        guard let provider = makeModelDiscoveryLLMProvider() else {
            llmConfigurationFeedbackKind = .warning
            if llmAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                llmConfigurationFeedback = isChineseUI ? "先填 API Key 才能拉取模型列表" : "Add an API key before fetching models"
            } else {
                llmConfigurationFeedback = isChineseUI ? "请先修正 Endpoint" : "Fix the endpoint before fetching models"
            }
            return
        }

        isLLMModelRefreshRunning = true
        llmConfigurationFeedback = isChineseUI ? "正在获取模型列表…" : "Loading models..."
        llmConfigurationFeedbackKind = .neutral
        defer { isLLMModelRefreshRunning = false }

        do {
            let models = try await provider.fetchAvailableModels()
            llmAvailableModels = models
            if llmModelText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               let first = models.first {
                llmModelText = first
            }
            llmConfigurationFeedback = isChineseUI
                ? "已获取 \(models.count) 个模型"
                : "Loaded \(models.count) models"
            llmConfigurationFeedbackKind = .success
        } catch {
            llmAvailableModels = []
            llmConfigurationFeedback = error.localizedDescription
            llmConfigurationFeedbackKind = .error
        }
    }

    
    init() {
        CurrentAppShortcutPanelManager.shared.appState = self
        installScreenLockObservers()
        refreshScreenLockState()

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

        licenseManager.$gateState
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.objectWillChange.send()
                self?.syncProductAccessGate()
            }
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
        
        voiceService.setAutoDictationEnhancementEnabled(self.isAutoDictationEnhancementEnabled)
        voiceService.setFullTextRewriteEnabled(self.isFullTextRewriteEnabled)
        syncLLMProviderConfiguration()
        voiceService.setDeveloperSpeechProfileEnabled(self.isDeveloperSpeechProfileEnabled)
        voiceService.setVoiceCommandOverrides(self.voiceCommandOverrides)
        voiceService.setVoiceLanguageTermsOverrides(self.voiceLanguageTermsOverrides)
        voiceService.setCustomAppShortcutRules(self.customAppShortcutRules)
        voiceService.setCustomAppLaunchAliasRules(self.customAppLaunchAliasRules)
        motionService.setTrackingExecutionEnabled { [weak self] in
            self?.isProductUnlocked ?? false
        }
        motionService.setTrackingExecutionDeniedHandler { [weak self] in
            self?.presentActivationRequiredFeedback()
        }

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


        voiceService.onIntent = { [weak self] intent, appName, bundleIdentifier, spokenText, originalContent, enhancedContent, diagnostics, wakeFollowUpGroupID in
            guard let self else { return }
            DispatchQueue.main.async {
                guard !self.isScreenLocked else { return }
                guard self.isProductUnlocked else {
                    self.presentActivationRequiredFeedback()
                    return
                }
                guard !self.isIdlePaused else { return }
                self.applyVoiceIntent(
                    intent,
                    appName: appName,
                    bundleIdentifier: bundleIdentifier,
                    spokenText: spokenText,
                    originalContent: originalContent,
                    enhancedContent: enhancedContent,
                    diagnostics: diagnostics,
                    wakeFollowUpGroupID: wakeFollowUpGroupID
                )
            }
        }
        voiceService.isDictationExecutionEnabled = { [weak self] in
            guard let self else { return false }
            return Self.shouldAllowVoiceFeature(
                isScreenLocked: self.isScreenLocked,
                isProductUnlocked: self.isProductUnlocked,
                isFeatureEnabled: self.isVoiceInputEnabled,
                isIdlePaused: self.isIdlePaused
            )
        }
        voiceService.isCommandExecutionEnabled = { [weak self] in
            guard let self else { return false }
            return Self.shouldAllowVoiceFeature(
                isScreenLocked: self.isScreenLocked,
                isProductUnlocked: self.isProductUnlocked,
                isFeatureEnabled: self.isVoiceControlEnabled,
                isIdlePaused: self.isIdlePaused
            )
        }
        voiceService.isAppIdlePaused = { [weak self] in
            self?.isIdlePaused ?? false
        }
        voiceService.onIdlePauseResumeRequest = { [weak self] source in
            guard let self, self.isIdlePaused else { return }
            _ = HeadMotionManager.shared.requestIdlePauseResume(source: source)
        }
        
        voiceService.onRecognitionFailure = { [weak self] transcript, reason, appName, bundleIdentifier in
            guard let self else { return }
            DispatchQueue.main.async {
                guard !self.isScreenLocked else { return }
                let trimmed = transcript?.trimmingCharacters(in: .whitespacesAndNewlines)
                let content = (trimmed?.isEmpty == false) ? trimmed : nil
                self.recordVoiceFailure(content, reason: reason, appName: appName, bundleIdentifier: bundleIdentifier)
            }
        }

        voiceService.onWakeAnalyticsSignal = { [weak self] signal in
            guard let self else { return }
            DispatchQueue.main.async {
                guard !self.isScreenLocked else { return }
                switch signal {
                case .hit(let groupID, let phrase, let localeIdentifier):
                    self.recordWakeHit(groupID: groupID, phrase: phrase, localeIdentifier: localeIdentifier)
                case .converted(let groupID, let followUp, let phrase, let localeIdentifier, let transcript):
                    self.recordWakeConversion(
                        groupID: groupID,
                        followUp: followUp,
                        phrase: phrase,
                        localeIdentifier: localeIdentifier,
                        transcript: transcript
                    )
                case .empty(let groupID, let phrase, let localeIdentifier):
                    self.recordWakeEmpty(groupID: groupID, phrase: phrase, localeIdentifier: localeIdentifier)
                case .miss(let phase, let reason, let phrase, let localeIdentifier, let transcript):
                    self.recordWakeMiss(
                        phase: phase,
                        reason: reason,
                        phrase: phrase,
                        localeIdentifier: localeIdentifier,
                        transcript: transcript
                    )
                }
            }
        }

        HeadMotionManager.shared.onIdlePauseStateChanged = { [weak self] paused in
            self?.applyIdlePauseState(paused)
        }
        HeadMotionManager.shared.$isGloballyPausedForIdle
            .receive(on: DispatchQueue.main)
            .sink { [weak self] paused in
                self?.applyIdlePauseState(paused)
            }
            .store(in: &cancellables)

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
            self.permissionStage = Self.derivePermissionStage(
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

        NotificationCenter.default.publisher(for: .toggleShortcutPanel)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.toggleShortcutPanel()
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .exportFocusedInputDiagnostics)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                do {
                    _ = try self.voiceService.exportFocusedInputDiagnostics()
                    HUDManager.shared.showTemporary(
                        message: AppLocalization.isChinese
                            ? "已导出输入框诊断"
                            : "Input diagnostics exported",
                        icon: "waveform.path.ecg"
                    )
                } catch {
                    HUDManager.shared.showTemporary(
                        message: AppLocalization.isChinese
                            ? "导出输入框诊断失败"
                            : "Couldn't export input diagnostics",
                        icon: "xmark.circle.fill"
                    )
                }
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

        syncProductAccessGate()
        refreshPermissions()
        continuePendingPermissionRecoveryIfNeeded()
    }

    private func syncProductAccessGate() {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in
                self?.syncProductAccessGate()
            }
            return
        }

        if isProductUnlocked {
            applyVoiceEnabledState()
            return
        }

        if motionService.isTracking {
            motionService.stopTracking()
        }

        voiceService.setPTTEnabled(false)
        voiceService.setAlwaysListeningEnabled(false)
        voiceService.setDirectCommandEnabled(false)
        voiceService.setWakeWordEnabled(false)
        voiceService.syncHUDState()
        HotkeyManager.shared.unregisterPTT()
        HeadMotionManager.shared.isPTTEnabled = false
        CurrentAppShortcutPanelManager.shared.hide()
    }

    private func presentActivationRequiredFeedback() {
        let message: String
        switch entitlementGateState {
        case .expired:
            message = AppLocalization.isChinese ? "授权已过期，请先恢复激活。" : "Your access has expired. Restore activation first."
        case .deviceLimitReached:
            message = AppLocalization.isChinese ? "设备数已满，请先移除旧设备。" : "Device limit reached. Remove an old device first."
        case .loading:
            message = AppLocalization.isChinese ? "正在验证授权，请稍候。" : "Checking access. Please wait."
        case .inactive:
            message = AppLocalization.isChinese ? "请先激活或开始试用。" : "Activate or start a trial first."
        case .active, .trialing:
            return
        }

        HUDManager.shared.showTemporary(
            message: message,
            icon: "lock.shield.fill"
        )
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

    private static func derivePermissionStage(
        accessibilityTrusted: Bool,
        microphoneAuthorized: Bool,
        speechAuthorized: Bool
    ) -> PermissionSetupStage {
        if !accessibilityTrusted { return .accessibility }
        if !microphoneAuthorized { return .microphone }
        if !speechAuthorized { return .speech }
        return .done
    }

    private func installScreenLockObservers() {
        let distributedCenter = DistributedNotificationCenter.default()
        screenLockObserverTokens.append(
            distributedCenter.addObserver(
                forName: Self.screenIsLockedNotificationName,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.setScreenLocked(true)
                }
            }
        )
        screenLockObserverTokens.append(
            distributedCenter.addObserver(
                forName: Self.screenIsUnlockedNotificationName,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.setScreenLocked(false)
                }
            }
        )

        let workspaceCenter = NSWorkspace.shared.notificationCenter
        workspaceObserverTokens.append(
            workspaceCenter.addObserver(
                forName: NSWorkspace.didActivateApplicationNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.refreshScreenLockState()
                }
            }
        )
    }

    private func refreshScreenLockState() {
        let frontmostBundleIdentifier = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        setScreenLocked(Self.isScreenLocked(frontmostBundleIdentifier: frontmostBundleIdentifier))
    }

    private func setScreenLocked(_ locked: Bool) {
        guard locked != isScreenLocked else { return }
        isScreenLocked = locked
    }

    static func isScreenLocked(frontmostBundleIdentifier: String?) -> Bool {
        frontmostBundleIdentifier == loginWindowBundleIdentifier
    }

    static func shouldAllowVoiceIntent(
        isScreenLocked: Bool,
        isProductUnlocked: Bool,
        isIdlePaused: Bool
    ) -> Bool {
        isProductUnlocked && !isScreenLocked && !isIdlePaused
    }

    static func shouldAllowVoiceFeature(
        isScreenLocked: Bool,
        isProductUnlocked: Bool,
        isFeatureEnabled: Bool,
        isIdlePaused: Bool
    ) -> Bool {
        isProductUnlocked && isFeatureEnabled && !isScreenLocked && !isIdlePaused
    }

    func finishCalibration() {
        motionService.finishCalibration()
    }
    
    func toggleMotionTracking() {
        guard !isIdlePaused else { return }
        if isMotionTracking {
            motionService.stopTracking()
        } else {
            motionService.startTracking()
        }
    }

    private func applyIdlePauseState(_ paused: Bool) {
        guard paused != isIdlePaused else { return }
        isIdlePaused = paused
        GlobalLogger.lifecycle.info(
            "[IdlePause] app state paused=\(paused) voiceMode=\(voiceActivationMode.rawValue) voiceEnabled=\(isVoiceEnabled)"
        )
        if paused {
            CurrentAppShortcutPanelManager.shared.hide()
            didSuspendVoiceRuntimeForIdlePause = voiceActivationMode != .wakeWord
            voiceService.setIdlePauseSuspended(didSuspendVoiceRuntimeForIdlePause)
            voiceService.syncHUDState()
            return
        }

        if didSuspendVoiceRuntimeForIdlePause,
           isProductUnlocked && !isScreenLocked && isVoiceEnabled {
            applyVoiceActivationMode()
        }
        didSuspendVoiceRuntimeForIdlePause = false
        voiceService.setIdlePauseSuspended(false)
        voiceService.syncHUDState()
    }

    func showShortcutPanel(activateApp: Bool = true, focusSearchField: Bool = true) {
        guard !isIdlePaused else { return }
        guard isProductUnlocked else {
            presentActivationRequiredFeedback()
            return
        }
        CurrentAppShortcutPanelManager.shared.show(activateApp: activateApp, focusSearchField: focusSearchField)
    }

    func hideShortcutPanel() {
        CurrentAppShortcutPanelManager.shared.hide()
    }

    func toggleShortcutPanel(activateApp: Bool = true, focusSearchField: Bool = true) {
        guard !isIdlePaused else { return }
        guard isProductUnlocked else {
            presentActivationRequiredFeedback()
            return
        }
        CurrentAppShortcutPanelManager.shared.toggle(activateApp: activateApp, focusSearchField: focusSearchField)
    }

    func toggleRecognitionInputControlMode() {
        guard !isIdlePaused else { return }
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
        bundleIdentifier: String? = nil,
        spokenText: String? = nil,
        originalContent: String? = nil,
        enhancedContent: String? = nil,
        diagnostics: String? = nil,
        wakeFollowUpGroupID: String? = nil
    ) {
        guard !isIdlePaused else { return }
        func recordControl(_ intent: VoiceIntent, appName: String? = appName, bundleIdentifier: String? = bundleIdentifier) {
            recordVoiceControl(intent, spokenText: spokenText, appName: appName, bundleIdentifier: bundleIdentifier)
        }
        GlobalLogger.lifecycle.info("[VoiceIntent] execute \(voiceIntentActionTitle(intent))")
        switch intent {
        case .clickLeft:
            GlobalLogger.lifecycle.info("[VoiceIntent] action=clickLeft")
            motionService.clickLeft()
            recordControl(intent)
        case .clickRight:
            GlobalLogger.lifecycle.info("[VoiceIntent] action=clickRight")
            motionService.clickRight()
            recordControl(intent)
        case .doubleClick:
            GlobalLogger.lifecycle.info("[VoiceIntent] action=doubleClick")
            motionService.doubleClick()
            recordControl(intent)
        case .toggleInputControlMode:
            GlobalLogger.lifecycle.info("[VoiceIntent] action=toggleInputControlMode")
            toggleRecognitionInputControlMode()
            recordControl(intent)
        case .toggleTracking:
            GlobalLogger.lifecycle.info("[VoiceIntent] action=toggleTracking")
            toggleMotionTracking()
            recordControl(intent)
        case .toggleLanguage:
            GlobalLogger.lifecycle.info("[VoiceIntent] action=toggleLanguage")
            guard isVoiceControlEnabled else { return }
            NotificationCenter.default.post(name: Notification.Name("AetherToggleLanguage"), object: nil)
            recordControl(intent)
        case .toggleShortcutPanel:
            GlobalLogger.lifecycle.info("[VoiceIntent] action=toggleShortcutPanel")
            toggleShortcutPanel(activateApp: false, focusSearchField: false)
            recordControl(intent)
        case .mediaPlayPause:
            GlobalLogger.lifecycle.info("[VoiceIntent] action=mediaPlayPause")
            nowPlayingService.togglePlayPause()
            recordControl(
                intent,
                appName: nowPlayingAppName.isEmpty ? nil : nowPlayingAppName,
                bundleIdentifier: nowPlayingBundleIdentifier.isEmpty ? nil : nowPlayingBundleIdentifier
            )
        case .mediaPrevious:
            GlobalLogger.lifecycle.info("[VoiceIntent] action=mediaPrevious")
            nowPlayingService.previousTrack()
            recordControl(
                intent,
                appName: nowPlayingAppName.isEmpty ? nil : nowPlayingAppName,
                bundleIdentifier: nowPlayingBundleIdentifier.isEmpty ? nil : nowPlayingBundleIdentifier
            )
        case .mediaNext:
            GlobalLogger.lifecycle.info("[VoiceIntent] action=mediaNext")
            nowPlayingService.nextTrack()
            recordControl(
                intent,
                appName: nowPlayingAppName.isEmpty ? nil : nowPlayingAppName,
                bundleIdentifier: nowPlayingBundleIdentifier.isEmpty ? nil : nowPlayingBundleIdentifier
            )
        case .showShortcutPanel:
            GlobalLogger.lifecycle.info("[VoiceIntent] action=showShortcutPanel")
            showShortcutPanel(activateApp: false, focusSearchField: false)
            recordControl(intent)
        case .hideShortcutPanel:
            GlobalLogger.lifecycle.info("[VoiceIntent] action=hideShortcutPanel")
            hideShortcutPanel()
            recordControl(intent)
        case .startPointer:
            GlobalLogger.lifecycle.info("[VoiceIntent] action=startPointer")
            motionService.startTracking()
            recordControl(intent)
        case .stopPointer:
            GlobalLogger.lifecycle.info("[VoiceIntent] action=stopPointer")
            motionService.stopTracking()
            recordControl(intent)
        case .recenter:
            GlobalLogger.lifecycle.info("[VoiceIntent] action=recenter")
            motionService.recenter()
            recordControl(intent)
        case .openApplication(let target):
            GlobalLogger.lifecycle.info("[VoiceIntent] action=openApplication app=\(target.displayName) bundle=\(target.bundleIdentifier)")
            openResolvedApplication(target)
            recordControl(
                intent,
                appName: target.displayName,
                bundleIdentifier: target.bundleIdentifier
            )
        case .frontmostAppCommand(let command):
            GlobalLogger.lifecycle.info("[VoiceIntent] action=frontmostAppCommand title=\(command.title) shortcut=\(command.shortcut.displayString) pid=\(command.processIdentifier)")
            let targetPID: pid_t? = command.isGlobalRule ? nil : command.processIdentifier
            AutomationOutputs.shared.pressShortcut(command.shortcut, targetPID: targetPID)
            recordControl(
                intent,
                appName: command.appName,
                bundleIdentifier: command.bundleIdentifier
            )
        case .scroll(let dx, let dy):
            GlobalLogger.lifecycle.info("[VoiceIntent] action=scroll dx=\(dx) dy=\(dy)")
            motionService.scroll(dx: dx, dy: dy)
            recordControl(intent)
        case .scrollToWeb(let edge):
            GlobalLogger.lifecycle.info("[VoiceIntent] action=scrollToWeb edge=\(edge)")
            if edge == "top" { motionService.scrollToTop() }
            else { motionService.scrollToBottom() }
            recordControl(intent)
        case .dragStart:
            GlobalLogger.lifecycle.info("[VoiceIntent] action=dragStart")
            motionService.dragStart()
            recordControl(intent)
        case .dragEnd:
            GlobalLogger.lifecycle.info("[VoiceIntent] action=dragEnd")
            motionService.dragEnd()
            recordControl(intent)
        case .undo:
            GlobalLogger.lifecycle.info("[VoiceIntent] action=undo")
            // Already applied inside SpeechManager. Keep this branch for usage tracking only.
            recordControl(intent)
        case .paste:
            GlobalLogger.lifecycle.info("[VoiceIntent] action=paste")
            // Already applied inside SpeechManager. Keep this branch for usage tracking only.
            recordControl(intent)
        case .clearInput:
            GlobalLogger.lifecycle.info("[VoiceIntent] action=clearInput")
            // Already applied inside SpeechManager. Keep this branch for usage tracking only.
            recordControl(intent)
        case .deleteBackward(let count):
            GlobalLogger.lifecycle.info("[VoiceIntent] action=deleteBackward count=\(count)")
            // Already applied inside SpeechManager. Keep this branch for usage tracking only.
            recordControl(intent)
        case .moveCursorHorizontally(let offset):
            GlobalLogger.lifecycle.info("[VoiceIntent] action=moveCursorHorizontally offset=\(offset)")
            // Already applied inside SpeechManager. Keep this branch for usage tracking only.
            recordControl(intent)
        case .selectHorizontally(let offset):
            GlobalLogger.lifecycle.info("[VoiceIntent] action=selectHorizontally offset=\(offset)")
            // Already applied inside SpeechManager. Keep this branch for usage tracking only.
            recordControl(intent)
        case .rewriteText(let payload):
            GlobalLogger.lifecycle.info("[VoiceIntent] action=rewriteText scope=\(payload.scope.rawValue) mode=\(payload.mode.rawValue)")
            recordVoiceRewrite(payload, spokenText: spokenText, appName: appName, bundleIdentifier: bundleIdentifier)
        case .dictation(let text):
            GlobalLogger.lifecycle.info("[VoiceIntent] action=dictation text=\(text)")
            let inputControlState = InputControlArbiter.shared.currentSnapshot.interactionState
            if inputControlState != .typing {
                GlobalLogger.lifecycle.info("[VoiceIntent] hud_control_mismatch text=\(text)")
                recordVoiceDictationWhileHUDControl(
                    text,
                    originalContent: originalContent,
                    spokenText: spokenText,
                    enhancedContent: enhancedContent,
                    diagnostics: diagnostics,
                    wakeFollowUpGroupID: wakeFollowUpGroupID,
                    appName: appName,
                    bundleIdentifier: bundleIdentifier
                )
            } else {
                recordVoiceDictation(
                    text,
                    originalContent: originalContent,
                    spokenText: spokenText,
                    enhancedContent: enhancedContent,
                    diagnostics: diagnostics,
                    wakeFollowUpGroupID: wakeFollowUpGroupID,
                    appName: appName,
                    bundleIdentifier: bundleIdentifier
                )
            }
        case .unknown:
            GlobalLogger.lifecycle.info("[VoiceIntent] action=unknown")
            if case .unknown(let transcript) = intent {
                let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
                let isControlLike = InputControlArbiter.shared.currentSnapshot.interactionState != .typing
                let localeIdentifier = voiceService.effectiveLocaleIdentifier
                if !trimmed.isEmpty, !isControlLike {
                    recordVoiceUnrecognized(
                        trimmed,
                        localeIdentifier: localeIdentifier,
                        appName: appName,
                        bundleIdentifier: bundleIdentifier
                    )
                } else if !trimmed.isEmpty {
                    recordVoiceUnknownCommand(
                        trimmed,
                        localeIdentifier: localeIdentifier,
                        appName: appName,
                        bundleIdentifier: bundleIdentifier
                    )
                } else {
                    recordControl(intent)
                }
            } else {
                recordControl(intent)
            }
        }
    }

    private func openResolvedApplication(_ target: AppLaunchTarget) {
        if let runningApp = NSWorkspace.shared.runningApplications.first(where: {
            $0.activationPolicy == .regular
                && ($0.bundleIdentifier?.caseInsensitiveCompare(target.bundleIdentifier) == .orderedSame)
        }) {
            _ = runningApp.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
            return
        }

        let appURL = target.launchPath
            .flatMap { path -> URL? in
                guard !path.isEmpty else { return nil }
                return URL(fileURLWithPath: path, isDirectory: true)
            }
            ?? NSWorkspace.shared.urlForApplication(withBundleIdentifier: target.bundleIdentifier)

        guard let appURL else {
            HUDManager.shared.showTemporary(
                message: AppLocalization.isChinese
                    ? "找不到 \(target.displayName)"
                    : "Couldn't find \(target.displayName)",
                icon: "xmark.circle.fill"
            )
            return
        }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: appURL, configuration: configuration) { _, error in
            guard let error else { return }
            DispatchQueue.main.async {
                GlobalLogger.lifecycle.error("[VoiceIntent] openApplication failed bundle=\(target.bundleIdentifier) error=\(error.localizedDescription)")
                HUDManager.shared.showTemporary(
                    message: AppLocalization.isChinese
                        ? "无法打开 \(target.displayName)"
                        : "Couldn't open \(target.displayName)",
                    icon: "xmark.circle.fill"
                )
            }
        }
    }

    private func recordVoiceControl(
        _ intent: VoiceIntent,
        spokenText: String? = nil,
        appName: String? = nil,
        bundleIdentifier: String? = nil
    ) {
        recordVoiceUsageEvent(
            kind: .control,
            action: voiceIntentActionTitle(intent),
            content: nil,
            spokenText: spokenText,
            appName: appName,
            bundleIdentifier: bundleIdentifier
        )
    }

    private func recordVoiceUnknownCommand(
        _ text: String,
        localeIdentifier: String,
        appName: String? = nil,
        bundleIdentifier: String? = nil
    ) {
        recordVoiceUsageEvent(
            kind: .control,
            action: NSLocalizedString("intent.unknown", comment: ""),
            content: Self.sanitizedWakeWordUsageContent(
                text,
                localeIdentifier: localeIdentifier,
                stripsWakeWord: voiceActivationMode == .wakeWord || isWakeWordEnabled,
                overrides: voiceLanguageTermsOverrides
            ),
            appName: appName,
            bundleIdentifier: bundleIdentifier,
            localeIdentifier: localeIdentifier
        )
    }

    private func dictationEventCode(from diagnostics: String?) -> String? {
        guard let diagnostics,
              diagnostics.hasPrefix("llm=") else {
            return nil
        }
        let value = diagnostics.dropFirst(4)
        guard !value.isEmpty else { return nil }
        return "dictation.llm.\(value)"
    }

    private func dictationEnhancementStatus(from diagnostics: String?) -> String? {
        guard let diagnostics,
              diagnostics.hasPrefix("llm=") else {
            return nil
        }
        return String(diagnostics.dropFirst(4))
    }

    private func normalizedDictationOriginalContent(
        _ originalContent: String?,
        committedText: String
    ) -> String? {
        guard let originalContent else { return nil }
        let trimmedOriginal = originalContent.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedCommitted = committedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedOriginal.isEmpty, trimmedOriginal != trimmedCommitted else {
            return nil
        }
        return originalContent
    }

    private func wakeFollowUpLocaleIdentifier(for groupID: String?) -> String? {
        guard let groupID else { return nil }
        return voiceUsageHistory.first(where: {
            $0.wakeGroupID == groupID && $0.kind == .activation
        })?.localeIdentifier
    }

    private func sanitizedWakeFollowUpContent(_ raw: String?, wakeGroupID: String?) -> String? {
        guard let wakeGroupID,
              let localeIdentifier = wakeFollowUpLocaleIdentifier(for: wakeGroupID) else {
            return raw
        }
        return Self.sanitizedWakeWordUsageContent(
            raw,
            localeIdentifier: localeIdentifier,
            stripsWakeWord: true,
            overrides: voiceLanguageTermsOverrides
        ) ?? raw
    }

    private func recordVoiceDictation(
        _ text: String,
        originalContent: String? = nil,
        spokenText: String? = nil,
        enhancedContent: String? = nil,
        diagnostics: String? = nil,
        wakeFollowUpGroupID: String? = nil,
        appName: String? = nil,
        bundleIdentifier: String? = nil
    ) {
        let recordedText = sanitizedWakeFollowUpContent(text, wakeGroupID: wakeFollowUpGroupID) ?? text
        let recordedOriginalContent = sanitizedWakeFollowUpContent(originalContent, wakeGroupID: wakeFollowUpGroupID)
        let recordedSpokenText = sanitizedWakeFollowUpContent(spokenText, wakeGroupID: wakeFollowUpGroupID)
        let recordedEnhancedContent = sanitizedWakeFollowUpContent(enhancedContent, wakeGroupID: wakeFollowUpGroupID)
        let localeIdentifier = wakeFollowUpLocaleIdentifier(for: wakeFollowUpGroupID)
        recordVoiceUsageEvent(
            kind: .dictation,
            action: AppLocalization.isChinese ? "输入" : "Dictation",
            content: recordedText,
            originalContent: normalizedDictationOriginalContent(recordedOriginalContent, committedText: recordedText),
            spokenText: recordedSpokenText,
            enhancedContent: normalizedVoiceUsageContent(recordedEnhancedContent),
            committedContent: normalizedVoiceUsageContent(recordedText),
            enhancementStatus: dictationEnhancementStatus(from: diagnostics),
            appName: appName,
            bundleIdentifier: bundleIdentifier,
            eventCode: dictationEventCode(from: diagnostics),
            wakeGroupID: wakeFollowUpGroupID,
            localeIdentifier: localeIdentifier
        )
    }
    
    private func recordVoiceDictationWhileHUDControl(
        _ text: String,
        originalContent: String? = nil,
        spokenText: String? = nil,
        enhancedContent: String? = nil,
        diagnostics: String? = nil,
        wakeFollowUpGroupID: String? = nil,
        appName: String? = nil,
        bundleIdentifier: String? = nil
    ) {
        let recordedText = sanitizedWakeFollowUpContent(text, wakeGroupID: wakeFollowUpGroupID) ?? text
        let recordedOriginalContent = sanitizedWakeFollowUpContent(originalContent, wakeGroupID: wakeFollowUpGroupID)
        let recordedSpokenText = sanitizedWakeFollowUpContent(spokenText, wakeGroupID: wakeFollowUpGroupID)
        let recordedEnhancedContent = sanitizedWakeFollowUpContent(enhancedContent, wakeGroupID: wakeFollowUpGroupID)
        let localeIdentifier = wakeFollowUpLocaleIdentifier(for: wakeFollowUpGroupID)
        recordVoiceUsageEvent(
            kind: .dictation,
            action: AppLocalization.isChinese ? "控制模式下输入" : "Dictation While HUD Control",
            content: recordedText,
            originalContent: normalizedDictationOriginalContent(recordedOriginalContent, committedText: recordedText),
            spokenText: recordedSpokenText,
            enhancedContent: normalizedVoiceUsageContent(recordedEnhancedContent),
            committedContent: normalizedVoiceUsageContent(recordedText),
            enhancementStatus: dictationEnhancementStatus(from: diagnostics),
            appName: appName,
            bundleIdentifier: bundleIdentifier,
            eventCode: dictationEventCode(from: diagnostics),
            wakeGroupID: wakeFollowUpGroupID,
            localeIdentifier: localeIdentifier
        )
    }

    private func recordVoiceRewrite(
        _ payload: TextRewriteIntentPayload,
        spokenText: String? = nil,
        appName: String? = nil,
        bundleIdentifier: String? = nil
    ) {
        guard let sourceText = payload.sourceText,
              let resultText = payload.resultText else {
            return
        }
        recordVoiceUsageEvent(
            kind: .dictation,
            action: payload.mode.actionTitle(isChinese: AppLocalization.isChinese),
            content: resultText,
            originalContent: sourceText,
            spokenText: spokenText,
            appName: appName,
            bundleIdentifier: bundleIdentifier,
            eventCode: "rewrite.\(payload.scope.rawValue).\(payload.mode.rawValue)",
            rewriteScope: payload.scope.rawValue,
            rewriteMode: payload.mode.rawValue
        )
    }
    
    private func recordVoiceUnrecognized(
        _ text: String,
        localeIdentifier: String,
        appName: String? = nil,
        bundleIdentifier: String? = nil
    ) {
        recordVoiceUsageEvent(
            kind: .dictation,
            action: AppLocalization.isChinese ? "未匹配" : "Unmatched",
            content: Self.sanitizedWakeWordUsageContent(
                text,
                localeIdentifier: localeIdentifier,
                stripsWakeWord: voiceActivationMode == .wakeWord || isWakeWordEnabled,
                overrides: voiceLanguageTermsOverrides
            ),
            appName: appName,
            bundleIdentifier: bundleIdentifier,
            localeIdentifier: localeIdentifier
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
            action = Self.localizedVoiceUsageAction("voice_usage.failure.dictation_disabled", fallback: "Voice Input Off")
        } else if reason == "no-speech-detected" {
            action = Self.localizedVoiceUsageAction("voice_usage.failure.no_speech", fallback: "No Speech Detected")
        } else if reason == "recognition-interrupted" {
            action = Self.localizedVoiceUsageAction("voice_usage.failure.interrupted", fallback: "Recognition Interrupted")
        } else if reason == "recognition-unavailable" {
            action = Self.localizedVoiceUsageAction("voice_usage.failure.unavailable", fallback: "Recognition Unavailable")
        } else if reason == "invalid-input-target" || reason == "post-injection-mismatch" {
            action = Self.localizedVoiceUsageAction("voice_usage.failure.injection_failed", fallback: "Input Failed")
        } else if reason == "post-injection-unverified" {
            action = Self.localizedVoiceUsageAction("voice_usage.failure.injection_unverified", fallback: "Input Unverified")
        } else {
            action = Self.localizedVoiceUsageAction("voice_usage.failure.recognition_failed", fallback: "Recognition Failed")
        }
        recordVoiceUsageEvent(
            kind: .dictation,
            action: action,
            content: text,
            appName: appName,
            bundleIdentifier: bundleIdentifier
        )
    }

    private func recordWakeHit(groupID: String, phrase: String?, localeIdentifier: String) {
        recordVoiceUsageEvent(
            kind: .activation,
            action: AppLocalization.isChinese ? "唤醒" : "Wake Hit",
            content: nil,
            appName: nil,
            bundleIdentifier: nil,
            eventCode: "wake.hit",
            wakeGroupID: groupID,
            wakePhrase: phrase,
            localeIdentifier: localeIdentifier
        )
    }

    private func recordWakeConversion(
        groupID: String,
        followUp: WakeAnalyticsFollowUpKind,
        phrase: String?,
        localeIdentifier: String,
        transcript: String?
    ) {
        let action: String
        let eventCode: String
        switch followUp {
        case .dictation:
            action = AppLocalization.isChinese ? "唤醒后输入" : "Wake to Dictation"
            eventCode = "wake.to_dictation"
        case .control:
            action = AppLocalization.isChinese ? "唤醒后控制" : "Wake to Control"
            eventCode = "wake.to_control"
        }

        recordVoiceUsageEvent(
            kind: .activation,
            action: action,
            content: Self.sanitizedWakeWordUsageContent(
                transcript,
                localeIdentifier: localeIdentifier,
                stripsWakeWord: true,
                overrides: voiceLanguageTermsOverrides
            ),
            appName: nil,
            bundleIdentifier: nil,
            eventCode: eventCode,
            wakeGroupID: groupID,
            wakePhrase: phrase,
            localeIdentifier: localeIdentifier
        )
    }

    private func recordWakeEmpty(groupID: String, phrase: String?, localeIdentifier: String) {
        recordVoiceUsageEvent(
            kind: .activation,
            action: AppLocalization.isChinese ? "空唤醒" : "Empty Wake",
            content: nil,
            appName: nil,
            bundleIdentifier: nil,
            eventCode: "wake.empty",
            wakeGroupID: groupID,
            wakePhrase: phrase,
            localeIdentifier: localeIdentifier
        )
    }

    private enum WakeMissDisposition {
        case trueMiss
        case followUpContent
        case lateAfterTimeout
    }

    private func wakeMissDisposition(
        phase: String,
        reason: WakeAnalyticsFailureReason,
        localeIdentifier: String
    ) -> WakeMissDisposition {
        guard reason == .noPhraseMatch, phase == "final-awake" else {
            return .trueMiss
        }

        guard let latestWakeEmpty = voiceUsageHistory.first(where: { event in
            event.kind == .activation
                && event.eventCode == "wake.empty"
                && (event.localeIdentifier == nil || event.localeIdentifier == localeIdentifier)
        }) else {
            return .followUpContent
        }

        let elapsed = Date().timeIntervalSince(latestWakeEmpty.timestamp)
        if elapsed >= 0, elapsed <= Self.wakeLateFollowUpWindowSeconds {
            return .lateAfterTimeout
        }
        return .followUpContent
    }

    private func recordWakeMiss(
        phase: String,
        reason: WakeAnalyticsFailureReason,
        phrase: String?,
        localeIdentifier: String,
        transcript: String?
    ) {
        let disposition = wakeMissDisposition(
            phase: phase,
            reason: reason,
            localeIdentifier: localeIdentifier
        )

        let action: String
        let eventCode: String
        let detail: String
        switch disposition {
        case .lateAfterTimeout:
            action = AppLocalization.isChinese ? "超时后补说" : "Late Follow-up"
            eventCode = "wake.followup.late"
            detail = AppLocalization.isChinese
                ? "唤醒窗口已结束，这句在超时后到达"
                : "The wake window had already ended before this follow-up arrived"
        case .followUpContent:
            action = AppLocalization.isChinese ? "后续语音" : "Follow-up Speech"
            eventCode = "wake.followup.content"
            detail = AppLocalization.isChinese
                ? "这句是唤醒后的后续语音，不是新的唤醒失败"
                : "This was follow-up speech after wake, not a new wake failure"
        case .trueMiss:
            action = AppLocalization.isChinese ? "唤醒失败" : "Wake Miss"
            eventCode = "wake.miss.\(reason.rawValue)"
            switch reason {
            case .belowThreshold:
                if let phrase, !phrase.isEmpty {
                    detail = AppLocalization.isChinese
                        ? "候选词“\(phrase)”接近唤醒词，但分数未过阈值"
                        : "Candidate '\(phrase)' was close, but stayed below the wake threshold"
                } else {
                    detail = AppLocalization.isChinese
                        ? "检测到接近唤醒词的候选，但分数未过阈值"
                        : "Detected a near wake candidate, but it stayed below the threshold"
                }
            case .phraseNotAtPrefix:
                if let phrase, !phrase.isEmpty {
                    detail = AppLocalization.isChinese
                        ? "检测到“\(phrase)”但不在句首"
                        : "Detected '\(phrase)', but it was not at the start of the utterance"
                } else {
                    detail = AppLocalization.isChinese
                        ? "检测到唤醒词，但不在句首"
                        : "Detected a wake phrase, but it was not at the start of the utterance"
                }
            case .prefixRejected:
                if let phrase, !phrase.isEmpty {
                    detail = AppLocalization.isChinese
                        ? "句首候选词“\(phrase)”未通过唤醒规则"
                        : "Leading candidate '\(phrase)' did not pass the wake matching rules"
                } else {
                    detail = AppLocalization.isChinese
                        ? "句首候选词未通过唤醒规则"
                        : "The leading candidate did not pass the wake matching rules"
                }
            case .noPhraseMatch:
                detail = AppLocalization.isChinese
                    ? "未检测到可用唤醒词"
                    : "No usable wake phrase was detected"
            }
        }

        recordVoiceUsageEvent(
            kind: .activation,
            action: action,
            content: detail,
            spokenText: transcript,
            appName: nil,
            bundleIdentifier: nil,
            eventCode: eventCode,
            wakePhrase: phrase,
            localeIdentifier: localeIdentifier
        )
    }

    private func recordVoiceUsageEvent(
        kind: VoiceUsageEventKind,
        action: String,
        content: String?,
        originalContent: String? = nil,
        spokenText: String? = nil,
        enhancedContent: String? = nil,
        committedContent: String? = nil,
        enhancementStatus: String? = nil,
        appName: String?,
        bundleIdentifier: String?,
        eventCode: String? = nil,
        wakeGroupID: String? = nil,
        wakePhrase: String? = nil,
        localeIdentifier: String? = nil,
        rewriteScope: String? = nil,
        rewriteMode: String? = nil
    ) {
        guard isVoiceUsageHistoryEnabled else { return }
        let context = resolvedVoiceUsageAppContext(appName: appName, bundleIdentifier: bundleIdentifier)
        let entry = VoiceUsageEvent(
            appName: context.name,
            bundleIdentifier: context.bundleIdentifier,
            kind: kind,
            action: action,
            content: normalizedVoiceUsageContent(content),
            originalContent: normalizedVoiceUsageContent(originalContent),
            spokenText: normalizedVoiceUsageContent(spokenText),
            enhancedContent: normalizedVoiceUsageContent(enhancedContent),
            committedContent: normalizedVoiceUsageContent(committedContent),
            enhancementStatus: normalizedVoiceUsageContent(enhancementStatus),
            eventCode: eventCode,
            wakeGroupID: wakeGroupID,
            wakePhrase: Self.normalizedWakePhrase(wakePhrase),
            localeIdentifier: normalizedVoiceUsageContent(localeIdentifier),
            rewriteScope: normalizedVoiceUsageContent(rewriteScope),
            rewriteMode: normalizedVoiceUsageContent(rewriteMode)
        )
        if kind == .activation {
            GlobalLogger.log(
                "[WakeAnalyticsStore] code=\(eventCode ?? "nil") group=\(wakeGroupID ?? "nil") phrase=\(entry.wakePhrase ?? "nil") locale=\(entry.localeIdentifier ?? "nil")",
                log: GlobalLogger.speech
            )
        }
        voiceUsageHistory.insert(entry, at: 0)
        storedVoiceUsageSummary = Self.updatedVoiceUsageSummary(storedVoiceUsageSummary, byAdding: entry)

        guard kind != .activation else { return }

        let currentAppSummary = storedVoiceUsageAppSummaries.first(where: { $0.bundleIdentifier == entry.bundleIdentifier })
            ?? VoiceUsageAppSummary(
                appName: entry.appName,
                bundleIdentifier: entry.bundleIdentifier,
                total: 0,
                dictationCount: 0,
                dictationCharacterCount: 0,
                failureCount: 0,
                unrecognizedCount: 0,
                mismatchCount: 0,
                controlCount: 0
            )
        let updatedAppSummary = Self.updatedVoiceUsageAppSummary(currentAppSummary, byAdding: entry)
        storedVoiceUsageAppSummaries = Self.sortVoiceUsageAppSummaries(
            storedVoiceUsageAppSummaries.filter { $0.bundleIdentifier != entry.bundleIdentifier } + [updatedAppSummary]
        )
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

    private static func normalizedVoiceUsageExcerpt(_ raw: String?) -> String? {
        guard var text = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
            return nil
        }
        text = text.replacingOccurrences(of: "\n", with: " ")
        if text.count > 280 {
            text = String(text.prefix(280)) + "…"
        }
        return text
    }

    private func normalizedVoiceUsageContent(_ raw: String?) -> String? {
        Self.normalizedVoiceUsageExcerpt(raw)
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
        case .toggleShortcutPanel: return String(localized: "hotkey.toggle_shortcut_panel")
        case .mediaPlayPause: return NSLocalizedString("intent.media_play_pause", comment: "")
        case .mediaPrevious: return NSLocalizedString("intent.media_previous", comment: "")
        case .mediaNext: return NSLocalizedString("intent.media_next", comment: "")
        case .showShortcutPanel: return NSLocalizedString("intent.show_shortcut_panel", comment: "")
        case .hideShortcutPanel: return NSLocalizedString("intent.hide_shortcut_panel", comment: "")
        case .startPointer: return NSLocalizedString("intent.start_pointer", comment: "")
        case .stopPointer: return NSLocalizedString("intent.stop_pointer", comment: "")
        case .recenter: return NSLocalizedString("intent.recenter", comment: "")
        case .openApplication(let target):
            return AppLocalization.isChinese ? "打开 \(target.displayName)" : "Open \(target.displayName)"
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
        case .moveCursorHorizontally(let offset):
            let count = abs(offset)
            if AppLocalization.isChinese {
                return offset >= 0 ? "向右移动\(count)个字" : "向左移动\(count)个字"
            }
            return offset >= 0 ? "Move right \(count) chars" : "Move left \(count) chars"
        case .selectHorizontally(let offset):
            let count = abs(offset)
            if AppLocalization.isChinese {
                return offset >= 0 ? "向右选择\(count)个字" : "向左选择\(count)个字"
            }
            return offset >= 0 ? "Select right \(count) chars" : "Select left \(count) chars"
        case .rewriteText(let payload):
            return payload.mode.actionTitle(isChinese: AppLocalization.isChinese)
        case .dictation: return NSLocalizedString("intent.dictation", comment: "")
        case .unknown: return NSLocalizedString("intent.unknown", comment: "")
        }
    }

    func refreshPermissions() { permissions.refresh() }
    func requestAccessibility() { permissions.requestAccessibility() }
    func requestMicrophone() { requestMicrophoneGuided() }
    func requestSpeech() { requestSpeechGuided() }
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
                requestMicrophoneGuided()
                return
            }
            if !speechAuthorized {
                requestSpeechGuided()
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

    private func performPermissionRequestAfterActivatingApp(_ action: @escaping () -> Void) {
        showMainWindow()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            action()
        }
    }

    func requestMicrophoneGuided() {
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        switch status {
        case .authorized:
            refreshPermissions()
        case .notDetermined:
            performPermissionRequestAfterActivatingApp { [weak self] in
                guard let self else { return }
                self.permissions.requestMicrophone()
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                    guard let self else { return }
                    self.refreshPermissions()
                }
            }
        case .denied, .restricted:
            permissions.openMicrophonePrivacyPane()
            refreshPermissions()
        @unknown default:
            permissions.openMicrophonePrivacyPane()
            refreshPermissions()
        }
    }

    func repairMicrophoneGuided() {
        Task { [weak self] in
            guard let self else { return }
            let didReset = await Self.resetTCCAsync(service: "Microphone")
            if didReset && self.relaunchForPermissionRecovery(.microphone) {
                return
            }
            self.requestMicrophoneGuided()
        }
    }

    func requestSpeechGuided() {
        let status = SFSpeechRecognizer.authorizationStatus()
        switch status {
        case .authorized:
            refreshPermissions()
        case .notDetermined:
            performPermissionRequestAfterActivatingApp { [weak self] in
                guard let self else { return }
                self.permissions.requestSpeech()
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                    guard let self else { return }
                    self.refreshPermissions()
                }
            }
        case .denied, .restricted:
            permissions.openSpeechPrivacyPane()
            refreshPermissions()
        @unknown default:
            permissions.openSpeechPrivacyPane()
            refreshPermissions()
        }
    }

    func repairSpeechGuided() {
        Task { [weak self] in
            guard let self else { return }
            let didReset = await Self.resetTCCAsync(service: "SpeechRecognition")
            if didReset && self.relaunchForPermissionRecovery(.speech) {
                return
            }
            self.requestSpeechGuided()
        }
    }

    private func continuePendingPermissionRecoveryIfNeeded() {
        guard let recovery = Self.pendingPermissionRecoveryFromLaunchArguments() else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            guard let self else { return }
            switch recovery {
            case .microphone:
                self.requestMicrophoneGuided()
            case .speech:
                self.requestSpeechGuided()
            }
        }
    }

    private func relaunchForPermissionRecovery(_ recovery: PendingPermissionRecovery) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = [
            "-n",
            Bundle.main.bundlePath,
            "--args",
            "\(Self.permissionRecoveryArgumentPrefix)\(recovery.rawValue)"
        ]

        do {
            try process.run()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                NSApp.terminate(nil)
            }
            return true
        } catch {
            return false
        }
    }

    private static func pendingPermissionRecoveryFromLaunchArguments() -> PendingPermissionRecovery? {
        guard let argument = CommandLine.arguments.first(where: { $0.hasPrefix(permissionRecoveryArgumentPrefix) }) else {
            return nil
        }
        let rawValue = String(argument.dropFirst(permissionRecoveryArgumentPrefix.count))
        return PendingPermissionRecovery(rawValue: rawValue)
    }

    nonisolated private static func resetTCCAsync(service: String) async -> Bool {
        await Task.detached(priority: .userInitiated) {
            resetTCC(service: service)
        }.value
    }

    nonisolated private static func resetTCC(service: String) -> Bool {
        let process = Process()
        let bundleIdentifier = Bundle.main.bundleIdentifier ?? "com.7fei.Aether"
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
        process.arguments = ["reset", service, bundleIdentifier]
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
            ? HotkeyAction.allCases.count
            : HotkeyAction.allCases.filter { $0 != .pushToTalk }.count
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
        let cardWidth: CGFloat = columnCount >= 3 ? 304 : 340
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
        if sectionCount >= 5 || totalCommands >= 24 { return 3 }
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
    @State private var isCloseButtonHovered: Bool = false
    @AppStorage("shortcutPanelHideUnavailable") private var hideUnavailableShortcuts: Bool = false

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
        let availabilityFiltered = sections.compactMap { section -> CurrentAppShortcutPanelSection? in
            let commands = hideUnavailableShortcuts
                ? section.commands.filter { $0.isEnabled }
                : section.commands
            guard !commands.isEmpty else { return nil }
            return CurrentAppShortcutPanelSection(title: section.title, commands: commands)
        }
        guard !normalizedSearchText.isEmpty else { return availabilityFiltered }
        return availabilityFiltered.compactMap { section -> CurrentAppShortcutPanelSection? in
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
            spacing: 18
        )
    }

    private var chromeBackground: Color {
        let base = colorScheme == .dark ? 0.24 : 0.10
        return Color.primary.opacity(isPanelFocused ? base : base * 1.15)
    }

    private var emptyStateBackground: Color {
        Color(nsColor: colorScheme == .dark ? .underPageBackgroundColor : .windowBackgroundColor).opacity(colorScheme == .dark ? 0.58 : 0.82)
    }

    var body: some View {
        ZStack {
            VisualEffectView(material: colorScheme == .dark ? .hudWindow : .popover, blendingMode: .behindWindow)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))

            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.white.opacity(colorScheme == .dark ? 0.12 : 0.28), lineWidth: 0.5)
                .shadow(color: .black.opacity(isPanelFocused ? 0.22 : 0.12), radius: isPanelFocused ? 18 : 10, y: isPanelFocused ? 9 : 5)

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
            .padding(24)
        }
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(alignment: .topLeading) {
            macCloseButton
                .padding(.leading, 18)
                .padding(.top, 18)
        }
        .opacity(isPanelFocused ? 1.0 : 0.96)
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
            .padding(.leading, 34)

            HStack(alignment: .center, spacing: 12) {
                let countStr = String.localizedStringWithFormat(NSLocalizedString("panels.shortcuts.count_fmt", comment: ""), totalVisibleShortcutCount)
                Text(countStr)
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        colorScheme == .dark
                            ? Color.white.opacity(0.12)
                            : Color(nsColor: .controlBackgroundColor).opacity(0.9)
                    )
                    .foregroundColor(Color(nsColor: .labelColor))
                    .clipShape(Capsule())

                Toggle(isOn: $hideUnavailableShortcuts) {
                    Text(isChinese ? "隐藏不可用项" : "Hide unavailable items")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.secondary)
                }
                .toggleStyle(.switch)
                .controlSize(.small)

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
            }

        }
    }

    private var macCloseButton: some View {
        Button {
            CurrentAppShortcutPanelManager.shared.hide()
        } label: {
            ZStack {
                Circle()
                    .fill(Color(red: 1.0, green: 0.37, blue: 0.33))
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(.black.opacity(isCloseButtonHovered ? 0.62 : 0.28))
            }
            .frame(width: 14, height: 14)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isCloseButtonHovered = hovering
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
                        .font(.system(size: 15, weight: .semibold))
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
        let targetPID: pid_t? = command.isGlobalRule ? nil : command.processIdentifier
        CurrentAppShortcutPanelManager.shared.hideAndRun(targetPID: targetPID) {
            AutomationOutputs.shared.pressShortcut(command.shortcut, targetPID: targetPID)
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
                    message: isChinese ? "按住说话请用快捷键" : "Use the hold-to-talk hotkey",
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
    private let rowSpacing: CGFloat = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 10) {
                Text(section.title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.secondary)
                Spacer(minLength: 8)
                Text("\(section.commands.count)")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.primary.opacity(colorScheme == .dark ? 0.05 : 0.04))
                    .clipShape(Capsule())
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 6)

            VStack(alignment: .leading, spacing: rowSpacing) {
                ForEach(Array(section.commands.enumerated()), id: \.element.id) { index, command in
                    CurrentAppShortcutRow(command: command, onTrigger: onTrigger)
                    if index != section.commands.count - 1 {
                        Divider()
                            .overlay(Color.primary.opacity(colorScheme == .dark ? 0.12 : 0.1))
                            .padding(.horizontal, 16)
                    }
                }
            }
            .padding(.bottom, 8)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

private struct AetherGlobalShortcutSectionCard: View {
    let entries: [AetherGlobalShortcutPanelEntry]
    let onTrigger: (AetherGlobalShortcutPanelEntry) -> Void
    @Environment(\.colorScheme) private var colorScheme
    private let rowSpacing: CGFloat = 0

    var body: some View {
        VStack(alignment: .leading, spacing: rowSpacing) {
            ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                AetherGlobalShortcutRow(entry: entry, onTrigger: onTrigger)
                if index != entries.count - 1 {
                    Divider()
                        .overlay(Color.primary.opacity(colorScheme == .dark ? 0.12 : 0.1))
                        .padding(.horizontal, 16)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(.vertical, 8)
    }
}

private struct AetherGlobalShortcutRow: View {
    let entry: AetherGlobalShortcutPanelEntry
    let onTrigger: (AetherGlobalShortcutPanelEntry) -> Void
    @State private var isHovered = false
    private let shortcutColumnWidth: CGFloat = 92

    var body: some View {
        Button {
            onTrigger(entry)
        } label: {
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    HoverMarqueeText(
                        text: entry.action.label,
                        font: .system(size: 16, weight: .medium),
                        color: isHovered ? Color(nsColor: .labelColor) : Color(nsColor: .labelColor),
                        isActive: isHovered,
                        height: 20
                    )
                    HoverMarqueeText(
                        text: entry.action.helperText,
                        font: .system(size: 13, weight: .regular),
                        color: isHovered ? Color(nsColor: .secondaryLabelColor) : Color(nsColor: .secondaryLabelColor),
                        isActive: isHovered,
                        gap: 24,
                        height: 17
                    )
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .layoutPriority(1)

                ShortcutBadgeView(binding: entry.binding, minWidth: shortcutColumnWidth, style: .compact)
                    .opacity(isHovered ? 0.98 : 1)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(isHovered ? Color.accentColor.opacity(0.14) : Color.clear)
            )
            .padding(.horizontal, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

private struct CurrentAppShortcutRow: View {
    let command: FrontmostAppCommand
    let onTrigger: (FrontmostAppCommand) -> Void
    @State private var isHovered = false
    private let shortcutColumnWidth: CGFloat = 92

    private var isChinese: Bool {
        AppLocalization.isChinese
    }

    private var submenuPath: String {
        guard command.menuPath.count > 1 else { return "" }
        return command.menuPath.dropFirst().joined(separator: " > ")
    }

    var body: some View {
        Button {
            onTrigger(command)
        } label: {
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                    HoverMarqueeText(
                        text: command.title,
                        font: .system(size: 16, weight: .medium),
                        color: isHovered ? (command.isEnabled ? Color(nsColor: .labelColor) : .secondary.opacity(0.8)) : (command.isEnabled ? Color(nsColor: .labelColor) : .secondary.opacity(0.8)),
                        isActive: isHovered,
                        height: 20
                    )
                        if !command.isEnabled {
                            Text(isChinese ? "灰置" : "Disabled")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.secondary.opacity(0.7))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(Color.primary.opacity(0.05))
                                .clipShape(Capsule())
                        }
                    }
                    HStack(alignment: .center, spacing: 8) {
                        if !submenuPath.isEmpty {
                            HoverMarqueeText(
                                text: submenuPath,
                                font: .system(size: 12, weight: .regular),
                                color: isHovered ? Color(nsColor: .secondaryLabelColor) : Color(nsColor: .secondaryLabelColor),
                                isActive: isHovered,
                                gap: 24,
                                height: 16
                            )
                        }
                        if !command.isEnabled {
                            Circle()
                                .fill(Color.secondary.opacity(0.3))
                                .frame(width: 4, height: 4)
                            Text(isChinese ? "当前菜单项不可点击" : "Currently disabled in app")
                                .font(.system(size: 12, weight: .regular))
                                .foregroundColor(.secondary.opacity(0.6))
                                .lineLimit(1)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .layoutPriority(1)

                ShortcutBadgeView(binding: command.shortcut, minWidth: shortcutColumnWidth, style: .compact)
                    .opacity(command.isEnabled ? (isHovered ? 0.98 : 1) : 0.55)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(isHovered ? Color.accentColor.opacity(0.14) : Color.clear)
            )
            .padding(.horizontal, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!command.isEnabled)
        .onHover { hovering in
            if command.isEnabled {
                isHovered = hovering
            }
        }
    }
}

private struct HoverMarqueeText: View {
    let text: String
    let font: Font
    let color: Color
    let isActive: Bool
    var gap: CGFloat = 32
    var height: CGFloat = 20

    @State private var containerWidth: CGFloat = 0
    @State private var contentWidth: CGFloat = 0
    @State private var animatedOffset: CGFloat = 0
    @State private var animationToken: UUID = UUID()

    private var shouldMarquee: Bool {
        isActive && contentWidth > containerWidth + 6
    }

    private var overflowDistance: CGFloat {
        max(contentWidth - containerWidth, 0)
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                if shouldMarquee {
                    HStack(spacing: gap) {
                        textView
                        textView
                    }
                    .offset(x: animatedOffset)
                } else {
                    textView
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            .onAppear {
                containerWidth = proxy.size.width
                restartAnimationIfNeeded()
            }
            .onChange(of: proxy.size.width) { _, newValue in
                containerWidth = newValue
                restartAnimationIfNeeded()
            }
        }
        .frame(height: height)
        .clipped()
        .background(
            textView
                .fixedSize()
                .hidden()
                .readWidth { width in
                    contentWidth = width
                    restartAnimationIfNeeded()
                }
        )
        .onChange(of: isActive) { _, _ in
            restartAnimationIfNeeded()
        }
        .onChange(of: text) { _, _ in
            restartAnimationIfNeeded()
        }
    }

    private var textView: some View {
        Text(text)
            .font(font)
            .foregroundColor(color)
            .fixedSize(horizontal: true, vertical: false)
    }
    private func restartAnimationIfNeeded() {
        animationToken = UUID()
        animatedOffset = 0
        guard shouldMarquee else { return }
        let currentToken = animationToken
        let distance = overflowDistance + gap
        let duration = max(2.8, Double(distance / 28))
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
            guard currentToken == animationToken, shouldMarquee else { return }
            withAnimation(.linear(duration: duration).repeatForever(autoreverses: false)) {
                animatedOffset = -distance
            }
        }
    }
}

private struct WidthPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private extension View {
    func readWidth(onChange: @escaping (CGFloat) -> Void) -> some View {
        background(
            GeometryReader { proxy in
                Color.clear.preference(key: WidthPreferenceKey.self, value: proxy.size.width)
            }
        )
        .onPreferenceChange(WidthPreferenceKey.self, perform: onChange)
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
            AetherRootView()
                .environmentObject(appState)
                .environment(\.locale, appState.appLocale)
        }
        .defaultSize(width: 960, height: 640)
        .commands {
            SidebarCommands() // Enable View -> Show/Hide Sidebar
            CommandGroup(after: .appInfo) {
                AetherCheckForUpdatesCommandView()
            }
        }
        
        AetherMenuBar()
            .environmentObject(appState)
            .environment(\.locale, appState.appLocale)
    }
}

// MARK: - Notification Names
extension Notification.Name {
    static let toggleShortcutPanel = Notification.Name("AetherToggleShortcutPanel")
    static let exportFocusedInputDiagnostics = Notification.Name("AetherExportFocusedInputDiagnostics")
    static let aetherHeadsetRouteChanged = Notification.Name("AetherHeadsetRouteChanged")
}
