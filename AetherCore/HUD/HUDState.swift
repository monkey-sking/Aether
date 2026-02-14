import Foundation
import Combine
import SwiftUI

enum HUDMode: String {
    case hidden
    case standby    // Wake Word waiting (Minimal/Dot)
    case active     // Listening (Standard)
    case dictation  // Long-form (Waveform)
    case processing // Trailing Audio Capture
}

final class HUDState: ObservableObject {
    @Published var mode: HUDMode = .hidden
    @Published var message: String = ""
    @Published var language: String = Locale.current.identifier
    @Published var isInteractive: Bool = false
    @Published var isTypingMode: Bool = false
    @Published var audioLevel: CGFloat = 0.0
    
    func update(mode: HUDMode, message: String, language: String, isInteractive: Bool) {
        self.mode = mode
        self.message = message
        self.language = language
        self.isInteractive = isInteractive
    }
}
