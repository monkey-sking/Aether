import SwiftUI
import AppKit
import Combine
import OSLog

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
    
    func update(mode: HUDMode, message: String = "", language: String, inputDeviceIcon: String = "mic.fill") {
        
        // Main thread safety
        if !Thread.isMainThread {
            DispatchQueue.main.async { self.update(mode: mode, message: message, language: language, inputDeviceIcon: inputDeviceIcon) }
            return
        }
        
        state.update(mode: mode, message: message, language: language, isTypingContext: lastKnownTypingState(), inputDeviceIcon: inputDeviceIcon)
        
        // Mode-specific behavior
        switch mode {
        case .hidden:
            performHide()
        case .standby:
            cancelHide()
            repositionWindow()
            ensureWindowVisible()
        case .listening, .command, .dictation, .processing:
            cancelHide()
            repositionWindow()
            ensureWindowVisible()
        }
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
        state.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
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
        if state.isTypingContext != finalTypingMode {
            state.isTypingContext = finalTypingMode
        }
        
        // Click-through: only allow mouse interaction when language toggle is visible
        let interactiveModes: [HUDMode] = [.listening, .command, .dictation]
        panel.ignoresMouseEvents = !interactiveModes.contains(state.mode)
        
        // 2. Determine Reference Screen
        let referencePoint = finalTypingMode ? anchor : mouseLoc
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
