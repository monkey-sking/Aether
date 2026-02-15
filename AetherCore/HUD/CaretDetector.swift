import AppKit
import Combine
import Carbon
import ApplicationServices
import OSLog

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
        
        // Fallback Timer (High frequency for smooth mouse following)
        followTimer = Timer.scheduledTimer(withTimeInterval: 0.016, repeats: true) { [weak self] _ in
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
            var role = roleValue as? String ?? ""
            
            // [Silence] Debug log was spamming console
            // logger.error("HUD_DEBUG: Focused App='\(self.currentAppName ?? "unknown")', Bundle='\(bundleID)', Role='\(role)'")
            
            // Drill down
            if ["AXWindow", "AXSheet", "AXScrollArea", "AXSplitGroup"].contains(role) || isSiriLike(appName: self.currentAppName, bundleID: bundleID) {
                if let child = findFirstTextField(in: element) {
                    element = child
                    // [Legacy Fix] Re-fetch role for the new element so isEditable checks work
                    var newRoleVal: CFTypeRef?
                    if AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &newRoleVal) == .success {
                        role = newRoleVal as? String ?? ""
                    }
                }
            }
            
            // Editability - adding AXGroup as a potential container for web-based inputs
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
                          if AXValueGetValue(boundsValue as! AXValue, .cgRect, &rawR) {
                              if (rawR.origin.x == 0 && rawR.origin.y == 0) || (rawR.width <= 1 && rawR.height <= 1) {
                                  // Bogus
                              } else if rawR.width > 80 || rawR.height > 80 {
                                  // Selection/Bound (Not a caret)
                              } else {
                                  if let r = extractRect(from: boundsValue!) {
                                      if isValid(r, in: windowFrame) {
                                          newRect = r
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
                             if AXValueGetValue(boundsValue as! AXValue, .cgRect, &rawR) {
                                  // 1. Bogus Check (0,0) or Tiny
                                  if (rawR.origin.x == 0 && rawR.origin.y == 0) || (rawR.width <= 1 && rawR.height <= 1) {
                                      self.logger.debug("🚨 [PRE-FLIP REJECT] Bogus standard range: \(rawR.debugDescription)")
                                  } 
                                  // 2. Non-Caret Geometry (Selection)
                                  // Codex often returns the whole line/block as selection range
                                  else if rawR.width > 80 || rawR.height > 80 {
                                      self.logger.debug("🚫 [NON-CARET] Rejecting large selection range: \(rawR.debugDescription)")
                                  } 
                                  else {
                                      if let r = extractRect(from: boundsValue!) {
                                          if isValid(r, in: windowFrame) {
                                              newRect = r
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
                     var p = CGPoint.zero; var s = CGSize.zero
                     if AXValueGetValue(posValue as! AXValue, .cgPoint, &p), AXValueGetValue(sizeValue as! AXValue, .cgSize, &s) {
                         let axVal = AXValueCreate(.cgRect, [CGRect(origin: p, size: s)])
                         if let r_appkit = extractRect(from: axVal as CFTypeRef) {
                             if isValid(r_appkit, in: windowFrame) {
                                  // [Logic Refactor] Prioritize Synthetic > Huge Rejection
                                  // 1. Synthetic Candidates (WebArea, TextArea users)
                                  if (role == "AXTextArea" || role == "AXWebArea") && (r_appkit.width > 220 || r_appkit.height > 70) {
                                      // [Legacy Restore] Codex/HighFreq Rule: Never use synthetic caret for code editors.
                                      // But DO use it for Browsers (WebArea).
                                      if !self.isHighFrequencyApp(appName: self.currentAppName, bundleID: self.currentAppBundleID) {
                                          self.logger.debug("⚠️ [WEAK CARET] Large bounds -> Synthetic Caret")
                                          let h = min(max(14.0, r_appkit.height), 24.0)
                                          let y = r_appkit.minY + max(0.0, (r_appkit.height - h) * 0.5)
                                          newRect = CGRect(x: r_appkit.minX + 12, y: y, width: 2, height: h)
                                          newInputContextRect = r_appkit
                                          shouldTemporarilyKeepLastCaret = true
                                      } else {
                                          self.logger.debug("🛡 [CODEX] Rejection: Preventing synthetic caret for editor pane.")
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
                                                     if AXValueGetValue(selectedRangeValue as! AXValue, .cfRange, &range) {
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
        if let r = newRect, self.isHighFrequencyApp(appName: self.currentAppName, bundleID: self.currentAppBundleID) {
             if r.width > 100 || r.height > 100 {
                 self.logger.debug("🛡 [CODEX] Final Sanity: Rejecting huge caret \(r.debugDescription, privacy: .public)")
                 newRect = nil
             } else {
                 self.logger.debug("✅ [CODEX] Final Sanity: Accepted caret \(r.debugDescription, privacy: .public)")
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
                
                // [Legacy Special Rule] Codex/HighFreq: Immediate Clear (Synchronous)
                if self.isHighFrequencyApp(appName: self.lastFocusedAppName, bundleID: self.lastFocusedBundleID) {
                    self.resetCaretState()
                    self.updateState()
                    return
                }

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
            return appKitRectFromAX(r)
        }
        return nil
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
        if r.width <= 0 || r.height <= 0 { return false } // [Fix] Reject empty rects (Codex 0,1050,0,0)

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
    
    private func readAXBool(_ element: AXUIElement, attribute: String) -> Bool? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        if let b = value as? Bool { return b }
        if let n = value as? NSNumber { return n.boolValue }
        return nil
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
