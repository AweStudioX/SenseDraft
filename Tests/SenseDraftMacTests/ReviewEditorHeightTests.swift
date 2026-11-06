@testable import SenseDraftMac
import XCTest

final class ReviewEditorHeightTests: XCTestCase {
    func testShortTextKeepsCompactMinimum() {
        XCTAssertEqual(ReviewEditorHeight.calculate(text: "Short", width: 500,
                                                    minimum: 44, maximum: 120), 44)
    }

    func testWrappedTextGrowsBeforeItReachesTheCap() {
        let text = String(repeating: "中文内容", count: 12)
        let wide = ReviewEditorHeight.calculate(text: text, width: 500,
                                                minimum: 40, maximum: 120)
        let narrow = ReviewEditorHeight.calculate(text: text, width: 220,
                                                  minimum: 40, maximum: 120)

        XCTAssertGreaterThan(wide, 40)
        XCTAssertGreaterThan(narrow, wide)
        XCTAssertLessThan(narrow, 120)
    }

    func testVeryLongTextStopsAtMaximum() {
        let text = String(repeating: "This is a longer sentence. ", count: 80)

        XCTAssertEqual(ReviewEditorHeight.calculate(text: text, width: 220,
                                                    minimum: 40, maximum: 120), 120)
    }

    func testSourceTextAlsoGrowsWithItsOwnHeightLimit() {
        let text = String(repeating: "A longer original sentence that should wrap. ", count: 12)

        XCTAssertGreaterThan(ReviewEditorHeight.calculate(text: text, width: 500,
                                                          minimum: 28, maximum: 100,
                                                          verticalInset: 4), 28)
        XCTAssertEqual(ReviewEditorHeight.calculate(text: text, width: 200,
                                                    minimum: 28, maximum: 100,
                                                    verticalInset: 4), 100)
    }
}
