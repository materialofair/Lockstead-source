import XCTest
@testable import Lockstead

final class RootRouteTests: XCTestCase {
    func testRouting() {
        XCTAssertEqual(RootRoute.determine(isAuthorized: false, hasPIN: false, sessionUnlocked: false), .onboarding)
        XCTAssertEqual(RootRoute.determine(isAuthorized: true, hasPIN: false, sessionUnlocked: false), .pinSetup)
        XCTAssertEqual(RootRoute.determine(isAuthorized: true, hasPIN: true, sessionUnlocked: false), .pinEntry)
        XCTAssertEqual(RootRoute.determine(isAuthorized: true, hasPIN: true, sessionUnlocked: true), .home)
    }
}
