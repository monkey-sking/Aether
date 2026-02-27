import SwiftUI
import AppKit
import Combine
import OSLog

final class HUDManager {
    static let shared = HUDManager()
    
    let state = HUDState()
    private let detector = CaretDetector()
    private var lastAXTypingCheckAt: Date = .distantPast
    private var cachedAXTypingState: Bool = false
    private var lastAXFocusRectCheckAt: Date = .distantPast
    private var cachedAXFocusRect: CGRect?
    private var lastAXCaretRectCheckAt: Date = .distantPast
    private var cachedAXCaretRect: CGRect?
    private var lastAXEstimatedCaretCheckAt: Date = .distantPast
    private var cachedAXEstimatedCaretPoint: CGPoint?
    private var cachedAXEstimatedCaretBounds: CGRect?
    private var lastAnchorTraceAt: Date = .distantPast
    private var lastAnchorTraceSignature: String = ""
    private var lastGoodTypingRect: CGRect?
    private var lastGoodTypingRectAt: Date = .distantPast
    private var lastInputInteractionPoint: CGPoint?
    private var lastInputInteractionAt: Date = .distantPast
    
    private var hudWindow: NSPanel?
    private var hideTask: DispatchWorkItem?
    private var pendingRepositionWorkItem: DispatchWorkItem?
    private var cancellables = Set<AnyCancellable>()
    
    private init() {
        setupSubscriptions()
        detector.start()
    }
    
    // MARK: - Public API
    
    func update(mode: HUDMode, message: String = "", language: String, inputDeviceIcon: String = "mic.fill") {
        
        // Main thread safety
        if !Thread.isMainThread {
            DispatchQueue.main.async { self.update(mode: mode, message: message, language: language, inputDeviceIcon: inputDeviceIcon) }
            return
        }
        
        state.update(mode: mode, message: message, language: language, isTypingContext: lastKnownTypingState(), inputDeviceIcon: inputDeviceIcon)
        if mode == .hidden {
            // Ensure transient indicators don't linger when the HUD is dismissed.
            state.isMicProgressVisible = false
            state.micProgress = 0.0
        }
        
        // Mode-specific behavior
        switch mode {
        case .hidden:
            performHide()
        case .standby:
            cancelHide()
            requestReposition(immediate: true)
            ensureWindowVisible()
        case .listening, .command, .dictation, .processing:
            cancelHide()
            requestReposition(immediate: true)
            ensureWindowVisible()
        }
    }

    func updateMicProgress(progress: CGFloat, visible: Bool) {
        if !Thread.isMainThread {
            DispatchQueue.main.async { self.updateMicProgress(progress: progress, visible: visible) }
            return
        }
        let clamped = min(max(progress, 0.0), 1.0)
        state.micProgress = clamped
        state.isMicProgressVisible = visible
    }
    
    func updateAudioLevel(_ level: Float) {
        DispatchQueue.main.async {
             // Further reduced gain from 10.0 to 8.0 to ensure 
             // normal speech doesn't constantly clip at 100%.
             self.state.audioLevel = CGFloat(min(level * 8.0, 1.0))
        }
    }
    
    func showTemporary(message: String, language: String? = nil, icon: String = "info.circle") {
        update(mode: .command, message: message, language: language ?? state.language, inputDeviceIcon: icon)
        scheduleHide(delay: 2.0)
    }
    
    func hide() {
        update(mode: .hidden, language: state.language, inputDeviceIcon: state.inputDeviceIcon)
    }
    
    // Replacement for HotkeyFeedbackHUD.typingContextSnapshot()
    func lastKnownTypingState() -> Bool {
        // Prefer caret/sticky (fast, high confidence), but fall back to AX focused element editability.
        // This fixes cases where the caret rect is not obtainable (some apps / web views),
        // but the focus is clearly in a text input.
        if detector.currentUpdate.caretRect != nil {
            return true
        }
        // Sticky can linger in "weird" apps; only treat it as typing if we still have a recent caret rect.
        if detector.currentUpdate.isSticky, detector.recentCaretRect() != nil {
            return true
        }

        // Codex/Antigravity-style web UIs: treat typing context as true only if we can obtain
        // input-box-sized geometry (or caret bounds). This avoids getting "stuck" in input mode
        // when AX reports a huge editable container.
        if isWeirdWebTypingApp(bundleID: detector.currentUpdate.sourceBundleID) {
            if axCaretRectThrottled() != nil { return true }
            if let r = detector.currentUpdate.inputRect, isTypingBoxSizedRect(r), !isProbablyWholeWindowRect(r) { return true }
            if let r = axFocusedElementRectThrottled(), isTypingBoxSizedRect(r), !isProbablyWholeWindowRect(r) { return true }
            return false
        }

        let now = Date()
        if now.timeIntervalSince(lastAXTypingCheckAt) < 0.12 {
            return cachedAXTypingState
        }
        lastAXTypingCheckAt = now
        let v = isAXFocusedElementEditable()
        cachedAXTypingState = v
        return v
    }

    private func isWeirdWebTypingApp(bundleID: String?) -> Bool {
        let b = (bundleID ?? NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "").lowercased()
        if b.contains("codex") { return true }
        if b.contains("antigravity") { return true }
        // Future: add more "web-based" special cases here.
        return false
    }

    private func isAXFocusedElementEditable() -> Bool {
        let systemWide = AXUIElementCreateSystemWide()
        var focusedElement: AnyObject?
        guard AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &focusedElement) == .success,
              let focusedElement else {
            return false
        }

        let element = focusedElement as! AXUIElement

        func boolAttr(_ name: CFString) -> Bool? {
            var value: CFTypeRef?
            guard AXUIElementCopyAttributeValue(element, name, &value) == .success else { return nil }
            if let b = value as? Bool { return b }
            if let n = value as? NSNumber { return n.boolValue }
            return nil
        }

        var roleRef: CFTypeRef?
        let role = (AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleRef) == .success)
            ? (roleRef as? String ?? "")
            : ""

        let directEditableRoles: Set<String> = [kAXTextFieldRole as String, kAXTextAreaRole as String, "AXSearchField", "AXComboBox", "AXHTMLTextInput"]

        // Prefer explicit editability.
        // This avoids false positives where a non-editable AXWebArea still exposes a selected range.
        let editable = boolAttr("AXEditable" as CFString) == true
        if editable { return true }

        // Role-based fallback: treat common input roles as typing context.
        if directEditableRoles.contains(role) { return true }

        // WebArea is extremely common as a focused element in web UIs even when not in a text box.
        // Without AXEditable, we treat it as non-typing to allow exiting "input mode" when clicking elsewhere.
        if role == "AXWebArea" { return false }

        // As a last resort, accept insertion-context attributes for non-WebArea elements.
        let hasSelectedRange: Bool = {
            var v: CFTypeRef?
            return AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &v) == .success
        }()
        let hasMarkerRange: Bool = {
            var v: CFTypeRef?
            return AXUIElementCopyAttributeValue(element, "AXSelectedTextMarkerRange" as CFString, &v) == .success
        }()
        if hasSelectedRange || hasMarkerRange {
            return true
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

    private func isProbablyWholeWindowRect(_ r: CGRect) -> Bool {
        guard r.width > 0, r.height > 0 else { return true }
        // Use intersection rather than midpoint: some bogus AX rects have insane origins and midpoints off-screen.
        let screen = NSScreen.screens.first(where: { $0.frame.intersects(r) }) ??
            NSScreen.screens.first(where: { $0.visibleFrame.intersects(r) }) ??
            NSScreen.main ??
            NSScreen.screens.first
        let s = screen?.visibleFrame ?? .zero
        guard s.width > 0, s.height > 0 else { return false }
        // Treat huge WebArea/window bounds as not a useful "input box" anchor.
        // We intentionally bias towards rejecting large containers (Codex/Antigravity often reports the whole pane).
        let area = r.width * r.height
        let screenArea = s.width * s.height
        if screenArea > 0, area > screenArea * 0.22 { return true }
        if r.height > 160 { return true }
        if r.width > s.width * 0.92, r.height > 60 { return true }
        return (r.width > s.width * 0.65) && (r.height > s.height * 0.45)
    }

    private func isTypingBoxSizedRect(_ r: CGRect) -> Bool {
        // Heuristic for "single-line input" / compact editor input region.
        // Codex prompt box tends to be short; the big editor pane is tall.
        if r.width <= 0 || r.height <= 0 { return false }
        if r.height < 18 { return false }
        if r.height > 110 { return false }
        if r.width < 140 { return false }
        return true
    }

    private func stableTypingRect(now: Date, candidate: CGRect?) -> CGRect? {
        if let c = candidate, isTypingBoxSizedRect(c), !isProbablyWholeWindowRect(c) {
            lastGoodTypingRect = c
            lastGoodTypingRectAt = now
            return c
        }
        if let last = lastGoodTypingRect, now.timeIntervalSince(lastGoodTypingRectAt) < 1.2 {
            return last
        }
        return nil
    }

    private func axFocusedElementRectThrottled() -> CGRect? {
        let now = Date()
        if now.timeIntervalSince(lastAXFocusRectCheckAt) < 0.18 {
            return cachedAXFocusRect
        }
        lastAXFocusRectCheckAt = now

        let systemWide = AXUIElementCreateSystemWide()
        var focusedElement: AnyObject?
        guard AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &focusedElement) == .success,
              let focusedElement else {
            cachedAXFocusRect = nil
            return nil
        }
        let element = focusedElement as! AXUIElement

        var posRef: CFTypeRef?
        var sizeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &posRef) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeRef) == .success,
              let posRef,
              let sizeRef else {
            cachedAXFocusRect = nil
            return nil
        }
        var p = CGPoint.zero
        var s = CGSize.zero
        let posVal = posRef as! AXValue
        let sizeVal = sizeRef as! AXValue
        guard AXValueGetValue(posVal, .cgPoint, &p),
              AXValueGetValue(sizeVal, .cgSize, &s) else {
            cachedAXFocusRect = nil
            return nil
        }

        let axRect = CGRect(origin: p, size: s)
        let r = appKitRectFromAX(axRect)
        cachedAXFocusRect = r
        return r
    }

    // Prefer caret geometry derived from the focused element's selected range.
    // This is significantly more reliable in web-based inputs (Chromium/WebView/Electron),
    // where the focused element bounds often represent a huge AXWebArea/container.
    private func axCaretRectThrottled() -> CGRect? {
        let now = Date()
        if now.timeIntervalSince(lastAXCaretRectCheckAt) < 0.12 {
            return cachedAXCaretRect
        }
        lastAXCaretRectCheckAt = now

        let systemWide = AXUIElementCreateSystemWide()
        var focusedElement: AnyObject?
        guard AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &focusedElement) == .success,
              let focusedElement else {
            cachedAXCaretRect = nil
            return nil
        }
        let element = focusedElement as! AXUIElement

        func rectFromParameterizedBounds(parameter: CFTypeRef, attr: CFString) -> CGRect? {
            var boundsRef: CFTypeRef?
            let err = AXUIElementCopyParameterizedAttributeValue(element, attr, parameter, &boundsRef)
            guard err == .success, let boundsVal = boundsRef else { return nil }
            guard CFGetTypeID(boundsVal) == AXValueGetTypeID() else { return nil }
            var axRect = CGRect.zero
            let axV = boundsVal as! AXValue
            guard AXValueGetValue(axV, .cgRect, &axRect) else { return nil }
            return appKitRectFromAX(axRect)
        }

        // 1) SelectedTextRange -> BoundsForRange (parameterized) => caret/selection rect in screen coords.
        var axRect: CGRect? = nil
        var rangeRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &rangeRef) == .success,
           let rangeVal = rangeRef {
            axRect = rectFromParameterizedBounds(parameter: rangeVal, attr: kAXBoundsForRangeParameterizedAttribute as CFString)
        }

        // 2) SelectedTextMarkerRange -> BoundsForTextMarkerRange (parameterized)
        // Some web-based apps expose marker ranges but not standard CFRange-based bounds.
        if axRect == nil {
            var markerRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(element, "AXSelectedTextMarkerRange" as CFString, &markerRef) == .success,
               let markerVal = markerRef {
                axRect = rectFromParameterizedBounds(parameter: markerVal, attr: "AXBoundsForTextMarkerRange" as CFString)
            }
        }

        guard let r0 = axRect else {
            cachedAXCaretRect = nil
            return nil
        }

        let r = r0

        // Reject obviously-wrong container rects.
        if isProbablyWholeWindowRect(r) {
            cachedAXCaretRect = nil
            return nil
        }

        cachedAXCaretRect = r
        return r
    }

    // Estimate caret point inside the focused element by using its value + selected range.
    // This helps for web-based inputs where bounds-for-range returns nil, but selected range/value exist.
    private func axEstimatedCaretContextThrottled() -> (point: CGPoint, bounds: CGRect)? {
        let now = Date()
        if now.timeIntervalSince(lastAXEstimatedCaretCheckAt) < 0.12 {
            if let p = cachedAXEstimatedCaretPoint, let b = cachedAXEstimatedCaretBounds {
                return (point: p, bounds: b)
            }
            return nil
        }
        lastAXEstimatedCaretCheckAt = now

        let systemWide = AXUIElementCreateSystemWide()
        var focusedElement: AnyObject?
        guard AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &focusedElement) == .success,
              let focusedElement else {
            cachedAXEstimatedCaretPoint = nil
            cachedAXEstimatedCaretBounds = nil
            return nil
        }
        let element = focusedElement as! AXUIElement

        // Focused element bounds in AX coords.
        var posRef: CFTypeRef?
        var sizeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &posRef) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeRef) == .success,
              let posRef,
              let sizeRef else {
            cachedAXEstimatedCaretPoint = nil
            cachedAXEstimatedCaretBounds = nil
            return nil
        }
        var p = CGPoint.zero
        var s = CGSize.zero
        let posVal = posRef as! AXValue
        let sizeVal = sizeRef as! AXValue
        guard AXValueGetValue(posVal, .cgPoint, &p),
              AXValueGetValue(sizeVal, .cgSize, &s) else {
            cachedAXEstimatedCaretPoint = nil
            cachedAXEstimatedCaretBounds = nil
            return nil
        }
        guard let bounds = appKitRectFromAX(CGRect(origin: p, size: s)) else {
            cachedAXEstimatedCaretPoint = nil
            cachedAXEstimatedCaretBounds = nil
            return nil
        }
        // Only use this estimator for "input-like" bounds; never for huge containers.
        if isProbablyWholeWindowRect(bounds) {
            cachedAXEstimatedCaretPoint = nil
            cachedAXEstimatedCaretBounds = nil
            return nil
        }

        // Selected range + value.
        var valueRef: CFTypeRef?
        var selectedRangeValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &valueRef) == .success,
              let valueStr = valueRef as? String,
              AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &selectedRangeValue) == .success else {
            cachedAXEstimatedCaretPoint = nil
            cachedAXEstimatedCaretBounds = nil
            return nil
        }
        var range = CFRange()
        let axV = selectedRangeValue as! AXValue
        guard AXValueGetValue(axV, .cfRange, &range) else {
            cachedAXEstimatedCaretPoint = nil
            cachedAXEstimatedCaretBounds = nil
            return nil
        }

        let total = max(0, valueStr.count)
        let location = max(0, min(range.location + range.length, total))
        if total == 0 {
            // No text: assume caret near left inset.
            let pt = CGPoint(x: bounds.minX + 18, y: bounds.midY)
            cachedAXEstimatedCaretPoint = pt
            cachedAXEstimatedCaretBounds = bounds
            return (point: pt, bounds: bounds)
        }

        func isCJKScalar(_ u: UnicodeScalar) -> Bool {
            let v = u.value
            if (0x4E00...0x9FFF).contains(v) { return true }
            if (0x3400...0x4DBF).contains(v) { return true }
            if (0xF900...0xFAFF).contains(v) { return true }
            if (0x3040...0x30FF).contains(v) { return true }
            if (0xAC00...0xD7AF).contains(v) { return true }
            return false
        }
        func advanceUnit(_ ch: Character) -> CGFloat {
            if ch == " " { return 0.33 }
            let scalars = String(ch).unicodeScalars
            if scalars.count == 1, let u = scalars.first {
                if u.isASCII {
                    if (48...57).contains(u.value) { return 0.62 }
                    if (65...90).contains(u.value) { return 0.60 }
                    if (97...122).contains(u.value) { return 0.58 }
                    return 0.48
                }
                if isCJKScalar(u) { return 1.0 }
                if u.value > 0xFFFF { return 1.1 }
                return 0.9
            }
            for u in scalars {
                if isCJKScalar(u) { return 1.0 }
                if u.value > 0xFFFF { return 1.1 }
            }
            return 0.95
        }
        func weightedUnits(_ s: String, upTo n: Int) -> CGFloat {
            if n <= 0 { return 0 }
            var units: CGFloat = 0
            var i = 0
            for ch in s {
                if i >= n { break }
                units += advanceUnit(ch)
                i += 1
            }
            return units
        }

        // Model inside the bounds:
        // - If text "fits" in the control, use a fixed-step model (more accurate for short strings).
        // - If text is longer than the control, clamp to the usable width (caret tends to pin to the right).
        let leadingInset = min(max(10.0, bounds.height * 0.5), 22.0)
        let trailingInset: CGFloat = 10.0
        let usableWidth = max(8.0, bounds.width - leadingInset - trailingInset)
        let unitsSoFar = weightedUnits(valueStr, upTo: location)
        let totalUnits = max(0.1, weightedUnits(valueStr, upTo: total))
        let step = min(max(9.0, bounds.height * 0.52), 13.0)
        let totalPx = totalUnits * step
        let offset: CGFloat
        if totalPx <= usableWidth {
            offset = unitsSoFar * step
        } else {
            offset = min(unitsSoFar * step, usableWidth)
        }
        let pt = CGPoint(x: bounds.minX + leadingInset + min(max(offset, 0.0), usableWidth), y: bounds.midY)
        cachedAXEstimatedCaretPoint = pt
        cachedAXEstimatedCaretBounds = bounds
        return (point: pt, bounds: bounds)
    }

    private func isTopBarInputRect(_ r: CGRect) -> Bool {
        // Browser address bars / top search fields live near the top of the visible frame.
        // In that case, placing the HUD above the input will often get clamped into awkward corners.
        guard r.width > 0, r.height > 0 else { return false }
        let screen = NSScreen.screens.first(where: { $0.visibleFrame.intersects(r) }) ??
            NSScreen.screens.first(where: { $0.frame.intersects(r) }) ??
            NSScreen.main
        let vf = screen?.visibleFrame ?? .zero
        guard vf.height > 0 else { return false }
        let topGap = max(0, vf.maxY - r.maxY)
        return topGap < 90
    }
    
    // MARK: - Internal Logic
    
    private func setupSubscriptions() {
        // 1. Detector Updates (Caret moved)
        detector.$currentUpdate
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.requestReposition()
            }
            .store(in: &cancellables)

        // 2. State updates that can affect layout.
        Publishers.CombineLatest4(state.$mode, state.$message, state.$language, state.$isTypingContext)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.requestReposition()
            }
            .store(in: &cancellables)

        // 3. Focus change in "weird" UIs (Codex/Antigravity) often doesn't move the caret rect.
        // Poll at low frequency while HUD is visible so clicking elsewhere can exit input mode
        // without requiring ESC.
        Timer.publish(every: 0.2, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self else { return }
                guard let panel = self.hudWindow, panel.isVisible else { return }
                if self.state.mode == .hidden { return }
                self.requestReposition()
            }
            .store(in: &cancellables)
    }

    private func requestReposition(immediate: Bool = false) {
        pendingRepositionWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.repositionWindow()
        }
        pendingRepositionWorkItem = work
        if immediate {
            DispatchQueue.main.async(execute: work)
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.012, execute: work)
        }
    }
    
    private func ensureWindow() {
        guard hudWindow == nil else { return }
        
        let rootView = HUDView(state: state)
        let hostingController = NSHostingController(rootView: rootView)
        hostingController.view.layer?.backgroundColor = NSColor.clear.cgColor
        
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
    }
    
    private func ensureWindowVisible() {
        ensureWindow()
        guard let panel = hudWindow else { return }
        if !panel.isVisible || panel.alphaValue < 0.9 {
            panel.alphaValue = 1.0
            panel.orderFront(nil)
        }
    }
    
    private func repositionWindow() {
        // [Ghost Keyboard Fix] Accessing mode from state should be main-thread safe enough here
        // If hidden, DO NOT move or update content (prevents "Ghost Keyboard" when fading out)
        if state.mode == .hidden { return }
        
        guard let panel = hudWindow else { return }
        
        // --- Fullscreen Video Check ---
        if shouldSuppressHUDForFullscreenVideo() {
            hideForHiddenCursor()
            return
        }
        
        let update = detector.currentUpdate
        let mouseLoc = NSEvent.mouseLocation
        let axFocusRect = axFocusedElementRectThrottled()
        let axCaret = axCaretRectThrottled()
        let axEstimated = axEstimatedCaretContextThrottled()
        
        // 1. Determine Anchor & Mode
        var anchor = mouseLoc
        let uiTypingMode = lastKnownTypingState()
        let wasTypingMode = state.isTypingContext
        var layoutTypingMode = false
        var preferAboveInput = false
        var preferBelowInput = false
        var typingRect: CGRect? = nil
        let now = Date()

        if !uiTypingMode {
            // Prevent stale anchors from "sticking" after focus leaves an input box.
            lastGoodTypingRect = nil
            lastGoodTypingRectAt = .distantPast
        }

        if uiTypingMode {
            // Prefer caret detector input rect when it's sane; otherwise fall back to the AX focused element bounds.
            if let r = update.inputRect, !isProbablyWholeWindowRect(r) {
                typingRect = r
            } else if let r = axFocusRect, !isProbablyWholeWindowRect(r) {
                typingRect = r
            }
            typingRect = stableTypingRect(now: now, candidate: typingRect)

            // Top-bar inputs (browser address bar) should prefer placing the HUD below,
            // otherwise we tend to clamp into awkward "top right" positions.
            if let r = typingRect, isTopBarInputRect(r) {
                preferBelowInput = true
                preferAboveInput = false
            }
        }

        // If we just entered typing mode (often via keyboard focus like Cmd+L),
        // initialize a reasonable "interaction point" so we don't bias the HUD far away.
        if uiTypingMode, !wasTypingMode, let r = typingRect {
            let isTopBar = isTopBarInputRect(r)
            let x: CGFloat
            if isTopBar {
                // Address bar caret is frequently at the end when focused via keyboard.
                x = r.maxX - 16
            } else {
                let bias = min(220, r.width * 0.33)
                x = r.minX + bias
            }
            lastInputInteractionPoint = CGPoint(x: min(max(x, r.minX + 8), r.maxX - 8), y: r.midY)
            lastInputInteractionAt = now
        }

        if uiTypingMode, let r = typingRect, r.contains(mouseLoc) {
            // Capture the last interaction point within the input box so we can estimate caret X
            // without "following the mouse" after focus leaves the input.
            lastInputInteractionPoint = mouseLoc
            lastInputInteractionAt = now
        }
        
        if let caret = update.caretRect {
            anchor = CGPoint(x: caret.midX, y: caret.midY)
            layoutTypingMode = true
        } else if update.isSticky, let last = detector.recentCaretRect() {
            anchor = CGPoint(x: last.midX, y: last.midY)
            layoutTypingMode = true
        } else if uiTypingMode, let axCaret {
            // Web-based UIs (Codex/Antigravity) often fail caret detection but expose bounds-for-range.
            anchor = CGPoint(x: axCaret.midX, y: axCaret.midY)
            layoutTypingMode = true
        } else if uiTypingMode, let axEstimated {
            // If bounds-for-range is unavailable, fall back to an estimated caret X within focused bounds.
            anchor = axEstimated.point
            layoutTypingMode = true
            preferAboveInput = true
            // Critical: treat focused bounds as typingRect so the HUD avoids covering the input text.
            if typingRect == nil {
                typingRect = axEstimated.bounds
                typingRect = stableTypingRect(now: now, candidate: typingRect)
            }
        } else if uiTypingMode, let r = typingRect {
            // Typing context, but no caret geometry: estimate caret X from recent input interaction,
            // and anchor ABOVE the input box to avoid colliding with the input rect.
            let recentInteraction = now.timeIntervalSince(lastInputInteractionAt) < 1.8
            let estimatedX: CGFloat = {
                if recentInteraction, let p = lastInputInteractionPoint {
                    return min(max(p.x, r.minX + 8), r.maxX - 8)
                }
                if isTopBarInputRect(r) {
                    // If we have no interaction signal, assume address-bar caret near the end.
                    return r.maxX - 16
                }
                // No interaction signal.
                // For wide "prompt" inputs, bias closer to the left so we don't end up far from caret.
                if r.width > 420 {
                    let bias = min(140, r.width * 0.2)
                    return min(max(r.minX + bias, r.minX + 8), r.maxX - 8)
                }
                let bias = min(220, r.width * 0.33)
                return min(max(r.minX + bias, r.minX + 8), r.maxX - 8)
            }()
            if preferBelowInput || isTopBarInputRect(r) {
                preferBelowInput = true
                preferAboveInput = false
                anchor = CGPoint(x: estimatedX, y: r.minY)
            } else {
                anchor = CGPoint(x: estimatedX, y: r.maxY)
                preferAboveInput = true
            }
            layoutTypingMode = true
        }
        
        // Sync to State for UI icons
        if state.isTypingContext != uiTypingMode {
            state.isTypingContext = uiTypingMode
        }

        // If we are in a typing context (keyboard icon) but we don't have a reliable caret/sticky anchor,
        // do NOT fall back to mouse-follow. Keeping the HUD stable is preferable to jitter.
        // This also matches Codex/Antigravity-style UIs where caret geometry is often missing or misleading.
        if uiTypingMode && !layoutTypingMode && panel.isVisible {
            return
        }
        
        // Click-through: only allow mouse interaction when language toggle is visible
        let interactiveModes: [HUDMode] = [.listening, .command, .dictation]
        panel.ignoresMouseEvents = !interactiveModes.contains(state.mode)
        
        // 2. Determine Reference Screen
        let referencePoint = layoutTypingMode ? anchor : mouseLoc
        let currentScreen = NSScreen.screens.first(where: { $0.frame.contains(referencePoint) }) ?? NSScreen.main ?? NSScreen.screens.first!
        let visibleFrame = currentScreen.visibleFrame
        
        // 3. Size Calculation
        // Avoid forcing a synchronous layout pass here; doing so during app startup
        // can re-enter SwiftUI graph updates and trigger AG precondition crashes.
        let existingSize = panel.frame.size
        let size: CGSize
        if existingSize.width > 1, existingSize.height > 1 {
            size = existingSize
        } else {
            size = CGSize(width: 200, height: 60)
        }
        
        // 4. Candidate Position Evaluation
        let padding: CGFloat = 16
        
        // [Legacy Order]
        // Typing Mode: Prefer Right-Center (input-adjacent), then fall back to corners.
        // Command Mode: Prefer Bottom-Right (Natural mouse follow)
        let candidates: [(BindingPosition, String)]
        if layoutTypingMode {
            if preferBelowInput {
                candidates = [
                    (.bottomRight, "BR"),
                    (.bottomCenter, "BC"),
                    (.bottomLeft, "BL"),
                    (.rightCenter, "RC"),
                    (.leftCenter, "LC"),
                    (.topCenter, "TC"),
                    (.topRight, "TR"),
                    (.topLeft, "TL")
                ]
            } else if preferAboveInput {
                candidates = [
                    (.topCenter, "TC"),
                    (.topRight, "TR"),
                    (.topLeft, "TL"),
                    (.rightCenter, "RC"),
                    (.leftCenter, "LC"),
                    (.bottomRight, "BR"),
                    (.bottomLeft, "BL")
                ]
            } else {
                candidates = [
                    (.rightCenter, "RC"),
                    (.leftCenter, "LC"),
                    (.topRight, "TR"),
                    (.bottomRight, "BR"),
                    (.topLeft, "TL"),
                    (.bottomLeft, "BL")
                ]
            }
        } else {
            candidates = [
                (.bottomRight, "BR"), (.topRight, "TR"), (.bottomLeft, "BL"), (.topLeft, "TL")
            ]
        }
        
        var bestPos: CGPoint? = nil
        
        // [Legacy] Avoidance Zones
        var zones: [CGRect] = []
        // Avoid Mouse
        zones.append(CGRect(x: mouseLoc.x - 15, y: mouseLoc.y - 15, width: 30, height: 30))
        
        // Avoid Caret itself (Legacy: caret.insetBy(dx: -5, dy: -2))
        if let caret = update.caretRect {
            zones.append(caret.insetBy(dx: -5, dy: -2))
        }
        
        // Avoid Input Context (Text Area)
        if layoutTypingMode, let inputRect = typingRect ?? update.inputRect {
             // Legacy used -8, -6
             zones.append(inputRect.insetBy(dx: -8, dy: -6))
        }
        
        for (cand, _) in candidates {
            let p = calculateCandidate(cand, anchor: anchor, size: size, padding: padding, isTyping: layoutTypingMode)
            let rect = CGRect(origin: p, size: size)
            
            // Rule 1: Must be within visible frame
            if visibleFrame.contains(rect) {
                // Rule 2: Avoid Collision
                var collision = false
                for zone in zones {
                    if rect.intersects(zone) {
                        collision = true
                        break
                    }
                }
                
                if !collision {
                    bestPos = p
                    break
                }
            }
        }
        
        // 5. Fallback: Edge Clamping & Smart Vertical Jump
        if bestPos == nil {
            var p = calculateCandidate(.bottomRight, anchor: anchor, size: size, padding: padding, isTyping: layoutTypingMode)
            
            // [Legacy Smart Fallback]: If inside text area, jump below it
            if layoutTypingMode, let _ = update.inputRect {
                // Not fully implementing the complex jump logic yet to avoid regressions,
                // relying on Clamping below.
            }
            
            // Clamp to visible frame (Legacy used 'padding' aka 16, not 8)
            p.x = max(visibleFrame.minX + padding, min(p.x, visibleFrame.maxX - size.width - padding))
            p.y = max(visibleFrame.minY + padding, min(p.y, visibleFrame.maxY - size.height - padding))

            // Legacy behavior: keep the HUD horizontally within the input box when in typing mode.
            // This prevents bottom-center placement from drifting far from the caret for long address bars.
            if layoutTypingMode, let r = typingRect {
                p.x = min(max(r.minX, p.x), r.maxX - size.width)
            }
            bestPos = p
        }
        
        if let pos = bestPos {
            panel.setFrameOrigin(pos)
            if panel.frame.size != size {
                 panel.setContentSize(size)
            }
            if !panel.isVisible && (state.mode != .hidden) {
                ensureWindowVisible()
            }

            // Lightweight file trace for weird UIs (Codex/Antigravity).
            // Only logs when the computed anchor/typing rect or final position changes meaningfully.
            if now.timeIntervalSince(lastAnchorTraceAt) > 0.12 {
                lastAnchorTraceAt = now
                func fmt(_ r: CGRect?) -> String {
                    guard let r else { return "nil" }
                    return "\(Int(r.origin.x)),\(Int(r.origin.y)),\(Int(r.size.width)),\(Int(r.size.height))"
                }
                let lastPtSig: String = {
                    guard let p = lastInputInteractionPoint, lastInputInteractionAt != .distantPast else { return "nil" }
                    let ageMs = Int(now.timeIntervalSince(lastInputInteractionAt) * 1000)
                    return "\(Int(p.x)),\(Int(p.y))@\(ageMs)ms"
                }()
                let sig = "mode=\(state.mode.rawValue) uiTyping=\(uiTypingMode) layoutTyping=\(layoutTypingMode) sticky=\(update.isSticky) anchor=\(Int(anchor.x)),\(Int(anchor.y)) lastPt=\(lastPtSig) inputRect=\(fmt(update.inputRect)) typingRect=\(fmt(typingRect)) axCaret=\(fmt(axCaret)) axFocus=\(fmt(axFocusRect)) lastGood=\(fmt(lastGoodTypingRect)) caret=\(fmt(update.caretRect)) final=\(Int(pos.x)),\(Int(pos.y)) size=\(Int(size.width))x\(Int(size.height))"
                if sig != lastAnchorTraceSignature {
                    lastAnchorTraceSignature = sig
                    let line = "\(now): \(sig)\n"
                    if let data = line.data(using: .utf8) {
                        let path = "/tmp/aether_hud_anchor_trace.txt"
                        if !FileManager.default.fileExists(atPath: path) {
                            FileManager.default.createFile(atPath: path, contents: nil)
                        }
                        if let fh = FileHandle(forWritingAtPath: path) {
                            fh.seekToEndOfFile()
                            fh.write(data)
                            try? fh.close()
                        }
                    }
                }
            }
        }
    }
    
    // --- Fullscreen Video Logic ---
    
    private func shouldSuppressHUDForFullscreenVideo() -> Bool {
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) ?? NSScreen.main else {
            return false
        }
        let isImmersive = screen.frame.size == screen.visibleFrame.size
        return isImmersive
    }
    
    private func hideForHiddenCursor() {
        if hudWindow?.isVisible == true {
            hudWindow?.alphaValue = 0
            hudWindow?.orderOut(nil)
        }
    }
    
    private enum BindingPosition {
        case topRight, bottomRight, topLeft, bottomLeft, topCenter, bottomCenter, rightCenter, leftCenter
    }
    
    private func calculateCandidate(_ pos: BindingPosition, anchor: CGPoint, size: CGSize, padding: CGFloat, isTyping: Bool) -> CGPoint {
        // Typing Mode: Use padding (16) to create gap from caret.
        // Control Mode: Use 24 to clear cursor.
        let yOffset: CGFloat = isTyping ? padding : 24
        
        switch pos {
        case .topRight:
            return CGPoint(x: anchor.x + padding, y: anchor.y + yOffset)
        case .topLeft:
            return CGPoint(x: anchor.x - size.width - padding, y: anchor.y + yOffset)
        case .topCenter:
            return CGPoint(x: anchor.x - size.width / 2, y: anchor.y + yOffset)
        case .bottomRight:
            return CGPoint(x: anchor.x + padding, y: anchor.y - size.height - padding)
        case .bottomLeft:
            return CGPoint(x: anchor.x - size.width - padding, y: anchor.y - size.height - padding)
        case .bottomCenter:
            return CGPoint(x: anchor.x - size.width / 2, y: anchor.y - size.height - padding)
        case .rightCenter:
            return CGPoint(x: anchor.x + padding, y: anchor.y - size.height / 2)
        case .leftCenter:
            return CGPoint(x: anchor.x - size.width - padding, y: anchor.y - size.height / 2)
        }
    }
    
    // MARK: - Hide Logic
    
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
        })
    }
}
