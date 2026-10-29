import SenseDraftCore
@testable import SenseDraftMac
import XCTest

final class ReviewModelTests: XCTestCase {
    private let preferenceKey = "preferredReviewProvider"
    private var previousPreference: String?

    override func setUp() {
        super.setUp()
        previousPreference = UserDefaults.standard.string(forKey: preferenceKey)
        UserDefaults.standard.removeObject(forKey: preferenceKey)
    }

    override func tearDown() {
        if let previousPreference {
            UserDefaults.standard.set(previousPreference, forKey: preferenceKey)
        } else {
            UserDefaults.standard.removeObject(forKey: preferenceKey)
        }
        super.tearDown()
    }

    @MainActor
    func testEarlierResultAppearsWhileAnotherProviderIsPending() throws {
        let model = ReviewModel()
        model.beginResults(providers: ["ChatGPT plan", "DeepSeek"])
        model.receive(try candidate("DeepSeek", english: "Second"))

        XCTAssertEqual(model.providerNames, ["ChatGPT plan", "DeepSeek"])
        XCTAssertEqual(model.candidates.map(\.provider), ["DeepSeek"])
        XCTAssertTrue(model.isReady)
        XCTAssertEqual(model.english, "Second")
    }

    @MainActor
    func testPreferredProviderTakesSelectionWhenItArrivesLater() throws {
        UserDefaults.standard.set("ChatGPT plan", forKey: preferenceKey)
        let model = ReviewModel()
        model.beginResults(providers: ["ChatGPT plan", "DeepSeek"])
        model.receive(try candidate("DeepSeek", english: "Second"))
        model.receive(try candidate("ChatGPT plan", english: "First"))

        XCTAssertEqual(model.candidates.map(\.provider), ["ChatGPT plan", "DeepSeek"])
        XCTAssertEqual(model.english, "First")
        XCTAssertEqual(model.selectedCandidateIndex, 0)
    }

    @MainActor
    func testManualSelectionSurvivesLaterResponseAndPersists() throws {
        let model = ReviewModel()
        model.beginResults(providers: ["ChatGPT plan", "DeepSeek"])
        model.receive(try candidate("DeepSeek", english: "Second"))
        model.selectCandidate(at: 0)
        model.receive(try candidate("ChatGPT plan", english: "First"))

        XCTAssertEqual(model.english, "Second")
        XCTAssertEqual(model.selectedCandidateIndex, 1)
        XCTAssertEqual(UserDefaults.standard.string(forKey: preferenceKey), "DeepSeek")
    }

    @MainActor
    func testEditingUnselectedCardDoesNotChangeReplaceTarget() throws {
        let model = ReviewModel()
        model.beginResults(providers: ["ChatGPT plan", "DeepSeek"])
        model.receive(try candidate("ChatGPT plan", english: "First"))
        model.receive(try candidate("DeepSeek", english: "Second"))
        model.editEnglish("Edited second", for: "DeepSeek")

        XCTAssertEqual(model.english, "First")
        XCTAssertEqual(model.candidates[1].english, "Edited second")
    }

    @MainActor
    func testArrowSelectionMovesBetweenAvailableResultsAndUpdatesReplaceTarget() throws {
        let model = ReviewModel()
        model.beginResults(providers: ["ChatGPT plan", "DeepSeek", "Kimi"])
        model.receive(try candidate("ChatGPT plan", english: "First"))
        model.receive(try candidate("Kimi", english: "Third"))
        var selectionChanges = 0
        model.onSelectCandidate = { selectionChanges += 1 }

        model.moveSelection(by: 1)
        XCTAssertEqual(model.selectedCandidateIndex, 1)
        XCTAssertEqual(model.english, "Third")
        XCTAssertEqual(UserDefaults.standard.string(forKey: preferenceKey), "Kimi")

        model.moveSelection(by: 1)
        XCTAssertEqual(model.selectedCandidateIndex, 1)
        XCTAssertEqual(selectionChanges, 1)

        model.moveSelection(by: -1)
        XCTAssertEqual(model.selectedCandidateIndex, 0)
        XCTAssertEqual(model.english, "First")
        XCTAssertEqual(selectionChanges, 2)
    }

    @MainActor
    func testArrowSelectionDoesNothingBeforeResultsArrive() {
        let model = ReviewModel()
        model.beginResults(providers: ["ChatGPT plan", "DeepSeek"])
        model.moveSelection(by: 1)
        XCTAssertFalse(model.isReady)
        XCTAssertEqual(model.selectedCandidateIndex, 0)
    }

    @MainActor
    func testReturnReplacesSelectedResultWhenPanelActionIsAvailable() throws {
        let model = ReviewModel()
        model.source = "Original"
        model.beginResults(providers: ["ChatGPT plan", "DeepSeek"])
        model.receive(try candidate("ChatGPT plan", english: "First"))
        model.receive(try candidate("DeepSeek", english: "Second"))
        model.selectCandidate(at: 1)
        var replacedEnglish: String?
        model.onReplace = { replacedEnglish = model.english }

        XCTAssertTrue(model.replaceFromPanel())
        XCTAssertEqual(replacedEnglish, "Second")
    }

    @MainActor
    func testReturnDoesNotReplaceWhenButtonWouldBeUnavailable() throws {
        let model = ReviewModel()
        model.source = "Original"
        var replacementCount = 0
        model.onReplace = { replacementCount += 1 }
        XCTAssertFalse(model.replaceFromPanel())

        model.beginResults(providers: ["ChatGPT plan"])
        model.receive(try candidate("ChatGPT plan", english: "Original"))
        XCTAssertFalse(model.replaceFromPanel())

        model.editEnglish("Changed", for: "ChatGPT plan")
        model.usedKeyboardFallback = true
        model.canRestoreFocus = false
        XCTAssertFalse(model.replaceFromPanel())

        model.canRestoreFocus = true
        model.isReplacing = true
        XCTAssertFalse(model.replaceFromPanel())
        XCTAssertEqual(replacementCount, 0)
    }

    private func candidate(_ provider: String, english: String) throws -> ReviewCandidate {
        ReviewCandidate(provider: provider,
                        result: try AnalysisResult(english: english, chineseMeaning: "中文", ambiguity: nil))
    }
}
