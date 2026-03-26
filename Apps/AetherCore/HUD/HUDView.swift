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
                    StandbyDotView(health: state.inputDeviceHealth)
                    if state.isLanguageIndicatorVisible {
                        languageToggle(showDivider: false)
                    }

                case .listening:
                    listeningLeadingVisual
                    if !trimmedMessage.isEmpty {
                        hudLabel(trimmedMessage)
                    }
                    trailingAccessories

                case .command:
                    listeningLeadingVisual
                    if !trimmedMessage.isEmpty {
                        hudLabel(trimmedMessage)
                    }
                    trailingAccessories

                case .dictation:
                    listeningLeadingVisual
                    if trimmedMessage.isEmpty {
                        WaveformView(level: state.audioLevel)
                    } else {
                        hudLabel(trimmedMessage)
                    }
                    trailingAccessories

                case .organizing:
                    stageLeadingVisual
                    if trimmedMessage.isEmpty {
                        TextOrganizingView()
                    } else {
                        hudLabel(trimmedMessage)
                    }
                    trailingAccessories

                case .typing:
                    stageLeadingVisual
                    if trimmedMessage.isEmpty {
                        TypingProgressView()
                    } else {
                        hudLabel(trimmedMessage)
                    }
                    trailingAccessories

                case .executing:
                    stageLeadingVisual
                    if trimmedMessage.isEmpty {
                        ExecutingPulseView()
                    } else {
                        hudLabel(trimmedMessage)
                    }
                    trailingAccessories

                case .optimizing:
                    optimizingLeadingVisual
                    if trimmedMessage.isEmpty {
                        OptimizingProgressView()
                    } else {
                        hudLabel(trimmedMessage)
                    }
                    trailingAccessories

                case .checking:
                    stageLeadingVisual
                    if trimmedMessage.isEmpty {
                        CheckingProgressView()
                    } else {
                        hudLabel(trimmedMessage)
                    }
                    trailingAccessories

                case .dragging:
                    actionBadge(symbol: "hand.draw.fill", tone: .white)
                    hudLabel(NSLocalizedString("speech.dragging", comment: ""))
                    trailingAccessories

                case .processing:
                    stageLeadingVisual
                    if !trimmedMessage.isEmpty {
                        hudLabel(trimmedMessage)
                    } else {
                        GenericProcessingView()
                    }
                    trailingAccessories

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
        }
        .frame(width: 22, height: 22)
        .overlay(alignment: .topLeading) {
            if let healthStyle = deviceHealthStyle {
                DeviceHealthBadge(style: healthStyle)
                    .offset(x: -4, y: -4)
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if let symbol = modeIndicatorSymbol {
                ModeIndicatorBadge(symbol: symbol, compact: prefersCompactModeIndicator)
                    .offset(x: prefersCompactModeIndicator ? 6 : 5, y: prefersCompactModeIndicator ? 6 : 5)
            }
        }
    }

    private var listeningLeadingVisual: some View {
        ZStack {
            AudioReactiveRingView(level: state.audioLevel)
            micIcon
        }
        .frame(width: 28, height: 28)
    }

    private var stageLeadingVisual: some View {
        ZStack {
            AnimatedHUDBadge(
                symbol: currentInputDeviceSymbol,
                tone: .white.opacity(0.92),
                animatePulse: false
            )
        }
        .overlay(alignment: .topLeading) {
            if let healthStyle = deviceHealthStyle {
                DeviceHealthBadge(style: healthStyle)
                    .offset(x: -4, y: -4)
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if let symbol = modeIndicatorSymbol {
                ModeIndicatorBadge(symbol: symbol, compact: prefersCompactModeIndicator)
                    .offset(x: prefersCompactModeIndicator ? 6 : 5, y: prefersCompactModeIndicator ? 6 : 5)
            }
        }
    }

    private var optimizingLeadingVisual: some View {
        semanticLeadingVisual(symbol: "wand.and.stars", tone: .mint)
    }

    @ViewBuilder
    private var feedbackLeadingVisual: some View {
        switch feedbackLeadingStrategy {
        case .device:
            ZStack {
                AnimatedHUDBadge(
                    symbol: currentInputDeviceSymbol,
                    tone: .white.opacity(0.92),
                    animatePulse: false
                )
                if let healthStyle = deviceHealthStyle {
                    DeviceHealthBadge(style: healthStyle)
                        .offset(x: -7, y: -7)
                }
                if let feedbackOutcomeSymbol {
                    OutcomeOverlayBadge(
                        symbol: feedbackOutcomeSymbol,
                        tone: feedbackTone,
                        style: feedbackBadgeStyle
                    )
                        .offset(x: 4, y: 4)
                }
            }
        case .wakeSuccess:
            semanticLeadingVisual(symbol: "waveform", tone: .green)
        case .warning:
            semanticLeadingVisual(symbol: "exclamationmark.triangle.fill", tone: .orange)
        case .error:
            semanticLeadingVisual(symbol: "xmark.circle.fill", tone: .red)
        }
    }

    private enum FeedbackLeadingStrategy {
        case device
        case wakeSuccess
        case warning
        case error
    }

    private var currentInputDeviceSymbol: String {
        resolvedSymbolName(for: state.inputDeviceIcon)
    }

    private var prefersCompactModeIndicator: Bool {
        let symbol = currentInputDeviceSymbol
        return symbol.contains("airpod") || symbol.contains("airpods")
    }

    private var modeIndicatorSymbol: String? {
        switch state.recognitionControlMode {
        case .command:
            return "command"
        case .dictation:
            return "character.cursor.ibeam"
        case .auto:
            return state.isTypingContext ? "character.cursor.ibeam" : "command"
        }
    }

    private enum FeedbackKind {
        case neutral
        case info
        case success
        case warning
        case error
    }

    private var feedbackKind: FeedbackKind {
        guard !trimmedMessage.isEmpty else { return .neutral }
        if compactFeedbackMessages.contains(trimmedMessage) {
            return .success
        }
        if warningFeedbackMessages.contains(trimmedMessage) || looksLikeWarningFeedback(trimmedMessage) {
            return .warning
        }
        if errorFeedbackMessages.contains(trimmedMessage) || looksLikeErrorFeedback(trimmedMessage) {
            return .error
        }
        if infoFeedbackMessages.contains(trimmedMessage) || looksLikeInfoFeedback(trimmedMessage) {
            return .info
        }
        return .info
    }

    private var feedbackLeadingStrategy: FeedbackLeadingStrategy {
        if trimmedMessage.isEmpty {
            return .wakeSuccess
        }
        switch feedbackKind {
        case .warning:
            return .warning
        case .error:
            return .error
        case .neutral, .info, .success:
            return .device
        }
    }

    private var feedbackOutcomeSymbol: String? {
        switch feedbackKind {
        case .neutral:
            return nil
        case .info:
            return "info"
        case .success:
            return "checkmark"
        case .warning:
            return "exclamationmark"
        case .error:
            return "xmark"
        }
    }

    private var feedbackTone: Color {
        switch feedbackKind {
        case .neutral:
            return .white
        case .info:
            return .white
        case .success:
            return .green
        case .warning:
            return .orange
        case .error:
            return .red
        }
    }

    private var feedbackBadgeStyle: OutcomeOverlayBadge.Style {
        switch feedbackKind {
        case .success:
            return .positive
        case .warning:
            return .warning
        case .error:
            return .critical
        case .info, .neutral:
            return .neutral
        }
    }

    private var shouldShowFeedbackText: Bool {
        guard !trimmedMessage.isEmpty else { return false }
        return !compactFeedbackMessages.contains(trimmedMessage)
    }

    fileprivate enum DeviceHealthBadgeStyle {
        case warning
        case limited
        case error
    }

    private var deviceHealthStyle: DeviceHealthBadgeStyle? {
        switch state.inputDeviceHealth {
        case .normal:
            return nil
        case .warning:
            return .warning
        case .limited:
            return .limited
        case .error:
            return .error
        }
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

    private var errorFeedbackMessages: Set<String> {
        [
            NSLocalizedString("speech.no_matching_command", comment: ""),
            NSLocalizedString("speech.no_editable_field", comment: ""),
            NSLocalizedString("speech.no_mic_detected", comment: ""),
            NSLocalizedString("speech.need_mic_permission", comment: ""),
            NSLocalizedString("speech.need_recognition_permission", comment: ""),
            NSLocalizedString("speech.voice_input_disabled", comment: ""),
            NSLocalizedString("speech.voice_control_disabled", comment: ""),
            "没完成",
            "Didn't finish"
        ]
    }

    private var warningFeedbackMessages: Set<String> {
        [
            NSLocalizedString("speech.playback_leak.detected", comment: ""),
            NSLocalizedString("speech.playback_leak.suppression_active", comment: ""),
            AppLocalization.isChinese ? "正在优化全文，请稍候" : "A full-text rewrite is already running. Please wait.",
            AppLocalization.isChinese ? "耳机麦不可用，已切到 Mac 麦克风" : "Switched to Mac microphone"
        ]
    }

    private var infoFeedbackMessages: Set<String> {
        [
            AppLocalization.isChinese ? "耳机已断开" : "Headset disconnected"
        ]
    }

    private func looksLikeWarningFeedback(_ message: String) -> Bool {
        let lowercased = message.lowercased()
        if AppLocalization.isChinese {
            return message.contains("不可用")
                || message.contains("请稍候")
                || message.contains("干扰")
        }
        return lowercased.contains("please wait")
            || lowercased.contains("interference")
            || lowercased.contains("switched to mac microphone")
    }

    private func looksLikeErrorFeedback(_ message: String) -> Bool {
        let lowercased = message.lowercased()
        if AppLocalization.isChinese {
            return message.contains("失败")
                || message.contains("失效")
                || message.contains("不支持")
                || message.contains("未替换")
                || message.contains("没找到")
                || message.contains("为空")
                || message.contains("过长")
                || message.contains("关闭")
        }
        return lowercased.contains("failed")
            || lowercased.contains("not support")
            || lowercased.contains("no editable")
            || lowercased.contains("not replaced")
            || lowercased.contains("no longer valid")
            || lowercased.contains("is off")
            || lowercased.contains("too long")
            || lowercased.contains("is empty")
            || lowercased.contains("not configured")
            || lowercased.contains("turned off")
    }

    private func looksLikeInfoFeedback(_ message: String) -> Bool {
        let lowercased = message.lowercased()
        if AppLocalization.isChinese {
            return message.contains("已连接")
                || message.contains("已切到")
        }
        return lowercased.hasPrefix("connected:")
            || lowercased.hasPrefix("switched:")
            || lowercased.hasPrefix("switched to ")
    }

    private func semanticLeadingVisual(symbol: String, tone: Color) -> some View {
        AnimatedHUDBadge(symbol: symbol, tone: tone.opacity(0.95), animatePulse: false)
    }

    @ViewBuilder
    private var trailingAccessories: some View {
        if hasVisibleContextIcon {
            contextIcon
        }
        if state.isLanguageIndicatorVisible {
            languageToggle(showDivider: hasVisibleContextIcon)
        }
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

    private var hasVisibleContextIcon: Bool {
        guard let bundleID = requestedAppBundleID(for: state.contextIcon) else { return false }
        return isWeChatBundleID(bundleID) || appIcon(for: bundleID) != nil
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
        return AnyView(EmptyView())
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
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white.opacity(0.9))
                    .fixedSize()
                    .frame(minWidth: 22, alignment: .center)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1.5)
                    .background(
                        Capsule(style: .continuous)
                            .fill(Color.white.opacity(0.12))
                    )
                    .overlay(
                        Capsule(style: .continuous)
                            .stroke(Color.white.opacity(0.14), lineWidth: 1)
                    )
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
    let health: HUDInputDeviceHealth
    @State private var isBreathing = false

    var body: some View {
        Circle()
            .fill(dotColor.opacity(0.9))
            .frame(width: 8, height: 8)
            .overlay(
                Circle()
                    .stroke(dotColor.opacity(health == .normal ? 0.0 : 0.45), lineWidth: 1.2)
                    .scaleEffect(isBreathing ? 1.7 : 1.1)
                    .opacity(health == .normal ? 0.0 : (isBreathing ? 0.0 : 0.9))
            )
            .scaleEffect(isBreathing ? 1.16 : 0.94)
            .opacity(isBreathing ? 0.95 : 0.74)
            .shadow(color: dotColor.opacity(0.38), radius: 4)
            .animation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true), value: isBreathing)
            .onAppear { isBreathing = true }
    }

    private var dotColor: Color {
        switch health {
        case .normal:
            return .green
        case .warning:
            return Color.yellow
        case .limited:
            return .orange
        case .error:
            return .red
        }
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

private struct GenericProcessingView: View {
    var body: some View {
        HStack(spacing: 8) {
            TextOrganizingView()
            ProcessingDotsView(tone: .white.opacity(0.88))
        }
    }
}

private struct TextOrganizingView: View {
    @State private var activeIndex = 0

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3, id: \.self) { index in
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(Color.white.opacity(activeIndex == index ? 0.9 : 0.35))
                    .frame(
                        width: activeIndex == index ? 17 : 13,
                        height: activeIndex == index ? 4.5 : 3.5
                    )
            }
        }
        .frame(height: 16)
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

private struct TypingProgressView: View {
    @State private var cursorVisible = true

    var body: some View {
        HStack(spacing: 5) {
            HStack(spacing: 4) {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(Color.white.opacity(0.7))
                    .frame(width: 16, height: 4)
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(Color.white.opacity(0.45))
                    .frame(width: 12, height: 4)
            }
            Rectangle()
                .fill(Color.green.opacity(cursorVisible ? 0.92 : 0.28))
                .frame(width: 2, height: 14)
                .shadow(color: Color.green.opacity(0.35), radius: 2)
        }
        .frame(height: 18)
        .animation(.easeInOut(duration: 0.18), value: cursorVisible)
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 320_000_000)
                await MainActor.run {
                    cursorVisible.toggle()
                }
            }
        }
    }
}

private struct ExecutingPulseView: View {
    @State private var offset: CGFloat = -4

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "arrow.right")
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(.white.opacity(0.92))
                .offset(x: offset)
            ForEach(0..<2, id: \.self) { index in
                Circle()
                    .fill(Color.white.opacity(index == 0 ? 0.4 : 0.7))
                    .frame(width: index == 0 ? 4 : 5, height: index == 0 ? 4 : 5)
                    .offset(x: offset * 0.3)
            }
        }
        .frame(height: 18)
        .animation(.easeInOut(duration: 0.32).repeatForever(autoreverses: true), value: offset)
        .onAppear {
            offset = 4
        }
    }
}

private struct OptimizingProgressView: View {
    @State private var activeIndex = 0

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3, id: \.self) { index in
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(Color.mint.opacity(activeIndex == index ? 0.95 : 0.35))
                    .frame(
                        width: activeIndex == index ? 15 : 11,
                        height: activeIndex == index ? 4.5 : 3.5
                    )
            }
        }
        .frame(height: 16)
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

private struct CheckingProgressView: View {
    @State private var phase = false

    var body: some View {
        ZStack {
            Circle()
                .trim(from: 0.1, to: 0.78)
                .stroke(
                    Color.white.opacity(0.78),
                    style: StrokeStyle(lineWidth: 1.8, lineCap: .round)
                )
                .frame(width: 18, height: 18)
                .rotationEffect(.degrees(phase ? 320 : 40))
            Image(systemName: "checkmark")
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(.white.opacity(0.9))
        }
        .frame(width: 20, height: 20)
        .animation(.easeInOut(duration: 0.55).repeatForever(autoreverses: false), value: phase)
        .onAppear {
            phase = true
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

private struct OutcomeOverlayBadge: View {
    enum Style {
        case neutral
        case positive
        case warning
        case critical
    }

    let symbol: String
    let tone: Color
    let style: Style

    var body: some View {
        ZStack {
            Circle()
                .fill(backgroundColor)
                .frame(width: 14, height: 14)
            Circle()
                .stroke(borderColor, lineWidth: 1)
                .frame(width: 14, height: 14)
            Image(systemName: symbol)
                .font(.system(size: 7.5, weight: .bold))
                .foregroundColor(symbolColor)
        }
        .shadow(color: shadowColor, radius: style == .positive ? 4 : 0)
    }

    private var backgroundColor: Color {
        switch style {
        case .neutral:
            return Color.white.opacity(0.14)
        case .positive:
            return Color.green.opacity(0.28)
        case .warning:
            return Color.orange.opacity(0.2)
        case .critical:
            return Color.red.opacity(0.2)
        }
    }

    private var borderColor: Color {
        switch style {
        case .neutral:
            return Color.white.opacity(0.26)
        case .positive, .warning, .critical:
            return tone.opacity(0.82)
        }
    }

    private var symbolColor: Color {
        switch style {
        case .positive:
            return .white
        case .neutral, .warning, .critical:
            return tone
        }
    }

    private var shadowColor: Color {
        switch style {
        case .positive:
            return Color.green.opacity(0.24)
        case .neutral, .warning, .critical:
            return .clear
        }
    }
}

private struct ModeIndicatorBadge: View {
    let symbol: String
    let compact: Bool

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.white.opacity(0.14))
                .frame(width: badgeSize, height: badgeSize)
            Circle()
                .stroke(Color.white.opacity(0.16), lineWidth: 1)
                .frame(width: badgeSize, height: badgeSize)
            Image(systemName: symbol)
                .font(.system(size: modeFontSize, weight: .semibold))
                .foregroundColor(.white.opacity(0.92))
        }
    }

    private var badgeSize: CGFloat {
        compact ? 12 : 14
    }

    private var modeFontSize: CGFloat {
        switch symbol {
        case "command":
            return compact ? 6.4 : 7.2
        case "character.cursor.ibeam":
            return compact ? 5.9 : 6.6
        default:
            return compact ? 6.4 : 7.2
        }
    }
}

private struct DeviceHealthBadge: View {
    let style: HUDView.DeviceHealthBadgeStyle
    @State private var pulse = false

    var body: some View {
        ZStack {
            if style == .limited {
                Circle()
                    .stroke(tone.opacity(0.34), lineWidth: 1)
                    .frame(width: 14, height: 14)
                    .scaleEffect(pulse ? 1.45 : 1.0)
                    .opacity(pulse ? 0.0 : 0.75)
            }

            Circle()
                .fill(backgroundColor)
                .frame(width: 14, height: 14)

            switch style {
            case .warning:
                Circle()
                    .stroke(borderColor, lineWidth: 1)
                    .frame(width: 14, height: 14)
                Circle()
                    .fill(tone)
                    .frame(width: 5.5, height: 5.5)
            case .limited:
                Circle()
                    .stroke(borderColor, lineWidth: 1)
                    .frame(width: 14, height: 14)
                RoundedRectangle(cornerRadius: 1, style: .continuous)
                    .fill(tone)
                    .frame(width: 6.5, height: 2)
            case .error:
                Circle()
                    .stroke(borderColor, lineWidth: 1)
                    .frame(width: 14, height: 14)
                Image(systemName: "xmark")
                    .font(.system(size: 6.5, weight: .bold))
                    .foregroundColor(tone)
            }
        }
        .frame(width: 14, height: 14)
        .shadow(color: shadowColor, radius: shadowRadius)
        .onAppear {
            guard style == .limited else { return }
            pulse = true
        }
        .animation(
            style == .limited
                ? .easeInOut(duration: 2.4).repeatForever(autoreverses: false)
                : .default,
            value: pulse
        )
    }

    private var tone: Color {
        switch style {
        case .warning:
            return Color.yellow
        case .limited:
            return .orange
        case .error:
            return .red
        }
    }

    private var backgroundColor: Color {
        switch style {
        case .warning:
            return Color.yellow.opacity(0.16)
        case .limited:
            return Color.orange.opacity(0.18)
        case .error:
            return Color.red.opacity(0.18)
        }
    }

    private var borderColor: Color {
        tone.opacity(0.82)
    }

    private var shadowColor: Color {
        switch style {
        case .warning:
            return Color.yellow.opacity(0.12)
        case .limited:
            return Color.orange.opacity(0.18)
        case .error:
            return Color.red.opacity(0.14)
        }
    }

    private var shadowRadius: CGFloat {
        switch style {
        case .warning:
            return 0
        case .limited:
            return 3
        case .error:
            return 0
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
