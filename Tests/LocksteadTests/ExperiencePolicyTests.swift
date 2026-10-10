import XCTest
import FamilyControls
@testable import Lockstead

@MainActor
final class ExperiencePolicyTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)
    private var suite: String!
    private var defaults: UserDefaults!
    private var store: AppGroupStore!
    private var scheduler: MockScheduler!
    private var lockScheduler: MockLockScheduler!
    private var guestScheduler: MockGuestScheduler!
    private var restrictions: MockRestrictions!
    private var vm: LockerViewModel!

    override func setUp() async throws {
        suite = "experience-policy-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)!
        store = AppGroupStore(defaults: defaults)
        scheduler = MockScheduler()
        lockScheduler = MockLockScheduler()
        guestScheduler = MockGuestScheduler()
        restrictions = MockRestrictions()
        let date = now
        vm = LockerViewModel(store: store, restrictions: restrictions, scheduler: scheduler,
                             lockScheduler: lockScheduler, guestScheduler: guestScheduler, now: { date })
    }

    override func tearDown() async throws {
        vm = nil
        defaults.removePersistentDomain(forName: suite)
    }

    private func scopedState() -> LockerState {
        var state = LockerState()
        state.isLockEnabled = true
        state.isVIP = true
        state.temporaryUnlockUntil = now.addingTimeInterval(1800)
        state.temporaryUnlockSelectionData = Data([1])
        return state
    }

    private func plan(_ state: LockerState, temporary: Set<Int> = [2, 3], guest: Set<Int> = []) -> RestrictionsPlanSpec<Int, Int> {
        RestrictionsPlan.makeSpec(selectionApplications: [1, 2], selectionCategories: [10],
                                  guestApplications: guest, temporaryApplications: temporary,
                                  state: state, now: now)
    }

    func testScopedBlocklistSubtractsAppsAndAddsCategoryExceptions() {
        let result = plan(scopedState())
        XCTAssertEqual(result.blockedApps, [1])
        XCTAssertEqual(result.shieldedCategories, [10])
        XCTAssertEqual(result.categoryExceptions, [2, 3])
        XCTAssertNil(result.shieldAllExcept)
    }

    func testScopedAllowlistUnionsAllowedApps() {
        var state = scopedState()
        state.lockMode = .allowlist
        let result = plan(state)
        XCTAssertEqual(result.shieldAllExcept, [1, 2, 3])
        XCTAssertNil(result.blockedApps)
        XCTAssertNil(result.shieldedCategories)
    }

    func testGuestRulesTakePrecedenceOverScopedAndFullPause() {
        var state = scopedState()
        state.guestModeUntil = now.addingTimeInterval(600)
        for data: Data? in [Data([1]), nil] {
            state.temporaryUnlockSelectionData = data
            let result = plan(state, guest: [9])
            XCTAssertEqual(result.shieldAllExcept, [9])
            XCTAssertTrue(result.categoryExceptions.isEmpty)
            XCTAssertNil(result.blockedApps)
        }
    }

    func testExpiryRestoresRulesAtExactDeadline() {
        var state = scopedState()
        state.temporaryUnlockUntil = now
        let result = plan(state)
        XCTAssertEqual(result.blockedApps, [1, 2])
        XCTAssertTrue(result.categoryExceptions.isEmpty)
        state.temporaryUnlockSelectionData = nil
        XCTAssertEqual(plan(state).blockedApps, [1, 2])
    }

    func testUndecodableScopedPayloadDoesNotBecomeFullPause() {
        let state = scopedState()
        // The production decoder yields an empty token set for corrupt payloads.
        XCTAssertTrue(RestrictionsPlan.lockActive(state: state, now: now))
        let result = plan(state, temporary: [])
        XCTAssertEqual(result.blockedApps, [1, 2])
        XCTAssertEqual(result.shieldedCategories, [10])
        XCTAssertTrue(result.categoryExceptions.isEmpty)
    }

    func testTemporarySessionRoundTripPreservesScopeAndGuest() throws {
        let session = TemporaryAccessSession(until: now.addingTimeInterval(900), selectionData: Data([1, 2, 3]))
        store.saveGuestModeUntil(now.addingTimeInterval(3600))
        store.saveTemporarySession(session)
        XCTAssertEqual(store.loadTemporarySession(), session)
        XCTAssertEqual(store.load().temporaryUnlockSelectionData, session.selectionData)
        XCTAssertEqual(store.load().temporaryUnlockUntil, session.until)
        XCTAssertEqual(store.load().guestModeUntil, now.addingTimeInterval(3600))
        store.saveTemporarySession(nil)
        XCTAssertNil(store.load().temporaryUnlockUntil)
        XCTAssertNil(store.load().temporaryUnlockSelectionData)
        XCTAssertEqual(store.load().guestModeUntil, now.addingTimeInterval(3600))
    }

    func testLegacyDeadlineMigratesAndClearCannotResurrectIt() {
        let deadline = now.addingTimeInterval(900)
        defaults.set(deadline, forKey: AppGroup.temporaryUnlockKey)
        XCTAssertEqual(store.load().temporaryUnlockUntil, deadline)
        XCTAssertNil(store.loadTemporarySession()?.selectionData)
        XCTAssertNil(defaults.object(forKey: AppGroup.temporaryUnlockKey))
        store.saveTemporarySession(nil)
        XCTAssertNil(store.load().temporaryUnlockUntil)
        XCTAssertNil(AppGroupStore(defaults: defaults).load().temporaryUnlockUntil)
    }

    func testLegacyMainBlobTimerDoesNotResurrectAfterClear() throws {
        // Old JSON stored dates in Foundation's reference-date representation.
        let blob: [String: Any] = ["temporaryUnlockUntil": now.addingTimeInterval(900).timeIntervalSinceReferenceDate,
                                   "guestModeUntil": now.addingTimeInterval(1800).timeIntervalSinceReferenceDate]
        defaults.removeObject(forKey: AppGroup.timedMigrationKey)
        defaults.set(try JSONSerialization.data(withJSONObject: blob), forKey: AppGroup.stateKey)
        XCTAssertEqual(store.load().temporaryUnlockUntil, now.addingTimeInterval(900))
        store.saveTimed(TimedModeState())
        XCTAssertNil(store.load().temporaryUnlockUntil)
        XCTAssertNil(store.load().guestModeUntil)
    }

    func testCombinedLegacyTimerMigrationPreservesBothDeadlines() throws {
        let legacy = TimedModeState(temporaryUnlockUntil: now.addingTimeInterval(900),
                                   guestModeUntil: now.addingTimeInterval(1800))
        defaults.set(try JSONEncoder().encode(legacy), forKey: AppGroup.timedStateKey)
        XCTAssertEqual(store.loadTimed(), legacy)
        XCTAssertNil(defaults.object(forKey: AppGroup.timedStateKey))
        XCTAssertNil(store.loadTemporarySession()?.selectionData)
        store.saveTimed(TimedModeState())
        XCTAssertEqual(store.loadTimed(), TimedModeState())
    }

    func testOldStateWithoutExperienceFieldsPreservesPINAndLegacySchedule() throws {
        let json: [String: Any] = ["pinHint": "keep me", "isVIP": true, "scheduleEnabled": true,
                                  "scheduleStartMinutes": 540, "scheduleEndMinutes": 1020]
        let state = try JSONDecoder().decode(LockerState.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(state.pinHint, "keep me")
        XCTAssertTrue(state.isVIP)
        XCTAssertTrue(state.scenes.isEmpty)
        XCTAssertNil(state.activeSceneID)
        XCTAssertEqual(state.effectiveScheduleRules.count, 1)
        XCTAssertEqual(state.effectiveScheduleRules.first?.weekdays, Set(1...7))
        XCTAssertEqual(state.effectiveScheduleRules.first?.startMinutes, 540)
        XCTAssertEqual(state.effectiveScheduleRules.first?.endMinutes, 1020)
    }

    func testCorruptAtomicSessionFailsClosed() {
        var state = LockerState()
        state.isLockEnabled = true
        store.save(state)
        defaults.set(Data("corrupt".utf8), forKey: AppGroup.temporarySessionKey)
        let loaded = store.load()
        XCTAssertNil(loaded.temporaryUnlockUntil)
        XCTAssertTrue(RestrictionsPlan.lockActive(state: loaded, now: now))
    }

    func testSceneRejectsFreshVIPExpiryWithoutMutatingRulesOrTimers() throws {
        var state = LockerState()
        state.isVIP = true
        state.lockMode = .allowlist
        let scene = GuardScene(name: "VIP", state: state)
        state.lockMode = .blocklist
        state.scenes = [scene]
        store.save(state)
        store.saveTemporaryUnlockUntil(now.addingTimeInterval(900))
        vm.reloadFromAppGroup()
        state = store.load()
        state.isVIP = false
        store.save(state) // Entitlement update after VM snapshot.
        let before = store.load()
        XCTAssertFalse(vm.applyScene(scene.id))
        XCTAssertEqual(store.load(), before)
        XCTAssertTrue(vm.showPaywall)
        XCTAssertEqual(scheduler.cancelCount, 0)
        XCTAssertEqual(lockScheduler.stopCount, 0)
        XCTAssertTrue(lockScheduler.started.isEmpty)
        XCTAssertTrue(restrictions.appliedPlans.isEmpty)
    }

    func testSceneSaveRenameDeleteKeepsOnlyRuleConfiguration() throws {
        var state = LockerState()
        state.pinHint = "private hint"
        state.pinHash = Data([44])
        state.isVIP = true
        state.guestSelectionData = Data([55])
        store.save(state)
        vm.reloadFromAppGroup()
        XCTAssertFalse(vm.saveScene(name: "  \n"))
        XCTAssertTrue(vm.saveScene(name: "  Study  "))
        let scene = try XCTUnwrap(store.load().scenes.first)
        XCTAssertEqual(scene.name, "Study")
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(scene)) as? [String: Any])
        for key in ["pinHint", "pinHash", "pinSalt", "isVIP", "guestSelectionData", "temporaryUnlockUntil", "guestModeUntil"] {
            XCTAssertNil(json[key], "Scene must not capture \(key)")
        }
        vm.renameScene(scene.id, name: "  Sleep  ")
        XCTAssertEqual(store.load().scenes.first?.name, "Sleep")
        vm.deleteScene(scene.id)
        XCTAssertTrue(store.load().scenes.isEmpty)
        XCTAssertNil(store.load().activeSceneID)
        XCTAssertEqual(store.load().pinHint, "private hint")
    }

    func testSceneApplyClearsPauseAndSkipPreservesFreshIndependentState() throws {
        var saved = LockerState()
        saved.isLockEnabled = true
        let scene = GuardScene(name: "Study", state: saved)
        var state = LockerState()
        state.scenes = [scene]
        state.scheduleSkippedDay = now
        store.save(state)
        store.saveTemporarySession(TemporaryAccessSession(until: now.addingTimeInterval(900), selectionData: Data([1])))
        store.saveGuestModeUntil(now.addingTimeInterval(1800))
        vm.reloadFromAppGroup()
        state = store.load()
        state.pinHint = "updated elsewhere"
        state.isVIP = true
        store.save(state)
        XCTAssertTrue(vm.applyScene(scene.id))
        let result = store.load()
        XCTAssertTrue(result.isLockEnabled)
        XCTAssertEqual(result.activeSceneID, scene.id)
        XCTAssertNil(result.scheduleSkippedDay)
        XCTAssertNil(result.temporaryUnlockUntil)
        XCTAssertNil(result.temporaryUnlockSelectionData)
        XCTAssertEqual(result.guestModeUntil, now.addingTimeInterval(1800))
        XCTAssertEqual(result.pinHint, "updated elsewhere")
        XCTAssertTrue(result.isVIP)
        XCTAssertEqual(scheduler.cancelCount, 1)
        XCTAssertEqual(guestScheduler.cancelCount, 0)
    }

    func testCustomDurationBoundsAndEmptyScopedSelection() {
        for minutes in [Int.min, -1, 0, 14, 721, Int.max] {
            XCTAssertFalse(vm.temporaryUnlock(minutes: minutes, selection: nil))
        }
        XCTAssertFalse(vm.temporaryUnlock(minutes: 30, selection: FamilyActivitySelection()))
        XCTAssertTrue(scheduler.scheduled.isEmpty)
        XCTAssertNil(store.load().temporaryUnlockUntil)
        for minutes in [15, 17, 720] {
            XCTAssertTrue(vm.temporaryUnlock(minutes: minutes, selection: nil))
            XCTAssertEqual(store.load().temporaryUnlockUntil, now.addingTimeInterval(TimeInterval(minutes * 60)))
        }
        XCTAssertEqual(scheduler.scheduled.count, 3)
    }
}
