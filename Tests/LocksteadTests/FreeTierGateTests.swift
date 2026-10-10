import XCTest
@testable import Lockstead

final class FreeTierGateTests: XCTestCase {
    func testFreeUserLimits() {
        XCTAssertTrue(FreeTierGate.canManage(appCount: 0, isVIP: false))
        XCTAssertTrue(FreeTierGate.canManage(appCount: 1, isVIP: false))
        XCTAssertFalse(FreeTierGate.canManage(appCount: 2, isVIP: false))
    }

    func testVIPUnlimited() {
        XCTAssertTrue(FreeTierGate.canManage(appCount: 200, isVIP: true))
    }

    func testPaywallTriggersExactlyWhenExceedingFreeLimit() {
        XCTAssertFalse(FreeTierGate.requiresPaywall(newCount: 1, isVIP: false))
        XCTAssertTrue(FreeTierGate.requiresPaywall(newCount: 2, isVIP: false))
        XCTAssertFalse(FreeTierGate.requiresPaywall(newCount: 2, isVIP: true))
    }
}
