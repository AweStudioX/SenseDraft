import XCTest
@testable import SenseDraftCore

final class PanelPlacementTests: XCTestCase {
    func testPrefersSideOfFieldWhenItFits() {
        let field = CGRect(x: 100, y: 300, width: 400, height: 80)
        let origin = PanelPlacement.origin(panelSize: CGSize(width: 300, height: 250),
                                           fieldRect: field, visibleFrame: CGRect(x: 0, y: 0, width: 1000, height: 800))
        let panel = CGRect(origin: origin, size: CGSize(width: 300, height: 250))
        XCTAssertTrue(panel.intersection(field).isNull)
        XCTAssertGreaterThanOrEqual(panel.minX, field.maxX)
    }

    func testUsesAboveOrBelowWhenSideDoesNotFit() {
        let field = CGRect(x: 30, y: 310, width: 730, height: 50)
        let origin = PanelPlacement.origin(panelSize: CGSize(width: 300, height: 250),
                                           fieldRect: field, visibleFrame: CGRect(x: 0, y: 0, width: 800, height: 800))
        let panel = CGRect(origin: origin, size: CGSize(width: 300, height: 250))
        XCTAssertTrue(panel.intersection(field).isNull)
    }

    func testRememberedOriginClampsToVisibleScreen() {
        let origin = PanelPlacement.clamp(CGPoint(x: 900, y: -20),
                                          panelSize: CGSize(width: 300, height: 250),
                                          visibleFrame: CGRect(x: 0, y: 0, width: 1000, height: 800))
        XCTAssertEqual(origin, CGPoint(x: 700, y: 0))
    }
}
