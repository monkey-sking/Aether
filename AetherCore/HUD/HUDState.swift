import Foundation
import SwiftUI

enum HUDMode: String {
    case hidden
    case standby     // 🟢 Wake Word waiting (Green Dot)
    case listening   // 🎤 Waiting for speech (Mic + "Listening...")
    case command     // 🎤 Live transcription (Mic + realtime text)
    case dictation   // 📊 Typing mode (Waveform)
    case processing  // ⋯ Trailing audio capture
}

enum HUDRecognitionControlMode: String {
    case auto
    case command
    case dictation
}

final class HUDState: ObservableObject {
    @Published var mode: HUDMode = .hidden
    @Published var message: String = ""
    @Published var language: String = Locale.current.identifier
    @Published var audioLevel: CGFloat = 0.0
    @Published var isTypingContext: Bool = false
    @Published var recognitionControlMode: HUDRecognitionControlMode = .auto
    @Published var inputDeviceIcon: String = "mic.fill"
    @Published var isLanguageIndicatorVisible: Bool = false
    // 0...1 progress for current recording segment (visual ring around mic icon).
    @Published var micProgress: CGFloat = 0.0
    @Published var isMicProgressVisible: Bool = false

    func update(
        mode: HUDMode,
        message: String,
        language: String,
        isTypingContext: Bool,
        recognitionControlMode: HUDRecognitionControlMode,
        inputDeviceIcon: String
    ) {
        self.mode = mode
        self.message = message
        self.language = language
        self.isTypingContext = isTypingContext
        self.recognitionControlMode = recognitionControlMode
        self.inputDeviceIcon = inputDeviceIcon
    }
}
