import Foundation

public enum FieldError: Error, Equatable {
    case protected
    case unsupportedRole
    case notEditable
    case empty
    case nonEnglish
    case unavailable
    case changed
    case writeFailed
}

public enum FieldPolicy {
    public static func validate(role: String, protected: Bool, editable: Bool, value: String) throws {
        guard !protected else { throw FieldError.protected }
        guard role == "AXTextField" || role == "AXTextArea" else { throw FieldError.unsupportedRole }
        guard editable else { throw FieldError.notEditable }
        guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw FieldError.empty }
        let containsCJK = value.unicodeScalars.contains { scalar in
            switch scalar.value {
            case 0x3400...0x9FFF, 0xF900...0xFAFF, 0x3040...0x30FF, 0xAC00...0xD7AF: true
            default: false
            }
        }
        guard !containsCJK else { throw FieldError.nonEnglish }
    }
}
