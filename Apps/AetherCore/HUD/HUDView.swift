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
                Text("speech.listening")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                    .shadow(color: .black.opacity(0.2), radius: 1, x: 0, y: 1)
                    .fixedSize()
                languageToggle

            case .command:
                micIcon
                Text(state.message)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                    .shadow(color: .black.opacity(0.2), radius: 1, x: 0, y: 1)
                    .fixedSize()
                languageToggle

            case .dictation:
                WaveformView(level: state.audioLevel)
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
        Image(systemName: "mic.fill")
            .foregroundColor(.green)
            .font(.system(size: 14))
            .scaleEffect(1.0 + (state.audioLevel * 0.5))
            .shadow(radius: 1)
            .opacity(0.8 + (state.audioLevel * 0.2))
            .animation(.linear(duration: 0.1), value: state.audioLevel)
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
