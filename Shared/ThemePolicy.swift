enum ThemePolicy {
    static func canUse(_ theme: XLThemeID, isVIP: Bool) -> Bool {
        isVIP || theme.isFree
    }
}
