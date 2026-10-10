import XCTest
@testable import Lockstead

final class LockScheduleTests: XCTestCase {
    private var calendar = Calendar(identifier: .gregorian)

    override func setUp() {
        super.setUp()
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
    }

    private func date(hour: Int, minute: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 7, day: 14,
                                           hour: hour, minute: minute))!
    }

    private func isActive(start: Int, end: Int, hour: Int, minute: Int) -> Bool {
        LockSchedule.isActive(startMinutes: start, endMinutes: end,
                              now: date(hour: hour, minute: minute), calendar: calendar)
    }

    // 普通窗口 09:00–17:00
    func testNormalWindow() {
        XCTAssertTrue(isActive(start: 540, end: 1020, hour: 9, minute: 0))    // 起点含
        XCTAssertTrue(isActive(start: 540, end: 1020, hour: 12, minute: 30))
        XCTAssertFalse(isActive(start: 540, end: 1020, hour: 17, minute: 0))  // 终点不含
        XCTAssertFalse(isActive(start: 540, end: 1020, hour: 8, minute: 59))
        XCTAssertFalse(isActive(start: 540, end: 1020, hour: 23, minute: 0))
    }

    // 跨夜窗口 21:00–07:00
    func testOvernightWindow() {
        let start = 21 * 60, end = 7 * 60
        XCTAssertTrue(isActive(start: start, end: end, hour: 21, minute: 0))
        XCTAssertTrue(isActive(start: start, end: end, hour: 23, minute: 59))
        XCTAssertTrue(isActive(start: start, end: end, hour: 0, minute: 0))
        XCTAssertTrue(isActive(start: start, end: end, hour: 6, minute: 59))
        XCTAssertFalse(isActive(start: start, end: end, hour: 7, minute: 0))
        XCTAssertFalse(isActive(start: start, end: end, hour: 12, minute: 0))
    }

    func testWindowLengthHandlesOvernight() {
        XCTAssertEqual(LockSchedule.windowLength(startMinutes: 540, endMinutes: 1020), 480)
        XCTAssertEqual(LockSchedule.windowLength(startMinutes: 21 * 60, endMinutes: 7 * 60), 600)
    }

    func testValidWindowRules() {
        XCTAssertTrue(LockSchedule.isValidWindow(startMinutes: 540, endMinutes: 555))   // 恰 15 分钟
        XCTAssertFalse(LockSchedule.isValidWindow(startMinutes: 540, endMinutes: 554))  // 14 分钟
        XCTAssertFalse(LockSchedule.isValidWindow(startMinutes: 540, endMinutes: 540))  // 零长
        XCTAssertFalse(LockSchedule.isValidWindow(startMinutes: -1, endMinutes: 100))   // 越界
        XCTAssertFalse(LockSchedule.isValidWindow(startMinutes: 0, endMinutes: 1440))   // 越界
        XCTAssertTrue(LockSchedule.isValidWindow(startMinutes: 23 * 60 + 50, endMinutes: 5)) // 跨夜 15 分钟
    }

    // 无效窗口一律视为不生效(而不是常锁),避免坏数据把设备永久锁死
    func testInvalidWindowNeverActive() {
        XCTAssertFalse(isActive(start: 540, end: 540, hour: 12, minute: 0))
    }
}
