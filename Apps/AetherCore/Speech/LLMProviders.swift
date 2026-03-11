import Foundation

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
        let prompt = "Add punctuation and fix obvious dictation errors. Keep meaning. Output only the corrected text.\n\nText:\n\(text)"
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
        req.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")

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
