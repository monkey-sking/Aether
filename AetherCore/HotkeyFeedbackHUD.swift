import SwiftUI
import AppKit
import os.log

/// A Unified HUD for Voice, PTT, and Hotkey Feedback.
/// Features: Follows mouse, interactive (language toggle), and persistent during dictation.
final class HotkeyFeedbackHUD {
    
    static let shared = HotkeyFeedbackHUD()
    private init() {}
    
    private var hudWindow: NSPanel?
    private var hideTask: DispatchWorkItem?

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
        @Published var isDictating: Bool = false // New State
        @Published var audioLevel: CGFloat = 0.0 // 0.0 to 1.0
    }
    
    private let state = HUDState()
    private let logger = Logger(subsystem: "com.7fei.Aether", category: "HUD")
    
    func updateAudioLevel(_ level: Float) {
        // Smooth changes if needed, but direct update is responsive
        DispatchQueue.main.async {
            // Visualize: map -60dB...0dB to 0...1? 
            // Input level is likely RMS amplitude (0.0 - 1.0)
            // Let's amplify small sounds: pow(level, 0.5) or * 5
            self.state.audioLevel = CGFloat(min(level * 5.0, 1.0)) 
        }
    }
    
    // MARK: - Public API
    
    static func show(_ message: String, icon: String? = nil) {
        shared.update(message: message, isListening: false)
        shared.scheduleHide(delay: 1.5)
    }
    
    static func showContinuous(message: String, isListening: Bool, language: String, isDictating: Bool) {
        shared.update(message: message, isListening: isListening, language: language, isInteractive: true, isDictating: isDictating)
        shared.cancelHide()
    }
    
    static func hide() {
        shared.scheduleHide(delay: 0.1)
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
            
            // Allow clicks if interactive
            self.hudWindow?.ignoresMouseEvents = !isInteractive
            
            self.repositionWindow()
            self.hudWindow?.orderFront(nil)
            self.hudWindow?.alphaValue = 1.0
            
            // Start following mouse if interactive/listening
            self.startFollowTimer()
        }
    }
    
    private var followTimer: Timer?
    
    private func startFollowTimer() {
        followTimer?.invalidate()
        followTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            DispatchQueue.main.async {
                guard let self = self else { return }
                // Only follow cursor if NOT in typing/dictation mode
                if !self.state.isDictating {
                    self.repositionWindow()
                }
            }
        }
    }
    
    private func stopFollowTimer() {
        followTimer?.invalidate()
        followTimer = nil
    }
    
    private func ensureWindow() {
        guard hudWindow == nil else { return }
        
        let savedState = self.state
        let rootView = HUDView(state: savedState)
        let hostingController = TransparentHostingController(rootView: rootView)
        // Background set in subclass loadView()
        
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
        panel.hasShadow = false // Disable system shadow to avoid square artifacts; SwiftUI handles shadow.
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary]
        panel.contentViewController = hostingController
        
        self.hudWindow = panel
    }
    
    private var caretRect: CGRect?
    private var lastCaretRect: CGRect?
    
    private func updateCaretRect() {
        // Run on background to avoid blocking UI
        DispatchQueue.global(qos: .userInteractive).async {
            var newRect: CGRect? = nil
            
            // 1. Get System-wide Element
            let systemWide = AXUIElementCreateSystemWide()
            
            // 2. Get Focused Element (Directly from system-wide, handles Spotlight/Overlays)
            var focusedElement: CFTypeRef?
            let elementStatus = AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &focusedElement)
            
            if elementStatus == .success {
                let element = focusedElement as! AXUIElement
                
                // 3. Get Selected Text Range
                var selectedRangeValue: CFTypeRef?
                let rangeStatus = AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &selectedRangeValue)
                
                if rangeStatus == .success {
                    // 4. Get Bounds for Range
                    var boundsValue: CFTypeRef?
                    let boundsStatus = AXUIElementCopyParameterizedAttributeValue(element, kAXBoundsForRangeParameterizedAttribute as CFString, selectedRangeValue!, &boundsValue)
                    
                    if boundsStatus == .success {
                        var rect = CGRect.zero
                        if AXValueGetValue(boundsValue as! AXValue, .cgRect, &rect) {
                            if let screenHeight = NSScreen.screens.first?.frame.height {
                                 rect.origin.y = screenHeight - rect.origin.y - rect.height
                            }
                            newRect = rect
                            self.logger.debug("✅ Caret detected at \(rect.debugDescription)")
                        }
                    } else {
                        self.logger.error("❌ Failed to get caret bounds: \(boundsStatus.rawValue)")
                    }
                } else {
                    // Optional: Try fallback to kAXBoundsAttribute for some generic elements
                    self.logger.error("❌ Failed to get selected range: \(rangeStatus.rawValue)")
                }
            } else {
                self.logger.error("❌ Failed to get focused element: \(elementStatus.rawValue)")
            }
            
            DispatchQueue.main.async {
                // Detect "Focus Jump"
                if let old = self.lastCaretRect, let current = newRect {
                    let dist = sqrt(pow(old.midX - current.midX, 2) + pow(old.midY - current.midY, 2))
                    if dist > 50 { // Significant jump (e.g., new window or field)
                        self.logger.debug("🔄 Focus Jump detected (dist: \(dist)). Force repositioning.")
                        self.caretRect = current
                        self.lastCaretRect = current
                        self.repositionWindow()
                    }
                } else if self.lastCaretRect == nil && newRect != nil {
                    // First focus detected
                    self.logger.debug("🆕 Initial focus detected at \(newRect!.debugDescription)")
                    self.caretRect = newRect
                    self.lastCaretRect = newRect
                    self.repositionWindow()
                }
                
                // Continuous update without force-repositioning (let followTimer handle small drift)
                self.caretRect = newRect
                if newRect != nil {
                    self.lastCaretRect = newRect
                }
            }
        }
    }

    private func repositionWindow() {
        guard let panel = hudWindow else { return }
        
        // Refresh caret info periodically (throttled by the caller timer)
        updateCaretRect()
        
        let mouseLoc = NSEvent.mouseLocation // Bottom-Left Reference
        
        // HUD Size
        panel.contentView?.layoutSubtreeIfNeeded()
        let size = panel.contentView?.fittingSize ?? CGSize(width: 200, height: 60)
        let padding: CGFloat = 20
        
        // ---------------------------------------------------------
        // 1. Determine Anchor & Mode
        // ---------------------------------------------------------
        let isTypingMode = self.caretRect != nil
        let anchor: CGPoint
        
        if isTypingMode, let caret = self.caretRect {
            // Anchor relative to Caret (Typing Mode)
            anchor = CGPoint(x: caret.midX, y: caret.minY)
            // self.logger.debug("⚓️ Anchoring to Caret (Typing Mode)")
        } else {
            // Anchor relative to Mouse (Command Mode)
            anchor = mouseLoc
            // self.logger.debug("⚓️ Anchoring to Mouse (Command Mode)")
        }
        
        // ---------------------------------------------------------
        // 2. Define High-Priority Avoidance Zones
        // ---------------------------------------------------------
        var zones: [CGRect] = []
        
        // Always avoid Mouse Cursor
        let mouseZone = CGRect(x: mouseLoc.x - 15, y: mouseLoc.y - 15, width: 30, height: 30)
        zones.append(mouseZone)
        
        // Always avoid Caret (if present)
        if let caret = self.caretRect {
            zones.append(caret.insetBy(dx: -5, dy: -2)) 
        }
        
        // ---------------------------------------------------------
        // 3. Evaluate Candidate Positions
        // ---------------------------------------------------------
        struct Candidate {
            let offset: CGPoint
            let name: String
        }
        
        let candidates: [Candidate]
        if isTypingMode {
            // Typing Mode: Prefer below or above caret, slightly offset
            candidates = [
                Candidate(offset: CGPoint(x: padding, y: -size.height - padding), name: "Caret-Below-Right"),
                Candidate(offset: CGPoint(x: padding, y: padding), name: "Caret-Above-Right"),
                Candidate(offset: CGPoint(x: -size.width - padding, y: -size.height - padding), name: "Caret-Below-Left"),
                Candidate(offset: CGPoint(x: -size.width - padding, y: padding), name: "Caret-Above-Left")
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
        
        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            
            for cand in candidates {
                let x = anchor.x + cand.offset.x
                let y = anchor.y + cand.offset.y
                let frame = CGRect(origin: CGPoint(x: x, y: y), size: size)
                
                // Rule 1: Must be on screen
                if !screenFrame.contains(frame) { continue }
                
                // Rule 2: Must not collide with mouse or caret
                var collision = false
                for zone in zones {
                    if frame.intersects(zone) {
                        collision = true
                        break 
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
                // Clamp to screen
                x = max(screenFrame.minX + padding, min(x, screenFrame.maxX - size.width - padding))
                y = max(screenFrame.minY + padding, min(y, screenFrame.maxY - size.height - padding))
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
            
            HStack(spacing: 8) {
                if state.isListening {
                    Image(systemName: "mic.fill")
                        .foregroundColor(.green)
                        .font(.system(size: 14))
                        .scaleEffect(1.0 + (state.audioLevel * 1.5)) // React to volume
                        .shadow(radius: 1) // [Clarity] Shadow for icon
                        .opacity(0.6 + (state.audioLevel * 0.4))
                        .animation(.linear(duration: 0.1), value: state.audioLevel)
                }
                
                Text(state.message)
                    // [Clarity] Thicker font for legibility on blur
                    .font(.system(size: 14, weight: .semibold)) 
                    .foregroundColor(.white)
                    // [Clarity] Shadow for text against light backgrounds
                    .shadow(color: .black.opacity(0.2), radius: 1, x: 0, y: 1)
                    .fixedSize()
                
                // Input Mode Indicator
                if state.isDictating {
                    Image(systemName: "keyboard")
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.9)) // [Clarity] Higher opacity
                        .shadow(radius: 1)
                } else if state.isInteractive {
                     Image(systemName: "command")
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.7))
                        .shadow(radius: 1)
                }
                
                if state.isInteractive {
                    Divider()
                        .frame(height: 16)
                        .background(Color.white.opacity(0.3))
                    
                    Button(action: {
                        // Toggle Language via Notification
                        NotificationCenter.default.post(name: Notification.Name("AetherToggleLanguage"), object: nil)
                    }) {
                        Text(displayLanguage)
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.white)
                            .shadow(color: .black.opacity(0.2), radius: 1, x: 0, y: 1) // [Clarity] Text shadow
                            .fixedSize() // Prevent "..." truncation
                            .frame(minWidth: 24, alignment: .center) // Fix width to prevent jitter
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
}
