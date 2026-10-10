import XCTest
@testable import SenseDraftCore

final class OAuthFailureTests: XCTestCase {
    func testStandardTokenError() {
        let body = Data(#"{"error":"invalid_grant","error_description":"Authorization code expired"}"#.utf8)
        XCTAssertEqual(OAuthFailure.parse(body)?.code, "invalid_grant")
    }

    func testNestedTokenError() {
        let body = Data(#"{"error":{"code":"invalid_client","message":"Client is not registered"}}"#.utf8)
        XCTAssertEqual(OAuthFailure.parse(body)?.code, "invalid_client")
    }

    func testMalformedBodyHasNoCode() {
        XCTAssertNil(OAuthFailure.parse(Data("not json".utf8)))
    }
}
