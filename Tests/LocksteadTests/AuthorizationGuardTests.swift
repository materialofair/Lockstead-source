import XCTest
@testable import Lockstead

final class AuthorizationGuardTests: XCTestCase {
    private var store: AppGroupStore!
    private var restrictions: MockRestrictions!
    private var unlockScheduler: MockScheduler!
    private var lockScheduler: MockLockScheduler!
    private var guestScheduler: MockGuestScheduler!
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    override func setUp() {
        super.setUp()
        store = AppGroupStore(defaults: UserDefaults(suiteName: "unit-test-\(UUID().uuidString)")!)
        restrictions = MockRestrictions()
        unlockScheduler = MockScheduler()
        lockScheduler = MockLockScheduler()
        guestScheduler = MockGuestScheduler()
    }

    private func sync(isAuthorized: Bool, previousAuthorized: Bool? = nil) {
        AuthorizationGuard.foregroundSync(isAuthorized: isAuthorized,
                                          previousAuthorized: previousAuthorized,
                                          store: store,
                                          restrictions: restrictions,
                                          unlockScheduler: unlockScheduler,
                                          lockScheduler: lockScheduler,
                                          guestScheduler: guestScheduler,
                                          now: now)
    }

    func testRevokedClearsRestrictionsAndCancelsAllSchedulers() {
        var s = store.load()
        s.isLockEnabled = true
        store.save(s)
        store.saveTimed(TimedModeState(temporaryUnlockUntil: now.addingTimeInterval(600),
                                       guestModeUntil: now.addingTimeInterval(1200)))

        sync(isAuthorized: false)

        XCTAssertEqual(restrictions.clearAllCount, 1)
        XCTAssertEqual(unlockScheduler.cancelCount, 1)
        XCTAssertEqual(lockScheduler.stopCount, 1)
        XCTAssertEqual(guestScheduler.cancelCount, 1)
        // 限时状态清空(调度已取消,不留悬空的截止时间)
        let after = store.load()
        XCTAssertNil(after.temporaryUnlockUntil)
        XCTAssertNil(after.guestModeUntil)
    }

    func testRevokedKeepsUserConfigForReauthorization() {
        let credentialStore = InMemoryPINCredentialStore()
        var s = store.load()
        s.isLockEnabled = true
        s.scheduleEnabled = true
        PINManager(store: credentialStore, hasher: .testFast).set(pin: "123456", hint: nil, in: &s)
        store.save(s)

        sync(isAuthorized: false)

        let after = store.load()
        XCTAssertTrue(after.isLockEnabled)     // 配置保留,重新授权后守护原样恢复
        XCTAssertTrue(after.scheduleEnabled)
        XCTAssertNotNil(credentialStore.loadCredential()) // PIN 凭据保留
        XCTAssertTrue(restrictions.appliedPlans.isEmpty) // 撤销分支绝不下发计划
    }

    func testAuthorizedReappliesPlanFromCurrentState() {
        var s = store.load()
        s.isLockEnabled = true
        store.save(s)

        sync(isAuthorized: true)

        XCTAssertEqual(restrictions.appliedPlans.count, 1)
        XCTAssertEqual(restrictions.clearAllCount, 0)
        XCTAssertTrue(lockScheduler.started.isEmpty) // 时间表未开启:不挂监控
    }

    func testAuthorizedRestartsDailyScheduleWhenEnabled() {
        var s = store.load()
        s.scheduleEnabled = true
        s.scheduleStartMinutes = 9 * 60
        s.scheduleEndMinutes = 17 * 60
        store.save(s)

        sync(isAuthorized: true) // 首次同步(previousAuthorized = nil):重挂
        XCTAssertEqual(lockScheduler.started.count, 1)
        XCTAssertEqual(lockScheduler.started.first?.start, 9 * 60)
        XCTAssertEqual(lockScheduler.started.first?.end, 17 * 60)
        // 一次性监控(临时解锁/访客)刻意不重挂:剩余时长可能低于 15 分钟下限
        XCTAssertTrue(unlockScheduler.scheduled.isEmpty)
        XCTAssertTrue(guestScheduler.scheduled.isEmpty)
    }

    func testAuthorizedSteadyStateSkipsScheduleRearm() {
        var s = store.load()
        s.scheduleEnabled = true
        store.save(s)

        sync(isAuthorized: true, previousAuthorized: true) // 稳态回前台:不重挂

        XCTAssertTrue(lockScheduler.started.isEmpty)
        XCTAssertEqual(restrictions.appliedPlans.count, 1) // 计划自愈照常执行
    }

    func testReauthorizationTransitionRearmsSchedule() {
        var s = store.load()
        s.scheduleEnabled = true
        store.save(s)

        sync(isAuthorized: true, previousAuthorized: false) // 撤销 → 重新授权翻转:重挂

        XCTAssertEqual(lockScheduler.started.count, 1)
    }
}
