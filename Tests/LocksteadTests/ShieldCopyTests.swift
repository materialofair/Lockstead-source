import XCTest
@testable import Lockstead

final class ShieldCopyTests: XCTestCase {
    func testCopyNonEmptyAndVariesByVIP() {
        let free = ShieldCopy.make(isVIP: false, appName: "TikTok")
        let vip = ShieldCopy.make(isVIP: true, appName: "TikTok")
        XCTAssertFalse(free.title.isEmpty)
        XCTAssertFalse(free.button.isEmpty)
        XCTAssertNotEqual(free.subtitle, vip.subtitle) // 免费版带升级引导
    }

    func testNilAppNameStillProducesTitle() {
        XCTAssertFalse(ShieldCopy.make(isVIP: false, appName: nil).title.isEmpty)
    }

    // 无痕模式的全部意义:不泄露品牌、不泄露 App 名、不提 PIN
    func testDiscreetCopyRevealsNothing() {
        let copy = ShieldCopy.make(isVIP: false, appName: "TikTok", discreet: true)
        XCTAssertFalse(copy.title.isEmpty)
        XCTAssertFalse(copy.subtitle.isEmpty)
        for text in [copy.title, copy.subtitle, copy.button] {
            XCTAssertFalse(text.contains("Lockstead"), "无痕文案泄露品牌名: \(text)")
            XCTAssertFalse(text.contains("TikTok"), "无痕文案泄露 App 名: \(text)")
            XCTAssertFalse(text.contains("PIN"), "无痕文案泄露 PIN 提示: \(text)")
        }
    }

    func testDiscreetCopyHasNoVIPUpsell() {
        let free = ShieldCopy.make(isVIP: false, appName: "X", discreet: true)
        let vip = ShieldCopy.make(isVIP: true, appName: "X", discreet: true)
        XCTAssertEqual(free.subtitle, vip.subtitle) // 无痕模式下不做升级引导
    }
}
