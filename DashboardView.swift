import SwiftUI

struct OverviewSettingsView: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject var headManager = HeadMotionManager.shared
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Big Status Indicator
                VStack(spacing: 12) {
                    statusIcon
                        .font(.system(size: 48))
                        .foregroundColor(statusColor)
                        .symbolEffect(.bounce, value: statusIconName)
                    
                    Text(statusText)
                        .font(.title2)
                        .fontWeight(.medium)
                    
                    if !descriptionText.isEmpty {
                        Text(descriptionText)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                }
                .padding(.vertical, 30)
                
                // Quick Toggles
                HStack(spacing: 20) {
                    ToggleCard(
                        title: String(localized: "row.voice"),
                        icon: "mic.fill",
                        isOn: $appState.isAlwaysListeningEnabled
                    )
                    
                    ToggleCard(
                        title: String(localized: "row.airpods_matrix"),
                        icon: "viewfinder",
                        isOn: $headManager.isTracking
                    )
                }
                .padding(.horizontal)
                
                // System Status Pills (Moved from Header)
                HStack {
                    StatusPill(label: "Driver", isOkay: appState.driverStatus.contains("Connected") || appState.driverStatus.contains("Ready"))
                    Spacer()
                    StatusPill(label: "AirPods", isOkay: headManager.isTracking)
                }
                .padding(.top, 20)
                .padding(.horizontal)
            }
            .padding()
        }
    }
    
    // MARK: - Status Logic
    
    private var statusIconName: String {
        if appState.isAlwaysListeningEnabled {
            if isListeningForCommand {
                return "mic.fill"
            } else if isWaitingForWakeWord {
                return "ear"
            }
        }
        return "mic.slash"
    }
    
    private var statusColor: Color {
        if appState.isAlwaysListeningEnabled {
            if isListeningForCommand {
                return .green
            } else if isWaitingForWakeWord {
                return .orange
            }
        }
        return .secondary
    }
    
    private var statusText: String {
        if appState.isAlwaysListeningEnabled {
            if isListeningForCommand {
                return String(localized: "speech.listening")
            } else if isWaitingForWakeWord {
                return String(localized: "speech.waiting_wakeword")
            }
        }
        return String(localized: "generic.off")
    }
    
    private var descriptionText: String {
        if appState.isAlwaysListeningEnabled {
            if isListeningForCommand {
                return String(localized: "dashboard.hint.command", defaultValue: "Say a command like 'Click'")
            } else {
                return String(localized: "dashboard.hint.wakeword", defaultValue: "Say 'Aether' to wake up")
            }
        }
        return String(localized: "dashboard.hint.enable", defaultValue: "Enable Voice Control to start")
    }
    
    private var isListeningForCommand: Bool {
        if headManager.isTracking && headManager.isLookingAtScreen { return true }
        if let last = appState.lastVoiceWakeTime {
             return Date().timeIntervalSince(last) < appState.alwaysListeningWakeWindowSeconds
        }
        return false
    }
    
    private var isWaitingForWakeWord: Bool {
        return appState.isAlwaysListeningEnabled && !isListeningForCommand
    }
    
    // MARK: - Components
    
    private var statusIcon: some View {
        Image(systemName: statusIconName)
    }
}

struct ToggleCard: View {
    let title: String
    let icon: String
    @Binding var isOn: Bool
    
    var body: some View {
        Button {
            isOn.toggle()
        } label: {
            VStack {
                Image(systemName: icon)
                    .font(.system(size: 24))
                    .foregroundColor(isOn ? .white : .primary)
                Text(title)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(isOn ? .white : .primary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(isOn ? .blue : Color.gray.opacity(0.1))
            .cornerRadius(12)
        }
        .buttonStyle(.plain)
    }
}

struct StatusPill: View {
    let label: String
    let isOkay: Bool
    
    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(isOkay ? Color.green : Color.red)
                .frame(width: 6, height: 6)
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Material.ultraThin)
        .cornerRadius(8)
    }
}
