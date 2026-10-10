import XCTest
import DeviceActivity
@testable import Lockstead

final class ScheduleRulesTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return calendar
    }

    private func date(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 9, day: day, hour: hour, minute: minute))!
    }

    func testWeekdaySelectionAndHalfOpenBoundary() {
        let rule = ScheduleRule(weekdays: [2, 3, 4, 5, 6], startMinutes: 9 * 60, endMinutes: 17 * 60)
        XCTAssertTrue(LockSchedule.isActive(rules: [rule], now: date(25, 9), calendar: calendar))
        XCTAssertFalse(LockSchedule.isActive(rules: [rule], now: date(25, 17), calendar: calendar))
        XCTAssertFalse(LockSchedule.isActive(rules: [rule], now: date(26, 12), calendar: calendar))
    }

    func testOvernightBelongsToStartWeekday() {
        let rule = ScheduleRule(weekdays: [6], startMinutes: 21 * 60, endMinutes: 7 * 60)
        XCTAssertFalse(LockSchedule.isActive(rules: [rule], now: date(25, 6), calendar: calendar))
        XCTAssertTrue(LockSchedule.isActive(rules: [rule], now: date(25, 22), calendar: calendar))
        XCTAssertTrue(LockSchedule.isActive(rules: [rule], now: date(26, 6), calendar: calendar))
        XCTAssertFalse(LockSchedule.isActive(rules: [rule], now: date(26, 7), calendar: calendar))
        XCTAssertFalse(LockSchedule.isActive(rules: [rule], now: date(26, 22), calendar: calendar))
    }

    func testOverlapAndTouchingWindowsOnlyReportUnionTransition() {
        let rules = [ScheduleRule(startMinutes: 9 * 60, endMinutes: 12 * 60),
                     ScheduleRule(startMinutes: 11 * 60, endMinutes: 14 * 60),
                     ScheduleRule(startMinutes: 14 * 60, endMinutes: 17 * 60)]
        XCTAssertEqual(LockSchedule.nextTransition(rules: rules, after: date(24, 10), calendar: calendar), date(24, 17))
        XCTAssertEqual(LockSchedule.nextStart(rules: rules, after: date(24, 10), calendar: calendar), date(25, 9))
    }

    func testSkipTodaySuppressesBothOvernightPartsAndResumesAtMidnight() {
        let rule = ScheduleRule(startMinutes: 21 * 60, endMinutes: 7 * 60)
        let skipped = date(24, 12)
        XCTAssertFalse(LockSchedule.isActive(rules: [rule], skippedDay: skipped, now: date(24, 6), calendar: calendar))
        XCTAssertFalse(LockSchedule.isActive(rules: [rule], skippedDay: skipped, now: date(24, 22), calendar: calendar))
        XCTAssertEqual(LockSchedule.nextTransition(rules: [rule], skippedDay: skipped,
                                                    after: date(24, 22), calendar: calendar), date(25, 0))
        XCTAssertTrue(LockSchedule.isActive(rules: [rule], skippedDay: skipped, now: date(25, 0), calendar: calendar))
    }

    func testSkipStartsAtMidnightAndNextWeeklyOccurrenceIsFound() {
        let overnight = ScheduleRule(startMinutes: 21 * 60, endMinutes: 7 * 60)
        XCTAssertEqual(LockSchedule.nextTransition(rules: [overnight], skippedDay: date(25, 12),
                                                    after: date(24, 22), calendar: calendar), date(25, 0))
        let friday = ScheduleRule(weekdays: [6], startMinutes: 9 * 60, endMinutes: 10 * 60)
        let expected = calendar.date(byAdding: .day, value: 7, to: date(25, 9))!
        XCTAssertEqual(LockSchedule.nextStart(rules: [friday], skippedDay: date(25, 12),
                                               after: date(24, 12), calendar: calendar), expected)
    }

    func testValidationRejectsMalformedAndExcessRules() {
        XCTAssertFalse(LockSchedule.isValid(rules: []))
        XCTAssertFalse(LockSchedule.isValid(rule: ScheduleRule(weekdays: [], startMinutes: 0, endMinutes: 60)))
        XCTAssertFalse(LockSchedule.isValid(rule: ScheduleRule(weekdays: [0, 8], startMinutes: 0, endMinutes: 60)))
        XCTAssertFalse(LockSchedule.isValid(rule: ScheduleRule(startMinutes: 0, endMinutes: 14)))
        XCTAssertFalse(LockSchedule.isValid(rule: ScheduleRule(startMinutes: 60, endMinutes: 60)))
        XCTAssertTrue(LockSchedule.isValid(rule: ScheduleRule(startMinutes: 1430, endMinutes: 5)))
        let rules = (0..<7).map { _ in ScheduleRule(startMinutes: 60, endMinutes: 120) }
        XCTAssertFalse(LockSchedule.isValid(rules: rules))
        XCTAssertTrue(LockSchedule.isValid(rules: Array(rules.prefix(6))))
        XCTAssertFalse(LockSchedule.isValid(rules: [rules[0], rules[0]]))
    }

    func testSpringForwardMissingTimeAdvancesToValidBoundary() {
        var calendar = self.calendar
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let before = calendar.date(from: DateComponents(year: 2026, month: 3, day: 8, hour: 1, minute: 59))!
        let start = calendar.date(from: DateComponents(year: 2026, month: 3, day: 8, hour: 3))!
        let end = calendar.date(from: DateComponents(year: 2026, month: 3, day: 8, hour: 4))!
        let rule = ScheduleRule(weekdays: [1], startMinutes: 150, endMinutes: 240)
        XCTAssertEqual(LockSchedule.nextTransition(rules: [rule], after: before, calendar: calendar), start)
        XCTAssertTrue(LockSchedule.isActive(rules: [rule], now: start, calendar: calendar))
        XCTAssertEqual(LockSchedule.nextTransition(rules: [rule], after: start, calendar: calendar), end)
    }

    func testFallBackRepeatedHourKeepsWindowContinuous() {
        var calendar = self.calendar
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let day = calendar.date(from: DateComponents(year: 2026, month: 11, day: 1))!
        let first = calendar.date(bySettingHour: 1, minute: 15, second: 0, of: day,
                                  matchingPolicy: .nextTime, repeatedTimePolicy: .first)!
        let second = calendar.date(bySettingHour: 1, minute: 15, second: 0, of: day,
                                   matchingPolicy: .nextTime, repeatedTimePolicy: .last)!
        let end = calendar.date(bySettingHour: 1, minute: 45, second: 0, of: day,
                                matchingPolicy: .nextTime, repeatedTimePolicy: .last)!
        let rule = ScheduleRule(weekdays: [1], startMinutes: 75, endMinutes: 105)
        XCTAssertTrue(LockSchedule.isActive(rules: [rule], now: first, calendar: calendar))
        XCTAssertTrue(LockSchedule.isActive(rules: [rule], now: second, calendar: calendar))
        XCTAssertEqual(LockSchedule.nextTransition(rules: [rule], after: first, calendar: calendar), end)
    }

    func testSchedulerCleansPartialRegistrationAndPreservesOtherMonitors() {
        enum TestFailure: Error { case registration }
        let unrelated = DeviceActivityName("other.feature")
        var registered: Set<DeviceActivityName> = [unrelated, DeviceActivityLockScheduler.activityName]
        var attempts = 0
        let scheduler = DeviceActivityLockScheduler(startMonitoring: { name, _ in
            attempts += 1
            if attempts == 2 { throw TestFailure.registration }
            registered.insert(name)
        }, stopMonitoring: { names in
            registered.subtract(names)
        }, monitoredActivities: { Array(registered) })
        let rules = [ScheduleRule(startMinutes: 60, endMinutes: 120),
                     ScheduleRule(startMinutes: 180, endMinutes: 240)]
        XCTAssertFalse(scheduler.start(rules: rules))
        XCTAssertEqual(attempts, 2)
        XCTAssertEqual(registered, [unrelated])
    }

    func testSchedulerRegistersExpectedRuleAndMidnightBoundaries() {
        var registered = Set<DeviceActivityName>()
        let scheduler = DeviceActivityLockScheduler(startMonitoring: { name, _ in
            registered.insert(name)
        }, stopMonitoring: { names in
            registered.subtract(names)
        }, monitoredActivities: { Array(registered) })
        let rules = (0..<6).map { _ in ScheduleRule(startMinutes: 60, endMinutes: 120) }
        XCTAssertTrue(scheduler.start(rules: rules))
        XCTAssertEqual(registered, DeviceActivityLockScheduler.expectedActivityNames(rules: rules))
        XCTAssertEqual(registered.count, 7)
        scheduler.stop()
        XCTAssertTrue(registered.isEmpty)
    }

}
