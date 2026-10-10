import Foundation

public struct OAuthFailure: Equatable, Sendable {
    public let code: String

    public static func parse(_ data: Data) -> OAuthFailure? {
        guard let body = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        let code: String?
        if let error = body["error"] as? String {
            code = error
        } else if let error = body["error"] as? [String: Any] {
            code = error["code"] as? String ?? error["type"] as? String
        } else {
            code = nil
        }
        guard let code, !code.isEmpty, code.count <= 80 else { return nil }
        return OAuthFailure(code: code)
    }
}
