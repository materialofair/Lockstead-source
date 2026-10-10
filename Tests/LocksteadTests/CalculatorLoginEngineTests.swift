import XCTest
@testable import Lockstead

final class CalculatorLoginEngineTests: XCTestCase {
    func testBasicCalculationRemainsFunctional() {
        var engine = CalculatorLoginEngine()
        _ = engine.press(.digit(8))
        _ = engine.press(.add)
        _ = engine.press(.digit(4))
        XCTAssertNil(engine.press(.equals))
        XCTAssertEqual(engine.display, "12")
    }

    func testExactlySixDigitsThenEqualsReturnsUnlockCandidate() {
        var engine = CalculatorLoginEngine()
        for digit in [1, 2, 3, 4, 5, 6] { _ = engine.press(.digit(digit)) }
        XCTAssertNil(engine.press(.equals))         // 第一次 = 只结算,不提交候选
        XCTAssertEqual(engine.press(.equals), "123456") // 第二次 = 确认提交
    }

    func testTooFewOrTooManyDigitsDoNotReturnCandidate() {
        var short = CalculatorLoginEngine()
        for digit in [1, 2, 3, 4, 5] { _ = short.press(.digit(digit)) }
        XCTAssertNil(short.press(.equals))
        XCTAssertNil(short.press(.equals))

        var long = CalculatorLoginEngine()
        for digit in [1, 2, 3, 4, 5, 6, 7] { _ = long.press(.digit(digit)) }
        XCTAssertNil(long.press(.equals))
        XCTAssertNil(long.press(.equals))
    }

    func testDecimalCannotBecomePINCandidate() {
        var engine = CalculatorLoginEngine()
        for digit in [1, 2, 3] { _ = engine.press(.digit(digit)) }
        _ = engine.press(.decimal)
        for digit in [4, 5] { _ = engine.press(.digit(digit)) }
        XCTAssertNil(engine.press(.equals))
        XCTAssertNil(engine.press(.equals))
    }

    func testClearResetsVisibleAndHiddenInput() {
        var engine = CalculatorLoginEngine()
        for digit in [1, 2, 3] { _ = engine.press(.digit(digit)) }
        _ = engine.press(.clear)
        for digit in [4, 5, 6] { _ = engine.press(.digit(digit)) }
        XCTAssertEqual(engine.display, "456")
        XCTAssertNil(engine.press(.equals))
    }

    func testEqualsClearsHiddenInputAfterSubmission() {
        var engine = CalculatorLoginEngine()
        for digit in [1, 2, 3, 4, 5, 6] { _ = engine.press(.digit(digit)) }
        XCTAssertNil(engine.press(.equals))
        XCTAssertEqual(engine.press(.equals), "123456")
        XCTAssertNil(engine.press(.equals)) // 提交后隐藏输入已清空,不再有候选
    }

    // MARK: - 双等号确认:单次 = 或插入其他按键不得触发 PIN 校验(防孩子误触锁死)

    func testSingleEqualsDoesNotSubmitCandidate() {
        var engine = CalculatorLoginEngine()
        for digit in [1, 2, 3, 4, 5, 6] { _ = engine.press(.digit(digit)) }
        XCTAssertNil(engine.press(.equals)) // 孩子随手按一次 = 不产生候选、不计失败
        XCTAssertEqual(engine.display, "123456")
    }

    func testInterveningKeyCancelsPendingCandidate() {
        var engine = CalculatorLoginEngine()
        for digit in [1, 2, 3, 4, 5, 6] { _ = engine.press(.digit(digit)) }
        _ = engine.press(.equals)
        _ = engine.press(.digit(7)) // 两次 = 之间插了任何键,挂起候选取消
        XCTAssertNil(engine.press(.equals))
    }

    // MARK: - 普通算术不得误触发 PIN 校验(伪装登录的锁死防护)

    func testOperatorResetsHiddenInput() {
        var engine = CalculatorLoginEngine()
        for digit in [1, 2, 3] { _ = engine.press(.digit(digit)) }
        _ = engine.press(.add)
        for digit in [4, 5, 6] { _ = engine.press(.digit(digit)) }
        XCTAssertNil(engine.press(.equals)) // 跨运算符的数字链不是 PIN 候选
        XCTAssertEqual(engine.display, "579")
    }

    func testPercentAndNegateResetHiddenInput() {
        var percent = CalculatorLoginEngine()
        for digit in [1, 2, 3, 4, 5, 6] { _ = percent.press(.digit(digit)) }
        _ = percent.press(.percent)
        XCTAssertNil(percent.press(.equals))

        var negate = CalculatorLoginEngine()
        for digit in [1, 2, 3, 4, 5, 6] { _ = negate.press(.digit(digit)) }
        _ = negate.press(.negate)
        XCTAssertNil(negate.press(.equals))
    }

    func testDigitsDroppedAtDisplayLimitDoNotEnterHiddenInput() {
        var engine = CalculatorLoginEngine()
        for _ in 1...15 { _ = engine.press(.digit(7)) }
        XCTAssertEqual(engine.display.count, 12) // 显示封顶
        XCTAssertNil(engine.press(.equals))      // 被丢弃的数字不会成为候选
    }

    // MARK: - 数字格式强制 POSIX locale(逗号小数地区 "3,5" 会破坏后续解析)

    func testFormatIsLocaleIndependent() {
        XCTAssertEqual(CalculatorLoginEngine.format(12), "12")
        XCTAssertEqual(CalculatorLoginEngine.format(12.5), "12.5")
        XCTAssertEqual(CalculatorLoginEngine.format(0.5), "0.5") // 只剪尾零,不剪小数点前的 0
        XCTAssertEqual(CalculatorLoginEngine.format(0.000001), "0.000001")
        XCTAssertEqual(CalculatorLoginEngine.format(123_456_789_012), "123456789012")
        XCTAssertEqual(CalculatorLoginEngine.format(.infinity), "0")
    }
}
