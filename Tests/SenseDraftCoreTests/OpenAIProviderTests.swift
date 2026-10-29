import Foundation
import XCTest
@testable import SenseDraftCore

actor RecordingTransport: HTTPTransport {
    let response: (Data, HTTPURLResponse)
    private(set) var requests: [URLRequest] = []

    init(status: Int = 200, body: String, headers: [String: String]? = nil) {
        self.response = (
            Data(body.utf8),
            HTTPURLResponse(url: URL(string: "https://api.openai.com/v1/responses")!, statusCode: status, httpVersion: nil, headerFields: headers)!
        )
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        return response
    }
}

final class OpenAIProviderTests: XCTestCase {
    private let completed = #"{"status":"completed","output":[{"type":"message","content":[{"type":"output_text","text":"{\"english\":\"I can send it tomorrow.\",\"chineseMeaning\":\"我明天可以发给你。\",\"ambiguity\":null,\"worthChanging\":true,\"reason\":\"Clearer commitment\"}"}]}]}"#

    func testInitialPromptPreservesMeaning() throws {
        let input = try AnalysisInput(source: "I might send 2 files to Sam.", locale: "en-US", chineseIntent: nil)
        let instructions = AnalysisPrompt.instructions(for: input)
        XCTAssertTrue(instructions.contains("names"))
        XCTAssertTrue(instructions.contains("numbers"))
        XCTAssertTrue(instructions.contains("uncertainty"))
        XCTAssertTrue(instructions.contains("already natural"))
        XCTAssertFalse(instructions.contains("authoritative Chinese"))
        XCTAssertTrue(instructions.contains("Preserve intentional abbreviations"))
        XCTAssertTrue(instructions.contains("Do not add emphasis or details"))
    }

    func testNaturalAbbreviationsAreOptional() throws {
        let preferences = WritingPreferences(useNaturalAbbreviations: true)
        let input = try AnalysisInput(source: "Please check it when you can", locale: "en-US",
                                      chineseIntent: nil, preferences: preferences)
        let instructions = AnalysisPrompt.instructions(for: input)
        XCTAssertTrue(instructions.contains("common, unambiguous English contractions and chat abbreviations"))
        XCTAssertTrue(instructions.contains("only when they fit the source's tone"))

        let defaultInput = try AnalysisInput(source: "Please check it when you can", locale: "en-US", chineseIntent: nil)
        XCTAssertFalse(AnalysisPrompt.instructions(for: defaultInput).contains("common, unambiguous English contractions and chat abbreviations"))
    }

    func testOlderWritingPreferencesDecodeWithAbbreviationsOff() throws {
        let old = #"{"style":"casual","openingCase":"matchInput","customInstruction":"keep it short"}"#.data(using: .utf8)!
        let preferences = try JSONDecoder().decode(WritingPreferences.self, from: old)
        XCTAssertFalse(preferences.useNaturalAbbreviations)
        XCTAssertEqual(preferences.style, .casual)
        XCTAssertEqual(preferences.customInstruction, "keep it short")
    }

    func testChineseInputUsesTranslationPromptAndDefaultCapitalization() throws {
        let input = try AnalysisInput(source: "这个方案明天可以发给 Sam", locale: "en-US", chineseIntent: nil)
        let instructions = AnalysisPrompt.instructions(for: input)
        XCTAssertTrue(instructions.contains("Translate the Chinese source"))
        XCTAssertTrue(instructions.contains("natural, idiomatic en-US English"))
        XCTAssertTrue(instructions.contains("worthChanging to true"))
        XCTAssertTrue(instructions.contains("standard capitalization"))
        XCTAssertFalse(instructions.contains("Match the source's opening capitalization"))
    }

    func testEditedChineseIsAuthoritative() throws {
        let input = try AnalysisInput(source: "I will send it.", locale: "en-US", chineseIntent: "我可能会发给他")
        let instructions = AnalysisPrompt.instructions(for: input)
        XCTAssertTrue(instructions.contains("authoritative Chinese"))
        XCTAssertTrue(instructions.contains("我可能会发给他"))
    }

    func testCasualPreferencesKeepLowercaseOpeningAndMeaning() throws {
        let preferences = WritingPreferences(style: .casual, openingCase: .matchInput,
                                             customInstruction: "keep it short for chat")
        let input = try AnalysisInput(source: "that will be great", locale: "en-US",
                                      chineseIntent: nil, preferences: preferences)
        let instructions = AnalysisPrompt.instructions(for: input)
        XCTAssertTrue(instructions.contains("conversational"))
        XCTAssertTrue(instructions.contains("lowercase"))
        XCTAssertTrue(instructions.contains("keep it short for chat"))
        XCTAssertTrue(instructions.contains("Preserve intended meaning"))
        XCTAssertTrue(instructions.contains("proper names"))
    }

    func testStandardCapitalizationAndProfessionalStyle() throws {
        let preferences = WritingPreferences(style: .professional, openingCase: .standard,
                                             customInstruction: "")
        let input = try AnalysisInput(source: "hello there", locale: "en-GB",
                                      chineseIntent: nil, preferences: preferences)
        let instructions = AnalysisPrompt.instructions(for: input)
        XCTAssertTrue(instructions.contains("workplace"))
        XCTAssertTrue(instructions.contains("standard capitalization"))
        XCTAssertFalse(instructions.contains("User writing preference"))
    }

    func testExplicitLowercaseOpening() throws {
        let preferences = WritingPreferences(openingCase: .lowercase)
        let input = try AnalysisInput(source: "That will be great", locale: "en-US",
                                      chineseIntent: nil, preferences: preferences)
        let instructions = AnalysisPrompt.instructions(for: input)
        XCTAssertTrue(instructions.contains("even if the source starts uppercase"))
        XCTAssertTrue(instructions.contains("proper names"))
    }

    func testCompletedResponseIsParsedAndRequestUsesAPIKey() async throws {
        let transport = RecordingTransport(body: completed)
        let provider = OpenAIProvider(key: "secret-test-key", transport: transport)
        let input = try AnalysisInput(source: "I send it tomorrow.", locale: "en-US", chineseIntent: nil)
        let result = try await provider.analyze(input)
        XCTAssertEqual(result.english, "I can send it tomorrow.")
        XCTAssertEqual(result.chineseMeaning, "我明天可以发给你。")
        XCTAssertTrue(result.worthChanging)
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
