import Foundation

struct ScheduleRule: Codable, Equatable, Identifiable {
    var id = UUID()
    var weekdays: Set<Int> = Set(1...7)
    var startMinutes: Int
    var endMinutes: Int
}

/// 时间表窗口的纯逻辑:分钟制(0-1439),支持跨夜(如 21:00–07:00)。
/// 时间判断必须是纯函数——DeviceActivity 的边界回调有分钟级抖动,
/// 真正的权威判断永远是「用当前时刻重算 RestrictionsPlan」。
enum LockSchedule {
    static let minimumWindowMinutes = 15 // DeviceActivity 的最小监控时长
    static let minutesPerDay = 24 * 60

    /// now 是否落在 [start, end) 窗口内;end < start 视为跨夜窗口
    static func isActive(startMinutes: Int, endMinutes: Int, now: Date,
                         calendar: Calendar = .current) -> Bool {
        guard isValidWindow(startMinutes: startMinutes, endMinutes: endMinutes) else { return false }
        let comps = calendar.dateComponents([.hour, .minute], from: now)
        let m = (comps.hour ?? 0) * 60 + (comps.minute ?? 0)
        if startMinutes < endMinutes {
            return m >= startMinutes && m < endMinutes
        }
        return m >= startMinutes || m < endMinutes // 跨夜
    }

    /// 窗口时长(考虑跨夜)
    static func windowLength(startMinutes: Int, endMinutes: Int) -> Int {
        let diff = endMinutes - startMinutes
        return diff > 0 ? diff : diff + minutesPerDay
    }

    static func isValidWindow(startMinutes: Int, endMinutes: Int) -> Bool {
        guard (0..<minutesPerDay).contains(startMinutes),
              (0..<minutesPerDay).contains(endMinutes),
              startMinutes != endMinutes else { return false }
        return windowLength(startMinutes: startMinutes, endMinutes: endMinutes) >= minimumWindowMinutes
    }

    static let maximumRules = 6

    static func isValid(rule: ScheduleRule) -> Bool {
        !rule.weekdays.isEmpty && rule.weekdays.isSubset(of: Set(1...7))
            && isValidWindow(startMinutes: rule.startMinutes, endMinutes: rule.endMinutes)
    }

    static func isValid(rules: [ScheduleRule]) -> Bool {
        !rules.isEmpty && rules.count <= maximumRules
            && Set(rules.map(\.id)).count == rules.count && rules.allSatisfy { isValid(rule: $0) }
    }

    static func isActive(rules: [ScheduleRule], skippedDay: Date? = nil, now: Date,
                         calendar: Calendar = .current) -> Bool {
        if let skippedDay, calendar.isDate(skippedDay, inSameDayAs: now) { return false }
        let today = calendar.startOfDay(for: now)
        return [-1, 0].contains { offset in
            guard let day = calendar.date(byAdding: .day, value: offset, to: today) else { return false }
            return rules.contains { rule in
                guard let interval = interval(rule: rule, startingOn: day, calendar: calendar) else { return false }
                return now >= interval.start && now < interval.end
            }
        }
    }

    /// Reports a change in the union, so an overlapping rule's boundary is not a false transition.
    static func nextTransition(rules: [ScheduleRule], skippedDay: Date? = nil, after: Date,
                               calendar: Calendar = .current) -> Date? {
        boundaries(rules: rules, after: after, calendar: calendar).first { boundary in
            isActive(rules: rules, skippedDay: skippedDay, now: boundary.addingTimeInterval(-0.001), calendar: calendar)
                != isActive(rules: rules, skippedDay: skippedDay, now: boundary, calendar: calendar)
        }
    }

    static func nextStart(rules: [ScheduleRule], skippedDay: Date? = nil, after: Date,
                          calendar: Calendar = .current) -> Date? {
        boundaries(rules: rules, after: after, calendar: calendar).first { boundary in
            !isActive(rules: rules, skippedDay: skippedDay, now: boundary.addingTimeInterval(-0.001), calendar: calendar)
                && isActive(rules: rules, skippedDay: skippedDay, now: boundary, calendar: calendar)
        }
    }

    private static func boundaries(rules: [ScheduleRule], after: Date, calendar: Calendar) -> [Date] {
        let today = calendar.startOfDay(for: after)
        var dates = Set<Date>()
        // Yesterday includes overnight ends; nine days cover a skipped occurrence and the next week.
        for offset in -1...9 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: today) else { continue }
            dates.insert(day)
            for rule in rules {
                if let interval = interval(rule: rule, startingOn: day, calendar: calendar) {
                    dates.insert(interval.start)
                    dates.insert(interval.end)
                }
            }
        }
        return dates.filter { $0 > after }.sorted()
    }

    private static func interval(rule: ScheduleRule, startingOn day: Date,
                                 calendar: Calendar) -> DateInterval? {
        guard isValid(rule: rule), rule.weekdays.contains(calendar.component(.weekday, from: day)),
              let endDay = calendar.date(byAdding: .day,
                                         value: rule.endMinutes < rule.startMinutes ? 1 : 0, to: day),
              let start = time(rule.startMinutes, on: day, calendar: calendar, repeated: .first),
              let end = time(rule.endMinutes, on: endDay, calendar: calendar, repeated: .last),
              end > start else { return nil }
        return DateInterval(start: start, end: end)
    }

    // Missing DST times advance to the next valid time. Repeated hours remain one continuous window.
    private static func time(_ minutes: Int, on day: Date, calendar: Calendar,
                             repeated: Calendar.RepeatedTimePolicy) -> Date? {
        calendar.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0,
                      of: day, matchingPolicy: .nextTime, repeatedTimePolicy: repeated, direction: .forward)
    }

}
