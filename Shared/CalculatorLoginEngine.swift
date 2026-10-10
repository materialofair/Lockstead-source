import Foundation

enum CalculatorKey: Hashable {
    case digit(Int)
    case add, subtract, multiply, divide
    case equals, clear, negate, percent, decimal

    var title: String {
        switch self {
        case .digit(let digit): String(digit)
        case .add: "+"
        case .subtract: "−"
        case .multiply: "×"
        case .divide: "÷"
        case .equals: "="
        case .clear: "AC"
        case .negate: "+/−"
        case .percent: "%"
        case .decimal: "."
        }
    }
}

struct CalculatorLoginEngine: Equatable {
    private enum Operation: Equatable {
        case add, subtract, multiply, divide
    }

    private(set) var display = "0"
    private var previousValue: Double?
    private var operation: Operation?
    private var shouldResetDisplay = false
    private var unlockInput = ""
    private var unlockInputOverflowed = false
    private var pendingUnlockCandidate: String?

    /// Handles a calculator key and returns a PIN candidate only after exactly six digits
    /// followed by two consecutive `=` presses (第一次 `=` 结算并把候选挂起,第二次 `=` 才提交).
    /// 双等号确认大幅收窄误触发面:孩子随手按一次 `=` 做计算不会计入失败次数、不会触发锁定;
    /// 任何算术操作(运算符/取反/百分号)都会重置隐藏输入,跨运算符的数字链也不是候选。
    mutating func press(_ key: CalculatorKey) -> String? {
        if key == .equals {
            // 挂起的候选只有紧接的下一次 = 能提交;期间按任何其他键都会取消挂起
            if let pending = pendingUnlockCandidate {
                pendingUnlockCandidate = nil
                return pending
            }
            let candidate = unlockCandidate()
            calculateResult()
            operation = nil
            shouldResetDisplay = true
            unlockInput = ""
            unlockInputOverflowed = false
            pendingUnlockCandidate = candidate
            return nil
        }
        pendingUnlockCandidate = nil
        switch key {
        case .digit(let digit):
            guard (0...9).contains(digit) else { return nil }
            if enterDigit(digit) {
                recordUnlockCharacter(String(digit))
            }
        case .decimal:
            if enterDecimal() {
                recordUnlockCharacter(".")
            }
        case .add:
            setOperation(.add)
        case .subtract:
            setOperation(.subtract)
        case .multiply:
            setOperation(.multiply)
        case .divide:
            setOperation(.divide)
        case .negate:
            resetUnlockInput()
            if let value = Double(display) { display = Self.format(-value) }
        case .percent:
            resetUnlockInput()
            if let value = Double(display) { display = Self.format(value / 100) }
        case .clear:
            self = Self()
        case .equals:
            break
        }
        return nil
    }

    /// - Returns: 数字是否真正进入了显示。达到 12 位上限时被丢弃的按键不计入隐藏输入,
    /// 保证「屏幕外」的数字不会混进 PIN 候选。
    private mutating func enterDigit(_ digit: Int) -> Bool {
        let value = String(digit)
        if shouldResetDisplay {
            display = value
            shouldResetDisplay = false
            return true
        }
        guard display.count < 12 else { return false }
        display = display == "0" ? value : display + value
        return true
    }

    private mutating func enterDecimal() -> Bool {
        if shouldResetDisplay {
            display = "0."
            shouldResetDisplay = false
            return true
        }
        guard !display.contains("."), display.count < 12 else { return false }
        display += "."
        return true
    }

    private mutating func setOperation(_ newOperation: Operation) {
        resetUnlockInput()
        if operation != nil {
            calculateResult()
        } else {
            previousValue = Double(display)
        }
        operation = newOperation
        shouldResetDisplay = true
    }

    private mutating func calculateResult() {
        guard let operation, let left = previousValue, let right = Double(display) else { return }
        let result: Double
        switch operation {
        case .add: result = left + right
        case .subtract: result = left - right
        case .multiply: result = left * right
        case .divide: result = right == 0 ? 0 : left / right
        }
        display = Self.format(result)
        previousValue = result
    }

    private mutating func resetUnlockInput() {
        unlockInput = ""
        unlockInputOverflowed = false
    }

    private mutating func recordUnlockCharacter(_ character: String) {
        guard !unlockInputOverflowed else { return }
        unlockInput += character
        if unlockInput.count > 6 {
            unlockInputOverflowed = true
        }
    }

    private func unlockCandidate() -> String? {
        guard !unlockInputOverflowed,
              unlockInput.count == 6,
              unlockInput.allSatisfy(\.isNumber) else { return nil }
        return unlockInput
    }

    /// 强制 POSIX locale:小数逗号地区 %f 会输出 "3,5" 这类串,导致后续 Double() 解析失败。
    /// 只修剪尾部零:两端修剪会把 "0.5" 剪成 "5"(见单测)。
    static func format(_ number: Double) -> String {
        guard number.isFinite else { return "0" }
        if number.rounded() == number {
            return String(format: "%.0f", locale: Locale(identifier: "en_US_POSIX"), number)
        }
        var text = String(format: "%.8f", locale: Locale(identifier: "en_US_POSIX"), number)
        while text.last == "0" { text.removeLast() }
        if text.last == "." { text.removeLast() }
        return text
    }
}
