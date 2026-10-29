import SenseDraftCore
@testable import SenseDraftMac
import XCTest

final class ProviderResultErrorMessageTests: XCTestCase {
    func testKimiQuotaErrorShowsActionableMessage() {
        let error = ChatCompletionsProviderError.httpStatus(429,
            type: "exceeded_current_quota_error", requestID: "abc123")
        XCTAssertEqual(ProviderResultErrorMessage.describe(error, provider: "Kimi"),
                       "HTTP 429. Kimi API balance or quota exhausted; check platform billing and usage.")
    }
}
