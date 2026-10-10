import XCTest
@testable import Lockstead

final class ThemeTests: XCTestCase {
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: "unit-test-theme-\(UUID().uuidString)")!
    }

    func testDefaultThemeIsSecondCatalogTheme() {
        XCTAssertEqual(XLThemeID.current(from: defaults), .teal)
    }

    func testPersistRoundTrip() {
        XLThemeID.plum.persist(to: defaults)
        XCTAssertEqual(XLThemeID.current(from: defaults), .plum)
    }

    func testDirtyValueFallsBack() {
        defaults.set("neon-pink", forKey: AppGroup.themeKey)
        XCTAssertEqual(XLThemeID.current(from: defaults), .teal)
    }

    func testFreeTiers() {
        XCTAssertTrue(XLThemeID.guardGreen.isFree)
        XCTAssertTrue(XLThemeID.teal.isFree)
        for t in [XLThemeID.indigo, .amber, .plum, .coral] {
            XCTAssertFalse(t.isFree)
        }
    }

    func testPolicyMatrix() {
        for t in XLThemeID.allCases {
            XCTAssertTrue(ThemePolicy.canUse(t, isVIP: true))
            XCTAssertEqual(ThemePolicy.canUse(t, isVIP: false), t.isFree)
        }
    }

    func testCatalogCoversAllThemesAndRoles() {
        for theme in XLThemeID.allCases {
            for role in XLColorRole.allCases {
                _ = XLThemeCatalog.uiColor(role, theme: theme) // 不崩溃、有值
            }
        }
    }

    func testSwatchesAreDistinct() {
        let swatches = XLThemeID.allCases.map {
            XLThemeCatalog.swatch(for: $0).cgColor.components ?? []
        }
        XCTAssertEqual(Set(swatches.map { "\($0)" }).count, XLThemeID.allCases.count)
    }

    func testReadableContentWidthKeepsPhonesNaturalAndCapsWideScreens() {
        XCTAssertEqual(XLLayout.readableContentWidth(availableWidth: 390), 390)
        XCTAssertEqual(XLLayout.readableContentWidth(availableWidth: 1_024), 720)
    }
}
