import Foundation
import XCTest
@testable import SenseDraftCore

actor RecordingTransport: HTTPTransport {
    let response: (Data, HTTPURLResponse)
    private(set) var requests: [URLRequest] = []

    init(status: Int = 200, body: String) {
        self.response = (
            Data(body.utf8),
            HTTPURLResponse(url: URL(string: "https://api.openai.com/v1/responses")!, statusCode: status, httpVersion: nil, headerFields: nil)!
        )
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        return response
    }
}

final class OpenAIProviderTests: XCTestCase {
    private let completed = #"{"status":"completed","output":[{"type":"message","content":[{"type":"output_text","text":"{\"english\":\"I can send it tomorrow.\",\"chineseMeaning\":\"我明天可以发给你。\",\"ambiguity\":null}"}]}]}"#

    func testInitialPromptPreservesMeaning() throws {
        let input = try AnalysisInput(source: "I might send 2 files to Sam.", locale: "en-US", chineseIntent: nil)
        let instructions = AnalysisPrompt.instructions(for: input)
        XCTAssertTrue(instructions.contains("names"))
        XCTAssertTrue(instructions.contains("numbers"))
        XCTAssertTrue(instructions.contains("uncertainty"))
        XCTAssertFalse(instructions.contains("authoritative Chinese"))
    }

    func testEditedChineseIsAuthoritative() throws {
        let input = try AnalysisInput(source: "I will send it.", locale: "en-US", chineseIntent: "我可能会发给他")
        let instructions = AnalysisPrompt.instructions(for: input)
        XCTAssertTrue(instructions.contains("authoritative Chinese"))
        XCTAssertTrue(instructions.contains("我可能会发给他"))
    }

    func testCompletedResponseIsParsedAndRequestUsesAPIKey() async throws {
        let transport = RecordingTransport(body: completed)
        let provider = OpenAIProvider(key: "secret-test-key", transport: transport)
        let input = try AnalysisInput(source: "I send it tomorrow.", locale: "en-US", chineseIntent: nil)
        let result = try await provider.analyze(input)
        XCTAssertEqual(result.english, "I can send it tomorrow.")
        XCTAssertEqual(result.chineseMeaning, "我明天可以发给你。")
        let requests = await transport.requests
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(requests[0].value(forHTTPHeaderField: "Authorization"), "Bearer secret-test-key")
        let payload = try XCTUnwrap(requests[0].httpBody)
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: payload) as? [String: Any])
        XCTAssertEqual(body["model"] as? String, "gpt-6.1-sol")
        XCTAssertEqual(body["store"] as? Bool, false)
        XCTAssertNotNil(body["text"])
    }

    func testIncompleteAndHTTPFailureDoNotProduceResult() async throws {
        let input = try AnalysisInput(source: "Hello", locale: "en-US", chineseIntent: nil)
        let incomplete = OpenAIProvider(key: "key", transport: RecordingTransport(body: #"{"status":"incomplete","output":[]}"#))
        do {
            _ = try await incomplete.analyze(input)
            XCTFail("Expected incomplete response")
        } catch let error as OpenAIProviderError {
            XCTAssertEqual(error, .incomplete)
        }

        let unauthorized = OpenAIProvider(key: "key", transport: RecordingTransport(status: 401, body: #"{"error":{"message":"bad key"}}"#))
        do {
            _ = try await unauthorized.analyze(input)
            XCTFail("Expected HTTP error")
        } catch let error as OpenAIProviderError {
            XCTAssertEqual(error, .httpStatus(401))
        }
    }
}
