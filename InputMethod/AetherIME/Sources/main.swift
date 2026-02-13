import Cocoa
import InputMethodKit

@objc(NSManualApplication)
final class NSManualApplication: NSApplication {}

final class AetherIMEAppDelegate: NSObject, NSApplicationDelegate {
    private var server: IMKServer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let bundle = Bundle.main
        let connectionName = bundle.object(forInfoDictionaryKey: "InputMethodConnectionName") as? String
            ?? "AetherIME_Connection"
        let bundleID = bundle.bundleIdentifier ?? "com.sevenfei.inputmethod.aether"

        server = IMKServer(name: connectionName, bundleIdentifier: bundleID)
    }
}

let app = NSApplication.shared
let delegate = AetherIMEAppDelegate()
app.delegate = delegate
app.setActivationPolicy(.prohibited)
app.run()
