import Foundation

enum UnitCategory: String, CaseIterable, Codable {
    case length
    case area
    case volume
    case mass
    case temperature
    case speed
    case time
    case data
    case angle
    case pressure

    var units: [Unit] {
        Unit.allCases.filter { $0.category == self }
    }
}

enum Unit: String, CaseIterable, Codable {
    case millimeter, centimeter, meter, kilometer, inch, foot, yard, mile
    case squareMillimeter, squareCentimeter, squareMeter, hectare, squareKilometer, squareInch, squareFoot, acre
    case milliliter, liter, cubicMeter, teaspoon, tablespoon, cup, pint, gallon
    case milligram, gram, kilogram, ton, ounce, pound
    case celsius, fahrenheit, kelvin
    case metersPerSecond, kilometersPerHour, milesPerHour, knot
    case millisecond, second, minute, hour, day, week
    case byte, kilobyte, megabyte, gigabyte, terabyte
    case degree, radian, gradian
    case pascal, kilopascal, megapascal, bar, psi, atmosphere

    var category: UnitCategory {
        switch self {
        case .millimeter, .centimeter, .meter, .kilometer, .inch, .foot, .yard, .mile:
            .length
        case .squareMillimeter, .squareCentimeter, .squareMeter, .hectare, .squareKilometer, .squareInch, .squareFoot, .acre:
            .area
        case .milliliter, .liter, .cubicMeter, .teaspoon, .tablespoon, .cup, .pint, .gallon:
            .volume
        case .milligram, .gram, .kilogram, .ton, .ounce, .pound:
            .mass
        case .celsius, .fahrenheit, .kelvin:
            .temperature
        case .metersPerSecond, .kilometersPerHour, .milesPerHour, .knot:
            .speed
        case .millisecond, .second, .minute, .hour, .day, .week:
            .time
        case .byte, .kilobyte, .megabyte, .gigabyte, .terabyte:
            .data
        case .degree, .radian, .gradian:
            .angle
        case .pascal, .kilopascal, .megapascal, .bar, .psi, .atmosphere:
            .pressure
        }
    }
}

enum UnitConverter {
    static func convert(_ value: Double, from source: Unit, to destination: Unit) -> Double? {
        guard source.category == destination.category else { return nil }

        if source.category == .temperature {
            return convertTemperature(value, from: source, to: destination)
        }

        guard let sourceFactor = factorToBase(for: source), let destinationFactor = factorToBase(for: destination) else {
            return nil
        }
        return value * sourceFactor / destinationFactor
    }

    static func formatted(_ value: Double) -> String {
        if value.isNaN { return "NaN" }
        if value == .infinity { return "∞" }
        if value == -.infinity { return "-∞" }
        if value == 0 { return "0" }

        let magnitude = abs(value)
        if magnitude >= 1_000_000_000 || magnitude < 0.000_001 {
            let scientific = String(format: "%.8e", locale: Locale(identifier: "en_US_POSIX"), value)
            if let exponentMarker = scientific.firstIndex(where: { $0 == "e" || $0 == "E" }),
               let exponent = Int(scientific[scientific.index(after: exponentMarker)...]) {
                let mantissa = trimTrailingZeros(String(scientific[..<exponentMarker]))
                return "\(mantissa)e\(exponent)"
            }
            return scientific
        }

        return trimTrailingZeros(String(format: "%.8f", locale: Locale(identifier: "en_US_POSIX"), value))
    }

    static func format(_ value: Double) -> String {
        formatted(value)
    }

    private static func convertTemperature(_ value: Double, from source: Unit, to destination: Unit) -> Double? {
        guard source.category == .temperature, destination.category == .temperature else { return nil }
        if source == destination { return value }

        switch (source, destination) {
        case (.celsius, .fahrenheit): return value * 9 / 5 + 32
        case (.celsius, .kelvin): return value + 273.15
        case (.fahrenheit, .celsius): return (value - 32) * 5 / 9
        case (.fahrenheit, .kelvin): return (value - 32) * 5 / 9 + 273.15
        case (.kelvin, .celsius): return value - 273.15
        case (.kelvin, .fahrenheit): return (value - 273.15) * 9 / 5 + 32
        default: return value
        }
    }

    private static func factorToBase(for unit: Unit) -> Double? {
        switch unit {
        case .millimeter: return 0.001
        case .centimeter: return 0.01
        case .meter: return 1
        case .kilometer: return 1_000
        case .inch: return 0.0254
        case .foot: return 0.3048
        case .yard: return 0.9144
        case .mile: return 1_609.344

        case .squareMillimeter: return 0.000_001
        case .squareCentimeter: return 0.0001
        case .squareMeter: return 1
        case .hectare: return 10_000
        case .squareKilometer: return 1_000_000
        case .squareInch: return 0.00064516
        case .squareFoot: return 0.09290304
        case .acre: return 4_046.8564224

        case .milliliter: return 0.001
        case .liter: return 1
        case .cubicMeter: return 1_000
        case .teaspoon: return 0.00492892159375
        case .tablespoon: return 0.01478676478125
        case .cup: return 0.2365882365
        case .pint: return 0.473176473
        case .gallon: return 3.785411784

        case .milligram: return 0.000001
        case .gram: return 0.001
        case .kilogram: return 1
        case .ton: return 1_000
        case .ounce: return 0.028349523125
        case .pound: return 0.45359237

        case .metersPerSecond: return 1
        case .kilometersPerHour: return 1 / 3.6
        case .milesPerHour: return 0.44704
        case .knot: return 0.5144444444444445

        case .millisecond: return 0.001
        case .second: return 1
        case .minute: return 60
        case .hour: return 3_600
        case .day: return 86_400
        case .week: return 604_800

        case .byte: return 1
        case .kilobyte: return 1_024
        case .megabyte: return 1_048_576
        case .gigabyte: return 1_073_741_824
        case .terabyte: return 1_099_511_627_776

        case .degree: return 1
        case .radian: return 180 / .pi
        case .gradian: return 0.9

        case .pascal: return 1
        case .kilopascal: return 1_000
        case .megapascal: return 1_000_000
        case .bar: return 100_000
        case .psi: return 6_894.757293168
        case .atmosphere: return 101_325

        case .celsius, .fahrenheit, .kelvin:
            return nil
        }
    }

    private static func trimTrailingZeros(_ text: String) -> String {
        guard text.contains(".") else { return text }
        return text
            .replacingOccurrences(of: "0+$", with: "", options: .regularExpression)
            .replacingOccurrences(of: "\\.$", with: "", options: .regularExpression)
    }
}

/// Presentation only: keep calculation, PIN input and copied values in their canonical POSIX form.
enum CalculatorNumberDisplay {
    static func text(_ canonical: String, locale: Locale = .current) -> String {
        canonical.replacingOccurrences(of: ".", with: locale.decimalSeparator ?? ".")
    }
}
