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
                languageToggle

            case .command:
                micIcon
                Text(state.message)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                    .shadow(color: .black.opacity(0.2), radius: 1, x: 0, y: 1)
                    .fixedSize()
                contextIcon
                languageToggle

            case .dictation:
                micIcon
                WaveformView(level: state.audioLevel)
                contextIcon
                languageToggle

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

            Image(systemName: resolvedSymbolName(for: state.inputDeviceIcon))
                .foregroundColor(.white)
                .font(.system(size: 14))
                .shadow(radius: 1)
        }
        .frame(width: 22, height: 22)
    }
    
    private func resolvedSymbolName(for requested: String) -> String {
        let normalized = requested.trimmingCharacters(in: .whitespacesAndNewlines)
        let primary = normalized.isEmpty ? "mic.slash" : normalized
        return primary
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
        if state.language.starts(with: "zh") { return "中" }
        if state.language.starts(with: "en") { return "En" }
        if state.language.starts(with: "ja") { return "日" }
        if state.language.starts(with: "ko") { return "한" }
        if state.language.starts(with: "fr") { return "Fr" }
        if state.language.starts(with: "de") { return "De" }
        if state.language.starts(with: "es") { return "Es" }
        return String(state.language.prefix(2)).capitalized
    }

    private var languageToggle: some View {
        HStack(spacing: 8) {
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
