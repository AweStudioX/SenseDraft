import Foundation
import XCTest
@testable import SenseDraftCore

final class ClaudeProviderTests: XCTestCase {
    func testClaudeUsesMessagesAPIAndParsesStructuredResult() async throws {
        let response = #"{"stop_reason":"end_turn","content":[{"type":"text","text":"{\"english\":\"Hello.\",\"chineseMeaning\":\"你好。\",\"ambiguity\":null,\"worthChanging\":false,\"reason\":null}"}]}"#
        let transport = RecordingTransport(body: response)
        let provider = ClaudeProvider(key: "claude-key", model: "claude-sonnet-5-5", transport: transport)
        let input = try AnalysisInput(source: "Hello.", locale: "en-US", chineseIntent: nil)
        let result = try await provider.analyze(input)
        XCTAssertEqual(result.chineseMeaning, "你好。")
        let requests = await transport.requests
        let request = try XCTUnwrap(requests.first)
        XCTAssertEqual(request.url?.absoluteString, "https://api.anthropic.com/v1/messages")
        XCTAssertEqual(request.value(forHTTPHeaderField: "x-api-key"), "claude-key")
        XCTAssertNotNil(request.value(forHTTPHeaderField: "anthropic-version"))
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Any])
        XCTAssertEqual(body["model"] as? String, "claude-sonnet-5-5")
        let outputConfig = try XCTUnwrap(body["output_config"] as? [String: Any])
        let format = try XCTUnwrap(outputConfig["format"] as? [String: Any])
        XCTAssertEqual(format["type"] as? String, "json_schema")
    }

    func testClaudeRejectsTruncatedResponse() async throws {
        let response = #"{"stop_reason":"max_tokens","content":[{"type":"text","text":"{}"}]}"#
        let provider = ClaudeProvider(key: "key", model: "claude-sonnet-5-5",
                                      transport: RecordingTransport(body: response))
        let input = try AnalysisInput(source: "Hello.", locale: "en-US", chineseIntent: nil)
        do {
            _ = try await provider.analyze(input)
            XCTFail("Expected incomplete response")
        } catch let error as ClaudeProviderError {
            XCTAssertEqual(error, .incomplete)
        }
    }
}
