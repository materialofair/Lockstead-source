import XCTest
@testable import Lockstead

final class SmokeTests: XCTestCase {
    func testAppGroupConstants() {
        XCTAssertTrue(AppGroup.suiteName.hasPrefix("group."))
    }
}
