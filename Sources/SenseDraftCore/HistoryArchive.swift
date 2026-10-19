import CryptoKit
import Foundation

public enum HistoryArchive {
    public static func seal(_ entries: [HistoryEntry], key: Data) throws -> Data {
        let plaintext = try JSONEncoder().encode(entries)
        let box = try AES.GCM.seal(plaintext, using: SymmetricKey(data: key))
        guard let combined = box.combined else { throw ArchiveError.invalidEncryptedData }
        return combined
    }

    public static func open(_ encrypted: Data, key: Data) throws -> [HistoryEntry] {
        let box = try AES.GCM.SealedBox(combined: encrypted)
        let plaintext = try AES.GCM.open(box, using: SymmetricKey(data: key))
        return try JSONDecoder().decode([HistoryEntry].self, from: plaintext)
    }

    public enum ArchiveError: Error {
        case invalidEncryptedData
    }
}
