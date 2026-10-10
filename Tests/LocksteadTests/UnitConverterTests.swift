import XCTest
@testable import Lockstead

final class UnitConverterTests: XCTestCase {
    func testConvertsMetersAndFeetInBothDirections() {
        XCTAssertEqual(UnitConverter.convert(1, from: .meter, to: .foot)!, 3.280839895013123, accuracy: 0.000_000_001)
        XCTAssertEqual(UnitConverter.convert(3.280839895013123, from: .foot, to: .meter)!, 1, accuracy: 0.000_000_001)
    }

    func testConvertsTemperatureWithDirectFormulas() {
        XCTAssertEqual(UnitConverter.convert(0, from: .celsius, to: .fahrenheit)!, 32, accuracy: 0.000_000_001)
        XCTAssertEqual(UnitConverter.convert(32, from: .fahrenheit, to: .celsius)!, 0, accuracy: 0.000_000_001)
        XCTAssertEqual(UnitConverter.convert(-40, from: .celsius, to: .fahrenheit)!, -40, accuracy: 0.000_000_001)
        XCTAssertEqual(UnitConverter.convert(100, from: .celsius, to: .kelvin)!, 373.15, accuracy: 0.000_000_001)
        XCTAssertEqual(UnitConverter.convert(273.15, from: .kelvin, to: .celsius)!, 0, accuracy: 0.000_000_001)
    }

    func testUsesBinaryDataSizes() {
        XCTAssertEqual(UnitConverter.convert(1024, from: .kilobyte, to: .megabyte)!, 1, accuracy: 0.000_000_001)
        XCTAssertEqual(UnitConverter.convert(1, from: .megabyte, to: .kilobyte)!, 1024, accuracy: 0.000_000_001)
    }

    func testRejectsCrossCategoryConversions() {
        XCTAssertNil(UnitConverter.convert(1, from: .meter, to: .second))
    }

    func testConvertsNegativeValues() {
        XCTAssertEqual(UnitConverter.convert(-10, from: .celsius, to: .fahrenheit)!, 14, accuracy: 0.000_000_001)
    }

    func testFormatterLimitsPrecisionAndTrimsTrailingZeros() {
        XCTAssertEqual(UnitConverter.formatted(12.34000000), "12.34")
        XCTAssertEqual(UnitConverter.formatted(1.234567891), "1.23456789")
        XCTAssertEqual(UnitConverter.formatted(-0.0), "0")
    }

    func testFormatterUsesScientificNotationForVeryLargeAndSmallValues() {
        XCTAssertEqual(UnitConverter.formatted(1_000_000_000), "1e9")
        XCTAssertEqual(UnitConverter.formatted(0.0000001), "1e-7")
        XCTAssertEqual(UnitConverter.formatted(-0.0000001), "-1e-7")
    }
}
