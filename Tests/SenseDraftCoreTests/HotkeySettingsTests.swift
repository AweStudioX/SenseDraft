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

    func testModifierIsRequired() {
        XCTAssertThrowsError(try HotkeySettings(analyze: .init(keyCode: 14, modifiers: 0), replace: .defaultReplace))
        XCTAssertThrowsError(try HotkeySettings(analyze: .init(keyCode: 14, modifiers: 512), replace: .defaultReplace))
    }
}
