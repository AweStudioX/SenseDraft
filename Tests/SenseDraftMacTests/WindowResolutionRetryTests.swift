@testable import SenseDraftMac
import XCTest

final class WindowResolutionRetryTests: XCTestCase {
    @MainActor
    func testTransientMissingWindowIsRetried() async throws {
        var probes = 0
        let window = try await WindowResolutionRetry.resolve(attempts: 3, interval: .zero,
            isActive: { true }, probe: {
                probes += 1
                return probes == 2 ? "editor" : nil
            })
        XCTAssertEqual(window, "editor")
        XCTAssertEqual(probes, 2)
    }

    @MainActor
    func testSwitchingAppsStopsCaptureBeforeAnotherProbe() async {
        var activeChecks = 0
        var probes = 0
        do {
            let _: String? = try await WindowResolutionRetry.resolve(attempts: 3, interval: .zero,
                isActive: {
                    activeChecks += 1
                    return activeChecks == 1
                }, probe: {
                    probes += 1
                    return nil
                })
            XCTFail("Expected capture to stop")
        } catch KeyboardFieldError.notFrontmost {
            XCTAssertEqual(probes, 1)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}
