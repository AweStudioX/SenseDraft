import XCTest
@testable import SenseDraftCore

final class AnalysisTests: XCTestCase {
    func testInputRejectsBlankSource() {
        XCTAssertThrowsError(try AnalysisInput(source: "  \n", locale: "en-US", chineseIntent: nil))
    }

    func testInputKeepsEntireFieldAndLocale() throws {
        let input = try AnalysisInput(source: "First sentence.\nSecond sentence.", locale: "en-US", chineseIntent: nil)
        XCTAssertEqual(input.source, "First sentence.\nSecond sentence.")
        XCTAssertEqual(input.locale, "en-US")
    }

    func testResultRejectsBlankEnglishOrMeaning() {
        XCTAssertThrowsError(try AnalysisResult(english: " ", chineseMeaning: "释义", ambiguity: nil))
        XCTAssertThrowsError(try AnalysisResult(english: "Hello.", chineseMeaning: " ", ambiguity: nil))
    }
}
