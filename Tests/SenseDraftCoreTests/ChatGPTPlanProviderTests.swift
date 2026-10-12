import XCTest
@testable import SenseDraftCore

final class ChatGPTPlanProviderTests: XCTestCase {
    func testAdmissionErrorCodeIsPreserved() {
        let body = Data(#"{"error":{"code":"subscription_sharing_user_not_eligible"}}"#.utf8)
        XCTAssertEqual(ChatGPTPlanProvider.errorCode(from: body), "subscription_sharing_user_not_eligible")
    }
    func testRequestUsesPlanContract() throws {
        let provider = ChatGPTPlanProvider(token: "mock-token", model: "account-visible-model")
        let request = try provider.makeRequest(AnalysisInput(source: "hi there", locale: "en-US", chineseIntent: nil))
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Any])
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer mock-token")
        XCTAssertEqual(body["model"] as? String, "account-visible-model")
        XCTAssertEqual(body["store"] as? Bool, false)
        XCTAssertEqual(body["stream"] as? Bool, true)
        XCTAssertNotNil(body["input"] as? [[String: Any]])
        XCTAssertNil(body["previous_response_id"])
    }

    func testCompletedStreamResultAfterReasoningEvent() throws {
        let payload = #"{"english":"Hello there.","chineseMeaning":"你好。","ambiguity":null,"worthChanging":false,"reason":"Already natural"}"#
        let delta = try JSONSerialization.data(withJSONObject: ["type": "response.output_text.delta", "delta": payload])
        let stream = "event: response.created\ndata: {\"type\":\"response.created\",\"response\":{\"output\":[]}}\n\n"
            + "event: response.output_item.done\ndata: {\"type\":\"response.output_item.done\",\"item\":{\"type\":\"reasoning\"}}\n\n"
            + "event: response.output_text.delta\ndata: \(String(decoding: delta, as: UTF8.self))\n\n"
            + "event: response.completed\ndata: {\"type\":\"response.completed\"}\n\n"
        let result = try ChatGPTPlanProvider.parse(Data(stream.utf8))
        XCTAssertEqual(result.english, "Hello there.")
        XCTAssertEqual(result.chineseMeaning, "你好。")
        XCTAssertFalse(result.worthChanging)
    }

    func testIncompleteResponseIsRejected() throws {
        let body = Data("data: {\"type\":\"response.incomplete\"}\n\n".utf8)
        XCTAssertThrowsError(try ChatGPTPlanProvider.parse(body)) { error in
            XCTAssertEqual(error as? StreamDecoderError, .incomplete)
        }
    }

    func testAnalyzeUsesCompleteSSEFrames() async throws {
        let payload = #"{"english":"That would be great.","chineseMeaning":"那太好了。","ambiguity":null,"worthChanging":true,"reason":null}"#
        let delta = try JSONSerialization.data(withJSONObject: ["type": "response.output_text.delta", "delta": payload])
        let body = "data: \(String(decoding: delta, as: UTF8.self))\n\ndata: {\"type\":\"response.completed\"}\n\n"
        let transport = RecordingTransport(body: body)
        let provider = ChatGPTPlanProvider(token: "plan-token", model: "account-model", transport: transport)
        let input = try AnalysisInput(source: "that will been great", locale: "en-US", chineseIntent: nil)
        let result = try await provider.analyze(input)
        XCTAssertEqual(result.english, "That would be great.")
        let requests = await transport.requests
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(requests[0].value(forHTTPHeaderField: "Authorization"), "Bearer plan-token")
        let requestBody = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(requests[0].httpBody)) as? [String: Any])
        XCTAssertEqual(requestBody["stream"] as? Bool, true)
        XCTAssertEqual(requestBody["store"] as? Bool, false)
    }
}
