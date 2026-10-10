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

    func testCompletedJSONResult() throws {
        let payload = #"{"english":"Hello there.","chineseMeaning":"你好。","ambiguity":null,"worthChanging":false,"reason":"Already natural"}"#
        let event = try JSONSerialization.data(withJSONObject: ["type": "response.output_text.delta", "delta": payload])
        let stream = "data: \(String(decoding: event, as: UTF8.self))\n\ndata: {\"type\":\"response.completed\"}\n\n"
        let result = try ChatGPTPlanProvider.parse(stream)
        XCTAssertEqual(result.english, "Hello there.")
        XCTAssertEqual(result.chineseMeaning, "你好。")
        XCTAssertFalse(result.worthChanging)
    }
}
