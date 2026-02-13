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
        
        // 2. Determine Reference Screen
        // Typing mode: anchor at caret. Control mode: anchor at mouse.
        let referencePoint = finalTypingMode ? anchor : mouseLoc
        let currentScreen = NSScreen.screens.first(where: { $0.frame.contains(referencePoint) }) ?? NSScreen.main ?? NSScreen.screens.first!
        let visibleFrame = currentScreen.visibleFrame
        
        // 3. Size Calculation
        panel.contentView?.layoutSubtreeIfNeeded()
        let size = panel.contentView?.fittingSize ?? CGSize(width: 120, height: 44)
        
        // 4. Candidate Position Evaluation
        // We evaluate several relative positions to find the best fit.
        let padding: CGFloat = 16
        let candidates: [(BindingPosition, String)] = [
            (.topRight, "TR"), (.bottomRight, "BR"), (.topLeft, "TL"), (.bottomLeft, "BL"), 
            (.topCenter, "TC"), (.bottomCenter, "BC")
        ]
        
        var bestPos: CGPoint? = nil
        
        for (cand, _) in candidates {
            let p = calculateCandidate(cand, anchor: anchor, size: size, padding: padding, isTyping: finalTypingMode)
            let rect = CGRect(origin: p, size: size)
            
            // Validation: Must be within visible frame
            if visibleFrame.contains(rect) {
                // Scoring: Avoid collision with mouse or anchor point
                let mouseCollision = rect.insetBy(dx: -10, dy: -10).contains(mouseLoc)
                if !mouseCollision {
                    bestPos = p
                    break
                }
            }
        }
        
        // 5. Fallback: Edge Clamping
        if bestPos == nil {
            var p = calculateCandidate(.bottomRight, anchor: anchor, size: size, padding: padding, isTyping: finalTypingMode)
            // Clamp to visible frame
            p.x = max(visibleFrame.minX + 8, min(p.x, visibleFrame.maxX - size.width - 8))
            p.y = max(visibleFrame.minY + 8, min(p.y, visibleFrame.maxY - size.height - 8))
            bestPos = p
        }
        
        if let pos = bestPos {
            panel.setFrameOrigin(pos)
            if panel.frame.size != size {
                 panel.setContentSize(size)
            }
            // Ensure visibility if not hidden by logic
            if !panel.isVisible && (state.mode != .hidden) {
                ensureWindowVisible()
            }
        }
    }
    
    // --- Fullscreen Video Logic ---
    
    private func shouldSuppressHUDForFullscreenVideo() -> Bool {
        // If the frontmost screen is in "Immersive" mode (Dock and Menu Bar hidden)
        // This is the standard state for fullscreen video playback.
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) ?? NSScreen.main else {
            return false
        }
        
        // In fullscreen, the frame and visibleFrame are identical.
        let isImmersive = screen.frame.size == screen.visibleFrame.size
        
        // We only suppress if not actively typing/interacting, or if it's truly immersive.
        // For now, follow the simple 'immersive' rule to match legacy behavior.
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
        // Offset adjustments based on original logic
        let yOffset: CGFloat = isTyping ? 0 : 0 // Original had specific Siri/Mouse offsets
        
        switch pos {
        case .topRight:
            return CGPoint(x: anchor.x + padding, y: anchor.y + yOffset)
        case .bottomRight:
            return CGPoint(x: anchor.x + padding, y: anchor.y - size.height - padding + yOffset)
        case .topLeft:
            return CGPoint(x: anchor.x - size.width - padding, y: anchor.y + yOffset)
        case .bottomLeft:
            return CGPoint(x: anchor.x - size.width - padding, y: anchor.y - size.height - padding + yOffset)
        case .topCenter:
            return CGPoint(x: anchor.x - size.width / 2, y: anchor.y + padding + yOffset)
        case .bottomCenter:
            return CGPoint(x: anchor.x - size.width / 2, y: anchor.y - size.height - padding + yOffset)
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
