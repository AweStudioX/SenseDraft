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

    func testInconsistentNoChangeUsesPlainLanguageInsteadOfErrorCase() {
        XCTAssertEqual(ProviderResultErrorMessage.describe(AnalysisError.inconsistentNoChange, provider: "Kimi"),
                       "The service marked this as unchanged but returned different English. Try Regenerate.")
    }

    func testUnreadableCompletionDoesNotShowInternalErrorCase() {
        XCTAssertEqual(ProviderResultErrorMessage.describe(ChatCompletionsProviderError.invalidResponse,
                                                           provider: "Kimi"),
                       "Kimi returned an unreadable result. Try Regenerate.")
    }

    func testUnknownErrorDoesNotExposeInternalDescription() {
        let error = NSError(domain: "private.network.detail", code: 42)
        XCTAssertEqual(ProviderResultErrorMessage.describe(error, provider: "Kimi"),
                       "Kimi analysis failed. Try Regenerate.")
    }
}
