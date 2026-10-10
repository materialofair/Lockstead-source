import Foundation

/// 主题标识。rawValue 持久化于 App Group(独立键,不进 LockerState)。
enum XLThemeID: String, CaseIterable {
    case guardGreen, teal, indigo, amber, plum, coral

    /// 免费档:守护绿 + 青碧;其余 VIP。
    var isFree: Bool {
        switch self {
        case .guardGreen, .teal: true
        default: false
        }
    }

    static func current(from defaults: UserDefaults = AppGroup.defaults) -> XLThemeID {
        guard let raw = defaults.string(forKey: AppGroup.themeKey),
              let theme = XLThemeID(rawValue: raw)
        else { return .teal }
        return theme
    }

    func persist(to defaults: UserDefaults = AppGroup.defaults) {
        defaults.set(rawValue, forKey: AppGroup.themeKey)
    }
}
