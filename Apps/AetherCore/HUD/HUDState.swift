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

final class HUDState: ObservableObject {
    @Published var mode: HUDMode = .hidden
    @Published var message: String = ""
    @Published var language: String = Locale.current.identifier
    @Published var audioLevel: CGFloat = 0.0

    func update(mode: HUDMode, message: String, language: String) {
        self.mode = mode
        self.message = message
        self.language = language
    }
}
