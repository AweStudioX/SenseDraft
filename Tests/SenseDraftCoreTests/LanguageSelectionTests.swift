import XCTest
@testable import SenseDraftCore

final class LanguageSelectionTests: XCTestCase {
    func testSupportedLanguagesIncludeIndependentTargetAndReferenceChoices() {
        XCTAssertEqual(LanguageChoice.defaultTarget.rawValue, "en-US")
        XCTAssertEqual(LanguageChoice.defaultReference.rawValue, "zh-Hans")
        XCTAssertNotNil(LanguageChoice(rawValue: "fr-FR"))
        XCTAssertNotNil(LanguageChoice(rawValue: "ja-JP"))
        XCTAssertNotNil(LanguageChoice(rawValue: "zh-Hant"))
    }

    func testPrimaryLanguageMenusKeepDefaultsFirstAndLeaveAllOthersAvailable() {
        XCTAssertEqual(LanguageChoice.primaryTargets.first, .defaultTarget)
        XCTAssertEqual(LanguageChoice.primaryReferences.first, .defaultReference)
        XCTAssertEqual(Set(LanguageChoice.primaryTargets).count, LanguageChoice.primaryTargets.count)
        XCTAssertEqual(Set(LanguageChoice.primaryReferences).count, LanguageChoice.primaryReferences.count)
        XCTAssertEqual(Set(LanguageChoice.primaryTargets + LanguageChoice.moreTargets),
                       Set(LanguageChoice.allCases))
        XCTAssertEqual(Set(LanguageChoice.primaryReferences + LanguageChoice.moreReferences),
                       Set(LanguageChoice.allCases))
    }

    func testPromptUsesBothSelectedLanguages() throws {
        let input = try AnalysisInput(source: "Bonjour, je suis disponible demain.",
                                      locale: "ja-JP", referenceLocale: "de-DE", chineseIntent: nil)
        let instructions = AnalysisPrompt.instructions(for: input)
        XCTAssertTrue(instructions.contains("Japanese"))
        XCTAssertTrue(instructions.contains("German"))
        XCTAssertTrue(instructions.contains("worthChanging to false"))
        XCTAssertFalse(instructions.contains("Chinese interpretation"))
    }

    func testRevisedReferenceMeaningFollowsSelectedLanguage() throws {
        let input = try AnalysisInput(source: "See you soon.", locale: "fr-FR",
                                      referenceLocale: "ja-JP", chineseIntent: "来週会いましょう")
        XCTAssertTrue(AnalysisPrompt.instructions(for: input).contains("Japanese intention"))
        XCTAssertTrue(AnalysisPrompt.userMessage(for: input).contains("revised meaning in Japanese"))
        XCTAssertTrue(AnalysisPrompt.userMessage(for: input).contains("French"))
    }
}
