@testable import SenseDraftMac
import XCTest

final class ProviderCredentialCacheTests: XCTestCase {
    @MainActor
    func testRepeatedReadsUseOneKeychainLoad() throws {
        var reads = 0
        let cache = ProviderCredentialCache { _ in
            reads += 1
            return "secret"
        }

        XCTAssertEqual(try cache.load(service: "provider"), "secret")
        XCTAssertEqual(try cache.load(service: "provider"), "secret")
        XCTAssertEqual(reads, 1)
    }

    @MainActor
    func testSavingAndRemovingUpdateCachedKey() throws {
        let cache = ProviderCredentialCache { _ in "old" }
        XCTAssertEqual(try cache.load(service: "provider"), "old")
        cache.recordSave("new", service: "provider")
        XCTAssertEqual(try cache.load(service: "provider"), "new")
        cache.remove(service: "provider")
        XCTAssertEqual(try cache.load(service: "provider"), "old")
    }
}
