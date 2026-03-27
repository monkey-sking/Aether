import Foundation
import os

/// Manages streaming dictation input. Tracks what is actually on screen vs what the STT engine reports.
///
/// **Core Bug Fix**: The old `handleStreamingTyping` used an append-only strategy based on character count.
/// When Apple STT mid-stream corrected a word (e.g. "好吧" → "好啊"), the append-only approach
/// printed the correction as *new* characters, producing garbage like "好吧好啊".
///
/// New approach:
///   - `screenTypedText` tracks the characters actually injected into the target app.
///   - `onPartial` only appends when the new text is a strict extension of `screenTypedText`.
///   - If STT revised earlier words (text no longer starts with `screenTypedText`), we skip until `onFinal`.
///   - `onFinal` uses diff-based correction: find common prefix, delete excess, type remainder.
@MainActor
final class DictationHandler {

    // MARK: - State

    /// What we have actually typed on screen (ground truth).
    private(set) var screenTypedText: String = ""
    private(set) var isAwaitingPartialReconciliation: Bool = false
    private var targetPID: pid_t?
    private var currentUtteranceID: UUID = UUID()
    private var pendingPartialCorrectionText: String?
    private var pendingPartialCorrectionWorkItem: DispatchWorkItem?
    private var pendingAppendTargetText: String?
    private var appendPumpTask: Task<Void, Never>?
    private let injector: any TextInjecting
    private let log = GlobalLogger.speech
    private let appendLeadDelayNs: UInt64 = 150_000_000
    private let appendSmallBacklogIntervalNs: UInt64 = 150_000_000
    private let appendMediumBacklogIntervalNs: UInt64 = 120_000_000
    private let appendLargeBacklogIntervalNs: UInt64 = 90_000_000

    // MARK: - LLM Enhancement

    var llmProvider: LLMProvider?
    var isLLMEnhancementEnabled: Bool = false
    var llmProviderContext: String = "source=openai-compatible"
    var onStatusUpdate: ((String) -> Void)?

    // MARK: - Init

    init(injector: any TextInjecting) {
        self.injector = injector
    }

    // MARK: - Public API

    /// Call at the start of each utterance to reset tracking state.
    func reset(targetPID: pid_t?) {
        cancelPendingPartialCorrection()
        cancelAppendPump()
        self.screenTypedText = ""
        self.targetPID = targetPID
        self.currentUtteranceID = UUID()
    }

    /// Called for every partial (non-final) STT result.
    ///
    /// Only types new characters when the engine output is a strict extension of what's on screen.
    /// If STT revised earlier words, we do nothing—corrections happen in `onFinal`.
    func onPartial(_ text: String) {
        guard !text.isEmpty else { return }

        if text == screenTypedText {
            cancelPendingPartialCorrection()
            return
        }

        if text.hasPrefix(screenTypedText) {
            // Safe extension: engine output starts with everything we've already typed.
            cancelPendingPartialCorrection()
            queueAppend(to: text)
            return
        }

        cancelAppendPump()
        schedulePartialCorrection(to: text)
    }

    /// Called when isFinal fires or EOS is detected.
    /// Performs diff-based correction to sync screen with final text.
    func onFinal(_ text: String) async {
        let utteranceID = self.currentUtteranceID
        let corrected: String
        if isLLMEnhancementEnabled, !text.isEmpty {
            if let provider = llmProvider {
                do {
                    let enhanced = try await provider.enhanceDictation(text)
                    corrected = enhanced.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? text : enhanced
                } catch {
                    GlobalLogger.speech.error(
                        "[DictationLLM] failure phase=finalize textCount=\(text.count) targetPID=\(targetPID ?? 0) \(llmProviderContext) error=\(error.localizedDescription)"
                    )
                    corrected = text
                }
            } else {
                GlobalLogger.speech.error(
                    "[DictationLLM] failure phase=finalize textCount=\(text.count) targetPID=\(targetPID ?? 0) \(llmProviderContext) note=provider-unavailable"
                )
                corrected = text
            }
        } else {
            corrected = text
        }
        
        guard self.currentUtteranceID == utteranceID else {
            os_log("DictationHandler onFinal: utterance expired, dropping correction.", log: log, type: .info)
            return
        }
        cancelPendingPartialCorrection()
        cancelAppendPump()
        applyCorrection(corrected)
    }

    /// Synchronous finalization (no LLM). Used when LLM is disabled.
    func onFinalSync(_ text: String) {
        cancelPendingPartialCorrection()
        cancelAppendPump()
        applyCorrection(text)
    }

    // MARK: - Private

    private func setAwaitingPartialReconciliation(_ awaiting: Bool) {
        guard isAwaitingPartialReconciliation != awaiting else { return }
        isAwaitingPartialReconciliation = awaiting
        onStatusUpdate?(awaiting ? "speech.recognizing" : "speech.listening")
    }

    private func cancelPendingPartialCorrection() {
        pendingPartialCorrectionWorkItem?.cancel()
        pendingPartialCorrectionWorkItem = nil
        pendingPartialCorrectionText = nil
        setAwaitingPartialReconciliation(false)
    }

    private func cancelAppendPump() {
        appendPumpTask?.cancel()
        appendPumpTask = nil
        pendingAppendTargetText = nil
    }

    private func queueAppend(to text: String) {
        guard text.hasPrefix(screenTypedText) else { return }
        if let pendingAppendTargetText,
           pendingAppendTargetText.hasPrefix(text),
           pendingAppendTargetText.count > text.count {
            return
        }
        pendingAppendTargetText = text
        guard appendPumpTask == nil else { return }

        let utteranceID = currentUtteranceID
        appendPumpTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                self.appendPumpTask = nil
                if self.pendingAppendTargetText == self.screenTypedText {
                    self.pendingAppendTargetText = nil
                }
            }

            try? await Task.sleep(nanoseconds: self.appendLeadDelayNs)

            while !Task.isCancelled, self.currentUtteranceID == utteranceID {
                guard let target = self.pendingAppendTargetText else { break }
                guard target.hasPrefix(self.screenTypedText) else { break }
                guard target != self.screenTypedText else {
                    self.pendingAppendTargetText = nil
                    break
                }

                guard let nextChunk = self.nextAppendChunk(from: self.screenTypedText, toward: target) else {
                    self.pendingAppendTargetText = nil
                    break
                }

                self.injector.type(nextChunk, targetPID: self.targetPID)
                self.screenTypedText.append(nextChunk)
                self.emitHUDProgressUpdate()
                os_log(
                    "DictationHandler stream append step: +'%{public}@' (screen: %d chars / target: %d chars)",
                    log: self.log,
                    type: .info,
                    nextChunk,
                    self.screenTypedText.count,
                    target.count
                )

                let backlogCount = max(0, target.count - self.screenTypedText.count)
                try? await Task.sleep(nanoseconds: self.appendPumpIntervalNs(for: backlogCount))
            }
        }
    }

    private func nextAppendChunk(from current: String, toward target: String) -> String? {
        guard target.hasPrefix(current) else { return nil }
        let suffixStart = target.index(target.startIndex, offsetBy: current.count)
        guard suffixStart < target.endIndex else { return nil }
        let nextIndex = target.index(after: suffixStart)
        return String(target[suffixStart..<nextIndex])
    }

    private func emitHUDProgressUpdate() {
        onStatusUpdate?(isAwaitingPartialReconciliation ? "speech.recognizing" : "speech.listening")
    }

    private func appendPumpIntervalNs(for backlogCount: Int) -> UInt64 {
        switch backlogCount {
        case 0...2:
            return appendSmallBacklogIntervalNs
        case 3...6:
            return appendMediumBacklogIntervalNs
        default:
            return appendLargeBacklogIntervalNs
        }
    }

    private func schedulePartialCorrection(to text: String) {
        pendingPartialCorrectionWorkItem?.cancel()
        pendingPartialCorrectionText = text
        setAwaitingPartialReconciliation(true)
        let utteranceID = currentUtteranceID
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            guard self.currentUtteranceID == utteranceID else { return }
            guard self.pendingPartialCorrectionText == text else { return }
            self.pendingPartialCorrectionText = nil
            self.pendingPartialCorrectionWorkItem = nil
            self.setAwaitingPartialReconciliation(false)
            self.applyCorrection(text)
            os_log(
                "DictationHandler stream reconcile: '%{public}@' (screen: %d chars)",
                log: self.log,
                type: .info,
                text,
                self.screenTypedText.count
            )
        }
        pendingPartialCorrectionWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22, execute: workItem)
    }

    private func applyCorrection(_ finalText: String) {
        guard !finalText.isEmpty else { return }
        guard finalText != screenTypedText else { return }

        if finalText.hasPrefix(screenTypedText) {
            // Pure append (most common case).
            let suffix = String(finalText.dropFirst(screenTypedText.count))
            if !suffix.isEmpty {
                injector.type(suffix, targetPID: targetPID)
            }
        } else {
            // Diff correction: find common prefix, delete excess, type new content.
            let commonLen = commonPrefixLength(screenTypedText, finalText)
            let toDelete = screenTypedText.count - commonLen
            let toType = String(finalText.dropFirst(commonLen))

            if toDelete > 0 {
                injector.deleteBackward(count: toDelete, targetPID: targetPID)
                os_log("DictationHandler correction: delete %d chars", log: log, type: .info, toDelete)
            }
            if !toType.isEmpty {
                injector.type(toType, targetPID: targetPID)
                os_log("DictationHandler correction: type '%{public}@'", log: log, type: .info, toType)
            }
        }
        screenTypedText = finalText
        emitHUDProgressUpdate()
    }

    /// Find the length of the common prefix between two strings (by Character, not byte).
    private func commonPrefixLength(_ a: String, _ b: String) -> Int {
        var count = 0
        var ai = a.startIndex
        var bi = b.startIndex
        while ai < a.endIndex && bi < b.endIndex {
            if a[ai] != b[bi] { break }
            count += 1
            ai = a.index(after: ai)
            bi = b.index(after: bi)
        }
        return count
    }
}
