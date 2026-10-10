import XCTest
@testable import SenseDraftCore

final class SessionTests: XCTestCase {
    private let snapshot = TargetSnapshot(appID: "com.apple.TextEdit", elementID: "editor-1", source: "Original")

    func testExactSourceCanBeReplaced() {
        let session = AnalysisSession(snapshot: snapshot)
        XCTAssertTrue(session.canReplace(currentAppID: "com.apple.TextEdit", currentElementID: "editor-1", currentValue: "Original"))
    }

    func testChangedSourceCannotBeReplaced() {
        let session = AnalysisSession(snapshot: snapshot)
        XCTAssertFalse(session.canReplace(currentAppID: "com.apple.TextEdit", currentElementID: "editor-1", currentValue: "Original, edited"))
    }

    func testDifferentExternalTargetCannotBeReplaced() {
        let session = AnalysisSession(snapshot: snapshot)
        XCTAssertFalse(session.canReplace(currentAppID: "com.apple.TextEdit", currentElementID: "editor-2", currentValue: "Original"))
        XCTAssertFalse(session.canReplace(currentAppID: "com.apple.mail", currentElementID: "editor-1", currentValue: "Original"))
    }

    func testOlderResponseCannotReplaceNewerRequest() throws {
        let original = AnalysisSession(snapshot: snapshot)
        let newer = AnalysisSession(snapshot: snapshot)
        let result = try AnalysisResult(english: "Revised", chineseMeaning: "修改后", ambiguity: nil)
        XCTAssertFalse(newer.accepts(result: result, for: original.generation))
        XCTAssertTrue(newer.accepts(result: result, for: newer.generation))
    }
}
