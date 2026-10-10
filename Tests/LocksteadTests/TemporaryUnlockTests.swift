import XCTest
@testable import Lockstead

final class MockRestrictions: RestrictionsApplying {
    var appliedPlans: [RestrictionsPlan] = []
    var clearAllCount = 0
    func apply(_ plan: RestrictionsPlan) { appliedPlans.append(plan) }
    func clearAll() { clearAllCount += 1 }
}

final class TemporaryUnlockTests: XCTestCase {
    func testRelockClearsTempUnlockAndAppliesPlan() {
        let defaults = UserDefaults(suiteName: "unit-test-\(UUID().uuidString)")!
        let store = AppGroupStore(defaults: defaults)
        store.saveTimed(TimedModeState(temporaryUnlockUntil: Date(timeIntervalSince1970: 1_700_000_000)))
        let mock = MockRestrictions()

        // 无条件清除:调度失败兜底路径必须撤销刚写入的截止时间
        TemporaryUnlockEnforcer.relock(store: store, restrictions: mock,
                                       now: Date(timeIntervalSince1970: 1_700_000_100))

        XCTAssertNil(store.load().temporaryUnlockUntil)
        XCTAssertEqual(mock.appliedPlans.count, 1)
    }

    // 定时到点只清已过期的解锁:用户刚开启的新解锁(未来截止)不被旧调度的到点回调误杀
    func testRelockExpiredKeepsNewerUnlock() {
        let defaults = UserDefaults(suiteName: "unit-test-\(UUID().uuidString)")!
        let store = AppGroupStore(defaults: defaults)
        let newerUnlock = Date(timeIntervalSince1970: 1_700_000_900)
        store.saveTimed(TimedModeState(temporaryUnlockUntil: newerUnlock))
        let mock = MockRestrictions()

        TemporaryUnlockEnforcer.relockExpired(store: store, restrictions: mock,
                                              now: Date(timeIntervalSince1970: 1_700_000_100))

        XCTAssertEqual(store.load().temporaryUnlockUntil, newerUnlock)
        XCTAssertTrue(mock.appliedPlans.isEmpty)
    }

    func testRelockExpiredClearsPastUnlock() {
        let defaults = UserDefaults(suiteName: "unit-test-\(UUID().uuidString)")!
        let store = AppGroupStore(defaults: defaults)
        store.saveTimed(TimedModeState(temporaryUnlockUntil: Date(timeIntervalSince1970: 1_700_000_000)))
        let mock = MockRestrictions()

        TemporaryUnlockEnforcer.relockExpired(store: store, restrictions: mock,
                                              now: Date(timeIntervalSince1970: 1_700_000_100))

        XCTAssertNil(store.load().temporaryUnlockUntil)
        XCTAssertEqual(mock.appliedPlans.count, 1)
    }

    // 访客模式到点/调度失败的共同出口:清截止时间 + 按当前时刻重算计划
    func testGuestModeEndClearsUntilAndAppliesPlan() {
        let defaults = UserDefaults(suiteName: "unit-test-\(UUID().uuidString)")!
        let store = AppGroupStore(defaults: defaults)
        store.saveTimed(TimedModeState(guestModeUntil: Date(timeIntervalSince1970: 1_700_000_000)))
        let mock = MockRestrictions()

        GuestModeEnforcer.end(store: store, restrictions: mock,
                              now: Date(timeIntervalSince1970: 1_700_000_100))

        XCTAssertNil(store.load().guestModeUntil)
        XCTAssertEqual(mock.appliedPlans.count, 1)
    }

    func testGuestModeEndExpiredKeepsNewerSession() {
        let defaults = UserDefaults(suiteName: "unit-test-\(UUID().uuidString)")!
        let store = AppGroupStore(defaults: defaults)
        let newerSession = Date(timeIntervalSince1970: 1_700_000_900)
        store.saveTimed(TimedModeState(guestModeUntil: newerSession))
        let mock = MockRestrictions()

        GuestModeEnforcer.endExpired(store: store, restrictions: mock,
                                     now: Date(timeIntervalSince1970: 1_700_000_100))

        XCTAssertEqual(store.load().guestModeUntil, newerSession)
        XCTAssertTrue(mock.appliedPlans.isEmpty)
    }

    // 分区后,限时状态与主状态互不波及:清理临时解锁不得碰掉主档配置
    func testTimedClearDoesNotTouchMainState() {
        let defaults = UserDefaults(suiteName: "unit-test-\(UUID().uuidString)")!
        let store = AppGroupStore(defaults: defaults)
        var state = LockerState()
        state.isLockEnabled = true
        state.scheduleEnabled = true
        store.save(state)
        store.saveTimed(TimedModeState(temporaryUnlockUntil: Date(timeIntervalSince1970: 1_700_000_000),
                                       guestModeUntil: Date(timeIntervalSince1970: 1_700_000_000)))
        let mock = MockRestrictions()

        TemporaryUnlockEnforcer.relock(store: store, restrictions: mock,
                                       now: Date(timeIntervalSince1970: 1_700_000_100))

        let after = store.load()
        XCTAssertTrue(after.isLockEnabled)
        XCTAssertTrue(after.scheduleEnabled)
        XCTAssertNil(after.temporaryUnlockUntil)
    }
}
