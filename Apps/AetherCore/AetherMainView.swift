import SwiftUI

// MARK: - Main Application Bundle
struct AetherMainView: View {
    @EnvironmentObject var appState: AppState
    @State private var selection: Panel? = .dashboard
    
    enum Panel: Hashable {
        case dashboard
        case input
        case output
        case shortcuts
        case system
    }
    
    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Section {
                    NavigationLink(value: Panel.dashboard) {
                        Label(L10n.commandCenterTitle, systemImage: "macwindow.on.rectangle")
                    }
                } header: {
                    Text(L10n.settingsTabOverview)
                }
                
                Section {
                    NavigationLink(value: Panel.input) {
                        Label(L10n.commandCenterVoiceStream, systemImage: "mic.fill")
                    }
                    NavigationLink(value: Panel.output) {
                        Label(L10n.commandCenterMotionMatrix, systemImage: "viewfinder")
                    }
                    NavigationLink(value: Panel.shortcuts) {
                        Label(L10n.settingsHeaderShortcuts, systemImage: "keyboard")
                    }
                } header: {
                    Text(L10n.navControls)
                }
                
                Section {
                    NavigationLink(value: Panel.system) {
                        Label(L10n.navSystem, systemImage: "gearshape")
                    }
                } header: {
                    Text(L10n.navConfiguration)
                }
            }
            .navigationTitle("Aether")
            .listStyle(.sidebar)
            
        } detail: {
            switch selection {
            case .dashboard:
                CommandCenterView()
            case .input:
                InputSettingsView()
            case .output:
                OutputSettingsView()
            case .shortcuts:
                ShortcutsSettingsView() 
            case .system:
                SystemSettingsView()
            case .none:
                Text(L10n.selectItem)
            }
        }
        .navigationSplitViewStyle(.balanced)
    }
}


// MARK: - Command Center (Home)
struct CommandCenterView: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject var headManager = HeadMotionManager.shared

    private var trackingBinding: Binding<Bool> {
        Binding(
            get: { headManager.isTracking },
            set: { isOn in
                if isOn {
                    headManager.startTracking()
                } else {
                    headManager.stopTracking()
                }
            }
        )
    }
    
    var body: some View {
        VStack(spacing: 24) { // Increased spacing
            // Title & Status Header
            HStack {
                VStack(alignment: .leading) {
                    Text(L10n.commandCenterTitle)
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                    HStack {
                        Circle()
                            .fill(appState.isAlwaysListeningEnabled ? Color.green : Color.red)
                            .frame(width: 8, height: 8)
                        Text(appState.isAlwaysListeningEnabled ? L10n.systemActive : L10n.systemOffline)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
                Spacer()
                
                // Top-right Action Buttons
                HStack(spacing: 12) {
                     Button(action: { headManager.recenter() }) {
                         Label(L10n.actionRecenter, systemImage: "scope")
                     }
                     .controlSize(.large)
                     
                     Button(action: {
                         appState.voiceActivationMode = appState.voiceActivationMode == .handsFree ? .pushToTalk : .handsFree
                     }) {
                         Image(systemName: appState.isAlwaysListeningEnabled ? "power.circle.fill" : "power.circle")
                             .font(.system(size: 24))
                             .foregroundColor(appState.isAlwaysListeningEnabled ? .green : .secondary)
                     }
                     .buttonStyle(.plain)
                }
            }
            .padding(.horizontal)
            .padding(.top, 20)
            
            // Signal-to-Action Visualization Area
            HStack(spacing: 20) {
                // Left: Voice Signal
                GlassCard {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            Image(systemName: "waveform.circle.fill")
                                .font(.title2)
                                .foregroundColor(.blue)
                            Text(L10n.vizVoiceSignal)
                                .font(.headline)
                            Spacer()
                            Text(appState.voiceStatus) // voiceStatus might need localization in AppState
                                .font(.caption.monospaced())
                                .foregroundColor(.secondary)
                        }
                        
                        VisualizerView(appState: appState)
                            .frame(height: 180)
                            .background(Color.black.opacity(0.3))
                            .cornerRadius(12)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
                            )
                        
                        // Metadata
                        HStack {
                            VStack(alignment: .leading) {
                                Text(L10n.vizLastCommand)
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(.secondary)
                                Text(appState.lastVoiceTranscript.isEmpty ? "--" : appState.lastVoiceTranscript)
                                    .font(.subheadline)
                                    .lineLimit(1)
                            }
                            Spacer()
                        }
                    }
                }
                
                // Right: Motion Matrix
                GlassCard {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            Image(systemName: "viewfinder.circle.fill")
                                .font(.title2)
                                .foregroundColor(.purple)
                            Text(L10n.commandCenterMotionMatrix)
                                .font(.headline)
                            Spacer()
                            Toggle("", isOn: trackingBinding)
                                .toggleStyle(.switch)
                                .labelsHidden()
                        }
                        
                        RadarView()
                            .frame(height: 180)
                        
                        // Metadata
                        HStack {
                            VStack(alignment: .leading) {
                                Text(L10n.vizCalibration)
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(.secondary)
                                if headManager.calibrationStatus == "Normal" {
                                    Text(L10n.calibrationNormal)
                                        .font(.subheadline)
                                        .foregroundColor(.green)
                                } else {
                                    Text(headManager.calibrationStatus)
                                        .font(.subheadline)
                                        .foregroundColor(.orange)
                                }
                            }
                            Spacer()
                            VStack(alignment: .trailing) {
                                Text(L10n.vizVelocity)
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(.secondary)
                                Text(String(format: "%.3f", headManager.currentVelocity))
                                    .font(.subheadline.monospaced())
                            }
                        }
                    }
                }
            }
            .frame(height: 320) // Fixed height for consistency
            .padding(.horizontal)
            
            Spacer()
        }
        .padding()
        .background(Color.black.opacity(0.4)) // Deep background
    }
}


// Placeholder views are now in SettingsModules.swift
