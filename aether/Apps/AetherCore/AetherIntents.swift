// The release packaging pipeline can explicitly disable App Intents when
// Xcode's metadata exporter is unstable on the current toolchain.
#if !AETHER_DISABLE_APP_INTENTS
import AppIntents

// MARK: - Shortcuts Provider

struct AetherShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        return []
    }
}
#endif
