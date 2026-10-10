import XCTest
@testable import Lockstead

final class GuardActionsTests: XCTestCase {
    private var store: AppGroupStore!
    private var restrictions: MockRestrictions!
    private var unlockScheduler: MockScheduler!
    private var guestScheduler: MockGuestScheduler!
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    override func setUp() {
        super.setUp()
        store = AppGroupStore(defaults: UserDefaults(suiteName: "unit-test-\(UUID().uuidString)")!)
        restrictions = MockRestrictions()
        unlockScheduler = MockScheduler()
        guestScheduler = MockGuestScheduler()
    }

    func testLockNowEnablesLockEndsTempUnlockAndApplies() {
        store.saveTimed(TimedModeState(temporaryUnlockUntil: now.addingTimeInterval(600)))

        let guestActive = GuardActions.lockNow(store: store, restrictions: restrictions,
                                               unlockScheduler: unlockScheduler, now: now)

        let after = store.load()
        XCTAssertTrue(after.isLockEnabled)
        XCTAssertNil(after.temporaryUnlockUntil)
        XCTAssertEqual(unlockScheduler.cancelCount, 1)
        XCTAssertEqual(restrictions.appliedPlans.count, 1)
        XCTAssertFalse(guestActive) // 无访客配置:如实报告「未处于访客模式」
    }

    func testLockNowDoesNotTouchOtherConfig() {
        let credentialStore = InMemoryPINCredentialStore()
        var s = store.load()
        s.scheduleEnabled = true
        s.isAntiRemovalEnabled = true
        PINManager(store: credentialStore, hasher: .testFast).set(pin: "123456", hint: nil, in: &s)
        store.save(s)

        GuardActions.lockNow(store: store, restrictions: restrictions,
                             unlockScheduler: unlockScheduler, now: now)

        let after = store.load()
        XCTAssertTrue(after.scheduleEnabled)
        XCTAssertTrue(after.isAntiRemovalEnabled)
        XCTAssertNotNil(credentialStore.loadCredential()) // PIN 凭据不受影响
    }

    func testGuestDurationRange() {
        // 下限 15 分钟来自 DeviceActivity 最小监控时长;上限 12 小时是「访客必须限时」的承诺
        XCTAssertFalse(GuardActions.isValidGuestDuration(14))
        XCTAssertTrue(GuardActions.isValidGuestDuration(15))
        XCTAssertTrue(GuardActions.isValidGuestDuration(45))   // 自定义:非预设值也合法
        XCTAssertTrue(GuardActions.isValidGuestDuration(720))
        XCTAssertFalse(GuardActions.isValidGuestDuration(721))
        // 预设档位都必须落在合法范围内
        for preset in GuardActions.guestPresetMinutes {
            XCTAssertTrue(GuardActions.isValidGuestDuration(preset))
        }
    }

    // 访客成功路径需要真实 ApplicationToken(造不出),真机回归覆盖;这里锁门控顺序与失败方向
    func testStartGuestModeRejectsInvalidDuration() {
        for bad in [10, 721] {
            XCTAssertThrowsError(try GuardActions.startGuestMode(
                minutes: bad, store: store, restrictions: restrictions,
                guestScheduler: guestScheduler, now: now)) { error in
                XCTAssertEqual(error as? GuardActionError, .invalidDuration)
            }
        }
        XCTAssertNil(store.load().guestModeUntil)
        XCTAssertTrue(guestScheduler.scheduled.isEmpty)
    }

    func testStartGuestModeRejectsEmptyGuestListBeforeVIPCheck() {
        // 白名单为空时,无论 VIP 与否都报「未配置」——比「需要 VIP」更接近真实堵点
        var s = store.load(); s.isVIP = true; store.save(s)
        XCTAssertThrowsError(try GuardActions.startGuestMode(
            minutes: 30, store: store, restrictions: restrictions,
            guestScheduler: guestScheduler, now: now)) { error in
            XCTAssertEqual(error as? GuardActionError, .guestListEmpty)
        }
        XCTAssertNil(store.load().guestModeUntil)
        XCTAssertTrue(restrictions.appliedPlans.isEmpty)
    }
}
