import Foundation
import Observation

/// 当前主题的可观察源。视图经 XL.* 令牌读取 → body 建立依赖 → 切换即全局重绘。
/// 刻意不标 @MainActor:令牌被 ButtonStyle 等非隔离上下文读取;写入只发生在主线程 UI。
@Observable
final class ThemeStore {
    static let shared = ThemeStore()

    var current: XLThemeID {
        didSet { current.persist() }
    }

    private init() {
        current = XLThemeID.current()
    }
}
