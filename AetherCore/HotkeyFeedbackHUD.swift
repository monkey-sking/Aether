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
    
    // State hosted in SwiftUI
    private class HUDState: ObservableObject {
        @Published var message: String = ""
        @Published var isListening: Bool = false
        @Published var language: String = "zh-CN"
        @Published var isInteractive: Bool = false
        @Published var isDictating: Bool = false // New State
    }
    
    private let state = HUDState()
    private let logger = Logger(subsystem: "com.7fei.Aether", category: "HUD")
    
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
                guard let self = self, let state = self.state else { return }
                // Only follow cursor if NOT in typing/dictation mode
                if !state.isDictating {
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
        let hostingController = NSHostingController(rootView: rootView)
        hostingController.view.wantsLayer = true
        hostingController.view.layer?.backgroundColor = NSColor.clear.cgColor
        hostingController.view.layer?.backgroundColor = NSColor.clear.cgColor
        
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 60),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary]
        panel.contentViewController = hostingController
        
        self.hudWindow = panel
    }
    
    private func repositionWindow() {
        guard let panel = hudWindow else { return }
        
        // Follow Mouse Logic
        let mouseLoc = NSEvent.mouseLocation
        // Flip Y for screen coordinates (Bottom-Left origin)
        // NSEvent.mouseLocation is already bottom-left relative to screen 0?
        // Yes, verify: screen 0 is usually main.
        
        // Panel size
        panel.contentView?.layoutSubtreeIfNeeded()
        let size = panel.contentView?.fittingSize ?? CGSize(width: 200, height: 60)
        
        // Position: 20px below/right of cursor
        var x = mouseLoc.x + 20
        var y = mouseLoc.y - size.height - 20
        
        // Constrain to screen
        if let screen = NSScreen.main {
            let frame = screen.visibleFrame
            x = max(frame.minX, min(x, frame.maxX - size.width))
            y = max(frame.minY, min(y, frame.maxY - size.height))
        }
        
        panel.setFrameOrigin(NSPoint(x: x, y: y))
        // Resize if needed
        if panel.frame.size != size {
             panel.setContentSize(size)
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
                        .scaleEffect(isAnimating ? 1.2 : 1.0)
                        .opacity(isAnimating ? 1.0 : 0.7)
                        .animation(Animation.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: isAnimating)
                        .onAppear { isAnimating = true }
                }
                
                Text(state.message)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white)
                    .fixedSize()
                
                // Input Mode Indicator
                if state.isDictating {
                    Image(systemName: "keyboard")
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.8))
                } else if state.isInteractive {
                     Image(systemName: "command")
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.6))
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
                            .fixedSize() // Prevent "..." truncation
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.white.opacity(0.2))
                            .cornerRadius(4)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16) // Increased padding
            .padding(.vertical, 10)   // Increased padding
            .padding(.horizontal, 16) // Increased padding
            .padding(.vertical, 10)   // Increased padding
            .background(.regularMaterial) // Use native SwiftUI Material to fix clipping issues
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(Color.white.opacity(0.2), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.2), radius: 8, x: 0, y: 4)
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
            return view
        }
        
        func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
            nsView.material = material
            nsView.blendingMode = blendingMode
        }
    }
}
