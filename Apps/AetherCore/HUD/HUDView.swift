import SwiftUI

struct HUDView: View {
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
            
            switch state.mode {
            case .standby:
                return "" // Minimal mode, no text usually
            case .active:
                if raw.isEmpty || raw == listeningText {
                    return String(localized: "speech.listening")
                }
                return state.message
            case .dictation:
                return state.message
            case .hidden:
                return ""
            }
        }()
        
        HStack(spacing: 8) {
            // Mode-specific Leading Icon
            switch state.mode {
            case .standby:
                // Minimal Dot for Standby
                Circle()
                    .fill(Color.green.opacity(0.8))
                    .frame(width: 8, height: 8)
                    .shadow(radius: 2)
            case .active:
                // Mic Icon for Active Command
                Image(systemName: "mic.fill")
                    .foregroundColor(.green)
                    .font(.system(size: 14))
                    .scaleEffect(1.0 + (state.audioLevel * 0.5))
                    .shadow(radius: 1)
                    .opacity(0.8 + (state.audioLevel * 0.2))
                    .animation(.linear(duration: 0.1), value: state.audioLevel)
            case .dictation:
                // Dictation uses Waveform (handled below) or custom icon
                EmptyView() 
            case .hidden:
                EmptyView()
            }
            
            // Content Area
            if state.mode == .dictation {
                 WaveformView(level: state.audioLevel)
                 // [Design] If showing waveform, do NOT show text to prevent clutter/loss issues
                 // User prefers waveform only for feedback
            } else if state.mode == .active {
                if !displayMessage.isEmpty {
                    Text(displayMessage)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                        .shadow(color: .black.opacity(0.2), radius: 1, x: 0, y: 1)
                        .fixedSize()
                }
            }
            
            // Trailing Icons (Context)
            if state.isTypingMode {
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
            
            // Language Toggle
            if state.isInteractive || state.mode == .dictation {
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
        .padding(.horizontal, state.mode == .standby ? 8 : 16)
        .padding(.vertical, state.mode == .standby ? 8 : 10)
        .background(
            VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
        )
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: Color.black.opacity(0.1), radius: 4, x: 0, y: 2)
    }
}

struct VisualEffectView: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode
    
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        view.appearance = NSAppearance(named: .vibrantDark)
        return view
    }
    
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
        if nsView.appearance?.name != .vibrantDark {
            nsView.appearance = NSAppearance(named: .vibrantDark)
        }
    }
}

struct WaveformView: View {
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
        let baseHeights: [CGFloat] = [6, 10, 14, 10, 6]
        let variance = CGFloat.random(in: 0.8...1.2)
        return max(3, baseHeights[index] * level * 2 * variance)
    }
}
