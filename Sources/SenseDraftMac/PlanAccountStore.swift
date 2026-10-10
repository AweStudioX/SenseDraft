import Foundation
import Security

struct PlanAccount: Codable, Sendable {
    let clientID: String
    let subject: String
    let email: String?
    let idToken: String
    let accessToken: String
    let refreshToken: String
    let scopes: String
    let expiresAt: Date

    var canUsePlan: Bool { Set(scopes.split(separator: " ").map(String.init)).contains("chatgpt.tokens.use.direct") }
}

enum PlanAccountStore {
    private static let service = "com.sensedraft.mac.chatgpt"
    private static let account = "active-account"

    static func load() throws -> PlanAccount? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else { throw KeychainError.failure(status) }
        return try JSONDecoder().decode(PlanAccount.self, from: data)
    }

    static func save(_ value: PlanAccount) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let data = try JSONEncoder().encode(value)
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecSuccess { return }
        guard status == errSecItemNotFound else { throw KeychainError.failure(status) }
        var add = query
        add[kSecValueData as String] = data
        let added = SecItemAdd(add as CFDictionary, nil)
        guard added == errSecSuccess else { throw KeychainError.failure(added) }
    }

    static func remove() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw KeychainError.failure(status) }
    }
}
