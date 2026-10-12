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
        XCTAssertEqual(body["stream"] as? Bool, false)
        XCTAssertNotNil(body["input"] as? [[String: Any]])
        XCTAssertNil(body["previous_response_id"])
    }

    func testCompletedJSONResultAfterReasoningItem() throws {
        let payload = #"{"english":"Hello there.","chineseMeaning":"你好。","ambiguity":null,"worthChanging":false,"reason":"Already natural"}"#
        let body = try JSONSerialization.data(withJSONObject: [
            "status": "completed",
            "output": [
                ["type": "reasoning", "summary": []],
                ["type": "message", "content": [["type": "output_text", "text": payload]]]
            ]
        ])
        let result = try ChatGPTPlanProvider.parse(body)
        XCTAssertEqual(result.english, "Hello there.")
        XCTAssertEqual(result.chineseMeaning, "你好。")
        XCTAssertFalse(result.worthChanging)
    }

    func testIncompleteResponseIsRejected() throws {
        let body = Data(#"{"status":"incomplete","output":[]}"#.utf8)
        XCTAssertThrowsError(try ChatGPTPlanProvider.parse(body)) { error in
            XCTAssertEqual(error as? ChatGPTPlanError, .incomplete)
        }
    }

    func testAnalyzeUsesNonStreamingResponse() async throws {
        let body = #"{"status":"completed","output":[{"type":"message","content":[{"type":"output_text","text":"{\"english\":\"That would be great.\",\"chineseMeaning\":\"那太好了。\",\"ambiguity\":null,\"worthChanging\":true,\"reason\":null}"}]}]}"#
        let transport = RecordingTransport(body: body)
        let provider = ChatGPTPlanProvider(token: "plan-token", model: "account-model", transport: transport)
        let input = try AnalysisInput(source: "that will been great", locale: "en-US", chineseIntent: nil)
        let result = try await provider.analyze(input)
        XCTAssertEqual(result.english, "That would be great.")
        let requests = await transport.requests
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(requests[0].value(forHTTPHeaderField: "Authorization"), "Bearer plan-token")
        let requestBody = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(requests[0].httpBody)) as? [String: Any])
        XCTAssertEqual(requestBody["stream"] as? Bool, false)
        XCTAssertEqual(requestBody["store"] as? Bool, false)
    }
}
