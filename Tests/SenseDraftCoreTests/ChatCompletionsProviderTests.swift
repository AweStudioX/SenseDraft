import Foundation
import XCTest
@testable import SenseDraftCore

final class ChatCompletionsProviderTests: XCTestCase {
    private let response = #"{"choices":[{"finish_reason":"stop","message":{"content":"{\"english\":\"I can send it tomorrow.\",\"chineseMeaning\":\"我明天可以发给你。\",\"ambiguity\":null,\"worthChanging\":true,\"reason\":\"Clearer wording\"}"}}]}"#

    func testDeepSeekUsesItsEndpointAndParsesResult() async throws {
        let transport = RecordingTransport(body: response)
        let provider = ChatCompletionsProvider(service: .deepSeek, key: "deep-key", model: "deepseek-flash", transport: transport)
        let input = try AnalysisInput(source: "I send it tomorrow.", locale: "en-US", chineseIntent: nil)
        let result = try await provider.analyze(input)
        XCTAssertEqual(result.english, "I can send it tomorrow.")
        let requests = await transport.requests
        let request = try XCTUnwrap(requests.first)
        XCTAssertEqual(request.url?.absoluteString, "https://api.deepseek.com/chat/completions")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer deep-key")
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Any])
        XCTAssertEqual(body["model"] as? String, "deepseek-flash")
        XCTAssertEqual((body["response_format"] as? [String: String])?["type"], "json_object")
    }

    func testKimiUsesItsEndpointAndParsesResult() async throws {
        let transport = RecordingTransport(body: response)
        let provider = ChatCompletionsProvider(service: .kimi(.china), key: "kimi-key", model: "kimi-k2.6", transport: transport)
        let input = try AnalysisInput(source: "I send it tomorrow.", locale: "en-US", chineseIntent: nil)
        let result = try await provider.analyze(input)
        XCTAssertEqual(result.chineseMeaning, "我明天可以发给你。")
        let requests = await transport.requests
        let request = try XCTUnwrap(requests.first)
        XCTAssertEqual(request.url?.absoluteString, "https://api.moonshot.cn/v1/chat/completions")
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Any])
        XCTAssertEqual((body["thinking"] as? [String: String])?["type"], "disabled")
    }

    func testKimiK3DoesNotDisableThinking() async throws {
        let transport = RecordingTransport(body: response)
        let provider = ChatCompletionsProvider(service: .kimi(.china), key: "kimi-key", model: "kimi-k3",
                                               transport: transport)
        let input = try AnalysisInput(source: "I send it tomorrow.", locale: "en-US", chineseIntent: nil)
        _ = try await provider.analyze(input)
        let requests = await transport.requests
        let request = try XCTUnwrap(requests.first)
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Any])
        XCTAssertNil(body["thinking"])
    }

    func testKimiGlobalUsesInternationalEndpoint() async throws {
        let transport = RecordingTransport(body: response)
        let provider = ChatCompletionsProvider(service: .kimi(.global), key: "kimi-key", transport: transport)
        let input = try AnalysisInput(source: "I send it tomorrow.", locale: "en-US", chineseIntent: nil)
        _ = try await provider.analyze(input)
        let requests = await transport.requests
        let request = try XCTUnwrap(requests.first)
        XCTAssertEqual(request.url?.absoluteString, "https://api.moonshot.ai/v1/chat/completions")
    }

    func testKimiParsesJSONCodeFenceFromLiveResponseShape() async throws {
        let content = """
        ```json
        {
          "english": "That'll be fine.",
          "chineseMeaning": "那样就可以了",
          "ambiguity": null,
          "worthChanging": true,
          "reason": "Fixes a typo."
        }
        ```
        """
        let encodedContent = try XCTUnwrap(String(data: JSONEncoder().encode(content), encoding: .utf8))
        let response = #"{"choices":[{"finish_reason":"stop","message":{"content":\#(encodedContent),"reasoning_content":"hidden reasoning"}}]}"#
        let provider = ChatCompletionsProvider(service: .kimi(.china), key: "kimi-key",
                                               transport: RecordingTransport(body: response))
        let input = try AnalysisInput(source: "thatll be fine", locale: "en-US", chineseIntent: nil)
        let result = try await provider.analyze(input)
        XCTAssertEqual(result.english, "That'll be fine.")
    }

    func testKimiRejectsProseAroundJSONCodeFence() async throws {
        let content = "Here is the result:\n```json\n{\"english\":\"Hello.\",\"chineseMeaning\":\"你好。\",\"ambiguity\":null,\"worthChanging\":false,\"reason\":null}\n```"
        let encodedContent = try XCTUnwrap(String(data: JSONEncoder().encode(content), encoding: .utf8))
        let response = #"{"choices":[{"finish_reason":"stop","message":{"content":\#(encodedContent)}}]}"#
        let provider = ChatCompletionsProvider(service: .kimi(.china), key: "kimi-key",
                                               transport: RecordingTransport(body: response))
        let input = try AnalysisInput(source: "Hello", locale: "en-US", chineseIntent: nil)
        do {
            _ = try await provider.analyze(input)
            XCTFail("Expected invalid response")
        } catch let error as ChatCompletionsProviderError {
            XCTAssertEqual(error, .invalidResponse)
        }
    }

    func testMissingKeyAndIncompleteResponseAreRejected() async throws {
        let input = try AnalysisInput(source: "Hello", locale: "en-US", chineseIntent: nil)
        do {
            _ = try await ChatCompletionsProvider(service: .kimi(.china), key: " ", transport: RecordingTransport(body: response)).analyze(input)
            XCTFail("Expected missing key")
        } catch let error as ChatCompletionsProviderError {
            XCTAssertEqual(error, .missingKey)
        }
        do {
            _ = try await ChatCompletionsProvider(service: .deepSeek, key: "key", transport: RecordingTransport(body: #"{"choices":[{"finish_reason":"length","message":{"content":"{}"}}]}"#)).analyze(input)
            XCTFail("Expected incomplete response")
        } catch let error as ChatCompletionsProviderError {
            XCTAssertEqual(error, .incomplete)
        }
    }

    func testKimiHTTPErrorKeepsSafeDiagnosticFields() async throws {
        let body = #"{"error":{"type":"exceeded_current_quota_error","message":"Account balance exhausted"}}"#
        let transport = RecordingTransport(status: 429, body: body,
                                           headers: ["Msh-Request-Id": "abc123-456"])
        let provider = ChatCompletionsProvider(service: .kimi(.china), key: "secret", transport: transport)
        let input = try AnalysisInput(source: "Hello", locale: "en-US", chineseIntent: nil)
        do {
            _ = try await provider.analyze(input)
            XCTFail("Expected HTTP error")
        } catch let error as ChatCompletionsProviderError {
            XCTAssertEqual(error, .httpStatus(429, type: "exceeded_current_quota_error", requestID: "abc123-456"))
            XCTAssertFalse(String(describing: error).contains("Account balance exhausted"))
        }
    }

    func testKimiHTTPErrorIgnoresUnexpectedDiagnosticValues() async throws {
        let body = #"{"error":{"type":"secret\nvalue"}}"#
        let transport = RecordingTransport(status: 429, body: body,
                                           headers: ["Msh-Request-Id": "not a safe id"])
        let provider = ChatCompletionsProvider(service: .kimi(.china), key: "secret", transport: transport)
        let input = try AnalysisInput(source: "Hello", locale: "en-US", chineseIntent: nil)
        do {
            _ = try await provider.analyze(input)
            XCTFail("Expected HTTP error")
        } catch let error as ChatCompletionsProviderError {
            XCTAssertEqual(error, .httpStatus(429, type: nil, requestID: nil))
        }
    }
}
