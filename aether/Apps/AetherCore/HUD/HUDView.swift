import SwiftUI

struct HUDView: View {
    @ObservedObject var state: HUDState
    
    var body: some View {
        HStack(spacing: 8) {
            switch state.mode {
            case .hidden:
                EmptyView()

            case .standby:
                Circle()
                    .fill(Color.green.opacity(0.8))
                    .frame(width: 8, height: 8)
                    .shadow(radius: 2)

            case .listening:
                micIcon
                Text(state.message.isEmpty ? LocalizedStringKey("speech.listening") : LocalizedStringKey(state.message))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                    .shadow(color: .black.opacity(0.2), radius: 1, x: 0, y: 1)
                    .fixedSize()
                contextIcon
                languageToggle(showDivider: true)

            case .command:
                if state.message.isEmpty {
                    micIcon
                    contextIcon
                    languageToggle(showDivider: true)
                } else {
                    micIcon
                    Text(state.message)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                        .shadow(color: .black.opacity(0.2), radius: 1, x: 0, y: 1)
                        .fixedSize()
                    contextIcon
                    languageToggle(showDivider: true)
                }

            case .dictation:
                micIcon
                WaveformView(level: state.audioLevel)
                contextIcon
                languageToggle(showDivider: true)

            case .processing:
                Image(systemName: "ellipsis")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.white.opacity(0.8))
                    .symbolEffect(.variableColor.iterative.reversing)
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

    // MARK: - Reusable Components

    private var micIcon: some View {
        ZStack {
            if state.isMicProgressVisible && (state.mode == .listening || state.mode == .command || state.mode == .dictation) {
                Circle()
                    .stroke(Color.white.opacity(0.22), lineWidth: 2)
                    .frame(width: 22, height: 22)
                Circle()
                    .trim(from: 0, to: state.micProgress)
                    .stroke(
                        Color.green.opacity(0.9),
                        style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .frame(width: 22, height: 22)
            }

            let requestedIcon = state.inputDeviceIcon
            if requestedIcon == "airpodspro.left" || requestedIcon == "airpodspro.right" {
                let isLeft = requestedIcon == "airpodspro.left"
                // Measured against the actual SwiftUI render path (`font(14) + clip + frame(22)`):
                // with the user-perspective swap (`!isLeft`), a 4pt compensation centers the clipped bud.
                let airPodsProHalfOffset: CGFloat = 4.0
                Image(systemName: "airpodspro")
                    .foregroundColor(.white)
                    .font(.system(size: 14))
                    .shadow(radius: 1)
                    // Swap: We want the other side of the symbol to match user perspective
                    .clipShape(AirPodHalfClip(isLeft: !isLeft))
                    .offset(x: isLeft ? -airPodsProHalfOffset : airPodsProHalfOffset)
            } else {
                Image(systemName: resolvedSymbolName(for: requestedIcon))
                    .foregroundColor(.white)
                    .font(.system(size: 14))
                    .shadow(radius: 1)
            }
        }
        .frame(width: 22, height: 22)
    }
    
    // MARK: - Helper Types
    
    struct AirPodHalfClip: Shape {
        let isLeft: Bool
        func path(in rect: CGRect) -> Path {
            var path = Path()
            // Reverted to user-confirmed crop values to clean up "other bud" residue while keeping shape
            let mid = rect.width / 2
            if isLeft {
                path.addRect(CGRect(x: 0, y: 0, width: mid - 1, height: rect.height))
            } else {
                path.addRect(CGRect(x: mid + 1, y: 0, width: mid + 1, height: rect.height))
            }
            return path
        }
    }
    
    private static let symbolFallbacks: [String: [String]] = [
        "airpodspro.left": ["airpod.gen3.left", "airpod.left", "airpods", "headphones"],
        "airpodspro.right": ["airpod.gen3.right", "airpod.right", "airpods", "headphones"],
        "airpod.gen3.left": ["airpod.left", "airpods", "headphones"],
        "airpod.gen3.right": ["airpod.right", "airpods", "headphones"],
        "airpod.gen3": ["airpods", "headphones"],
        "airpodspro": ["airpods", "headphones"],
        "airpodsmax": ["headphones"]
    ]

    private func resolvedSymbolName(for requested: String) -> String {
        let normalized = requested.trimmingCharacters(in: .whitespacesAndNewlines)
        let primary = normalized.isEmpty ? "mic.slash" : normalized
        if isValidSymbol(primary) { return primary }

        if let fallbacks = Self.symbolFallbacks[primary] {
            for fallback in fallbacks where isValidSymbol(fallback) {
                return fallback
            }
        }

        return isValidSymbol("mic.slash") ? "mic.slash" : "mic"
    }

    private func isValidSymbol(_ name: String) -> Bool {
        NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil
    }

    private var contextIcon: some View {
        let symbol: String
        switch state.recognitionControlMode {
        case .command:
            symbol = "command"
        case .dictation:
            symbol = "keyboard"
        case .auto:
            symbol = state.isTypingContext ? "keyboard" : "command"
        }

        return Image(systemName: symbol)
            .font(.system(size: 12))
            .foregroundColor(.white.opacity(0.8))
            .shadow(radius: 1)
    }

    private var displayLanguage: String {
        let localized = NSLocalizedString("speech.lang_indicator", comment: "HUD language indicator")
        // If the key is not found or matches the key name (default behavior), fallback to prefix
        if localized == "speech.lang_indicator" || localized.isEmpty {
            return String(state.language.prefix(2)).capitalized
        }
        return localized
    }

    private func languageToggle(showDivider: Bool) -> some View {
        HStack(spacing: 8) {
            if showDivider {
                Divider()
                    .frame(height: 16)
                    .background(Color.white.opacity(0.3))
            }

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
                .animation(.spring(response: 0.15, dampingFraction: 0.4, blendDuration: 0), value: level)
            }
        }
        .frame(height: 20)
    }

    private func barHeight(for index: Int) -> CGFloat {
        // [Optimization] Non-linear scaling (pow 0.8)
        // This ensures the bars grow rapidly for small levels but resist 
        // hitting the 'baseHeight' too easily for normal/loud speech.
        let curveLevel = pow(level, 0.8)
        
        let baseHeights: [CGFloat] = [6, 11, 16, 11, 6]
        let dynamicHeight = 3 + (baseHeights[index] - 3) * curveLevel
        return min(baseHeights[index], dynamicHeight)
    }
}
