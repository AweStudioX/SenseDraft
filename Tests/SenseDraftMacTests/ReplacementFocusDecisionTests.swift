@testable import SenseDraftMac
import XCTest

final class ReplacementFocusDecisionTests: XCTestCase {
    func testKeyboardReplacementRestoresSourceOnlyFromSenseDraftPanel() {
        XCTAssertEqual(KeyboardReplacementFocusDecision.decide(activePID: 10, sourcePID: 20, ownPID: 10), .activateSource)
        XCTAssertEqual(KeyboardReplacementFocusDecision.decide(activePID: 20, sourcePID: 20, ownPID: 10), .alreadyActive)
        XCTAssertEqual(KeyboardReplacementFocusDecision.decide(activePID: 30, sourcePID: 20, ownPID: 10), .reject)
    }
}
