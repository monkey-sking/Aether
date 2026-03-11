import Foundation
import os

/// Handles the control flow path (non-dictation).
/// Only processes final results through VoiceCommandRouter.
/// Partial results are forwarded to the HUD for live preview only.
@MainActor
final class CommandHandler {

    // MARK: - Callbacks
    var onIntent: ((VoiceIntent) -> Void)?
    var onTranscriptUpdate: ((String) -> Void)?

    // MARK: - Dependencies
    private let router = VoiceCommandRouter()
    private let log = GlobalLogger.speech

    // MARK: - Public API

    /// Called for every partial (non-final) STT result. Only updates HUD display.
    func onPartial(_ text: String) {
        onTranscriptUpdate?(text)
    }

    /// Called on final result. Routes through VoiceCommandRouter and fires intent.
    func onFinal(_ text: String, bias: VoiceCommandRouter.RoutingBias) {
        guard !text.isEmpty else { return }
        let intent = router.route(transcript: text, bias: bias)
        os_log("CommandHandler routed: '%{public}@' -> %{public}@",
               log: log, type: .info, text, String(describing: intent))
        onIntent?(intent)
    }
}
