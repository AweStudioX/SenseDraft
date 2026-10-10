import Foundation

public protocol HTTPTransport: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

public struct URLSessionTransport: HTTPTransport {
    public init() {}

    public func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let response = response as? HTTPURLResponse else {
            throw OpenAIProviderError.invalidResponse
        }
        return (data, response)
    }
}

public enum OpenAIProviderError: Error, Equatable {
    case missingKey
    case httpStatus(Int)
    case incomplete
    case invalidResponse
}

public struct OpenAIProvider: LanguageService {
    private let key: String
    private let model: String
    private let transport: any HTTPTransport

    public init(key: String, model: String = "gpt-6.1-sol", transport: any HTTPTransport = URLSessionTransport()) {
        self.key = key
        self.model = model
        self.transport = transport
    }

    public func analyze(_ input: AnalysisInput) async throws -> AnalysisResult {
        guard !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw OpenAIProviderError.missingKey
        }
        let schema: [String: Any] = [
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
        ]
        let body: [String: Any] = [
            "model": model,
            "store": false,
            "instructions": AnalysisPrompt.instructions(for: input),
            "input": [["role": "user", "content": input.source]],
            "text": ["format": ["type": "json_schema", "name": "sensedraft_analysis", "schema": schema, "strict": true]]
        ]
        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/responses")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await transport.send(request)
        guard (200..<300).contains(response.statusCode) else {
            throw OpenAIProviderError.httpStatus(response.statusCode)
        }
        guard let envelope = try? JSONDecoder().decode(ResponseEnvelope.self, from: data) else {
            throw OpenAIProviderError.invalidResponse
        }
        guard envelope.status == "completed" else {
            throw OpenAIProviderError.incomplete
        }
        guard let text = envelope.output.flatMap(\.content).first(where: { $0.type == "output_text" })?.text,
              let outputData = text.data(using: .utf8),
              let output = try? JSONDecoder().decode(AnalysisPayload.self, from: outputData) else {
            throw OpenAIProviderError.invalidResponse
        }
        return try AnalysisResult(english: output.english, chineseMeaning: output.chineseMeaning, ambiguity: output.ambiguity, worthChanging: output.worthChanging, reason: output.reason, source: input.source)
    }
}

private struct ResponseEnvelope: Decodable {
    let status: String
    let output: [ResponseMessage]
}

private struct ResponseMessage: Decodable {
    let content: [ResponseContent]
}

private struct ResponseContent: Decodable {
    let type: String
    let text: String?
}

private struct AnalysisPayload: Decodable {
    let english: String
    let chineseMeaning: String
    let ambiguity: String?
    let worthChanging: Bool
    let reason: String?
}
