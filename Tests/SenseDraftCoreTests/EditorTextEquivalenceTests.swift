import XCTest
@testable import SenseDraftCore

final class EditorTextEquivalenceTests: XCTestCase {
    func testChromiumTrailingZeroWidthPlaceholdersMatchCopiedVisibleText() {
        let visible = "pls check it for me about the question"
        XCTAssertTrue(EditorTextEquivalence.matchesAccessibilityAndCopy(
            accessibility: visible + "\u{200B}\n\u{200B}\n\u{200B}", copied: visible))
    }

    func testRealNewlinesAndInternalZeroWidthCharactersRemainSignificant() {
        XCTAssertFalse(EditorTextEquivalence.matchesAccessibilityAndCopy(
            accessibility: "first\nsecond", copied: "firstsecond"))
        XCTAssertFalse(EditorTextEquivalence.matchesAccessibilityAndCopy(
            accessibility: "first\u{200B}second", copied: "firstsecond"))
        XCTAssertFalse(EditorTextEquivalence.matchesAccessibilityAndCopy(
            accessibility: "first\n\u{200B}", copied: "first"))
    }

    func testChangedPlaceholderCountDoesNotChangeVisibleAccessibilityText() {
        XCTAssertTrue(EditorTextEquivalence.matchesAccessibilityValues(
            "draft\u{200B}\n\u{200B}", "draft\u{200B}"))
        XCTAssertFalse(EditorTextEquivalence.matchesAccessibilityValues(
            "draft\u{200B}", "different\u{200B}"))
    }
}
