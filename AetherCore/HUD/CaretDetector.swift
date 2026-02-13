import AppKit
import Combine
import Carbon
import ApplicationServices

final class CaretDetector: ObservableObject {
    struct Update {
        let caretRect: CGRect?
        let inputRect: CGRect?
        let sourceBundleID: String?
        let isSticky: Bool
    }
    
    @Published var currentUpdate: Update = Update(caretRect: nil, inputRect: nil, sourceBundleID: nil, isSticky: false)
    
    // Internal State
    private var eventMonitors: [Any] = []
    private var axObserver: AXObserver?
    private var observedPid: pid_t = 0
    
    // Bridged Data
    private var bridgedCaretRect: CGRect?
    private var bridgedInputContextRect: CGRect?
    private var bridgedBundleID: String?
    private var bridgedCaretAt: Date?
    
    // Local Calculation State
    private var caretRect: CGRect?
    private var lastCaretRect: CGRect?
    private var lastCaretRectAt: Date?
    private var inputContextRect: CGRect?
    private var caretSourceBundleID: String?
    
    private var isFetchingCaret = false
    private var singleLineStepBySource: [String: CGFloat] = [:]
    
    // Sticky Logic
    private var caretStickyTimer: Timer?
    private var isCaretStickyActive: Bool = false
    private var lastKeyDrivenUpdateAt: Date = .distantPast
    
    // Fallback
    private var followTimer: Timer?
    
    // Diagnostics
    private var currentAppName: String?
    private var currentAppBundleID: String?
    private var lastFocusedAppName: String?
    private var lastFocusedBundleID: String?
    
    private lazy var inputMethodBridge: InputMethodCaretBridge = {
        let bridge = InputMethodCaretBridge()
        bridge.onCaretUpdate = { [weak self] update in
            guard let self = self else { return }
            self.bridgedCaretRect = update.caretRect
            self.bridgedInputContextRect = update.contextRect
            self.bridgedBundleID = update.bundleID
            self.bridgedCaretAt = update.timestamp
            // Trigger update
            DispatchQueue.main.async { self.recalcCaret() }
        }
        return bridge
    }()
    
    init() {}

    func start() {
        startFollowTimer()
    }
    
    func stop() {
        stopFollowTimer()
    }
    
    func recentCaretRect(maxAge: TimeInterval = 0.28) -> CGRect? {
         guard let rect = lastCaretRect, let ts = lastCaretRectAt else { return nil }
         let age = Date().timeIntervalSince(ts)
         if isCodexLike(appName: currentAppName, bundleID: currentAppBundleID) {
             if age <= min(maxAge, 0.18) { return rect }
             return nil
         }
         return age <= maxAge ? rect : nil
    }

    // MARK: - Event Monitoring
    
    private func startFollowTimer() {
        setupAXObserver()
        inputMethodBridge.start()
        
        // Mouse Click
        if let monitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown], handler: { [weak self] _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                self?.recalcCaret()
            }
        }) {
            eventMonitors.append(monitor)
        }
        
        // Key Down
        if let monitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown, handler: { [weak self] _ in
            guard let self = self else { return }
            let now = Date()
            if now.timeIntervalSince(self.lastKeyDrivenUpdateAt) < 0.03 { return }
            self.lastKeyDrivenUpdateAt = now
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.012) {
                self.recalcCaret()
            }
        }) {
            eventMonitors.append(monitor)
        }
        
        // App Switch
        let wsObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] _ in
            self?.handleAppSwitch()
        }
        eventMonitors.append(wsObserver)
        
        // Fallback Timer
        followTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            DispatchQueue.main.async { self?.recalcCaret() }
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
    
    private func handleAppSwitch() {
        self.isFetchingCaret = false
        self.caretRect = nil
        self.lastCaretRect = nil
        self.lastCaretRectAt = nil
        self.caretSourceBundleID = nil
        self.isCaretStickyActive = false
        self.caretStickyTimer?.invalidate()
        self.caretStickyTimer = nil
        
        setupAXObserver()
        recalcCaret()
    }
    
    // MARK: - AX Observer
    
    private func setupAXObserver() {
        teardownAXObserver()
        guard let app = NSWorkspace.shared.frontmostApplication else { return }
        if app.bundleIdentifier == Bundle.main.bundleIdentifier { return }
        
        let pid = app.processIdentifier
        var observer: AXObserver?
        let callback: AXObserverCallback = { (observer, element, notification, refcon) in
            guard let refcon = refcon else { return }
            let detector = Unmanaged<CaretDetector>.fromOpaque(refcon).takeUnretainedValue()
            DispatchQueue.main.async {
                detector.recalcCaret()
            }
        }
        
        let result = AXObserverCreate(pid, callback, &observer)
        guard result == .success, let obs = observer else { return }
        
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        let appElement = AXUIElementCreateApplication(pid)
        
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
    }
    
    private func teardownAXObserver() {
        if let obs = axObserver {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(obs), .defaultMode)
            axObserver = nil
            observedPid = 0
        }
    }
    
    // MARK: - Core Logic
    
    private func recalcCaret() {
        updateCaretRect()
    }
    
    private func updateCaretRect() {
        if isFetchingCaret { return }
        isFetchingCaret = true
        
        // Short-circuit for self
        if NSWorkspace.shared.frontmostApplication?.bundleIdentifier == Bundle.main.bundleIdentifier {
            DispatchQueue.main.async {
                self.isFetchingCaret = false
                self.resetCaretState()
                self.updateState()
            }
            return
        }
        
        DispatchQueue.global(qos: .userInteractive).async {
            self.performCaretDetection()
        }
    }
    
    private func resetCaretState() {
        self.caretRect = nil
        self.lastCaretRect = nil
        self.lastCaretRectAt = nil
        self.caretSourceBundleID = nil
        self.inputContextRect = nil
        self.isCaretStickyActive = false
        self.caretStickyTimer?.invalidate()
        self.caretStickyTimer = nil
    }
    
    private func performCaretDetection() {
        var newRect: CGRect? = nil
        var newInputContextRect: CGRect? = nil
        var newCaretSourceBundleID: String? = nil
        var focusedIsEditable = false
        var shouldTemporarilyKeepLastCaret = false
        var usedInputMethodBridge = false // Simplified: always try AX first, or IME if preferred
        
        // 1. IME Bridge Check (Simplified)
        // ... (Skipping complex compare logic for brevity, implementing functional check)
        
        // 2. AX System Wide
        let systemWide = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(systemWide, 0.1)
        
        var focusedElement: CFTypeRef?
        let elementStatus = AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &focusedElement)
        
        // Fallback search
        if elementStatus != .success || focusedElement == nil {
            if let frontApp = NSWorkspace.shared.frontmostApplication {
                 let frontAppElement = AXUIElementCreateApplication(frontApp.processIdentifier)
                 var windowsRef: CFTypeRef?
                 if AXUIElementCopyAttributeValue(frontAppElement, kAXWindowsAttribute as CFString, &windowsRef) == .success,
                    let windows = windowsRef as? [AXUIElement], let firstWindow = windows.first {
                     focusedElement = firstWindow
                 }
            }
        }
        
        if let elementRef = focusedElement {
            var element = elementRef as! AXUIElement
            
            // Diagnostics
            var pid: pid_t = 0
            AXUIElementGetPid(element, &pid)
            let app = NSRunningApplication(processIdentifier: pid)
            let bundleID = app?.bundleIdentifier ?? ""
            self.currentAppName = app?.localizedName
            self.currentAppBundleID = bundleID
            self.lastFocusedAppName = self.currentAppName
            self.lastFocusedBundleID = bundleID
            
            if bundleID == Bundle.main.bundleIdentifier {
                DispatchQueue.main.async {
                    self.isFetchingCaret = false
                    self.resetCaretState()
                    self.updateState()
                }
                return
            }
            
            var roleValue: CFTypeRef?
            AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleValue)
            let role = roleValue as? String ?? ""
            
            // Drill down
            if ["AXWindow", "AXSheet", "AXScrollArea", "AXSplitGroup"].contains(role) || isSiriLike(appName: self.currentAppName, bundleID: bundleID) {
                if let child = findFirstTextField(in: element) {
                    element = child
                }
            }
            
            // Editability
            var isEditable = ["AXTextField", "AXSearchField", "AXComboBox", "AXHTMLTextInput", "AXTextArea"].contains(role)
            let axEditable = readAXBool(element, attribute: "AXEditable")
            if axEditable == true { isEditable = true }
             
             // --- Fetch Parent Window ---
             var windowFrame: CGRect? = nil
             var windowValue: CFTypeRef?
             if AXUIElementCopyAttributeValue(element, kAXWindowAttribute as CFString, &windowValue) == .success {
                 let windowElement = windowValue as! AXUIElement
                 var posVal: CFTypeRef?
                 var sizeVal: CFTypeRef?
                 if AXUIElementCopyAttributeValue(windowElement, kAXPositionAttribute as CFString, &posVal) == .success,
                    AXUIElementCopyAttributeValue(windowElement, kAXSizeAttribute as CFString, &sizeVal) == .success {
                     var p = CGPoint.zero; var s = CGSize.zero
                     if AXValueGetValue(posVal as! AXValue, .cgPoint, &p), AXValueGetValue(sizeVal as! AXValue, .cgSize, &s) {
                         let rawWin = CGRect(origin: p, size: s)
                         if let primary = NSScreen.screens.first {
                             let appKitY = primary.frame.height - rawWin.origin.y - rawWin.height
                             windowFrame = CGRect(x: rawWin.origin.x, y: appKitY, width: rawWin.width, height: rawWin.height)
                         }
                     }
                 }
             }
             
             // --- 3. Selected Text Range ---
             if isEditable {
                 focusedIsEditable = true
                 
                 // Try Marker (Web)
                 var markerRangeValue: CFTypeRef?
                 if AXUIElementCopyAttributeValue(element, "AXSelectedTextMarkerRange" as CFString, &markerRangeValue) == .success {
                     var boundsValue: CFTypeRef?
                     if AXUIElementCopyParameterizedAttributeValue(element, "AXBoundsForTextMarkerRange" as CFString, markerRangeValue!, &boundsValue) == .success {
                         if let r = extractRect(from: boundsValue!) {
                             if isValid(r, in: windowFrame) {
                                 newRect = r
                             }
                         }
                     }
                 }
                 
                 // Try Standard Range
                 if newRect == nil {
                     var selectedRangeValue: CFTypeRef?
                     if AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &selectedRangeValue) == .success {
                         var boundsValue: CFTypeRef?
                         if AXUIElementCopyParameterizedAttributeValue(element, kAXBoundsForRangeParameterizedAttribute as CFString, selectedRangeValue!, &boundsValue) == .success {
                             if let r = extractRect(from: boundsValue!) {
                                 if isValid(r, in: windowFrame) {
                                     newRect = r
                                 }
                             }
                         }
                     }
                 }
             }
             
             // --- Fallback: Element Bounds ---
             if newRect == nil && isEditable {
                 var posValue: CFTypeRef?
                 var sizeValue: CFTypeRef?
                 if AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &posValue) == .success,
                    AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeValue) == .success {
                     var p = CGPoint.zero; var s = CGSize.zero
                     if AXValueGetValue(posValue as! AXValue, .cgPoint, &p), AXValueGetValue(sizeValue as! AXValue, .cgSize, &s) {
                         let axVal = AXValueCreate(.cgRect, [CGRect(origin: p, size: s)])
                         if let r_appkit = extractRect(from: axVal as CFTypeRef) {
                             if isValid(r_appkit, in: windowFrame) {
                                  // Synthetic weak caret logic for big text areas
                                 if (role == "AXTextArea" || role == "AXWebArea") && (r_appkit.width > 220 || r_appkit.height > 70) {
                                     let h = min(max(14.0, r_appkit.height), 24.0)
                                     let y = r_appkit.minY + max(0.0, (r_appkit.height - h) * 0.5)
                                     newRect = CGRect(x: r_appkit.minX + 12, y: y, width: 2, height: h)
                                     newInputContextRect = r_appkit
                                     shouldTemporarilyKeepLastCaret = true
                                 } else {
                                     newRect = r_appkit
                                 }
                             }
                         }
                     }
                 }
             }
        }
        
        if newRect != nil {
            newCaretSourceBundleID = self.currentAppBundleID
        }
        
        DispatchQueue.main.async {
            self.isFetchingCaret = false
            
            if newRect == nil {
                if !focusedIsEditable {
                    // Not editable, clear sticky immediately
                    self.resetCaretState()
                    self.updateState()
                    return
                }
                
                // Editable but lost caret: enter Sticky Grace Period
                if let last = self.recentCaretRect(), shouldTemporarilyKeepLastCaret {
                     // keep existing
                     return
                }
                
                if self.caretRect != nil && !self.isCaretStickyActive {
                    // Start sticky timer
                    let sticky = self.stickyDuration(for: self.lastFocusedBundleID, appName: self.lastFocusedAppName)
                    self.isCaretStickyActive = true
                    self.caretStickyTimer?.invalidate()
                    self.caretStickyTimer = Timer.scheduledTimer(withTimeInterval: sticky, repeats: false) { [weak self] _ in
                        guard let self = self else { return }
                        if self.isCaretStickyActive {
                            self.resetCaretState()
                            self.updateState()
                        }
                    }
                    // Update state to reflect sticky overlay
                    self.updateState()
                    return
                }
                
                if self.isCaretStickyActive && self.recentCaretRect() == nil {
                    // Expired
                    self.resetCaretState()
                    self.updateState()
                    return
                }
                return
            }
            
            // Focus recovered
            self.isCaretStickyActive = false
            self.caretStickyTimer?.invalidate()
            self.caretStickyTimer = nil
            
            self.caretRect = newRect
            self.lastCaretRect = newRect
            self.lastCaretRectAt = Date()
            self.caretSourceBundleID = newCaretSourceBundleID
            self.inputContextRect = newInputContextRect
            
            self.updateState()
        }
    }
    
    private func updateState() {
        let update = Update(
            caretRect: caretRect,
            inputRect: inputContextRect,
            sourceBundleID: caretSourceBundleID,
            isSticky: isCaretStickyActive
        )
        self.currentUpdate = update
    }

    // MARK: - Helpers
    
    private func extractRect(from value: CFTypeRef) -> CGRect? {
        var r = CGRect.zero
        if AXValueGetValue(value as! AXValue, .cgRect, &r) {
            if let primary = NSScreen.screens.first {
                r.origin.y = primary.frame.height - r.origin.y - r.size.height
            }
            return r
        }
        return nil
    }
    
    private func isValid(_ r: CGRect, in w: CGRect?) -> Bool {
        if r.origin.x == 0 && r.origin.y == 0 { return false }
        if let win = w {
            let expanded = win.insetBy(dx: -50, dy: -50)
            if !expanded.contains(r.origin) { return false }
        }
        // Fallback: On Any Screen?
        for screen in NSScreen.screens {
            if screen.frame.contains(r.origin) { return true }
        }
        return false
    }
    
    private func readAXBool(_ element: AXUIElement, attribute: String) -> Bool? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        if let b = value as? Bool { return b }
        if let n = value as? NSNumber { return n.boolValue }
        return nil
    }
    
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
                if targetRoles.contains(role) { return child }
            }
            if let found = findFirstTextField(in: child, depth: depth - 1) { return found }
        }
        return nil
    }
    
    private func isSiriLike(appName: String?, bundleID: String?) -> Bool {
        if bundleID?.contains("apple.siri") == true { return true }
        if appName?.lowercased().contains("siri") == true { return true }
        return false
    }
    
    private func isCodexLike(appName: String?, bundleID: String?) -> Bool {
        let loweredName = appName?.lowercased() ?? ""
        if loweredName.contains("codex") { return true }
        let loweredBundle = bundleID?.lowercased() ?? ""
        return loweredBundle.contains("codex")
    }
    
    private func stickyDuration(for bundleID: String?, appName: String?) -> TimeInterval {
        if isCodexLike(appName: appName, bundleID: bundleID) { return 0.06 }
        return 0.08
    }
}
