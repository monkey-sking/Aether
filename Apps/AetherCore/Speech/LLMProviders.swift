import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

enum TextRewriteScope: String, Codable, Sendable {
    case fullDocument
}

enum TextRewriteMode: String, Codable, Sendable {
    case proofreadAndPolish

    func actionTitle(isChinese: Bool) -> String {
        switch self {
        case .proofreadAndPolish:
            return isChinese ? "全文纠错优化" : "Polish Full Text"
        }
    }
}

enum TextRewriteFailureReason: String, Codable, Sendable {
    case noInputTarget
    case unsupportedTarget
    case llmUnavailable
    case sourceEmpty
    case sourceTooLong
    case providerFailed
    case focusChanged
    case inputInvalid
    case commitFailed
}

struct TextRewriteIntentPayload: Equatable, Sendable {
    var scope: TextRewriteScope
    var mode: TextRewriteMode
    var sourceText: String?
    var resultText: String?
    var failureReason: TextRewriteFailureReason?

    init(
        scope: TextRewriteScope,
        mode: TextRewriteMode,
        sourceText: String? = nil,
        resultText: String? = nil,
        failureReason: TextRewriteFailureReason? = nil
    ) {
        self.scope = scope
        self.mode = mode
        self.sourceText = sourceText
        self.resultText = resultText
        self.failureReason = failureReason
    }
}

enum ASRExpertTone: String, Codable, CaseIterable, Sendable {
    case preserveSpoken
    case formal
    case directive

    var promptDescription: String {
        switch self {
        case .preserveSpoken:
            return "Keep the spoken tone and rhythm. Only fix ASR errors, punctuation, and obvious grammar issues."
        case .formal:
            return "Rewrite into clear formal prose suitable for documents, email, or polished notes."
        case .directive:
            return "Rewrite into concise action-oriented instructions while preserving the original intent."
        }
    }
}

struct ASRExpertProfile: Codable, Equatable, Sendable {
    var isEnabled: Bool
    var domain: String
    var tone: ASRExpertTone
    var glossaryText: String
    var extraInstructions: String

    init(
        isEnabled: Bool = false,
        domain: String = "",
        tone: ASRExpertTone = .preserveSpoken,
        glossaryText: String = "",
        extraInstructions: String = ""
    ) {
        self.isEnabled = isEnabled
        self.domain = domain
        self.tone = tone
        self.glossaryText = glossaryText
        self.extraInstructions = extraInstructions
    }
}

protocol LLMProvider {
    func enhanceDictation(_ text: String) async throws -> String
    func rewriteText(_ text: String, mode: TextRewriteMode) async throws -> String
    func interpretCommand(_ text: String) async throws -> VoiceIntent
}

protocol LLMHealthCheckProvider: LLMProvider {
    func testConfiguration() async throws
}

enum LLMServiceSource: String, Codable, CaseIterable, Hashable, Sendable {
    case appleOnDevice
    case openAICompatible

    var logValue: String {
        switch self {
        case .appleOnDevice:
            return "apple-on-device"
        case .openAICompatible:
            return "openai-compatible"
        }
    }
}

struct AppleOnDeviceLLMConfig: Equatable, Sendable {
    var rewriteProfile: ASRExpertProfile?
    var contextualGlossaryText: String?
    var localeIdentifier: String
}

enum LLMProviderConfiguration: Sendable {
    case appleOnDevice(AppleOnDeviceLLMConfig)
    case openAICompatible(OpenAICompatibleProvider.Config)
}

enum AppleOnDeviceLLMAvailability: Equatable, Sendable {
    case available
    case requiresMacOS26
    case deviceNotEligible
    case appleIntelligenceDisabled
    case modelNotReady
    case unsupportedLocale

    var logValue: String {
        switch self {
        case .available:
            return "available"
        case .requiresMacOS26:
            return "requires-macos-26"
        case .deviceNotEligible:
            return "device-not-eligible"
        case .appleIntelligenceDisabled:
            return "apple-intelligence-disabled"
        case .modelNotReady:
            return "model-not-ready"
        case .unsupportedLocale:
            return "unsupported-locale"
        }
    }

    func statusTitle(isChinese: Bool) -> String {
        switch self {
        case .available:
            return isChinese ? "本机可用" : "Available"
        case .requiresMacOS26:
            return isChinese ? "系统过低" : "Needs macOS 26"
        case .deviceNotEligible:
            return isChinese ? "设备不支持" : "Unsupported Device"
        case .appleIntelligenceDisabled:
            return isChinese ? "未开启" : "Disabled"
        case .modelNotReady:
            return isChinese ? "模型未就绪" : "Model Not Ready"
        case .unsupportedLocale:
            return isChinese ? "语言未支持" : "Unsupported Locale"
        }
    }

    func detail(isChinese: Bool, localeName: String? = nil) -> String {
        switch self {
        case .available:
            return isChinese
                ? "Apple 本地模型可用，不需要 API Key，也不需要服务地址。"
                : "Apple on-device rewrite is available. No API key or endpoint is required."
        case .requiresMacOS26:
            return isChinese
                ? "Apple 本地模型需要 macOS 26 或更高版本。"
                : "Apple on-device rewrite requires macOS 26 or later."
        case .deviceNotEligible:
            return isChinese
                ? "当前设备不支持 Apple Intelligence，本地改写不可用。"
                : "This device is not eligible for Apple Intelligence, so on-device rewrite is unavailable."
        case .appleIntelligenceDisabled:
            return isChinese
                ? "请先在系统设置里启用 Apple Intelligence。"
                : "Enable Apple Intelligence in System Settings first."
        case .modelNotReady:
            return isChinese
                ? "Apple 本地模型还没准备好，稍后再试。"
                : "The Apple on-device model is not ready yet. Try again later."
        case .unsupportedLocale:
            if let localeName, !localeName.isEmpty {
                return isChinese
                    ? "Apple 本地模型暂不支持当前语音语言：\(localeName)。"
                    : "Apple on-device rewrite does not currently support the active speech language: \(localeName)."
            }
            return isChinese
                ? "Apple 本地模型暂不支持当前语音语言。"
                : "Apple on-device rewrite does not currently support the active speech language."
        }
    }
}

enum AppleOnDeviceLLMError: LocalizedError {
    case unavailable(AppleOnDeviceLLMAvailability, localeName: String?)
    case generationFailed(String)

    var errorDescription: String? {
        switch self {
        case .unavailable(let availability, let localeName):
            return availability.detail(isChinese: AppLocalization.isChinese, localeName: localeName)
        case .generationFailed(let message):
            return message
        }
    }
}

enum LLMProviderError: LocalizedError {
    case invalidResponse(preview: String? = nil)
    case backendStatus(code: Int, message: String)
    case noModelsReturned
    case requestTimedOut

    var errorDescription: String? {
        switch self {
        case .invalidResponse(let preview):
            let base = AppLocalization.isChinese
                ? "服务返回了无法识别的数据"
                : "The service returned an invalid response"
            guard let preview, !preview.isEmpty else {
                return base
            }
            return AppLocalization.isChinese
                ? "\(base)：\(preview)"
                : "\(base): \(preview)"
        case .backendStatus(_, let message):
            return message
        case .noModelsReturned:
            return AppLocalization.isChinese ? "服务没有返回可用模型" : "The service returned no available models"
        case .requestTimedOut:
            return AppLocalization.isChinese ? "请求超时，请检查服务地址或稍后重试" : "The request timed out. Check the endpoint or try again later."
        }
    }
}

// Minimal OpenAI-compatible provider (optional). For MVP we keep it behind a toggle.
final class OpenAICompatibleProvider: LLMHealthCheckProvider {
    struct Config: Equatable, Sendable {
        var endpoint: URL
        var apiKey: String
        var model: String
        var rewriteProfile: ASRExpertProfile?
        var contextualGlossaryText: String?
    }

    enum RequestFlavor: Equatable {
        case chatCompletions
        case completions
        case responses
        case lmStudioChat
    }

    struct EndpointDescriptor: Equatable {
        var url: URL
        var flavor: RequestFlavor
    }

    private struct ResponseEnvelope {
        var data: Data
        var statusCode: Int
        var contentType: String?
    }

    static let defaultEndpointString = "https://api.openai.com/v1/chat/completions"
    private static let modelListTimeout: TimeInterval = 12
    private static let testConnectionTimeout: TimeInterval = 15
    private static let dictationTimeout: TimeInterval = 10
    private static let rewriteTimeout: TimeInterval = 35

    private let config: Config

    init(config: Config) {
        self.config = config
    }

    var resolvedConfig: Config {
        config
    }

    var configuredModel: String {
        config.model
    }

    static func makeConfig(
        endpointString: String,
        apiKey: String,
        model: String,
        rewriteProfile: ASRExpertProfile? = nil,
        contextualGlossaryText: String? = nil
    ) -> Config? {
        let trimmedEndpoint = endpointString.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty, !trimmedModel.isEmpty,
              let endpoint = URL(string: trimmedEndpoint),
              !trimmedEndpoint.isEmpty else {
            return nil
        }
        return Config(
            endpoint: endpoint,
            apiKey: trimmedKey,
            model: trimmedModel,
            rewriteProfile: rewriteProfile,
            contextualGlossaryText: contextualGlossaryText
        )
    }

    static func makeFromEnvironment(
        processInfo: ProcessInfo = .processInfo
    ) -> OpenAICompatibleProvider? {
        let env = processInfo.environment

        let endpointString = env["AETHER_LLM_ENDPOINT"]
            ?? env["OPENAI_BASE_URL"]
            ?? defaultEndpointString

        guard let config = makeConfig(
            endpointString: endpointString,
            apiKey: env["AETHER_LLM_API_KEY"] ?? env["OPENAI_API_KEY"] ?? "",
            model: env["AETHER_LLM_MODEL"] ?? env["OPENAI_MODEL"] ?? "",
            rewriteProfile: nil,
            contextualGlossaryText: nil
        ) else {
            return nil
        }

        return OpenAICompatibleProvider(config: config)
    }

    func enhanceDictation(_ text: String) async throws -> String {
        let prompt = Self.dictationPrompt(
            text: text,
            profile: config.rewriteProfile,
            contextualGlossaryText: config.contextualGlossaryText
        )
        return try await call(
            prompt: prompt,
            temperature: 0,
            timeout: Self.dictationTimeout
        )
    }

    func rewriteText(_ text: String, mode: TextRewriteMode) async throws -> String {
        let prompt = Self.rewritePrompt(
            text: text,
            mode: mode,
            profile: config.rewriteProfile,
            contextualGlossaryText: config.contextualGlossaryText
        )
        return try await call(prompt: prompt, timeout: Self.rewriteTimeout)
    }

    func interpretCommand(_ text: String) async throws -> VoiceIntent {
        // For now, return unknown; command routing is handled locally for speed/reliability.
        _ = text
        return .unknown(text)
    }

    func testConnection() async throws {
        let response = try await call(
            prompt: "Reply with OK only.",
            temperature: 0,
            maxTokens: 8,
            timeout: Self.testConnectionTimeout
        )
        if response.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw LLMProviderError.invalidResponse()
        }
    }

    func testConfiguration() async throws {
        try await testConnection()
    }

    func fetchAvailableModels() async throws -> [String] {
        var req = authorizedRequest(
            url: Self.modelsEndpoint(from: config.endpoint),
            timeout: Self.modelListTimeout
        )
        req.httpMethod = "GET"
        let response = try await perform(req)
        GlobalLogger.speech.info(
            "[LLM] models success url=\(req.url?.absoluteString ?? "nil") status=\(response.statusCode) contentType=\(response.contentType ?? "nil") preview=\(Self.responsePreview(from: response.data) ?? "nil")"
        )
        return try Self.parseModelList(from: response.data)
    }

    static func dictationPrompt(
        text: String,
        profile: ASRExpertProfile?,
        contextualGlossaryText: String? = nil
    ) -> String {
        var sections: [String] = [
            "Add punctuation and fix obvious ASR or dictation errors.",
            "Prefer the smallest possible edit. If you are unsure, keep the original wording.",
            "Preserve the original meaning and primary language.",
            "Do not rewrite numbers, URLs, email addresses, file paths, code identifiers, proper nouns, or product names unless the recognition error is obvious.",
            "Output only the corrected text."
        ]

        if let expertSections = expertPromptSections(
            from: profile,
            contextualGlossaryText: contextualGlossaryText
        ) {
            sections.append(contentsOf: expertSections)
        }

        sections.append("Text:\n\(text)")
        return sections.joined(separator: "\n\n")
    }

    static func rewritePrompt(
        text: String,
        mode: TextRewriteMode,
        profile: ASRExpertProfile?,
        contextualGlossaryText: String? = nil
    ) -> String {
        var sections: [String] = [
            "Rewrite the user's text by fixing typos, grammar, punctuation, awkward phrasing, and likely ASR misrecognitions.",
            "Run a basic logic-consistency check. If the sentence contains an obvious self-contradiction caused by recognition errors, resolve it using the surrounding context without inventing new facts.",
            "Preserve the original meaning, language, and structure unless the requested tone explicitly asks for a different presentation.",
            "Keep paragraph breaks, Markdown, and list formatting when present.",
            "Do not add explanations, headings, quotes, or commentary.",
            "Output only the final rewritten text."
        ]

        switch mode {
        case .proofreadAndPolish:
            break
        }

        if let expertSections = expertPromptSections(
            from: profile,
            contextualGlossaryText: contextualGlossaryText
        ) {
            sections.append(contentsOf: expertSections)
        }

        sections.append("Text:\n\(text)")
        return sections.joined(separator: "\n\n")
    }

    static func requestDescriptor(for configuredEndpoint: URL) -> EndpointDescriptor {
        let trimmedPath = normalizedPath(configuredEndpoint.path)
        switch true {
        case trimmedPath.hasSuffix("/chat/completions"):
            return EndpointDescriptor(url: configuredEndpoint, flavor: .chatCompletions)
        case trimmedPath.hasSuffix("/responses"):
            return EndpointDescriptor(url: configuredEndpoint, flavor: .responses)
        case trimmedPath.hasSuffix("/api/v1/chat"):
            return EndpointDescriptor(url: configuredEndpoint, flavor: .lmStudioChat)
        case trimmedPath.hasSuffix("/completions"):
            return EndpointDescriptor(url: configuredEndpoint, flavor: .completions)
        case trimmedPath.hasSuffix("/api/v1/models"):
            return EndpointDescriptor(
                url: replacingPath(in: configuredEndpoint, with: replacingSuffix("/models", in: trimmedPath, with: "/chat")),
                flavor: .lmStudioChat
            )
        case trimmedPath.hasSuffix("/models"):
            return EndpointDescriptor(
                url: replacingPath(in: configuredEndpoint, with: replacingSuffix("/models", in: trimmedPath, with: "/chat/completions")),
                flavor: .chatCompletions
            )
        case trimmedPath == "":
            return EndpointDescriptor(
                url: replacingPath(in: configuredEndpoint, with: "/v1/chat/completions"),
                flavor: .chatCompletions
            )
        case trimmedPath.hasSuffix("/api/v1"):
            return EndpointDescriptor(
                url: replacingPath(in: configuredEndpoint, with: trimmedPath + "/chat"),
                flavor: .lmStudioChat
            )
        case trimmedPath.hasSuffix("/v1"):
            return EndpointDescriptor(
                url: replacingPath(in: configuredEndpoint, with: trimmedPath + "/chat/completions"),
                flavor: .chatCompletions
            )
        case trimmedPath.hasSuffix("/chat"):
            return EndpointDescriptor(url: configuredEndpoint, flavor: .lmStudioChat)
        default:
            return EndpointDescriptor(
                url: replacingPath(in: configuredEndpoint, with: trimmedPath + "/chat/completions"),
                flavor: .chatCompletions
            )
        }
    }

    static func modelsEndpoint(from configuredEndpoint: URL) -> URL {
        let descriptor = requestDescriptor(for: configuredEndpoint)
        let path = normalizedPath(descriptor.url.path)
        switch descriptor.flavor {
        case .chatCompletions:
            return replacingPath(
                in: descriptor.url,
                with: replacingSuffix("/chat/completions", in: path, with: "/models")
            )
        case .completions:
            return replacingPath(
                in: descriptor.url,
                with: replacingSuffix("/completions", in: path, with: "/models")
            )
        case .responses:
            return replacingPath(
                in: descriptor.url,
                with: replacingSuffix("/responses", in: path, with: "/models")
            )
        case .lmStudioChat:
            return replacingPath(
                in: descriptor.url,
                with: replacingSuffix("/chat", in: path, with: "/models")
            )
        }
    }

    private func authorizedRequest(
        url: URL,
        timeout: TimeInterval = OpenAICompatibleProvider.rewriteTimeout
    ) -> URLRequest {
        var req = URLRequest(url: url, timeoutInterval: timeout)
        req.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        return req
    }

    private func call(
        prompt: String,
        temperature: Double = 0.2,
        maxTokens: Int? = nil,
        timeout: TimeInterval = OpenAICompatibleProvider.rewriteTimeout
    ) async throws -> String {
        let descriptors = Self.preferredDescriptors(for: config.endpoint, model: config.model)
        var lastError: Error?

        for descriptor in descriptors {
            var req = authorizedRequest(url: descriptor.url, timeout: timeout)
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONSerialization.data(
                withJSONObject: Self.requestBody(
                    for: descriptor.flavor,
                    model: config.model,
                    prompt: prompt,
                    temperature: temperature,
                    maxTokens: maxTokens
                )
            )
            GlobalLogger.speech.info(
                "[LLM] request flavor=\(Self.flavorLabel(descriptor.flavor)) url=\(descriptor.url.absoluteString) model=\(config.model) promptChars=\(prompt.count)"
            )

            do {
                let response = try await perform(req)
                GlobalLogger.speech.info(
                    "[LLM] response flavor=\(Self.flavorLabel(descriptor.flavor)) url=\(descriptor.url.absoluteString) status=\(response.statusCode) contentType=\(response.contentType ?? "nil") preview=\(Self.responsePreview(from: response.data) ?? "nil")"
                )
                return try Self.parseResponseText(from: response.data)
            } catch {
                lastError = error
                GlobalLogger.speech.error(
                    "[LLM] request failed flavor=\(Self.flavorLabel(descriptor.flavor)) url=\(descriptor.url.absoluteString) error=\(error.localizedDescription)"
                )
                if !Self.shouldTryNextDescriptor(after: error) {
                    throw error
                }
            }
        }

        throw lastError ?? LLMProviderError.invalidResponse()
    }

    private func perform(_ request: URLRequest) async throws -> ResponseEnvelope {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch let error as URLError where error.code == .timedOut {
            throw LLMProviderError.requestTimedOut
        } catch {
            throw error
        }
        guard let http = response as? HTTPURLResponse else {
            throw LLMProviderError.invalidResponse()
        }
        guard (200..<300).contains(http.statusCode) else {
            let message = Self.extractErrorMessage(from: data)
                ?? HTTPURLResponse.localizedString(forStatusCode: http.statusCode)
            throw LLMProviderError.backendStatus(code: http.statusCode, message: message)
        }
        return ResponseEnvelope(
            data: data,
            statusCode: http.statusCode,
            contentType: http.value(forHTTPHeaderField: "Content-Type")
        )
    }

    private static func extractErrorMessage(from data: Data) -> String? {
        guard !data.isEmpty else { return nil }
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let error = json["error"] as? [String: Any],
               let message = error["message"] as? String,
               !message.isEmpty {
                return message
            }
            if let error = json["error"] as? String,
               !error.isEmpty {
                return error
            }
            if let message = json["message"] as? String,
               !message.isEmpty {
                return message
            }
        }
        if let raw = responsePreview(from: data) {
            return raw
        }
        return nil
    }

    static func parseResponseText(from data: Data) throws -> String {
        if let streamed = extractTextFromEventStream(data),
           !streamed.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return streamed
        }

        let json = try jsonObject(from: data)
        let trimmed = extractText(from: json)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else {
            throw LLMProviderError.invalidResponse(preview: responsePreview(from: data))
        }
        return trimmed
    }

    static func parseModelList(from data: Data) throws -> [String] {
        let json = try jsonObject(from: data)
        let models = Array(Set(extractModelIdentifiers(from: json))).sorted()
        guard !models.isEmpty else {
            throw LLMProviderError.noModelsReturned
        }
        return models
    }

    private static func requestBody(
        for flavor: RequestFlavor,
        model: String,
        prompt: String,
        temperature: Double,
        maxTokens: Int?
    ) -> [String: Any] {
        switch flavor {
        case .chatCompletions:
            var body: [String: Any] = [
                "model": model,
                "messages": [
                    ["role": "system", "content": "You are a helpful assistant."],
                    ["role": "user", "content": prompt],
                ],
                "temperature": temperature,
            ]
            if let maxTokens {
                body["max_tokens"] = maxTokens
            }
            return body
        case .completions:
            var body: [String: Any] = [
                "model": model,
                "prompt": prompt,
                "temperature": temperature,
            ]
            if let maxTokens {
                body["max_tokens"] = maxTokens
            }
            return body
        case .responses:
            var body: [String: Any] = [
                "model": model,
                "input": prompt,
                "temperature": temperature,
            ]
            if let maxTokens {
                body["max_output_tokens"] = maxTokens
            }
            return body
        case .lmStudioChat:
            var body: [String: Any] = [
                "model": model,
                "input": prompt,
                "temperature": temperature,
            ]
            if let maxTokens {
                body["max_tokens"] = maxTokens
                body["max_output_tokens"] = maxTokens
            }
            return body
        }
    }

    private static func expertPromptSections(
        from profile: ASRExpertProfile?,
        contextualGlossaryText: String?
    ) -> [String]? {
        let hasEnabledProfile = profile?.isEnabled == true
        let mergedGlossary = mergedGlossaryText(
            profileGlossary: hasEnabledProfile ? profile?.glossaryText : nil,
            contextualGlossary: contextualGlossaryText
        )
        guard hasEnabledProfile || mergedGlossary != nil else { return nil }

        var sections: [String] = []

        if let profile, profile.isEnabled {
            sections.append("Target tone: \(profile.tone.promptDescription)")

            let domain = profile.domain.trimmingCharacters(in: .whitespacesAndNewlines)
            if !domain.isEmpty {
                sections.append("Domain context: \(domain)")
            }

            let extra = profile.extraInstructions.trimmingCharacters(in: .whitespacesAndNewlines)
            if !extra.isEmpty {
                sections.append("Additional rewrite requirements:\n\(extra)")
            }
        }

        if let mergedGlossary {
            sections.append("Preferred keywords and terminology:\n\(mergedGlossary)")
        }

        return sections
    }

    private static func mergedGlossaryText(
        profileGlossary: String?,
        contextualGlossary: String?
    ) -> String? {
        let rawLines =
            promptGlossaryLines(from: profileGlossary) +
            promptGlossaryLines(from: contextualGlossary)
        let uniqueLines = VoiceLexiconSupport.uniqueTerms(rawLines)
        guard !uniqueLines.isEmpty else { return nil }
        return uniqueLines.joined(separator: "\n")
    }

    private static func promptGlossaryLines(from raw: String?) -> [String] {
        guard let raw else { return [] }
        return raw
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private static func candidateDescriptors(for configuredEndpoint: URL) -> [EndpointDescriptor] {
        let primary = requestDescriptor(for: configuredEndpoint)
        let rawPath = normalizedPath(configuredEndpoint.path)
        let basePaths = candidateBasePaths(for: rawPath)
        var candidates = [primary]

        for basePath in basePaths {
            if basePath.hasSuffix("/api/v1") {
                candidates.append(
                    EndpointDescriptor(
                        url: replacingPath(in: configuredEndpoint, with: basePath + "/chat"),
                        flavor: .lmStudioChat
                    )
                )
            }

            if basePath.hasSuffix("/v1") || basePath.isEmpty {
                candidates.append(
                    EndpointDescriptor(
                        url: replacingPath(in: configuredEndpoint, with: basePath + "/chat/completions"),
                        flavor: .chatCompletions
                    )
                )
                candidates.append(
                    EndpointDescriptor(
                        url: replacingPath(in: configuredEndpoint, with: basePath + "/responses"),
                        flavor: .responses
                    )
                )
                candidates.append(
                    EndpointDescriptor(
                        url: replacingPath(in: configuredEndpoint, with: basePath + "/completions"),
                        flavor: .completions
                    )
                )
            }
        }

        return candidates.reduce(into: []) { partial, descriptor in
            if !partial.contains(descriptor) {
                partial.append(descriptor)
            }
        }
    }

    private static func preferredDescriptors(for configuredEndpoint: URL, model: String) -> [EndpointDescriptor] {
        let descriptors = candidateDescriptors(for: configuredEndpoint)
        guard modelPrefersResponses(model) else {
            return descriptors
        }

        return descriptors.sorted { lhs, rhs in
            flavorPriority(lhs.flavor) < flavorPriority(rhs.flavor)
        }
    }

    private static func shouldTryNextDescriptor(after error: Error) -> Bool {
        if let providerError = error as? LLMProviderError {
            switch providerError {
            case .invalidResponse:
                return true
            case .backendStatus(let code, _):
                return [400, 404, 405, 415, 422].contains(code)
            case .noModelsReturned:
                return false
            case .requestTimedOut:
                return false
            }
        }
        return false
    }

    private static func flavorLabel(_ flavor: RequestFlavor) -> String {
        switch flavor {
        case .chatCompletions:
            return "chat.completions"
        case .completions:
            return "completions"
        case .responses:
            return "responses"
        case .lmStudioChat:
            return "lmstudio.chat"
        }
    }

    private static func modelPrefersResponses(_ model: String) -> Bool {
        let lowered = model.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return lowered.hasPrefix("gpt-5")
            || lowered.hasPrefix("gpt-4.1")
            || lowered.hasPrefix("o1")
            || lowered.hasPrefix("o3")
            || lowered.hasPrefix("o4")
    }

    private static func flavorPriority(_ flavor: RequestFlavor) -> Int {
        switch flavor {
        case .responses:
            return 0
        case .chatCompletions:
            return 1
        case .completions:
            return 2
        case .lmStudioChat:
            return 3
        }
    }

    private static func jsonObject(from data: Data) throws -> Any {
        guard !data.isEmpty else {
            throw LLMProviderError.invalidResponse()
        }
        do {
            return try JSONSerialization.jsonObject(with: data)
        } catch {
            throw LLMProviderError.invalidResponse(preview: responsePreview(from: data))
        }
    }

    private static func extractText(from value: Any) -> String? {
        if let text = normalizedString(value as? String) {
            return text
        }

        guard let dictionary = value as? [String: Any] else {
            if let array = value as? [Any] {
                return joinTextParts(array.compactMap(extractText(from:)))
            }
            return nil
        }

        if let text = normalizedString(dictionary["output_text"] as? String) {
            return text
        }
        if let choices = dictionary["choices"] as? [Any],
           let text = choices.compactMap(extractChoiceText(from:)).first {
            return text
        }
        if let output = dictionary["output"] as? [Any] {
            let text = joinTextParts(output.compactMap(extractOutputItemText(from:)))
            if text != nil {
                return text
            }
        }
        if let message = dictionary["message"],
           let text = extractMessageText(from: message) {
            return text
        }
        if let text = normalizedString(dictionary["text"] as? String) {
            return text
        }
        if let content = dictionary["content"],
           let text = extractContentText(from: content) {
            return text
        }
        return nil
    }

    private static func extractChoiceText(from value: Any) -> String? {
        guard let dictionary = value as? [String: Any] else {
            return nil
        }
        if let message = dictionary["message"],
           let text = extractMessageText(from: message) {
            return text
        }
        if let delta = dictionary["delta"],
           let text = extractContentText(from: delta) {
            return text
        }
        if let text = normalizedString(dictionary["text"] as? String) {
            return text
        }
        return nil
    }

    private static func extractMessageText(from value: Any) -> String? {
        guard let dictionary = value as? [String: Any] else {
            return extractContentText(from: value)
        }
        if let content = dictionary["content"],
           let text = extractContentText(from: content) {
            return text
        }
        if let text = normalizedString(dictionary["text"] as? String) {
            return text
        }
        return nil
    }

    private static func extractOutputItemText(from value: Any) -> String? {
        guard let dictionary = value as? [String: Any] else {
            return extractContentText(from: value)
        }
        if let content = dictionary["content"],
           let text = extractContentText(from: content) {
            return text
        }
        if let text = normalizedString(dictionary["text"] as? String) {
            return text
        }
        if let message = dictionary["message"],
           let text = extractMessageText(from: message) {
            return text
        }
        return nil
    }

    private static func extractContentText(from value: Any) -> String? {
        if let text = normalizedString(value as? String) {
            return text
        }

        if let array = value as? [Any] {
            return joinTextParts(array.compactMap(extractContentText(from:)))
        }

        guard let dictionary = value as? [String: Any] else {
            return nil
        }

        if let text = normalizedString(dictionary["text"] as? String) {
            return text
        }
        if let textDictionary = dictionary["text"] as? [String: Any] {
            if let text = normalizedString(textDictionary["value"] as? String) {
                return text
            }
            if let text = normalizedString(textDictionary["text"] as? String) {
                return text
            }
        }
        if let inputText = normalizedString(dictionary["input_text"] as? String) {
            return inputText
        }
        if let outputText = normalizedString(dictionary["output_text"] as? String) {
            return outputText
        }
        if let value = dictionary["value"],
           let text = extractContentText(from: value) {
            return text
        }
        if let content = dictionary["content"],
           let text = extractContentText(from: content) {
            return text
        }
        return nil
    }

    private static func extractModelIdentifiers(from value: Any) -> [String] {
        if let text = normalizedString(value as? String) {
            return [text]
        }

        if let array = value as? [Any] {
            return array.flatMap(extractModelIdentifiers(from:))
        }

        guard let dictionary = value as? [String: Any] else {
            return []
        }

        if let data = dictionary["data"] {
            return extractModelIdentifiers(from: data)
        }
        if let models = dictionary["models"] {
            return extractModelIdentifiers(from: models)
        }
        if let loadedModels = dictionary["loaded_models"] {
            return extractModelIdentifiers(from: loadedModels)
        }
        if let loadedInstances = dictionary["loaded_instances"] {
            return extractModelIdentifiers(from: loadedInstances)
        }
        if let text = normalizedString(dictionary["id"] as? String) {
            return [text]
        }
        if let text = normalizedString(dictionary["model"] as? String) {
            return [text]
        }
        if let text = normalizedString(dictionary["name"] as? String) {
            return [text]
        }
        if let text = normalizedString(dictionary["key"] as? String) {
            return [text]
        }
        if let text = normalizedString(dictionary["identifier"] as? String) {
            return [text]
        }
        if let modelInfo = dictionary["model_info"] {
            return extractModelIdentifiers(from: modelInfo)
        }
        return []
    }

    private static func normalizedString(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func joinTextParts(_ values: [String]) -> String? {
        let parts = values
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !parts.isEmpty else { return nil }
        return parts.joined(separator: "\n\n")
    }

    private static func normalizedPath(_ path: String) -> String {
        guard path != "/" else { return "" }
        return path.hasSuffix("/") ? String(path.dropLast()) : path
    }

    private static func candidateBasePaths(for rawPath: String) -> [String] {
        var paths: [String] = []

        func append(_ value: String) {
            let normalized = normalizedPath(value)
            if !paths.contains(normalized) {
                paths.append(normalized)
            }
        }

        append(rawPath)

        switch rawPath {
        case "":
            append("/v1")
            append("/api/v1")
        case "/v1":
            append("")
            append("/api/v1")
        case "/api/v1":
            append("")
            append("/v1")
        default:
            if rawPath.hasSuffix("/chat/completions") {
                append(replacingSuffix("/chat/completions", in: rawPath, with: ""))
            } else if rawPath.hasSuffix("/responses") {
                append(replacingSuffix("/responses", in: rawPath, with: ""))
            } else if rawPath.hasSuffix("/completions") {
                append(replacingSuffix("/completions", in: rawPath, with: ""))
            } else if rawPath.hasSuffix("/chat") {
                append(replacingSuffix("/chat", in: rawPath, with: ""))
            } else if rawPath.hasSuffix("/models") {
                append(replacingSuffix("/models", in: rawPath, with: ""))
            }
            append("/v1")
            append("/api/v1")
        }

        return paths
    }

    private static func replacingSuffix(_ suffix: String, in path: String, with replacement: String) -> String {
        guard path.hasSuffix(suffix) else { return path }
        return String(path.dropLast(suffix.count)) + replacement
    }

    private static func replacingPath(in url: URL, with path: String) -> URL {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url
        }
        components.path = path
        return components.url ?? url
    }

    private static func responsePreview(from data: Data) -> String? {
        guard let raw = String(data: data, encoding: .utf8) else {
            return nil
        }
        let singleLine = raw
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !singleLine.isEmpty else {
            return nil
        }
        if singleLine.count <= 140 {
            return singleLine
        }
        let endIndex = singleLine.index(singleLine.startIndex, offsetBy: 140)
        return String(singleLine[..<endIndex]) + "..."
    }

    private static func extractTextFromEventStream(_ data: Data) -> String? {
        guard let raw = String(data: data, encoding: .utf8),
              raw.contains("data:") else {
            return nil
        }

        var chunks: [String] = []
        for line in raw.split(whereSeparator: \.isNewline) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.hasPrefix("data:") else { continue }
            let payload = trimmed.dropFirst("data:".count).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !payload.isEmpty, payload != "[DONE]" else { continue }

            if let payloadData = payload.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: payloadData),
               let text = extractText(from: json) {
                chunks.append(text)
            } else {
                chunks.append(payload)
            }
        }

        return joinTextParts(chunks)
    }
}

enum AppleOnDeviceLLMProviderFactory {
    static func availability(localeIdentifier: String) -> AppleOnDeviceLLMAvailability {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            let locale = Locale(identifier: localeIdentifier)
            let model = SystemLanguageModel(
                useCase: .general,
                guardrails: .permissiveContentTransformations
            )
            switch model.availability {
            case .available:
                return model.supportsLocale(locale) ? .available : .unsupportedLocale
            case .unavailable(let reason):
                switch reason {
                case .deviceNotEligible:
                    return .deviceNotEligible
                case .appleIntelligenceNotEnabled:
                    return .appleIntelligenceDisabled
                case .modelNotReady:
                    return .modelNotReady
                @unknown default:
                    return .modelNotReady
                }
            }
        }
        #endif
        return .requiresMacOS26
    }

    static func makeProvider(config: AppleOnDeviceLLMConfig) -> LLMHealthCheckProvider? {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            return AppleOnDeviceLLMProvider(config: config)
        }
        #endif
        return nil
    }
}

#if canImport(FoundationModels)
@available(macOS 26.0, *)
private final class AppleOnDeviceLLMProvider: LLMHealthCheckProvider {
    private let config: AppleOnDeviceLLMConfig
    private let model: SystemLanguageModel
    private let locale: Locale

    init?(config: AppleOnDeviceLLMConfig) {
        let availability = AppleOnDeviceLLMProviderFactory.availability(localeIdentifier: config.localeIdentifier)
        guard availability == .available else { return nil }
        self.config = config
        self.locale = Locale(identifier: config.localeIdentifier)
        self.model = SystemLanguageModel(
            useCase: .general,
            guardrails: .permissiveContentTransformations
        )
    }

    func enhanceDictation(_ text: String) async throws -> String {
        let prompt = OpenAICompatibleProvider.dictationPrompt(
            text: text,
            profile: config.rewriteProfile,
            contextualGlossaryText: config.contextualGlossaryText
        )
        return try await respond(to: prompt)
    }

    func rewriteText(_ text: String, mode: TextRewriteMode) async throws -> String {
        let prompt = OpenAICompatibleProvider.rewritePrompt(
            text: text,
            mode: mode,
            profile: config.rewriteProfile,
            contextualGlossaryText: config.contextualGlossaryText
        )
        return try await respond(to: prompt)
    }

    func interpretCommand(_ text: String) async throws -> VoiceIntent {
        _ = text
        return .unknown(text)
    }

    func testConfiguration() async throws {
        _ = try await respond(to: "Reply with OK only.")
    }

    private func respond(to prompt: String) async throws -> String {
        let localeName = locale.localizedString(forIdentifier: locale.identifier)
        let availability = AppleOnDeviceLLMProviderFactory.availability(localeIdentifier: config.localeIdentifier)
        guard availability == .available else {
            throw AppleOnDeviceLLMError.unavailable(availability, localeName: localeName)
        }

        do {
            let session = LanguageModelSession(model: model)
            let response = try await session.respond(to: prompt)
            let text = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else {
                throw LLMProviderError.invalidResponse()
            }
            return text
        } catch let error as LanguageModelSession.GenerationError {
            switch error {
            case .unsupportedLanguageOrLocale:
                throw AppleOnDeviceLLMError.unavailable(.unsupportedLocale, localeName: localeName)
            default:
                throw AppleOnDeviceLLMError.generationFailed(error.localizedDescription)
            }
        } catch {
            throw AppleOnDeviceLLMError.generationFailed(error.localizedDescription)
        }
    }
}
#endif
