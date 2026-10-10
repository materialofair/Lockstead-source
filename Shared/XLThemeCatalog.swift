import UIKit

enum XLColorRole: CaseIterable {
    case bg, surface, surface2, ink, muted
    case primary, primaryDeep, primaryTint
    case accent, accentTint, border, danger, onPrimary
}

/// 6 主题 × 13 角色 × 双模式色表。
/// 色值由 DESIGN.md/spec 的 OKLCH 参数生成(同 L/C 换 hue,WCAG 已校验),禁止手改单值。
enum XLThemeCatalog {
    static func uiColor(_ role: XLColorRole, theme: XLThemeID) -> UIColor {
        palettes[theme]![role]!
    }

    /// 设置页色样:固定用该主题浅色 primary,不随系统深浅切换。
    static func swatch(for theme: XLThemeID) -> UIColor {
        let light = UITraitCollection(userInterfaceStyle: .light)
        return uiColor(.primary, theme: theme).resolvedColor(with: light)
    }

    private static let palettes: [XLThemeID: [XLColorRole: UIColor]] = {
        var p: [XLThemeID: [XLColorRole: UIColor]] = [:]
        for t in XLThemeID.allCases { p[t] = table(t) }
        return p
    }()

    private static func table(_ theme: XLThemeID) -> [XLColorRole: UIColor] {
        switch theme {
        case .guardGreen: return [
            .bg: dyn(0xFAFAF9, 0x12130D),
            .surface: dyn(0xFFFFFF, 0x1D1F18),
            .surface2: dyn(0xF2F3ED, 0x282A21),
            .ink: dyn(0x1A1C14, 0xEAECE6),
            .muted: dyn(0x515448, 0x9DA093),
            .primary: dyn(0x5E6B04, 0xB6C95E),
            .primaryDeep: dyn(0x434E00, 0x98A84C),
            .primaryTint: dyn(0xEAF2D0, 0x2B310E),
            .accent: dyn(0xAC731A, 0xE5AB60),
            .accentTint: dyn(0xFEEBD6, 0x3C2A13),
            .border: dyn(0xDDDFD9, 0x32342C),
            .danger: dyn(0xC22826, 0xEF6661),
            .onPrimary: dyn(0xFFFFFF, 0x12130D),
        ]
        case .teal: return [
            .bg: dyn(0xF9FAFA, 0x0C1414),
            .surface: dyn(0xFFFFFF, 0x162020),
            .surface2: dyn(0xEDF4F4, 0x202B2B),
            .ink: dyn(0x121D1D, 0xE5EDED),
            .muted: dyn(0x465656, 0x91A3A2),
            .primary: dyn(0x007677, 0x10D8D8),
            .primaryDeep: dyn(0x005758, 0x00B5B5),
            .primaryTint: dyn(0xCBF7F6, 0x003636),
            .accent: dyn(0xB66B31, 0xF0A36E),
            .accentTint: dyn(0xFFE9D9, 0x3F2717),
            .border: dyn(0xD8E0DF, 0x2B3535),
            .danger: dyn(0xC22826, 0xEF6661),
            .onPrimary: dyn(0xFFFFFF, 0x0C1414),
        ]
        case .indigo: return [
            .bg: dyn(0xF9FAFB, 0x101318),
            .surface: dyn(0xFFFFFF, 0x1B1E25),
            .surface2: dyn(0xF0F2F8, 0x252931),
            .ink: dyn(0x171B22, 0xE8EBF1),
            .muted: dyn(0x4D535E, 0x989FAB),
            .primary: dyn(0x4360A4, 0x93BBFF),
            .primaryDeep: dyn(0x2D457D, 0x7A9CE9),
            .primaryTint: dyn(0xDEEDFF, 0x202D49),
            .accent: dyn(0xA97416, 0xE2AC5E),
            .accentTint: dyn(0xFDECD5, 0x3B2A12),
            .border: dyn(0xDBDEE3, 0x2F333A),
            .danger: dyn(0xC22826, 0xEF6661),
            .onPrimary: dyn(0xFFFFFF, 0x101318),
        ]
        case .amber: return [
            .bg: dyn(0xFBFAF9, 0x16120D),
            .surface: dyn(0xFFFFFF, 0x221D17),
            .surface2: dyn(0xF6F2ED, 0x2E2820),
            .ink: dyn(0x1F1A13, 0xEEEAE5),
            .muted: dyn(0x595146, 0xA69D91),
            .primary: dyn(0x895700, 0xF0B04F),
            .primaryDeep: dyn(0x663E00, 0xCA933E),
            .primaryTint: dyn(0xFFE9CC, 0x3E2909),
            .accent: dyn(0x5D7DC8, 0x93B6FF),
            .accentTint: dyn(0xE3EFFF, 0x232D45),
            .border: dyn(0xE1DDD8, 0x37322B),
            .danger: dyn(0xC22826, 0xEF6661),
            .onPrimary: dyn(0xFFFFFF, 0x16120D),
        ]
        case .plum: return [
            .bg: dyn(0xFAFAFB, 0x141117),
            .surface: dyn(0xFFFFFF, 0x201C23),
            .surface2: dyn(0xF4F1F7, 0x2B272F),
            .ink: dyn(0x1C1920, 0xECEAF0),
            .muted: dyn(0x55505C, 0xA19BA9),
            .primary: dyn(0x735097, 0xD2A7FF),
            .primaryDeep: dyn(0x543772, 0xB08ADA),
            .primaryTint: dyn(0xF4E6FF, 0x342644),
            .accent: dyn(0x439458, 0x7FCC90),
            .accentTint: dyn(0xDFF6E2, 0x1C3422),
            .border: dyn(0xDFDDE2, 0x343139),
            .danger: dyn(0xC22826, 0xEF6661),
            .onPrimary: dyn(0xFFFFFF, 0x141117),
        ]
        case .coral: return [
            .bg: dyn(0xFBFAF9, 0x181110),
            .surface: dyn(0xFFFFFF, 0x241C1B),
            .surface2: dyn(0xF8F0F0, 0x302625),
            .ink: dyn(0x211817, 0xF0E9E8),
            .muted: dyn(0x5D4E4D, 0xAB9A98),
            .primary: dyn(0x9A4541, 0xFF9A91),
            .primaryDeep: dyn(0x742E2B, 0xDF7F78),
            .primaryTint: dyn(0xFFE2DE, 0x462220),
            .accent: dyn(0x008CBA, 0x5FC5F3),
            .accentTint: dyn(0xD8F4FF, 0x123240),
            .border: dyn(0xE3DCDB, 0x3A302F),
            .danger: dyn(0xC22826, 0xEF6661),
            .onPrimary: dyn(0xFFFFFF, 0x181110),
        ]
        }
    }

    private static func dyn(_ light: UInt32, _ dark: UInt32) -> UIColor {
        UIColor { trait in
            trait.userInterfaceStyle == .dark ? UIColor(rgb: dark) : UIColor(rgb: light)
        }
    }
}

extension UIColor {
    convenience init(rgb: UInt32) {
        self.init(
            red: CGFloat((rgb >> 16) & 0xFF) / 255,
            green: CGFloat((rgb >> 8) & 0xFF) / 255,
            blue: CGFloat(rgb & 0xFF) / 255,
            alpha: 1
        )
    }
}
