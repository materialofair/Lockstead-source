import UIKit

/// 品牌色板:按当前主题(App Group 键)查表解析。
/// 主 App 与扩展共用;扩展每次渲染时重新读键,天然跟随主题。
enum XLPalette {
    static var bg: UIColor { c(.bg) }
    static var surface: UIColor { c(.surface) }
    static var surface2: UIColor { c(.surface2) }
    static var ink: UIColor { c(.ink) }
    static var muted: UIColor { c(.muted) }
    static var primary: UIColor { c(.primary) }
    static var primaryDeep: UIColor { c(.primaryDeep) }
    static var primaryTint: UIColor { c(.primaryTint) }
    static var accent: UIColor { c(.accent) }
    static var accentTint: UIColor { c(.accentTint) }
    static var danger: UIColor { c(.danger) }
    static var border: UIColor { c(.border) }
    static var onPrimary: UIColor { c(.onPrimary) }

    private static func c(_ role: XLColorRole) -> UIColor {
        XLThemeCatalog.uiColor(role, theme: XLThemeID.current())
    }
}
