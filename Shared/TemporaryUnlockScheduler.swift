import Foundation
import DeviceActivity

protocol UnlockScheduling {
    @discardableResult func scheduleRelock(until: Date) -> Bool
    func cancelRelock()
}

struct DeviceActivityUnlockScheduler: UnlockScheduling {
    static let activityName = DeviceActivityName("lockstead.temporaryUnlock")

    @discardableResult
    func scheduleRelock(until: Date) -> Bool {
        let center = DeviceActivityCenter()
        center.stopMonitoring([Self.activityName])
        let units: Set<Calendar.Component> = [.year, .month, .day, .hour, .minute, .second]
        // 加 60s 冗余:until 由调用方以秒计算(now()+900),此处再取 Date() 会截断到秒,
        // 导致区间可能 <15 分钟(DeviceActivity 的最小监控时长),触发 startMonitoring 抛错并立即兜底重锁。
        // temporaryUnlockUntil 才是权威时间源,晚到 60s 内relock 是可接受的;绝不能立即relock。
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
            // 调度失败时兜底:不留下"永久解锁"——立即恢复锁定
            TemporaryUnlockEnforcer.relock(store: AppGroupStore(),
                                           restrictions: ManagedSettingsRestrictions(),
                                           now: Date())
            return false
        }
    }

    func cancelRelock() {
        DeviceActivityCenter().stopMonitoring([Self.activityName])
    }
}

enum TemporaryUnlockEnforcer {
    /// 无条件清除临时解锁(调度失败兜底:刚写入的截止时间必须同步撤销)
    static func relock(store: AppGroupStore, restrictions: RestrictionsApplying, now: Date) {
        clear(store: store, restrictions: restrictions, now: now, onlyIfExpired: false)
    }

    /// 定时到点:只清除已过期的解锁,不误杀用户刚开启的新一次解锁(新解锁有自己的监控)
    static func relockExpired(store: AppGroupStore, restrictions: RestrictionsApplying, now: Date) {
        clear(store: store, restrictions: restrictions, now: now, onlyIfExpired: true)
    }

    private static func clear(store: AppGroupStore, restrictions: RestrictionsApplying,
                              now: Date, onlyIfExpired: Bool) {
        let timed = store.loadTimed()
        if onlyIfExpired, let until = timed.temporaryUnlockUntil, until > now { return }
        store.saveTemporaryUnlockUntil(nil)
        restrictions.apply(RestrictionsPlan.make(from: store.load(), now: now))
    }
}
