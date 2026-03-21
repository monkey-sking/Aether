import AppKit
import SwiftUI
import Combine
import Sparkle

enum AetherUpdateFeedResolver {
    private static let channelKey = "aether.update.channel"

    static func currentChannel() -> AetherUpdateChannel {
        let raw = UserDefaults.standard.string(forKey: channelKey) ?? AetherUpdateChannel.stable.rawValue
        return AetherUpdateChannel(rawValue: raw) ?? .stable
    }

    static func feedURLString(for channel: AetherUpdateChannel) -> String {
        let key = channel == .beta ? "AetherBetaFeedURL" : "AetherStableFeedURL"
        let fallback = channel == .beta
            ? "https://aether.7caifei.com/aether-beta/appcast.xml"
            : "https://aether.7caifei.com/aether/appcast.xml"
        return Bundle.main.object(forInfoDictionaryKey: key) as? String ?? fallback
    }

    static func downloadURLString(for channel: AetherUpdateChannel) -> String? {
        let key = channel == .beta ? "AetherBetaDownloadURL" : "AetherDownloadURL"
        return Bundle.main.object(forInfoDictionaryKey: key) as? String
    }

    static func currentFeedURLString() -> String {
        feedURLString(for: currentChannel())
    }
}

@MainActor
private final class AetherSparkleFeedDelegate: NSObject, SPUUpdaterDelegate {
    static let shared = AetherSparkleFeedDelegate()

    func feedURLString(for updater: SPUUpdater) -> String? {
        AetherUpdateFeedResolver.currentFeedURLString()
    }

    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        AetherSparkleFocusHelper.bringAppToFront()
    }

    func updaterDidNotFindUpdate(_ updater: SPUUpdater) {
        AetherSparkleFocusHelper.bringAppToFront()
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
        HUDManager.shared.hideImmediately()
        AetherSparkleFocusHelper.bringAppToFront()
        updaterController.checkForUpdates(nil)
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
