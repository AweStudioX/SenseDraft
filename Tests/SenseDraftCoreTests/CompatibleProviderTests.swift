import Foundation
import XCTest
@testable import SenseDraftCore

final class CompatibleProviderTests: XCTestCase {
    private let response = #"{"choices":[{"finish_reason":"stop","message":{"content":"{\"english\":\"Hello.\",\"chineseMeaning\":\"你好。\",\"ambiguity\":null,\"worthChanging\":false,\"reason\":null}"}}]}"#

    func testPresetsUseTheirOwnEndpointsAndStructuredFormats() async throws {
        let cases: [(CompatibleService, String, String)] = [
            (.gemini, "https://generativelanguage.googleapis.com/v1beta/openai/chat/completions", "json_schema"),
            (.openRouter, "https://openrouter.ai/api/v1/chat/completions", "json_schema"),
            (.qwen(.china), "https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions", "json_schema"),
            (.qwen(.singapore), "https://dashscope-intl.aliyuncs.com/compatible-mode/v1/chat/completions", "json_schema"),
            (.ollama, "http://localhost:11434/v1/chat/completions", "json_schema")
        ]
        let input = try AnalysisInput(source: "Hello.", locale: "en-US", chineseIntent: nil)
        for (service, endpoint, format) in cases {
            let transport = RecordingTransport(body: response)
            let provider = CompatibleProvider(service: service, key: "key", model: "text-model", transport: transport)
            let result = try await provider.analyze(input)
            XCTAssertEqual(result.english, "Hello.")
            let requests = await transport.requests
            let request = try XCTUnwrap(requests.first)
            XCTAssertEqual(request.url?.absoluteString, endpoint)
            let body = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Any])
            XCTAssertEqual((body["response_format"] as? [String: Any])?["type"] as? String, format)
        }
    }

    func testCustomEndpointUsesValidatedURLAndKey() async throws {
        let transport = RecordingTransport(body: response)
        let provider = CompatibleProvider(service: .custom("https://example.com/v1"), key: "private-key",
                                          model: "model-a", transport: transport)
        let input = try AnalysisInput(source: "Hello.", locale: "en-US", chineseIntent: nil)
        _ = try await provider.analyze(input)
        let requests = await transport.requests
        let request = try XCTUnwrap(requests.first)
        XCTAssertEqual(request.url?.absoluteString, "https://example.com/v1/chat/completions")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer private-key")
    }

    func testCustomEndpointRejectsRemoteHTTPBeforeSendingKey() async throws {
        let transport = RecordingTransport(body: response)
        let provider = CompatibleProvider(service: .custom("http://example.com/v1"), key: "private-key",
                                          model: "model-a", transport: transport)
        let input = try AnalysisInput(source: "Hello.", locale: "en-US", chineseIntent: nil)
        do {
            _ = try await provider.analyze(input)
            XCTFail("Expected invalid endpoint")
        } catch let error as CompatibleProviderError {
            XCTAssertEqual(error, .invalidEndpoint)
        }
        let requests = await transport.requests
        XCTAssertEqual(requests.count, 0)
    }

    func testOllamaDoesNotRequireOrSendAPIKey() async throws {
        let transport = RecordingTransport(body: response)
        let provider = CompatibleProvider(service: .ollama, key: "", model: "qwen3", transport: transport)
        let input = try AnalysisInput(source: "Hello.", locale: "en-US", chineseIntent: nil)
        _ = try await provider.analyze(input)
        let requests = await transport.requests
        let request = try XCTUnwrap(requests.first)
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
    }

    func testCustomLocalEndpointCanRunWithoutAPIKey() async throws {
        let transport = RecordingTransport(body: response)
        let provider = CompatibleProvider(service: .custom("http://127.0.0.1:1234/v1"), key: "",
                                          model: "local-model", transport: transport)
        let input = try AnalysisInput(source: "Hello.", locale: "en-US", chineseIntent: nil)
        _ = try await provider.analyze(input)
        let requests = await transport.requests
        let request = try XCTUnwrap(requests.first)
        XCTAssertEqual(request.url?.absoluteString, "http://127.0.0.1:1234/v1/chat/completions")
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
    }

    func testOpenRouterRequiresStructuredOutputCapableRoute() async throws {
        let transport = RecordingTransport(body: response)
        let provider = CompatibleProvider(service: .openRouter, key: "key", model: "anthropic/claude-haiku-5.5",
                                          transport: transport)
        let input = try AnalysisInput(source: "Hello.", locale: "en-US", chineseIntent: nil)
        _ = try await provider.analyze(input)
        let requests = await transport.requests
        let request = try XCTUnwrap(requests.first)
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Any])
        let routing = try XCTUnwrap(body["provider"] as? [String: Any])
        XCTAssertEqual(routing["require_parameters"] as? Bool, true)
    }
}
