import XCTest
@testable import SenseDraftCore

final class HistoryLedgerTests: XCTestCase {
    func testRegenerationUpdatesTheExistingEntry() {
        let id = UUID()
        let first = HistoryEntry(id: id, createdAt: Date(timeIntervalSince1970: 100),
                                 source: "draft", english: "first", chinese: "第一", provider: "API Key")
        let revised = HistoryEntry(id: id, createdAt: Date(timeIntervalSince1970: 200),
                                   source: "draft", english: "second", chinese: "第二", provider: "API Key")

        let entries = HistoryLedger.upsert(revised, into: HistoryLedger.upsert(first, into: []))

        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].english, "second")
        XCTAssertEqual(entries[0].createdAt, first.createdAt)
    }

    func testUnlimitedHistoryKeepsMoreThanOneHundredEntries() {
        var entries: [HistoryEntry] = []
        for index in 0..<101 {
            let entry = HistoryEntry(createdAt: Date(timeIntervalSince1970: TimeInterval(index)),
                                     source: "draft", english: "text \(index)", chinese: "意思", provider: "API Key")
            entries = HistoryLedger.upsert(entry, into: entries)
        }

        XCTAssertEqual(entries.count, 101)
        XCTAssertEqual(entries.first?.english, "text 100")
        XCTAssertEqual(entries.last?.english, "text 0")
    }

    func testSevenDayRetentionRemovesOnlyOlderEntries() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let old = HistoryEntry(createdAt: now.addingTimeInterval(-8 * 86_400),
                               source: "old", english: "old", chinese: "旧", provider: "API Key")
        let recent = HistoryEntry(createdAt: now.addingTimeInterval(-6 * 86_400),
                                  source: "recent", english: "recent", chinese: "新", provider: "API Key")
        let boundary = HistoryEntry(createdAt: now.addingTimeInterval(-7 * 86_400),
                                    source: "boundary", english: "boundary", chinese: "边界", provider: "API Key")

        XCTAssertEqual(HistoryLedger.prune([old, recent, boundary], retention: .sevenDays, now: now),
                       [recent, boundary])
        XCTAssertEqual(HistoryLedger.prune([old, recent, boundary], retention: .thirtyDays, now: now).count, 3)
        XCTAssertEqual(HistoryLedger.prune([old, recent, boundary], retention: .unlimited, now: now).count, 3)
        XCTAssertEqual(HistoryLedger.upsert(recent, into: [old], retention: .sevenDays, now: now), [recent])
    }

    func testThirtyDayRetentionRemovesEntriesOlderThanThirtyDays() {
        let now = Date(timeIntervalSince1970: 3_000_000)
        let old = HistoryEntry(createdAt: now.addingTimeInterval(-31 * 86_400),
                               source: "old", english: "old", chinese: "旧", provider: "API Key")
        let boundary = HistoryEntry(createdAt: now.addingTimeInterval(-30 * 86_400),
                                    source: "boundary", english: "boundary", chinese: "边界", provider: "API Key")

        XCTAssertEqual(HistoryLedger.prune([old, boundary], retention: .thirtyDays, now: now), [boundary])
        XCTAssertEqual(HistoryLedger.prune([old, boundary], retention: .unlimited, now: now), [boundary, old])
    }

    func testReplacementRecordsTheFinalEditedEnglish() {
        let entry = HistoryEntry(source: "draft", english: "suggestion", chinese: "意思", provider: "API Key")
        let entries = HistoryLedger.markReplaced(entry.id, english: "edited", in: [entry])

        XCTAssertEqual(entries[0].english, "edited")
        XCTAssertTrue(entries[0].replaced)
    }
}
