import Foundation
import DeviceActivity

protocol LockScheduleScheduling {
    @discardableResult func startDaily(startMinutes: Int, endMinutes: Int) -> Bool
    @discardableResult func start(rules: [ScheduleRule]) -> Bool
    func stop()
}

extension LockScheduleScheduling {
    // Keeps legacy single-window implementations usable without claiming support for extra rules.
    @discardableResult
    func start(rules: [ScheduleRule]) -> Bool {
        guard rules.count == 1, let rule = rules.first,
              rule.weekdays == Set(1...7), LockSchedule.isValid(rule: rule) else { return false }
        return startDaily(startMinutes: rule.startMinutes, endMinutes: rule.endMinutes)
    }
}

struct DeviceActivityLockScheduler: LockScheduleScheduling {
    static let activityName = DeviceActivityName("lockstead.lockSchedule")
    private static let rulePrefix = "lockstead.lockSchedule.rule."
    private static let midnightName = DeviceActivityName("lockstead.lockSchedule.midnight")

    private let startMonitoring: (DeviceActivityName, DeviceActivitySchedule) throws -> Void
    private let stopMonitoring: ([DeviceActivityName]) -> Void
    private let monitoredActivities: () -> [DeviceActivityName]

    init(startMonitoring: @escaping (DeviceActivityName, DeviceActivitySchedule) throws -> Void = {
        try DeviceActivityCenter().startMonitoring($0, during: $1)
    }, stopMonitoring: @escaping ([DeviceActivityName]) -> Void = {
        DeviceActivityCenter().stopMonitoring($0)
    }, monitoredActivities: @escaping () -> [DeviceActivityName] = {
        DeviceActivityCenter().activities
    }) {
        self.startMonitoring = startMonitoring
        self.stopMonitoring = stopMonitoring
        self.monitoredActivities = monitoredActivities
    }

    static func expectedActivityNames(rules: [ScheduleRule]) -> Set<DeviceActivityName> {
        Set(rules.map { DeviceActivityName(rulePrefix + $0.id.uuidString) } + [midnightName])
    }

    static func isScheduleActivity(_ activity: DeviceActivityName) -> Bool {
        activity == activityName || activity == midnightName || activity.rawValue.hasPrefix(rulePrefix)
    }

    @discardableResult
    func startDaily(startMinutes: Int, endMinutes: Int) -> Bool {
        start(rules: [ScheduleRule(startMinutes: startMinutes, endMinutes: endMinutes)])
    }

    @discardableResult
    func start(rules: [ScheduleRule]) -> Bool {
        guard LockSchedule.isValid(rules: rules) else { return false }
        stop()
        do {
            // At most six daily boundary monitors plus one midnight monitor. Weekday membership
            // and overlaps are evaluated from persisted rules whenever any boundary arrives.
            for rule in rules {
                try startMonitoring(DeviceActivityName(Self.rulePrefix + rule.id.uuidString),
                    DeviceActivitySchedule(
                        intervalStart: DateComponents(hour: rule.startMinutes / 60, minute: rule.startMinutes % 60),
                        intervalEnd: DateComponents(hour: rule.endMinutes / 60, minute: rule.endMinutes % 60),
                        repeats: true))
            }
            // Reevaluate skipped-day expiry even when no configured rule starts at midnight.
            try startMonitoring(Self.midnightName, DeviceActivitySchedule(
                intervalStart: DateComponents(hour: 0, minute: 0),
                intervalEnd: DateComponents(hour: 0, minute: 15), repeats: true))
            return true
        } catch {
            // Partial registration is never presented as a working schedule.
            stop()
            return false
        }
    }

    func stop() {
        let registered = monitoredActivities().filter { Self.isScheduleActivity($0) }
        stopMonitoring(Array(Set(registered + [Self.activityName, Self.midnightName])))
    }
}

/// 以当前时刻为准重算并应用限制计划——所有时间边界回调的共同出口
enum PlanEnforcer {
    static func reapply(store: AppGroupStore, restrictions: RestrictionsApplying, now: Date) {
        let state = store.load()
        restrictions.apply(RestrictionsPlan.make(from: state, now: now))
    }
}
