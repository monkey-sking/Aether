import Foundation
import os

/// Single-timer end-of-speech state machine.
/// Replaces: segmentTimer + micProgressTimer (EOS part) + tickContinuous EOS logic.
///
/// Usage:
///   1. Call start() when a recognition session begins.
///   2. Call noteVoiceActivity(true) from the audio VAD callback.
///   3. Call noteTranscriptChanged() whenever a non-empty partial arrives.
///   4. Call noteUtteranceStarted() when the first non-empty partial arrives.
///   5. Call stop() / noteUtteranceEnded() on session teardown or segment restart.
@MainActor
final class EOSDetector {

    // MARK: - Config (read from UserDefaults at start())
    var trailingSilenceMs: Double = 900
    var minUtteranceMs: Double = 450
    var maxUtteranceMs: Double = 15000
    var maxSegmentSec: Double = 32

    // MARK: - Callbacks
    var onEndOfSpeech: (() -> Void)?
    var onSegmentTimeout: (() -> Void)?
    var endOfSpeechDeferralMsProvider: (() -> Double?)?

    // MARK: - State
    private(set) var isActive: Bool = false
    private var timer: Timer?
    private var segmentStartedAt: Date = .distantPast
    private var lastSpeechAt: Date = .distantPast
    private var utteranceStartedAt: Date = .distantPast
    private var hasUtterance: Bool = false
    private var deferredEndOfSpeechUntil: Date?
    private var hasUsedEndOfSpeechDeferral: Bool = false
    private let log = GlobalLogger.speech

    // MARK: - Public API

    func start() {
        stop()
        segmentStartedAt = Date()
        isActive = true
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        isActive = false
        hasUtterance = false
        utteranceStartedAt = .distantPast
        lastSpeechAt = .distantPast
        deferredEndOfSpeechUntil = nil
        hasUsedEndOfSpeechDeferral = false
    }

    /// Called from audio VAD callback on each buffer.
    func noteVoiceActivity(_ active: Bool) {
        if active {
            lastSpeechAt = Date()
            deferredEndOfSpeechUntil = nil
        }
    }

    /// Called whenever the partial transcript changes.
    func noteTranscriptChanged() {
        guard hasUtterance else { return }
        // Transcript is still evolving, so treat this as fresh speech activity too.
        // This makes endpointing less sensitive to short VAD dropouts while the user
        // is still speaking a continuous sentence.
        lastSpeechAt = Date()
        deferredEndOfSpeechUntil = nil
    }

    /// Call when the first non-empty partial arrives (utterance has started).
    func noteUtteranceStarted() {
        if !hasUtterance {
            hasUtterance = true
            utteranceStartedAt = Date()
            deferredEndOfSpeechUntil = nil
            hasUsedEndOfSpeechDeferral = false
        }
    }

    /// Call after the utterance is finalized to reset utterance-level state.
    func noteUtteranceEnded() {
        hasUtterance = false
        utteranceStartedAt = .distantPast
        lastSpeechAt = .distantPast
        deferredEndOfSpeechUntil = nil
        hasUsedEndOfSpeechDeferral = false
    }

    // MARK: - Private

    private func tick() {
        guard isActive else { return }
        let now = Date()

        // Segment timeout — fires regardless of whether an utterance is in progress.
        let segmentAgeMs = now.timeIntervalSince(segmentStartedAt) * 1000.0
        if segmentAgeMs >= maxSegmentSec * 1000.0 {
            os_log("EOSDetector: segment timeout (%.0fms)", log: log, type: .info, segmentAgeMs)
            stop()
            onSegmentTimeout?()
            return
        }

        guard hasUtterance else { return }

        let utteranceAgeMs = now.timeIntervalSince(utteranceStartedAt) * 1000.0
        let silenceAgeMs = lastSpeechAt == .distantPast ? utteranceAgeMs
                                                        : now.timeIntervalSince(lastSpeechAt) * 1000.0

        if utteranceAgeMs >= maxUtteranceMs {
            os_log("EOSDetector: max utterance (%.0fms)", log: log, type: .info, utteranceAgeMs)
            stop()
            onEndOfSpeech?()
            return
        }

        guard utteranceAgeMs >= minUtteranceMs else { return }
        guard silenceAgeMs >= trailingSilenceMs else { return }

        if let deferredUntil = deferredEndOfSpeechUntil {
            guard now >= deferredUntil else { return }
            deferredEndOfSpeechUntil = nil
        } else if !hasUsedEndOfSpeechDeferral,
                  let extraMs = endOfSpeechDeferralMsProvider?(),
                  extraMs > 0 {
            hasUsedEndOfSpeechDeferral = true
            deferredEndOfSpeechUntil = now.addingTimeInterval(extraMs / 1000.0)
            os_log("EOSDetector: deferred EOS by %.0fms", log: log, type: .info, extraMs)
            return
        }

        os_log("EOSDetector: trailing silence (%.0fms silence, %.0fms utterance)",
               log: log, type: .info, silenceAgeMs, utteranceAgeMs)
        stop()
        onEndOfSpeech?()
    }
}
