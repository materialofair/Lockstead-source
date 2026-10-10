import SwiftUI
import UIKit

struct CalculatorLoginView: View {
    private enum Surface {
        case calculator
        case converter
    }

    let onUnlocked: () -> Void

    @State private var calculator = CalculatorLoginEngine()
    @State private var converter = UnitConversionState()
    @State private var surface: Surface = .calculator
    @State private var showRecovery = false
    @State private var showStorageError = false
    @State private var copiedResult = false
    @State private var lockoutUntil: Date?
    private let store = AppGroupStore()
    private let rows: [[CalculatorKey]] = [
        [.clear, .negate, .percent, .divide],
        [.digit(7), .digit(8), .digit(9), .multiply],
        [.digit(4), .digit(5), .digit(6), .subtract],
        [.digit(1), .digit(2), .digit(3), .add],
        [.digit(0), .decimal, .equals]
    ]

    var body: some View {
        GeometryReader { geometry in
            let spacing: CGFloat = 12
            let widthLimitedSize = (min(geometry.size.width - 32, 430) - spacing * 3) / 4
            let heightLimitedSize = max(56, (geometry.size.height - 210) / 5)
            let buttonSize = min(widthLimitedSize, heightLimitedSize)
            let panelWidth = buttonSize * 4 + spacing * 3

            ZStack {
                Color.black.ignoresSafeArea()
                VStack(spacing: spacing) {
                    Spacer(minLength: 24)
                    if surface == .calculator {
                        calculatorSurface(buttonSize: buttonSize, spacing: spacing)
                    } else {
                        ScrollView(.vertical, showsIndicators: false) {
                            converterSurface(buttonSize: buttonSize, spacing: spacing)
                        }
                    }
                }
                .frame(width: panelWidth)
                .padding(.bottom, 16)
            }
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showRecovery) { PINRecoveryHelpView() }
        .alert(String(localized: "pin.manage.storage.title", table: "PINExperience"), isPresented: $showStorageError) {
            Button("common.ok", role: .cancel) {}
        } message: {
            Text("pin.manage.storage", tableName: "PINExperience")
        }
        .task {
            // 冷启动恢复锁定期(冷却状态在 Keychain,重启不丢)——与 PINEntryView 保持同一行为
            if lockoutUntil == nil, let until = PINManager().lockoutUntil(in: store.load()) {
                lockoutUntil = until
            }
        }
    }

    @ViewBuilder
    private func calculatorSurface(buttonSize: CGFloat, spacing: CGFloat) -> some View {
        HStack {
            Button { showRecovery = true } label: {
                Image(systemName: "questionmark.circle")
                    .foregroundStyle(Color(white: 0.7))
                    .frame(width: 36, height: 30)
            }
            .accessibilityLabel(Text("pin.recovery.help", tableName: "PINExperience"))
            Spacer()
            Button { surface = .converter } label: {
                Image(systemName: "ruler")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(Color(white: 0.7))
                    .frame(width: 36, height: 30)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("calculator.converter.open")
        }
        Text(CalculatorNumberDisplay.text(calculator.display))
            .font(.system(size: min(78, buttonSize * 0.8), weight: .light))
            .foregroundStyle(.white)
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.45)
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.horizontal, 8)
            .padding(.bottom, 8)

        ForEach(rows, id: \.self) { row in
            HStack(spacing: spacing) {
                ForEach(row, id: \.self) { key in
                    CalculatorLoginButton(
                        key: key,
                        width: key == .digit(0) ? buttonSize * 2 + spacing : buttonSize,
                        height: buttonSize
                    ) {
                        handle(key)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func converterSurface(buttonSize: CGFloat, spacing: CGFloat) -> some View {
        HStack {
            Button { surface = .calculator } label: {
                Image(systemName: "plus.forwardslash.minus")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(Color(white: 0.7))
                    .frame(width: 36, height: 30)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("calculator.converter.close")
            Spacer()
            Menu {
                ForEach(UnitCategory.allCases, id: \.self) { category in
                    Button(String(localized: String.LocalizationValue(category.localizationKey))) {
                        converter.select(category: category)
                    }
                }
            } label: {
                Label(String(localized: String.LocalizationValue(converter.category.localizationKey)), systemImage: "chevron.up.chevron.down")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white)
            }
        }

        HStack(spacing: 8) {
            unitMenu(selection: converter.source, isSource: true)
            Button { converter.swapUnits() } label: {
                Image(systemName: "arrow.left.arrow.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.black)
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(Color(white: 0.7)))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("calculator.converter.swap"))
            unitMenu(selection: converter.destination, isSource: false)
        }

        VStack(alignment: .trailing, spacing: 2) {
            Text(CalculatorNumberDisplay.text(converter.input.isEmpty ? "0" : converter.input))
                .font(.system(size: min(34, buttonSize * 0.38), weight: .light))
                .foregroundStyle(Color(white: 0.7))
            Text(CalculatorNumberDisplay.text(converter.result))
                .font(.system(size: min(58, buttonSize * 0.62), weight: .light))
                .foregroundStyle(.white)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.45)
                .onLongPressGesture {
                    UIPasteboard.general.string = converter.result
                    copiedResult = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { copiedResult = false }
                }
            if copiedResult {
                Text("calculator.converter.copied")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Color(white: 0.7))
            }
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .padding(.horizontal, 8)

        ForEach(ConverterKey.rows, id: \.self) { row in
            HStack(spacing: spacing) {
                ForEach(row, id: \.self) { key in
                    ConverterKeyButton(key: key, width: key == .zero ? buttonSize * 2 + spacing : buttonSize, height: buttonSize) {
                        handleConverter(key)
                    }
                }
            }
        }
    }

    private func unitMenu(selection: Unit, isSource: Bool) -> some View {
        Menu {
            ForEach(converter.category.units, id: \.self) { unit in
                Button {
                    if isSource { converter.select(source: unit) }
                    else { converter.select(destination: unit) }
                } label: {
                    Text(String(localized: String.LocalizationValue(unit.localizationKey)))
                }
            }
        } label: {
            Text(selection.symbol)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(Capsule().fill(Color(white: 0.22)))
        }
    }
    private func handle(_ key: CalculatorKey) {
        let feedback = UIImpactFeedbackGenerator(style: .light)
        feedback.impactOccurred()
        guard let candidate = calculator.press(key) else { return }

        // 锁定期内保持伪装:计算器照常可用,只是不再校验候选(校验本身也会被冷却拦截)
        if let lockoutUntil, lockoutUntil > Date() { return }

        var state = store.load()
        let result = PINManager().verify(pin: candidate, state: &state)
        store.save(state)
        switch result {
        case .success:
            onUnlocked()
        case .storageFailure:
            showStorageError = true
        case .wrongPIN, .lockedOut:
            // 伪装约束下不显示错误文案;用警示触感给出中性反馈(家长能感知,孩子看不出语义)
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
            if case .lockedOut(let until) = result {
                lockoutUntil = until
            }
        }
    }

    private func handleConverter(_ key: ConverterKey) {
        let feedback = UIImpactFeedbackGenerator(style: .light)
        feedback.impactOccurred()
        switch key {
        case .digit(let digit): converter.append(digit: digit)
        case .decimal: converter.appendDecimal()
        case .clear: converter.clear()
        case .negate: converter.toggleSign()
        case .percent: converter.applyPercent()
        case .delete: converter.deleteLast()
        case .zero: converter.append(digit: 0)
        }
    }
}

private enum ConverterKey: Hashable {
    case digit(Int), zero, decimal, clear, negate, percent, delete

    static let rows: [[ConverterKey]] = [
        [.clear, .negate, .percent, .delete],
        [.digit(7), .digit(8), .digit(9)],
        [.digit(4), .digit(5), .digit(6)],
        [.digit(1), .digit(2), .digit(3)],
        [.zero, .decimal]
    ]

    var title: String {
        switch self {
        case .digit(let digit): String(digit)
        case .zero: "0"
        case .decimal: "."
        case .clear: "AC"
        case .negate: "+/−"
        case .percent: "%"
        case .delete: "⌫"
        }
    }
}

private struct ConverterKeyButton: View {
    let key: ConverterKey
    let width: CGFloat
    let height: CGFloat
    let action: () -> Void

    private var color: Color {
        switch key {
        case .clear, .negate, .percent: Color(white: 0.62)
        case .delete: .orange
        default: Color(white: 0.22)
        }
    }

    var body: some View {
        Button(action: action) {
            Text(CalculatorNumberDisplay.text(key.title))
                .font(.system(size: 31, weight: .medium))
                .foregroundStyle(key == .clear || key == .negate || key == .percent ? .black : .white)
                .frame(width: width, height: height)
                .background(color)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

private struct CalculatorLoginButton: View {
    let key: CalculatorKey
    let width: CGFloat
    let height: CGFloat
    let action: () -> Void

    private var color: Color {
        switch key {
        case .add, .subtract, .multiply, .divide, .equals: .orange
        case .clear, .negate, .percent: Color(white: 0.62)
        default: Color(white: 0.22)
        }
    }

    var body: some View {
        Button(action: action) {
            Text(CalculatorNumberDisplay.text(key.title))
                .font(.system(size: 31, weight: .medium))
                .foregroundStyle(key == .clear || key == .negate || key == .percent ? .black : .white)
                .frame(width: width, height: height)
                .background(color)
                .clipShape(Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(CalculatorNumberDisplay.text(key.title))
    }
}
