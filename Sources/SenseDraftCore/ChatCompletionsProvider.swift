import Foundation

public enum KimiAPIRegion: String, CaseIterable, Sendable {
    case china
    case global
}

public enum ChatCompletionsService: Sendable {
    case deepSeek
    case kimi(KimiAPIRegion)

    var endpoint: URL {
        switch self {
        case .deepSeek: URL(string: "https://api.deepseek.com/chat/completions")!
        case .kimi(.china): URL(string: "https://api.moonshot.cn/v1/chat/completions")!
        case .kimi(.global): URL(string: "https://api.moonshot.ai/v1/chat/completions")!
        }
    }

    var defaultModel: String {
        switch self {
        case .deepSeek: "deepseek-flash"
        case .kimi: "kimi-k2.6"
        }
    }
}

public enum ChatCompletionsProviderError: Error, Equatable {
    case missingKey
    case httpStatus(Int, type: String?, requestID: String?)
    case incomplete
    case invalidResponse
}

public struct ChatCompletionsProvider: LanguageService {
    private let service: ChatCompletionsService
    private let key: String
    private let model: String
    private let transport: any HTTPTransport

    public init(service: ChatCompletionsService, key: String, model: String? = nil,
                transport: any HTTPTransport = URLSessionTransport()) {
        self.service = service
        self.key = key
        self.model = model ?? service.defaultModel
        self.transport = transport
    }

    public func analyze(_ input: AnalysisInput) async throws -> AnalysisResult {
        guard !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ChatCompletionsProviderError.missingKey
        }
        let instructions = AnalysisPrompt.instructions(for: input) + "\nReturn only a JSON object with these fields: english (string), chineseMeaning (string), ambiguity (string or null), worthChanging (boolean), reason (string or null)."
        var body: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "system", "content": instructions],
                ["role": "user", "content": input.source]
            ],
            "response_format": ["type": "json_object"]
        ]
        if case .kimi = service, model == "kimi-k2.6" {
            body["thinking"] = ["type": "disabled"]
        }
        var request = URLRequest(url: service.endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await transport.send(request)
        guard (200..<300).contains(response.statusCode) else {
            let errorType = (try? JSONDecoder().decode(CompletionErrorEnvelope.self, from: data))?.error.type
            let safeType = Self.knownErrorTypes.contains(errorType ?? "") ? errorType : nil
            let requestID = response.value(forHTTPHeaderField: "Msh-Request-Id")
            let safeRequestID = requestID.flatMap { value in
                value.count <= 80 && !value.isEmpty &&
                value.utf8.allSatisfy { byte in
                    (48...57).contains(byte) || (65...90).contains(byte) ||
                    (97...122).contains(byte) || byte == 45
                } ? value : nil
            }
            throw ChatCompletionsProviderError.httpStatus(response.statusCode, type: safeType,
                                                          requestID: safeRequestID)
        }
        guard let envelope = try? JSONDecoder().decode(CompletionEnvelope.self, from: data),
              let choice = envelope.choices.first else {
            throw ChatCompletionsProviderError.invalidResponse
        }
        guard choice.finishReason == "stop" else { throw ChatCompletionsProviderError.incomplete }
        guard let content = choice.message.content,
              let payload = try? JSONDecoder().decode(CompletionPayload.self,
                                                      from: Data(Self.jsonContent(content).utf8)) else {
            throw ChatCompletionsProviderError.invalidResponse
        }
        return try AnalysisResult(english: payload.english, chineseMeaning: payload.chineseMeaning,
                                  ambiguity: payload.ambiguity, worthChanging: payload.worthChanging,
                                  reason: payload.reason, source: input.source)
    }

    private static let knownErrorTypes: Set<String> = [
        "exceeded_current_quota_error", "rate_limit_reached_error", "engine_overloaded_error"
    ]

    private static func jsonContent(_ content: String) -> String {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasSuffix("```"), let firstLineEnd = trimmed.firstIndex(of: "\n") else {
            return trimmed
        }
        let openingFence = trimmed[..<firstLineEnd]
        guard openingFence == "```json" || openingFence == "```" else { return trimmed }
        let bodyStart = trimmed.index(after: firstLineEnd)
        let bodyEnd = trimmed.index(trimmed.endIndex, offsetBy: -3)
        guard bodyStart <= bodyEnd else { return trimmed }
        return String(trimmed[bodyStart..<bodyEnd]).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private struct CompletionErrorEnvelope: Decodable {
    let error: CompletionErrorDetail
}

private struct CompletionErrorDetail: Decodable {
    let type: String?
}

private struct CompletionEnvelope: Decodable {
    let choices: [CompletionChoice]
}

private struct CompletionChoice: Decodable {
    let finishReason: String
    let message: CompletionMessage

    enum CodingKeys: String, CodingKey {
        case finishReason = "finish_reason", message
    }
}

private struct CompletionMessage: Decodable {
    let content: String?
}

private struct CompletionPayload: Decodable {
    let english: String
    let chineseMeaning: String
    let ambiguity: String?
    let worthChanging: Bool
    let reason: String?
}
