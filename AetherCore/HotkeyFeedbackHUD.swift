import SwiftUI
import AppKit
import os.log
import Combine

private struct InputMethodCaretUpdate {
    let caretRect: CGRect
    let contextRect: CGRect?
    let bundleID: String?
    let timestamp: Date
}

private final class InputMethodCaretBridge {
    static let notificationName = Notification.Name("com.7fei.aether.inputmethod.caret")

    var onCaretUpdate: ((InputMethodCaretUpdate) -> Void)?

    private var observer: NSObjectProtocol?

    func start() {
        guard observer == nil else { return }
        observer = DistributedNotificationCenter.default().addObserver(
            forName: Self.notificationName,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self else { return }
            guard let update = self.decode(notification.userInfo) else { return }
            self.onCaretUpdate?(update)
        }
    }

    func stop() {
        guard let observer else { return }
        DistributedNotificationCenter.default().removeObserver(observer)
        self.observer = nil
    }

    private func decode(_ userInfo: [AnyHashable: Any]?) -> InputMethodCaretUpdate? {
        guard let userInfo else { return nil }
        guard
            let caretX = toCGFloat(userInfo["caretX"]),
            let caretY = toCGFloat(userInfo["caretY"]),
            let caretW = toCGFloat(userInfo["caretW"]),
            let caretH = toCGFloat(userInfo["caretH"])
        else {
            return nil
        }

        let caretRect = CGRect(x: caretX, y: caretY, width: caretW, height: caretH)

        var contextRect: CGRect?
        if
            let contextX = toCGFloat(userInfo["contextX"]),
            let contextY = toCGFloat(userInfo["contextY"]),
            let contextW = toCGFloat(userInfo["contextW"]),
            let contextH = toCGFloat(userInfo["contextH"])
        {
            contextRect = CGRect(x: contextX, y: contextY, width: contextW, height: contextH)
        }

        let bundleID = userInfo["bundleID"] as? String
        let timestamp = toDouble(userInfo["timestamp"]).map { Date(timeIntervalSince1970: $0) } ?? Date()

        return InputMethodCaretUpdate(
            caretRect: caretRect,
            contextRect: contextRect,
            bundleID: bundleID,
            timestamp: timestamp
        )
    }

    private func toCGFloat(_ value: Any?) -> CGFloat? {
        if let n = value as? NSNumber { return CGFloat(truncating: n) }
        if let d = value as? Double { return CGFloat(d) }
        if let s = value as? String, let d = Double(s) { return CGFloat(d) }
        return nil
    }

    private func toDouble(_ value: Any?) -> Double? {
        if let n = value as? NSNumber { return n.doubleValue }
        if let d = value as? Double { return d }
        if let s = value as? String { return Double(s) }
        return nil
    }
}

/// A Unified HUD for Voice, PTT, and Hotkey Feedback.
/// Features: Follows mouse, interactive (language toggle), and persistent during dictation.
final class HotkeyFeedbackHUD {
    
    static let shared = HotkeyFeedbackHUD()
    private init() {}
    
    private var hudWindow: NSPanel?
    private var hideTask: DispatchWorkItem?

    class FileLogger {
        static let shared = FileLogger()
        private let fileURL: URL?
        private let queue = DispatchQueue(label: "com.aether.filelogger")
        private let verboseLogging: Bool

        private init() {
            verboseLogging = ProcessInfo.processInfo.environment["AETHER_VERBOSE_LOG"] == "1"
            if let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
                fileURL = docs.appendingPathComponent("Aether_Debug.log")
                // Append start marker
                log("=== SESSION STARTED: \(Date()) ===")
            } else {
                fileURL = nil
            }
        }

        func debug(_ message: String) {
            if !verboseLogging {
                let keep = message.contains("ERROR") ||
                    message.contains("❌") ||
                    message.contains("🚨") ||
                    message.contains("⚠️") ||
                    message.contains("💥")
                if !keep { return }
            }
            log("DEBUG: " + message)
        }
        
        func error(_ message: String) {
            log("ERROR: " + message)
        }

        private func log(_ message: String) {
            guard let url = fileURL else { return }
            queue.async {
                let formatter = ISO8601DateFormatter()
                let timestamp = formatter.string(from: Date())
                let line = "\(timestamp) \(message)\n"
                
                if let data = line.data(using: .utf8) {
                    if FileManager.default.fileExists(atPath: url.path) {
                        if let handle = try? FileHandle(forWritingTo: url) {
                            handle.seekToEndOfFile()
                            handle.write(data)
                            handle.closeFile()
                        }
                    } else {
                        try? line.write(to: url, atomically: true, encoding: .utf8)
                    }
                }
            }
        }
    }

    // Subclass to ensure transparent background
    class TransparentHostingController<Content>: NSHostingController<Content> where Content : View {
        override func loadView() {
            super.loadView()
            view.wantsLayer = true
            view.layer?.backgroundColor = NSColor.clear.cgColor
            view.layer?.isOpaque = false
        }
    }
    
    // State hosted in SwiftUI
    private class HUDState: ObservableObject {
        @Published var message: String = ""
        @Published var isListening: Bool = false
        @Published var language: String = "zh-CN"
        @Published var isInteractive: Bool = false
        @Published var isDictating: Bool = false
        @Published var audioLevel: CGFloat = 0.0
        
        // Subject for instant notification of state changes
        let stateChanged = PassthroughSubject<Void, Never>()
    }
    
    private let state = HUDState()
    // private let logger = Logger(subsystem: "com.7fei.Aether", category: "HUD")
    private let logger = FileLogger.shared
    private var cancellables = Set<AnyCancellable>()
    
    func updateAudioLevel(_ level: Float) {
        DispatchQueue.main.async {
            self.state.audioLevel = CGFloat(min(level * 5.0, 1.0))
        }
    }
    
    // MARK: - Public API
    
    static func show(_ message: String, icon: String? = nil) {
        shared.update(message: message, isListening: false)
        shared.scheduleHide(delay: shared.hudAutoHideDelay())
    }
    
    static func showContinuous(message: String, isListening: Bool, language: String, isDictating: Bool) {
        shared.update(message: message, isListening: isListening, language: language, isInteractive: true, isDictating: isDictating)
        shared.cancelHide()
        // INSTANT NOTIFICATION for zero-latency UI switch
        shared.state.stateChanged.send()
    }
    
    static func hide() {
        shared.scheduleHide(delay: 0.1)
        shared.state.stateChanged.send()
    }

    static func typingContextSnapshot() -> Bool {
        shared.typingContextSnapshot()
    }
    
    // MARK: - internal
    
    private func update(message: String, isListening: Bool, language: String = "zh-CN", isInteractive: Bool = false, isDictating: Bool = false) {
        DispatchQueue.main.async {
            self.ensureWindow()
            self.state.message = message
            self.state.isListening = isListening
            self.state.language = language
            self.state.isInteractive = isInteractive
            self.state.isDictating = isDictating
            
            // Allow clicks if interactive
            self.hudWindow?.ignoresMouseEvents = !isInteractive
            
            self.repositionWindow()
            self.hudWindow?.orderFront(nil)
            self.hudWindow?.alphaValue = 1.0
            
            // Keep AX/mouse monitors alive only while HUD is active listening/interactive.
            if isListening || isInteractive {
                if self.followTimer == nil {
                    self.startFollowTimer()
                }
            } else if self.followTimer != nil {
                self.stopFollowTimer()
            }
        }
    }

    private func typingContextSnapshot() -> Bool {
        if Thread.isMainThread {
            return (self.caretRect != nil) || (self.isCaretStickyActive && self.recentCaretRect() != nil)
        }
        var result = false
        DispatchQueue.main.sync {
            result = (self.caretRect != nil) || (self.isCaretStickyActive && self.recentCaretRect() != nil)
        }
        return result
    }
    
    private var followTimer: Timer?
    private var eventMonitors: [Any] = []
    private var axObserver: AXObserver?
    private var observedPid: pid_t = 0
    private lazy var inputMethodBridge: InputMethodCaretBridge = {
        let bridge = InputMethodCaretBridge()
        bridge.onCaretUpdate = { [weak self] update in
            guard let self = self else { return }
            self.bridgedCaretRect = update.caretRect
            self.bridgedInputContextRect = update.contextRect
            self.bridgedBundleID = update.bundleID
            self.bridgedCaretAt = update.timestamp
            if Date().timeIntervalSince(self.lastBridgeRxLogAt) >= 0.5 {
                self.lastBridgeRxLogAt = Date()
                self.logger.debug("⚠️ [IME BRIDGE RX] caret=\(update.caretRect.debugDescription) bundle=\(update.bundleID ?? "nil")")
            }
            if self.typingContextSnapshot() {
                self.repositionWindow()
            }
        }
        return bridge
    }()
    private var bridgedCaretRect: CGRect?
    private var bridgedInputContextRect: CGRect?
    private var bridgedBundleID: String?
    private var bridgedCaretAt: Date?
    private var lastCaretCompareLogAt: Date = .distantPast
    private var lastBridgeRxLogAt: Date = .distantPast
    private var lastMouseFollowRepositionAt: Date = .distantPast

    private func hudAutoHideDelay() -> TimeInterval {
        let value = UserDefaults.standard.object(forKey: "hudAutoHideSeconds") as? Double ?? 1.5
        return min(max(value, 0.5), 8.0)
    }
    
    private func startFollowTimer() {
        // 1. AX Observer (Event-Driven: Focus/Caret changes) — replaces Timer polling
        setupAXObserver()
        inputMethodBridge.start()
        
        // 2. Global Mouse Move Monitor (Non-input-mode follow)
        // When caretRect is nil, HUD follows mouse in real-time via this monitor
        if let monitor = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved, handler: { [weak self] _ in
            guard let self = self else { return }
            // Only reposition in mouse-follow mode (no active caret)
            if self.caretRect == nil {
                let now = Date()
                if now.timeIntervalSince(self.lastMouseFollowRepositionAt) < 0.016 { return }
                self.lastMouseFollowRepositionAt = now
                DispatchQueue.main.async {
                    self.repositionWindow()
                }
            }
        }) {
            eventMonitors.append(monitor)
        }
        
        // 3. Global Mouse Click Monitor (Immediate Trigger on Click)
        // Catches focus changes (e.g. clicking a text box) instantly
        if let monitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown], handler: { [weak self] _ in
            DispatchQueue.main.async {
                // Click may change focus — re-evaluate caret after brief delay for AX to settle
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    self?.updateCaretRect()
                }
                // Burst updates improve responsiveness in web/electron focus transitions.
                self?.scheduleFocusBurst(delays: [0.01, 0.04, 0.10])
            }
        }) {
            eventMonitors.append(monitor)
        }
        
        // 4. Global Key Monitor (typing caret usually moves with keystrokes)
        if let monitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown, handler: { [weak self] _ in
            guard let self = self else { return }
            let now = Date()
            if now.timeIntervalSince(self.lastKeyDrivenUpdateAt) < 0.03 { return }
            self.lastKeyDrivenUpdateAt = now
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.012) {
                if self.typingContextSnapshot() {
                    self.updateCaretRect()
                }
            }
        }) {
            eventMonitors.append(monitor)
        }
        
        // 5. App Switching Monitor (Immediate Trigger on Cmd+Tab)
        let wsObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] _ in
            self?.logger.debug("📱 App Switch detected. Forcing update.")
            self?.isFetchingCaret = false
            self?.caretRect = nil // Reset caret on app switch
            self?.lastCaretRect = nil
            self?.lastCaretRectAt = nil
            self?.caretSourceBundleID = nil
            self?.isCaretStickyActive = false
            self?.caretStickyTimer?.invalidate()
            self?.caretStickyTimer = nil
            self?.repositionWindow()
            // Re-establish AX observer for new app
            self?.setupAXObserver()
            if let s = self,
               s.isCodexLike(appName: NSWorkspace.shared.frontmostApplication?.localizedName,
                             bundleID: NSWorkspace.shared.frontmostApplication?.bundleIdentifier) {
                s.scheduleFocusBurst(delays: [0.0, 0.03, 0.09, 0.18, 0.32, 0.50])
            } else {
                self?.scheduleFocusBurst()
            }
        }
        eventMonitors.append(wsObserver)
        
        // 6. Fallback Timer (Low-frequency safety net for edge cases)
        // Only runs updateCaretRect, not repositionWindow (that's event-driven now)
        followTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.updateCaretRect()
            }
        }
    }
    
    /// Sets up AXObserver for the frontmost app's focused element changes.
    /// This is the core event-driven mechanism that replaces Timer polling.
    private func setupAXObserver() {
        // Tear down old observer
        teardownAXObserver()
        
        guard let app = NSWorkspace.shared.frontmostApplication else { return }
        if app.bundleIdentifier == Bundle.main.bundleIdentifier {
            return
        }
        let pid = app.processIdentifier
        
        var observer: AXObserver?
        let callback: AXObserverCallback = { (observer, element, notification, refcon) in
            guard let refcon = refcon else { return }
            let hud = Unmanaged<HotkeyFeedbackHUD>.fromOpaque(refcon).takeUnretainedValue()
            if hud.shouldEmitXcodeDiagLog(minInterval: 1.2) {
                let notifName = notification as String
                hud.logger.debug("⚡ [AXEvent] \(notifName)")
            }
            DispatchQueue.main.async {
                hud.updateCaretRect()
            }
        }
        
        let result = AXObserverCreate(pid, callback, &observer)
        guard result == .success, let obs = observer else {
            logger.debug("⚠️ AXObserverCreate failed for PID \(pid): \(result.rawValue)")
            return
        }
        
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        let appElement = AXUIElementCreateApplication(pid)
        
        // Monitor focus changes (text field → button, etc.) and text selection changes
        let notifications: [CFString] = [
            kAXFocusedUIElementChangedNotification as CFString,
            kAXSelectedTextChangedNotification as CFString,
            kAXValueChangedNotification as CFString
        ]
        
        for notif in notifications {
            AXObserverAddNotification(obs, appElement, notif, refcon)
        }
        
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(obs), .defaultMode)
        
        self.axObserver = obs
        self.observedPid = pid
        logger.debug("✅ AXObserver installed for '\(app.localizedName ?? "?")', PID \(pid)")
    }
    
    private func teardownAXObserver() {
        if let obs = axObserver {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(obs), .defaultMode)
            axObserver = nil
            observedPid = 0
        }
    }
    
    private func stopFollowTimer() {
        followTimer?.invalidate()
        followTimer = nil
        
        teardownAXObserver()
        inputMethodBridge.stop()
        
        for monitor in eventMonitors {
            if let obs = monitor as? NSObjectProtocol {
                NSWorkspace.shared.notificationCenter.removeObserver(obs)
            } else {
                NSEvent.removeMonitor(monitor)
            }
        }
        eventMonitors.removeAll()
    }
    
    private func ensureWindow() {
        guard hudWindow == nil else { return }
        
        let savedState = self.state
        let rootView = HUDView(state: savedState)
        let hostingController = TransparentHostingController(rootView: rootView)
        
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 60),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .screenSaver
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary]
        panel.contentViewController = hostingController
        
        self.hudWindow = panel
        
        // SUBSCRIBE TO INSTANT CHANGES
        state.stateChanged
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in
                guard let self = self else { return }
                let front = NSWorkspace.shared.frontmostApplication
                let codexFrontmost = self.isCodexLike(appName: front?.localizedName, bundleID: front?.bundleIdentifier)
                if codexFrontmost && (self.state.isListening || self.state.isInteractive) {
                    self.updateCaretRect()
                }
                self.repositionWindow()
            }
            .store(in: &cancellables)
    }
    
    private var caretRect: CGRect?
    private var lastCaretRect: CGRect?
    private var lastCaretRectAt: Date?
    private var isFetchingCaret = false // Throttling flag
    
    // Throttling for logs
    private var lastLoggedAnchor: CGPoint = .zero
    private var lastLoggedMode: String = ""
    private var lastLoggedScreenName: String = ""
    private var currentAppName: String?
    private var currentAppBundleID: String?
    private var lastFocusedAppName: String?
    private var lastFocusedBundleID: String?
    private var caretSourceBundleID: String?
    private var inputContextRect: CGRect?
    private var singleLineStepBySource: [String: CGFloat] = [:]
    private var lastPreFlipRejectLogAt: Date = .distantPast
    private var lastXcodeDiagLogAt: Date = .distantPast
    
    // Caret Sticky Logic (v0.1.4)
    private var caretStickyTimer: Timer?
    private var isCaretStickyActive: Bool = false
    private var lastKeyDrivenUpdateAt: Date = .distantPast

    private func isSiriLike(appName: String?, bundleID: String) -> Bool {
        if bundleID.contains("apple.siri") || bundleID == "com.apple.Spotlight" {
            return true
        }
        let lowered = appName?.lowercased() ?? ""
        return lowered.contains("siri")
    }

    private func recentCaretRect(maxAge: TimeInterval = 0.28) -> CGRect? {
        guard let rect = lastCaretRect, let ts = lastCaretRectAt else { return nil }
        let age = Date().timeIntervalSince(ts)
        if isCodexLike(appName: currentAppName, bundleID: currentAppBundleID) {
            if age <= min(maxAge, 0.18) {
                return rect
            }
            return nil
        }
        if age <= maxAge {
            return rect
        }
        return nil
    }

    private func recentBridgedCaret(maxAge: TimeInterval = 0.45) -> (caret: CGRect, context: CGRect?, bundleID: String?)? {
        let snapshot: (CGRect?, CGRect?, String?, Date?) = {
            if Thread.isMainThread {
                return (self.bridgedCaretRect, self.bridgedInputContextRect, self.bridgedBundleID, self.bridgedCaretAt)
            }
            var local: (CGRect?, CGRect?, String?, Date?) = (nil, nil, nil, nil)
            DispatchQueue.main.sync {
                local = (self.bridgedCaretRect, self.bridgedInputContextRect, self.bridgedBundleID, self.bridgedCaretAt)
            }
            return local
        }()

        guard let caret = snapshot.0, let ts = snapshot.3 else { return nil }
        if Date().timeIntervalSince(ts) > maxAge { return nil }

        // Some IMK environments report empty/IME bundle as source; don't reject those updates.
        if let rawSourceBundle = snapshot.2 {
            let sourceBundle = rawSourceBundle.trimmingCharacters(in: .whitespacesAndNewlines)
            let imeBundle = "com.sevenfei.inputmethod.aether"
            let appBundle = Bundle.main.bundleIdentifier ?? ""
            let needsStrictMatch = !sourceBundle.isEmpty && sourceBundle != imeBundle && sourceBundle != appBundle
            if needsStrictMatch,
               let frontBundle = NSWorkspace.shared.frontmostApplication?.bundleIdentifier,
               sourceBundle != frontBundle {
                return nil
            }
        }

        return (caret: caret, context: snapshot.1, bundleID: snapshot.2)
    }

    private func shouldEmitCaretCompareLog(minInterval: TimeInterval = 0.5) -> Bool {
        let now = Date()
        if now.timeIntervalSince(lastCaretCompareLogAt) >= minInterval {
            lastCaretCompareLogAt = now
            return true
        }
        return false
    }

    private func shouldEmitPreFlipRejectLog(minInterval: TimeInterval = 0.35) -> Bool {
        let now = Date()
        if now.timeIntervalSince(lastPreFlipRejectLogAt) >= minInterval {
            lastPreFlipRejectLogAt = now
            return true
        }
        return false
    }

    private func singleLineStepCacheKey(bundleID: String, role: String) -> String {
        "\(bundleID)#\(role)"
    }

    private func preferredSingleLineStep(bundleID: String, role: String, fieldHeight: CGFloat) -> CGFloat {
        let key = singleLineStepCacheKey(bundleID: bundleID, role: role)
        if let cached = singleLineStepBySource[key] {
            return min(max(cached, 8.0), 15.0)
        }
        return min(max(9.0, fieldHeight * 0.52), 13.0)
    }

    private func updateSingleLineStepSample(bundleID: String, role: String, observedStep: CGFloat) {
        let key = singleLineStepCacheKey(bundleID: bundleID, role: role)
        let clamped = min(max(observedStep, 8.0), 15.0)
        if let old = singleLineStepBySource[key] {
            singleLineStepBySource[key] = old * 0.7 + clamped * 0.3
        } else {
            singleLineStepBySource[key] = clamped
        }
    }

    private func isCJKScalar(_ scalar: UnicodeScalar) -> Bool {
        let v = scalar.value
        return
            (0x4E00...0x9FFF).contains(v) ||
            (0x3400...0x4DBF).contains(v) ||
            (0xF900...0xFAFF).contains(v) ||
            (0x3040...0x30FF).contains(v) ||
            (0xAC00...0xD7AF).contains(v)
    }

    private func characterAdvanceUnit(_ ch: Character) -> CGFloat {
        let s = String(ch)
        if s == "\n" || s == "\r" {
            return 0.0
        }
        if s.unicodeScalars.contains(where: { isCJKScalar($0) }) {
            return 1.0
        }
        if s.unicodeScalars.allSatisfy({ $0.isASCII }) {
            if s.rangeOfCharacter(from: .decimalDigits) != nil || s.rangeOfCharacter(from: .letters) != nil {
                return 0.56
            }
            if s.rangeOfCharacter(from: .whitespacesAndNewlines) != nil {
                return 0.33
            }
            return 0.50
        }
        return 0.82
    }

    private func weightedCaretUnits(in text: String, location: Int) -> CGFloat {
        let clamped = max(0, min(location, text.count))
        guard clamped > 0 else { return 0.0 }
        var units: CGFloat = 0.0
        for ch in text.prefix(clamped) {
            units += characterAdvanceUnit(ch)
        }
        return units
    }

    private func isTerminalLike(bundleID: String) -> Bool {
        let ids = [
            "com.apple.Terminal",
            "com.googlecode.iterm2",
            "com.github.wez.wezterm",
            "dev.warp.Warp-Stable"
        ]
        return ids.contains(bundleID)
    }

    private func isCodexLike(appName: String?, bundleID: String?) -> Bool {
        let loweredName = appName?.lowercased() ?? ""
        if loweredName.contains("codex") { return true }
        let loweredBundle = bundleID?.lowercased() ?? ""
        return loweredBundle.contains("codex")
    }

    private func isXcodeLike(appName: String?, bundleID: String?) -> Bool {
        if bundleID == "com.apple.dt.Xcode" { return true }
        let loweredName = appName?.lowercased() ?? ""
        return loweredName == "xcode"
    }

    private func shouldEmitXcodeDiagLog(minInterval: TimeInterval = 0.6) -> Bool {
        let now = Date()
        if now.timeIntervalSince(lastXcodeDiagLogAt) >= minInterval {
            lastXcodeDiagLogAt = now
            return true
        }
        return false
    }

    private func isLikelySameAppFamily(_ a: String, _ b: String) -> Bool {
        if a == b { return true }
        if a.hasPrefix(b + ".") || b.hasPrefix(a + ".") { return true }
        let aParts = a.split(separator: ".")
        let bParts = b.split(separator: ".")
        if aParts.count >= 2 && bParts.count >= 2 {
            let aRoot = "\(aParts[0]).\(aParts[1])"
            let bRoot = "\(bParts[0]).\(bParts[1])"
            if aRoot == bRoot { return true }
        }
        return false
    }

    private func readAXBool(_ element: AXUIElement, attribute: String) -> Bool? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else {
            return nil
        }
        if let boolValue = value as? Bool {
            return boolValue
        }
        if let number = value as? NSNumber {
            return number.boolValue
        }
        return nil
    }

    private func hasTextInsertionContext(_ element: AXUIElement) -> Bool {
        var selectedRangeValue: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &selectedRangeValue) == .success {
            return true
        }
        var markerRangeValue: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, "AXSelectedTextMarkerRange" as CFString, &markerRangeValue) == .success {
            return true
        }
        return false
    }

    private func preferInputMethodCaretEngine() -> Bool {
        UserDefaults.standard.object(forKey: "preferInputMethodCaret") as? Bool ?? false
    }

    private func caretEngineCompareEnabled() -> Bool {
        UserDefaults.standard.object(forKey: "caretEngineCompareEnabled") as? Bool ?? false
    }

    private func stickyDuration(for bundleID: String?, appName: String?) -> TimeInterval {
        if isCodexLike(appName: appName, bundleID: bundleID) {
            return 0.06
        }
        guard let bundleID else { return 0.08 }
        if isSiriLike(appName: appName, bundleID: bundleID) {
            return 0.10
        }
        if isTerminalLike(bundleID: bundleID) {
            return 0.05
        }
        return 0.08
    }

    private func scheduleFocusBurst(delays: [TimeInterval] = [0.0, 0.03, 0.09, 0.18]) {
        for delay in delays {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                self?.updateCaretRect()
            }
        }
    }
    
    // Helper: Recursively find a text field in children (Depth-First)
    // v0.1.5: Increased depth to 5 for deeper Siri hierarchies
    private func findFirstTextField(in element: AXUIElement, depth: Int = 5) -> AXUIElement? {
        if depth <= 0 { return nil }
        
        var childrenRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenRef) == .success,
              let children = childrenRef as? [AXUIElement] else { return nil }
        
        let targetRoles = ["AXTextField", "AXTextArea", "AXSearchField", "AXComboBox", "AXWebArea"]
        
        for child in children {
            var roleRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(child, kAXRoleAttribute as CFString, &roleRef) == .success,
               let role = roleRef as? String {
                
                // 1. Direct match for standard input roles
                if targetRoles.contains(role) {
                    return child
                }
                
                // 2. Special Case: Siri static text that is actually acting as an input placeholder
                if role == "AXStaticText" {
                    var pid: pid_t = 0
                    AXUIElementGetPid(child, &pid)
                    if let bundleID = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier,
                       bundleID.contains("apple.siri") {
                        return child
                    }
                }
            }
            // Recurse
            if let found = findFirstTextField(in: child, depth: depth - 1) {
                return found
            }
        }
        return nil
    }
    
    private func updateCaretRect() {
        // Prevent stacking AX calls if previous one is hanging (common in Browsers)
        if isFetchingCaret { return }
        isFetchingCaret = true

        // Hard short-circuit for Aether frontmost to avoid expensive AX polling/log churn
        // against our own UI tree (which can be very chatty in the main window).
        if NSWorkspace.shared.frontmostApplication?.bundleIdentifier == Bundle.main.bundleIdentifier {
            DispatchQueue.main.async {
                self.isFetchingCaret = false
                let hadCaretState = (self.caretRect != nil) || self.isCaretStickyActive || (self.inputContextRect != nil)
                self.caretRect = nil
                self.lastCaretRect = nil
                self.lastCaretRectAt = nil
                self.caretSourceBundleID = nil
                self.inputContextRect = nil
                self.isCaretStickyActive = false
                self.caretStickyTimer?.invalidate()
                self.caretStickyTimer = nil
                if hadCaretState {
                    self.repositionWindow()
                }
            }
            return
        }
        
        // Run on background to avoid blocking UI
        DispatchQueue.global(qos: .userInteractive).async {
            var newRect: CGRect? = nil
            var newInputContextRect: CGRect? = nil
            var newCaretSourceBundleID: String? = nil
            var focusedIsEditable = false
            var shouldTemporarilyKeepLastCaret = false
            var usedInputMethodBridge = false
            let preferIME = self.preferInputMethodCaretEngine()
            let compareEnabled = self.caretEngineCompareEnabled()
            var preferredBridgedRect: CGRect? = nil
            var preferredBridgedInputContextRect: CGRect? = nil
            var preferredBridgedBundleID: String? = nil

            if let bridged = self.recentBridgedCaret(), preferIME {
                focusedIsEditable = true
                shouldTemporarilyKeepLastCaret = true
                preferredBridgedBundleID = bridged.bundleID
                if compareEnabled {
                    preferredBridgedRect = bridged.caret
                    preferredBridgedInputContextRect = bridged.context
                    self.logger.debug("📎 [IME BRIDGE] Compare mode enabled; collecting AX baseline with bridged caret preference.")
                } else {
                    newRect = bridged.caret
                    newInputContextRect = bridged.context
                    newCaretSourceBundleID = bridged.bundleID ?? NSWorkspace.shared.frontmostApplication?.bundleIdentifier
                    usedInputMethodBridge = true
                    self.logger.debug("✅ [IME BRIDGE] Using bridged caret \(bridged.caret.debugDescription)")
                }
            }
            
            if !usedInputMethodBridge {
                // 1. Get System-wide Element
                let systemWide = AXUIElementCreateSystemWide()
                // TIMEOUT: Fail fast (100ms) if App is unresponsive (e.g. busy Browser)
                AXUIElementSetMessagingTimeout(systemWide, 0.1)
                
                // 2. Get Focused Element (Directly from system-wide, handles Spotlight/Overlays)
                var focusedElement: CFTypeRef?
                let elementStatus = AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &focusedElement)
            
            func extractRect(from value: CFTypeRef) -> CGRect? {
                var r = CGRect.zero
                if AXValueGetValue(value as! AXValue, .cgRect, &r) {
                    // UNIVERSAL MULTI-MONITOR NORMALIZATION
                    // Apple's Global Coordinate Systems:
                    // 1. AX System: Top-Left of primary screen is (0,0). Y increases down.
                    // 2. AppKit/CoreGraphics: Bottom-Left of primary screen is (0,0). Y increases up.
                    
                    // The core discrepancy is that AX uses Y-down and AppKit uses Y-up.
                    // To accurately translate between them without screen-specific logic:
                    // appkit_y = (Primary_Screen_Height) - ax_y - rect_height
                    
                    if let primary = NSScreen.screens.first {
                        let primaryHeight = primary.frame.height
                        r.origin.y = primaryHeight - r.origin.y - r.size.height
                    }
                    return r
                }
                return nil
            }

                if elementStatus != .success || focusedElement == nil {
                self.logger.debug("⚠️ [FOCUS FAILED] systemWide CopyAttributeValue failed: \(elementStatus.rawValue). Trying fallback...")
                
                // Fallback: Check frontmost app windows directly (Siri often lacks system-wide focus)
                if let frontApp = NSWorkspace.shared.frontmostApplication {
                    let frontAppPID = frontApp.processIdentifier
                    let frontAppElement = AXUIElementCreateApplication(frontAppPID)
                    let frontAppName = frontApp.localizedName ?? "Unknown"
                    
                    // Specific targets that tend to hide focus: Siri, NotificationCenter, Spotlight
                    let stealthApps = ["Siri", "SiriNCService", "NotificationCenter", "Spotlight"]
                    if stealthApps.contains(frontAppName) || frontApp.bundleIdentifier?.contains("apple.siri") == true {
                        self.logger.debug("🎯 [SIRI FALLBACK] Probing frontmost app: \(frontAppName) (PID: \(frontAppPID))")
                        
                        var windowsRef: CFTypeRef?
                        if AXUIElementCopyAttributeValue(frontAppElement, kAXWindowsAttribute as CFString, &windowsRef) == .success,
                           let windows = windowsRef as? [AXUIElement], let firstWindow = windows.first {
                            // Use first window as starting point for drill-down
                            focusedElement = firstWindow
                        }
                    }
                }
            }

                if let elementRef = focusedElement {
                var element = elementRef as! AXUIElement
                
                // DIAGNOSTICS: Identify Target App & Role
                var pid: pid_t = 0
                AXUIElementGetPid(element, &pid)
                let app = NSRunningApplication(processIdentifier: pid)
                let appName = app?.localizedName ?? "Unknown(\(pid))"
                let bundleID = app?.bundleIdentifier ?? ""
                self.currentAppName = appName
                self.currentAppBundleID = bundleID
                self.lastFocusedAppName = appName
                self.lastFocusedBundleID = bundleID
                let codexDiag = self.isCodexLike(appName: appName, bundleID: bundleID)
                
                // v0.1.5: BLACKLIST Aether's own process to avoid hidden WebView focus
                if bundleID == Bundle.main.bundleIdentifier {
                    // self.logger.debug("🛡 [BLACKLIST] Ignoring self-focus for Aether to avoid false-positive Typing Mode.")
                    DispatchQueue.main.async {
                        self.isFetchingCaret = false
                        // Avoid high-frequency no-op relayout churn when Aether itself is frontmost.
                        let hadCaretState = (self.caretRect != nil) || self.isCaretStickyActive || (self.inputContextRect != nil)
                        self.caretRect = nil
                        self.lastCaretRect = nil
                        self.lastCaretRectAt = nil
                        self.caretSourceBundleID = nil
                        self.inputContextRect = nil
                        self.isCaretStickyActive = false
                        self.caretStickyTimer?.invalidate()
                        self.caretStickyTimer = nil
                        if hadCaretState {
                            self.repositionWindow()
                        }
                    }
                    return
                }

                var roleValue: CFTypeRef?
                var role = ""
                if AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleValue) == .success {
                    role = roleValue as? String ?? ""
                }
                
                // Drill-down should be conservative. Aggressive drill-down on generic roles (AXGroup/AXButton)
                // can incorrectly lock web apps (Codex/Electron) into AXTextArea typing mode.
                let shouldDrillDown =
                    role == "AXWindow" ||
                    role == "AXSheet" ||
                    role == "AXScrollArea" ||
                    role == "AXSplitGroup" ||
                    self.isSiriLike(appName: appName, bundleID: bundleID)
                if shouldDrillDown {
                    if let child = self.findFirstTextField(in: element) {
                        element = child
                        // Re-fetch role
                        if AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleValue) == .success {
                             let newRole = roleValue as? String ?? ""
                             self.logger.debug("⬇️ [DRILL DOWN] Swapped \(role) -> \(newRole)")
                             role = newRole
                        }
                    } else if bundleID.contains("apple.siri") {
                        // Special Case: Even if drill-down fails, if it's Siri's main window, 
                        // we prefer Typing Mode because Siri is almost always for input.
                        self.logger.debug("🎯 [SIRI FORCE] Drill-down failed but App is Siri. Forcing Typing mode check.")
                        // We keep the role as is, and let the isEditable check handle it
                    }
                }
                
                self.logger.debug("🔎 [FOCUS DETECTED] App: \(appName) (PID: \(pid)) | Role: \(role)")
                if codexDiag && self.shouldEmitXcodeDiagLog() {
                    self.logger.debug("⚠️ [CODEX DIAG] focus role=\(role) pid=\(pid)")
                }
                
                // --- Editability Check ---
                let directEditableRoles = ["AXTextField", "AXSearchField", "AXComboBox", "AXHTMLTextInput"]
                let conditionalEditableRoles = ["AXTextArea", "AXWebArea", "AXStaticText"]
                let axEditable = self.readAXBool(element, attribute: "AXEditable")
                let axFocused = self.readAXBool(element, attribute: "AXFocused")
                let hasInsertionContext = self.hasTextInsertionContext(element)
                var isEditable = directEditableRoles.contains(role)
                
                // [BRUTE FORCE] If this is Siri, it's ALWAYS an input context.
                if self.isSiriLike(appName: appName, bundleID: bundleID) {
                    isEditable = true
                    self.logger.debug("🎯 [SIRI FAIL-SAFE] Forcing Typing Mode for Siri process.")
                }

                if conditionalEditableRoles.contains(role) {
                    if role == "AXWebArea" {
                        // AXWebArea can retain stale marker/range info in web apps.
                        // Require BOTH editable flag and insertion context to count as active typing.
                        isEditable = ((axEditable == true) && hasInsertionContext && axFocused != false) || isEditable
                    } else if role == "AXTextArea" {
                        // TextArea is considered active only with insertion context
                        // (or explicit direct role match / Siri fail-safe).
                        isEditable = ((hasInsertionContext || axEditable == true) && axFocused != false) || isEditable
                    } else {
                        isEditable = (axEditable == true) || hasInsertionContext || isEditable
                    }
                }

                if axEditable == true && role != "AXWebArea" && role != "AXTextArea" {
                    isEditable = true
                }

                if self.isTerminalLike(bundleID: bundleID), axEditable != true && !hasInsertionContext {
                    isEditable = false
                }
                if self.isCodexLike(appName: appName, bundleID: bundleID),
                   role == "AXTextArea" || role == "AXWebArea" {
                    isEditable = (axFocused == true) && (hasInsertionContext || axEditable == true)
                }
                if self.isCodexLike(appName: appName, bundleID: bundleID),
                   role == "AXGroup",
                   hasInsertionContext,
                   axFocused != false {
                    isEditable = true
                }
                if axFocused == false && !self.isSiriLike(appName: appName, bundleID: bundleID) {
                    isEditable = false
                }
                 
                 self.logger.debug("📝 [EDITABILITY] Role: \(role) → isEditable: \(isEditable) | AXFocused: \(String(describing: axFocused))")
                 if codexDiag && self.shouldEmitXcodeDiagLog() {
                     self.logger.debug("⚠️ [CODEX DIAG] editable=\(isEditable) axFocused=\(String(describing: axFocused)) axEditable=\(String(describing: axEditable)) insertion=\(hasInsertionContext)")
                 }
                 focusedIsEditable = isEditable
                
                // --- NEW: Fetch Parent Window for validation ---
                var windowValue: CFTypeRef?
                var windowFrame: CGRect? = nil
                if AXUIElementCopyAttributeValue(element, kAXWindowAttribute as CFString, &windowValue) == .success {
                    let windowElement = windowValue as! AXUIElement
                    var posVal: CFTypeRef?
                    var sizeVal: CFTypeRef?
                    if AXUIElementCopyAttributeValue(windowElement, kAXPositionAttribute as CFString, &posVal) == .success,
                       AXUIElementCopyAttributeValue(windowElement, kAXSizeAttribute as CFString, &sizeVal) == .success {
                        var p = CGPoint.zero
                        var s = CGSize.zero
                        if AXValueGetValue(posVal as! AXValue, .cgPoint, &p),
                           AXValueGetValue(sizeVal as! AXValue, .cgSize, &s) {
                            // Convert window raw (AX) -> AppKit (Y-flip)
                            // Reuse extractRect logic implicitly: windowFrame needs same coord system as caret
                            let rawWindowRect = CGRect(origin: p, size: s)
                            // Manually apply flip here since extractRect is for CFTypeRef
                            if let primary = NSScreen.screens.first {
                                let h = primary.frame.height
                                let appKitY = h - rawWindowRect.origin.y - rawWindowRect.height
                                windowFrame = CGRect(x: rawWindowRect.origin.x, y: appKitY, width: rawWindowRect.width, height: rawWindowRect.height)
                                self.logger.debug("🔲 [WINDOW FRAME KEY] RawY=\(p.y) -> AppKitY=\(appKitY) | Rect=\(windowFrame!.debugDescription)")
                            }
                        }
                    } else {
                         self.logger.debug("⚠️ [WINDOW FRAME] Failed to get pos/size for window element.")
                    }
                } else {
                    self.logger.debug("⚠️ [WINDOW FRAME] No parent window found for element.")
                }


                // Helper: Validate Rect against Window
                func isValid(_ r: CGRect, in w: CGRect?) -> Bool {
                    // 1. Check for (0,0) anomaly (rarely valid for a caret in standard usage)
                    if r.origin.x == 0 && r.origin.y == 0 {
                         self.logger.debug("❌ [VALIDATION] Rejected: Rect is (0,0)")
                         return false
                    }
                    // 2. Window Bounds Check (with leniency for tooltips/popups)
                    if let win = w {
                        let expanded = win.insetBy(dx: -50, dy: -50)
                        if !expanded.contains(r.origin) {
                             self.logger.debug("❌ [VALIDATION] Rejected: Origin \(r.origin.debugDescription) outside Window \(win.debugDescription) (Expanded: \(expanded.debugDescription))")
                             return false
                        }
                    }
                    return true
                }
                
                // Helper: Fallback validation (On Screen?)
                func isValidOnScreen(_ r: CGRect) -> Bool {
                    for screen in NSScreen.screens {
                        if screen.frame.contains(r.origin) { return true }
                    }
                    self.logger.debug("❌ [VALIDATION] Rejected: Origin \(r.origin.debugDescription) not on any screen.")
                    return false
                }

                let singleLineRoles: Set<String> = ["AXTextField", "AXSearchField", "AXComboBox", "AXHTMLTextInput"]

                // --- NEW: Try Web-Specific "Marker Range" (Chrome/Edge/Safari) ---
                // Based on InputSourcePro/InputMethodKit heuristics
                var caretWasBogus = false  // Track if caret returned garbage (0,0) for fallback logic
                var sawNonCaretGeometry = false // Track "selection/bounds-like" rects to avoid bad fallback in web text areas
                var selectedTextRange: CFRange?
                var axTruthCaretRect: CGRect?
                var markerRangeValue: CFTypeRef?
                let markerStatus = AXUIElementCopyAttributeValue(element, "AXSelectedTextMarkerRange" as CFString, &markerRangeValue)
                
                if markerStatus == .success && isEditable {
                    var boundsValue: CFTypeRef?
                    let boundsStatus = AXUIElementCopyParameterizedAttributeValue(element, "AXBoundsForTextMarkerRange" as CFString, markerRangeValue!, &boundsValue)
                    
                    if boundsStatus == .success {
                        var rawR = CGRect.zero
                        if AXValueGetValue(boundsValue as! AXValue, .cgRect, &rawR) {
                            self.logger.debug("--- [AX MARKER RAW] x=\(rawR.origin.x), y=\(rawR.origin.y)")
                            
                            // PRE-FLIP: Reject known bogus marker geometries.
                            if (rawR.origin.x == 0 && rawR.origin.y == 0) || (rawR.width <= 1 && rawR.height <= 1) {
                                if self.shouldEmitPreFlipRejectLog() {
                                    self.logger.debug("🚨 [PRE-FLIP REJECT] Web Marker raw AX coords are bogus (\(rawR.debugDescription)).")
                                }
                                caretWasBogus = true
                            } else if rawR.width > 80 || rawR.height > 80 || (rawR.width * rawR.height) > 2400 {
                                // Many web/electron apps sometimes return selected-block bounds here.
                                self.logger.debug("🚫 [NON-CARET GEOMETRY] Web Marker looks like selection/bounds (\(rawR.debugDescription)); skip as caret.")
                                sawNonCaretGeometry = true
                            } else {
                                // 1. Convert to AppKit
                                if let r = extractRect(from: boundsValue!) {
                                    // 2. Validate in AppKit Coords
                                        if isValid(r, in: windowFrame) {
                                            newRect = r
                                            axTruthCaretRect = r
                                            self.logger.debug("✅ Web Marker Caret detected (Window Valid).")
                                        } else if (windowFrame == nil || singleLineRoles.contains(role)) && isValidOnScreen(r) {
                                            newRect = r
                                            axTruthCaretRect = r
                                            self.logger.debug("⚠️ Web Marker Caret detected (Screen Valid fallback for role: \(role)).")
                                        } else {
                                            self.logger.debug("🚨 [INVALID] Web Marker rejected by validation relative to Window/Screen.")
                                    }
                                }
                            }
                        }
                    }
                }
                if codexDiag && self.shouldEmitXcodeDiagLog() {
                    self.logger.debug("⚠️ [CODEX DIAG] markerStatus=\(markerStatus.rawValue)")
                }

                // 3. Get Selected Text Range (Standard/Native)
                if newRect == nil && isEditable { // Only try if editable
                    var selectedRangeValue: CFTypeRef?
                    let rangeStatus = AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &selectedRangeValue)
                    
                    if rangeStatus == .success {
                        if let selectedRangeValue {
                            let rangeAX = selectedRangeValue as! AXValue
                            var range = CFRange()
                            if AXValueGetValue(rangeAX, .cfRange, &range) {
                                selectedTextRange = range
                            }
                        }
                        var boundsValue: CFTypeRef?
                        let boundsStatus = AXUIElementCopyParameterizedAttributeValue(element, kAXBoundsForRangeParameterizedAttribute as CFString, selectedRangeValue!, &boundsValue)
                        
                        if boundsStatus == .success {
                            var rawR = CGRect.zero
                            if AXValueGetValue(boundsValue as! AXValue, .cgRect, &rawR) {
                                self.logger.debug("--- [AX RAW CARET] x=\(rawR.origin.x), y=\(rawR.origin.y)")
                                
                                // PRE-FLIP: Reject known bogus caret geometries.
                                if (rawR.origin.x == 0 && rawR.origin.y == 0) || (rawR.width <= 1 && rawR.height <= 1) {
                                    if self.shouldEmitPreFlipRejectLog() {
                                        self.logger.debug("🚨 [PRE-FLIP REJECT] Standard Caret raw AX coords are bogus (\(rawR.debugDescription)).")
                                    }
                                    caretWasBogus = true  // Signal: we KNOW it's an input field, just bad coords
                                } else if rawR.width > 80 || rawR.height > 80 || (rawR.width * rawR.height) > 2400 {
                                    self.logger.debug("🚫 [NON-CARET GEOMETRY] Standard range looks like selection/bounds (\(rawR.debugDescription)); skip as caret.")
                                    sawNonCaretGeometry = true
                                } else {
                                    // 1. Convert to AppKit
                                    if let r = extractRect(from: boundsValue!) {
                                        // 2. Validate in AppKit Coords
                                        if isValid(r, in: windowFrame) {
                                            newRect = r
                                            axTruthCaretRect = r
                                            self.logger.debug("✅ Standard Caret detected (Window Valid).")
                                        } else if (windowFrame == nil || singleLineRoles.contains(role)) && isValidOnScreen(r) {
                                            newRect = r
                                            axTruthCaretRect = r
                                            self.logger.debug("⚠️ Standard Caret detected (Screen Valid fallback for role: \(role)).")
                                        } else {
                                            self.logger.debug("🚨 [INVALID] Caret rejected by validation.")
                                        }
                                    }
                                }
                            }
                        }
                    }
                    if codexDiag && self.shouldEmitXcodeDiagLog() {
                        let sel = selectedTextRange.map { "\($0.location):\($0.length)" } ?? "nil"
                        self.logger.debug("⚠️ [CODEX DIAG] rangeStatus=\(rangeStatus.rawValue) selectedRange=\(sel)")
                    }
                    
                    if newRect == nil {
                            // Only log if Marker also failed
                            if markerStatus != .success {
                                self.logger.debug("❌ AX range failure: \(rangeStatus.rawValue)")
                            }
                    }
                }

                // AX baseline vs single-line estimate compare (independent of IME bridge).
                if let axRect = axTruthCaretRect, singleLineRoles.contains(role), let range = selectedTextRange {
                    var posValue: CFTypeRef?
                    var sizeValue: CFTypeRef?
                    if AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &posValue) == .success,
                       AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeValue) == .success {
                        var p = CGPoint.zero
                        var s = CGSize.zero
                        if AXValueGetValue(posValue as! AXValue, .cgPoint, &p),
                           AXValueGetValue(sizeValue as! AXValue, .cgSize, &s) {
                            let rRaw = CGRect(origin: p, size: s)
                            let axValue = AXValueCreate(.cgRect, [rRaw])
                            if let rAppkit = extractRect(from: axValue as CFTypeRef) {
                                let h = min(max(14.0, rAppkit.height - 6.0), 24.0)
                                let y = rAppkit.minY + max(0.0, (rAppkit.height - h) * 0.5)
                                let leadingInset = min(max(10.0, rAppkit.height * 0.5), 22.0)
                                let trailingInset: CGFloat = 10.0
                                let usableWidth = max(8.0, rAppkit.width - leadingInset - trailingInset)
                                var caretXOffset: CGFloat = 0.0
                                var valueRef: CFTypeRef?
                                if AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &valueRef) == .success,
                                   let valueStr = valueRef as? String {
                                    let total = max(0, valueStr.count)
                                    let location = max(0, min(range.location + range.length, total))
                                    if total > 0 {
                                        let step = self.preferredSingleLineStep(bundleID: bundleID, role: role, fieldHeight: rAppkit.height)
                                        let units = self.weightedCaretUnits(in: valueStr, location: location)
                                        caretXOffset = min(units * step, usableWidth)
                                        if units > 0 {
                                            let observed = (axRect.midX - (rAppkit.minX + leadingInset)) / units
                                            if observed.isFinite {
                                                self.updateSingleLineStepSample(bundleID: bundleID, role: role, observedStep: observed)
                                            }
                                        }
                                    }
                                }
                                let estimate = CGRect(x: rAppkit.minX + leadingInset + caretXOffset, y: y, width: 2.0, height: h)
                                let delta = hypot(axRect.midX - estimate.midX, axRect.midY - estimate.midY)
                                if self.shouldEmitCaretCompareLog(minInterval: 0.25) {
                                    self.logger.debug("⚠️ [AX-EST COMPARE] delta=\(Int(delta)) | AX=\(axRect.debugDescription) | EST=\(estimate.debugDescription)")
                                }
                            }
                        }
                    }
                }
                    
                if newRect == nil {
                    // Fallback 1: Element Bounds
                    // Use the focused element's own position/size as the anchor.
                    //
                    // TWO scenarios allow this fallback:
                    // A) Role is a known text input type (AXTextField, AXTextArea, etc.)
                    // B) Caret query succeeded but returned bogus (0,0) — this PROVES it's an input
                    //    context even if the role is non-standard (e.g. web-based inputs in Electron apps).
                    let validTextRoles = ["AXTextField", "AXTextArea", "AXSearchField", "AXComboBox", "AXHTMLTextInput"]
                    let isKnownInputRole = validTextRoles.contains(role)
                    
                    let avoidElementFallbackForWebRole = (role == "AXTextArea" || role == "AXWebArea") && sawNonCaretGeometry && !codexDiag
                    let avoidElementFallbackForCodexGroup = codexDiag && role == "AXGroup"
                    if avoidElementFallbackForWebRole || avoidElementFallbackForCodexGroup {
                        self.logger.debug("🚫 [FALLBACK BLOCKED] Web text role had non-caret geometry; keep last valid caret instead of using element bounds.")
                        shouldTemporarilyKeepLastCaret = true
                    } else if isKnownInputRole || caretWasBogus || isEditable {
                        if caretWasBogus && !isKnownInputRole {
                            self.logger.debug("🔄 [BOGUS CARET FALLBACK] Role '\(role)' not in text roles, but caret query proved input context. Using element bounds.")
                        }
                        var posValue: CFTypeRef?
                        var sizeValue: CFTypeRef?
                        if AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &posValue) == .success,
                            AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeValue) == .success {
                            var p = CGPoint.zero
                            var s = CGSize.zero
                            if AXValueGetValue(posValue as! AXValue, .cgPoint, &p),
                                AXValueGetValue(sizeValue as! AXValue, .cgSize, &s) {
                                let r_raw = CGRect(origin: p, size: s)
                                
                                // 1. Convert to AppKit First
                                let axValue = AXValueCreate(.cgRect, [r_raw])
                                if let r_appkit = extractRect(from: axValue as CFTypeRef) {
                                    
                                    // 2. Validate in AppKit Coords
                                    var isValidElement = isValid(r_appkit, in: windowFrame)
                                    
                                    // HEURISTIC: "Huge Element Rejection"
                                    if isValidElement, let screen = NSScreen.main {
                                        let sFrame = screen.frame
                                        // Size check is coord-system independent
                                        if r_appkit.width > sFrame.width * 0.7 && r_appkit.height > sFrame.height * 0.7 {
                                            self.logger.debug("⚠️ [HEURISTIC] Element is huge (>70% screen). Ignoring.")
                                            isValidElement = false
                                        }
                                    }

                                    // AXTextArea/AXWebArea in web/electron UIs often report textarea bounds
                                    // instead of insertion caret; reject oversized element anchors.
                                    if isValidElement, (role == "AXTextArea" || role == "AXWebArea"),
                                       (r_appkit.width > 220 || r_appkit.height > 70) {
                                        // Use a weak synthetic caret anchor for wide web text areas
                                        // (Codex/Electron often expose textarea bounds instead of caret).
                                        let h = min(max(14.0, r_appkit.height), 24.0)
                                        let y = r_appkit.minY + max(0.0, (r_appkit.height - h) * 0.5)
                                        let x = r_appkit.minX + 12.0
                                        newRect = CGRect(x: x, y: y, width: 2.0, height: h)
                                        newInputContextRect = r_appkit
                                        shouldTemporarilyKeepLastCaret = true
                                        self.logger.debug("⚠️ [WEAK CARET] Large web text bounds; using synthetic caret anchor (\(newRect!.debugDescription)).")
                                        isValidElement = false
                                    }
                                    
                                    if isValidElement {
                                        if singleLineRoles.contains(role) {
                                            // Single-line browser fields (address/search) often only expose control bounds.
                                            // Use a synthetic caret anchor and estimate x from selected range.
                                            let h = min(max(14.0, r_appkit.height - 6.0), 24.0)
                                            let y = r_appkit.minY + max(0.0, (r_appkit.height - h) * 0.5)
                                            let leadingInset = min(max(10.0, r_appkit.height * 0.5), 22.0)
                                            let trailingInset: CGFloat = 10.0
                                            let usableWidth = max(8.0, r_appkit.width - leadingInset - trailingInset)
                                            var caretXOffset: CGFloat = 0.0
                                            if let range = selectedTextRange {
                                                var valueRef: CFTypeRef?
                                                if AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &valueRef) == .success,
                                                   let valueStr = valueRef as? String {
                                                    let total = max(0, valueStr.count)
                                                    let location = max(0, min(range.location + range.length, total))
                                                    if total > 0 {
                                                        // Fixed-width step model with per-app adaptive calibration.
                                                        let step = self.preferredSingleLineStep(bundleID: bundleID, role: role, fieldHeight: r_appkit.height)
                                                        let units = self.weightedCaretUnits(in: valueStr, location: location)
                                                        caretXOffset = min(units * step, usableWidth)
                                                    }
                                                }
                                            }
                                            let x = r_appkit.minX + leadingInset + caretXOffset
                                            newRect = CGRect(x: x, y: y, width: 2.0, height: h)
                                            newInputContextRect = r_appkit
                                            shouldTemporarilyKeepLastCaret = true
                                            self.logger.debug("✅ Element Fallback used with dynamic single-line caret (role: \(role), offset: \(Int(caretXOffset))).")
                                        } else {
                                            newRect = r_appkit
                                            if role == "AXTextArea" || role == "AXWebArea" {
                                                newInputContextRect = r_appkit
                                            }
                                            self.logger.debug("✅ Element Fallback used (role: \(role)).")
                                        }
                                    } else {
                                        self.logger.debug("🚨 [INVALID] Fallback Element rejected.")
                                    }
                                }
                            }
                        }
                    } else {
                        self.logger.debug("🚫 [FALLBACK BLOCKED] Role '\(role)' is not a text field. Skipping element bounds.")
                    }
                }
                if codexDiag && self.shouldEmitXcodeDiagLog() {
                    self.logger.debug("⚠️ [CODEX DIAG] resolveResult caret=\(newRect?.debugDescription ?? "nil") context=\(newInputContextRect?.debugDescription ?? "nil") keepLast=\(shouldTemporarilyKeepLastCaret)")
                }
                } else {
                    self.logger.debug("❌ AX focus failure: \(elementStatus.rawValue)")
                }
            }

            if let bridgedRect = preferredBridgedRect {
                if let axRect = newRect {
                    let delta = hypot(axRect.midX - bridgedRect.midX, axRect.midY - bridgedRect.midY)
                    if self.shouldEmitCaretCompareLog() {
                        self.logger.debug("⚠️ [CARET COMPARE] delta=\(Int(delta)) | AX=\(axRect.debugDescription) | IME=\(bridgedRect.debugDescription)")
                    }
                    if delta >= 12 {
                        self.logger.debug("⚠️ [CARET DELTA] AX vs IME delta=\(Int(delta)) | AX=\(axRect.debugDescription) | IME=\(bridgedRect.debugDescription)")
                    }
                } else {
                    self.logger.debug("⚠️ [CARET DELTA] AX missing while IME available; using IME caret.")
                }
                newRect = bridgedRect
                newInputContextRect = preferredBridgedInputContextRect
                newCaretSourceBundleID = preferredBridgedBundleID ?? NSWorkspace.shared.frontmostApplication?.bundleIdentifier
                usedInputMethodBridge = true
            }
            if newRect != nil && newCaretSourceBundleID == nil {
                newCaretSourceBundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? self.currentAppBundleID ?? self.lastFocusedBundleID
            }
            DispatchQueue.main.async {
                self.isFetchingCaret = false // Reset Flag
                // If focus is lost or fails, CLEAR THE RECT immediately to avoid stale positioning
                if newRect == nil {
                    if !focusedIsEditable {
                        self.isCaretStickyActive = false
                        self.caretStickyTimer?.invalidate()
                        self.caretStickyTimer = nil
                        self.caretRect = nil
                        self.caretSourceBundleID = nil
                        self.inputContextRect = nil
                        self.repositionWindow()
                        return
                    }
                    // In editable context, AX can transiently fail or return selection bounds.
                    // Preserve last valid caret to avoid mode/position flicker.
                    if focusedIsEditable && shouldTemporarilyKeepLastCaret &&
                        self.recentCaretRect() != nil {
                        self.logger.debug("🧷 [KEEP LAST CARET] Editable context without valid caret geometry; preserving previous caret.")
                        return
                    }
                    if self.caretRect != nil && !self.isCaretStickyActive {
                        // Adaptive sticky duration: shorter for Siri/Terminal, moderate elsewhere.
                        let sticky = self.stickyDuration(for: self.lastFocusedBundleID, appName: self.lastFocusedAppName)
                        self.logger.debug("⏳ Focus lost, entering Sticky Grace Period (\(sticky)s).")
                        self.isCaretStickyActive = true
                        self.caretStickyTimer?.invalidate()
                        self.caretStickyTimer = Timer.scheduledTimer(withTimeInterval: sticky, repeats: false) { [weak self] _ in
                             guard let self = self else { return }
                             if self.isCaretStickyActive {
                                self.logger.debug("❄️ Sticky Grace Period expired, clearing caretRect.")
                                self.isCaretStickyActive = false
                                self.caretRect = nil
                                self.caretSourceBundleID = nil
                                self.inputContextRect = nil
                                self.repositionWindow() // Final switch to Command Mode
                             }
                        }
                    } else if self.isCaretStickyActive && self.recentCaretRect() == nil {
                        // Sticky already expired logically; avoid getting stuck in typing mode.
                        self.isCaretStickyActive = false
                        self.caretStickyTimer?.invalidate()
                        self.caretStickyTimer = nil
                        self.caretRect = nil
                        self.caretSourceBundleID = nil
                        self.inputContextRect = nil
                        self.repositionWindow()
                    }
                    return
                }
                
                // If focus recovered during sticky period, cancel it
                if self.isCaretStickyActive {
                    self.logger.debug("✨ Focus recovered during Sticky Period.")
                    self.isCaretStickyActive = false
                    self.caretStickyTimer?.invalidate()
                    self.caretStickyTimer = nil
                }
                
                let oldRect = self.caretRect
                let oldInputRect = self.inputContextRect
                if self.lastCaretRect == nil, let initial = newRect {
                    self.logger.debug("🆕 Initial focus detected at \(initial.debugDescription)")
                }

                self.caretRect = newRect
                self.lastCaretRect = newRect
                self.lastCaretRectAt = Date()
                self.caretSourceBundleID = newCaretSourceBundleID
                self.inputContextRect = newInputContextRect

                // Reposition whenever caret anchor actually changes, not only on large jumps.
                var shouldReposition = false
                switch (oldRect, newRect) {
                case (.none, .some), (.some, .none):
                    shouldReposition = true
                case let (.some(old), .some(current)):
                    let dist = sqrt(pow(old.midX - current.midX, 2) + pow(old.midY - current.midY, 2))
                    if dist > 2 {
                        shouldReposition = true
                    }
                default:
                    break
                }
                if !shouldReposition, oldInputRect != newInputContextRect {
                    shouldReposition = true
                }

                if shouldReposition {
                    self.repositionWindow()
                }
            }
        }
    }

    private func repositionWindow() {
        guard let panel = hudWindow else { return }
        
        // NOTE: updateCaretRect() is NO LONGER called here.
        // It is triggered by AXObserver events, mouse clicks, and app switches independently.
        // repositionWindow() only reads the current caretRect state and positions the window.
        
        let mouseLoc = NSEvent.mouseLocation // Bottom-Left Reference
        
        // HUD Size
        panel.contentView?.layoutSubtreeIfNeeded()
        let size = panel.contentView?.fittingSize ?? CGSize(width: 200, height: 60)
        let padding: CGFloat = 10
        
        let isSiri = isSiriLike(appName: currentAppName, bundleID: currentAppBundleID ?? "")
        
        // ---------------------------------------------------------
        // 1. Determine Anchor & Mode
        // ---------------------------------------------------------
        var activeCaret = self.caretRect
        if activeCaret == nil && self.isCaretStickyActive {
            activeCaret = self.recentCaretRect()
        }
        let frontApp = NSWorkspace.shared.frontmostApplication
        let codexFrontmost = isCodexLike(appName: frontApp?.localizedName, bundleID: frontApp?.bundleIdentifier)
        if codexFrontmost,
           let sourceBundle = self.caretSourceBundleID,
           let frontBundle = frontApp?.bundleIdentifier,
           !sourceBundle.isEmpty,
           !isLikelySameAppFamily(sourceBundle, frontBundle) {
            activeCaret = nil
            self.isCaretStickyActive = false
            self.caretStickyTimer?.invalidate()
            self.caretStickyTimer = nil
            self.caretRect = nil
            self.caretSourceBundleID = nil
            self.inputContextRect = nil
        }
        var finalTypingMode = (activeCaret != nil)
        var anchor: CGPoint = finalTypingMode ? CGPoint(x: (activeCaret!.width > 4 ? activeCaret!.maxX : activeCaret!.midX), y: activeCaret!.minY) : mouseLoc
        
        // FINAL DIAGNOSTIC LOG (Throttled: only log MAJOR movements or mode changes)
        let modeStr = finalTypingMode ? "Typing" : "Command"
        let dist = sqrt(pow(anchor.x - lastLoggedAnchor.x, 2) + pow(anchor.y - lastLoggedAnchor.y, 2))
        
        // v0.1.4/0.1.5: Threshold increased to 100px for less noise
        // v0.1.6: Silency Command mode movement log completely, only log mode changes or Typing mode updates
        let isMajorMovement = dist > 100
        let isModeChange = modeStr != lastLoggedMode
        
        // v0.1.8-Hotfix: If major movement occurs during sticky period, force break it to Command mode
        if isMajorMovement && self.isCaretStickyActive {
            self.logger.debug("💥 Major movement detected during Sticky Period. Force-breaking to Command Mode.")
            self.isCaretStickyActive = false
            self.caretRect = nil
            self.caretStickyTimer?.invalidate()
            self.caretStickyTimer = nil
            activeCaret = nil
            finalTypingMode = false
            anchor = mouseLoc
        }

        let finalModeStr = finalTypingMode ? "Typing" : "Command"

        if state.isListening && state.isDictating != finalTypingMode {
            state.isDictating = finalTypingMode
            state.stateChanged.send()
        }
        
        if isModeChange || (finalTypingMode && isMajorMovement) {
            self.logger.debug("📊 [HUD CALC] Mode: \(finalModeStr) | Anchor: (\(Int(anchor.x)), \(Int(anchor.y))) | Caret: \(self.caretRect?.debugDescription ?? "N/A") (Sticky: \(self.isCaretStickyActive)) | MSG: '\(self.state.message)'")
            lastLoggedAnchor = anchor
            lastLoggedMode = finalModeStr
        }
        
        // ---------------------------------------------------------
        // 2. Define High-Priority Avoidance Zones
        // ---------------------------------------------------------
        var zones: [CGRect] = []
        
        // Always avoid Mouse Cursor
        let mouseZone = CGRect(x: mouseLoc.x - 15, y: mouseLoc.y - 15, width: 30, height: 30)
        zones.append(mouseZone)
        
        // Always avoid Caret (if present)
        if let caret = activeCaret {
            zones.append(caret.insetBy(dx: -5, dy: -2)) 
        }
        // In typing mode, also avoid covering the current input region if known.
        if finalTypingMode, let inputRect = self.inputContextRect {
            zones.append(inputRect.insetBy(dx: -8, dy: -6))
        }
        
        // ---------------------------------------------------------
        // 3. Evaluate Candidate Positions
        // ---------------------------------------------------------
        struct Candidate {
            let offset: CGPoint
            let name: String
        }
        
        let candidates: [Candidate]
        if finalTypingMode {
            // Typing Mode: Prefer ABOVE caret (to avoid IME candidates below), then below
            candidates = [
                Candidate(offset: CGPoint(x: padding, y: padding), name: "Caret-Above-Right"),
                Candidate(offset: CGPoint(x: padding, y: -size.height - padding), name: "Caret-Below-Right"),
                Candidate(offset: CGPoint(x: -size.width - padding, y: padding), name: "Caret-Above-Left"),
                Candidate(offset: CGPoint(x: -size.width - padding, y: -size.height - padding), name: "Caret-Below-Left")
            ]
        } else {
            // Command Mode: Prefer Bottom-Right of mouse
            candidates = [
                Candidate(offset: CGPoint(x: padding, y: -size.height - padding), name: "Mouse-Bottom-Right"),
                Candidate(offset: CGPoint(x: padding, y: padding), name: "Mouse-Top-Right"),
                Candidate(offset: CGPoint(x: -size.width - padding, y: -size.height - padding), name: "Mouse-Bottom-Left"),
                Candidate(offset: CGPoint(x: -size.width - padding, y: padding), name: "Mouse-Top-Left")
            ]
        }
        
        var bestPos: CGPoint? = nil
        
        // Use caret screen in typing mode; mouse screen otherwise.
        // This prevents HUD from jumping far away when caret and mouse are on different displays.
        let referencePoint: CGPoint = {
            if finalTypingMode, let caret = activeCaret {
                return CGPoint(x: caret.midX, y: caret.midY)
            }
            return mouseLoc
        }()
        let currentScreen = NSScreen.screens.first(where: { $0.frame.contains(referencePoint) }) ?? NSScreen.main
        let screenName = currentScreen?.localizedName ?? "Unknown"
        let screenFrameStr = currentScreen?.frame.debugDescription ?? "Zero"
        
        // Throttled Screen Detection Log (v0.1.4: Only log on actual screen switch)
        if screenName != lastLoggedScreenName {
             self.logger.debug("🖥 [SCREEN DETECT] Mouse: (\(Int(mouseLoc.x)), \(Int(mouseLoc.y))) -> Screen: \(screenName) Frame: \(screenFrameStr)")
             lastLoggedScreenName = screenName
        }
        
        if let screen = currentScreen {
            let screenFrame = screen.visibleFrame
            
            for cand in candidates {
                let x = anchor.x + cand.offset.x
                let y = anchor.y + cand.offset.y
                let frame = CGRect(origin: CGPoint(x: x, y: y), size: size)
                
                
                // Rule 1: Must be on screen
                // Siri Exception: Allow overlapping with top edge/menu bar areas if needed
                if !screenFrame.contains(frame) && !isSiri { 
                    continue 
                } else if isSiri {
                    // For Siri, still ensure it's within the full screen (not just visibleFrame)
                    if !screen.frame.contains(frame) { continue }
                }
                
                // Rule 2: Must not collide with mouse or caret
                // Siri Exception: Allow overlapping with caret zone to stay flush/tight
                var collision = false
                if !isSiri {
                    for zone in zones {
                        if frame.intersects(zone) {
                            collision = true
                            break 
                        }
                    }
                }
                
                if !collision {
                    bestPos = frame.origin
                    break
                }
            }
            
            // ---------------------------------------------------------
            // 4. Fallback (Screen Edge Constraints)
            // ---------------------------------------------------------
            if bestPos == nil {
                var x = anchor.x + padding
                var y = anchor.y - size.height - padding
                if finalTypingMode, let inputRect = self.inputContextRect {
                    // Prefer staying outside the editable text region when candidate search fails.
                    y = inputRect.maxY + padding
                    x = min(max(inputRect.minX, x), inputRect.maxX - size.width)
                }
                // Clamp to screen (visibleFrame normally, but full screen for Siri)
                let clampFrame = isSiri ? screen.frame : screenFrame
                
                x = max(clampFrame.minX + padding, min(x, clampFrame.maxX - size.width - padding))
                y = max(clampFrame.minY + padding, min(y, clampFrame.maxY - size.height - padding))
                bestPos = CGPoint(x: x, y: y)
            }
        } else {
             bestPos = CGPoint(x: anchor.x + padding, y: anchor.y - size.height - padding)
        }
        
        if let pos = bestPos {
            // Apply positioning
            panel.setFrameOrigin(pos)
            if panel.frame.size != size {
                 panel.setContentSize(size)
            }
        }
    }
    
    private func scheduleHide(delay: TimeInterval) {
        hideTask?.cancel()
        let task = DispatchWorkItem { [weak self] in
            self?.performHide()
        }
        hideTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: task)
    }
    
    private func cancelHide() {
        hideTask?.cancel()
    }
    
    private func performHide() {
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.2
            self.hudWindow?.animator().alphaValue = 0
        }, completionHandler: {
            self.hudWindow?.orderOut(nil)
            self.stopFollowTimer()
        })
    }
    
    // MARK: - SwiftUI View
    
    private struct HUDView: View {
        @ObservedObject var state: HUDState
        @State private var isAnimating: Bool = false
        
        var body: some View {
            let displayLanguage: String = {
                if state.language == "zh-CN" || state.language.starts(with: "zh") { return "中" }
                if state.language == "en-US" || state.language.starts(with: "en") { return "En" }
                return state.language
            }()
            let displayMessage: String = {
                let listeningText = String(localized: "speech.listening")
                let raw = state.message.trimmingCharacters(in: .whitespacesAndNewlines)
                if state.isListening && !state.isDictating && (raw.isEmpty || raw == listeningText) {
                    return String(localized: "speech.waiting_command")
                }
                return state.message
            }()
            
            HStack(spacing: 8) {
                // Mic Icon (Persistent per user request)
                if state.isListening {
                    Image(systemName: "mic.fill")
                        .foregroundColor(.green)
                        .font(.system(size: 14))
                        .scaleEffect(1.0 + (state.audioLevel * 1.5))
                        .shadow(radius: 1)
                        .opacity(0.6 + (state.audioLevel * 0.4))
                        .animation(.linear(duration: 0.1), value: state.audioLevel)
                }
                
                if state.isDictating {
                    WaveformView(level: state.audioLevel)
                } else {
                    if !displayMessage.isEmpty {
                        Text(displayMessage)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.white)
                            .shadow(color: .black.opacity(0.2), radius: 1, x: 0, y: 1)
                            .fixedSize()
                    }
                }
                
                // Keyboard/Command Icon (Persistent)
                if state.isDictating {
                    Image(systemName: "keyboard")
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.9))
                        .shadow(radius: 1)
                } else if state.isInteractive {
                     Image(systemName: "command")
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.7))
                        .shadow(radius: 1)
                }
                
                // Language Toggle (Persistent per user request)
                if state.isInteractive {
                    Divider()
                        .frame(height: 16)
                        .background(Color.white.opacity(0.3))
                    
                    Button(action: {
                        NotificationCenter.default.post(name: Notification.Name("AetherToggleLanguage"), object: nil)
                    }) {
                        Text(displayLanguage)
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.white)
                            .shadow(color: .black.opacity(0.2), radius: 1, x: 0, y: 1)
                            .fixedSize()
                            .frame(minWidth: 24, alignment: .center)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.white.opacity(0.2))
                            .cornerRadius(4)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
            )
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .shadow(color: Color.black.opacity(0.1), radius: 4, x: 0, y: 2)
        }
    }
    
    private struct VisualEffectView: NSViewRepresentable {
        let material: NSVisualEffectView.Material
        let blendingMode: NSVisualEffectView.BlendingMode
        
        func makeNSView(context: Context) -> NSVisualEffectView {
            let view = NSVisualEffectView()
            view.material = material
            view.blendingMode = blendingMode
            view.state = .active
            // [Clarity] Force Dark Mode to ensure white text is always legible
            view.appearance = NSAppearance(named: .vibrantDark)
            return view
        }
        
        func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
            nsView.material = material
            nsView.blendingMode = blendingMode
            // [Clarity] Ensure appearance stays dark
            if nsView.appearance?.name != .vibrantDark {
                nsView.appearance = NSAppearance(named: .vibrantDark)
            }
        }
    }
    
    private struct WaveformView: View {
        let level: CGFloat
        
        var body: some View {
            HStack(spacing: 3) {
                ForEach(0..<5) { i in
                    RoundedRectangle(cornerRadius: 1.5)
                    .fill(Color.green.opacity(0.8))
                    .frame(width: 3, height: barHeight(for: i))
                    .animation(.spring(response: 0.2, dampingFraction: 0.5), value: level)
                }
            }
            .frame(height: 20)
        }
        
        private func barHeight(for index: Int) -> CGFloat {
            // Create a pseudo-varied waveform based on level
            let baseHeights: [CGFloat] = [6, 10, 14, 10, 6]
            let variance = CGFloat.random(in: 0.8...1.2)
            return max(3, baseHeights[index] * level * 2 * variance)
        }
    }
}
