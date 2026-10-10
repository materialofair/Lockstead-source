import Foundation

extension UnitCategory {
    var localizationKey: String { "calculator.converter.category.\(rawValue)" }
}

extension Unit {
    var localizationKey: String { "calculator.converter.unit.\(rawValue)" }

    var symbol: String {
        switch self {
        case .millimeter: "mm"; case .centimeter: "cm"; case .meter: "m"; case .kilometer: "km"; case .inch: "in"; case .foot: "ft"; case .yard: "yd"; case .mile: "mi"
        case .squareMillimeter: "mm²"; case .squareCentimeter: "cm²"; case .squareMeter: "m²"; case .hectare: "ha"; case .squareKilometer: "km²"; case .squareInch: "in²"; case .squareFoot: "ft²"; case .acre: "ac"
        case .milliliter: "mL"; case .liter: "L"; case .cubicMeter: "m³"; case .teaspoon: "tsp"; case .tablespoon: "tbsp"; case .cup: "cup"; case .pint: "pt"; case .gallon: "gal"
        case .milligram: "mg"; case .gram: "g"; case .kilogram: "kg"; case .ton: "t"; case .ounce: "oz"; case .pound: "lb"
        case .celsius: "°C"; case .fahrenheit: "°F"; case .kelvin: "K"
        case .metersPerSecond: "m/s"; case .kilometersPerHour: "km/h"; case .milesPerHour: "mph"; case .knot: "kn"
        case .millisecond: "ms"; case .second: "s"; case .minute: "min"; case .hour: "h"; case .day: "d"; case .week: "wk"
        case .byte: "B"; case .kilobyte: "KB"; case .megabyte: "MB"; case .gigabyte: "GB"; case .terabyte: "TB"
        case .degree: "°"; case .radian: "rad"; case .gradian: "gon"
        case .pascal: "Pa"; case .kilopascal: "kPa"; case .megapascal: "MPa"; case .bar: "bar"; case .psi: "psi"; case .atmosphere: "atm"
        }
    }
}
