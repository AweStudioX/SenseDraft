import ApplicationServices
@testable import SenseDraftMac
import XCTest

final class CapturedInputFocusTests: XCTestCase {
    @MainActor
    func testKeyboardCaptureWithFocusedElementCanReplaceFromPanel() {
        let window = AXUIElementCreateApplication(42)
        let element = AXUIElementCreateSystemWide()
        let field = KeyboardField(pid: 42, appID: "example.editor", window: window,
                                  focusedElement: element, windowTitle: nil, source: "Original",
                                  bounds: nil, selection: nil)

        XCTAssertTrue(CapturedInput.keyboard(field).canRestoreFocusFromPanel)
    }

    @MainActor
    func testKeyboardCaptureWithoutFocusedElementRequiresEditorShortcut() {
        let window = AXUIElementCreateApplication(42)
        let field = KeyboardField(pid: 42, appID: "example.editor", window: window,
                                  focusedElement: nil, windowTitle: nil, source: "Original",
                                  bounds: nil, selection: nil)

        XCTAssertFalse(CapturedInput.keyboard(field).canRestoreFocusFromPanel)
    }

    @MainActor
    func testKeyboardCaptureFocusedOnWindowRequiresEditorShortcut() {
        let window = AXUIElementCreateApplication(42)
        let field = KeyboardField(pid: 42, appID: "example.editor", window: window,
                                  focusedElement: window, windowTitle: nil, source: "Original",
                                  bounds: nil, selection: nil)

        XCTAssertFalse(CapturedInput.keyboard(field).canRestoreFocusFromPanel)
    }
}
