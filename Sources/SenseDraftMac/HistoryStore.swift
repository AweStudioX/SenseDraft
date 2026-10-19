import Foundation
import Security
import SenseDraftCore

private enum HistoryStorageError: LocalizedError {
    case missingKey

    var errorDescription: String? {
        "The encryption key is missing. Delete the unreadable history to start again."
    }
}

@MainActor
final class HistoryStore: ObservableObject {
    @Published private(set) var entries: [HistoryEntry] = []
    @Published private(set) var errorMessage: String?

    private let fileURL: URL
    private let storageAvailable: Bool
    private var canWrite = true
    private var retention: HistoryRetention
    private let keyService = "com.kaaaaai.SenseDraft.history"
    private var pruneTimer: Timer?

    init(retention: HistoryRetention) {
        self.retention = retention
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first?.appendingPathComponent("SenseDraft", isDirectory: true)
        storageAvailable = directory != nil
        fileURL = (directory ?? FileManager.default.temporaryDirectory)
            .appendingPathComponent("history.enc")
        if directory == nil {
            errorMessage = "Application Support is unavailable. History cannot be loaded."
            return
        }
        do {
            if FileManager.default.fileExists(atPath: fileURL.path) {
                let encrypted = try Data(contentsOf: fileURL)
                let key = try loadKey(createIfMissing: false)
                entries = try HistoryArchive.open(encrypted, key: key)
                pruneExpired()
            }
        } catch {
            canWrite = false
            errorMessage = "Could not open local history: \(error.localizedDescription)"
        }
        pruneTimer = Timer.scheduledTimer(withTimeInterval: 3_600, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.pruneExpired() }
        }
    }

    func record(_ entry: HistoryEntry) {
        save(HistoryLedger.upsert(entry, into: entries, retention: retention))
    }

    func setRetention(_ value: HistoryRetention) {
        retention = value
        pruneExpired()
    }

    func pruneExpired() {
        let current = HistoryLedger.prune(entries, retention: retention)
        if current.count != entries.count { save(current) }
    }

    func markReplaced(_ id: UUID, english: String) {
        guard entries.contains(where: { $0.id == id }) else { return }
        save(HistoryLedger.markReplaced(id, english: english, in: entries))
    }

    @discardableResult
    func remove(_ id: UUID) -> Bool {
        save(entries.filter { $0.id != id })
        return !entries.contains { $0.id == id }
    }

    func clear() {
        do {
            if FileManager.default.fileExists(atPath: fileURL.path) {
                try FileManager.default.removeItem(at: fileURL)
            }
            entries = []
            canWrite = true
            errorMessage = nil
        } catch {
            errorMessage = "Could not clear local history: \(error.localizedDescription)"
        }
    }

    private func save(_ candidate: [HistoryEntry]) {
        guard storageAvailable, canWrite else { return }
        do {
            let directory = fileURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700])
            let combined = try HistoryArchive.seal(candidate, key: loadKey(createIfMissing: true))
            try combined.write(to: fileURL, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
            entries = candidate
            errorMessage = nil
        } catch {
            errorMessage = "Could not save local history: \(error.localizedDescription)"
        }
    }

    private func loadKey(createIfMissing: Bool) throws -> Data {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keyService,
            kSecAttrAccount as String: "encryption-key"
        ]
        var readQuery = query
        readQuery[kSecReturnData as String] = true
        readQuery[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(readQuery as CFDictionary, &item)
        if status == errSecSuccess, let data = item as? Data {
            return data
        }
        guard status == errSecItemNotFound else { throw KeychainError.failure(status) }
        guard createIfMissing else { throw HistoryStorageError.missingKey }
        var key = Data(count: 32)
        let randomStatus = key.withUnsafeMutableBytes { bytes in
            SecRandomCopyBytes(kSecRandomDefault, bytes.count, bytes.baseAddress!)
        }
        guard randomStatus == errSecSuccess else { throw KeychainError.failure(randomStatus) }
        var addQuery = query
        addQuery[kSecValueData as String] = key
        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        guard addStatus == errSecSuccess else { throw KeychainError.failure(addStatus) }
        return key
    }
}
