import Foundation
import AVFoundation
import Speech
import AppKit
import os.log
import ApplicationServices
import Combine

enum VoiceIntent: Equatable {
    case clickLeft
    case clickRight
    case doubleClick
    case startPointer
    case stopPointer
    case recenter
    case setDwell(Bool)
    case scroll(Int, Int) // dx, dy
    case scrollToWeb(String) // "top", "bottom"
    case dragStart
    case dragEnd
    case undo
    case paste
    case lockConnection
    case unlockConnection
    case dictation(String)
    case unknown(String)
}

final class VoiceCommandRouter {
    func route(transcript raw: String, isTypingMode: Bool = false) -> VoiceIntent {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .unknown(raw) }

        // Normalize: lowercase, remove common filler spaces.
        // We keep 'trimmed' for dictation content.
        let s = trimmed.lowercased().replacingOccurrences(of: " ", with: "")

        // --- Context-Aware Routing ---
        
        // 1. Force Command Mode: "指令", "Command"
        // e.g. "指令 点击" -> "点击" logic
        // We don't strip prefix yet for simplicity in matching, but we should probably bypass dictation check.
        let isForceCommand = s.hasPrefix("指令") || s.hasPrefix("command")

        // 2. Force Dictation Mode: "输入", "Type"
        // Already handled by existing check, but let's be explicit.
        let isForceDictation = s.hasPrefix("输入") || s.hasPrefix("Input") || s.hasPrefix("type") || s.hasPrefix("写")
        
        // 3. Typing Mode Default
        if isTypingMode && !isForceCommand {
            // In text field: default to dictation unless user said "Command..."
            // But we might want to check for "Input..." prefix to strip it?
            // Existing logic handles "Input..." stripping. 
            // Here, if just "Hello World", we return .dictation("Hello World")
            if !isForceDictation {
                return .dictation(trimmed)
            }
        }

        if s.contains("撤销") || s == "undo" || s.contains("撤回") {
            return .undo
        }
        if s.contains("粘贴") || s.contains("paste") {
            return .paste
        }
        if s.contains("锁定") || s.contains("lockairpods") || s.contains("lock") {
            return .lockConnection
        }
        if s.contains("解锁") || s.contains("unlockairpods") || s.contains("unlock") {
            return .unlockConnection
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
        if s.contains("点击") || s.contains("click") || s.contains("单击") {
            return .clickLeft
        }

        // Scroll / Drag
        if s.contains("向上") || s.contains("up") || s.contains("上滚") { return .scroll(0, -300) }
        if s.contains("向下") || s.contains("down") || s.contains("下滚") { return .scroll(0, 300) }
        if s.contains("到顶") || s.contains("top") { return .scrollToWeb("top") }
        if s.contains("到底") || s.contains("bottom") { return .scrollToWeb("bottom") }
        
        if s.contains("拖") || s.contains("drag") || s.contains("抓住") { return .dragStart }
        if s.contains("放") || s.contains("drop") || s.contains("松开") { return .dragEnd }

        if s.contains("写") || s.contains("input") || s.contains("type") || s.contains("输入") {
            // "type hello world" -> "hello world"
            let start = trimmed.index(trimmed.startIndex, offsetBy: 2)
            return .dictation(String(trimmed[start...]).trimmingCharacters(in: .whitespacesAndNewlines))
        }

        // --- Pinyin Fallback (for Homophones) ---
        // Solves "右键" (You Jian) vs "邮件" (You Jian)
        let py = trimmed.pinyin
        
        if py.contains("youjian") || py.contains("rightclick") { return .clickRight }
        if py.contains("zuo") && (py.contains("hua") || py.contains("yi")) { 
            // "左滑" (zuo hua), "左移" (zuo yi) -> maybe invalid? 
            // Let's stick to known commands.
        }
        
        // Check Pinyin for core commands if exact match failed
        if py.contains("dianji") || py.contains("danji") { return .clickLeft } // 点击/单击
        if py.contains("shuangji") { return .doubleClick } // 双击
        if py.contains("xiangshang") || py.contains("shanggun") { return .scroll(0, -300) } // 向上/上滚
        if py.contains("xiangxia") || py.contains("xiagun") { return .scroll(0, 300) } // 向下/下滚
        
        // Default fallback: treat as dictation for MVP (better UX than "unknown").
        return .dictation(trimmed)
    }
}

// MARK: - Pinyin Helper
extension String {
    var pinyin: String {
        // "你好" -> "nǐ hǎo" -> "ni hao" -> "nihao"
        return self
            .applyingTransform(.toLatin, reverse: false)?
            .applyingTransform(.stripDiacritics, reverse: false)?
            .lowercased()
            .replacingOccurrences(of: " ", with: "") ?? self.lowercased()
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
        AutomationOutputs.shared.pasteText(text)
        lastInjectedAt = Date()
    }

    func undoPasteIfRecent(maxAgeSeconds: TimeInterval = 20) {
        guard let at = lastInjectedAt, Date().timeIntervalSince(at) <= maxAgeSeconds else { return }
        AutomationOutputs.shared.undo()
    }
}

@MainActor
final class SpeechManager: ObservableObject {
    @Published var status: String = "Idle"
    @Published var lastTranscript: String = ""
    @Published var lastError: String = ""
    
    // --- New Features (Build 2170) ---
    @Published var activeLocale: Locale = Locale(identifier: "zh-CN") {
        didSet {
            // Reset recognizer so next session uses new locale
            recognizer = SFSpeechRecognizer(locale: activeLocale)
        }
    }
    
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
    @Published var isDictating: Bool = false // For HUD Feedback

    private let router = VoiceCommandRouter()
    private let injector = TextInjector()
    
    // Internal States
    private var lastStreamedText: String = ""
    private var stopTimer: Timer?
    private var failsafeTimer: Timer?
    private var audioRingBuffer: [AVAudioPCMBuffer] = []
    private let ringBufferCapacity = 10 // ~0.5s at 1024 frames/buffer

    private var audioEngine: AVAudioEngine?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    
    // Recognizer (Updated on locale change)
    private var recognizer: SFSpeechRecognizer? = SFSpeechRecognizer(locale: Locale(identifier: "zh-CN"))

    private var continuousTimer: Timer?
    private var lastChangeAt: Date?
    private var lastStableText: String = ""
    private var sessionGeneration: Int = 0 
    @Published var lastWakeTime: Date? // For context-aware wake window & UI feedback
    private var cancellables = Set<AnyCancellable>()

    private var isAwake: Bool {
        // Gaze Wake: if looking at screen AND tracking is active -> Awake
        // Note: HeadMotionManager is MainActor, ensure safe access.
        if HeadMotionManager.shared.isTracking && HeadMotionManager.shared.isLookingAtScreen {
            return true
        }

        guard let last = lastWakeTime else { return false }
        return Date().timeIntervalSince(last) < 8.0 
    }

    private var isTypingMode: Bool {
        // 1. Check System Wide Focus (Most Reliable)
        let systemWide = AXUIElementCreateSystemWide()
        var focusedElement: AnyObject?
        let result = AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &focusedElement)
        
        if result == .success, let element = focusedElement {
            let axElement = element as! AXUIElement
            
            // Check Role
            var role: AnyObject?
            if AXUIElementCopyAttributeValue(axElement, kAXRoleAttribute as CFString, &role) == .success,
               let roleString = role as? String {
                if roleString == kAXTextAreaRole || roleString == kAXTextFieldRole || roleString == "AXSearchField" || roleString == "AXComboBox" {
                    return true
                }
            }
            
            // Check Owner PID -> Bundle ID (for Siri/Spotlight exceptions)
            var pid: pid_t = 0
            AXUIElementGetPid(axElement, &pid)
            if let app = NSRunningApplication(processIdentifier: pid),
               let bundleId = app.bundleIdentifier {
                if bundleId == "com.apple.Siri" || bundleId == "com.apple.siri.launcher" || bundleId == "com.apple.Spotlight" {
                    return true
                }
            }
        }
        
        return false
    }

    var onIntent: ((VoiceIntent) -> Void)?
    var llmProvider: LLMProvider?

    private let log = OSLog(subsystem: "com.7fei.Aether", category: "Speech")
    
    // Helper to use NSLocalizedString which handles dynamic strings better than String(localized:)
    private func setStatus(_ key: String) {
        self.status = NSLocalizedString(key, comment: "")
    }

    @objc func toggleLanguage() {
        if activeLocale.identifier.starts(with: "zh") {
            activeLocale = Locale(identifier: "en-US")
        } else {
            activeLocale = Locale(identifier: "zh-CN")
        }
        status = "Language: \(activeLocale.identifier)"
        os_log("Switched Language to: %{public}@", log: log, type: .info, activeLocale.identifier)
        
        // Restart session if running (streaming context)
        if recognitionTask != nil {
            stopAndFinalize()
            startOnce() // Restart immediately with new locale
        }
    }

    func startOnce() {
        // [Stability] Cancel any existing task/timer to prevent stale state
        stopTimer?.invalidate()
        stopTimer = nil
        
        if recognitionTask != nil {
            recognitionTask?.cancel()
            recognitionTask = nil
        }

        guard let recognizer, recognizer.isAvailable else {
            status = NSLocalizedString("speech.unavailable", comment: "")
            lastError = "Speech recognizer unavailable"
            os_log("Error: Speech recognizer unavailable", log: log, type: .error)
            return
        }

        // Ensure Persistent Audio Engine is running
        do {
            try setupAudioEngine()
        } catch {
            status = NSLocalizedString("speech.error", comment: "") // Generic error for engine
            lastError = error.localizedDescription
            return
        }

        sessionGeneration += 1
        let currentGeneration = sessionGeneration
        
        // Reset Streaming State
        lastStreamedText = ""
        isDictating = isTypingMode // Set initial state based on context

        // [Stability] Reset Failsafe Timer (Stops recording after 60s max)
        failsafeTimer?.invalidate()
        failsafeTimer = Timer.scheduledTimer(withTimeInterval: 60.0, repeats: false) { [weak self] _ in
            os_log("Failsafe: Stopping session after 60s timeout.", log: GlobalLogger.speech, type: .error)
            Task { @MainActor in
                self?.stopAndFinalize()
            }
        }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        if #available(macOS 13, *) {
            request.addsPunctuation = true
        }
        // Important: Add contextual strings to improve specific command recognition
        request.contextualStrings = ["点击", "双击", "向下", "向上", "右键", "Click", "Double Click", "Scroll Down", "Scroll Up", "Right Click"]

        recognitionRequest = request
        lastTranscript = ""
        lastError = ""
        status = NSLocalizedString("speech.listening", comment: "") + " (\(activeLocale.identifier.starts(with: "zh") ? "中" : "En"))"
        os_log("Session Started (gen %d) Locale: %{public}@", log: log, type: .info, currentGeneration, activeLocale.identifier)
        
        // [Ring Buffer] Flush pre-buffered audio to catch the start of speech
        audioRingBuffer.forEach { recognitionRequest?.append($0) }
        
        // [HUD] Show immediate feedback
        HotkeyFeedbackHUD.showContinuous(message: NSLocalizedString("speech.listening", comment: ""), isListening: true, language: activeLocale.identifier.starts(with: "zh") ? "中" : "En", isDictating: isDictating)

        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }
            
            // [Streaming Dictation]
            // We process partial results for typing feedback
            if let result = result {
                DispatchQueue.main.async {
                    guard self.sessionGeneration == currentGeneration else { return }
                    let text = result.bestTranscription.formattedString
                    self.lastTranscript = text
                    self.lastChangeAt = Date()
                    
                    // Update HUD with live transcript
                    HotkeyFeedbackHUD.showContinuous(message: text.isEmpty ? NSLocalizedString("speech.listening", comment: "") : text, isListening: true, language: self.activeLocale.identifier.starts(with: "zh") ? "中" : "En", isDictating: self.isDictating)
                    
                    // Handle Streaming Typing (if in typing mode)
                    if self.isTypingMode && !result.isFinal {
                        self.handleStreamingTyping(currentText: text)
                    }
                }
            }
            
            if let error = error {
                DispatchQueue.main.async {
                    guard self.sessionGeneration == currentGeneration else { return }
                    
                    // Check if error is just "No speech" or "Cancelled"
                    let nsError = error as NSError
                    let isNoSpeechError = (nsError.domain == "kAFAssistantErrorDomain" && nsError.code == 203) 
                        || error.localizedDescription.contains("No speech detected")
                    let isCancelled = (nsError.domain == "kAFAssistantErrorDomain" && (nsError.code == 216 || nsError.code == 1700)) 
                        || (nsError.domain == "SFSpeechErrorDomain" && nsError.code == 10) // 10 = cancelled
                        || error.localizedDescription.contains("canceled")
                    
                    // Ignore cancellations (intentional stops)
                    if isCancelled {
                        self.stopAndFinalize()
                        return
                    }

                    // [No Speech Handling]
                    // If no speech is detected, we should NOT show an error in Continuous Mode.
                    // Instead, we just loop back (restart) silently.
                    if isNoSpeechError {
                        os_log("No Speech Detected (Timeout). Resetting...", log: self.log, type: .info)
                        self.stopAndFinalize()
                        // If continuous mode is on, logic elsewhere (e.g. stopContinuous/startContinuous or manual restart) 
                        // might need to be triggered. 
                        // Actually, `stopAndFinalize` stops the engine.
                        // In `startContinuous`, we use a timer to restart? No, we use `continuousTimer` for TICKs.
                        // But if the engine errors out, we need to restart it if `isAlwaysListeningEnabled`.
                        
                        if self.isAlwaysListeningEnabled {
                             DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                 // Auto-restart for continuous listening
                                 self.startOnce()
                             }
                        }
                        return
                    }

                    self.status = NSLocalizedString("speech.error", comment: "")
                    self.lastError = error.localizedDescription
                    os_log("Recognition Error: %{public}@", log: self.log, type: .error, error.localizedDescription)
                    self.stopAndFinalize()
                }
            }
        }
    }
    
    // [Streaming Logic]
    private func handleStreamingTyping(currentText: String) {
        // Compare with lastStreamedText
        // Find common prefix
        let commonPrefix = currentText.commonPrefix(with: lastStreamedText)
        
        // Backspace distinct suffix of lastStreamedText
        let backspaceCount = lastStreamedText.count - commonPrefix.count
        if backspaceCount > 0 {
            AutomationOutputs.shared.backspace(count: backspaceCount)
        }
        
        // Type new suffix
        let newSuffix = String(currentText.dropFirst(commonPrefix.count))
        if !newSuffix.isEmpty {
            // Use typeText for reliable, clipboard-safe injection
            AutomationOutputs.shared.typeText(newSuffix)
        }
            // Ideally we need `typeText` (keystrokes).
            // But `AutomationOutput` only has `pasteText`.
            // Let's assume `pasteText` is acceptable for now (chunks).
        

        lastStreamedText = currentText
    }

    private func setupAudioEngine() throws {
        if let engine = audioEngine, engine.isRunning { return }
        

        
        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        
        // Enable Voice Processing IO (Echo Cancellation + HFP handling)
        // This is critical for AirPods to work in bidirectional mode on macOS.
        if #available(macOS 10.15, *) {
            do {
                try inputNode.setVoiceProcessingEnabled(true)
                os_log("Voice Processing IO enabled.", log: log, type: .info)
            } catch {
                os_log("Failed to enable Voice Processing IO: %{public}@", log: log, type: .error, error.localizedDescription)
            }
        }

        let format = inputNode.outputFormat(forBus: 0)
        
        if format.sampleRate == 0 {
             os_log("Error: Input Node Sample Rate is 0", log: log, type: .error)
        } else {
             os_log("Input Format: %{public}@", log: log, type: .info, format.description)
        }
        
        // Remove existing tap if any (to be safe)
        inputNode.removeTap(onBus: 0)
        
        // Use NATIVE format for Tap (avoid Error -10875)
        // Manual downmix to Mono inside the block.
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: nil) { [weak self] buffer, _ in
             guard let self = self else { return }
             
             // Check if we need to downmix (if channels > 1)
             let format = buffer.format
             if format.channelCount > 1 {
                 // Create Mono Format with SAME sample rate
                 if let monoFormat = AVAudioFormat(commonFormat: format.commonFormat, sampleRate: format.sampleRate, channels: 1, interleaved: false),
                    let monoBuffer = AVAudioPCMBuffer(pcmFormat: monoFormat, frameCapacity: buffer.frameCapacity) {
                     
                     monoBuffer.frameLength = buffer.frameLength
                     
                     // Copy Channel 0 to Mono Buffer
                     // (Assuming Ch0 contains the voice data, as seen in logs)
                     if let srcData = buffer.floatChannelData?[0],
                        let dstData = monoBuffer.floatChannelData?[0] {
                         memcpy(dstData, srcData, Int(buffer.frameLength) * MemoryLayout<Float>.size)
                     }
                     
                     // Calculate RMS
                     var rms: Float = 0
                     if let channelData = monoBuffer.floatChannelData?[0] {
                         let channelDataPtr = UnsafeBufferPointer(start: channelData, count: Int(monoBuffer.frameLength))
                         var sum: Float = 0
                         for sample in channelDataPtr {
                             sum += sample * sample
                         }
                         rms = sqrt(sum / Float(monoBuffer.frameLength))
                     }
                     
                     // Update HUD with audio level
                     // RMS is usually very small (0.0 - 0.5 for normal speech). 
                     // We map it for visual feedback.
                     HotkeyFeedbackHUD.shared.updateAudioLevel(rms)
                     
                     if Int.random(in: 0...50) == 0 {
                          os_log("Audio RMS: %.4f", log: self.log, type: .debug, rms)
                     }
                                          self.recognitionRequest?.append(monoBuffer)
                      
                      // Update Ring Buffer (Main Thread for safety)
                      DispatchQueue.main.async { [weak self] in
                          guard let self = self else { return }
                          self.audioRingBuffer.append(monoBuffer)
                          if self.audioRingBuffer.count > self.ringBufferCapacity {
                              self.audioRingBuffer.removeFirst()
                          }
                      }
                      return
                 }
             }
             
             // Fallback: Use original buffer
             self.recognitionRequest?.append(buffer)
        }
        
        audioEngine = engine
        engine.prepare()
        try engine.start()
        os_log("Persistent Audio Engine STARTED.", log: log, type: .info)
    }

    func stopAndFinalize() {
        HotkeyFeedbackHUD.hide()
        guard recognitionTask != nil else { return }
        // STOP REQUEST ONLY. Keep engine running.
        
        // Stop appending audio to this request (handled by nil check in tap block)
        // But explicit endAudio is good practice.
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()

        let transcript = lastTranscript
        
        // Cleanup request objects
        recognitionTask = nil
        recognitionRequest = nil

        status = "Processing…"
        os_log("Session Ended. Final Transcript: '%{public}@'", log: log, type: .default, transcript)
        handleTranscript(transcript)
    }
    
    // Explicit teardown if needed (e.g. app quit)
    func teardownEngine() {
        audioEngine?.stop()
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine = nil
    }



    init() {
        GlobalLogger.lifecycle.info("SpeechManager Initialized")
        NotificationCenter.default.addObserver(self, selector: #selector(pttDown), name: HeadMotionManager.pttDownNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(pttUp), name: HeadMotionManager.pttUpNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(toggleLanguage), name: Notification.Name("AetherToggleLanguage"), object: nil)

        // Gaze Wake Feedback
        HeadMotionManager.shared.$isLookingAtScreen
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isLooking in
                if isLooking && HeadMotionManager.shared.isTracking {
                    self?.playWakeSound()
                }
            }
            .store(in: &cancellables)
            
        requestPermissions()
    }

    private func playWakeSound() {
        NSSound(named: "Tink")?.play()
    }

    private func requestPermissions() {
        GlobalLogger.speech.info("Requesting Permissions")
        SFSpeechRecognizer.requestAuthorization { [weak self] auth in
            DispatchQueue.main.async {
                guard let self = self else { return }
                switch auth {
                case .authorized:
                    self.status = "Speech Authorized"
                    GlobalLogger.speech.info("Permission Granted: Authorized")
                case .denied:
                    self.status = "Speech Denied"
                    GlobalLogger.speech.error("Permission Denied")
                case .restricted:
                    self.status = "Speech Restricted"
                    GlobalLogger.speech.error("Permission Restricted")
                case .notDetermined:
                    self.status = "Speech Not Determined"
                    GlobalLogger.speech.info("Permission Not Determined")
                @unknown default:
                    self.status = "Speech Unknown"
                    GlobalLogger.speech.error("Permission Unknown")
                }
            }
        }
        AVCaptureDevice.requestAccess(for: .audio) { granted in
            GlobalLogger.speech.info("Microphone Permission: \(granted ? "Granted" : "Denied")")
        }
    }

    @objc private func pttDown() {
        GlobalLogger.input.info("PTT DOWN")
        // Default: push-to-talk; can be extended to "wakeword" later.
        guard !isAlwaysListeningEnabled else { return }
        startOnce()
    }

    @objc private func pttUp() {
        GlobalLogger.input.info("PTT UP")
        guard !isAlwaysListeningEnabled else { return }
        
        // [Trailing Audio]
        // Delay stopping for 0.6s to catch the last syllable.
        // User reports "dropped last char".
        stopTimer?.invalidate()
        stopTimer = Timer.scheduledTimer(withTimeInterval: 0.6, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.stopAndFinalize()
            }
        }
    }

    private func startContinuous() {
        // Continuous mode: require a wake phrase to reduce accidental actions.
        status = NSLocalizedString("speech.listening", comment: "") + " (Wake: “Aether/艾瑟”)"
        os_log("Starting Continuous Mode (Wake Word Required)", log: log, type: .default)
        startOnce()
        continuousTimer?.invalidate()
        if isAlwaysListeningEnabled {
            continuousTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    self?.tickContinuous()
                }
            }
        }
    }

    private func stopContinuous() {
        os_log("Stopping Continuous Mode", log: log, type: .default)
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

        os_log("End of utterance detected: '%{public}@'", log: log, type: .default, text)

        // Stop current session WITHOUT processing (we handle it ourselves below).
        teardownSession()
        handleTranscript(text)
        if isAlwaysListeningEnabled {
            startOnce()
        }
    }

    /// Stops the audio engine and recognition task without processing the transcript.
    /// Used by `tickContinuous()` which handles transcript processing separately.
    private func teardownSession() {
        guard recognitionTask != nil else { return }
        os_log("Ending session (no-process)...", log: log, type: .info)
        // Only stop request/task
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        cleanup()
    }

    private func cleanup() {
        recognitionTask = nil
        recognitionRequest = nil
        stopTimer?.invalidate()
        stopTimer = nil
        failsafeTimer?.invalidate()
        failsafeTimer = nil
        isDictating = false
        // Engine NOT cleared
    }

    private func handleTranscript(_ transcript: String) {
        let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { 
            os_log("Transcript empty, ignoring.", log: log, type: .debug)
            return 
        }

        var textToRoute = trimmed
        var wakeWordDetected = false

        if isAlwaysListeningEnabled {
            let lower = trimmed.lowercased()
            let clean = lower.filter { !$0.isPunctuation }
            
            let wakeEn = clean.hasPrefix("aether") || clean.hasPrefix("ether") || clean.hasPrefix("heyaether") || clean.hasPrefix("hey") || clean.hasPrefix("hi")
            let wakeZh = trimmed.contains("艾瑟") || trimmed.contains("以太") || trimmed.contains("掉色") || trimmed.contains("艾色") || trimmed.contains("嘿") || trimmed.contains("喂")
            
            let isAwakeWindow = isAwake
            
            if isAwakeWindow {
                // Currently in active window.
                // Check if user said wake word anyway (e.g. "Aether click")
                if wakeEn || wakeZh {
                    textToRoute = stripWakeWord(from: trimmed)
                    wakeWordDetected = true
                    playWakeSound()
                } else {
                    // No wake word, but allowed due to active window
                    textToRoute = trimmed
                }
            } else {
                // Idle state: Must have wake word
                if wakeEn || wakeZh {
                    textToRoute = stripWakeWord(from: trimmed)
                    wakeWordDetected = true
                    playWakeSound()
                    os_log("Wake Word Detected! Entering active commands window.", log: log, type: .default)
                } else {
                     os_log("Ignored (No Wake Word): '%{public}@'", log: log, type: .default, trimmed)
                     return 
                }
            }
        } else {
            // PTT Mode: No wake word needed, route as is
            os_log("Processing PTT Command: '%{public}@'", log: log, type: .default, trimmed)
        }
        
        let typingContext = isTypingMode
        if typingContext {
            os_log("Context: Typing Mode Detected", log: log, type: .info)
        }

        let intent = router.route(transcript: textToRoute, isTypingMode: typingContext)
        
        // Update Wake Time
        if wakeWordDetected {
            lastWakeTime = Date()
        } else if case .unknown = intent {
            // If unknown command in wake window, do NOT extend window? 
            // Or maybe we do, to allow retries? 
            // Let's say we don't extend on unknown, to let it expire if it was just noise.
        } else {
            // Valid command executed -> extend wake window
            lastWakeTime = Date()
        }
        
        handleIntent(intent)
    }

    private func stripWakeWord(from text: String) -> String {
        var remainder = text
        // Simple heuristic stripping
        let prefixes = ["Aether", "Ether", "Hey Aether", "Hey", "Hi", "艾瑟", "以太", "掉色", "艾色", "嘿", "喂"]
        // Try longest prefix first? 
        // Or just checking ranges.
        // Simplified approach: find range of keywords.
        // Since we already know it matched, let's try to remove the first occurrence.
        
        for key in prefixes {
            if let range = remainder.range(of: key, options: [.caseInsensitive, .diacriticInsensitive]) {
                // Only if it's at the start or very close
                if range.lowerBound < remainder.index(remainder.startIndex, offsetBy: 5) {
                    remainder.removeSubrange(remainder.startIndex..<range.upperBound)
                    return remainder.trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }
        }
        return remainder
    }

    private func handleIntent(_ intent: VoiceIntent) {
        os_log("Routing Intent: %{public}@", log: log, type: .default, String(describing: intent))
        
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
            status = NSLocalizedString("speech.undo", comment: "")
        case .paste:
            AutomationOutputs.shared.pasteFromClipboard()
            status = "Pasted (Cmd+V)"
        case .dictation(let text):
            // If we were streaming, the text is already on screen (via typeText).
            // Do NOT paste again unless we weren't in typing mode (e.g. forced dictation command).
            if isTypingMode {
                status = NSLocalizedString("speech.done", comment: "")
            } else {
                injector.paste(text)
                self.status = NSLocalizedString("speech.pasted", comment: "")
            }
        default:
            onIntent?(intent)
            self.status = NSLocalizedString("speech.done", comment: "")
        }
    }

    func undoLastInjection() {
        injector.undoPasteIfRecent()
    }
}

// MARK: - Global Logger (Merged)

enum GlobalLogger {
    private static let subsystem = "com.7fei.Aether"

    static let speech = OSLog(subsystem: subsystem, category: "Speech")
    static let lifecycle = OSLog(subsystem: subsystem, category: "Lifecycle")
    static let input = OSLog(subsystem: subsystem, category: "Input")

    static func log(_ message: String, log: OSLog, type: OSLogType = .default) {
        // Always print to stderr for immediate terminal feedback.
        // We use a simplified category extraction for the stderr print.
        let category: String
        if log === speech { category = "Speech" }
        else if log === lifecycle { category = "Lifecycle" }
        else if log === input { category = "Input" }
        else { category = "Aether" }

        let formatted = "\(Date()) [\(category)] \(message)\n"
        fputs(formatted, stderr)
        
        // Also log to system console
        os_log("%{public}@", log: log, type: type, message)
    }
}

extension OSLog {
    func info(_ message: String) {
        GlobalLogger.log(message, log: self, type: .info)
    }
    func error(_ message: String) {
        GlobalLogger.log(message, log: self, type: .error)
    }
    func debug(_ message: String) {
        GlobalLogger.log(message, log: self, type: .debug)
    }
}
