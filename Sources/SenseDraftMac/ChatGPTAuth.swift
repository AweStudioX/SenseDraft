import AppKit
import CryptoKit
import Darwin
import Foundation
import Security

enum ChatGPTAuthError: Error {
    case callbackUnavailable
    case callbackTimedOut
    case invalidCallback
    case denied
    case invalidToken
    case missingPlanPermission
    case httpStatus(Int)
}

@MainActor
enum ChatGPTAuth {
    private static let resource = "https://api.openai.com/v1"
    private static let tokenURL = URL(string: "https://auth.openai.com/api/accounts/oauth/token")!

    static func signIn() async throws -> PlanAccount {
        let previous = try PlanAccountStore.load()
        let registeredClientID = previous?.clientID ?? UserDefaults.standard.string(forKey: "chatgptClientID")
        let listener = try LoopbackCallback()
        defer { listener.close() }
        let redirectURI = "http://127.0.0.1:\(listener.port)/auth/callback"
        let state = try randomURLSafe(32)
        let nonce = try randomURLSafe(32)
        let verifier = try randomURLSafe(64)
        let challenge = Data(SHA256.hash(data: Data(verifier.utf8))).base64URL
        let hostID: String
        if let saved = UserDefaults.standard.string(forKey: "chatgptHostID") { hostID = saved }
        else {
            hostID = "urn:uuid:\(UUID().uuidString.lowercased())"
            UserDefaults.standard.set(hostID, forKey: "chatgptHostID")
        }

        var components = URLComponents(string: "https://auth.openai.com/api/accounts/authorize")!
        var items = [
            URLQueryItem(name: "client_id", value: registeredClientID ?? "dynamic_agent_client"),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "scope", value: "openid profile email offline_access resource.invoke chatgpt.tokens.use.direct"),
            URLQueryItem(name: "resource", value: resource),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "nonce", value: nonce),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "ext_agent_host_id", value: hostID)
        ]
        if let previous {
            items.append(URLQueryItem(name: "id_token_hint", value: previous.idToken))
            if let email = previous.email { items.append(URLQueryItem(name: "login_hint", value: email)) }
        }
        if registeredClientID == nil {
            items.append(URLQueryItem(name: "agent_name_hint", value: "SenseDraft"))
        }
        components.queryItems = items
        guard let url = components.url, NSWorkspace.shared.open(url) else { throw ChatGPTAuthError.callbackUnavailable }
        let callback = try await withTaskCancellationHandler {
            try await listener.waitForCallback()
        } onCancel: {
            listener.close()
        }
        var query: [String: String] = [:]
        for item in callback.queryItems ?? [] {
            guard query[item.name] == nil, let value = item.value else { throw ChatGPTAuthError.invalidCallback }
            query[item.name] = value
        }
        guard query["state"] == state else { throw ChatGPTAuthError.invalidCallback }
        if query["error"] != nil { throw ChatGPTAuthError.denied }
        guard let code = query["code"], !code.isEmpty else { throw ChatGPTAuthError.invalidCallback }
        let clientID = registeredClientID ?? query["client_id"]
        guard let clientID, clientID != "dynamic_agent_client", !clientID.isEmpty,
              registeredClientID == nil || query["client_id"] == nil || query["client_id"] == registeredClientID else {
            throw ChatGPTAuthError.invalidCallback
        }
        UserDefaults.standard.set(clientID, forKey: "chatgptClientID")
        let token = try await exchange([
            "grant_type": "authorization_code", "client_id": clientID, "code": code,
            "code_verifier": verifier, "redirect_uri": redirectURI, "resource": resource
        ])
        let identity = try await verifyIDToken(token.idToken, clientID: clientID, nonce: nonce)
        try Task.checkCancellation()
        if let previous, previous.subject != identity.subject { throw ChatGPTAuthError.invalidToken }
        let account = PlanAccount(
            clientID: clientID, subject: identity.subject, email: identity.email,
            idToken: token.idToken, accessToken: token.accessToken, refreshToken: token.refreshToken,
            scopes: token.scope, expiresAt: Date().addingTimeInterval(TimeInterval(token.expiresIn))
        )
        guard account.canUsePlan else { throw ChatGPTAuthError.missingPlanPermission }
        try PlanAccountStore.save(account)
        return account
    }

    static func validAccount() async throws -> PlanAccount? {
        guard let current = try PlanAccountStore.load() else { return nil }
        guard current.canUsePlan else { throw ChatGPTAuthError.missingPlanPermission }
        if current.expiresAt > Date().addingTimeInterval(120) { return current }
        let token = try await exchange([
            "grant_type": "refresh_token", "client_id": current.clientID,
            "refresh_token": current.refreshToken, "resource": resource
        ])
        let identity = try await verifyIDToken(token.idToken, clientID: current.clientID, nonce: nil)
        guard identity.subject == current.subject else { throw ChatGPTAuthError.invalidToken }
        let updated = PlanAccount(
            clientID: current.clientID, subject: current.subject, email: current.email,
            idToken: token.idToken, accessToken: token.accessToken, refreshToken: token.refreshToken,
            scopes: token.scope, expiresAt: Date().addingTimeInterval(TimeInterval(token.expiresIn))
        )
        guard updated.canUsePlan else { throw ChatGPTAuthError.missingPlanPermission }
        try PlanAccountStore.save(updated)
        return updated
    }

    private static func exchange(_ fields: [String: String]) async throws -> TokenResponse {
        var request = URLRequest(url: tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var components = URLComponents()
        components.queryItems = fields.map { URLQueryItem(name: $0.key, value: $0.value) }
        request.httpBody = components.percentEncodedQuery?.data(using: .utf8)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw ChatGPTAuthError.invalidToken }
        guard response.statusCode == 200 else { throw ChatGPTAuthError.httpStatus(response.statusCode) }
        return try JSONDecoder().decode(TokenResponse.self, from: data)
    }

    private static func verifyIDToken(_ token: String, clientID: String, nonce: String?) async throws -> Identity {
        let parts = token.split(separator: ".")
        guard parts.count == 3,
              let headerData = Data(base64URL: String(parts[0])),
              let payloadData = Data(base64URL: String(parts[1])),
              let signature = Data(base64URL: String(parts[2])),
              let header = try? JSONDecoder().decode(JWTHeader.self, from: headerData),
              header.alg == "RS256",
              let claims = try? JSONDecoder().decode(IDClaims.self, from: payloadData),
              claims.iss == "https://auth.openai.com", claims.aud.contains(clientID),
              (nonce == nil || claims.nonce == nonce), claims.exp > Date().timeIntervalSince1970,
              !claims.sub.isEmpty else { throw ChatGPTAuthError.invalidToken }

        let (configData, _) = try await URLSession.shared.data(from: URL(string: "https://auth.openai.com/.well-known/openid-configuration")!)
        let config = try JSONDecoder().decode(OIDCConfiguration.self, from: configData)
        guard let jwksURL = URL(string: config.jwksURI), jwksURL.scheme == "https", jwksURL.host == "auth.openai.com" else {
            throw ChatGPTAuthError.invalidToken
        }
        let (jwksData, _) = try await URLSession.shared.data(from: jwksURL)
        let jwks = try JSONDecoder().decode(JWKS.self, from: jwksData)
        guard let jwk = jwks.keys.first(where: { $0.kid == header.kid && $0.kty == "RSA" }),
              let modulus = Data(base64URL: jwk.n), let exponent = Data(base64URL: jwk.e) else {
            throw ChatGPTAuthError.invalidToken
        }
        let der = ASN1.sequence(ASN1.integer(modulus) + ASN1.integer(exponent))
        let attrs: [String: Any] = [kSecAttrKeyType as String: kSecAttrKeyTypeRSA, kSecAttrKeyClass as String: kSecAttrKeyClassPublic]
        guard let publicKey = SecKeyCreateWithData(der as CFData, attrs as CFDictionary, nil),
              SecKeyVerifySignature(publicKey, .rsaSignatureMessagePKCS1v15SHA256,
                                    Data("\(parts[0]).\(parts[1])".utf8) as CFData,
                                    signature as CFData, nil) else { throw ChatGPTAuthError.invalidToken }
        return Identity(subject: claims.sub, email: claims.email)
    }

    private static func randomURLSafe(_ count: Int) throws -> String {
        var bytes = [UInt8](repeating: 0, count: count)
        guard SecRandomCopyBytes(kSecRandomDefault, count, &bytes) == errSecSuccess else {
            throw ChatGPTAuthError.invalidToken
        }
        return Data(bytes).base64URL
    }
}

private struct Identity { let subject: String; let email: String? }
private struct TokenResponse: Decodable {
    let accessToken: String
    let refreshToken: String
    let idToken: String
    let scope: String
    let expiresIn: Int
    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token", refreshToken = "refresh_token", idToken = "id_token"
        case scope, expiresIn = "expires_in"
    }
}
private struct JWTHeader: Decodable { let alg: String; let kid: String }
private struct IDClaims: Decodable {
    let iss: String
    let aud: Audience
    let sub: String
    let nonce: String?
    let exp: Double
    let email: String?
}
private enum Audience: Decodable {
    case one(String), many([String])
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(String.self) { self = .one(value) }
        else { self = .many(try container.decode([String].self)) }
    }
    func contains(_ value: String) -> Bool {
        switch self { case .one(let item): item == value; case .many(let items): items.contains(value) }
    }
}
private struct OIDCConfiguration: Decodable {
    let jwksURI: String
    enum CodingKeys: String, CodingKey { case jwksURI = "jwks_uri" }
}
private struct JWKS: Decodable { let keys: [JWK] }
private struct JWK: Decodable { let kid: String; let kty: String; let n: String; let e: String }

private extension Data {
    var base64URL: String { base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "") }
    init?(base64URL: String) {
        var text = base64URL.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        text += String(repeating: "=", count: (4 - text.count % 4) % 4)
        self.init(base64Encoded: text)
    }
}

private enum ASN1 {
    static func length(_ count: Int) -> Data {
        if count < 128 { return Data([UInt8(count)]) }
        var value = count
        var bytes: [UInt8] = []
        while value > 0 { bytes.insert(UInt8(value & 255), at: 0); value >>= 8 }
        return Data([UInt8(0x80 | bytes.count)] + bytes)
    }
    static func integer(_ value: Data) -> Data {
        var bytes = value
        while bytes.count > 1 && bytes.first == 0 { bytes.removeFirst() }
        if let first = bytes.first, first & 0x80 != 0 { bytes.insert(0, at: 0) }
        return Data([0x02]) + length(bytes.count) + bytes
    }
    static func sequence(_ value: Data) -> Data { Data([0x30]) + length(value.count) + value }
}

private final class LoopbackCallback: @unchecked Sendable {
    let port: UInt16
    private let fd: Int32
    private let lock = NSLock()
    private var closed = false

    init() throws {
        let socketFD = Darwin.socket(AF_INET, SOCK_STREAM, 0)
        guard socketFD >= 0 else { throw ChatGPTAuthError.callbackUnavailable }
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = 0
        address.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))
        let bindResult = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.bind(socketFD, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
        }
        guard bindResult == 0, Darwin.listen(socketFD, 1) == 0 else {
            Darwin.close(socketFD)
            throw ChatGPTAuthError.callbackUnavailable
        }
        var size = socklen_t(MemoryLayout<sockaddr_in>.size)
        let nameResult = withUnsafeMutablePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.getsockname(socketFD, $0, &size) }
        }
        guard nameResult == 0 else {
            Darwin.close(socketFD)
            throw ChatGPTAuthError.callbackUnavailable
        }
        fd = socketFD
        port = UInt16(bigEndian: address.sin_port)
    }

    func close() {
        lock.lock()
        defer { lock.unlock() }
        if !closed { closed = true; Darwin.close(fd) }
    }

    private var isClosed: Bool {
        lock.lock()
        defer { lock.unlock() }
        return closed
    }

    func waitForCallback() async throws -> URLComponents {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                var ready = false
                for _ in 0..<600 {
                    if self.isClosed {
                        continuation.resume(throwing: CancellationError())
                        return
                    }
                    var descriptor = pollfd(fd: self.fd, events: Int16(POLLIN), revents: 0)
                    if Darwin.poll(&descriptor, 1, 1000) > 0 {
                        if self.isClosed {
                            continuation.resume(throwing: CancellationError())
                            return
                        }
                        ready = true
                        break
                    }
                }
                guard ready else { continuation.resume(throwing: ChatGPTAuthError.callbackTimedOut); return }
                let client = Darwin.accept(self.fd, nil, nil)
                guard client >= 0 else {
                    continuation.resume(throwing: self.isClosed ? CancellationError() : ChatGPTAuthError.invalidCallback)
                    return
                }
                defer { Darwin.close(client) }
                var buffer = [UInt8](repeating: 0, count: 8192)
                let count = Darwin.read(client, &buffer, buffer.count)
                let request = count > 0 ? String(decoding: buffer.prefix(Int(count)), as: UTF8.self) : ""
                let path = request.split(separator: "\r\n").first?.split(separator: " ").dropFirst().first.map(String.init)
                let response = "HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nConnection: close\r\n\r\nSenseDraft sign-in received. You can return to the app."
                _ = response.withCString { Darwin.write(client, $0, strlen($0)) }
                guard let path, path.hasPrefix("/auth/callback"),
                      let components = URLComponents(string: "http://127.0.0.1:\(self.port)\(path)") else {
                    continuation.resume(throwing: ChatGPTAuthError.invalidCallback)
                    return
                }
                continuation.resume(returning: components)
            }
        }
    }
}
