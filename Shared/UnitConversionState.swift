import Foundation

struct UnitConversionState {
    private enum Key {
        static let category = "calculator.converter.category"
        static let source = "calculator.converter.source"
        static let destination = "calculator.converter.destination"
    }

    private let defaults: UserDefaults
    private(set) var category: UnitCategory
    private(set) var source: Unit
    private(set) var destination: Unit
    private(set) var input = ""

    /// 换算偏好与其他跨进程状态一致走 App Group:只读偏好,扩展并不编译本文件,
    /// 走 AppGroup.defaults 避免主 App 与其余表面隐性分域。
    init(defaults: UserDefaults = AppGroup.defaults) {
        self.defaults = defaults
        let storedCategory = defaults.string(forKey: Key.category).flatMap(UnitCategory.init(rawValue:))
        let resolvedCategory = storedCategory ?? .length
        category = resolvedCategory
        source = defaults.string(forKey: Key.source + ".\(resolvedCategory.rawValue)")
            .flatMap(Unit.init(rawValue:))
            .flatMap { $0.category == resolvedCategory ? $0 : nil } ?? Self.defaultUnits(for: resolvedCategory).source
        destination = defaults.string(forKey: Key.destination + ".\(resolvedCategory.rawValue)")
            .flatMap(Unit.init(rawValue:))
            .flatMap { $0.category == resolvedCategory ? $0 : nil }
            ?? Self.defaultUnits(for: resolvedCategory).destination
    }

    var result: String {
        guard let value = Double(input) else { return "0" }
        return UnitConverter.formatted(UnitConverter.convert(value, from: source, to: destination) ?? 0)
    }

    mutating func select(category: UnitCategory) {
        guard self.category != category else { return }
        self.category = category
        let defaults = Self.defaultUnits(for: category)
        source = self.defaults.string(forKey: Key.source + ".\(category.rawValue)")
            .flatMap(Unit.init(rawValue:))
            .flatMap { $0.category == category ? $0 : nil } ?? defaults.source
        destination = self.defaults.string(forKey: Key.destination + ".\(category.rawValue)")
            .flatMap(Unit.init(rawValue:))
            .flatMap { $0.category == category ? $0 : nil } ?? defaults.destination
        input = ""
        persistSelection()
    }

    mutating func select(source: Unit) {
        guard source.category == category else { return }
        self.source = source
        persistSelection()
    }

    mutating func select(destination: Unit) {
        guard destination.category == category else { return }
        self.destination = destination
        persistSelection()
    }

    mutating func swapUnits() {
        (source, destination) = (destination, source)
        persistSelection()
    }

    mutating func append(digit: Int) {
        guard (0...9).contains(digit), input.count < 12 else { return }
        input = input == "0" ? String(digit) : input + String(digit)
    }

    mutating func appendDecimal() {
        guard !input.contains("."), input.count < 12 else { return }
        input = input.isEmpty ? "0." : input + "."
    }

    mutating func toggleSign() {
        guard !input.isEmpty else { return }
        input = input.hasPrefix("-") ? String(input.dropFirst()) : "-" + input
    }

    mutating func applyPercent() {
        guard let value = Double(input) else { return }
        input = UnitConverter.formatted(value / 100)
    }

    mutating func deleteLast() {
        guard !input.isEmpty else { return }
        input.removeLast()
        if input == "-" { input = "" }
    }

    mutating func clear() {
        input = ""
    }

    private func persistSelection() {
        defaults.set(category.rawValue, forKey: Key.category)
        defaults.set(source.rawValue, forKey: Key.source + ".\(category.rawValue)")
        defaults.set(destination.rawValue, forKey: Key.destination + ".\(category.rawValue)")
    }

    private static func defaultUnits(for category: UnitCategory) -> (source: Unit, destination: Unit) {
        switch category {
        case .length: (.meter, .foot)
        case .area: (.squareMeter, .squareFoot)
        case .volume: (.liter, .gallon)
        case .mass: (.kilogram, .pound)
        case .temperature: (.celsius, .fahrenheit)
        case .speed: (.kilometersPerHour, .milesPerHour)
        case .time: (.hour, .minute)
        case .data: (.megabyte, .gigabyte)
        case .angle: (.degree, .radian)
        case .pressure: (.bar, .psi)
        }
    }
}
