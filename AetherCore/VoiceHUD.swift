import SwiftUI
你
struct VoiceHUD: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject var headManager = HeadMotionManager.shared
    
    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { context in
            if isAwake {
                HStack(spacing: 8) {
                    Image(systemName: "mic.fill")
                        .foregroundColor(.green)
                        .imageScale(.medium)
                        // Simple pulse animation could go here
                    
                    Text(displayCookie)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.white)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Material.regularMaterial)
                .cornerRadius(20)
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(Color.white.opacity(0.2), lineWidth: 1)
                )
                .padding(.top, 60)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.spring(), value: isAwake)
    }
    
    private var isAwake: Bool {
        // Gaze Wake
        if headManager.isTracking && headManager.isLookingAtScreen {
            return true
        }
        // Timeout Wake
        if let last = appState.lastVoiceWakeTime {
            return Date().timeIntervalSince(last) < 8.0
        }
        return false
    }
    
    private var displayCookie: String {
        if headManager.isLookingAtScreen && headManager.isTracking {
            return "Listening (Gaze)"
        }
        return "Listening..."
    }
}
