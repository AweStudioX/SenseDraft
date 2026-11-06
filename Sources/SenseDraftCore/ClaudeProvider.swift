import Foundation

public enum ClaudeProviderError: Error, Equatable {
    case missingKey
    case missingModel
    case httpStatus(Int)
    case incomplete
    case invalidResponse
}

public struct ClaudeProvider: LanguageService {
    private let key: String
    private let model: String
    private let transport: any HTTPTransport

    public init(key: String, model: String,
                transport: any HTTPTransport = URLSessionTransport()) {
        self.key = key
        self.model = model
        self.transport = transport
    }

    public func analyze(_ input: AnalysisInput) async throws -> AnalysisResult {
        guard !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ClaudeProviderError.missingKey
        }
        guard !model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ClaudeProviderError.missingModel
        }
        let body: [String: Any] = [
            "model": model,
            "max_tokens": 8192,
            "system": AnalysisPrompt.instructions(for: input),
            "messages": [["role": "user", "content": AnalysisPrompt.userMessage(for: input)]],
            "output_config": ["format": ["type": "json_schema", "schema": Self.analysisSchema]]
        ]
        var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        request.httpMethod = "POST"
        request.setValue(key, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await transport.send(request)
        guard (200..<300).contains(response.statusCode) else {
            throw ClaudeProviderError.httpStatus(response.statusCode)
        }
        guard let envelope = try? JSONDecoder().decode(ClaudeEnvelope.self, from: data) else {
            throw ClaudeProviderError.invalidResponse
        }
        guard envelope.stopReason == "end_turn" else { throw ClaudeProviderError.incomplete }
        guard let content = envelope.content.first(where: { $0.type == "text" })?.text,
              let payload = try? JSONDecoder().decode(ClaudePayload.self, from: Data(content.utf8)) else {
            throw ClaudeProviderError.invalidResponse
        }
        return try AnalysisResult(english: payload.english, chineseMeaning: payload.chineseMeaning,
                                  ambiguity: payload.ambiguity, worthChanging: payload.worthChanging,
                                  reason: payload.reason, source: input.source)
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

private struct ClaudeEnvelope: Decodable {
    let stopReason: String?
    let content: [Content]
    struct Content: Decodable { let type: String; let text: String? }
    enum CodingKeys: String, CodingKey { case stopReason = "stop_reason", content }
}

private struct ClaudePayload: Decodable {
    let english: String
    let chineseMeaning: String
    let ambiguity: String?
    let worthChanging: Bool
    let reason: String?
}
