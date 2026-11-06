import AppKit
@testable import SenseDraftMac
import XCTest

final class ReviewPanelKeyActionTests: XCTestCase {
    func testCommandReturnRegeneratesWhileEditing() {
        XCTAssertEqual(ReviewPanelKeyAction.resolve(keyCode: 36, modifiers: [.command], isEditing: true),
                       .regenerate)
        XCTAssertEqual(ReviewPanelKeyAction.resolve(keyCode: 76, modifiers: [.command], isEditing: true),
                       .regenerate)
    }

    func testPlainReturnKeepsEditingBehavior() {
        XCTAssertNil(ReviewPanelKeyAction.resolve(keyCode: 36, modifiers: [], isEditing: true))
        XCTAssertEqual(ReviewPanelKeyAction.resolve(keyCode: 36, modifiers: [], isEditing: false),
                       .replace)
    }

    func testGlobalReplaceShortcutIsNotHandledAsRegenerate() {
        XCTAssertNil(ReviewPanelKeyAction.resolve(keyCode: 36, modifiers: [.command, .option], isEditing: true))
    }
}
