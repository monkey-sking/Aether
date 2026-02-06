import Foundation
import AVFoundation
import Speech
import AppKit

enum VoiceIntent: Equatable {
    case clickLeft
    case clickRight
    case doubleClick
    case startPointer
    case stopPointer
    case recenter
    case setDwell(Bool)
    case undo
    case dictation(String)
    case unknown(String)
}

final class VoiceCommandRouter {
    func route(transcript raw: String) -> VoiceIntent {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .unknown(raw) }

        // Normalize: lowercase, remove common filler spaces.
        let s = trimmed.lowercased().replacingOccurrences(of: " ", with: "")

        if s.contains("撤销") || s == "undo" || s.contains("撤回") {
            return .undo
        }
        if s.contains("停止") || s.contains("暂停控制") || s == "stop" || s.contains("stop") {
            return .stopPointer
        }
        if s.contains("开始") || s.contains("继续") || s.contains("start") {
            return .startPointer
        }
        if s.contains("校准") || s.contains("居中") || s.contains("重置") || s.contains("recenter") {
            return .recenter
        }
        if s.contains("打开悬停") || s.contains("开启悬停") || s.contains("dwellon") {
            return .setDwell(true)
        }
        if s.contains("关闭悬停") || s.contains("关掉悬停") || s.contains("dwelloff") {
            return .setDwell(false)
        }

        if s.contains("右键") || s.contains("rightclick") || s.contains("context") {
            return .clickRight
        }
        if s.contains("双击") || s.contains("doubleclick") {
            return .doubleClick
        }
        if s.contains("点击") || s == "click" || s.contains("leftclick") {
            return .clickLeft
        }

        // Dictation heuristics: anything that looks like "输入xxx"
        if s.hasPrefix("输入") && trimmed.count > 2 {
            let start = trimmed.index(trimmed.startIndex, offsetBy: 2)
            return .dictation(String(trimmed[start...]).trimmingCharacters(in: .whitespacesAndNewlines))
        }

        // Default fallback: treat as dictation for MVP (better UX than "unknown").
        return .dictation(trimmed)
    }
}

protocol LLMProvider {
    func enhanceDictation(_ text: String) async throws -> String
    func interpretCommand(_ text: String) async throws -> VoiceIntent
}

// Minimal OpenAI-compatible provider (optional). For MVP we keep it behind a toggle.
final class OpenAICompatibleProvider: LLMProvider {
    struct Config {
        var endpoint: URL
        var apiKey: String
        var model: String
    }

    private let config: Config

    init(config: Config) {
        self.config = config
    }

    func enhanceDictation(_ text: String) async throws -> String {
        // Very small prompt; callers should handle timeouts and fallback.
        let prompt = "Add punctuation and fix obvious dictation errors. Keep meaning. Output only the corrected text.\\n\\nText:\\n\\(text)"
        return try await call(prompt: prompt)
    }

    func interpretCommand(_ text: String) async throws -> VoiceIntent {
        // For now, return unknown; command routing is handled locally for speed/reliability.
        _ = text
        return .unknown(text)
    }

    private func call(prompt: String) async throws -> String {
        var req = URLRequest(url: config.endpoint)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \\(config.apiKey)", forHTTPHeaderField: "Authorization")

        // OpenAI-compatible shape (chat/completions). We keep it generic.
        let body: [String: Any] = [
            "model": config.model,
            "messages": [
                ["role": "system", "content": "You are a helpful assistant."],
                ["role": "user", "content": prompt],
            ],
            "temperature": 0.2,
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, _) = try await URLSession.shared.data(for: req)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let choices = json?["choices"] as? [[String: Any]]
        let msg = choices?.first?["message"] as? [String: Any]
        let content = msg?["content"] as? String
        return content?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }
}

final class TextInjector {
    private(set) var lastInjectedAt: Date?

    func paste(_ text: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)

        // Cmd+V
        let source = CGEventSource(stateID: .combinedSessionState)
        let cmdKey: CGKeyCode = 55
        let vKey: CGKeyCode = 9

        let cmdDown = CGEvent(keyboardEventSource: source, virtualKey: cmdKey, keyDown: true)
        cmdDown?.flags = .maskCommand
        cmdDown?.post(tap: .cghidEventTap)

        let vDown = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: true)
        vDown?.flags = .maskCommand
        vDown?.post(tap: .cghidEventTap)

        let vUp = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: false)
        vUp?.flags = .maskCommand
        vUp?.post(tap: .cghidEventTap)

        let cmdUp = CGEvent(keyboardEventSource: source, virtualKey: cmdKey, keyDown: false)
        cmdUp?.post(tap: .cghidEventTap)

        lastInjectedAt = Date()
    }

    func undoPasteIfRecent(maxAgeSeconds: TimeInterval = 20) {
        guard let at = lastInjectedAt, Date().timeIntervalSince(at) <= maxAgeSeconds else { return }
        let source = CGEventSource(stateID: .combinedSessionState)
        let cmdKey: CGKeyCode = 55
        let zKey: CGKeyCode = 6

        let cmdDown = CGEvent(keyboardEventSource: source, virtualKey: cmdKey, keyDown: true)
        cmdDown?.flags = .maskCommand
        cmdDown?.post(tap: .cghidEventTap)

        let zDown = CGEvent(keyboardEventSource: source, virtualKey: zKey, keyDown: true)
        zDown?.flags = .maskCommand
        zDown?.post(tap: .cghidEventTap)

        let zUp = CGEvent(keyboardEventSource: source, virtualKey: zKey, keyDown: false)
        zUp?.flags = .maskCommand
        zUp?.post(tap: .cghidEventTap)

        let cmdUp = CGEvent(keyboardEventSource: source, virtualKey: cmdKey, keyDown: false)
        cmdUp?.post(tap: .cghidEventTap)
    }
}

@MainActor
final class SpeechManager: ObservableObject {
    @Published var status: String = "Idle"
    @Published var lastTranscript: String = ""
    @Published var isAlwaysListeningEnabled: Bool = false {
        didSet {
            if isAlwaysListeningEnabled {
                startContinuous()
            } else {
                stopContinuous()
            }
        }
    }
    @Published var isLLMEnhancementEnabled: Bool = false

    private let router = VoiceCommandRouter()
    private let injector = TextInjector()

    private var audioEngine: AVAudioEngine?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "zh-CN"))

    private var continuousTimer: Timer?
    private var lastChangeAt: Date?
    private var lastStableText: String = ""

    var onIntent: ((VoiceIntent) -> Void)?
    var llmProvider: LLMProvider?

    init() {
        NotificationCenter.default.addObserver(self, selector: #selector(pttDown), name: HeadMotionManager.pttDownNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(pttUp), name: HeadMotionManager.pttUpNotification, object: nil)
        requestPermissions()
    }

    private func requestPermissions() {
        SFSpeechRecognizer.requestAuthorization { [weak self] auth in
            DispatchQueue.main.async {
                switch auth {
                case .authorized:
                    self?.status = "Speech Authorized"
                case .denied:
                    self?.status = "Speech Denied"
                case .restricted:
                    self?.status = "Speech Restricted"
                case .notDetermined:
                    self?.status = "Speech Not Determined"
                @unknown default:
                    self?.status = "Speech Unknown"
                }
            }
        }
        AVCaptureDevice.requestAccess(for: .audio) { _ in }
    }

    @objc private func pttDown() {
        // Default: push-to-talk; can be extended to "wakeword" later.
        guard !isAlwaysListeningEnabled else { return }
        startOnce()
    }

    @objc private func pttUp() {
        guard !isAlwaysListeningEnabled else { return }
        stopAndFinalize()
    }

    func startOnce() {
        guard recognitionTask == nil else { return }
        guard let recognizer, recognizer.isAvailable else {
            status = "Speech Unavailable"
            return
        }

        let engine = AVAudioEngine()
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true

        let inputNode = engine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            request.append(buffer)
        }

        audioEngine = engine
        recognitionRequest = request
        lastTranscript = ""
        status = "Listening… (⌃⌥V)"

        do {
            engine.prepare()
            try engine.start()
        } catch {
            status = "Audio Start Failed: \\(error.localizedDescription)"
            cleanup()
            return
        }

        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }
            if let result {
                DispatchQueue.main.async {
                    let text = result.bestTranscription.formattedString
                    self.lastTranscript = text
                    self.lastChangeAt = Date()
                }
            }
            if error != nil {
                DispatchQueue.main.async {
                    self.status = "Speech Error"
                    self.stopAndFinalize()
                }
            }
        }
    }

    func stopAndFinalize() {
        guard recognitionTask != nil else { return }
        audioEngine?.stop()
        audioEngine?.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()

        let transcript = lastTranscript
        cleanup()

        status = "Processing…"
        handleTranscript(transcript)
    }

    private func startContinuous() {
        // Continuous mode: require a wake phrase to reduce accidental actions.
        status = "Listening… (Wake: “Aether …”)"
        startOnce()
        continuousTimer?.invalidate()
        continuousTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { [weak self] _ in
            self?.tickContinuous()
        }
    }

    private func stopContinuous() {
        continuousTimer?.invalidate()
        continuousTimer = nil
        stopAndFinalize()
    }

    private func tickContinuous() {
        guard isAlwaysListeningEnabled else { return }
        guard let lastChange = lastChangeAt else { return }
        guard !lastTranscript.isEmpty else { return }

        // If the transcript hasn't changed for a bit, treat it as an utterance boundary.
        if Date().timeIntervalSince(lastChange) < 1.0 { return }
        if lastStableText == lastTranscript { return }
        lastStableText = lastTranscript

        let text = lastTranscript
        lastTranscript = ""
        lastChangeAt = nil

        // Process, then restart the session to keep listening.
        stopAndFinalize()
        handleTranscript(text)
        if isAlwaysListeningEnabled {
            startOnce()
        }
    }

    private func cleanup() {
        recognitionTask = nil
        recognitionRequest = nil
        audioEngine = nil
    }

    private func handleTranscript(_ transcript: String) {
        let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        // Wake phrase gate for continuous mode.
        if isAlwaysListeningEnabled {
            let lower = trimmed.lowercased()
            let wakeEn = lower.hasPrefix("aether")
            let wakeZh = trimmed.hasPrefix("艾瑟") || trimmed.hasPrefix("以太")
            guard wakeEn || wakeZh else { return }

            // Strip wake word prefix.
            var remainder = trimmed
            if wakeEn {
                remainder = String(remainder.dropFirst(min(5, remainder.count))).trimmingCharacters(in: .whitespacesAndNewlines)
            } else if wakeZh {
                remainder = String(remainder.dropFirst(2)).trimmingCharacters(in: .whitespacesAndNewlines)
            }
            guard !remainder.isEmpty else { return }
            let intent = router.route(transcript: remainder)
            handleIntent(intent)
            return
        }

        let intent = router.route(transcript: trimmed)
        handleIntent(intent)
    }

    private func handleIntent(_ intent: VoiceIntent) {
        if case .dictation(let text) = intent, isLLMEnhancementEnabled, let llmProvider {
            Task {
                do {
                    let enhanced = try await llmProvider.enhanceDictation(text)
                    await MainActor.run {
                        self.injector.paste(enhanced.isEmpty ? text : enhanced)
                        self.status = "Pasted"
                    }
                } catch {
                    await MainActor.run {
                        self.injector.paste(text)
                        self.status = "Pasted (No LLM)"
                    }
                }
            }
            return
        }

        switch intent {
        case .undo:
            injector.undoPasteIfRecent()
            status = "Undo"
        case .dictation(let text):
            injector.paste(text)
            status = "Pasted"
        default:
            onIntent?(intent)
            status = "Done"
        }
    }

    func undoLastInjection() {
        injector.undoPasteIfRecent()
    }
}
