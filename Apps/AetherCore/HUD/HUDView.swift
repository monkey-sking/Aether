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

                case .listening, .command, .dictation, .organizing, .typing, .executing, .checking, .processing:
                    listeningLeadingVisual
                    compactSpeechLane
                    trailingAccessories

                case .optimizing:
                    optimizingLeadingVisual
                    if trimmedMessage.isEmpty {
                        OptimizingProgressView()
                    } else {
                        hudLabel(trimmedMessage)
                    }
                    trailingAccessories

                case .dragging:
                    actionBadge(symbol: "hand.draw.fill", tone: .white)
                    hudLabel(NSLocalizedString("speech.dragging", comment: ""))
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
        .padding(.horizontal, state.mode == .standby ? 8 : (isTwoStateSpeechMode ? 8 : 16))
        .padding(.vertical, state.mode == .standby ? 8 : (isTwoStateSpeechMode ? 7 : 10))
        .background(
            VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
        )
        .clipShape(RoundedRectangle(cornerRadius: hudContainerCornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: hudContainerCornerRadius, style: .continuous)
                .stroke(Color.white.opacity(0.06), lineWidth: 0.8)
        )
        .shadow(color: Color.black.opacity(0.12), radius: 6, x: 0, y: 3)
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

    private var compactSpeechLane: some View {
        TwoStateSpeechLaneView(
            text: trimmedMessage,
            level: state.audioLevel,
            barsWidth: compactSpeechBarsWidth,
            textWidth: compactSpeechTextWidth
        )
    }

    private var isTwoStateSpeechMode: Bool {
        switch state.mode {
        case .listening, .command, .dictation, .organizing, .typing, .executing, .checking, .processing:
            return true
        default:
            return false
        }
    }

    private var micIcon: some View {
        let requestedIcon = state.inputDeviceIcon
        let resolvedSymbol = resolvedSymbolName(for: requestedIcon)
        return ZStack {
            ZStack {
                if state.isMicProgressVisible && (state.mode == .listening || state.mode == .command || state.mode == .dictation) {
                    Circle()
                        .stroke(Color.white.opacity(0.22), lineWidth: 2)
                        .frame(width: deviceGlyphMetrics.progressDiameter, height: deviceGlyphMetrics.progressDiameter)
                    Circle()
                        .trim(from: 0, to: state.micProgress)
                        .stroke(
                            Color.green.opacity(0.9),
                            style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)
                        )
                        .rotationEffect(.degrees(-90))
                        .frame(width: deviceGlyphMetrics.progressDiameter, height: deviceGlyphMetrics.progressDiameter)
                }

                Image(systemName: resolvedSymbol)
                    .foregroundColor(.white)
                    .font(.system(size: deviceGlyphMetrics.listeningSymbolFontSize))
                    .offset(y: deviceGlyphMetrics.listeningSymbolYOffset)
                    .shadow(radius: 1)
            }
        }
        .frame(width: deviceGlyphMetrics.deviceFrameDiameter, height: deviceGlyphMetrics.deviceFrameDiameter)
    }

    private var listeningLeadingVisual: some View {
        decoratedDeviceLeadingVisual {
            AudioReactiveRingView(
                level: state.audioLevel,
                baseDiameter: deviceGlyphMetrics.ringBaseDiameter,
                expansion: deviceGlyphMetrics.ringExpansion,
                lineWidth: deviceGlyphMetrics.ringStrokeWidth,
                isCalmed: state.isPositionAnimating
            )
            micIcon
        }
    }

    private var stageLeadingVisual: some View {
        decoratedDeviceLeadingVisual {
            AnimatedHUDBadge(
                symbol: currentInputDeviceSymbol,
                tone: .white.opacity(0.92),
                animatePulse: false,
                circleDiameter: deviceGlyphMetrics.stageCircleDiameter,
                frameDiameter: leadingVisualFrameDiameter,
                symbolFontSize: deviceGlyphMetrics.stageSymbolFontSize,
                symbolYOffset: deviceGlyphMetrics.stageSymbolYOffset
            )
        }
    }

    private var optimizingLeadingVisual: some View {
        semanticLeadingVisual(symbol: "wand.and.stars", tone: .mint)
    }

    @ViewBuilder
    private var feedbackLeadingVisual: some View {
        switch feedbackLeadingStrategy {
        case .device:
            decoratedDeviceLeadingVisual(
                outcomeSymbol: feedbackOutcomeSymbol,
                outcomeTone: feedbackTone,
                outcomeStyle: feedbackBadgeStyle
            ) {
                AnimatedHUDBadge(
                    symbol: currentInputDeviceSymbol,
                    tone: .white.opacity(0.92),
                    animatePulse: false,
                    circleDiameter: deviceGlyphMetrics.stageCircleDiameter,
                    frameDiameter: leadingVisualFrameDiameter,
                    symbolFontSize: deviceGlyphMetrics.stageSymbolFontSize,
                    symbolYOffset: deviceGlyphMetrics.stageSymbolYOffset
                )
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

    private struct DeviceGlyphMetrics {
        let deviceFrameDiameter: CGFloat
        let progressDiameter: CGFloat
        let listeningSymbolFontSize: CGFloat
        let listeningSymbolYOffset: CGFloat
        let stageCircleDiameter: CGFloat
        let stageSymbolFontSize: CGFloat
        let stageSymbolYOffset: CGFloat
        let ringBaseDiameter: CGFloat
        let ringExpansion: CGFloat
        let ringStrokeWidth: CGFloat
    }

    private var deviceGlyphMetrics: DeviceGlyphMetrics {
        metrics(for: currentInputDeviceSymbol)
    }

    private var overlayBadgeTopOffset: CGFloat {
        1.0
    }

    private var overlayBadgeBottomOffset: CGFloat {
        -1.0
    }

    private var overlayBadgeDiameter: CGFloat {
        13.5
    }

    private var leadingVisualFrameDiameter: CGFloat {
        30
    }

    private var hudContainerCornerRadius: CGFloat {
        if state.mode == .standby {
            return 16
        }
        return isTwoStateSpeechMode ? 22 : 24
    }

    private var compactSpeechBarsWidth: CGFloat {
        30
    }

    private var compactSpeechTextWidth: CGFloat {
        var width: CGFloat = 104
        if hasVisibleContextIcon { width -= 18 }
        if state.isLanguageIndicatorVisible { width -= 22 }
        return max(width, 72)
    }

    private var primaryBadgeCircleDiameter: CGFloat {
        27
    }

    private var primaryBadgeSymbolFontSize: CGFloat {
        15
    }

    private func metrics(for symbol: String) -> DeviceGlyphMetrics {
        let normalized = symbol.lowercased()

        if normalized == "airpods.max" {
            return DeviceGlyphMetrics(
                deviceFrameDiameter: 27,
                progressDiameter: 27,
                listeningSymbolFontSize: 17.8,
                listeningSymbolYOffset: 0.2,
                stageCircleDiameter: primaryBadgeCircleDiameter,
                stageSymbolFontSize: 15.2,
                stageSymbolYOffset: 0.2,
                ringBaseDiameter: 25.8,
                ringExpansion: 4.0,
                ringStrokeWidth: 1.25
            )
        }

        if normalized.contains("airpod") || normalized.contains("airpods") {
            return DeviceGlyphMetrics(
                deviceFrameDiameter: 27,
                progressDiameter: 27,
                listeningSymbolFontSize: 18.2,
                listeningSymbolYOffset: 0.15,
                stageCircleDiameter: primaryBadgeCircleDiameter,
                stageSymbolFontSize: 15.4,
                stageSymbolYOffset: 0.15,
                ringBaseDiameter: 25.8,
                ringExpansion: 4.0,
                ringStrokeWidth: 1.25
            )
        }

        if normalized.contains("headphones") {
            return DeviceGlyphMetrics(
                deviceFrameDiameter: 27,
                progressDiameter: 27,
                listeningSymbolFontSize: 18.0,
                listeningSymbolYOffset: 0.05,
                stageCircleDiameter: primaryBadgeCircleDiameter,
                stageSymbolFontSize: 15.2,
                stageSymbolYOffset: 0.05,
                ringBaseDiameter: 25.9,
                ringExpansion: 4.1,
                ringStrokeWidth: 1.25
            )
        }

        if normalized.contains("mic.slash") {
            return DeviceGlyphMetrics(
                deviceFrameDiameter: 27,
                progressDiameter: 27,
                listeningSymbolFontSize: 16.7,
                listeningSymbolYOffset: 0,
                stageCircleDiameter: primaryBadgeCircleDiameter,
                stageSymbolFontSize: 14.6,
                stageSymbolYOffset: 0,
                ringBaseDiameter: 25.7,
                ringExpansion: 4.0,
                ringStrokeWidth: 1.25
            )
        }

        return DeviceGlyphMetrics(
            deviceFrameDiameter: 27,
            progressDiameter: 27,
            listeningSymbolFontSize: 17.2,
            listeningSymbolYOffset: 0,
            stageCircleDiameter: primaryBadgeCircleDiameter,
            stageSymbolFontSize: 14.8,
            stageSymbolYOffset: 0,
            ringBaseDiameter: 25.8,
            ringExpansion: 4.2,
            ringStrokeWidth: 1.3
        )
    }

    @ViewBuilder
    private func decoratedDeviceLeadingVisual<Content: View>(
        outcomeSymbol: String? = nil,
        outcomeTone: Color = .white,
        outcomeStyle: OutcomeOverlayBadge.Style = .neutral,
        @ViewBuilder content: () -> Content
    ) -> some View {
        ZStack {
            content()
        }
        .frame(width: leadingVisualFrameDiameter, height: leadingVisualFrameDiameter)
        .overlay(alignment: .topLeading) {
            if let healthStyle = deviceHealthStyle {
                DeviceHealthBadge(style: healthStyle, size: overlayBadgeDiameter)
                    .offset(x: overlayBadgeTopOffset, y: overlayBadgeTopOffset)
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if let outcomeSymbol {
                OutcomeOverlayBadge(
                    symbol: outcomeSymbol,
                    tone: outcomeTone,
                    style: outcomeStyle,
                    size: overlayBadgeDiameter
                )
                .offset(x: overlayBadgeBottomOffset, y: overlayBadgeBottomOffset)
            } else if let symbol = modeIndicatorSymbol {
                ModeIndicatorBadge(symbol: symbol, size: overlayBadgeDiameter)
                    .offset(x: overlayBadgeBottomOffset, y: overlayBadgeBottomOffset)
            }
        }
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
            "Rewrite done",
            "No changes",
            "优化完成",
            "无需修改"
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
            AppLocalization.isChinese ? "正在优化，请稍候" : "Optimizing. Please wait.",
            AppLocalization.isChinese ? "已切到Mac麦" : "Switched to Mac mic"
        ]
    }

    private var infoFeedbackMessages: Set<String> {
        [
            AppLocalization.isChinese ? "耳机已断开" : "Headset disconnected",
            AppLocalization.isChinese ? "耳机已连接" : "Headset connected"
        ]
    }

    private func looksLikeWarningFeedback(_ message: String) -> Bool {
        let lowercased = message.lowercased()
        if AppLocalization.isChinese {
            return message.contains("不可用")
                || message.contains("请稍候")
                || message.contains("干扰")
                || message.contains("Mac麦")
        }
        return lowercased.contains("please wait")
            || lowercased.contains("interference")
            || lowercased.contains("switched to mac mic")
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
        AnimatedHUDBadge(
            symbol: symbol,
            tone: tone.opacity(0.95),
            animatePulse: false,
            circleDiameter: primaryBadgeCircleDiameter,
            frameDiameter: leadingVisualFrameDiameter,
            symbolFontSize: primaryBadgeSymbolFontSize
        )
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
            .lineLimit(1)
            .truncationMode(.tail)
            .minimumScaleFactor(0.92)
            .frame(maxWidth: hudLabelMaxWidth, alignment: .leading)
            .layoutPriority(1)
    }

    private var hudLabelMaxWidth: CGFloat {
        var width: CGFloat = state.mode == .feedback ? 252 : 232
        if hasVisibleContextIcon { width -= 20 }
        if state.isLanguageIndicatorVisible { width -= 24 }
        return max(width, 132)
    }

    private func actionBadge(symbol: String, tone: Color) -> some View {
        AnimatedHUDBadge(
            symbol: symbol,
            tone: tone,
            animatePulse: false,
            circleDiameter: primaryBadgeCircleDiameter,
            frameDiameter: leadingVisualFrameDiameter,
            symbolFontSize: primaryBadgeSymbolFontSize
        )
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
                    RoundedRectangle(cornerRadius: 7.5, style: .continuous)
                        .fill(Color.white.opacity(0.10))
                        .frame(width: 20, height: 20)
                    RoundedRectangle(cornerRadius: 7.5, style: .continuous)
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
                        .clipShape(RoundedRectangle(cornerRadius: 5.5, style: .continuous))
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
    let baseDiameter: CGFloat
    let expansion: CGFloat
    let lineWidth: CGFloat
    let isCalmed: Bool
    @State private var displayedLevel: CGFloat = 0.18

    var body: some View {
        let clamped = max(0.12, min(level, 1.0))
        let targetLevel = isCalmed ? min(clamped, 0.42) : clamped
        let effectiveExpansion = isCalmed ? expansion * 0.42 : expansion
        Circle()
            .stroke(Color.green.opacity(isCalmed ? 0.32 : 0.4), lineWidth: isCalmed ? max(1.15, lineWidth - 0.1) : lineWidth)
            .frame(
                width: baseDiameter + displayedLevel * effectiveExpansion,
                height: baseDiameter + displayedLevel * effectiveExpansion
            )
            .animation(.easeOut(duration: isCalmed ? 0.24 : 0.2), value: displayedLevel)
            .onAppear {
                displayedLevel = targetLevel
            }
            .onChange(of: targetLevel) { newValue in
                let blend: CGFloat = isCalmed ? 0.24 : 0.46
                displayedLevel = displayedLevel * (1 - blend) + newValue * blend
            }
            .onChange(of: isCalmed) { calmed in
                if calmed {
                    displayedLevel = min(displayedLevel, 0.42)
                }
            }
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

private struct TextOrganizingView: View {
    @State private var activeIndex = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 3.5) {
            ForEach(0..<3, id: \.self) { index in
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(activeIndex == index ? Color.white.opacity(0.92) : Color.white.opacity(0.36))
                    .frame(
                        width: lineWidth(for: index),
                        height: activeIndex == index ? 4 : 3
                    )
            }
        }
        .frame(width: 32, height: 18, alignment: .leading)
        .animation(.easeInOut(duration: 0.2), value: activeIndex)
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 260_000_000)
                await MainActor.run {
                    activeIndex = (activeIndex + 1) % 3
                }
            }
        }
    }

    private func lineWidth(for index: Int) -> CGFloat {
        let baseWidths: [CGFloat] = [30, 22, 27]
        if activeIndex == index {
            return baseWidths[index] + 2
        }
        return baseWidths[index]
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

private struct TwoStateSpeechLaneView: View {
    let text: String
    let level: CGFloat
    let barsWidth: CGFloat
    let textWidth: CGFloat

    @State private var phase: CGFloat = 0

    var body: some View {
        Group {
            if text.isEmpty {
                HStack(alignment: .center, spacing: 3) {
                    ForEach(0..<3, id: \.self) { index in
                        RoundedRectangle(cornerRadius: 1.6, style: .continuous)
                            .fill(Color.white.opacity(barOpacity(for: index)))
                            .frame(width: 2.8, height: barHeight(for: index))
                            .shadow(color: Color.white.opacity(0.12), radius: 1.2)
                    }
                }
                .frame(width: barsWidth, height: 18, alignment: .leading)
            } else {
                Text(text)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white.opacity(0.98))
                    .shadow(color: .black.opacity(0.2), radius: 1, x: 0, y: 1)
                    .lineLimit(1)
                    .truncationMode(.head)
                    .minimumScaleFactor(0.92)
                    .frame(width: textWidth, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .animation(.easeInOut(duration: 0.16), value: phase)
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 180_000_000)
                await MainActor.run {
                    phase += 1
                }
            }
        }
    }

    private func barOpacity(for index: Int) -> Double {
        let boosted = max(0.14, min(level, 1.0))
        let phaseOffset = sin((phase + CGFloat(index) * 0.75) * 1.05)
        let wave = max(0, 0.5 + phaseOffset * 0.5)
        let emphasis: Double = index == 1 ? 1.0 : 0.88
        return min(0.96, (0.34 + Double(boosted) * 0.42 + Double(wave) * 0.16) * emphasis)
    }

    private func barHeight(for index: Int) -> CGFloat {
        let baseHeights: [CGFloat] = [7, 13, 9]
        let boosted = max(0.14, min(level, 1.0))
        let phaseOffset = sin((phase + CGFloat(index) * 0.78) * 1.1)
        let wave = max(0, 0.5 + phaseOffset * 0.5)
        let effective = max(0.36, boosted * 0.74 + wave * 0.3)
        let minHeight: CGFloat = 4
        return minHeight + (baseHeights[index] - minHeight) * min(effective, 1.0)
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
    let circleDiameter: CGFloat
    let frameDiameter: CGFloat
    let symbolFontSize: CGFloat
    let symbolYOffset: CGFloat
    @State private var pulseVisible = false

    init(
        symbol: String,
        tone: Color,
        animatePulse: Bool,
        circleDiameter: CGFloat = 24,
        frameDiameter: CGFloat = 28,
        symbolFontSize: CGFloat = 13,
        symbolYOffset: CGFloat = 0
    ) {
        self.symbol = symbol
        self.tone = tone
        self.animatePulse = animatePulse
        self.circleDiameter = circleDiameter
        self.frameDiameter = frameDiameter
        self.symbolFontSize = symbolFontSize
        self.symbolYOffset = symbolYOffset
    }

    var body: some View {
        ZStack {
            if animatePulse {
                Circle()
                    .stroke(tone.opacity(0.45), lineWidth: 1.5)
                    .frame(width: frameDiameter, height: frameDiameter)
                    .scaleEffect(pulseVisible ? 1.55 : 1.05)
                    .opacity(pulseVisible ? 0.0 : 0.88)
                    .animation(.easeOut(duration: 0.55).repeatForever(autoreverses: false), value: pulseVisible)
            }

            Circle()
                .fill(tone.opacity(0.18))
                .frame(width: circleDiameter, height: circleDiameter)

            Circle()
                .stroke(tone.opacity(0.38), lineWidth: 1.1)
                .frame(width: circleDiameter, height: circleDiameter)

            Image(systemName: symbol)
                .font(.system(size: symbolFontSize, weight: .semibold))
                .foregroundColor(.white)
                .offset(y: symbolYOffset)
                .shadow(radius: 1)
        }
        .frame(width: frameDiameter, height: frameDiameter)
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
    let size: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .fill(backgroundColor)
                .frame(width: size, height: size)
            Circle()
                .stroke(borderColor, lineWidth: 1)
                .frame(width: size, height: size)
            Image(systemName: symbol)
                .font(.system(size: size * 0.54, weight: .bold))
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
    let size: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.white.opacity(0.14))
                .frame(width: size, height: size)
            Circle()
                .stroke(Color.white.opacity(0.16), lineWidth: 1)
                .frame(width: size, height: size)
            Image(systemName: symbol)
                .font(.system(size: modeFontSize, weight: .semibold))
                .foregroundColor(.white.opacity(0.92))
        }
    }

    private var modeFontSize: CGFloat {
        switch symbol {
        case "command":
            return size * 0.51
        case "character.cursor.ibeam":
            return size * 0.47
        default:
            return size * 0.51
        }
    }
}

private struct DeviceHealthBadge: View {
    let style: HUDView.DeviceHealthBadgeStyle
    let size: CGFloat
    @State private var pulse = false

    var body: some View {
        ZStack {
            if style == .limited {
                Circle()
                    .stroke(tone.opacity(0.34), lineWidth: 1)
                    .frame(width: size, height: size)
                    .scaleEffect(pulse ? 1.45 : 1.0)
                    .opacity(pulse ? 0.0 : 0.75)
            }

            Circle()
                .fill(backgroundColor)
                .frame(width: size, height: size)

            switch style {
            case .warning:
                Circle()
                    .stroke(borderColor, lineWidth: 1)
                    .frame(width: size, height: size)
                Circle()
                    .fill(tone)
                    .frame(width: size * 0.4, height: size * 0.4)
            case .limited:
                Circle()
                    .stroke(borderColor, lineWidth: 1)
                    .frame(width: size, height: size)
                RoundedRectangle(cornerRadius: 1, style: .continuous)
                    .fill(tone)
                    .frame(width: size * 0.46, height: max(2, size * 0.15))
            case .error:
                Circle()
                    .stroke(borderColor, lineWidth: 1)
                    .frame(width: size, height: size)
                Image(systemName: "xmark")
                    .font(.system(size: size * 0.47, weight: .bold))
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
