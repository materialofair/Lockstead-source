import SwiftUI

/// SwiftUI 层设计令牌。色值唯一来源是 Shared/XLPalette(见 DESIGN.md)。
enum XL {
    static var bg: Color { c(.bg) }
    static var surface: Color { c(.surface) }
    static var surface2: Color { c(.surface2) }
    static var ink: Color { c(.ink) }
    static var muted: Color { c(.muted) }
    static var primary: Color { c(.primary) }
    static var primaryDeep: Color { c(.primaryDeep) }
    static var primaryTint: Color { c(.primaryTint) }
    static var accent: Color { c(.accent) }
    static var accentTint: Color { c(.accentTint) }
    static var danger: Color { c(.danger) }
    static var border: Color { c(.border) }
    static var onPrimary: Color { c(.onPrimary) }

    private static func c(_ role: XLColorRole) -> Color {
        Color(XLThemeCatalog.uiColor(role, theme: ThemeStore.shared.current))
    }

    /// 间距阶:4 / 8 / 12 / 16 / 20 / 24 / 32
    enum Space {
        static let xs: CGFloat = 4
        static let s: CGFloat = 8
        static let m: CGFloat = 12
        static let l: CGFloat = 16
        static let xl: CGFloat = 20
        static let xxl: CGFloat = 24
        static let xxxl: CGFloat = 32
    }

    static let cardRadius: CGFloat = 16
    static let buttonRadius: CGFloat = 14
    static let badgeRadius: CGFloat = 8
    static let dashboardRadius: CGFloat = 20
    static let dashboardPadding: CGFloat = 18
    static let screenPadding: CGFloat = 20
    static let buttonHeight: CGFloat = 52
}

enum XLLayout {
    static let maxReadableContentWidth: CGFloat = 720

    static func readableContentWidth(availableWidth: CGFloat) -> CGFloat {
        min(availableWidth, maxReadableContentWidth)
    }
}

/// 页面骨架:统一底色 + 水平边距的滚动容器。
struct XLScreen<Content: View>: View {
    var spacing: CGFloat = XL.Space.l
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: spacing) {
                content
            }
            .padding(.horizontal, XL.screenPadding)
            .padding(.vertical, XL.Space.l)
            .frame(maxWidth: XLLayout.maxReadableContentWidth + XL.screenPadding * 2)
            .frame(maxWidth: .infinity)
        }
        .background(XL.bg)
        .scrollBounceBehavior(.basedOnSize)
    }
}
