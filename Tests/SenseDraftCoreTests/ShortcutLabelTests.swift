import Carbon
import XCTest
@testable import SenseDraftCore

final class ShortcutLabelTests: XCTestCase {
    func testPreviouslyMissingKeysHaveNames() {
        XCTAssertEqual(ShortcutLabel.keyName(50), "~")
        XCTAssertEqual(ShortcutLabel.keyName(122), "F1")
        XCTAssertEqual(ShortcutLabel.keyName(105), "F13")
        XCTAssertEqual(ShortcutLabel.keyName(83), "Keypad 1")
    }

    func testSavedShortcutsUseCurrentLayoutWithoutChangingKeyCode() {
        let shortcut = Shortcut(keyCode: 50, modifiers: UInt32(cmdKey | optionKey))
        XCTAssertEqual(ShortcutLabel.describe(shortcut), "⌥⌘~")
        XCTAssertEqual(shortcut.keyCode, 50)
        XCTAssertEqual(ShortcutLabel.describe(.defaultAnalyze), "⌥⌘" + ShortcutLabel.keyName(14))
        XCTAssertEqual(ShortcutLabel.describe(.defaultReplace), "⌥⌘↩")
    }

    func testUnknownKeyRemainsExplicit() {
        XCTAssertEqual(ShortcutLabel.keyName(999), "Key 999")
    }

    func testAllStandardFunctionAndKeypadKeysHaveNames() {
        let functionKeys: [UInt32] = [122, 120, 99, 118, 96, 97, 98, 100, 101, 109,
                                      103, 111, 105, 107, 113, 106, 64, 79, 80, 90]
        let keypad: [UInt32] = [65, 67, 69, 71, 75, 76, 78, 81, 82, 83, 84, 85,
                               86, 87, 88, 89, 91, 92, 95]
        for code in functionKeys + keypad {
            XCTAssertFalse(ShortcutLabel.keyName(code).hasPrefix("Key "), "Missing label for \(code)")
        }
    }
}
