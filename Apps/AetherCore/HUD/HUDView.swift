import SwiftUI
import AppKit

struct HUDView: View {
    @ObservedObject var state: HUDState
    
    var body: some View {
        VStack(alignment: .leading, spacing: state.isGestureTrailVisible ? 8 : 0) {
            HStack(spacing: 8) {
                switch state.mode {
                case .hidden:
                    EmptyView()

                case .standby:
                    StandbyDotView()
                    if state.isLanguageIndicatorVisible {
                        languageToggle(showDivider: true)
                    }

                case .listening:
                    listeningLeadingVisual
                    if !trimmedMessage.isEmpty {
                        hudLabel(trimmedMessage)
                    }
                    contextIcon
                    if state.isLanguageIndicatorVisible {
                        languageToggle(showDivider: true)
                    }

                case .command:
                    listeningLeadingVisual
                    if !trimmedMessage.isEmpty {
                        hudLabel(trimmedMessage)
                    }
                    contextIcon
                    if state.isLanguageIndicatorVisible {
                        languageToggle(showDivider: true)
                    }

                case .dictation:
                    actionBadge(symbol: "keyboard", tone: .green)
                    if trimmedMessage.isEmpty {
                        WaveformView(level: state.audioLevel)
                    } else {
                        hudLabel(trimmedMessage)
                    }
                    contextIcon
                    if state.isLanguageIndicatorVisible {
                        languageToggle(showDivider: true)
                    }

                case .dragging:
                    actionBadge(symbol: "hand.draw.fill", tone: .white)
                    hudLabel(NSLocalizedString("speech.dragging", comment: ""))
                    contextIcon
                    if state.isLanguageIndicatorVisible {
                        languageToggle(showDivider: true)
                    }

                case .processing:
                    processingLeadingVisual
                    if !trimmedMessage.isEmpty {
                        hudLabel(trimmedMessage)
                    }
                    contextIcon
                    if state.isLanguageIndicatorVisible {
                        languageToggle(showDivider: true)
                    }

                case .feedback:
                    feedbackLeadingVisual
                    if shouldShowFeedbackText {
                        hudLabel(trimmedMessage)
                    }
                    if state.isLanguageIndicatorVisible {
                        languageToggle(showDivider: shouldShowFeedbackText)
                    }
                }
            }

            if state.isGestureTrailVisible {
                GestureTrailView(points: state.gestureTrailPoints)
                    .frame(width: 172, height: 74)
                if !state.gestureTrailStatus.isEmpty {
                    Text(state.gestureTrailStatus)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.white.opacity(0.84))
                        .fixedSize()
                }
            }
        }
        .padding(.horizontal, state.mode == .standby ? 8 : 16)
        .padding(.vertical, state.mode == .standby ? 8 : 10)
        .background(
            VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
        )
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: Color.black.opacity(0.1), radius: 4, x: 0, y: 2)
        .overlay(alignment: .topLeading) {
            if state.caretDebugIndicatorVisible {
                HStack(spacing: 4) {
                    Circle()
                        .fill(state.caretDebugIndicatorColor)
                        .frame(width: 8, height: 8)
                        .overlay(
                            Circle()
                                .stroke(Color.white.opacity(0.8), lineWidth: 1)
                        )
                    if !state.caretDebugIndicatorLabel.isEmpty {
                        Text(state.caretDebugIndicatorLabel)
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundColor(.white.opacity(0.9))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.black.opacity(0.28))
                            .clipShape(Capsule())
                    }
                }
                .offset(x: 6, y: 6)
            }
        }
    }

    // MARK: - Reusable Components

    private var trimmedMessage: String {
        state.message.trimmingCharacters(in: .whitespacesAndNewlines)
    }

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
            Image(systemName: resolvedSymbolName(for: requestedIcon))
                .foregroundColor(.white)
                .font(.system(size: 14))
                .shadow(radius: 1)
        }
        .frame(width: 22, height: 22)
    }

    private var listeningLeadingVisual: some View {
        ZStack {
            AudioReactiveRingView(level: state.audioLevel)
            micIcon
        }
        .frame(width: 28, height: 28)
    }

    private var processingLeadingVisual: some View {
        HStack(spacing: 6) {
            if let symbol = processingAccentSymbol {
                actionBadge(symbol: symbol, tone: processingTone)
            }
            ProcessingDotsView(tone: processingTone)
        }
    }

    private var feedbackLeadingVisual: some View {
        AnimatedHUDBadge(
            symbol: feedbackSymbol,
            tone: feedbackTone,
            animatePulse: true
        )
    }

    private var processingAccentSymbol: String? {
        let requested = state.inputDeviceIcon.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !requested.isEmpty else { return nil }
        guard !isGenericProcessingIcon(requested) else { return nil }
        return resolvedSymbolName(for: requested)
    }

    private var processingTone: Color {
        guard let symbol = processingAccentSymbol else { return .white.opacity(0.92) }
        if symbol.contains("wand") { return .mint }
        if symbol.contains("keyboard") || symbol.contains("text.cursor") { return .green }
        return .white.opacity(0.92)
    }

    private var feedbackSymbol: String {
        let requested = state.inputDeviceIcon.trimmingCharacters(in: .whitespacesAndNewlines)
        if requested.isEmpty {
            return "checkmark.circle.fill"
        }
        return resolvedSymbolName(for: requested)
    }

    private var feedbackTone: Color {
        if compactFeedbackMessages.contains(trimmedMessage) || feedbackSymbol.contains("checkmark") {
            return .green
        }
        if feedbackSymbol.contains("xmark") || feedbackSymbol.contains("slash") {
            return .red
        }
        if feedbackSymbol.contains("exclamationmark") || feedbackSymbol.contains("pause") {
            return .orange
        }
        if feedbackSymbol.contains("wand") {
            return .mint
        }
        if feedbackSymbol.contains("keyboard") || feedbackSymbol.contains("text.cursor") {
            return .green
        }
        if feedbackSymbol.contains("command") {
            return .cyan
        }
        if trimmedMessage.isEmpty {
            return .green
        }
        return .white
    }

    private var shouldShowFeedbackText: Bool {
        guard !trimmedMessage.isEmpty else { return false }
        return !compactFeedbackMessages.contains(trimmedMessage)
    }

    private var compactFeedbackMessages: Set<String> {
        [
            NSLocalizedString("speech.done", comment: ""),
            NSLocalizedString("speech.typed", comment: ""),
            NSLocalizedString("speech.pasted", comment: ""),
            NSLocalizedString("speech.pasted_cmdv", comment: ""),
            NSLocalizedString("speech.undo", comment: ""),
            NSLocalizedString("speech.undo_done", comment: ""),
            "Full-text rewrite complete",
            "Checked. No rewrite needed",
            "已完成全文纠错优化",
            "已检查，原文无需修改"
        ]
    }

    private func isGenericProcessingIcon(_ icon: String) -> Bool {
        let normalized = icon.lowercased()
        return normalized.hasPrefix("mic")
            || normalized.hasPrefix("airpod")
            || normalized.hasPrefix("airpods")
            || normalized == "laptopcomputer"
            || normalized == "headphones"
    }

    private func hudLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 14, weight: .semibold))
            .foregroundColor(.white)
            .shadow(color: .black.opacity(0.2), radius: 1, x: 0, y: 1)
            .fixedSize()
    }

    private func actionBadge(symbol: String, tone: Color) -> some View {
        AnimatedHUDBadge(symbol: symbol, tone: tone, animatePulse: false)
    }
    
    // MARK: - Helper Types
    
    private static let symbolFallbacks: [String: [String]] = [
        "airpods.pro.left": ["airpod.gen3.left", "airpod.left", "airpods", "headphones"],
        "airpods.pro.right": ["airpod.gen3.right", "airpod.right", "airpods", "headphones"],
        "airpod.gen3.left": ["airpod.left", "airpods", "headphones"],
        "airpod.gen3.right": ["airpod.right", "airpods", "headphones"],
        "airpod.gen3": ["airpods", "headphones"],
        "airpods.pro": ["airpods", "headphones"],
        "airpods.max": ["headphones"],
        "airpodsmax": ["airpods.max", "headphones"],
        "airpodspro": ["airpods.pro", "airpods", "headphones"]
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

    private func requestedAppBundleID(for requested: String) -> String? {
        let prefix = "app-bundle:"
        guard requested.hasPrefix(prefix) else { return nil }
        let bundleID = String(requested.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
        return bundleID.isEmpty ? nil : bundleID
    }

    private func appIcon(for bundleID: String) -> NSImage? {
        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        let icon = NSWorkspace.shared.icon(forFile: appURL.path)
        icon.size = NSSize(width: 18, height: 18)
        return icon
    }

    private func isWeChatBundleID(_ bundleID: String) -> Bool {
        let lowercased = bundleID.lowercased()
        return lowercased.contains("xinwechat") || lowercased.contains("wechat")
    }

    private func isValidSymbol(_ name: String) -> Bool {
        NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil
    }

    private var contextIcon: some View {
        if let bundleID = requestedAppBundleID(for: state.contextIcon),
           isWeChatBundleID(bundleID) {
            return AnyView(
                Image("WeChatModeIcon")
                    .renderingMode(.template) // use HUD tint, not WeChat green
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 18, height: 18)
                    .foregroundColor(.white.opacity(0.84))
                    .shadow(radius: 1)
            )
        }

        if let bundleID = requestedAppBundleID(for: state.contextIcon),
           let icon = appIcon(for: bundleID) {
            return AnyView(
                ZStack {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.white.opacity(0.10))
                        .frame(width: 20, height: 20)
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                        .frame(width: 20, height: 20)
                    Image(nsImage: icon)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: 14, height: 14)
                        .saturation(0)
                        .brightness(0.06)
                        .contrast(1.05)
                        .opacity(0.9)
                        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                }
                .shadow(radius: 1)
            )
        }

        let symbol: String
        switch state.recognitionControlMode {
        case .command:
            symbol = "command"
        case .dictation:
            symbol = "keyboard"
        case .auto:
            symbol = state.isTypingContext ? "keyboard" : "command"
        }

        return AnyView(
            Image(systemName: symbol)
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.8))
                .shadow(radius: 1)
        )
    }

    private var displayLanguage: String {
        shortLanguageLabel(for: state.language)
    }

    private func shortLanguageLabel(for identifier: String) -> String {
        let normalized = identifier.replacingOccurrences(of: "_", with: "-").lowercased()
        if normalized.contains("hant") { return "繁" }
        if normalized.hasPrefix("zh") { return "中" }
        if normalized.hasPrefix("en") { return "En" }
        if normalized.hasPrefix("ja") { return "日" }
        if normalized.hasPrefix("ko") { return "한" }
        if normalized.hasPrefix("fr") { return "Fr" }
        if normalized.hasPrefix("de") { return "De" }
        if normalized.hasPrefix("es") { return "Es" }
        return String(identifier.prefix(2)).capitalized
    }

    private func languageToggle(showDivider: Bool) -> some View {
        HStack(spacing: 8) {
            if showDivider {
                Divider()
                    .frame(height: 16)
                    .background(Color.white.opacity(0.3))
            }

            Button(action: {
                let defaults = UserDefaults.standard
                let inputEnabled = defaults.object(forKey: "isVoiceInputEnabled") as? Bool
                let controlEnabled = defaults.object(forKey: "isVoiceControlEnabled") as? Bool
                let anyVoiceEnabled = inputEnabled == true || controlEnabled == true ||
                    (defaults.object(forKey: "isVoiceEnabled") as? Bool ?? true)
                guard anyVoiceEnabled else { return }
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

private struct GestureTrailView: View {
    let points: [HUDState.GestureTrailPoint]

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.white.opacity(0.06))
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.white.opacity(0.1), lineWidth: 1)

                Path { path in
                    guard let first = points.first else { return }
                    let mappedFirst = map(first, in: proxy.size)
                    path.move(to: mappedFirst)
                    for point in points.dropFirst() {
                        path.addLine(to: map(point, in: proxy.size))
                    }
                }
                .stroke(
                    LinearGradient(
                        colors: [Color.green.opacity(0.95), Color.cyan.opacity(0.85)],
                        startPoint: .leading,
                        endPoint: .trailing
                    ),
                    style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round)
                )

                if let first = points.first {
                    Circle()
                        .fill(Color.white.opacity(0.95))
                        .frame(width: 6, height: 6)
                        .position(map(first, in: proxy.size))
                }
                if let last = points.last {
                    Circle()
                        .fill(Color.green.opacity(0.95))
                        .frame(width: 7, height: 7)
                        .shadow(color: .green.opacity(0.4), radius: 4)
                        .position(map(last, in: proxy.size))
                }
            }
        }
    }

    private func map(_ point: HUDState.GestureTrailPoint, in size: CGSize) -> CGPoint {
        let x = 10 + point.x * max(size.width - 20, 1)
        let y = 10 + point.y * max(size.height - 20, 1)
        return CGPoint(x: x, y: y)
    }
}

private struct StandbyDotView: View {
    @State private var isBreathing = false

    var body: some View {
        Circle()
            .fill(Color.green.opacity(0.88))
            .frame(width: 8, height: 8)
            .scaleEffect(isBreathing ? 1.18 : 0.92)
            .opacity(isBreathing ? 0.95 : 0.74)
            .shadow(color: .green.opacity(0.45), radius: 4)
            .animation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true), value: isBreathing)
            .onAppear { isBreathing = true }
    }
}

private struct AudioReactiveRingView: View {
    let level: CGFloat

    var body: some View {
        let clamped = max(0.12, min(level, 1.0))
        Circle()
            .stroke(Color.green.opacity(0.42), lineWidth: 1.6)
            .frame(width: 24 + clamped * 8, height: 24 + clamped * 8)
            .animation(.easeOut(duration: 0.14), value: clamped)
    }
}

private struct ProcessingDotsView: View {
    let tone: Color
    @State private var activeIndex = 0

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(tone.opacity(activeIndex == index ? 0.95 : 0.42))
                    .frame(width: activeIndex == index ? 5.5 : 4.5, height: activeIndex == index ? 5.5 : 4.5)
            }
        }
        .frame(width: 24, height: 14)
        .animation(.easeInOut(duration: 0.18), value: activeIndex)
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 220_000_000)
                await MainActor.run {
                    activeIndex = (activeIndex + 1) % 3
                }
            }
        }
    }
}

private struct AnimatedHUDBadge: View {
    let symbol: String
    let tone: Color
    let animatePulse: Bool
    @State private var pulseVisible = false

    var body: some View {
        ZStack {
            if animatePulse {
                Circle()
                    .stroke(tone.opacity(0.45), lineWidth: 1.5)
                    .frame(width: 28, height: 28)
                    .scaleEffect(pulseVisible ? 1.55 : 1.05)
                    .opacity(pulseVisible ? 0.0 : 0.88)
                    .animation(.easeOut(duration: 0.55).repeatForever(autoreverses: false), value: pulseVisible)
            }

            Circle()
                .fill(tone.opacity(0.18))
                .frame(width: 24, height: 24)

            Circle()
                .stroke(tone.opacity(0.38), lineWidth: 1.1)
                .frame(width: 24, height: 24)

            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.white)
                .shadow(radius: 1)
        }
        .frame(width: 28, height: 28)
        .onAppear {
            guard animatePulse else { return }
            pulseVisible = true
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
