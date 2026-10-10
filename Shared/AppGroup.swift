import Foundation
import os

enum AppGroup {
    static let suiteName = "group.zeronet.lockstead"
    static let stateKey = "locker.state.v1"
    static let stateBackupKey = "locker.state.v1.bak"
    static let timedStateKey = "locker.timed.v1"          // 旧版合键,读取迁移后删除
    static let temporaryUnlockKey = "locker.tempunlock.v1" // 临时解锁截止,独立键
    static let temporarySessionKey = "locker.tempSession.v2"
    static let timedMigrationKey = "locker.timedMigrated.v2"
    static let guestModeKey = "locker.guestmode.v1"        // 访客模式截止,独立键
    static let themeKey = "xl.theme.v1"

    private static let logger = Logger(subsystem: "zeronet.lockstead", category: "AppGroup")

    /// App Group 是否真的解析成功。失败时 UI 面(盾牌配置扩展)降级标准域继续渲染,
    /// 执行面(RestrictionsPlan)则 fail-closed 全量盾牌——绝不静默放行一切。
    static let isSuiteAvailable: Bool = UserDefaults(suiteName: suiteName) != nil

    /// App Group 未配置时降级标准域并记日志,而不是 fatalError 崩溃:
    /// 盾牌配置扩展进程里崩溃只会表现为无声的渲染失败,且没有主 App 的日志可查。
    /// 真正的兜底在 RestrictionsPlan.make:套件不可用时返回全量盾牌计划(fail-closed)。
    static let defaults: UserDefaults = {
        guard let d = UserDefaults(suiteName: suiteName) else {
            logger.error("App Group \(suiteName, privacy: .public) 未配置——检查 entitlements,降级使用标准域")
            assertionFailure("App Group \(suiteName) 未配置——检查 entitlements")
            return .standard
        }
        return d
    }()
}
