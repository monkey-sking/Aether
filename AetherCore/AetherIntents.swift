// The release packaging pipeline can explicitly disable App Intents when
// Xcode's metadata exporter is unstable on the current toolchain.
#if !AETHER_DISABLE_APP_INTENTS
import AppIntents

// MARK: - Toggle Connection Lock

struct ToggleConnectionLockIntent: AppIntent {
    static var title: LocalizedStringResource = "Toggle AirPods Connection Lock"
    static var description = IntentDescription("Lock or unlock AirPods to this Mac, preventing automatic switching to other devices.")

    func perform() async throws -> some IntentResult & ProvidesDialog {
        await ConnectionLockService.shared.toggle()
        let locked = await ConnectionLockService.shared.isLocked
        return .result(dialog: locked ? "AirPods locked to this Mac." : "AirPods unlocked.")
    }
}

struct LockConnectionIntent: AppIntent {
    static var title: LocalizedStringResource = "Lock AirPods to Mac"
    static var description = IntentDescription("Prevent AirPods from automatically switching to other devices.")

    func perform() async throws -> some IntentResult & ProvidesDialog {
        await ConnectionLockService.shared.lock()
        return .result(dialog: "AirPods locked to this Mac.")
    }
}

struct UnlockConnectionIntent: AppIntent {
    static var title: LocalizedStringResource = "Unlock AirPods"
    static var description = IntentDescription("Allow AirPods to automatically switch between devices again.")

    func perform() async throws -> some IntentResult & ProvidesDialog {
        await ConnectionLockService.shared.unlock()
        return .result(dialog: "AirPods unlocked.")
    }
}

// MARK: - Shortcuts Provider

struct AetherShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: ToggleConnectionLockIntent(),
            phrases: [
                "Toggle AirPods lock with \(.applicationName)",
                "用\(.applicationName)切换耳机连接锁定",
            ],
            shortTitle: "Toggle AirPods Lock",
            systemImageName: "airpodspro"
        )
        AppShortcut(
            intent: LockConnectionIntent(),
            phrases: [
                "Lock AirPods with \(.applicationName)",
                "用\(.applicationName)锁定耳机连接",
            ],
            shortTitle: "Lock AirPods",
            systemImageName: "lock.fill"
        )
        AppShortcut(
            intent: UnlockConnectionIntent(),
            phrases: [
                "Unlock AirPods with \(.applicationName)",
                "用\(.applicationName)解除耳机连接锁定",
            ],
            shortTitle: "Unlock AirPods",
            systemImageName: "lock.open.fill"
        )
    }
}
#endif
