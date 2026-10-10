import XCTest
@testable import Lockstead

final class VIPProductsTests: XCTestCase {
    private struct ProductLoadingError: LocalizedError {
        var errorDescription: String? { "Products unavailable" }
    }

    /// 审核码本身只出现在审核备注里(源码与二进制都只存哈希),测试用码与备注一致
    private let reviewCode = "LOCKSTEAD-PUBLIC-TEST-ONLY"

    private func reviewAccess(expiryDate: Date = .distantFuture) -> ReviewAccessStore {
        ReviewAccessStore(flagStore: InMemoryReviewAccessFlagStore(), expiryDate: expiryDate)
    }

    func testAnyVIPProductGrantsVIP() {
        XCTAssertTrue(VIPProducts.isVIP(activeProductIDs: ["lockstead.vip.monthly"]))
        XCTAssertTrue(VIPProducts.isVIP(activeProductIDs: ["lockstead.vip.lifetime", "other"]))
        XCTAssertFalse(VIPProducts.isVIP(activeProductIDs: []))
        XCTAssertFalse(VIPProducts.isVIP(activeProductIDs: ["some.random.id"]))
    }

    @MainActor
    func testVerifiedPurchaseGrantsAndPersistsVIPBeforeFinishingTransaction() async {
        let defaults = UserDefaults(suiteName: "unit-test-\(UUID().uuidString)")!
        let store = AppGroupStore(defaults: defaults)
        let reviewAccess = reviewAccess()
        let sut = EntitlementStore(appGroupStore: store, reviewAccessStore: reviewAccess)
        var wasVIPWhenFinished = false

        await sut.completeVerifiedPurchase(productID: VIPProducts.lifetime) {
            wasVIPWhenFinished = sut.isVIP
        }

        XCTAssertTrue(wasVIPWhenFinished)
        XCTAssertTrue(sut.isVIP)
        XCTAssertTrue(store.load().isVIP)
    }

    @MainActor
    func testRefreshRestoresVIPFromLatestTransactionWhenCurrentEntitlementsAreEmpty() async {
        let defaults = UserDefaults(suiteName: "unit-test-\(UUID().uuidString)")!
        let store = AppGroupStore(defaults: defaults)
        let sut = EntitlementStore(
            appGroupStore: store,
            reviewAccessStore: reviewAccess(),
            activeProductIDsProvider: { [VIPProducts.lifetime] }
        )

        await sut.refresh()

        XCTAssertTrue(sut.isVIP)
        XCTAssertTrue(store.load().isVIP)
    }

    @MainActor
    func testProductLoadingFailureLeavesRetryableNonLoadingState() async {
        let defaults = UserDefaults(suiteName: "unit-test-\(UUID().uuidString)")!
        let sut = EntitlementStore(
            appGroupStore: AppGroupStore(defaults: defaults),
            reviewAccessStore: reviewAccess(),
            productsProvider: { throw ProductLoadingError() }
        )

        await sut.loadProducts()

        XCTAssertFalse(sut.isLoadingProducts)
        XCTAssertTrue(sut.products.isEmpty)
        XCTAssertEqual(sut.lastError, "Products unavailable")
    }

    @MainActor
    func testEmptyProductResponseBecomesRetryableErrorInsteadOfInfiniteLoading() async {
        let defaults = UserDefaults(suiteName: "unit-test-\(UUID().uuidString)")!
        let sut = EntitlementStore(
            appGroupStore: AppGroupStore(defaults: defaults),
            reviewAccessStore: reviewAccess(),
            productsProvider: { [] }
        )

        await sut.loadProducts()

        XCTAssertFalse(sut.isLoadingProducts)
        XCTAssertTrue(sut.products.isEmpty)
        XCTAssertEqual(sut.lastError, String(localized: "paywall.load.empty"))
    }

    @MainActor
    func testReviewAccessGrantsVIPAndSurvivesEmptyTransactionRefresh() async {
        let defaults = UserDefaults(suiteName: "unit-test-\(UUID().uuidString)")!
        let store = AppGroupStore(defaults: defaults)
        let expiry = Date(timeIntervalSince1970: 2_000)
        let now = Date(timeIntervalSince1970: 1_000)
        let reviewAccess = ReviewAccessStore(flagStore: InMemoryReviewAccessFlagStore(), expiryDate: expiry)
        let sut = EntitlementStore(
            appGroupStore: store,
            reviewAccessStore: reviewAccess,
            now: { now },
            activeProductIDsProvider: { [] }
        )

        XCTAssertTrue(sut.activateReviewAccess(code: "  \(reviewCode.lowercased())  "))
        await sut.refresh()

        XCTAssertTrue(sut.isVIP)
        XCTAssertTrue(sut.isReviewAccessActive)
        XCTAssertTrue(store.load().isVIP)
    }

    @MainActor
    func testExpiredReviewAccessClearsStaleVIPMirror() async {
        let defaults = UserDefaults(suiteName: "unit-test-\(UUID().uuidString)")!
        let store = AppGroupStore(defaults: defaults)
        let expiry = Date(timeIntervalSince1970: 2_000)
        let reviewAccess = ReviewAccessStore(flagStore: InMemoryReviewAccessFlagStore(), expiryDate: expiry)
        XCTAssertTrue(reviewAccess.activate(code: reviewCode,
                                            at: Date(timeIntervalSince1970: 1_000)))
        var state = store.load()
        state.isVIP = true
        store.save(state)

        let sut = EntitlementStore(
            appGroupStore: store,
            reviewAccessStore: reviewAccess,
            now: { Date(timeIntervalSince1970: 3_000) },
            activeProductIDsProvider: { [] }
        )
        await sut.refresh()

        XCTAssertFalse(sut.isVIP)
        XCTAssertFalse(sut.isReviewAccessActive)
        XCTAssertFalse(store.load().isVIP)
    }

    @MainActor
    func testVerifiedPurchaseReplacesTemporaryReviewAccess() async {
        let defaults = UserDefaults(suiteName: "unit-test-\(UUID().uuidString)")!
        let reviewAccess = ReviewAccessStore(flagStore: InMemoryReviewAccessFlagStore(), expiryDate: .distantFuture)
        let sut = EntitlementStore(
            appGroupStore: AppGroupStore(defaults: defaults),
            reviewAccessStore: reviewAccess
        )
        XCTAssertTrue(sut.activateReviewAccess(code: reviewCode))

        await sut.completeVerifiedPurchase(productID: VIPProducts.lifetime) {}

        XCTAssertTrue(sut.isVIP)
        XCTAssertFalse(reviewAccess.wasActivated)
        XCTAssertFalse(sut.isReviewAccessActive)
    }
}
