import Foundation
import Speech
import AVFoundation
import os

/// Manages SFSpeechRecognizer task lifecycle.
/// Key guarantee: onFinal fires for every isFinal result, regardless of calling mode.
/// The coordinator (SpeechManager) decides whether to process it.
@MainActor
final class RecognitionSession {

    // MARK: - Callbacks (called on main thread)
    var onPartial: ((String) -> Void)?
    var onFinal: ((String) -> Void)?
    /// isRecoverable = true for no-speech / cancelled errors; false for hard errors.
    var onError: ((Error, Bool) -> Void)?

    // MARK: - State
    private(set) var isRunning: Bool = false
    private var recognizer: SFSpeechRecognizer?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private let log = GlobalLogger.speech

    // MARK: - Public API

    func start(
        locale: Locale,
        autoPunctuation: Bool,
        contextualStrings: [String],
        prebuffered: [AVAudioPCMBuffer],
        taskHint: SFSpeechRecognitionTaskHint = .unspecified,
        preferOnDevice: Bool = false
    ) throws {
        cancel()

        guard let rec = SFSpeechRecognizer(locale: locale), rec.isAvailable else {
            throw RecognitionSessionError.unavailable
        }
        recognizer = rec

        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        req.taskHint = taskHint
        if #available(macOS 13, *) {
            req.addsPunctuation = autoPunctuation
        }
        if preferOnDevice, rec.supportsOnDeviceRecognition {
            req.requiresOnDeviceRecognition = true
        }
        req.contextualStrings = contextualStrings
        prebuffered.forEach { req.append($0) }
        request = req

        task = rec.recognitionTask(with: req) { [weak self] result, error in
            guard let self else { return }

            if let result = result {
                DispatchQueue.main.async {
                    let text = result.bestTranscription.formattedString
                    if result.isFinal {
                        self.isRunning = false
                        self.onFinal?(text)
                    } else {
                        self.onPartial?(text)
                    }
                }
            }

            if let error = error {
                DispatchQueue.main.async {
                    self.isRunning = false
                    let ns = error as NSError
                    let isCancelled = ns.code == 10 || ns.code == 216 || ns.code == 1700
                        || error.localizedDescription.contains("canceled")
                    let isNoSpeech = (ns.domain == "kAFAssistantErrorDomain" && ns.code == 203)
                        || error.localizedDescription.contains("No speech detected")
                    let isRecoverable = isCancelled || isNoSpeech
                    if !isCancelled {
                        self.onError?(error, isRecoverable)
                    }
                }
            }
        }

        isRunning = true
        os_log("RecognitionSession started (locale=%{public}@)", log: log, type: .info, locale.identifier)
    }

    /// Append a buffer from the audio tap to the active recognition request.
    func append(_ buffer: AVAudioPCMBuffer) {
        request?.append(buffer)
    }

    /// Signal end of audio and wait for the engine to emit isFinal.
    func finish() {
        request?.endAudio()
        task?.finish()
        os_log("RecognitionSession finish() called", log: log, type: .info)
    }

    /// Immediately cancel the recognition task.
    func cancel() {
        request?.endAudio()
        task?.cancel()
        task = nil
        request = nil
        recognizer = nil
        isRunning = false
    }
}

enum RecognitionSessionError: Error {
    case unavailable
}
