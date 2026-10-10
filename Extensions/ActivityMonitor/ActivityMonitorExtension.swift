import Foundation
import DeviceActivity

class ActivityMonitorExtension: DeviceActivityMonitor {
    override func intervalDidStart(for activity: DeviceActivityName) {
        super.intervalDidStart(for: activity)
        guard DeviceActivityLockScheduler.isScheduleActivity(activity) else { return }
        // 时间窗开始:重算计划 → 上锁
        PlanEnforcer.reapply(store: AppGroupStore(),
                             restrictions: ManagedSettingsRestrictions(),
                             now: Date())
    }

    override func intervalDidEnd(for activity: DeviceActivityName) {
        super.intervalDidEnd(for: activity)
        if DeviceActivityLockScheduler.isScheduleActivity(activity) {
            PlanEnforcer.reapply(store: AppGroupStore(),
                                 restrictions: ManagedSettingsRestrictions(), now: Date())
            return
        }
        switch activity {
        case DeviceActivityUnlockScheduler.activityName:
            // 临时解锁到期:只清已过期的那次解锁,并重锁
            TemporaryUnlockEnforcer.relockExpired(store: AppGroupStore(),
                                                  restrictions: ManagedSettingsRestrictions(),
                                                  now: Date())
        case DeviceActivityGuestScheduler.activityName:
            // 访客时限到:只结束已过期的会话,后台恢复原有阻止策略
            GuestModeEnforcer.endExpired(store: AppGroupStore(),
                                         restrictions: ManagedSettingsRestrictions(),
                                         now: Date())
        default:
            break
        }
    }
}
