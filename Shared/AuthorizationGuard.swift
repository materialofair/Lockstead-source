import Foundation

/// 回前台/授权变化时的校准出口。
///
/// 授权在:以当前时刻重算并重新应用计划,自愈任何残留(重新授权后的恢复、
/// 扩展进程失败留下的过期状态);时间表开着就重新挂上边界监控。
/// 授权不在(用户在系统设置里撤销了 Screen Time 授权):清空全部已下发限制、
/// 取消所有调度、清掉限时状态——绝不能在一台已撤销授权的设备上残留限制,
/// 「卸载/撤销后残留」是本品类的信任杀手(见竞品差评)。
/// 用户配置(选择、开关、PIN、时间表窗口)保留:重新授权后守护原样恢复。
enum AuthorizationGuard {
    /// - Parameter previousAuthorized: 上一次同步时的授权状态(nil = 本次启动首次同步)。
    ///   仅在首次同步或「未授权 → 已授权」翻转时重挂每日监控,避免每次回前台都
    ///   stop/start DeviceActivity(区间内重启监控会立即再触发 intervalDidStart,白白唤醒扩展进程)。
    static func foregroundSync(isAuthorized: Bool,
                               previousAuthorized: Bool?,
                               store: AppGroupStore,
                               restrictions: RestrictionsApplying,
                               unlockScheduler: UnlockScheduling,
                               lockScheduler: LockScheduleScheduling,
                               guestScheduler: GuestModeScheduling,
                               now: Date) {
        var state = store.load()
        if isAuthorized {
            restrictions.apply(RestrictionsPlan.make(from: state, now: now))
            // 撤销期间监控已被取消;时间表开着就重新挂上(重复挂载幂等,窗口 ≥15 分钟无最小时长风险)。
            // 临时解锁/访客的一次性监控刻意不在这里重挂:剩余时间可能已 <15 分钟,
            // 重挂会触发 startMonitoring 抛错并立即重锁/终止,反而误伤正常使用。
            if state.scheduleEnabled && (previousAuthorized != true || state.scheduleRegistrationFailed) {
                state.scheduleRegistrationFailed = !lockScheduler.start(rules: state.effectiveScheduleRules)
                store.save(state)
                restrictions.apply(RestrictionsPlan.make(from: state, now: now))
            }
            return
        }
        // 限时状态连同其调度一并清掉:调度已取消,留着截止时间就是一个无人监控的悬空状态
        let timed = store.loadTimed()
        if timed.temporaryUnlockUntil != nil || timed.guestModeUntil != nil {
            store.saveTimed(TimedModeState())
        }
        restrictions.clearAll()
        unlockScheduler.cancelRelock()
        lockScheduler.stop()
        guestScheduler.cancelRestore()
    }
}
