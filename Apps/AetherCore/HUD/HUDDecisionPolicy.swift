import Foundation

enum HUDDecisionPolicy {
    enum VisibilityAction: Equatable {
        case visible
        case hide
        case preserveCurrentVisible
        case speechBars
    }

    struct VisibilityDecision: Equatable {
        let action: VisibilityAction
        let reason: String
    }

    static func resolvedVisibility(
        isWakeGatedStandby: Bool,
        isSpeechExitBarsHoldActive: Bool,
        hasTemporaryHUD: Bool,
        hasLanguageIndicator: Bool,
        isContinuousActive: Bool,
        isSessionActive: Bool,
        isPushToTalkOnlyIdle: Bool,
        dictationOnlyWithoutFocusHidden: Bool,
        hasRealHardware: Bool,
        isWakeGatedHiddenBeforeModeSelection: Bool
    ) -> VisibilityDecision {
        if isWakeGatedStandby {
            if isSpeechExitBarsHoldActive {
                return VisibilityDecision(action: .speechBars, reason: "wake-gated-standby-exit-bars")
            }
            if hasTemporaryHUD || hasLanguageIndicator {
                return VisibilityDecision(action: .preserveCurrentVisible, reason: "wake-gated-standby-temporary")
            }
            return VisibilityDecision(action: .hide, reason: "wake-gated-standby")
        }

        if !isContinuousActive && !isSessionActive {
            if isSpeechExitBarsHoldActive {
                return VisibilityDecision(action: .speechBars, reason: "no-session-exit-bars")
            }
            if isPushToTalkOnlyIdle {
                if hasTemporaryHUD || hasLanguageIndicator {
                    return VisibilityDecision(action: .preserveCurrentVisible, reason: "ptt-idle-temporary")
                }
                return VisibilityDecision(action: .hide, reason: "ptt-idle-hidden")
            }
            if !hasRealHardware {
                return VisibilityDecision(action: .visible, reason: "no-hardware-feedback")
            }
            if hasTemporaryHUD || hasLanguageIndicator {
                return VisibilityDecision(action: .preserveCurrentVisible, reason: "no-session-temporary")
            }
            return VisibilityDecision(action: .hide, reason: "no-session-hidden")
        }

        if dictationOnlyWithoutFocusHidden {
            if isSpeechExitBarsHoldActive {
                return VisibilityDecision(action: .speechBars, reason: "dictation-only-without-focus-exit-bars")
            }
            return VisibilityDecision(action: .hide, reason: "dictation-only-without-focus-hidden")
        }

        if isWakeGatedHiddenBeforeModeSelection {
            if isSpeechExitBarsHoldActive {
                return VisibilityDecision(action: .speechBars, reason: "wake-gated-before-mode-exit-bars")
            }
            return VisibilityDecision(action: .hide, reason: "wake-gated-before-mode-hidden")
        }

        return VisibilityDecision(action: .visible, reason: "normal-visible")
    }

    static func resolvedMode(
        shouldCollapseHandsFreeHUDToStandby: Bool,
        shouldShowProcessingDots: Bool,
        shouldShowRecognizingWhileDictating: Bool,
        effectiveDictating: Bool,
        shouldShowIdleAutoDictationHUD: Bool,
        lastTranscript: String
    ) -> HUDMode {
        if shouldCollapseHandsFreeHUDToStandby {
            return .standby
        }
        if shouldShowProcessingDots || shouldShowRecognizingWhileDictating {
            return .organizing
        }
        if effectiveDictating {
            return .dictation
        }
        if shouldShowIdleAutoDictationHUD {
            return .listening
        }
        if !lastTranscript.isEmpty {
            return .command
        }
        return .listening
    }

    static func resolvedMessage(
        mode: HUDMode,
        explicitMessage: String,
        lastTranscript: String,
        screenTypedText: String,
        isInputMutationActive: Bool,
        collapseToTwoState: Bool,
        suppressedCollapsedStatuses: Set<String> = []
    ) -> String {
        let trimmedExplicit = explicitMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        let remaining = remainingDictationHUDText(
            transcript: lastTranscript,
            screenTypedText: screenTypedText
        )

        guard collapseToTwoState else {
            switch mode {
            case .dictation:
                return remaining
            case .command:
                if !trimmedExplicit.isEmpty { return trimmedExplicit }
                return lastTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
            default:
                return trimmedExplicit
            }
        }

        let tail = displayedDictationHUDTail(from: remaining)
        let mutationFallbackText = tail.isEmpty && isInputMutationActive
            ? semanticHUDTailSlice(
                from: normalizedHUDMessageText(lastTranscript)
            )
            : ""

        switch mode {
        case .listening:
            return trimmedExplicit
        case .command:
            if !trimmedExplicit.isEmpty { return trimmedExplicit }
            if !tail.isEmpty { return tail }
            return lastTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        case .dictation, .organizing, .typing, .executing, .checking, .processing:
            if !tail.isEmpty { return tail }
            if !mutationFallbackText.isEmpty { return mutationFallbackText }
            if suppressedCollapsedStatuses.contains(trimmedExplicit) { return "" }
            return trimmedExplicit
        default:
            return trimmedExplicit
        }
    }

    static func remainingDictationHUDText(
        transcript: String,
        screenTypedText: String
    ) -> String {
        guard !transcript.isEmpty else { return "" }
        guard !screenTypedText.isEmpty else { return transcript }

        if transcript.hasPrefix(screenTypedText) {
            return String(transcript.dropFirst(screenTypedText.count))
        }

        let common = commonPrefixLen(screenTypedText, transcript)
        return common > 0 ? String(transcript.dropFirst(common)) : transcript
    }

    static func displayedDictationHUDTail(from remainingText: String) -> String {
        semanticHUDTailSlice(from: normalizedHUDMessageText(remainingText))
    }

    static func normalizedHUDMessageText(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func semanticHUDTailSlice(from tail: String) -> String {
        let preferredLength = 18
        let searchWindow = 34
        let minimumSemanticSegmentLength = 5
        guard tail.count > preferredLength else { return tail }

        let characters = Array(tail)
        let lowerBound = max(0, characters.count - searchWindow)
        let preferredBreakpointStart = max(lowerBound, characters.count - preferredLength)

        for index in stride(from: preferredBreakpointStart, through: lowerBound, by: -1) {
            guard isSemanticHUDTailBreakpoint(characters[index]) else { continue }
            let nextIndex = index + 1
            guard nextIndex < characters.count else { continue }
            let candidate = String(characters[nextIndex...]).trimmingCharacters(in: .whitespacesAndNewlines)
            if candidate.count >= minimumSemanticSegmentLength {
                return candidate
            }
        }

        return tail
    }

    static func isSemanticHUDTailBreakpoint(_ character: Character) -> Bool {
        switch character {
        case "，", "。", "！", "？", "；", "、", " ":
            return true
        default:
            return false
        }
    }

    static func commonPrefixLen(_ a: String, _ b: String) -> Int {
        var count = 0
        var ai = a.startIndex
        var bi = b.startIndex

        while ai < a.endIndex && bi < b.endIndex {
            if a[ai] != b[bi] {
                break
            }
            count += 1
            ai = a.index(after: ai)
            bi = b.index(after: bi)
        }

        return count
    }
}
