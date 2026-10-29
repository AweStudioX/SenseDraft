@testable import SenseDraftMac
import XCTest

final class KeyboardWindowSelectionTests: XCTestCase {
    func testSingleWindowCanBeUsedWhenFocusedAndMainWindowAreUnavailable() {
        XCTAssertEqual(KeyboardWindowSelection.choose(focused: nil, ancestor: nil,
                                                     main: nil, windows: ["window-1"]), "window-1")
    }

    func testMultipleWindowsRemainAmbiguousWithoutFocus() {
        XCTAssertNil(KeyboardWindowSelection.choose(focused: nil, ancestor: nil,
                                                   main: nil, windows: ["window-1", "window-2"]))
    }

    func testFocusedElementAncestorWinsOverMainWindow() {
        XCTAssertEqual(KeyboardWindowSelection.choose(focused: nil, ancestor: "window-2",
                                                     main: "window-1", windows: ["window-1", "window-2"]), "window-2")
    }
}
