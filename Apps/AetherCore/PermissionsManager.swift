import Foundation
import AppKit
import ApplicationServices
import AVFoundation
import Speech

@MainActor
final class PermissionsManager: ObservableObject {
    @Published var accessibilityTrusted: Bool = false
    @Published var microphoneAuthorized: Bool = false
    @Published var speechAuthorized: Bool = false

    init() {
        refresh()
    }

    func refresh() {
        // Accessibility / Input Monitoring
        accessibilityTrusted = AXIsProcessTrusted()

        // Microphone
        microphoneAuthorized = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized

        // Speech Recognition
        speechAuthorized = SFSpeechRecognizer.authorizationStatus() == .authorized
    }

    func requestAccessibility() {
        // Triggers the system prompt (opens Accessibility list). User still must toggle manually.
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(opts)
        refresh()
    }

    func requestMicrophone() {
        AVCaptureDevice.requestAccess(for: .audio) { _ in
            DispatchQueue.main.async { self.refresh() }
        }
    }

    func requestSpeech() {
        SFSpeechRecognizer.requestAuthorization { _ in
            DispatchQueue.main.async { self.refresh() }
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

