import SwiftUI
import AppKit

// MARK: - Shared UI Components

enum AetherUI {
    static let cardCornerRadius: CGFloat = 22
    static let dashboardTileMinHeight: CGFloat = 214
    static let dashboardCompactTileMinHeight: CGFloat = 164
    static let sidebarIconSize: CGFloat = 16
    static let sidebarIconFrame: CGFloat = 22

    static let pageTitleFont = Font.system(size: 22, weight: .bold, design: .rounded)
    static let sectionHeaderFont = Font.system(size: 13, weight: .semibold, design: .rounded)
    static let sidebarItemFont = Font.system(size: 15, weight: .semibold, design: .rounded)
    static let cardTitleFont = Font.system(size: 17, weight: .semibold, design: .rounded)
    static let bodyFont = Font.system(size: 14, weight: .medium, design: .default)
    static let captionFont = Font.system(size: 12, weight: .medium, design: .default)
    static let captionStrongFont = Font.system(size: 12, weight: .semibold, design: .rounded)
    static let menuBrandFont = Font.system(size: 15, weight: .semibold, design: .rounded)
    static let menuHeadlineFont = Font.system(size: 14, weight: .semibold, design: .rounded)
}

struct NoFocusRingTextField: NSViewRepresentable {
    let placeholder: String
    @Binding var text: String
    @Binding var isFocused: Bool

    var font: NSFont = .systemFont(ofSize: 13, weight: .regular)

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: NoFocusRingTextField
        init(parent: NoFocusRingTextField) { self.parent = parent }

        func controlTextDidChange(_ obj: Notification) {
            guard let field = obj.object as? NSTextField else { return }
            if parent.text != field.stringValue {
                parent.text = field.stringValue
            }
        }

        func controlTextDidBeginEditing(_ obj: Notification) {
            if let field = obj.object as? NSTextField,
               let textView = field.currentEditor() as? NSTextView {
                textView.focusRingType = .none
                textView.enclosingScrollView?.focusRingType = .none
                textView.enclosingScrollView?.drawsBackground = false
                textView.drawsBackground = false
            }
            if !parent.isFocused { parent.isFocused = true }
        }

        func controlTextDidEndEditing(_ obj: Notification) {
            if parent.isFocused { parent.isFocused = false }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    private final class FocuslessTextField: NSTextField {
        override var focusRingType: NSFocusRingType {
            get { .none }
            set {}
        }
        override var focusRingMaskBounds: NSRect { .zero }
        override func drawFocusRingMask() {}
        override class var cellClass: AnyClass? {
            get { FocuslessTextFieldCell.self }
            set {}
        }
    }

    private final class FocuslessTextFieldCell: NSTextFieldCell {
        override var focusRingType: NSFocusRingType {
            get { .none }
            set {}
        }
        override func drawFocusRingMask(withFrame cellFrame: NSRect, in controlView: NSView) {}
    }

    func makeNSView(context: Context) -> NSTextField {
        let field = FocuslessTextField(string: text)
        field.placeholderString = placeholder
        field.isBezeled = false
        field.isBordered = false
        field.drawsBackground = false
        field.backgroundColor = .clear
        field.focusRingType = .none
        if let cell = field.cell as? NSTextFieldCell {
            cell.focusRingType = .none
            cell.isScrollable = true
            cell.drawsBackground = false
            cell.backgroundColor = .clear
        }
        field.font = font
        field.delegate = context.coordinator
        return field
    }

    func updateNSView(_ nsView: NSTextField, context: Context) {
        context.coordinator.parent = self
        if nsView.placeholderString != placeholder {
            nsView.placeholderString = placeholder
        }
        if nsView.stringValue != text {
            nsView.stringValue = text
        }
        if nsView.font != font {
            nsView.font = font
        }

        if let window = nsView.window {
            let isFirstResponder = (window.firstResponder as? NSView)?.isDescendant(of: nsView) == true || window.firstResponder === nsView
            if isFocused && !isFirstResponder {
                window.makeFirstResponder(nsView)
            } else if !isFocused && isFirstResponder {
                window.makeFirstResponder(nil)
            }
        }
    }
}

struct SuppressEnclosingScrollFocusRing: NSViewRepresentable {
    final class Coordinator {
        var didApply: Bool = false
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        applyFocusRingSuppression(from: nsView, coordinator: context.coordinator)
    }

    private func applyFocusRingSuppression(from view: NSView, coordinator: Coordinator) {
        // SwiftUI ScrollView on macOS uses an NSScrollView that can draw "corner brackets"
        // focus indicators. Force-disable the focus ring on the enclosing scroll view.
        guard let scroll = view.enclosingScrollView else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                self.applyFocusRingSuppression(from: view, coordinator: coordinator)
            }
            return
        }

        if coordinator.didApply {
            return
        }

        scroll.focusRingType = .none
        scroll.contentView.focusRingType = .none
        scroll.documentView?.focusRingType = .none
        scroll.borderType = .noBorder
        scroll.drawsBackground = false
        coordinator.didApply = true
    }
}

struct SidebarSectionHeader: View {
    let title: LocalizedStringKey

    var body: some View {
        HStack(spacing: 8) {
            Capsule()
                .fill(Color.accentColor.opacity(0.75))
                .frame(width: 4, height: 14)

            Text(title)
                .font(AetherUI.sectionHeaderFont)
                .foregroundStyle(.secondary)
                .textCase(nil)
                .tracking(0.2)
        }
        .padding(.top, 4)
    }
}

struct SidebarItemLabel: View {
    let title: String
    private let systemImage: String?
    private let iconView: AnyView?

    init(title: String, systemImage: String) {
        self.title = title
        self.systemImage = systemImage
        self.iconView = nil
    }

    init<Icon: View>(title: String, @ViewBuilder icon: () -> Icon) {
        self.title = title
        self.systemImage = nil
        self.iconView = AnyView(icon())
    }

    var body: some View {
        HStack(spacing: 12) {
            if let iconView {
                iconView
                    .frame(width: AetherUI.sidebarIconFrame, alignment: .center)
            } else if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: AetherUI.sidebarIconSize, weight: .semibold))
                    .frame(width: AetherUI.sidebarIconFrame, alignment: .center)
                    .foregroundStyle(.secondary)
            }

            Text(title)
                .font(AetherUI.sidebarItemFont)
                .foregroundStyle(.primary)
                .lineLimit(1)
        }
        .padding(.vertical, 6)
    }
}

struct SettingsPageHero<HeaderTrailing: View>: View {
    let title: String
    let subtitle: String
    let headerTrailing: HeaderTrailing

    init(
        title: String,
        subtitle: String,
        @ViewBuilder headerTrailing: () -> HeaderTrailing
    ) {
        self.title = title
        self.subtitle = subtitle
        self.headerTrailing = headerTrailing()
    }

    var body: some View {
        GlassCard(padding: 18) {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(title)
                        .font(AetherUI.pageTitleFont)
                    Text(subtitle)
                        .font(.callout)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 12)

                headerTrailing
            }
        }
    }
}

struct TransparencyModeIcon: View {
    let size: CGFloat
    var color: Color = .primary

    var body: some View {
        Image(systemName: "person.fill.viewfinder")
            .font(.system(size: size, weight: .semibold))
        .foregroundStyle(color)
        .frame(width: size, height: size, alignment: .center)
    }
}

struct DashboardTileHeader: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let iconBackground: Color
    let iconForeground: Color

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                Circle()
                    .fill(iconBackground)
                    .frame(width: 46, height: 46)

                Image(systemName: systemImage)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(iconForeground)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(AetherUI.cardTitleFont)
                    .lineLimit(1)
                    .minimumScaleFactor(0.9)
                Text(subtitle)
                    .font(AetherUI.bodyFont)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .allowsTightening(true)
                    .minimumScaleFactor(0.88)
            }
            .layoutPriority(1)

            Spacer(minLength: 12)
        }
    }
}

struct ControlCard: View {
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey
    let icon: String
    let color: Color
    @Binding var isOn: Bool
    
    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(isOn ? color : Color.gray.opacity(0.16))
                    .frame(width: 40, height: 40)

                Image(systemName: icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(isOn ? .white : .secondary)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Toggle("", isOn: $isOn)
                .labelsHidden()
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isOn ? color.opacity(0.25) : Color.black.opacity(0.04), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.02), radius: 1, x: 0, y: 1)
    }
}

struct SettingsPage<Content: View, HeaderTrailing: View, FooterOverlay: View>: View {
    @Environment(\.colorScheme) private var colorScheme

    let title: String
    let subtitle: String
    let headerTrailing: HeaderTrailing
    let showsInlineHeader: Bool
    let footerOverlay: FooterOverlay
    var content: Content

    init(
        title: String,
        subtitle: String,
        showsInlineHeader: Bool = false,
        @ViewBuilder content: () -> Content
    ) where HeaderTrailing == EmptyView, FooterOverlay == EmptyView {
        self.title = title
        self.subtitle = subtitle
        self.headerTrailing = EmptyView()
        self.showsInlineHeader = showsInlineHeader
        self.footerOverlay = EmptyView()
        self.content = content()
    }

    init(
        title: String,
        subtitle: String,
        showsInlineHeader: Bool = false,
        @ViewBuilder headerTrailing: () -> HeaderTrailing,
        @ViewBuilder content: () -> Content
    ) where FooterOverlay == EmptyView {
        self.title = title
        self.subtitle = subtitle
        self.headerTrailing = headerTrailing()
        self.showsInlineHeader = showsInlineHeader
        self.footerOverlay = EmptyView()
        self.content = content()
    }

    init(
        title: String,
        subtitle: String,
        showsInlineHeader: Bool = false,
        @ViewBuilder headerTrailing: () -> HeaderTrailing,
        @ViewBuilder footerOverlay: () -> FooterOverlay,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.headerTrailing = headerTrailing()
        self.showsInlineHeader = showsInlineHeader
        self.footerOverlay = footerOverlay()
        self.content = content()
    }

    private var baseContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                SettingsPageHero(title: title, subtitle: subtitle) {
                    headerTrailing
                }

                content
            }
            .frame(maxWidth: 960, alignment: .leading)
            .padding(.horizontal, 22)
            .padding(.vertical, 18)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background {
            ZStack {
                Color(nsColor: .windowBackgroundColor)

                LinearGradient(
                    colors: [
                        Color.accentColor.opacity(colorScheme == .dark ? 0.10 : 0.08),
                        Color.green.opacity(colorScheme == .dark ? 0.06 : 0.05),
                        Color.clear
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                RadialGradient(
                    colors: [
                        Color.white.opacity(colorScheme == .dark ? 0.08 : 0.85),
                        Color.clear
                    ],
                    center: .topLeading,
                    startRadius: 24,
                    endRadius: 360
                )
                .offset(x: -120, y: -90)
            }
            .ignoresSafeArea()
        }
        .overlay(alignment: .bottomTrailing) {
            footerOverlay
                .padding(.trailing, 22)
                .padding(.bottom, 18)
        }
    }

    @ViewBuilder
    var body: some View {
        baseContent
            .navigationTitle(title)
    }
}

struct PermissionRow: View {
    let icon: String
    let title: LocalizedStringKey
    let isGranted: Bool
    let detail: String?
    let action: () -> Void

    init(
        icon: String,
        title: LocalizedStringKey,
        isGranted: Bool,
        detail: String? = nil,
        action: @escaping () -> Void
    ) {
        self.icon = icon
        self.title = title
        self.isGranted = isGranted
        self.detail = detail
        self.action = action
    }
    
    var body: some View {
        HStack {
            Image(systemName: icon)
                .frame(width: 20)
                .foregroundColor(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                if let detail, !detail.isEmpty {
                    Text(detail)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            Spacer()
            if isGranted {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
            } else {
                Button(String(localized: "permissions.open_pane"), action: action)
                    .controlSize(.small)
            }
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(12)
    }
}

// MARK: - Generic Glass Card
struct GlassCard<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme

    var content: Content
    var padding: CGFloat
    
    init(padding: CGFloat = 20, @ViewBuilder content: () -> Content) {
        self.padding = padding
        self.content = content()
    }
    
    var body: some View {
        content
            .padding(padding)
            .background {
                RoundedRectangle(cornerRadius: AetherUI.cardCornerRadius, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(colorScheme == .dark ? 0.08 : 0.96),
                                Color(nsColor: .controlBackgroundColor).opacity(colorScheme == .dark ? 0.90 : 0.94)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
            .overlay {
                RoundedRectangle(cornerRadius: AetherUI.cardCornerRadius, style: .continuous)
                    .stroke(
                        colorScheme == .dark
                            ? Color.white.opacity(0.08)
                            : Color.black.opacity(0.06),
                        lineWidth: 1
                    )
            }
            .shadow(
                color: Color.black.opacity(colorScheme == .dark ? 0.18 : 0.05),
                radius: colorScheme == .dark ? 10 : 18,
                x: 0,
                y: colorScheme == .dark ? 4 : 10
            )
    }
}

// MARK: - Voice Visualizer (Simulated Waveform)
struct VisualizerView: View {
    @ObservedObject var appState: AppState
    @State private var phase: CGFloat = 0
    @State private var amplitude: CGFloat = 0
    
    // Simulate audio level since we don't have raw buffer access easily here
    // In a real app, we'd bind this to SpeechManager's audio meter
    var targetAmplitude: CGFloat {
        if appState.voiceStatus == "Listening..." { return 1.0 }
        if appState.voiceStatus == "Processing..." { return 0.5 }
        return 0.1
    }
    
    var body: some View {
        Canvas { context, size in
            let midY = size.height / 2
            let width = size.width
            
            var path = Path()
            path.move(to: CGPoint(x: 0, y: midY))
            
            for x in stride(from: 0, to: width, by: 2) {
                let relativeX = x / width
                let sine = sin(relativeX * 10 + phase)
                let y = midY + sine * amplitude * 20 * sin(relativeX * .pi) // Windowing
                path.addLine(to: CGPoint(x: x, y: y))
            }
            
            context.stroke(path, with: .color(.green), lineWidth: 2)
        }
        .onReceive(Timer.publish(every: 0.02, on: .main, in: .common).autoconnect()) { _ in
            phase += 0.2
            // Smooth amplitude transition
            let diff = targetAmplitude - amplitude
            amplitude += diff * 0.1
        }
    }
}

// MARK: - Motion Radar (Matrix)
struct RadarView: View {
    @ObservedObject var headManager = HeadMotionManager.shared
    
    var body: some View {
        GeometryReader { geo in
            ZStack {
                // Background Grid
                Circle()
                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
                
                Circle()
                    .stroke(Color.white.opacity(0.05), lineWidth: 1)
                    .scaleEffect(0.5)
                
                // Crosshair
                Path { path in
                    path.move(to: CGPoint(x: geo.size.width / 2, y: 0))
                    path.addLine(to: CGPoint(x: geo.size.width / 2, y: geo.size.height))
                    path.move(to: CGPoint(x: 0, y: geo.size.height / 2))
                    path.addLine(to: CGPoint(x: geo.size.width, y: geo.size.height / 2))
                }
                .stroke(Color.white.opacity(0.1), style: StrokeStyle(lineWidth: 1, dash: [5]))
                
                // Current Head Position Cursor
                Circle()
                    .fill(Color.blue)
                    .frame(width: 10, height: 10)
                    .shadow(color: .blue, radius: 5)
                    .offset(
                        x: CGFloat(headManager.currentHeadYaw * 500), // Scale factor
                        y: CGFloat(headManager.currentHeadPitch * 500)
                    )
                    .animation(.interactiveSpring, value: headManager.currentHeadYaw)
                
                // Velocity Indicator (Ring expands with speed)
                if headManager.currentVelocity > 0.001 {
                    Circle()
                        .stroke(Color.blue.opacity(0.5), lineWidth: 1)
                        .frame(width: 10 + CGFloat(headManager.currentVelocity * 1000), height: 10 + CGFloat(headManager.currentVelocity * 1000))
                        .offset(
                             x: CGFloat(headManager.currentHeadYaw * 500),
                             y: CGFloat(headManager.currentHeadPitch * 500)
                        )
                }
                
                // Status Text
                VStack {
                    Spacer()
                    HStack {
                        Text(String(format: "Y: %.2f", headManager.currentHeadYaw))
                        Spacer()
                        Text(String(format: "P: %.2f", headManager.currentHeadPitch))
                    }
                    .font(.caption2.monospaced())
                    .foregroundColor(.secondary)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .background(Color.black.opacity(0.2))
        .cornerRadius(12)
    }
}
