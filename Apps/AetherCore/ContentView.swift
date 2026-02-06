import SwiftUI

struct ContentView: View {
    @EnvironmentObject var appState: AppState
    
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "antenna.radiowaves.left.and.right")
                .font(.system(size: 60))
                .foregroundColor(.blue)
            
            Text("Project Aether")
                .font(.largeTitle)
                .fontWeight(.bold)
            
            Text("Perception Network: \(appState.driverStatus)")
                .font(.headline)
                .foregroundColor(.secondary)
            
            Divider()
            
            VStack(alignment: .leading, spacing: 10) {
                StatusRow(icon: "magicmouse", title: "Virtual HID", status: appState.driverStatus == "Activated" ? "Running" : "Idle")
                StatusRow(icon: "airpods", title: "AirPods Matrix", status: appState.isMotionTracking ? "Tracking" : "Ready")
                StatusRow(icon: "mic", title: "Voice", status: appState.voiceStatus)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Permissions")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    HStack(spacing: 8) {
                        PermissionPill(title: "Accessibility", ok: appState.accessibilityTrusted)
                        PermissionPill(title: "Microphone", ok: appState.microphoneAuthorized)
                        PermissionPill(title: "Speech", ok: appState.speechAuthorized)
                    }

                    HStack(spacing: 10) {
                        Button("Fix Accessibility") { appState.requestAccessibility() }
                        Button("Open Pane") { appState.openAccessibilityPane() }
                    }
                    .controlSize(.small)

                    HStack(spacing: 10) {
                        Button("Fix Microphone") { appState.requestMicrophone() }
                        Button("Open Pane") { appState.openMicrophonePane() }
                    }
                    .controlSize(.small)

                    HStack(spacing: 10) {
                        Button("Fix Speech") { appState.requestSpeech() }
                        Button("Open Pane") { appState.openSpeechPane() }
                    }
                    .controlSize(.small)
                }
                .padding(8)
                .background(Color.black.opacity(0.06))
                .cornerRadius(8)
                
                if appState.isMotionTracking {
                    Text(appState.attitudeData)
                        .font(.system(.caption, design: .monospaced))
                        .padding(8)
                        .background(Color.black.opacity(0.1))
                        .cornerRadius(5)
                }

                if !appState.lastVoiceTranscript.isEmpty {
                    Text(appState.lastVoiceTranscript)
                        .font(.system(.caption, design: .monospaced))
                        .padding(8)
                        .background(Color.black.opacity(0.1))
                        .cornerRadius(5)
                }
                
                StatusRow(icon: "laptopcomputer", title: "Lid Sensor", status: "Ready")
                
                Toggle("Dwell Click (悬停点击)", isOn: $appState.isDwellClickEnabled)
                    .padding(.top, 5)

                Toggle("Always Listening (常驻监听)", isOn: $appState.isAlwaysListeningEnabled)

                Toggle("LLM Enhance Dictation (大模型增强听写)", isOn: $appState.isLLMEnhancementEnabled)

                Text("Push-to-talk: hold ⌃⌥V (默认). Always Listening: say “Aether …”")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(10)
            
            Spacer()
            
            VStack(spacing: 12) {
                Button(action: {
                    appState.activateDriver()
                }) {
                    Text("Activate Perception")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                
                Button(action: {
                    appState.toggleMotionTracking()
                }) {
                    Text(appState.isMotionTracking ? "Stop Motion Matrix" : "Start Motion Matrix")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                
                if appState.isMotionTracking && appState.calibrationStatus != "Normal" {
                    Button(action: {
                        appState.finishCalibration()
                    }) {
                        Text("Finish Range Calibration")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                    .controlSize(.large)
                    
                    Text(appState.calibrationStatus)
                        .font(.caption)
                        .foregroundColor(.orange)
                }
                
                VStack(spacing: 4) {
                    Text("Emergency Stop: ⌃⌥S")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .padding(.top, 5)
            }
        }
        .padding()
    }
}

struct PermissionPill: View {
    let title: String
    let ok: Bool

    var body: some View {
        Text("\(ok ? "✓" : "•") \(title)")
            .font(.caption2)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(ok ? Color.green.opacity(0.2) : Color.orange.opacity(0.2))
            .cornerRadius(999)
    }
}

struct StatusRow: View {
    let icon: String
    let title: String
    let status: String
    
    var body: some View {
        HStack {
            Image(systemName: icon)
                .frame(width: 24)
            Text(title)
            Spacer()
            Text(status)
                .foregroundColor(.secondary)
        }
    }
}
