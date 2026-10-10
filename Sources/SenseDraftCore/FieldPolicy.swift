import Foundation

public enum FieldError: Error, Equatable {
    case protected
    case unsupportedRole
    case notEditable
    case empty
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
    }
}
