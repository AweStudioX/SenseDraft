import Foundation

public enum QwenAPIRegion: String, CaseIterable, Sendable {
    case china
    case singapore
}

public enum CompatibleService: Sendable {
    case gemini
    case openRouter
    case qwen(QwenAPIRegion)
    case ollama
    case custom(String)

    var baseURL: String {
        switch self {
        case .gemini: "https://generativelanguage.googleapis.com/v1beta/openai"
        case .openRouter: "https://openrouter.ai/api/v1"
        case .qwen(.china): "https://dashscope.aliyuncs.com/compatible-mode/v1"
        case .qwen(.singapore): "https://dashscope-intl.aliyuncs.com/compatible-mode/v1"
        case .ollama: "http://localhost:11434/v1"
        case .custom(let address): address
        }
    }

    var requiresKey: Bool {
        if case .ollama = self { return false }
        if case .custom = self { return false }
        return true
    }

    var structuredFormat: String {
        if case .custom = self { return "json_object" }
        return "json_schema"
    }
}

public enum CompatibleProviderError: Error, Equatable {
    case missingKey
    case missingModel
    case invalidEndpoint
    case httpStatus(Int)
    case incomplete
    case invalidResponse
}

public struct CompatibleProvider: LanguageService {
    private let service: CompatibleService
    private let key: String
    private let model: String
    private let transport: any HTTPTransport

    public init(service: CompatibleService, key: String, model: String,
                transport: any HTTPTransport = URLSessionTransport()) {
        self.service = service
        self.key = key
        self.model = model
        self.transport = transport
    }

    public func analyze(_ input: AnalysisInput) async throws -> AnalysisResult {
        guard !model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw CompatibleProviderError.missingModel
        }
        guard !service.requiresKey || !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw CompatibleProviderError.missingKey
        }
        guard let endpoint = Self.endpoint(for: service.baseURL) else {
            throw CompatibleProviderError.invalidEndpoint
        }
        let instructions = AnalysisPrompt.instructions(for: input)
            + "\nReturn only a JSON object with fields: english (string), chineseMeaning (string), ambiguity (string or null), worthChanging (boolean), reason (string or null)."
        var body: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "system", "content": instructions],
                ["role": "user", "content": AnalysisPrompt.userMessage(for: input)]
            ]
        ]
        if service.structuredFormat == "json_schema" {
            body["response_format"] = [
                "type": "json_schema",
                "json_schema": [
                    "name": "sensedraft_analysis",
                    "strict": true,
                    "schema": Self.analysisSchema
                ]
            ]
        } else {
            body["response_format"] = ["type": "json_object"]
        }
        if case .openRouter = service {
            body["provider"] = ["require_parameters": true]
        }
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await transport.send(request)
        guard (200..<300).contains(response.statusCode) else {
            throw CompatibleProviderError.httpStatus(response.statusCode)
        }
        guard let envelope = try? JSONDecoder().decode(Envelope.self, from: data),
              let choice = envelope.choices.first else {
            throw CompatibleProviderError.invalidResponse
        }
        guard choice.finishReason == "stop" else { throw CompatibleProviderError.incomplete }
        guard let content = choice.message.content,
              let payload = try? JSONDecoder().decode(Payload.self, from: Data(content.utf8)) else {
            throw CompatibleProviderError.invalidResponse
        }
        return try AnalysisResult(english: payload.english, chineseMeaning: payload.chineseMeaning,
                                  ambiguity: payload.ambiguity, worthChanging: payload.worthChanging,
                                  reason: payload.reason, source: input.source)
    }

    private static func endpoint(for base: String) -> URL? {
        guard var components = URLComponents(string: base),
              let scheme = components.scheme?.lowercased(),
              let host = components.host?.lowercased(), !host.isEmpty,
              components.user == nil, components.password == nil,
              components.query == nil, components.fragment == nil,
              scheme == "https" || (scheme == "http" && ["localhost", "127.0.0.1", "::1"].contains(host)) else {
            return nil
        }
        let path = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        components.path = "/" + (path.isEmpty ? "" : path + "/") + "chat/completions"
        return components.url
    }

    private static var analysisSchema: [String: Any] { [
        "type": "object",
        "properties": [
            "english": ["type": "string"],
            "chineseMeaning": ["type": "string"],
            "ambiguity": ["type": ["string", "null"]],
            "worthChanging": ["type": "boolean"],
            "reason": ["type": ["string", "null"]]
        ],
        "required": ["english", "chineseMeaning", "ambiguity", "worthChanging", "reason"],
        "additionalProperties": false
    ] }
}

private struct Envelope: Decodable {
    let choices: [Choice]
    struct Choice: Decodable {
        let finishReason: String?
        let message: Message
        enum CodingKeys: String, CodingKey { case finishReason = "finish_reason", message }
    }
    struct Message: Decodable { let content: String? }
}

private struct Payload: Decodable {
    let english: String
    let chineseMeaning: String
    let ambiguity: String?
    let worthChanging: Bool
    let reason: String?
}
