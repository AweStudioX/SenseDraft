import AppKit
import XCTest
@testable import SenseDraftMac

final class ReviewHoverPlacementTests: XCTestCase {
    func testTopRightButtonPositionsSidecarAtTopRight() {
        let origin = ReviewHoverPlacement.origin(
            review: CGRect(x: 20, y: 100, width: 800, height: 500),
            pointer: CGPoint(x: 800, y: 580),
            sidecar: CGSize(width: 280, height: 160),
            visible: CGRect(x: 0, y: 0, width: 1200, height: 800))

        XCTAssertEqual(origin, CGPoint(x: 828, y: 420))
    }

    func testBottomLeftButtonPositionsSidecarAtBottomLeft() {
        let origin = ReviewHoverPlacement.origin(
            review: CGRect(x: 350, y: 100, width: 700, height: 500),
            pointer: CGPoint(x: 370, y: 120),
            sidecar: CGSize(width: 280, height: 160),
            visible: CGRect(x: 0, y: 0, width: 1200, height: 800))

        XCTAssertEqual(origin, CGPoint(x: 62, y: 120))
    }

    func testBottomRightButtonPositionsSidecarAtBottomRight() {
        let origin = ReviewHoverPlacement.origin(
            review: CGRect(x: 20, y: 100, width: 800, height: 500),
            pointer: CGPoint(x: 800, y: 120),
            sidecar: CGSize(width: 280, height: 160),
            visible: CGRect(x: 0, y: 0, width: 1200, height: 800))

        XCTAssertEqual(origin, CGPoint(x: 828, y: 120))
    }

    func testBelowReviewIsUsedBeforeOverlappingWhenNeitherSideFits() {
        let origin = ReviewHoverPlacement.origin(
            review: CGRect(x: 100, y: 250, width: 1000, height: 300),
            pointer: CGPoint(x: 300, y: 270),
            sidecar: CGSize(width: 280, height: 160),
            visible: CGRect(x: 0, y: 0, width: 1100, height: 800))

        XCTAssertEqual(origin, CGPoint(x: 160, y: 82))
    }
}
