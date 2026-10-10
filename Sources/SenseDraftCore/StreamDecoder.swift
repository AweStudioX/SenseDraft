import Foundation

public enum StreamDecoderError: Error, Equatable {
    case failed(String)
    case incomplete
    case interrupted
    case invalidEvent
}

public enum StreamDecoder {
    public static func consume(_ stream: String) throws -> String {
        var output = ""
        var completed = false
        for frame in stream.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n\n") {
            let data = frame.split(separator: "\n").compactMap { line -> String? in
                guard line.hasPrefix("data:") else { return nil }
                return String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces)
            }.joined(separator: "\n")
            guard !data.isEmpty, data != "[DONE]" else { continue }
            guard let bytes = data.data(using: .utf8),
                  let event = try? JSONDecoder().decode(StreamEvent.self, from: bytes) else {
                throw StreamDecoderError.invalidEvent
            }
            switch event.type {
            case "response.output_text.delta": output += event.delta ?? ""
            case "response.completed": completed = true
            case "response.failed": throw StreamDecoderError.failed(event.response?.error?.code ?? "unknown_error")
            case "response.incomplete": throw StreamDecoderError.incomplete
            default: break
            }
        }
        guard completed else { throw StreamDecoderError.interrupted }
        return output
    }
}

private struct StreamEvent: Decodable {
    let type: String
    let delta: String?
    let response: StreamResponse?
}

private struct StreamResponse: Decodable {
    let error: StreamError?
}

private struct StreamError: Decodable {
    let code: String?
}
