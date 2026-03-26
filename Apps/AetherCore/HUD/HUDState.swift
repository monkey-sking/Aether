import Foundation
import SwiftUI

enum HUDMode: String {
    case hidden
    case standby     // Wake Word waiting (Green Dot)
    case listening   // Waiting for speech (Mic + "Listening...")
    case command     // Live transcription (Mic + realtime text)
    case dictation   // Typing mode (Waveform)
    case organizing  // Captured speech is being normalized/refined
    case typing      // Final text is being injected
    case executing   // Command/action is being executed
    case optimizing  // Long-running rewrite/optimization
    case checking    // Post-apply verification
    case dragging    // Pointer drag is active
    case processing  // ⋯ Trailing audio capture
    case feedback    // Temporary result / alert pulse
}

enum HUDRecognitionControlMode: String {
    case auto
    case command
    case dictation
}

enum HUDInputDeviceHealth: String {
    case normal
    case warning
    case limited
    case error
}

final class HUDState: ObservableObject {
    struct GestureTrailPoint: Equatable {
        let x: CGFloat
        let y: CGFloat
    }

    @Published var mode: HUDMode = .hidden
    @Published var message: String = ""
    @Published var language: String = Locale.current.identifier
    @Published var audioLevel: CGFloat = 0.0
    @Published var isTypingContext: Bool = false
    @Published var recognitionControlMode: HUDRecognitionControlMode = .auto
    @Published var inputDeviceIcon: String = "mic.fill"
    @Published var inputDeviceHealth: HUDInputDeviceHealth = .normal
    @Published var contextIcon: String = ""
    @Published var isLanguageIndicatorVisible: Bool = false
    // 0...1 progress for current recording segment (visual ring around mic icon).
    @Published var micProgress: CGFloat = 0.0
    @Published var isMicProgressVisible: Bool = false
    @Published var caretDebugIndicatorVisible: Bool = false
    @Published var caretDebugIndicatorColor: Color = .clear
    @Published var caretDebugIndicatorLabel: String = ""
    @Published var gestureTrailPoints: [GestureTrailPoint] = []
    @Published var gestureTrailStatus: String = ""
    @Published var isGestureTrailVisible: Bool = false

    func update(
        mode: HUDMode,
        message: String,
        language: String,
        isTypingContext: Bool,
        recognitionControlMode: HUDRecognitionControlMode,
        inputDeviceIcon: String,
        inputDeviceHealth: HUDInputDeviceHealth,
        contextIcon: String
    ) {
        self.mode = mode
        self.message = message
        self.language = language
        self.isTypingContext = isTypingContext
        self.recognitionControlMode = recognitionControlMode
        self.inputDeviceIcon = inputDeviceIcon
        self.inputDeviceHealth = inputDeviceHealth
        self.contextIcon = contextIcon
    }

    func updateGestureTrail(points: [GestureTrailPoint], status: String, visible: Bool) {
        gestureTrailPoints = points
        gestureTrailStatus = status
        isGestureTrailVisible = visible
    }
}
