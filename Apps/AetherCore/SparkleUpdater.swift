import AppKit
import SwiftUI
import Combine
import Sparkle

enum AetherDownloadSource: String {
    case manual
    case update
}

enum AetherDownloadURLResolver {
    private static var authBaseURLString: String {
        Bundle.main.object(forInfoDictionaryKey: "AetherAuthBaseURL") as? String
            ?? "https://auth.aether.7caifei.com"
    }

    private static var currentShortVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    static func urlString(for channel: AetherUpdateChannel, source: AetherDownloadSource) -> String? {
        guard var components = URLComponents(string: authBaseURLString) else { return nil }
        components.path = channel == .beta ? "/beta/Aether.dmg" : "/download/Aether.dmg"
        components.queryItems = [
            URLQueryItem(name: "source", value: source.rawValue),
            URLQueryItem(name: "channel", value: channel.rawValue),
            URLQueryItem(name: "version", value: currentShortVersion),
        ]
        return components.string
    }
}

enum AetherUpdateFeedResolver {
    private static let channelKey = "aether.update.channel"
    private static let explicitChannelKey = "aether.update.channel.explicit"

    private static var buildDefaultChannel: AetherUpdateChannel {
        isBetaBuild ? .beta : .stable
    }

    private static var isBetaBuild: Bool {
        guard let rawLabel = Bundle.main.object(forInfoDictionaryKey: "AetherPublicVersionLabel") as? String else {
            return false
        }
        return !rawLabel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    static func currentChannel() -> AetherUpdateChannel {
        let defaults = UserDefaults.standard
        let defaultChannel = buildDefaultChannel
        if defaults.bool(forKey: explicitChannelKey) {
            let raw = defaults.string(forKey: channelKey) ?? defaultChannel.rawValue
            return AetherUpdateChannel(rawValue: raw) ?? defaultChannel
        }

        if defaults.string(forKey: channelKey) != defaultChannel.rawValue {
            defaults.set(defaultChannel.rawValue, forKey: channelKey)
        }
        return defaultChannel
    }

    static func setChannel(_ channel: AetherUpdateChannel, explicit: Bool = true) {
        let defaults = UserDefaults.standard
        defaults.set(channel.rawValue, forKey: channelKey)
        defaults.set(explicit, forKey: explicitChannelKey)
    }

    static func feedURLString(for channel: AetherUpdateChannel) -> String {
        let key = channel == .beta ? "AetherBetaFeedURL" : "AetherStableFeedURL"
        let fallback = channel == .beta
            ? "https://aether.7caifei.com/aether-beta/appcast.xml"
            : "https://aether.7caifei.com/aether/appcast.xml"
        return Bundle.main.object(forInfoDictionaryKey: key) as? String ?? fallback
    }

    static func downloadURLString(for channel: AetherUpdateChannel) -> String? {
        AetherDownloadURLResolver.urlString(for: channel, source: .update)
            ?? {
                let key = channel == .beta ? "AetherBetaDownloadURL" : "AetherDownloadURL"
                return Bundle.main.object(forInfoDictionaryKey: key) as? String
            }()
    }

    static func currentFeedURLString() -> String {
        feedURLString(for: currentChannel())
    }
}

private final class AetherAppcastPublicLabelCache {
    static let shared = AetherAppcastPublicLabelCache()

    private let stateQueue = DispatchQueue(label: "com.aether.appcast-public-label-cache")
    private let cacheLifetime: TimeInterval = 30
    private var labelsByFeedURLString: [String: [String: String]] = [:]
    private var fetchedAtByFeedURLString: [String: Date] = [:]
    private var inFlightFeedURLStrings = Set<String>()

    private init() {}

    func publicLabel(forBuildVersion buildVersion: String?, feedURLString: String) -> String? {
        guard let buildVersion, !buildVersion.isEmpty else { return nil }

        return stateQueue.sync {
            labelsByFeedURLString[feedURLString]?[buildVersion]
        }
    }

    func preload(feedURLString: String, force: Bool = false) async {
        let normalizedFeedURLString = feedURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedFeedURLString.isEmpty,
              let feedURL = URL(string: normalizedFeedURLString) else {
            return
        }

        guard beginLoad(feedURLString: normalizedFeedURLString, force: force) else {
            return
        }
        defer { endLoad(feedURLString: normalizedFeedURLString) }

        do {
            let (data, _) = try await URLSession.shared.data(from: feedURL)
            let labels = AetherAppcastFeedInspector.publicLabelsByBuildVersion(from: data)

            stateQueue.sync {
                labelsByFeedURLString[normalizedFeedURLString] = labels
                fetchedAtByFeedURLString[normalizedFeedURLString] = Date()
            }
        } catch {
            // Keep the previous cache if the feed refresh fails.
        }
    }

    private func beginLoad(feedURLString: String, force: Bool) -> Bool {
        stateQueue.sync {
            if inFlightFeedURLStrings.contains(feedURLString) {
                return false
            }

            if !force,
               let fetchedAt = fetchedAtByFeedURLString[feedURLString],
               Date().timeIntervalSince(fetchedAt) < cacheLifetime {
                return false
            }

            inFlightFeedURLStrings.insert(feedURLString)
            return true
        }
    }

    private func endLoad(feedURLString: String) {
        stateQueue.sync {
            inFlightFeedURLStrings.remove(feedURLString)
        }
    }
}

@MainActor
private final class AetherSparkleFeedDelegate: NSObject, SPUUpdaterDelegate {
    static let shared = AetherSparkleFeedDelegate()

    func feedURLString(for updater: SPUUpdater) -> String? {
        let feedURLString = AetherUpdateFeedResolver.currentFeedURLString()
        Task {
            await AetherAppcastPublicLabelCache.shared.preload(feedURLString: feedURLString)
        }
        return feedURLString
    }

    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        AetherSparkleFocusHelper.bringAppToFront()
    }

    func updaterDidNotFindUpdate(_ updater: SPUUpdater) {
        AetherSparkleFocusHelper.bringAppToFront()
    }
}

private final class AetherSparkleVersionDisplayer: NSObject, SUVersionDisplay {
    static let shared = AetherSparkleVersionDisplayer()

    private var currentDisplayChannel: AetherBuildVersionFormatter.DisplayChannel {
        AetherUpdateFeedResolver.currentChannel().versionDisplayChannel
    }

    private var bundlePublicLabel: String? {
        Bundle.main.object(forInfoDictionaryKey: "AetherPublicVersionLabel") as? String
    }

    private var currentFeedURLString: String {
        AetherUpdateFeedResolver.currentFeedURLString()
    }

    private func publicLabel(for item: SUAppcastItem?) -> String? {
        guard let item else { return nil }
        return AetherBuildVersionFormatter.publicLabel(
            from: item.fileURL?.absoluteString,
            propertiesDictionary: item.propertiesDictionary
        ) ?? AetherAppcastPublicLabelCache.shared.publicLabel(
            forBuildVersion: item.versionString,
            feedURLString: currentFeedURLString
        )
    }

    func formatUpdateVersion(
        fromUpdate update: SUAppcastItem,
        andBundleDisplayVersion bundleDisplayVersion: AutoreleasingUnsafeMutablePointer<NSString>,
        withBundleVersion bundleVersion: String
    ) -> String {
        let displays = AetherBuildVersionFormatter.comparisonDisplay(
            updateShortVersion: update.displayVersionString,
            updateBuildVersion: update.versionString,
            updatePublicLabel: publicLabel(for: update),
            bundleShortVersion: bundleDisplayVersion.pointee as String,
            bundleBuildVersion: bundleVersion,
            bundlePublicLabel: bundlePublicLabel,
            channel: currentDisplayChannel
        )

        let resolvedBundleDisplay = displays.bundle
            ?? AetherBuildVersionFormatter.versionDisplay(
                shortVersion: bundleDisplayVersion.pointee as String,
                buildVersion: bundleVersion,
                publicLabel: bundlePublicLabel,
                channel: currentDisplayChannel
            )
            ?? (bundleDisplayVersion.pointee as String)
        bundleDisplayVersion.pointee = resolvedBundleDisplay as NSString

        return displays.update
            ?? AetherBuildVersionFormatter.versionDisplay(
                shortVersion: update.displayVersionString,
                buildVersion: update.versionString,
                publicLabel: publicLabel(for: update),
                channel: currentDisplayChannel
            )
            ?? update.displayVersionString
    }

    func formatBundleDisplayVersion(
        _ bundleDisplayVersion: String,
        withBundleVersion bundleVersion: String,
        matchingUpdate: SUAppcastItem?
    ) -> String {
        AetherBuildVersionFormatter.versionDisplay(
            shortVersion: bundleDisplayVersion,
            buildVersion: bundleVersion,
            publicLabel: bundlePublicLabel ?? publicLabel(for: matchingUpdate),
            channel: currentDisplayChannel
        ) ?? bundleDisplayVersion
    }
}

private final class AetherSparkleUserDriverDelegate: NSObject, SPUStandardUserDriverDelegate {
    static let shared = AetherSparkleUserDriverDelegate()

    nonisolated func standardUserDriverWillShowModalAlert() {
        Task { @MainActor in
            HUDManager.shared.hideImmediately()
            AetherSparkleFocusHelper.bringAppToFront()
        }
    }

    func standardUserDriverRequestsVersionDisplayer() -> (any SUVersionDisplay)? {
        AetherSparkleVersionDisplayer.shared
    }
}

@MainActor
private enum AetherSparkleFocusHelper {
    static func bringAppToFront() {
        // Sparkle presents modal alerts that can appear behind other apps if we're not active.
        // Activate and bring all windows forward so the update alert is always visible.
        NSRunningApplication.current.activate(options: [.activateAllWindows])
        NSApp.activate(ignoringOtherApps: true)
    }
}

@MainActor
final class AetherSparkleController: ObservableObject {
    static let shared = AetherSparkleController()

    let updaterController: SPUStandardUpdaterController

    private init() {
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: AetherSparkleFeedDelegate.shared,
            userDriverDelegate: AetherSparkleUserDriverDelegate.shared
        )
        _ = updaterController.updater.clearFeedURLFromUserDefaults()
    }

    func refreshFeedSelection() {
        _ = updaterController.updater.clearFeedURLFromUserDefaults()
        updaterController.updater.resetUpdateCycle()
    }

    func checkForUpdates() {
        let feedURLString = AetherUpdateFeedResolver.currentFeedURLString()
        Task { [updaterController] in
            await AetherAppcastPublicLabelCache.shared.preload(
                feedURLString: feedURLString,
                force: true
            )
            await MainActor.run {
                HUDManager.shared.hideImmediately()
                AetherSparkleFocusHelper.bringAppToFront()
                updaterController.checkForUpdates(nil)
            }
        }
    }
}

@MainActor
private final class CheckForUpdatesViewModel: ObservableObject {
    @Published var canCheckForUpdates = false

    init(updater: SPUUpdater) {
        updater.publisher(for: \.canCheckForUpdates)
            .receive(on: RunLoop.main)
            .assign(to: &$canCheckForUpdates)
    }
}

@MainActor
struct AetherCheckForUpdatesCommandView: View {
    @StateObject private var viewModel: CheckForUpdatesViewModel
    private let sparkleController: AetherSparkleController

    init() {
        let sparkleController = AetherSparkleController.shared
        self.sparkleController = sparkleController
        _viewModel = StateObject(
            wrappedValue: CheckForUpdatesViewModel(
                updater: sparkleController.updaterController.updater
            )
        )
    }

    var body: some View {
        Button("Check for Updates…") {
            sparkleController.checkForUpdates()
        }
        .disabled(!viewModel.canCheckForUpdates)
    }
}
