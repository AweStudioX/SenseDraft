import XCTest
@testable import SenseDraftCore

final class EditorTextEquivalenceTests: XCTestCase {
    func testRepeatedCopiesAcceptOnlyFormattingEquivalentText() {
        XCTAssertTrue(EditorTextEquivalence.matchesRepeatedCopies("第一行\r\n第二行", "第一行\n第二行"))
        XCTAssertTrue(EditorTextEquivalence.matchesRepeatedCopies("cafe\u{301}", "café"))
        XCTAssertTrue(EditorTextEquivalence.matchesRepeatedCopies("中文\u{200B}", "中文"))
        XCTAssertFalse(EditorTextEquivalence.matchesRepeatedCopies("第一行\n第二行", "第一行\n新内容"))
        XCTAssertFalse(EditorTextEquivalence.matchesRepeatedCopies("中文", "中文。"))
    }

    func testVerifiedAccessibilityCanIgnoreCopyOnlyTerminalNewline() {
        XCTAssertTrue(EditorTextEquivalence.matchesVerifiedAccessibilityAndCopy(
            accessibility: "中文内容", copied: "中文内容\n"))
        XCTAssertTrue(EditorTextEquivalence.matchesVerifiedAccessibilityAndCopy(
            accessibility: "中文内容", copied: "中文内容\r\n"))
        XCTAssertFalse(EditorTextEquivalence.matchesVerifiedAccessibilityAndCopy(
            accessibility: "中文内容", copied: "中文内容。"))
        XCTAssertFalse(EditorTextEquivalence.matchesVerifiedAccessibilityAndCopy(
            accessibility: "中文内容", copied: "中文内容\n\n"))
    }

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
