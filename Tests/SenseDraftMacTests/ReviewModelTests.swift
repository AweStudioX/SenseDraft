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
    func testResultCanWaitForPanelResizeBeforeBecomingVisibleOrReplaceable() throws {
        let model = ReviewModel()
        model.source = "Original"
        model.beginResults(providers: ["DeepSeek"])
        model.receive(try candidate("DeepSeek", english: "Revised"), deferReveal: true)

        XCTAssertFalse(model.revealedProviders.contains("DeepSeek"))
        XCTAssertFalse(model.hasReplacement)

        model.revealPendingResults()
        XCTAssertTrue(model.revealedProviders.contains("DeepSeek"))
        XCTAssertTrue(model.hasReplacement)
    }

    @MainActor
    func testCopyUsesOnlyTheSelectedRevealedSuggestion() throws {
        let model = ReviewModel()
        model.beginResults(providers: ["ChatGPT plan", "DeepSeek"])
        model.receive(try candidate("ChatGPT plan", english: "First"))
        model.receive(try candidate("DeepSeek", english: "Second"))
        var copiedProviders: [String] = []
        model.onCopyCandidate = { copiedProviders.append($0) }

        model.selectCandidate(at: 1)
        model.copySelectedSuggestion()
        XCTAssertEqual(copiedProviders, ["DeepSeek"])

        model.beginResults(providers: ["DeepSeek"])
        model.receive(try candidate("DeepSeek", english: "Third"), deferReveal: true)
        model.copySelectedSuggestion()
        XCTAssertEqual(copiedProviders, ["DeepSeek"])
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

    @MainActor
    func testUnchangedSelectedEnglishExplainsWhyReplaceIsUnavailable() throws {
        let model = ReviewModel()
        model.source = "Original"
        model.beginResults(providers: ["DeepSeek"])
        XCTAssertNil(model.replacementUnavailableReason)

        model.receive(try candidate("DeepSeek", english: "Original"))
        XCTAssertEqual(model.replacementUnavailableReason,
                       "Selected suggestion matches the original. Edit it to enable Replace.")

        model.editEnglish("Revised", for: "DeepSeek")
        XCTAssertNil(model.replacementUnavailableReason)
    }

    @MainActor
    func testRegenerateShortcutUsesEditedChineseAndRespectsLoadingState() throws {
        let model = ReviewModel()
        model.source = "Original"
        model.beginResults(providers: ["DeepSeek"])
        model.receive(try candidate("DeepSeek", english: "Revised"))
        var regenerated = 0
        model.onRegenerate = { regenerated += 1 }

        XCTAssertEqual(model.regenerateTitle, "Regenerate")
        XCTAssertNil(model.editedChineseIntent)
        XCTAssertTrue(model.regenerateFromPanel())

        model.editChinese("改过的中文", for: "DeepSeek")
        XCTAssertEqual(model.regenerateTitle, "Regenerate from meaning check")
        XCTAssertEqual(model.editedChineseIntent, "改过的中文")
        XCTAssertTrue(model.regenerateFromPanel())

        model.isLoading = true
        XCTAssertFalse(model.regenerateFromPanel())
        XCTAssertEqual(regenerated, 2)

        model.editChinese(" ", for: "DeepSeek")
        XCTAssertNil(model.editedChineseIntent)
        XCTAssertEqual(model.regenerateTitle, "Regenerate")
    }

    @MainActor
    func testLateProviderResultDoesNotTurnEditedMeaningIntoGeneratedMeaning() throws {
        let model = ReviewModel()
        model.source = "Original"
        model.beginResults(providers: ["DeepSeek", "Kimi"])
        model.receive(try candidate("DeepSeek", english: "First"))
        model.editChinese("用户纠正的意思", for: "DeepSeek")

        model.receive(try candidate("Kimi", english: "Second"))

        XCTAssertEqual(model.editedChineseIntent, "用户纠正的意思")
        XCTAssertEqual(model.lastGeneratedChinese, "中文")
    }

    @MainActor
    func testRegenerationKeepsLatestUserCorrectionWithoutFurtherEdits() throws {
        let model = ReviewModel()
        model.source = "Original"
        var requestedIntents: [String?] = []
        model.onRegenerate = { requestedIntents.append(model.editedChineseIntent) }
        model.beginResults(providers: ["DeepSeek"])
        model.receive(try candidate("DeepSeek", english: "First"))

        model.editChinese("第一次纠正", for: "DeepSeek")
        XCTAssertTrue(model.regenerateFromPanel())
        model.beginResults(providers: ["DeepSeek"])
        model.receive(try candidate("DeepSeek", english: "Second", chinese: "第一次的释义"))

        model.editChinese("第二次纠正", for: "DeepSeek")
        XCTAssertTrue(model.regenerateFromPanel())
        model.beginResults(providers: ["DeepSeek"])
        model.receive(try candidate("DeepSeek", english: "Third", chinese: "第二次的释义"))
        XCTAssertTrue(model.regenerateFromPanel())

        XCTAssertEqual(requestedIntents, ["第一次纠正", "第二次纠正", "第二次纠正"])
    }

    @MainActor
    func testNewCaptureClearsEarlierConfirmedMeaning() throws {
        let model = ReviewModel()
        model.source = "Original"
        model.beginResults(providers: ["DeepSeek"])
        model.receive(try candidate("DeepSeek", english: "First"))
        model.onRegenerate = {}
        model.editChinese("旧输入的纠正", for: "DeepSeek")
        XCTAssertTrue(model.regenerateFromPanel())

        model.resetChineseIntent()
        model.source = "New source"
        model.beginResults(providers: ["DeepSeek"])
        model.receive(try candidate("DeepSeek", english: "New result"))

        XCTAssertNil(model.editedChineseIntent)
    }

    @MainActor
    func testEditingAnotherMeaningCardMakesItTheRegenerationSource() throws {
        let model = ReviewModel()
        model.beginResults(providers: ["DeepSeek", "Kimi"])
        model.receive(try candidate("DeepSeek", english: "First"))
        model.receive(try candidate("Kimi", english: "Second"))

        model.editChinese("Kimi 的纠正", for: "Kimi")

        XCTAssertEqual(model.editedChineseIntent, "Kimi 的纠正")
    }

    private func candidate(_ provider: String, english: String, chinese: String) throws -> ReviewCandidate {
        ReviewCandidate(provider: provider,
                        result: try AnalysisResult(english: english, chineseMeaning: chinese, ambiguity: nil))
    }

    private func candidate(_ provider: String, english: String) throws -> ReviewCandidate {
        ReviewCandidate(provider: provider,
                        result: try AnalysisResult(english: english, chineseMeaning: "中文", ambiguity: nil))
    }
}
