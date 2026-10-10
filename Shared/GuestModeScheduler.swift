import Foundation
import DeviceActivity

protocol GuestModeScheduling {
    @discardableResult func scheduleRestore(until: Date) -> Bool
    func cancelRestore()
}

/// 访客模式的定时恢复。访客模式必须限时:即使主 App 被 .all(except:) 一并盾住,
/// ActivityMonitor 扩展也会在到点时于后台恢复原状——不存在永久锁死路径。
struct DeviceActivityGuestScheduler: GuestModeScheduling {
    static let activityName = DeviceActivityName("lockstead.guestMode")

    @discardableResult
    func scheduleRestore(until: Date) -> Bool {
        let center = DeviceActivityCenter()
        center.stopMonitoring([Self.activityName])
        let units: Set<Calendar.Component> = [.year, .month, .day, .hour, .minute, .second]
        // 60s 冗余同临时解锁:防止秒级截断让区间短于 15 分钟下限而抛错
        let paddedEnd = until.addingTimeInterval(60)
        let schedule = DeviceActivitySchedule(
            intervalStart: Calendar.current.dateComponents(units, from: Date()),
            intervalEnd: Calendar.current.dateComponents(units, from: paddedEnd),
            repeats: false
        )
        do {
            try center.startMonitoring(Self.activityName, during: schedule)
            return true
        } catch {
            // 调度失败 = 无法保证自动恢复 → 立即终止访客模式,绝不进入无守护的限时状态
            GuestModeEnforcer.end(store: AppGroupStore(),
                                  restrictions: ManagedSettingsRestrictions(),
                                  now: Date())
            return false
        }
    }

    func cancelRestore() {
        DeviceActivityCenter().stopMonitoring([Self.activityName])
    }
}

enum GuestModeEnforcer {
    /// 无条件结束访客模式(调度失败兜底:刚写入的截止时间必须同步撤销)
    static func end(store: AppGroupStore, restrictions: RestrictionsApplying, now: Date) {
        clear(store: store, restrictions: restrictions, now: now, onlyIfExpired: false)
    }

    /// 定时到点:只结束已过期的访客模式,不误杀用户刚开启的新会话
    static func endExpired(store: AppGroupStore, restrictions: RestrictionsApplying, now: Date) {
        clear(store: store, restrictions: restrictions, now: now, onlyIfExpired: true)
    }

    /// 结束访客模式:清除截止时间并按当前时刻重算计划
    private static func clear(store: AppGroupStore, restrictions: RestrictionsApplying,
                              now: Date, onlyIfExpired: Bool) {
        let timed = store.loadTimed()
        if onlyIfExpired, let until = timed.guestModeUntil, until > now { return }
        store.saveGuestModeUntil(nil)
        restrictions.apply(RestrictionsPlan.make(from: store.load(), now: now))
    }
}
