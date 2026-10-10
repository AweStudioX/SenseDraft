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

    func testCompletedEventCanProvideFinalText() throws {
        let stream = #"data: {"type":"response.completed","response":{"output":[{"type":"message","content":[{"type":"output_text","text":"final"}]}]}}"# + "\n\n"
        XCTAssertEqual(try StreamDecoder.consume(stream), "final")
    }

    func testUnrelatedEventWithDifferentResponseShapeDoesNotInvalidateStream() throws {
        let stream = """
        event: response.created
        data: {"type":"response.created","response":{"output":{"pending":true}}}

        event: response.output_text.delta
        data: {"type":"response.output_text.delta","delta":"hello"}

        event: response.completed
        data: {"type":"response.completed","response":{"output":{"pending":false}}}

        """
        XCTAssertEqual(try StreamDecoder.consume(stream), "hello")
    }

    func testFinalizedTextIsUsedWhenDeltasAreMissing() throws {
        let stream = """
        data: {"type":"response.output_text.done","text":"final"}

        data: {"type":"response.completed"}

        """
        XCTAssertEqual(try StreamDecoder.consume(stream), "final")
    }

    func testUntypedErrorFramePreservesCode() {
        let stream = "data: {\"error\":{\"code\":\"subscription_sharing_usage_unavailable\"}}\n\n"
        XCTAssertThrowsError(try StreamDecoder.consume(stream)) { error in
            XCTAssertEqual(error as? StreamDecoderError, .failed("subscription_sharing_usage_unavailable"))
        }
    }
}
