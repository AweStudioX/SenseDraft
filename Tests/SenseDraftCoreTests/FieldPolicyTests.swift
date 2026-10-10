import XCTest
@testable import SenseDraftCore

final class FieldPolicyTests: XCTestCase {
    func testMixedChineseInputIsRejected() {
        XCTAssertThrowsError(try FieldPolicy.validate(role: "AXTextArea", protected: false, editable: true, value: "Please review 这个版本")) { error in
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
