import XCTest
@testable import Lockstead

final class UnitConversionStateTests: XCTestCase {
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: "unit-conversion-state-\(UUID().uuidString)")!
    }

    func testChangingCategoryClearsInputAndResetsCompatibleUnits() {
        var state = UnitConversionState(defaults: defaults)
        state.append(digit: 1)
        state.select(category: .temperature)

        XCTAssertEqual(state.category, .temperature)
        XCTAssertEqual(state.input, "")
        XCTAssertEqual(state.source.category, .temperature)
        XCTAssertEqual(state.destination.category, .temperature)
    }

    func testChangingUnitsWithinCategoryPreservesInputAndPersistsSelection() {
        var state = UnitConversionState(defaults: defaults)
        state.append(digit: 2)
        state.select(source: .kilometer)
        state.select(destination: .mile)

        XCTAssertEqual(state.input, "2")
        let restored = UnitConversionState(defaults: defaults)
        XCTAssertEqual(restored.source, .kilometer)
        XCTAssertEqual(restored.destination, .mile)
    }

    func testEachCategoryRestoresItsOwnLastUsedUnitPair() {
        var state = UnitConversionState(defaults: defaults)
        state.select(source: .kilometer)
        state.select(destination: .mile)
        state.select(category: .temperature)
        state.select(source: .kelvin)
        state.select(destination: .fahrenheit)
        state.select(category: .length)

        XCTAssertEqual(state.source, .kilometer)
        XCTAssertEqual(state.destination, .mile)
    }

    func testConverterKeypadNeverProducesPINCandidate() {
        var state = UnitConversionState(defaults: defaults)
        for digit in [1, 2, 3, 4, 5, 6] { state.append(digit: digit) }
        XCTAssertEqual(state.input, "123456")
        XCTAssertEqual(state.result, UnitConverter.formatted(123456 * 3.280839895013123))
    }

    func testSwapAndEditingOperationsUpdateOnlyConversionInput() {
        var state = UnitConversionState(defaults: defaults)
        state.append(digit: 5)
        state.appendDecimal()
        state.append(digit: 5)
        state.applyPercent()
        state.toggleSign()
        state.deleteLast()
        state.swapUnits()

        XCTAssertEqual(state.source, .foot)
        XCTAssertEqual(state.destination, .meter)
        XCTAssertFalse(state.input.isEmpty)
    }
}
