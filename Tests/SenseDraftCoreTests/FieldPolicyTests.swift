import XCTest
@testable import SenseDraftCore

final class FieldPolicyTests: XCTestCase {
    func testMultilineEditorUsesVerifiedKeyboardReplacement() {
        XCTAssertEqual(FieldPolicy.replacementMethod(role: "AXTextArea"), .verifiedKeyboard)
        XCTAssertEqual(FieldPolicy.replacementMethod(role: "AXTextField"), .directAccessibility)
    }

    func testPlainAccessibleMultilineInputDoesNotRequireFormattingConfirmation() {
        XCTAssertFalse(FieldPolicy.needsFormattingConfirmation(capturedWithKeyboard: false,
                                                                 hasMixedFormatting: false))
        XCTAssertTrue(FieldPolicy.needsFormattingConfirmation(capturedWithKeyboard: false,
                                                                hasMixedFormatting: true))
        XCTAssertTrue(FieldPolicy.needsFormattingConfirmation(capturedWithKeyboard: true,
                                                                hasMixedFormatting: false))
    }

    func testChineseAndMixedInputAreAccepted() throws {
        XCTAssertNoThrow(try FieldPolicy.validate(role: "AXTextArea", protected: false, editable: true, value: "请帮我看看这个版本"))
        XCTAssertNoThrow(try FieldPolicy.validate(role: "AXTextArea", protected: false, editable: true, value: "Please review 这个版本"))
    }

    func testJapaneseKanaIsRejected() {
        XCTAssertThrowsError(try FieldPolicy.validate(role: "AXTextArea", protected: false, editable: true, value: "こんにちは")) { error in
            XCTAssertEqual(error as? FieldError, .nonEnglish)
        }
    }
    func testEditableTextAreaIsAccepted() throws {
        XCTAssertNoThrow(try FieldPolicy.validate(role: "AXTextArea", protected: false, editable: true, value: "Hello"))
    }

    func testProtectedFieldIsRejected() {
        XCTAssertThrowsError(try FieldPolicy.validate(role: "AXTextField", protected: true, editable: true, value: "secret")) { error in
            XCTAssertEqual(error as? FieldError, .protected)
        }
    }

    func testBlankNoneditableAndUnsupportedFieldsAreRejected() {
        XCTAssertThrowsError(try FieldPolicy.validate(role: "AXTextField", protected: false, editable: true, value: "   "))
        XCTAssertThrowsError(try FieldPolicy.validate(role: "AXTextField", protected: false, editable: false, value: "Hello"))
        XCTAssertThrowsError(try FieldPolicy.validate(role: "AXButton", protected: false, editable: true, value: "Hello"))
    }
}
