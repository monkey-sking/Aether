import Foundation

enum VoiceActivityHoldPolicy {
    static func isSpeechActivityHoldActive(
        latestVoiceActivity: Bool,
        lastSpeechActivityAge: TimeInterval?,
        holdWindow: TimeInterval
    ) -> Bool {
        if latestVoiceActivity {
            return true
        }

        guard let lastSpeechActivityAge else {
            return false
        }

        guard holdWindow > 0 else {
            return false
        }

        return lastSpeechActivityAge <= holdWindow
    }

    static func shouldKeepWakeGatedDictationActive(
        isWakeWordEnabled: Bool,
        isDirectCommandEnabled: Bool,
        sessionTypingMode: Bool,
        isUtteranceActive: Bool,
        hasStreamedDictation: Bool,
        pendingWakeFollowUp: Bool,
        fallbackWindowActive: Bool,
        speechActivityHoldActive: Bool
    ) -> Bool {
        guard isWakeWordEnabled, !isDirectCommandEnabled else { return false }
        guard sessionTypingMode else { return false }
        return isUtteranceActive
            || hasStreamedDictation
            || pendingWakeFollowUp
            || fallbackWindowActive
            || speechActivityHoldActive
    }

    static func shouldKeepWakeFollowUpActive(
        isWakeFollowUpSessionActive: Bool,
        keepWakeGatedDictationHUD: Bool,
        speechActivityHoldActive: Bool
    ) -> Bool {
        isWakeFollowUpSessionActive || keepWakeGatedDictationHUD || speechActivityHoldActive
    }

    static func shouldExtendWakeFollowUp(
        speechActivityHoldActive: Bool,
        holdWindow: TimeInterval,
        recognitionRunning: Bool,
        audioRunning: Bool,
        isStopping: Bool
    ) -> Bool {
        guard recognitionRunning, audioRunning, !isStopping else {
            return false
        }

        guard holdWindow >= 0 else {
            return false
        }

        return speechActivityHoldActive
    }

    static func shouldHoldWakeFollowUpForLateFinal(
        isUtteranceActive: Bool,
        hasTranscript: Bool,
        hasRecentTranscriptChange: Bool,
        speechActivityHoldActive: Bool
    ) -> Bool {
        isUtteranceActive || hasTranscript || hasRecentTranscriptChange || speechActivityHoldActive
    }

    static func shouldHideDictationOnlyHUDWithoutFocus(
        focusedTypingEvidence: Bool,
        effectiveDictating: Bool,
        speechActivityHoldActive: Bool
    ) -> Bool {
        guard !focusedTypingEvidence else {
            return false
        }

        guard !effectiveDictating else {
            return false
        }

        guard !speechActivityHoldActive else {
            return false
        }

        return true
    }
}
