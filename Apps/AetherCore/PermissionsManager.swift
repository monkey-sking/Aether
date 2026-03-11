import Foundation
import AppKit
import ApplicationServices
import AVFoundation
import Speech
import os.log

@MainActor
final class PermissionsManager: ObservableObject {
    private let log = OSLog(subsystem: "com.7fei.Aether", category: "Permissions")
    private var lastAccessibilityPromptAt: Date = .distantPast
    private var didRequestAccessibilityPromptThisRun: Bool = false
    private var lastMicrophonePromptAt: Date = .distantPast
    private var lastSpeechPromptAt: Date = .distantPast
    private var isMicrophoneRequestInFlight: Bool = false
    private var isSpeechRequestInFlight: Bool = false

    @Published var accessibilityTrusted: Bool = false
    @Published var microphoneAuthorized: Bool = false
    @Published var speechAuthorized: Bool = false

    init() {
        // Defer permission check to onAppear to avoid TCC crash on launch
    }

    func refresh() {
        // Accessibility / Input Monitoring
        accessibilityTrusted = AXIsProcessTrusted()

        // Microphone
        let micStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        microphoneAuthorized = micStatus == .authorized

        // Speech Recognition
        let speechStatus = SFSpeechRecognizer.authorizationStatus()
        speechAuthorized = speechStatus == .authorized

        os_log(
            "refresh: AX=%{bool}d, Mic=%{public}@(%d), Speech=%{public}@(%d)",
            log: log,
            type: .info,
            accessibilityTrusted,
            String(describing: micStatus),
            micStatus.rawValue,
            String(describing: speechStatus),
            speechStatus.rawValue
        )
    }

    @discardableResult
    func requestAccessibility() -> Bool {
        if AXIsProcessTrusted() {
            didRequestAccessibilityPromptThisRun = false
            refresh()
            return false
        }
        if didRequestAccessibilityPromptThisRun {
            refresh()
            return false
        }
        let now = Date()
        if now.timeIntervalSince(lastAccessibilityPromptAt) < 1.5 {
            refresh()
            return false
        }
        didRequestAccessibilityPromptThisRun = true
        lastAccessibilityPromptAt = now
        // Triggers the system prompt (opens Accessibility list). User still must toggle manually.
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(opts)
        refresh()
        return true
    }

    func requestMicrophone() {
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        if status == .authorized {
            refresh()
            return
        }
        let now = Date()
        if isMicrophoneRequestInFlight || now.timeIntervalSince(lastMicrophonePromptAt) < 1.2 {
            refresh()
            return
        }
        isMicrophoneRequestInFlight = true
        lastMicrophonePromptAt = now
        AVCaptureDevice.requestAccess(for: .audio) { _ in
            DispatchQueue.main.async {
                self.isMicrophoneRequestInFlight = false
                self.refresh()
            }
        }
    }

    func requestSpeech() {
        let status = SFSpeechRecognizer.authorizationStatus()
        if status == .authorized {
            refresh()
            return
        }
        let now = Date()
        if isSpeechRequestInFlight || now.timeIntervalSince(lastSpeechPromptAt) < 1.2 {
            refresh()
            return
        }
        isSpeechRequestInFlight = true
        lastSpeechPromptAt = now
        SFSpeechRecognizer.requestAuthorization { _ in
            DispatchQueue.main.async {
                self.isSpeechRequestInFlight = false
                self.refresh()
            }
        }
    }

    func openAccessibilityPrivacyPane() {
        openSystemSettings(urlString: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
    }

    func openMicrophonePrivacyPane() {
        openSystemSettings(urlString: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")
    }

    func openSpeechPrivacyPane() {
        openSystemSettings(urlString: "x-apple.systempreferences:com.apple.preference.security?Privacy_SpeechRecognition")
    }

    private func openSystemSettings(urlString: String) {
        guard let url = URL(string: urlString) else { return }
        NSWorkspace.shared.open(url)
    }
}
