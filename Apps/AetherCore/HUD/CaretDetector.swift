import AppKit
import Combine
import Carbon
import ApplicationServices
import OSLog
import CoreText

final class CaretDetector: ObservableObject {
    struct Update {
        let caretRect: CGRect?
        let inputRect: CGRect?
        let sourceBundleID: String?
        let isSticky: Bool
        let caretSourceLabel: String?
    }

    private struct DetectionSnapshot {
        let currentAppName: String?
        let currentAppBundleID: String?
        let lastFocusedAppName: String?
        let lastFocusedBundleID: String?
        let bridgedCaretRect: CGRect?
        let bridgedInputContextRect: CGRect?
        let bridgedBundleID: String?
        let bridgedCaretAt: Date?
        let frontmostAppPID: pid_t?
        let frontmostAppBundleID: String?
    }

    private struct DetectionResult {
        let currentAppName: String?
        let currentAppBundleID: String?
        let lastFocusedAppName: String?
        let lastFocusedBundleID: String?
        let caretRect: CGRect?
        let inputContextRect: CGRect?
        let caretSourceBundleID: String?
        let caretSourceLabel: String?
        let focusedIsEditable: Bool
        let shouldTemporarilyKeepLastCaret: Bool
    }
    
    @Published var currentUpdate: Update = Update(caretRect: nil, inputRect: nil, sourceBundleID: nil, isSticky: false, caretSourceLabel: nil)
    
    // Internal State
    private var eventMonitors: [Any] = []
    private var axObserver: AXObserver?
    private var observedPid: pid_t = 0
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.7fei.Aether", category: "CaretDetector")
    
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
    private var caretSourceLabel: String?
    
    private var isFetchingCaret = false
    private var singleLineStepBySource: [String: CGFloat] = [:]
    
    // Sticky Logic
    private var caretStickyTimer: Timer?
    private var isCaretStickyActive: Bool = false
    private var lastKeyDrivenUpdateAt: Date = .distantPast
    
    // Fallback
    private var followTimer: Timer?
    private var lastFollowPollAt: Date = .distantPast
    private var imeBridgeEnabled: Bool {
        UserDefaults.standard.object(forKey: "hudImeBridgeEnabled") as? Bool ?? false
    }

    // Diagnostics
    private var currentAppName: String?
    private var currentAppBundleID: String?
    private var lastFocusedAppName: String?
    private var lastFocusedBundleID: String?

    private static let browserBundleIDs: Set<String> = [
        "com.apple.safari",
        "com.google.chrome",
        "com.google.Chrome.beta",
        "com.google.Chrome.canary",
        "com.google.chrome.beta",
        "com.google.chrome.canary",
        "com.brave.browser",
        "company.thebrowser.browser",
        "com.kagi.kagimacos",
        "com.microsoft.edgemac",
        "com.microsoft.edgemac.beta",
        "com.microsoft.edgemac.dev",
        "com.microsoft.edgemac.canary",
        "org.mozilla.firefox"
    ]
    
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

    func handleAccessibilityTrustChange(trusted: Bool) {
        DispatchQueue.main.async {
            self.isFetchingCaret = false
            self.teardownAXObserver()
            if trusted {
                self.setupAXObserver()
                self.recalcCaret()
            } else {
                self.resetCaretState()
                self.updateState()
            }
        }
    }

    func handleGlobalMouseClick(at point: CGPoint) {
        DispatchQueue.main.async {
            let activeInputRect = self.currentInputLikeRect()
            let insideInput = activeInputRect?.insetBy(dx: -8, dy: -8).contains(point) ?? false
            if insideInput {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.035) {
                    self.recalcCaret()
                }
                return
            }

            self.bridgedCaretRect = nil
            self.bridgedInputContextRect = nil
            self.bridgedBundleID = nil
            self.bridgedCaretAt = nil
            self.resetCaretState()
            self.updateState()

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.035) {
                self.recalcCaret()
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                self.recalcCaret()
            }
        }
    }
    
    func recentCaretRect(maxAge: TimeInterval = 0.28) -> CGRect? {
         guard let rect = lastCaretRect, let ts = lastCaretRectAt else { return nil }
         let age = Date().timeIntervalSince(ts)
         if isHighFrequencyApp(appName: currentAppName, bundleID: currentAppBundleID) {
             // Strict Codex Legacy Rule: Zero Tolerance.
             // Never return cached rect. Always require fresh detection.
             return nil
         }
         return age <= maxAge ? rect : nil
    }

    // MARK: - Event Monitoring
    
    private func startFollowTimer() {
        setupAXObserver()
        if imeBridgeEnabled {
            inputMethodBridge.start()
        }
        lastFollowPollAt = .distantPast
        
        // Mouse Click
        if let monitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown], handler: { [weak self] _ in
            let point = NSEvent.mouseLocation
            HUDManager.shared.handleGlobalMouseDown(at: point)
            self?.handleGlobalMouseClick(at: point)
        }) {
            eventMonitors.append(monitor)
        }

        // Mouse Move (for HUD avoidance responsiveness in input mode)
        if let monitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged],
            handler: { _ in
                HUDManager.shared.notifyPointerMoved()
            }
        ) {
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
        
        // Legacy behavior: high-frequency fallback for smoother focus/caret catch-up.
        followTimer = Timer.scheduledTimer(withTimeInterval: 0.016, repeats: true) { [weak self] _ in
            DispatchQueue.main.async {
                guard let self else { return }
                let now = Date()
                guard now.timeIntervalSince(self.lastFollowPollAt) >= self.passiveFollowInterval(for: now) else {
                    return
                }
                self.lastFollowPollAt = now
                self.recalcCaret()
            }
        }
    }
    
    private func stopFollowTimer() {
        followTimer?.invalidate()
        followTimer = nil
        lastFollowPollAt = .distantPast
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
        self.lastFollowPollAt = .distantPast
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

    private func passiveFollowInterval(for now: Date) -> TimeInterval {
        let bundleID = (currentAppBundleID ?? NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "").lowercased()
        let recentlyKeyDriven = now.timeIntervalSince(lastKeyDrivenUpdateAt) < 0.2
        let recentlyBridged = bridgedCaretAt.map { now.timeIntervalSince($0) < 0.18 } ?? false
        let hasLiveTypingSignal =
            currentUpdate.caretRect != nil ||
            currentUpdate.inputRect != nil ||
            currentUpdate.isSticky ||
            recentlyKeyDriven ||
            recentlyBridged

        if hasLiveTypingSignal {
            return 1.0 / 60.0
        }
        if Self.browserBundleIDs.contains(bundleID) {
            return 1.0 / 8.0
        }
        return 1.0 / 20.0
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
        var hydratedFocus: CFTypeRef?
        _ = AXUIElementCopyAttributeValue(appElement, kAXFocusedUIElementAttribute as CFString, &hydratedFocus)
        self.axObserver = obs
        self.observedPid = pid
        DispatchQueue.main.async { [weak self] in
            self?.recalcCaret()
        }
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
        let snapshot = makeDetectionSnapshot()
        
        // Short-circuit for self
        if snapshot.frontmostAppBundleID == Bundle.main.bundleIdentifier {
            DispatchQueue.main.async {
                self.isFetchingCaret = false
                self.resetCaretState()
                self.updateState()
            }
            return
        }
        
        DispatchQueue.global(qos: .userInteractive).async {
            let result = self.performCaretDetection(snapshot: snapshot)
            DispatchQueue.main.async {
                self.applyDetectionResult(result)
            }
        }
    }

    private func makeDetectionSnapshot() -> DetectionSnapshot {
        let frontmostApp = NSWorkspace.shared.frontmostApplication
        return DetectionSnapshot(
            currentAppName: currentAppName,
            currentAppBundleID: currentAppBundleID,
            lastFocusedAppName: lastFocusedAppName,
            lastFocusedBundleID: lastFocusedBundleID,
            bridgedCaretRect: bridgedCaretRect,
            bridgedInputContextRect: bridgedInputContextRect,
            bridgedBundleID: bridgedBundleID,
            bridgedCaretAt: bridgedCaretAt,
            frontmostAppPID: frontmostApp?.processIdentifier,
            frontmostAppBundleID: frontmostApp?.bundleIdentifier
        )
    }
    
    private func resetCaretState() {
        self.caretRect = nil
        self.lastCaretRect = nil
        self.lastCaretRectAt = nil
        self.caretSourceBundleID = nil
        self.inputContextRect = nil
        self.caretSourceLabel = nil
        self.isCaretStickyActive = false
        self.caretStickyTimer?.invalidate()
        self.caretStickyTimer = nil
    }

    private func currentInputLikeRect() -> CGRect? {
        if let r = currentUpdate.inputRect, isInputLikeBounds(r), !isLikelyWholeWindowBounds(r) {
            return r
        }
        if let r = currentUpdate.caretRect {
            return r.insetBy(dx: -18, dy: -12)
        }
        return nil
    }
    
    private func performCaretDetection(snapshot: DetectionSnapshot) -> DetectionResult {
        var newRect: CGRect? = nil
        var newInputContextRect: CGRect? = nil
        var newCaretSourceBundleID: String? = nil
        var focusedIsEditable = false
        var shouldTemporarilyKeepLastCaret = false
        var usedInputMethodBridge = false // Simplified: always try AX first, or IME if preferred
        var imeRect: CGRect? = nil
        var imeContextRect: CGRect? = nil
        var imeBundleID: String? = nil
        var imeSourceLabel: String? = nil
        var detectedCurrentAppName = snapshot.currentAppName
        var detectedCurrentAppBundleID = snapshot.currentAppBundleID
        var detectedLastFocusedAppName = snapshot.lastFocusedAppName
        var detectedLastFocusedBundleID = snapshot.lastFocusedBundleID

        // 1. IME Bridge Check (fresh bridge update wins when AX is flaky across app/focus switches).
        if imeBridgeEnabled,
           let bridgedAt = snapshot.bridgedCaretAt,
           Date().timeIntervalSince(bridgedAt) <= 0.45,
           let rawBridgeCaret = snapshot.bridgedCaretRect,
           let bridgeCaret = normalizeBridgeRect(rawBridgeCaret) {
            let frontBundle = snapshot.frontmostAppBundleID
            let bundleMatches = (snapshot.bridgedBundleID == nil) || (frontBundle == nil) || (snapshot.bridgedBundleID == frontBundle)
            if bundleMatches {
                imeRect = normalizeCaretRect(bridgeCaret)
                if let rawContext = snapshot.bridgedInputContextRect {
                    imeContextRect = normalizeBridgeRect(rawContext) ?? rawContext
                }
                imeBundleID = snapshot.bridgedBundleID ?? frontBundle
                imeSourceLabel = "IME"
                focusedIsEditable = true
                usedInputMethodBridge = true
            }
        }
        
        // 2. AX System Wide
        let systemWide = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(systemWide, 0.1)
        
        var focusedElement: CFTypeRef?
        let elementStatus = AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &focusedElement)
        
        // Fallback search
        if elementStatus != .success || focusedElement == nil {
            if let frontmostPID = snapshot.frontmostAppPID {
                 let frontAppElement = AXUIElementCreateApplication(frontmostPID)
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
            let appName = app?.localizedName
            detectedCurrentAppName = appName
            detectedCurrentAppBundleID = bundleID
            detectedLastFocusedAppName = appName
            detectedLastFocusedBundleID = bundleID
            
            if bundleID == Bundle.main.bundleIdentifier {
                return DetectionResult(
                    currentAppName: detectedCurrentAppName,
                    currentAppBundleID: detectedCurrentAppBundleID,
                    lastFocusedAppName: detectedLastFocusedAppName,
                    lastFocusedBundleID: detectedLastFocusedBundleID,
                    caretRect: nil,
                    inputContextRect: nil,
                    caretSourceBundleID: nil,
                    caretSourceLabel: nil,
                    focusedIsEditable: false,
                    shouldTemporarilyKeepLastCaret: false
                )
            }
            
            var roleValue: CFTypeRef?
            AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleValue)
            var role = roleValue as? String ?? ""
            
            // [Silence] Debug log was spamming console
            // logger.error("HUD_DEBUG: Focused App='\(self.currentAppName ?? "unknown")', Bundle='\(bundleID)', Role='\(role)'")
            
            // Drill down
            if ["AXWindow", "AXSheet", "AXScrollArea", "AXSplitGroup"].contains(role) || isSiriLike(appName: appName, bundleID: bundleID) {
                if let child = findFirstTextField(in: element) {
                    element = child
                    // [Legacy Fix] Re-fetch role for the new element so isEditable checks work
                    var newRoleVal: CFTypeRef?
                    if AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &newRoleVal) == .success {
                        role = newRoleVal as? String ?? ""
                    }
                }
            }
            
            let collapsedInsertionContext = hasCollapsedInsertionContext(element)
            var isEditable = ["AXTextField", "AXSearchField", "AXComboBox", "AXHTMLTextInput", "AXTextArea"].contains(role)
            let axEditable = readAXBool(element, attribute: "AXEditable")
            let hasSettableValue = valueAttributeIsSettable(element)
            let hasEditableAncestor = editableAncestor(for: element) != nil
            let hasStrongContainerInsertionEvidence: Bool = {
                guard collapsedInsertionContext else { return false }
                if self.extractRectFromElement(element) != nil { return true }
                guard let bounds = self.elementBoundsRect(element) else { return false }
                return self.isInputLikeBounds(bounds) && !self.isLikelyWholeWindowBounds(bounds)
            }()
            if role == "AXWebArea" || role == "AXGroup" || role == "AXScrollArea" || role == "AXSplitGroup" {
                // Browser/web containers are frequently focused even when not typing.
                // Only keep them editable when AX gives stronger evidence than a stale collapsed range.
                isEditable = (axEditable == true) || hasSettableValue || hasEditableAncestor || hasStrongContainerInsertionEvidence
            } else if axEditable == true || hasSettableValue || hasEditableAncestor {
                isEditable = true
            }
             
             // --- Fetch Parent Window ---
             var windowFrame: CGRect? = nil
             var windowValue: CFTypeRef?
             if AXUIElementCopyAttributeValue(element, kAXWindowAttribute as CFString, &windowValue) == .success {
                 let windowElement = windowValue as! AXUIElement
                 var posVal: CFTypeRef?
                 var sizeVal: CFTypeRef?
                 if AXUIElementCopyAttributeValue(windowElement, kAXPositionAttribute as CFString, &posVal) == .success,
                    AXUIElementCopyAttributeValue(windowElement, kAXSizeAttribute as CFString, &sizeVal) == .success {
                     let posV = posVal as! AXValue; let sizeV = sizeVal as! AXValue
                     var p = CGPoint.zero; var s = CGSize.zero
                     if AXValueGetValue(posV, .cgPoint, &p), AXValueGetValue(sizeV, .cgSize, &s) {
                         let rawWin = CGRect(origin: p, size: s)
                         windowFrame = appKitRectFromAX(rawWin)
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
                          // [Legacy Restore] Pre-Extract Validation
                          var rawR = CGRect.zero
                          let bVal = boundsValue as! AXValue
                          if AXValueGetValue(bVal, .cgRect, &rawR) {
                              if (rawR.origin.x == 0 && rawR.origin.y == 0) || (rawR.width <= 1 && rawR.height <= 1) {
                                  // Bogus
                              } else if rawR.width > 80 || rawR.height > 80 {
                                  // Selection/Bound (Not a caret) -> try to refine via CFRange if available.
                                  var selectedRangeValue: CFTypeRef?
                                  if AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &selectedRangeValue) == .success,
                                     let selectedRangeValue,
                                     let range = selectedTextRange(from: selectedRangeValue),
                                     let refined = refineCaretRect(element, selectedRange: range) {
                                      newRect = refined
                                  }
                              } else {
                                  if let r = extractRect(from: boundsValue!) {
                                      if isValid(r, in: windowFrame) {
                                          let candidate = normalizeCaretRect(r)
                                          if isLikelyCaretRect(candidate) {
                                              newRect = candidate
                                          }
                                      }
                                  }
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
                             
                             // [Legacy Restore] Strict Validation for Standard Range
                             var rawR = CGRect.zero
                             let bVal = boundsValue as! AXValue
                             if AXValueGetValue(bVal, .cgRect, &rawR) {
                                  // 1. Bogus Check (0,0) or Tiny
                                  if (rawR.origin.x == 0 && rawR.origin.y == 0) || (rawR.width <= 1 && rawR.height <= 1) {
                                      self.logger.debug("[PRE-FLIP REJECT] Bogus standard range: \(rawR.debugDescription)")
                                  } 
                                  // 2. Non-Caret Geometry (Selection)
                                  // Codex often returns the whole line/block as selection range
                                  else if rawR.width > 80 || rawR.height > 80 {
                                      self.logger.debug("[NON-CARET] Large selection range: \(rawR.debugDescription)")
                                      if let range = selectedTextRange(from: selectedRangeValue!) {
                                          if let refined = refineCaretRect(element, selectedRange: range) {
                                              newRect = refined
                                          }
                                      }
                                  } else {
                                      if let r = extractRect(from: boundsValue!) {
                                          if isValid(r, in: windowFrame) {
                                              let candidate = normalizeCaretRect(r)
                                              if isLikelyCaretRect(candidate) {
                                                  newRect = candidate
                                              } else if let range = selectedTextRange(from: selectedRangeValue!) {
                                                  if let refined = refineCaretRect(element, selectedRange: range) {
                                                      newRect = refined
                                                  }
                                              }
                                          }
                                      }
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
                     let posV = posValue as! AXValue; let sizeV = sizeValue as! AXValue
                     var p = CGPoint.zero; var s = CGSize.zero
                     if AXValueGetValue(posV, .cgPoint, &p), AXValueGetValue(sizeV, .cgSize, &s) {
                         let axVal = AXValueCreate(.cgRect, [CGRect(origin: p, size: s)])
                         if let r_appkit = extractRect(from: axVal as CFTypeRef) {
                             if isValid(r_appkit, in: windowFrame) {
                                  // [Logic Refactor] Prioritize Synthetic > Huge Rejection
                                  // 1. Synthetic Candidates (WebArea, TextArea users)
                                  if (role == "AXTextArea" || role == "AXWebArea") && (r_appkit.width > 220 || r_appkit.height > 70) {
                                      // [Legacy Restore] Codex/HighFreq Rule: Never use synthetic caret for code editors.
                                      // For web containers, only synthesize when AX explicitly reports editable.
                                      if (axEditable == true) && !self.isHighFrequencyApp(appName: detectedCurrentAppName, bundleID: detectedCurrentAppBundleID) {
                                          self.logger.debug("⚠️ [WEAK CARET] Large bounds -> Synthetic Caret")
                                          let h = min(max(14.0, r_appkit.height), 24.0)
                                          let y = r_appkit.minY + max(0.0, (r_appkit.height - h) * 0.5)
                                          newRect = CGRect(x: r_appkit.minX + 12, y: y, width: 2, height: h)
                                          newInputContextRect = r_appkit
                                          shouldTemporarilyKeepLastCaret = true
                                      } else {
                                          self.logger.debug("[WEB] Rejection: Preventing synthetic caret without editable evidence.")
                                      }
                                  } else {
                                      // 2. Standard Candidates
                                      // [Legacy Restore] HEURISTIC: "Huge Element Rejection"
                                      var isHuge = false
                                      if let screen = NSScreen.main {
                                          let sFrame = screen.frame
                                          if r_appkit.width > sFrame.width * 0.7 && r_appkit.height > sFrame.height * 0.7 {
                                              isHuge = true
                                          }
                                      }
                                      
                                      if !isHuge {
                                          let singleLineRoles: Set<String> = ["AXTextField", "AXSearchField", "AXComboBox", "AXHTMLTextInput"]
                                          if singleLineRoles.contains(role) {
                                               // [Legacy Restore] Dynamic Single-Line Caret
                                               // Estimate X position based on character count to mimic "moving with words"
                                               let h = min(max(14.0, r_appkit.height - 6.0), 24.0)
                                               let y = r_appkit.minY + max(0.0, (r_appkit.height - h) * 0.5)
                                               let leadingInset = min(max(10.0, r_appkit.height * 0.5), 22.0)
                                               let trailingInset: CGFloat = 10.0
                                               let usableWidth = max(8.0, r_appkit.width - leadingInset - trailingInset)
                                               var caretXOffset: CGFloat = 0.0
                                               
                                               // Attempt to read value & range

                                               
                                               // We need to re-fetch value/range if we didn't get them earlier
                                               // But wait, we might have `selectedTextRange` if we add it to class state or re-fetch
                                               // For now, let's re-fetch quickly since this is fallback
                                               var valueRef: CFTypeRef?
                                               var selectedRangeValue: CFTypeRef?
                                                if AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &valueRef) == .success,
                                                   let valueStr = valueRef as? String,
                                                   AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &selectedRangeValue) == .success {
                                                    
                                                     var range = CFRange()
                                                     let selV = selectedRangeValue as! AXValue
                                                     if AXValueGetValue(selV, .cfRange, &range) {
                                                         let total = max(0, valueStr.count)
                                                         let location = max(0, min(range.location + range.length, total))
                                                         if total > 0 {
                                                             // Fixed-step model works better for short strings; clamp for long strings.
                                                             let step = min(max(9.0, r_appkit.height * 0.52), 13.0)
                                                             let unitsSoFar = self.weightedAdvanceUnits(valueStr, upToCharacters: location)
                                                             let totalUnits = max(0.1, self.weightedTotalUnits(valueStr))
                                                             let totalPx = totalUnits * step
                                                             if totalPx <= usableWidth {
                                                                 caretXOffset = min(unitsSoFar * step, usableWidth)
                                                             } else {
                                                                 caretXOffset = min(unitsSoFar * step, usableWidth)
                                                             }
                                                         }
                                                     }
                                                }
                                               
                                               let x = r_appkit.minX + leadingInset + caretXOffset
                                               newRect = CGRect(x: x, y: y, width: 2.0, height: h)
                                               newInputContextRect = r_appkit
                                               shouldTemporarilyKeepLastCaret = true
                                               self.logger.debug("✅ [FALLBACK] Dynamic Single-Line Caret: offset \(Int(caretXOffset)) (approx)")
                                          } else {
                                              newRect = r_appkit
                                              if role == "AXTextArea" || role == "AXWebArea" {
                                                  newInputContextRect = r_appkit
                                              }
                                          }
                                      } else {
                                          self.logger.debug("❌ [HUGE] Rejecting standard huge element: \(r_appkit.debugDescription)")
                                      }
                                  }
                             }
                         }
                     }
                 }
             }
        }
        
        // [Final Sanity Check] Codex/HighFreq
        if let r = newRect, self.isHighFrequencyApp(appName: detectedCurrentAppName, bundleID: detectedCurrentAppBundleID) {
             if r.width > 100 || r.height > 100 {
                 self.logger.debug("[CODEX] Final Sanity: Rejecting huge caret \(r.debugDescription, privacy: .public)")
                 newRect = nil
             } else {
                 self.logger.debug("✅ [CODEX] Final Sanity: Accepted caret \(r.debugDescription, privacy: .public)")
             }
        }
        
        if newRect != nil {
            newCaretSourceBundleID = detectedCurrentAppBundleID
        }

        // Prefer AX caret when present; fall back to IME only when AX is unavailable/unlikely.
        let axLikely = newRect.map { self.isLikelyCaretRect(self.normalizeCaretRect($0)) } ?? false
        let imeLikely = imeRect.map { self.isLikelyCaretRect(self.normalizeCaretRect($0)) } ?? false
        if axLikely {
            newRect = newRect.map { self.normalizeCaretRect($0) }
        } else if imeLikely {
            newRect = imeRect
            newInputContextRect = imeContextRect ?? newInputContextRect
            newCaretSourceBundleID = imeBundleID ?? newCaretSourceBundleID
        } else if newRect == nil, let fallbackIme = imeRect {
            newRect = fallbackIme
            newInputContextRect = imeContextRect ?? newInputContextRect
            newCaretSourceBundleID = imeBundleID ?? newCaretSourceBundleID
        }
        let newSourceLabel: String? = {
            if newRect == nil { return nil }
            if axLikely || (!imeLikely && newCaretSourceBundleID == detectedCurrentAppBundleID) { return "AX" }
            if imeRect != nil { return imeSourceLabel ?? "IME" }
            return "AX"
        }()

        return DetectionResult(
            currentAppName: detectedCurrentAppName,
            currentAppBundleID: detectedCurrentAppBundleID,
            lastFocusedAppName: detectedLastFocusedAppName,
            lastFocusedBundleID: detectedLastFocusedBundleID,
            caretRect: newRect,
            inputContextRect: newInputContextRect,
            caretSourceBundleID: newCaretSourceBundleID,
            caretSourceLabel: newSourceLabel,
            focusedIsEditable: focusedIsEditable,
            shouldTemporarilyKeepLastCaret: shouldTemporarilyKeepLastCaret
        )
    }
    
    private func applyDetectionResult(_ result: DetectionResult) {
        isFetchingCaret = false
        currentAppName = result.currentAppName
        currentAppBundleID = result.currentAppBundleID
        lastFocusedAppName = result.lastFocusedAppName
        lastFocusedBundleID = result.lastFocusedBundleID

        if result.caretRect == nil {
            if !result.focusedIsEditable {
                // Not editable, clear sticky immediately
                resetCaretState()
                updateState()
                return
            }

            // Editable but lost caret: enter Sticky Grace Period
            if isHighFrequencyApp(appName: lastFocusedAppName, bundleID: lastFocusedBundleID) {
                resetCaretState()
                updateState()
                return
            }

            if recentCaretRect() != nil, result.shouldTemporarilyKeepLastCaret {
                // keep existing
                return
            }

            if caretRect != nil && !isCaretStickyActive {
                let sticky = stickyDuration(for: lastFocusedBundleID, appName: lastFocusedAppName)
                isCaretStickyActive = true
                caretStickyTimer?.invalidate()
                caretStickyTimer = Timer.scheduledTimer(withTimeInterval: sticky, repeats: false) { [weak self] _ in
                    guard let self = self else { return }
                    if self.isCaretStickyActive {
                        self.resetCaretState()
                        self.updateState()
                    }
                }
                // Update state to reflect sticky overlay
                updateState()
                return
            }

            if isCaretStickyActive && recentCaretRect() == nil {
                resetCaretState()
                updateState()
                return
            }
            return
        }

        // Focus recovered
        isCaretStickyActive = false
        caretStickyTimer?.invalidate()
        caretStickyTimer = nil

        caretRect = result.caretRect
        lastCaretRect = result.caretRect
        lastCaretRectAt = Date()
        caretSourceBundleID = result.caretSourceBundleID
        inputContextRect = result.inputContextRect
        caretSourceLabel = result.caretSourceLabel

        updateState()
    }

    private func updateState() {
        let focusBundleID = caretSourceBundleID ?? lastFocusedBundleID ?? currentAppBundleID
        let update = Update(
            caretRect: caretRect,
            inputRect: inputContextRect,
            sourceBundleID: focusBundleID,
            isSticky: isCaretStickyActive,
            caretSourceLabel: caretSourceLabel
        )
        self.currentUpdate = update
    }

    // MARK: - Helpers
    
    private func extractRect(from value: CFTypeRef) -> CGRect? {
        var r = CGRect.zero
        let axVal = value as! AXValue
        if AXValueGetValue(axVal, .cgRect, &r) {
            return appKitRectFromAX(r)
        }
        return nil
    }

    private func normalizeBridgeRect(_ rect: CGRect) -> CGRect? {
        guard rect.width > 0, rect.height > 0 else { return nil }
        if isRectOnAnyScreen(rect) { return rect }

        let desktopMaxY = NSScreen.screens.map(\.frame.maxY).max() ?? 0
        guard desktopMaxY > 0 else { return nil }
        let flipped = CGRect(
            x: rect.origin.x,
            y: desktopMaxY - rect.origin.y - rect.size.height,
            width: rect.size.width,
            height: rect.size.height
        )
        return isRectOnAnyScreen(flipped) ? flipped : nil
    }

    private func isRectOnAnyScreen(_ rect: CGRect) -> Bool {
        for screen in NSScreen.screens {
            if screen.frame.intersects(rect) || screen.visibleFrame.intersects(rect) {
                return true
            }
        }
        return false
    }

    private func appKitRectFromAX(_ axRect: CGRect) -> CGRect? {
        let desktopMaxY = NSScreen.screens.map(\.frame.maxY).max() ?? 0
        guard desktopMaxY > 0 else { return nil }
        return CGRect(
            x: axRect.origin.x,
            y: desktopMaxY - axRect.origin.y - axRect.size.height,
            width: axRect.size.width,
            height: axRect.size.height
        )
    }
    
    private func isValid(_ r: CGRect, in w: CGRect?) -> Bool {
        if r.origin.x == 0 && r.origin.y == 0 { return false }
        if r.width < 0 || r.height <= 0 { return false } // Allow zero-width carets; reject negative/empty.

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

    private func extractRectFromElement(_ element: AXUIElement) -> CGRect? {
        // Try Marker (Web)
        var markerRangeValue: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, "AXSelectedTextMarkerRange" as CFString, &markerRangeValue) == .success {
            var boundsValue: CFTypeRef?
            if AXUIElementCopyParameterizedAttributeValue(element, "AXBoundsForTextMarkerRange" as CFString, markerRangeValue!, &boundsValue) == .success {
                return extractRect(from: boundsValue!)
            }
        }
        
        // Try Standard Range
        var selectedRangeValue: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &selectedRangeValue) == .success {
            var boundsValue: CFTypeRef?
            if AXUIElementCopyParameterizedAttributeValue(element, kAXBoundsForRangeParameterizedAttribute as CFString, selectedRangeValue!, &boundsValue) == .success {
                return extractRect(from: boundsValue!)
            }
        }
        return nil
    }

    private func selectedTextRange(from value: CFTypeRef) -> CFRange? {
        guard CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        let ax = value as! AXValue
        guard AXValueGetType(ax) == .cfRange else { return nil }
        var range = CFRange()
        guard AXValueGetValue(ax, .cfRange, &range) else { return nil }
        if range.location < 0 { return nil }
        return range
    }

    private func visibleCharacterRange(_ element: AXUIElement) -> CFRange? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, "AXVisibleCharacterRange" as CFString, &value) == .success,
              let value else {
            return nil
        }
        return selectedTextRange(from: value)
    }

    private func intersectRange(_ a: CFRange, _ b: CFRange) -> CFRange? {
        let aEnd = a.location + a.length
        let bEnd = b.location + b.length
        let start = max(a.location, b.location)
        let end = min(aEnd, bEnd)
        if end <= start { return nil }
        return CFRange(location: start, length: end - start)
    }

    private func boundsForRange(_ element: AXUIElement, range: CFRange) -> CGRect? {
        var r = range
        guard let rangeValue = AXValueCreate(.cfRange, &r) else { return nil }
        var boundsRef: CFTypeRef?
        let err = AXUIElementCopyParameterizedAttributeValue(
            element,
            kAXBoundsForRangeParameterizedAttribute as CFString,
            rangeValue,
            &boundsRef
        )
        guard err == .success, let boundsRef else { return nil }
        return extractRect(from: boundsRef)
    }

    private func caretRectFromLineInfo(_ element: AXUIElement, caretIndex: Int) -> CGRect? {
        let indexNumber = NSNumber(value: caretIndex)
        var lineRef: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(element, "AXLineForIndex" as CFString, indexNumber, &lineRef) == .success,
              let lineNumber = lineRef as? NSNumber else {
            return nil
        }

        var rangeRef: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(element, "AXRangeForLine" as CFString, lineNumber, &rangeRef) == .success,
              let rangeRef,
              let lineRange = selectedTextRange(from: rangeRef) else {
            return nil
        }

        guard let lineRect = boundsForRange(element, range: lineRange) else { return nil }

        let elementBounds = elementBoundsRect(element)
        let visibleRange = visibleCharacterRange(element)
        let effectiveRange = visibleRange.flatMap { intersectRange(lineRange, $0) } ?? lineRange

        var baseRect = lineRect
        if let effectiveRect = boundsForRange(element, range: effectiveRange) {
            baseRect = effectiveRect
        } else if let elementBounds {
            baseRect = CGRect(x: elementBounds.minX, y: lineRect.minY, width: elementBounds.width, height: lineRect.height)
        }

        let firstCharRect: CGRect? = {
            guard effectiveRange.length > 0 else { return nil }
            let r = CFRange(location: effectiveRange.location, length: 1)
            return boundsForRange(element, range: r)
        }()
        let lastCharRect: CGRect? = {
            guard effectiveRange.length > 0 else { return nil }
            let lastIndex = effectiveRange.location + max(0, effectiveRange.length - 1)
            let r = CFRange(location: lastIndex, length: 1)
            return boundsForRange(element, range: r)
        }()

        if let first = firstCharRect, isLikelyCharRect(first) {
            if let last = lastCharRect, isLikelyCharRect(last) {
                baseRect = CGRect(
                    x: first.minX,
                    y: first.minY,
                    width: max(2, last.maxX - first.minX),
                    height: first.height
                )
            } else {
                baseRect = CGRect(
                    x: first.minX,
                    y: first.minY,
                    width: max(2, baseRect.maxX - first.minX),
                    height: first.height
                )
            }
        }

        let visibleStart = effectiveRange.location
        let visibleEnd = effectiveRange.location + effectiveRange.length
        if caretIndex <= visibleStart {
            return CGRect(x: baseRect.minX - 1, y: baseRect.minY, width: 2, height: baseRect.height)
        }
        if caretIndex >= visibleEnd {
            return CGRect(x: baseRect.maxX - 1, y: baseRect.minY, width: 2, height: baseRect.height)
        }

        let offset = max(0, caretIndex - visibleStart)
        var prefixAttr: NSAttributedString?
        if offset > 0 {
            let prefixRange = CFRange(location: visibleStart, length: offset)
            prefixAttr = attributedStringForRange(element, range: prefixRange)
            if prefixAttr == nil {
                if let lineAttr = attributedStringForRange(element, range: lineRange) {
                    let startInLine = max(0, min(visibleStart - lineRange.location, lineAttr.length))
                    let len = max(0, min(offset, lineAttr.length - startInLine))
                    if len > 0 {
                        prefixAttr = lineAttr.attributedSubstring(from: NSRange(location: startInLine, length: len))
                    }
                }
            }
        }

        let width: CGFloat
        if let prefixAttr {
            let ctLine = CTLineCreateWithAttributedString(prefixAttr)
            var ascent: CGFloat = 0
            var descent: CGFloat = 0
            var leading: CGFloat = 0
            width = CGFloat(CTLineGetTypographicBounds(ctLine, &ascent, &descent, &leading))
        } else {
            width = 0
        }

        let x = min(max(baseRect.minX + width, baseRect.minX), baseRect.maxX)
        return CGRect(x: x - 1, y: baseRect.minY, width: 2, height: baseRect.height)
    }

    private func attributedStringForRange(_ element: AXUIElement, range: CFRange) -> NSAttributedString? {
        var r = range
        guard let rangeValue = AXValueCreate(.cfRange, &r) else { return nil }
        var attrRef: CFTypeRef?
        let err = AXUIElementCopyParameterizedAttributeValue(
            element,
            "AXAttributedStringForRange" as CFString,
            rangeValue,
            &attrRef
        )
        guard err == .success, let attrRef else { return nil }
        return attrRef as? NSAttributedString
    }

    private func isLikelyCharRect(_ rect: CGRect) -> Bool {
        if rect.width <= 0 || rect.height <= 0 { return false }
        if rect.width > 80 || rect.height > 80 { return false }
        return true
    }

    private func refineCaretRect(_ element: AXUIElement, selectedRange: CFRange) -> CGRect? {
        let caretIndex = max(0, selectedRange.location + selectedRange.length)
        let caretRange = CFRange(location: caretIndex, length: 0)
        if let caretRect = boundsForRange(element, range: caretRange) {
            let normalized = normalizeCaretRect(caretRect)
            if isLikelyCaretRect(normalized) {
                return normalized
            }
            if caretRect.width > max(80, caretRect.height * 6),
               let lineCaret = caretRectFromLineInfo(element, caretIndex: caretIndex) {
                return lineCaret
            }
        }

        let candidates: [(CFRange, Bool)] = [
            (CFRange(location: max(0, caretIndex - 1), length: 1), true),
            (CFRange(location: caretIndex, length: 1), false)
        ]

        for (range, useMaxX) in candidates {
            if range.location < 0 || range.length <= 0 { continue }
            if let charRect = boundsForRange(element, range: range) {
                if charRect.height <= 0 { continue }
                if charRect.width > max(80, charRect.height * 6),
                   let lineCaret = caretRectFromLineInfo(element, caretIndex: caretIndex) {
                    return lineCaret
                }
                let x = useMaxX ? charRect.maxX : charRect.minX
                let caret = CGRect(x: x - 1, y: charRect.minY, width: 2, height: charRect.height)
                if isValid(caret, in: nil) {
                    return caret
                }
            }
        }
        return nil
    }

    private func normalizeCaretRect(_ rect: CGRect) -> CGRect {
        if rect.width <= 0 {
            return CGRect(x: rect.minX, y: rect.minY, width: 2, height: rect.height)
        }
        return rect
    }

    private func isLikelyCaretRect(_ rect: CGRect) -> Bool {
        guard rect.height > 0 else { return false }
        let maxWidth = max(6.0, min(12.0, rect.height * 0.6))
        return rect.width <= maxWidth && rect.height <= 60
    }

    private func elementBoundsRect(_ element: AXUIElement) -> CGRect? {
        var posValue: CFTypeRef?
        var sizeValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &posValue) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeValue) == .success,
              let posValue,
              let sizeValue else {
            return nil
        }

        let posV = posValue as! AXValue
        let sizeV = sizeValue as! AXValue
        var p = CGPoint.zero
        var s = CGSize.zero
        guard AXValueGetValue(posV, .cgPoint, &p),
              AXValueGetValue(sizeV, .cgSize, &s) else {
            return nil
        }
        let axRect = CGRect(origin: p, size: s)
        return appKitRectFromAX(axRect)
    }

    private func isInputLikeBounds(_ rect: CGRect) -> Bool {
        guard rect.width > 0, rect.height > 0 else { return false }
        guard rect.height >= 18, rect.height <= 220 else { return false }
        return rect.width >= 56
    }

    private func isLikelyWholeWindowBounds(_ rect: CGRect) -> Bool {
        guard rect.width > 0, rect.height > 0 else { return true }
        let screen = NSScreen.screens.first(where: { $0.frame.intersects(rect) }) ??
            NSScreen.screens.first(where: { $0.visibleFrame.intersects(rect) }) ??
            NSScreen.main ??
            NSScreen.screens.first
        let visible = screen?.visibleFrame ?? .zero
        guard visible.width > 0, visible.height > 0 else { return false }

        let area = rect.width * rect.height
        let screenArea = visible.width * visible.height
        if screenArea > 0, area > screenArea * 0.22 { return true }
        if rect.height > 280 { return true }
        if rect.width > visible.width * 0.92, rect.height > 60 { return true }
        return rect.width > visible.width * 0.65 && rect.height > visible.height * 0.45
    }
    
    private func readAXBool(_ element: AXUIElement, attribute: String) -> Bool? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        if let b = value as? Bool { return b }
        if let n = value as? NSNumber { return n.boolValue }
        return nil
    }

    private func valueAttributeIsSettable(_ element: AXUIElement) -> Bool {
        var settable = DarwinBoolean(false)
        let result = AXUIElementIsAttributeSettable(element, kAXValueAttribute as CFString, &settable)
        return result == .success && settable.boolValue
    }

    private func editableAncestor(for element: AXUIElement, depth: Int = 6) -> AXUIElement? {
        for attribute in ["AXEditableAncestor", "AXHighestEditableAncestor"] {
            var value: CFTypeRef?
            if AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
               let value,
               CFGetTypeID(value) == AXUIElementGetTypeID() {
                return (value as! AXUIElement)
            }
        }

        var current = element
        for _ in 0..<depth {
            var parentValue: CFTypeRef?
            guard AXUIElementCopyAttributeValue(current, kAXParentAttribute as CFString, &parentValue) == .success,
                  let parentValue,
                  CFGetTypeID(parentValue) == AXUIElementGetTypeID() else {
                break
            }
            let parent = parentValue as! AXUIElement
            var roleValue: CFTypeRef?
            let role = (AXUIElementCopyAttributeValue(parent, kAXRoleAttribute as CFString, &roleValue) == .success)
                ? (roleValue as? String ?? "")
                : ""
            if readAXBool(parent, attribute: "AXEditable") == true ||
                valueAttributeIsSettable(parent) ||
                hasCollapsedInsertionContext(parent) ||
                ["AXTextField", "AXSearchField", "AXComboBox", "AXHTMLTextInput", "AXTextArea"].contains(role) {
                return parent
            }
            current = parent
        }
        return nil
    }

    private func hasCollapsedInsertionContext(_ element: AXUIElement) -> Bool {
        var selectedRangeValue: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &selectedRangeValue) == .success,
           let selectedRangeValue,
           CFGetTypeID(selectedRangeValue) == AXValueGetTypeID() {
            let ax = selectedRangeValue as! AXValue
            if AXValueGetType(ax) == .cfRange {
                var range = CFRange()
                if AXValueGetValue(ax, .cfRange, &range) {
                    if range.length == 0 { return true }
                } else {
                    return true
                }
            } else {
                return true
            }
        }

        var markerRangeValue: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, "AXSelectedTextMarkerRange" as CFString, &markerRangeValue) == .success {
            return true
        }

        return false
    }

    // For single-line web/native fields (address/search bars), AX often exposes bounds for the control
    // but not the caret. Use a crude proportional model that treats CJK/emoji as wider than ASCII.
    private func weightedAdvanceUnits(_ s: String, upToCharacters n: Int) -> CGFloat {
        if n <= 0 { return 0 }
        var units: CGFloat = 0
        var i = 0
        for ch in s {
            if i >= n { break }
            units += characterAdvanceUnit(ch)
            i += 1
        }
        return units
    }

    private func weightedTotalUnits(_ s: String) -> CGFloat {
        var units: CGFloat = 0
        for ch in s {
            units += characterAdvanceUnit(ch)
        }
        return units
    }

    private func characterAdvanceUnit(_ ch: Character) -> CGFloat {
        if ch == " " { return 0.33 }
        let scalarView = String(ch).unicodeScalars
        if scalarView.count == 1, let u = scalarView.first {
            if u.isASCII {
                // Digits/ASCII letters tend to be narrower than CJK.
                if (u.value >= 48 && u.value <= 57) { return 0.62 } // 0-9
                if (u.value >= 65 && u.value <= 90) { return 0.60 } // A-Z
                if (u.value >= 97 && u.value <= 122) { return 0.58 } // a-z
                return 0.48 // punctuation/symbols
            }
            if isCJKScalar(u) { return 1.0 }
            if u.value > 0xFFFF { return 1.1 } // likely emoji/surrogate plane
            return 0.9
        }
        // Multi-scalar graphemes (emoji sequences etc.)
        for u in scalarView {
            if isCJKScalar(u) { return 1.0 }
            if u.value > 0xFFFF { return 1.1 }
        }
        return 0.95
    }

    private func isCJKScalar(_ u: UnicodeScalar) -> Bool {
        let v = u.value
        if (0x4E00...0x9FFF).contains(v) { return true } // CJK Unified Ideographs
        if (0x3400...0x4DBF).contains(v) { return true } // CJK Extension A
        if (0xF900...0xFAFF).contains(v) { return true } // CJK Compatibility Ideographs
        if (0x3040...0x30FF).contains(v) { return true } // Hiragana/Katakana
        if (0xAC00...0xD7AF).contains(v) { return true } // Hangul
        return false
    }
    
    private func findFirstTextField(in element: AXUIElement, depth: Int = 5) -> AXUIElement? {
        if depth <= 0 { return nil }
        var childrenRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenRef) == .success,
              let children = childrenRef as? [AXUIElement] else { return nil }
        
        let targetRoles = ["AXTextField", "AXTextArea", "AXSearchField", "AXComboBox", "AXHTMLTextInput"]
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
        if bundleID?.lowercased().contains("spotlight") == true { return true }
        if appName?.lowercased().contains("siri") == true { return true }
        if appName?.lowercased().contains("spotlight") == true { return true }
        return false
    }
    
    private func isHighFrequencyApp(appName: String?, bundleID: String?) -> Bool {
        let keywords = [
            "codex", "code", // VS Code
            "cursor", // Cursor
            "zed", // Zed
            "sublime", "atom", "textmate", // Text Editors
            "intellij", "jetbrains", "webstorm", "pycharm", "goland", "rider", "clion", "rubymine", "appcode", "datagrip", "phpstorm", "android studio", // JetBrains
            "xcode", "simulator" // Apple Dev
        ]
        
        let loweredName = appName?.lowercased() ?? ""
        let loweredBundle = bundleID?.lowercased() ?? ""
        
        for kw in keywords {
            if loweredName.contains(kw) || loweredBundle.contains(kw) { return true }
        }
        return false
    }
    
    private func stickyDuration(for bundleID: String?, appName: String?) -> TimeInterval {
        if isHighFrequencyApp(appName: appName, bundleID: bundleID) { return 0.0 } // Legacy: Zero sticky
        return 0.08
    }
}
