import XCTest
@testable import SenseDraftCore

final class HistoryArchiveTests: XCTestCase {
    func testEncryptedArchiveRoundTripsAndRejectsAnotherKey() throws {
        let entry = HistoryEntry(source: "private draft", english: "suggestion",
                                 chinese: "含义", provider: "API Key")
        let key = Data(repeating: 0x42, count: 32)
        let encrypted = try HistoryArchive.seal([entry], key: key)

        XCTAssertFalse(encrypted.contains(Data("private draft".utf8)))
        XCTAssertEqual(try HistoryArchive.open(encrypted, key: key), [entry])
        XCTAssertThrowsError(try HistoryArchive.open(encrypted, key: Data(repeating: 0x24, count: 32)))
    }
}
