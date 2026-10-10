import XCTest
@testable import Lockstead

final class InMemoryReviewAccessFlagStore: ReviewAccessFlagStoring {
    private(set) var activated = false
    func load() -> Bool { activated }
    func save(_ activated: Bool) { self.activated = activated }
}

final class ReviewAccessStoreTests: XCTestCase {
    /// 审核码本身只出现在审核备注里(源码与二进制都只存哈希)。
    /// 公开测试夹具；与任何生产 App Review 访问码无关。
    private let reviewCode = "LOCKSTEAD-PUBLIC-TEST-ONLY"

    private func makeStore() -> (ReviewAccessStore, InMemoryReviewAccessFlagStore) {
        let flagStore = InMemoryReviewAccessFlagStore()
        let expiry = Date(timeIntervalSince1970: 2_000)
        return (ReviewAccessStore(flagStore: flagStore, expiryDate: expiry), flagStore)
    }

    func testActivationRequiresCodeAndMustHappenBeforeExpiry() {
        let (sut, flagStore) = makeStore()

        XCTAssertFalse(sut.activate(code: "wrong", at: Date(timeIntervalSince1970: 1_000)))
        XCTAssertFalse(flagStore.load())
        XCTAssertFalse(sut.activate(code: reviewCode, at: Date(timeIntervalSince1970: 2_000))) // 到期
        XCTAssertTrue(sut.activate(code: "  \(reviewCode.lowercased())  ",
                                   at: Date(timeIntervalSince1970: 1_000))) // 大小写/空白容错
        XCTAssertTrue(flagStore.load())
        XCTAssertTrue(sut.isActive(at: Date(timeIntervalSince1970: 1_999)))
    }

    func testExpiredAccessClearsPersistedActivation() {
        let (sut, flagStore) = makeStore()
        XCTAssertTrue(sut.activate(code: reviewCode, at: Date(timeIntervalSince1970: 1_000)))

        XCTAssertFalse(sut.isActive(at: Date(timeIntervalSince1970: 2_000)))
        XCTAssertFalse(flagStore.load())
    }

    func testClearRemovesActivation() {
        let (sut, flagStore) = makeStore()
        XCTAssertTrue(sut.activate(code: reviewCode, at: Date(timeIntervalSince1970: 1_000)))
        sut.clear()
        XCTAssertFalse(flagStore.load())
        XCTAssertFalse(sut.wasActivated)
    }
}
