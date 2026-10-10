import XCTest
@testable import SenseDraftCore

final class HotkeySettingsTests: XCTestCase {
    func testDefaultsUseDifferentShortcuts() throws {
        let settings = HotkeySettings.defaults
        XCTAssertNotEqual(settings.analyze, settings.replace)
        XCTAssertEqual(settings.analyze, .defaultAnalyze)
        XCTAssertEqual(settings.replace, .defaultReplace)
    }

    func testIdenticalShortcutsAreRejected() {
        let shortcut = Shortcut(keyCode: 14, modifiers: 2304)
        XCTAssertThrowsError(try HotkeySettings(analyze: shortcut, replace: shortcut))
    }
}
