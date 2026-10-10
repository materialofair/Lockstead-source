import XCTest
@testable import Lockstead
import FamilyControls
import ManagedSettings

final class MockScheduler: UnlockScheduling {
    var scheduled: [Date] = []
    var cancelCount = 0
    var succeeds = true
    func scheduleRelock(until: Date) -> Bool {
        if succeeds { scheduled.append(until) }
        return succeeds
    }
    func cancelRelock() { cancelCount += 1 }
}

final class MockLockScheduler: LockScheduleScheduling {
    var started: [(start: Int, end: Int)] = []
    var stopCount = 0
    var succeeds = true
    var startedRules: [[ScheduleRule]] = []
    func start(rules: [ScheduleRule]) -> Bool {
        if succeeds {
            startedRules.append(rules)
            started.append(contentsOf: rules.map { ($0.startMinutes, $0.endMinutes) })
        }
        return succeeds
    }
    func startDaily(startMinutes: Int, endMinutes: Int) -> Bool {
        if succeeds { started.append((startMinutes, endMinutes)) }
        return succeeds
    }
    func stop() { stopCount += 1 }
}

final class MockGuestScheduler: GuestModeScheduling {
    var scheduled: [Date] = []
    var cancelCount = 0
    var succeeds = true
    func scheduleRestore(until: Date) -> Bool {
        if succeeds { scheduled.append(until) }
        return succeeds
    }
    func cancelRestore() { cancelCount += 1 }
}

@MainActor
final class LockerViewModelTests: XCTestCase {
    private var vm: LockerViewModel!
    private var restrictions: MockRestrictions!
    private var scheduler: MockScheduler!
    private var lockScheduler: MockLockScheduler!
    private var guestScheduler: MockGuestScheduler!
    private var store: AppGroupStore!
    private var now: Date!

    override func setUp() async throws {
        now = Date(timeIntervalSince1970: 1_700_000_000)
        store = AppGroupStore(defaults: UserDefaults(suiteName: "unit-test-\(UUID().uuidString)")!)
        restrictions = MockRestrictions()
        scheduler = MockScheduler()
        lockScheduler = MockLockScheduler()
        guestScheduler = MockGuestScheduler()
        vm = LockerViewModel(store: store, restrictions: restrictions,
                             scheduler: scheduler, lockScheduler: lockScheduler,
                             guestScheduler: guestScheduler,
                             now: { self.now })
    }

    func testSetLockPersistsAndApplies() {
        vm.setLock(true)
        XCTAssertTrue(store.load().isLockEnabled)
        XCTAssertEqual(restrictions.appliedPlans.count, 1)
    }

    func testExpiredManagedSettingsTokensReapplyCurrentRestrictions() {
        guard #available(iOS 26.5, *) else { return }

        NotificationCenter.default.post(
            name: ManagedSettingsStore.TokenExpiryMessage.name,
            object: nil
        )

        XCTAssertEqual(restrictions.appliedPlans.count, 1)
    }

    func testTemporaryUnlockOnlyAcceptsAllowedDurations() {
        vm.temporaryUnlock(minutes: 5) // 非法档位:拒绝
        XCTAssertNil(store.load().temporaryUnlockUntil)
        XCTAssertTrue(scheduler.scheduled.isEmpty)

        vm.temporaryUnlock(minutes: 15)
        XCTAssertEqual(store.load().temporaryUnlockUntil!.timeIntervalSince(now), 900, accuracy: 0.1)
        XCTAssertEqual(scheduler.scheduled.count, 1)
        XCTAssertEqual(restrictions.appliedPlans.count, 1)
    }

    func testTemporaryUnlockSchedulingFailureRollsBackAndPublishesFeedback() {
        scheduler.succeeds = false

        vm.temporaryUnlock(minutes: 15)

        XCTAssertNil(store.load().temporaryUnlockUntil)
        XCTAssertEqual(vm.feedback, .temporaryUnlockFailed)
    }

    func testEndTemporaryUnlockNow() {
        vm.temporaryUnlock(minutes: 15)
        vm.endTemporaryUnlockNow()
        XCTAssertNil(store.load().temporaryUnlockUntil)
        XCTAssertEqual(scheduler.cancelCount, 1)
    }

    func testRefreshTimedModesClearsExpiredDeadlinesWhileAppStaysForeground() {
        var state = store.load()
        state.isLockEnabled = true
        store.save(state)
        store.saveTimed(TimedModeState(temporaryUnlockUntil: now.addingTimeInterval(-1),
                                       guestModeUntil: now.addingTimeInterval(-1)))
        vm.reloadFromAppGroup()

        vm.refreshTimedModes(at: now)

        XCTAssertNil(store.load().temporaryUnlockUntil)
        XCTAssertNil(store.load().guestModeUntil)
        XCTAssertEqual(scheduler.cancelCount, 1)
        XCTAssertEqual(guestScheduler.cancelCount, 1)
        XCTAssertEqual(restrictions.appliedPlans.count, 1)
    }

    func testScheduleEnableStartsMonitoringAndDisableStops() {
        vm.setScheduleEnabled(true)
        XCTAssertTrue(store.load().scheduleEnabled)
        XCTAssertEqual(lockScheduler.started.count, 1)
        XCTAssertEqual(lockScheduler.started.first?.start, 21 * 60) // 默认 21:00–07:00
        XCTAssertEqual(lockScheduler.started.first?.end, 7 * 60)

        vm.setScheduleEnabled(false)
        XCTAssertFalse(store.load().scheduleEnabled)
        XCTAssertEqual(lockScheduler.stopCount, 1)
    }

    func testScheduleWindowChangeRestartsMonitoringWhenEnabled() {
        vm.setScheduleEnabled(true)
        vm.setScheduleWindow(startMinutes: 9 * 60, endMinutes: 17 * 60)
        let s = store.load()
        XCTAssertEqual(s.scheduleStartMinutes, 9 * 60)
        XCTAssertEqual(s.scheduleEndMinutes, 17 * 60)
        XCTAssertEqual(lockScheduler.started.count, 2) // 开启 1 次 + 改窗重启 1 次
    }

    func testScheduleWindowRejectsInvalidWindow() {
        vm.setScheduleWindow(startMinutes: 600, endMinutes: 605) // < 15 分钟
        let s = store.load()
        XCTAssertEqual(s.scheduleStartMinutes, 21 * 60) // 保持默认,拒绝写入
        XCTAssertTrue(lockScheduler.started.isEmpty)
    }

    func testConfigureAndEnableScheduleCommitsWindowBeforeStartingMonitoring() {
        vm.configureAndEnableSchedule(startMinutes: 9 * 60, endMinutes: 17 * 60)

        let state = store.load()
        XCTAssertTrue(state.scheduleEnabled)
        XCTAssertEqual(state.scheduleStartMinutes, 9 * 60)
        XCTAssertEqual(state.scheduleEndMinutes, 17 * 60)
        XCTAssertEqual(lockScheduler.started.count, 1)
        XCTAssertEqual(lockScheduler.started.first?.start, 9 * 60)
        XCTAssertEqual(lockScheduler.started.first?.end, 17 * 60)
    }

    func testScheduleFailurePreservesWindowAndPublishesFailure() {
        lockScheduler.succeeds = false

        vm.configureAndEnableSchedule(startMinutes: 9 * 60, endMinutes: 17 * 60)

        XCTAssertTrue(store.load().scheduleEnabled)
        XCTAssertTrue(store.load().scheduleRegistrationFailed)
        XCTAssertEqual(vm.feedback, .scheduleFailed)
    }

    func testLockModePersistsForVIPAndPaywallsForFree() {
        var s = store.load(); s.isVIP = true; store.save(s)
        vm.setLockMode(.allowlist)
        XCTAssertEqual(store.load().lockMode, .allowlist)
        XCTAssertFalse(vm.showPaywall)

        s = store.load(); s.isVIP = false; store.save(s)
        vm.setLockMode(.blocklist) // 回黑名单不需要 VIP
        XCTAssertEqual(store.load().lockMode, .blocklist)
        vm.setLockMode(.allowlist) // 非 VIP 点白名单 → Paywall,不写入
        XCTAssertEqual(store.load().lockMode, .blocklist)
        XCTAssertTrue(vm.showPaywall)
    }

    func testClearAllDisablesScheduleAndStopsMonitoring() {
        vm.setScheduleEnabled(true)
        vm.clearAllRestrictions()
        XCTAssertFalse(store.load().scheduleEnabled)
        XCTAssertEqual(lockScheduler.stopCount, 1)
    }

    // MARK: - 访客模式(真实 token 造不出,成功路径走真机回归;这里锁门控与清理)

    func testStartGuestModeRejectsInvalidMinutesAndEmptySelection() {
        var s = store.load(); s.isVIP = true; store.save(s)
        vm.startGuestMode(minutes: 10)  // 低于 15 分钟下限
        vm.startGuestMode(minutes: 721) // 超过 12 小时上限
        vm.startGuestMode(minutes: 30)  // 合法时长但访客白名单为空
        XCTAssertNil(store.load().guestModeUntil)
        XCTAssertTrue(guestScheduler.scheduled.isEmpty)
        XCTAssertFalse(vm.showPaywall)
    }

    func testEndGuestModeClearsStateAndCancelsRestore() {
        store.saveTimed(TimedModeState(guestModeUntil: now.addingTimeInterval(1800)))
        vm.reloadFromAppGroup()
        vm.endGuestModeNow()
        XCTAssertNil(store.load().guestModeUntil)
        XCTAssertEqual(guestScheduler.cancelCount, 1)
    }

    func testClearAllEndsGuestMode() {
        store.saveTimed(TimedModeState(guestModeUntil: now.addingTimeInterval(1800)))
        vm.reloadFromAppGroup()
        vm.clearAllRestrictions()
        XCTAssertNil(store.load().guestModeUntil)
        XCTAssertEqual(guestScheduler.cancelCount, 1)
    }

    func testPrivacyTogglesPersistIndependently() {
        vm.setDiscreetShield(true)
        vm.setBiometricUnlock(true)
        XCTAssertTrue(store.load().isDiscreetShieldEnabled)
        XCTAssertTrue(store.load().isBiometricUnlockEnabled)

        vm.setDiscreetShield(false)
        let s = store.load()
        XCTAssertFalse(s.isDiscreetShieldEnabled)
        XCTAssertTrue(s.isBiometricUnlockEnabled) // 关一个不影响另一个
    }

    func testCalculatorLoginModePersistsWithoutClobberingPIN() {
        let credentialStore = InMemoryPINCredentialStore()
        var state = store.load()
        PINManager(store: credentialStore, hasher: .testFast).set(pin: "123456", hint: nil, in: &state)
        store.save(state)

        vm.setLoginMode(.calculator)

        XCTAssertEqual(store.load().loginMode, .calculator)
        XCTAssertNotNil(credentialStore.loadCredential()) // PIN 凭据在 Keychain,状态保存不会触及
    }

    func testClearAllRestrictions() {
        vm.setLock(true)
        vm.clearAllRestrictions()
        let s = store.load()
        XCTAssertFalse(s.isLockEnabled)
        XCTAssertFalse(s.isAntiRemovalEnabled)
        XCTAssertNil(s.temporaryUnlockUntil)
        XCTAssertEqual(restrictions.clearAllCount, 1)
        XCTAssertEqual(scheduler.cancelCount, 1)
    }

    func testCommitSelectionEmptyIsOK() {
        vm.commitSelection()
        XCTAssertNil(vm.selectionError)
        XCTAssertFalse(vm.showPaywall)
    }

    func testPendingSelectionOnlyAppliesAfterVIPPurchase() {
        let pending = FamilyActivitySelection()

        vm.stageSelectionForPaywall(pending, selectedItemCount: 2)

        XCTAssertEqual(vm.pendingSelectionCount, 2)
        XCTAssertTrue(vm.showPaywall)

        vm.resolvePendingSelectionAfterPaywall(isVIP: false)

        XCTAssertNil(vm.pendingSelectionCount)
        XCTAssertFalse(vm.showPaywall)
        XCTAssertTrue(restrictions.appliedPlans.isEmpty)

        vm.stageSelectionForPaywall(pending, selectedItemCount: 2)
        vm.resolvePendingSelectionAfterPaywall(isVIP: true)

        XCTAssertNil(vm.pendingSelectionCount)
        XCTAssertFalse(vm.showPaywall)
        XCTAssertEqual(restrictions.appliedPlans.count, 1)
        XCTAssertEqual(vm.feedback, .selectionApplied(itemCount: 2))
    }

    func testGuardSetupProgressGuidesSelectionBeforeEnablingProtection() {
        XCTAssertEqual(
            GuardSetupProgress.resolve(selectedItemCount: 0, lockEnabled: false),
            .chooseApps
        )
        XCTAssertEqual(
            GuardSetupProgress.resolve(selectedItemCount: 2, lockEnabled: false),
            .enableProtection
        )
        XCTAssertEqual(
            GuardSetupProgress.resolve(selectedItemCount: 1, lockEnabled: true),
            .complete
        )
    }

    func testGuestModePreviewSummarizesImpactBeforeStarting() {
        let preview = GuestModePreview(
            allowedAppCount: 2,
            durationMinutes: 30,
            now: now
        )

        XCTAssertEqual(preview.allowedAppCount, 2)
        XCTAssertEqual(preview.endsAt, now.addingTimeInterval(30 * 60))
    }

    // C1 回归:vm 初始化后,其他写入者(EntitlementStore)直接写入 App Group 的 isVIP
    // 不应被 vm 之后的整体覆写(wholesale save)清除。
    func testVMSaveDoesNotClobberVIPMirror() {
        var s = store.load()
        s.isVIP = true
        store.save(s)

        vm.setLock(true)

        XCTAssertTrue(store.load().isVIP)
    }

    // C1 回归:vm 初始化后,其他写入者(PINSetupView/PINEntryView)写入 Keychain 的
    // PIN 凭据不应被 vm 的状态保存触及(凭据已彻底移出 App Group 状态档)。
    func testVMSaveDoesNotErasePINSetAfterInit() {
        let credentialStore = InMemoryPINCredentialStore()
        var s = store.load()
        PINManager(store: credentialStore, hasher: .testFast).set(pin: "123456", hint: nil, in: &s)
        store.save(s)

        vm.setLock(true)

        XCTAssertNotNil(credentialStore.loadCredential())
    }
}
