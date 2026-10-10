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
        var finalText: String?
        var completed = false
        for frame in stream.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n\n") {
            let data = frame.split(separator: "\n").compactMap { line -> String? in
                guard line.hasPrefix("data:") else { return nil }
                return String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces)
            }.joined(separator: "\n")
            guard !data.isEmpty, data != "[DONE]" else { continue }
            guard let bytes = data.data(using: .utf8),
                  let event = try? JSONSerialization.jsonObject(with: bytes) as? [String: Any] else {
                throw StreamDecoderError.invalidEvent
            }
            if let error = event["error"] as? [String: Any], event["type"] == nil {
                throw StreamDecoderError.failed(error["code"] as? String ?? "unknown_error")
            }
            guard let type = event["type"] as? String else { throw StreamDecoderError.invalidEvent }
            switch type {
            case "response.output_text.delta":
                guard let delta = event["delta"] as? String else { throw StreamDecoderError.invalidEvent }
                output += delta
            case "response.output_text.done":
                finalText = event["text"] as? String
            case "response.completed":
                completed = true
                if output.isEmpty {
                    output = finalText ?? completedText(event) ?? ""
                }
            case "response.failed":
                let response = event["response"] as? [String: Any]
                let error = response?["error"] as? [String: Any]
                throw StreamDecoderError.failed(error?["code"] as? String ?? "unknown_error")
            case "response.incomplete": throw StreamDecoderError.incomplete
            default: break
            }
        }
        guard completed else { throw StreamDecoderError.interrupted }
        return output
    }

    private static func completedText(_ event: [String: Any]) -> String? {
        guard let response = event["response"] as? [String: Any],
              let items = response["output"] as? [[String: Any]] else { return nil }
        for item in items {
            guard let content = item["content"] as? [[String: Any]] else { continue }
            if let text = content.first(where: { $0["type"] as? String == "output_text" })?["text"] as? String {
                return text
            }
        }
        return nil
    }
}
