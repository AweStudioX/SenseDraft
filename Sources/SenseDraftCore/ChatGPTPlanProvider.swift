import Foundation

public enum ChatGPTPlanError: Error, Equatable {
    case httpStatus(Int)
    case invalidResponse
    case noModels
}

public struct PlanModel: Decodable, Equatable, Sendable {
    public let slug: String
    public let displayName: String
    public let visibility: String

    enum CodingKeys: String, CodingKey {
        case slug
        case displayName = "display_name"
        case visibility
    }
}

public struct ChatGPTPlanProvider: LanguageService {
    private let token: String
    private let model: String

    public init(token: String, model: String) {
        self.token = token
        self.model = model
    }

    public func listModels() async throws -> [PlanModel] {
        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/models")!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw ChatGPTPlanError.invalidResponse }
        guard (200..<300).contains(response.statusCode) else { throw ChatGPTPlanError.httpStatus(response.statusCode) }
        let envelope = try JSONDecoder().decode(ModelEnvelope.self, from: data)
        return envelope.models.filter { $0.visibility == "list" }
    }

    public func analyze(_ input: AnalysisInput) async throws -> AnalysisResult {
        let request = try makeRequest(input)
        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        guard let response = response as? HTTPURLResponse else { throw ChatGPTPlanError.invalidResponse }
        guard (200..<300).contains(response.statusCode) else { throw ChatGPTPlanError.httpStatus(response.statusCode) }
        var stream = ""
        for try await line in bytes.lines {
            stream += line + "\n"
        }
        return try Self.parse(stream)
    }

    public func makeRequest(_ input: AnalysisInput) throws -> URLRequest {
        let schema: [String: Any] = [
            "type": "object",
            "properties": [
                "english": ["type": "string"],
                "chineseMeaning": ["type": "string"],
                "ambiguity": ["type": ["string", "null"]]
            ],
            "required": ["english", "chineseMeaning", "ambiguity"],
            "additionalProperties": false
        ]
        let body: [String: Any] = [
            "model": model,
            "store": false,
            "stream": true,
            "instructions": AnalysisPrompt.instructions(for: input),
            "input": [["role": "user", "content": input.source]],
            "text": ["format": ["type": "json_schema", "name": "sensedraft_analysis", "schema": schema, "strict": true]]
        ]
        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/responses")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    public static func parse(_ stream: String) throws -> AnalysisResult {
        let text = try StreamDecoder.consume(stream)
        guard let data = text.data(using: .utf8),
              let output = try? JSONDecoder().decode(Payload.self, from: data) else {
            throw ChatGPTPlanError.invalidResponse
        }
        return try AnalysisResult(english: output.english, chineseMeaning: output.chineseMeaning, ambiguity: output.ambiguity)
    }
}

private struct ModelEnvelope: Decodable {
    let models: [PlanModel]
}

private struct Payload: Decodable {
    let english: String
    let chineseMeaning: String
    let ambiguity: String?
}
