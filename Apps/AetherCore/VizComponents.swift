import SwiftUI

// MARK: - Shared UI Components

struct ControlCard: View {
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey
    let icon: String
    let color: Color
    @Binding var isOn: Bool
    
    var body: some View {
        Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                isOn.toggle()
            }
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(isOn ? color : Color.gray.opacity(0.2))
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
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Toggle("", isOn: $isOn)
                    .labelsHidden()
            }
            .padding(12)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isOn ? color.opacity(0.3) : Color.black.opacity(0.05), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.03), radius: 2, x: 0, y: 1)
        }
        .buttonStyle(.plain)
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
                Button("Allow", action: action)
                    .controlSize(.small)
            }
        }
        .padding(12)
    }
}

// MARK: - Generic Glass Card
struct GlassCard<Content: View>: View {
    var content: Content
    
    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }
    
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16)
                .fill(Material.ultraThin)
                .shadow(color: Color.black.opacity(0.1), radius: 5, x: 0, y: 2)
            
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
            
            content
                .padding()
        }
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
