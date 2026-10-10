import XCTest
@testable import Lockstead

final class SelectionPolicyTests: XCTestCase {
    func testWebDomainsUnsupported() {
        XCTAssertEqual(SelectionPolicy.evaluate(appCount: 0, categoryCount: 0, webDomainCount: 2, isVIP: true),
                       .unsupportedKinds)
    }

    // 类别 = 无限量 App:VIP 可用,免费档走 Paywall(不能绕过 1 个 App 的边界)
    func testCategoriesAreVIPOnly() {
        XCTAssertEqual(SelectionPolicy.evaluate(appCount: 0, categoryCount: 1, webDomainCount: 0, isVIP: true),
                       .ok)
        XCTAssertEqual(SelectionPolicy.evaluate(appCount: 1, categoryCount: 2, webDomainCount: 0, isVIP: true),
                       .ok)
        XCTAssertEqual(SelectionPolicy.evaluate(appCount: 0, categoryCount: 1, webDomainCount: 0, isVIP: false),
                       .needsPaywall)
    }

    func testFreeUserSecondAppNeedsPaywall() {
        XCTAssertEqual(SelectionPolicy.evaluate(appCount: 2, categoryCount: 0, webDomainCount: 0, isVIP: false),
                       .needsPaywall)
        XCTAssertEqual(SelectionPolicy.evaluate(appCount: 1, categoryCount: 0, webDomainCount: 0, isVIP: false),
                       .ok)
        XCTAssertEqual(SelectionPolicy.evaluate(appCount: 5, categoryCount: 0, webDomainCount: 0, isVIP: true),
                       .ok)
    }
}
