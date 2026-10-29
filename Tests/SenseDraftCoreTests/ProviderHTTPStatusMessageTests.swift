import XCTest
@testable import SenseDraftCore

final class ProviderHTTPStatusMessageTests: XCTestCase {
    func testRateLimitDoesNotBlameCredentials() {
        XCTAssertEqual(ProviderHTTPStatusMessage.forConnectionCheck(429),
                       "HTTP 429. Rate limit or quota reached; check usage or try again later.")
    }

    func testAuthenticationAndModelErrorsHaveDifferentGuidance() {
        XCTAssertEqual(ProviderHTTPStatusMessage.forConnectionCheck(401),
                       "HTTP 401. Check the API key and region.")
        XCTAssertEqual(ProviderHTTPStatusMessage.forConnectionCheck(404),
                       "HTTP 404. Check the model and API region.")
    }

    func testKimiRateLimitTypesExplainNextStep() {
        XCTAssertEqual(ProviderHTTPStatusMessage.forConnectionCheck(429, kimiErrorType: "exceeded_current_quota_error"),
                       "HTTP 429. Kimi API balance or quota exhausted; check platform billing and usage.")
        XCTAssertEqual(ProviderHTTPStatusMessage.forConnectionCheck(429, kimiErrorType: "rate_limit_reached_error"),
                       "HTTP 429. Kimi rate limit reached; wait and check your account limits.")
        XCTAssertEqual(ProviderHTTPStatusMessage.forConnectionCheck(429, kimiErrorType: "engine_overloaded_error"),
                       "HTTP 429. Kimi service is overloaded; try again later.")
    }
}
