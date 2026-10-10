import XCTest
@testable import SenseDraftCore

final class StreamDecoderTests: XCTestCase {
    func testRequiresCompletedEvent() throws {
        let stream = """
        data: {"type":"response.output_text.delta","delta":"hello"}

        data: {"type":"response.completed"}

        """
        XCTAssertEqual(try StreamDecoder.consume(stream), "hello")
        XCTAssertThrowsError(try StreamDecoder.consume("data: {\"type\":\"response.output_text.delta\",\"delta\":\"hello\"}\n\n"))
    }

    func testFailurePreservesCode() {
        let stream = "data: {\"type\":\"response.failed\",\"response\":{\"error\":{\"code\":\"subscription_sharing_usage_limit_exceeded\"}}}\n\n"
        XCTAssertThrowsError(try StreamDecoder.consume(stream)) { error in
            XCTAssertEqual(error as? StreamDecoderError, .failed("subscription_sharing_usage_limit_exceeded"))
        }
    }
}
