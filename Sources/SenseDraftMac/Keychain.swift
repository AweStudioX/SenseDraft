import Foundation
import Security

enum KeychainError: Error {
    case failure(OSStatus)
}

enum APIKeyStore {
    private static let service = "com.sensedraft.mac.openai"

    static func load() throws -> String? {
        try ProviderKeyStore.load(service: service)
    }

    static func save(_ key: String) throws {
        try ProviderKeyStore.save(key, service: service)
    }

    static func remove() throws {
        try ProviderKeyStore.remove(service: service)
    }
}

enum ProviderKeyStore {
    private static let account = "api-key"

    static func contains(service: String) throws -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        let status = SecItemCopyMatching(query as CFDictionary, nil)
        if status == errSecItemNotFound { return false }
        guard status == errSecSuccess else { throw KeychainError.failure(status) }
        return true
    }

    static func load(service: String) throws -> String? {
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
        guard status == errSecSuccess, let data = result as? Data,
              let key = String(data: data, encoding: .utf8) else {
            throw KeychainError.failure(status)
        }
        return key
    }

    static func save(_ key: String, service: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let data = Data(key.utf8)
        let updateStatus = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if updateStatus == errSecSuccess { return }
        guard updateStatus == errSecItemNotFound else { throw KeychainError.failure(updateStatus) }
        var add = query
        add[kSecValueData as String] = data
        let addStatus = SecItemAdd(add as CFDictionary, nil)
        guard addStatus == errSecSuccess else { throw KeychainError.failure(addStatus) }
    }

    static func remove(service: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw KeychainError.failure(status) }
    }
}

@MainActor
final class ProviderCredentialCache {
    private let loader: (String) throws -> String?
    private var values: [String: String] = [:]

    init(loader: @escaping (String) throws -> String?) {
        self.loader = loader
    }

    func load(service: String) throws -> String? {
        if let value = values[service] { return value }
        guard let value = try loader(service) else { return nil }
        values[service] = value
        return value
    }

    func recordSave(_ value: String, service: String) {
        values[service] = value
    }

    func remove(service: String) {
        values.removeValue(forKey: service)
    }
}
