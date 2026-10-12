import Foundation

public enum ChatGPTPlanError: Error, Equatable {
    case httpStatus(Int, String?)
    case invalidResponse
    case incomplete
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
    private let transport: any HTTPTransport

    public init(token: String, model: String, transport: any HTTPTransport = URLSessionTransport()) {
        self.token = token
        self.model = model
        self.transport = transport
    }

    public func listModels() async throws -> [PlanModel] {
        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/models")!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw ChatGPTPlanError.invalidResponse }
        guard (200..<300).contains(response.statusCode) else { throw ChatGPTPlanError.httpStatus(response.statusCode, Self.errorCode(from: data)) }
        let envelope = try JSONDecoder().decode(ModelEnvelope.self, from: data)
        return envelope.models.filter { $0.visibility == "list" }
    }

    public func analyze(_ input: AnalysisInput) async throws -> AnalysisResult {
        let request = try makeRequest(input)
        let (data, response) = try await transport.send(request)
        guard (200..<300).contains(response.statusCode) else {
            throw ChatGPTPlanError.httpStatus(response.statusCode, Self.errorCode(from: data))
        }
        return try Self.parse(data, source: input.source)
    }

    public func makeRequest(_ input: AnalysisInput) throws -> URLRequest {
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
            "stream": false,
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

    public static func parse(_ data: Data, source: String? = nil) throws -> AnalysisResult {
        guard let response = try? JSONDecoder().decode(PlanResponse.self, from: data) else {
            throw ChatGPTPlanError.invalidResponse
        }
        guard response.status == "completed" else { throw ChatGPTPlanError.incomplete }
        guard let text = response.output.compactMap(\.content).flatMap({ $0 })
            .first(where: { $0.type == "output_text" })?.text else {
            throw ChatGPTPlanError.invalidResponse
        }
        guard let data = text.data(using: .utf8),
              let output = try? JSONDecoder().decode(Payload.self, from: data) else {
            throw ChatGPTPlanError.invalidResponse
        }
        return try AnalysisResult(english: output.english, chineseMeaning: output.chineseMeaning, ambiguity: output.ambiguity, worthChanging: output.worthChanging, reason: output.reason, source: source)
    }

    static func errorCode(from data: Data) -> String? {
        guard let body = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let error = body["error"] as? [String: Any] else { return nil }
        return error["code"] as? String
    }
}

private struct PlanResponse: Decodable {
    let status: String
    let output: [PlanOutputItem]
}

private struct PlanOutputItem: Decodable {
    let content: [PlanOutputContent]?
}

private struct PlanOutputContent: Decodable {
    let type: String
    let text: String?
}

private struct ModelEnvelope: Decodable {
    let models: [PlanModel]
}

private struct Payload: Decodable {
    let english: String
    let chineseMeaning: String
    let ambiguity: String?
    let worthChanging: Bool
    let reason: String?
}
