import XCTest
@testable import Lockstead

final class LockerStateTests: XCTestCase {
    private var store: AppGroupStore!

    override func setUp() {
        super.setUp()
        let defaults = UserDefaults(suiteName: "unit-test-\(UUID().uuidString)")!
        store = AppGroupStore(defaults: defaults)
    }

    func testLoadReturnsDefaultStateWhenEmpty() {
        let state = store.load()
        XCTAssertEqual(state, LockerState())
        XCTAssertFalse(state.isLockEnabled)
        XCTAssertFalse(state.isVIP)
        XCTAssertNil(state.pinHash)
    }

    func testSaveThenLoadRoundTrips() {
        var state = LockerState()
        state.isLockEnabled = true
        state.isVIP = true
        state.pinHint = "生日"
        store.save(state)
        XCTAssertEqual(store.load(), state)
    }

    // 限时字段走独立键:主档 save 不携带,分键写入后 load 再合并
    func testTimedModesLiveInSeparateKey() {
        let temporaryUnlock = Date(timeIntervalSince1970: 1_800_000_000)
        let guestMode = Date(timeIntervalSince1970: 1_800_000_600)

        var state = LockerState()
        state.temporaryUnlockUntil = temporaryUnlock
        state.guestModeUntil = guestMode
        store.save(state) // 主档刻意不写限时字段
        XCTAssertNil(store.load().temporaryUnlockUntil)
        XCTAssertNil(store.load().guestModeUntil)

        store.saveTimed(TimedModeState(temporaryUnlockUntil: temporaryUnlock,
                                       guestModeUntil: guestMode))
        let loaded = store.load()
        XCTAssertEqual(loaded.temporaryUnlockUntil, temporaryUnlock)
        XCTAssertEqual(loaded.guestModeUntil, guestMode)
    }

    // 旧版:限时字段写在主档里。首次 load 迁往独立键,数值不丢
    func testLegacyTimedFieldsMigrateToTimedKeyOnLoad() {
        let defaults = UserDefaults(suiteName: "unit-test-timed-migration-\(UUID().uuidString)")!
        let legacyJSON = """
        {"isLockEnabled":true,"temporaryUnlockUntil":1800000000,"guestModeUntil":1800000060}
        """
        defaults.set(Data(legacyJSON.utf8), forKey: AppGroup.stateKey)
        let store = AppGroupStore(defaults: defaults)

        // Date 的默认 Codable 编码基准是 2001-01-01(reference date)
        let expectedUnlock = Date(timeIntervalSinceReferenceDate: 1_800_000_000)
        let expectedGuest = Date(timeIntervalSinceReferenceDate: 1_800_000_060)
        let first = store.load()
        XCTAssertEqual(first.temporaryUnlockUntil, expectedUnlock)
        XCTAssertEqual(first.guestModeUntil, expectedGuest)
        // 迁移后 timed 键已存在,再 load 依旧一致
        XCTAssertEqual(store.load(), first)
    }

    // 整档损坏时回退上一份完好备份,而不是静默回落全新状态(等于清空用户配置)
    func testCorruptPrimaryRecoversFromBackup() {
        let defaults = UserDefaults(suiteName: "unit-test-backup-\(UUID().uuidString)")!
        let store = AppGroupStore(defaults: defaults)

        var v1 = LockerState()
        v1.isLockEnabled = true
        store.save(v1)
        var v2 = v1
        v2.scheduleEnabled = true
        store.save(v2)

        defaults.set(Data("corrupt".utf8), forKey: AppGroup.stateKey)
        let recovered = store.load()
        XCTAssertTrue(recovered.isLockEnabled)      // 备份档 v1 仍在
        XCTAssertFalse(recovered.scheduleEnabled)   // v2 的增量丢失,但配置没有整体清空
    }

    // 旧版本存档没有后加的键:必须能解码且保住 PIN,新开关取默认值
    func testLegacyPayloadWithoutNewKeysDecodesAndPreservesPIN() {
        let defaults = UserDefaults(suiteName: "unit-test-legacy-\(UUID().uuidString)")!
        let legacyJSON = """
        {"isLockEnabled":true,"isVIP":true,"pinHash":"AQID","pinSalt":"BAUG","failedPINAttempts":2}
        """
        defaults.set(Data(legacyJSON.utf8), forKey: AppGroup.stateKey)
        let s = AppGroupStore(defaults: defaults).load()
        XCTAssertTrue(s.isLockEnabled)
        XCTAssertTrue(s.isVIP)
        XCTAssertEqual(s.pinHash, Data([1, 2, 3]))
        XCTAssertEqual(s.pinSalt, Data([4, 5, 6]))
        XCTAssertEqual(s.failedPINAttempts, 2)
        XCTAssertFalse(s.isDiscreetShieldEnabled)
        XCTAssertFalse(s.isBiometricUnlockEnabled)
        XCTAssertEqual(s.loginMode, .pin)
        XCTAssertEqual(s.lockMode, .blocklist)
        XCTAssertFalse(s.scheduleEnabled)
        XCTAssertEqual(s.scheduleStartMinutes, 21 * 60)
        XCTAssertEqual(s.scheduleEndMinutes, 7 * 60)
        XCTAssertNil(s.guestSelectionData)
        XCTAssertNil(s.guestModeUntil)
    }

    // 未来新增的未知 lockMode 值降级为默认,不抛错整档失败
    func testUnknownLockModeFallsBackToBlocklist() {
        let defaults = UserDefaults(suiteName: "unit-test-mode-\(UUID().uuidString)")!
        let json = """
        {"isLockEnabled":true,"lockMode":"somethingNew"}
        """
        defaults.set(Data(json.utf8), forKey: AppGroup.stateKey)
        let s = AppGroupStore(defaults: defaults).load()
        XCTAssertTrue(s.isLockEnabled) // 整档没有失败
        XCTAssertEqual(s.lockMode, .blocklist)
    }

    func testLoginModeRoundTripsAndUnknownValueFallsBackToPIN() {
        var state = LockerState()
        state.loginMode = .calculator
        store.save(state)
        XCTAssertEqual(store.load().loginMode, .calculator)

        let defaults = UserDefaults(suiteName: "unit-test-login-mode-\(UUID().uuidString)")!
        defaults.set(Data(#"{"loginMode":"futureMode"}"#.utf8), forKey: AppGroup.stateKey)
        XCTAssertEqual(AppGroupStore(defaults: defaults).load().loginMode, .pin)
    }

    func testNewFlagsRoundTrip() {
        var state = LockerState()
        state.isDiscreetShieldEnabled = true
        state.isBiometricUnlockEnabled = true
        store.save(state)
        XCTAssertEqual(store.load(), state)
    }

    func testLegacyHideFlagMigratesToLock() {
        let defaults = UserDefaults(suiteName: "unit-test-strict-block-migration-\(UUID().uuidString)")!
        let legacyJSON = """
        {"isHideEnabled":true}
        """
        defaults.set(Data(legacyJSON.utf8), forKey: AppGroup.stateKey)

        XCTAssertTrue(AppGroupStore(defaults: defaults).load().isLockEnabled)
    }

    func testPreviousStrictBlockMigratesToLock() {
        let defaults = UserDefaults(suiteName: "unit-test-single-lock-migration-\(UUID().uuidString)")!
        let previousJSON = """
        {"isLockEnabled":false,"isStrictBlockEnabled":true}
        """
        defaults.set(Data(previousJSON.utf8), forKey: AppGroup.stateKey)

        XCTAssertTrue(AppGroupStore(defaults: defaults).load().isLockEnabled)
    }

    func testCorruptDataFallsBackToDefault() {
        let defaults = UserDefaults(suiteName: "unit-test-corrupt-\(UUID().uuidString)")!
        defaults.set(Data("not json".utf8), forKey: AppGroup.stateKey)
        let s = AppGroupStore(defaults: defaults)
        XCTAssertEqual(s.load(), LockerState())
    }
}
