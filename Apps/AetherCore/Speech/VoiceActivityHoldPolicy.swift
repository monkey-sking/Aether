import Foundation

enum VoiceActivityHoldPolicy {
    static func hasRecentVoiceActivity(
        latestVoiceActivity: Bool,
        lastVoiceActivityAge: TimeInterval?,
        holdWindow: TimeInterval
    ) -> Bool {
        if latestVoiceActivity {
            return true
        }

        guard let lastVoiceActivityAge else {
            return false
        }

        return lastVoiceActivityAge <= holdWindow
    }

    static func shouldExtendWakeFollowUp(
        latestVoiceActivity: Bool,
        lastVoiceActivityAge: TimeInterval?,
        holdWindow: TimeInterval,
        recognitionRunning: Bool,
        audioRunning: Bool,
        isStopping: Bool
    ) -> Bool {
        guard recognitionRunning, audioRunning, !isStopping else {
            return false
        }

        return hasRecentVoiceActivity(
            latestVoiceActivity: latestVoiceActivity,
            lastVoiceActivityAge: lastVoiceActivityAge,
            holdWindow: holdWindow
        )
    }

    static func shouldHoldDictationHUD(
        dictationEnabled: Bool,
        typingInteraction: Bool,
        wakeGated: Bool,
        wakeFollowUpActive: Bool,
        latestVoiceActivity: Bool,
        lastVoiceActivityAge: TimeInterval?,
        holdWindow: TimeInterval
    ) -> Bool {
        guard dictationEnabled, typingInteraction else {
            return false
        }

        guard !wakeGated || wakeFollowUpActive else {
            return false
        }

        return hasRecentVoiceActivity(
            latestVoiceActivity: latestVoiceActivity,
            lastVoiceActivityAge: lastVoiceActivityAge,
            holdWindow: holdWindow
        )
    }
}
