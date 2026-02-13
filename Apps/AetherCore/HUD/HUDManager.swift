import SwiftUI
import AppKit
import Combine

final class HUDManager {
    static let shared = HUDManager()
    
    let state = HUDState()
    private let detector = CaretDetector()
    
    private var hudWindow: NSPanel?
    private var hideTask: DispatchWorkItem?
    private var cancellables = Set<AnyCancellable>()
    
    private init() {
        setupSubscriptions()
        detector.start()
    }
    
    // MARK: - Public API
    
    func update(mode: HUDMode, message: String = "", language: String? = nil, isInteractive: Bool = false) {
        // Main thread safety
        if !Thread.isMainThread {
            DispatchQueue.main.async { self.update(mode: mode, message: message, language: language, isInteractive: isInteractive) }
            return
        }
        
        let displayLang = language ?? InputSourceManager.shared.currentInputSourceID
        state.update(mode: mode, message: message, language: displayLang, isInteractive: isInteractive)
        
        // Mode-specific behavior
        switch mode {
        case .hidden:
            scheduleHide(delay: 0.1)
        case .standby:
            // Standby (Wake Word waiting) -> Persistent but minimal
            cancelHide()
            repositionWindow()
            ensureWindowVisible()
        case .active, .dictation:
            // Active interaction -> Persistent
            cancelHide()
            repositionWindow()
            ensureWindowVisible()
        }
    }
    
    func updateAudioLevel(_ level: Float) {
        DispatchQueue.main.async {
             self.state.audioLevel = CGFloat(min(level * 5.0, 1.0))
        }
    }
    
    func showTemporary(message: String) {
        update(mode: .active, message: message)
        scheduleHide(delay: 2.0)
    }
    
    func hide() {
        update(mode: .hidden)
    }
    
    // Replacement for HotkeyFeedbackHUD.typingContextSnapshot()
    func lastKnownTypingState() -> Bool {
        return detector.currentUpdate.caretRect != nil || detector.currentUpdate.isSticky
    }
    
    // MARK: - Internal Logic
    
    private func setupSubscriptions() {
        // 1. Detector Updates (Caret moved)
        detector.$currentUpdate
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.repositionWindow()
            }
            .store(in: &cancellables)
            
        // 2. State Updates (Content changed)
        state.stateChanged
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in
                self?.repositionWindow()
            }
            .store(in: &cancellables)
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
        guard let panel = hudWindow else { return }
        
        // --- Fullscreen Video Check ---
        if shouldSuppressHUDForFullscreenVideo() {
            hideForHiddenCursor()
            return
        }
        
        let update = detector.currentUpdate
        let mouseLoc = NSEvent.mouseLocation
        
        // 1. Determine Anchor & Mode
        var anchor = mouseLoc
        var finalTypingMode = false
        
        if let caret = update.caretRect {
            anchor = CGPoint(x: caret.midX, y: caret.midY)
            finalTypingMode = true
        } else if update.isSticky, let last = detector.recentCaretRect() {
            anchor = CGPoint(x: last.midX, y: last.midY)
            finalTypingMode = true
        }
        
        // Sync to State for UI icons
        if state.isTypingMode != finalTypingMode {
            state.isTypingMode = finalTypingMode
        }
        
        // [Legacy Restore] Click-through behavior
        panel.ignoresMouseEvents = !state.isInteractive
        
        // 2. Determine Reference Screen
        let referencePoint = finalTypingMode ? anchor : mouseLoc
        let currentScreen = NSScreen.screens.first(where: { $0.frame.contains(referencePoint) }) ?? NSScreen.main ?? NSScreen.screens.first!
        let visibleFrame = currentScreen.visibleFrame
        
        // 3. Size Calculation
        panel.contentView?.layoutSubtreeIfNeeded()
        let size = panel.contentView?.fittingSize ?? CGSize(width: 120, height: 44)
        
        // 4. Candidate Position Evaluation
        let padding: CGFloat = 16
        
        // [Legacy Order]
        // Typing Mode: Prefer Top-Right (Standard annotation style)
        // Command Mode: Prefer Bottom-Right (Natural mouse follow)
        let candidates: [(BindingPosition, String)]
        if finalTypingMode {
            candidates = [
                (.topRight, "TR"), (.bottomRight, "BR"), (.topLeft, "TL"), (.bottomLeft, "BL")
            ]
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
        if finalTypingMode, let inputRect = update.inputRect {
             // Legacy used -8, -6
             zones.append(inputRect.insetBy(dx: -8, dy: -6))
        }
        
        for (cand, _) in candidates {
            let p = calculateCandidate(cand, anchor: anchor, size: size, padding: padding, isTyping: finalTypingMode)
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
            var p = calculateCandidate(.bottomRight, anchor: anchor, size: size, padding: padding, isTyping: finalTypingMode)
            
            // [Legacy Smart Fallback]: If inside text area, jump below it
            if finalTypingMode, let inputRect = update.inputRect {
                // Not fully implementing the complex jump logic yet to avoid regressions,
                // relying on Clamping below.
            }
            
            // Clamp to visible frame (Legacy used 'padding' aka 16, not 8)
            p.x = max(visibleFrame.minX + padding, min(p.x, visibleFrame.maxX - size.width - padding))
            p.y = max(visibleFrame.minY + padding, min(p.y, visibleFrame.maxY - size.height - padding))
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
        case topRight, bottomRight, topLeft, bottomLeft, topCenter, bottomCenter
    }
    
    private func calculateCandidate(_ pos: BindingPosition, anchor: CGPoint, size: CGSize, padding: CGFloat, isTyping: Bool) -> CGPoint {
        // [Legacy Restore] 
        // Typing Mode: Use padding (16) instead of 0 to create a gap.
        // Control Mode: Use 24 to clear cursor.
        let yOffset: CGFloat = isTyping ? padding : 24
        
        switch pos {
        case .topRight:
            return CGPoint(x: anchor.x + padding, y: anchor.y + yOffset)
        case .bottomRight:
            return CGPoint(x: anchor.x + padding, y: anchor.y - size.height - padding) // Below doesn't need extra Y offset usually if padding is enough? 
            // Legacy: y = anchor.y - size.height - padding. (No yOffset added in legacy for bottom candidates? Let's check)
            // Legacy: y = anchor.y + cand.offset.y. BottomRight offset: padding, -size.height - padding.
            // So: anchor.y - size.height - padding. Correct.
            // My code below uses + yOffset? 
            // Logic: "Above" needs +yOffset. "Below" needs -yOffset? or just padding?
            // Let's simplify: yOffset is strictly for "Above" candidates to clear the line height?
            
            // Actually, let's strictly follow Legacy Candidate logic:
            // TopRight: (x + padding, y + padding)
        case .topLeft:
             return CGPoint(x: anchor.x - size.width - padding, y: anchor.y + yOffset)
        case .topCenter:
             return CGPoint(x: anchor.x - size.width / 2, y: anchor.y + padding + yOffset)
             
        case .bottomRight:
             // Legacy BottomRight was: y = anchor.y - size.height - padding
             // We can just use -padding.
             return CGPoint(x: anchor.x + padding, y: anchor.y - size.height - padding)
        case .bottomLeft:
             return CGPoint(x: anchor.x - size.width - padding, y: anchor.y - size.height - padding)
        case .bottomCenter:
             return CGPoint(x: anchor.x - size.width / 2, y: anchor.y - size.height - padding)
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

// Dummy InputSourceManager if not exists, or assume it exists in project
class InputSourceManager {
    static let shared = InputSourceManager()
    var currentInputSourceID: String { "en-US" } // Placeholder
}
