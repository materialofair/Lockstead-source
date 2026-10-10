import XCTest
@testable import Lockstead
import FamilyControls

final class RestrictionsPlanTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func state(lock: Bool = true, vip: Bool = false,
                       antiRemoval: Bool = false, tempUntil: Date? = nil,
                       selection: FamilyActivitySelection = FamilyActivitySelection()) -> LockerState {
        var s = LockerState()
        s.isLockEnabled = lock
        s.isVIP = vip
        s.isAntiRemovalEnabled = antiRemoval
        s.temporaryUnlockUntil = tempUntil
        s.selectionData = try? JSONEncoder().encode(selection)
        return s
    }

    // MARK: - 决策纯函数 makeSpec:用伪造 token 覆盖模拟器上到不了的真实分支

    private func makeSpec(selectionApps: Set<Int> = [],
                          selectionCategories: Set<Int> = [],
                          guestApps: Set<Int> = [],
                          state s: LockerState,
                          at date: Date = Date(timeIntervalSince1970: 1_700_000_000),
                          calendar: Calendar = .current) -> RestrictionsPlanSpec<Int, Int> {
        RestrictionsPlan.makeSpec(selectionApplications: selectionApps,
                                  selectionCategories: selectionCategories,
                                  guestApplications: guestApps,
                                  state: s, now: date, calendar: calendar)
    }

    func testSpecActiveBlacklistBlocksSelectedApps() {
        let spec = makeSpec(selectionApps: [1, 2], state: state(lock: true))
        XCTAssertEqual(spec.blockedApps, [1, 2])
        XCTAssertNil(spec.shieldAllExcept)
        XCTAssertNil(spec.shieldedCategories)
    }

    func testSpecLockDisabledBlocksNothing() {
        let spec = makeSpec(selectionApps: [1, 2], state: state(lock: false))
        XCTAssertNil(spec.blockedApps)
        XCTAssertNil(spec.shieldAllExcept)
    }

    func testSpecTemporaryUnlockSuppressesBlocking() {
        let s = state(lock: true, tempUntil: now.addingTimeInterval(900))
        XCTAssertNil(makeSpec(selectionApps: [1, 2], state: s).blockedApps)
        // 过期的临时解锁不再抑制
        let expired = state(lock: true, tempUntil: now.addingTimeInterval(-1))
        XCTAssertEqual(makeSpec(selectionApps: [1, 2], state: expired).blockedApps, [1, 2])
    }

    func testSpecAllowlistShieldsAllExceptSelected() {
        var s = state(lock: true, vip: true)
        s.lockMode = .allowlist
        let spec = makeSpec(selectionApps: [1, 2], state: s)
        XCTAssertEqual(spec.shieldAllExcept, [1, 2])
        XCTAssertNil(spec.blockedApps)
        XCTAssertNil(spec.shieldedCategories)
    }

    func testSpecAllowlistEmptySelectionDoesNotLockWholeDevice() {
        var s = state(lock: true, vip: true)
        s.lockMode = .allowlist
        let spec = makeSpec(selectionApps: [], state: s)
        XCTAssertNil(spec.shieldAllExcept) // 空选择不锁全机
        XCTAssertNil(spec.blockedApps)
    }

    func testSpecCategoryShieldingRequiresVIP() {
        let vipSpec = makeSpec(selectionCategories: [5, 6], state: state(lock: true, vip: true))
        XCTAssertEqual(vipSpec.shieldedCategories, [5, 6])
        XCTAssertNil(vipSpec.blockedApps) // 没有具体 App,黑名单为空
        let freeSpec = makeSpec(selectionCategories: [5, 6], state: state(lock: true, vip: false))
        XCTAssertNil(freeSpec.shieldedCategories)
    }

    func testSpecGuestModeWinsOverActiveLock() {
        var s = state(lock: true, vip: true)
        s.guestModeUntil = now.addingTimeInterval(1800)
        let spec = makeSpec(selectionApps: [1, 2], selectionCategories: [9], guestApps: [3], state: s)
        XCTAssertEqual(spec.shieldAllExcept, [3]) // 只放行访客白名单
        XCTAssertNil(spec.blockedApps)
        XCTAssertNil(spec.shieldedCategories)
    }

    func testSpecGuestModeRequiresNonEmptyAllowlist() {
        var s = state(lock: true)
        s.guestModeUntil = now.addingTimeInterval(1800)
        let spec = makeSpec(selectionApps: [1, 2], guestApps: [], state: s)
        XCTAssertNil(spec.shieldAllExcept) // 白名单为空:访客模式不生效,回落普通锁定
        XCTAssertEqual(spec.blockedApps, [1, 2])
    }

    func testSpecExpiredGuestModeFallsBackToLock() {
        var s = state(lock: true)
        s.guestModeUntil = now.addingTimeInterval(-1)
        let spec = makeSpec(selectionApps: [1, 2], guestApps: [3], state: s)
        XCTAssertNil(spec.shieldAllExcept)
        XCTAssertEqual(spec.blockedApps, [1, 2])
    }

    func testSpecScheduleOutsideWindowSuppressesEverything() {
        var s = scheduledState(start: 9 * 60, end: 17 * 60)
        s.isVIP = true
        s.lockMode = .allowlist
        let spec = makeSpec(selectionApps: [1, 2], selectionCategories: [5], state: s,
                            at: date(hour: 20, minute: 0), calendar: shanghaiCalendar)
        XCTAssertNil(spec.shieldAllExcept)
        XCTAssertNil(spec.blockedApps)
        XCTAssertNil(spec.shieldedCategories)
    }

    func testSpecScheduleInsideWindowLocks() {
        let s = scheduledState(start: 9 * 60, end: 17 * 60)
        let spec = makeSpec(selectionApps: [1, 2], state: s,
                            at: date(hour: 12, minute: 0), calendar: shanghaiCalendar)
        XCTAssertEqual(spec.blockedApps, [1, 2])
    }

    func testSpecDenyAppRemovalRequiresVIPAndToggle() {
        XCTAssertFalse(makeSpec(state: state(vip: false, antiRemoval: true)).denyAppRemoval)
        XCTAssertFalse(makeSpec(state: state(vip: true, antiRemoval: false)).denyAppRemoval)
        XCTAssertTrue(makeSpec(state: state(vip: true, antiRemoval: true)).denyAppRemoval)

        var guest = state(lock: true, vip: true, antiRemoval: true)
        guest.guestModeUntil = now.addingTimeInterval(1800)
        XCTAssertTrue(makeSpec(guestApps: [3], state: guest).denyAppRemoval) // 访客期间防卸载同样生效
    }

    // MARK: - make(from:) 薄适配层(真实 token 解码,模拟器上走空选择路径)

    func testMakeWithEmptySelectionProducesNilNotEmptySet() {
        let plan = RestrictionsPlan.make(from: state(lock: true), now: now)
        XCTAssertNil(plan.blockedApps)
        XCTAssertNil(plan.shieldAllExcept)
        XCTAssertNil(plan.shieldedCategories)
    }

    func testMakeLockDisabledMeansNoShield() {
        let plan = RestrictionsPlan.make(from: state(lock: false), now: now)
        XCTAssertNil(plan.blockedApps)
    }

    func testMakeDenyAppRemovalRequiresVIPAndToggle() {
        XCTAssertFalse(RestrictionsPlan.make(from: state(vip: false, antiRemoval: true), now: now).denyAppRemoval)
        XCTAssertFalse(RestrictionsPlan.make(from: state(vip: true, antiRemoval: false), now: now).denyAppRemoval)
        XCTAssertTrue(RestrictionsPlan.make(from: state(vip: true, antiRemoval: true), now: now).denyAppRemoval)
    }

    // MARK: - lockActive:锁定此刻是否生效的权威判断(纯函数,时间表/临时解锁门控都在这)

    private var shanghaiCalendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return c
    }

    private func date(hour: Int, minute: Int) -> Date {
        shanghaiCalendar.date(from: DateComponents(year: 2026, month: 7, day: 14,
                                                   hour: hour, minute: minute))!
    }

    private func scheduledState(start: Int, end: Int) -> LockerState {
        var s = state(lock: true)
        s.scheduleEnabled = true
        s.scheduleStartMinutes = start
        s.scheduleEndMinutes = end
        return s
    }

    func testLockActivePlainToggle() {
        XCTAssertTrue(RestrictionsPlan.lockActive(state: state(lock: true), now: now))
        XCTAssertFalse(RestrictionsPlan.lockActive(state: state(lock: false), now: now))
    }

    func testLockActiveRespectsTemporaryUnlock() {
        let s = state(lock: true, tempUntil: now.addingTimeInterval(900))
        XCTAssertFalse(RestrictionsPlan.lockActive(state: s, now: now))
        XCTAssertTrue(RestrictionsPlan.lockActive(state: s, now: now.addingTimeInterval(901)))
    }

    func testLockActiveInsideAndOutsideScheduleWindow() {
        let s = scheduledState(start: 9 * 60, end: 17 * 60)
        XCTAssertTrue(RestrictionsPlan.lockActive(state: s, now: date(hour: 12, minute: 0),
                                                  calendar: shanghaiCalendar))
        XCTAssertFalse(RestrictionsPlan.lockActive(state: s, now: date(hour: 20, minute: 0),
                                                   calendar: shanghaiCalendar))
    }

    func testLockActiveTemporaryUnlockWinsInsideWindow() {
        var s = scheduledState(start: 9 * 60, end: 17 * 60)
        s.temporaryUnlockUntil = date(hour: 12, minute: 30)
        XCTAssertFalse(RestrictionsPlan.lockActive(state: s, now: date(hour: 12, minute: 0),
                                                   calendar: shanghaiCalendar))
    }

    // MARK: - 访客模式

    func testGuestModeInactiveWithoutSelectionOrWhenExpired() {
        var s = state(lock: true)
        s.guestModeUntil = now.addingTimeInterval(1800) // 有截止时间但白名单为空 → 不生效
        XCTAssertFalse(RestrictionsPlan.guestModeActive(state: s, now: now))
        XCTAssertNil(RestrictionsPlan.make(from: s, now: now).shieldAllExcept)

        s.guestModeUntil = now.addingTimeInterval(-1) // 已过期
        XCTAssertFalse(RestrictionsPlan.guestModeActive(state: s, now: now))

        s.guestModeUntil = nil
        XCTAssertFalse(RestrictionsPlan.guestModeActive(state: s, now: now))
    }

    func testGuestModeActiveGenericCheck() {
        XCTAssertTrue(RestrictionsPlan.guestModeActive(guestModeUntil: now.addingTimeInterval(600),
                                                       guestApplications: Set([1]), now: now))
        XCTAssertFalse(RestrictionsPlan.guestModeActive(guestModeUntil: now.addingTimeInterval(600),
                                                        guestApplications: Set<Int>(), now: now))
        XCTAssertFalse(RestrictionsPlan.guestModeActive(guestModeUntil: now.addingTimeInterval(-1),
                                                        guestApplications: Set([1]), now: now))
    }

    // MARK: - 单一锁定策略

    func testBlockedApplicationsRule() {
        XCTAssertEqual(RestrictionsPlan.blockedApplications(tokens: Set([1, 2]),
                                                            lockActive: true, allowlistMode: false), [1, 2])
        XCTAssertNil(RestrictionsPlan.blockedApplications(tokens: Set([1, 2]),
                                                          lockActive: false, allowlistMode: false))
        XCTAssertNil(RestrictionsPlan.blockedApplications(tokens: Set([1, 2]),
                                                          lockActive: true, allowlistMode: true))
        XCTAssertNil(RestrictionsPlan.blockedApplications(tokens: Set<Int>(),
                                                          lockActive: true, allowlistMode: false))
    }

    func testTokenRefreshUpdatesEveryReferenceWithOneRefreshPass() throws {
        let original: [Set<Int>?] = [[1, 2], nil, [2, 3]]

        let refreshed = try RestrictionsTokenRefresh.refresh(original) { tokens in
            tokens = tokens.map { $0 + 10 }
        }

        XCTAssertEqual(refreshed, [[11, 12], nil, [12, 13]])
    }

    func testTokenRefreshFailureKeepsOriginalReferences() {
        enum RefreshError: Error { case failed }
        let original: [Set<Int>?] = [[1, 2], nil, [2, 3]]

        let refreshed = RestrictionsTokenRefresh.refreshOrOriginal(original) { _ in
            throw RefreshError.failed
        }

        XCTAssertEqual(refreshed, original)
    }

    func testManagedSettingUpdateOnlyWritesChangedValues() {
        XCTAssertFalse(ManagedSettingsRestrictions.needsUpdate(current: Optional(1), desired: 1))
        XCTAssertFalse(ManagedSettingsRestrictions.needsUpdate(current: nil as Int?, desired: nil))
        XCTAssertTrue(ManagedSettingsRestrictions.needsUpdate(current: Optional(1), desired: 2))
        XCTAssertTrue(ManagedSettingsRestrictions.needsUpdate(current: Optional(1), desired: nil))
    }
}
