import XCTest
import CryptoKit
@testable import Lockstead

final class PINManagerTests: XCTestCase {
    private var now: Date!
    private var pm: PINManager!
    private var credentialStore: InMemoryPINCredentialStore!
    private var state: LockerState!

    override func setUp() {
        super.setUp()
        now = Date(timeIntervalSince1970: 1_700_000_000)
        credentialStore = InMemoryPINCredentialStore()
        pm = PINManager(now: { self.now }, store: credentialStore, hasher: .testFast)
        state = LockerState()
        XCTAssertTrue(pm.set(pin: "123456", hint: "hint", in: &state))
    }

    func testFormatValidation() {
        XCTAssertTrue(PINManager.isValidFormat("123456"))
        XCTAssertFalse(PINManager.isValidFormat("12345"))     // 太短
        XCTAssertFalse(PINManager.isValidFormat("1234567"))  // 太长
        XCTAssertFalse(PINManager.isValidFormat("12345a"))   // 非数字
    }

    func testSetStoresDerivedCredentialOutsideStateBlob() throws {
        let credential = try XCTUnwrap(credentialStore.loadCredential())
        XCTAssertNil(state.pinHash)          // 凭据不再落 App Group 状态档
        XCTAssertNil(state.pinSalt)
        XCTAssertEqual(state.pinHint, "hint")
        XCTAssertGreaterThanOrEqual(credential.iterations, 1)
        XCTAssertNil(String(data: credential.hash, encoding: .utf8)) // 不是明文
    }

    func testSamePINDifferentSaltDifferentHash() throws {
        let otherStore = InMemoryPINCredentialStore()
        var otherState = LockerState()
        PINManager(now: { self.now }, store: otherStore, hasher: .testFast)
            .set(pin: "123456", hint: nil, in: &otherState)

        XCTAssertNotEqual(
            try XCTUnwrap(credentialStore.loadCredential()).hash,
            try XCTUnwrap(otherStore.loadCredential()).hash
        )
    }

    func testVerifyCorrectPIN() {
        XCTAssertEqual(pm.verify(pin: "123456", state: &state), .success)
        XCTAssertEqual(credentialStore.loadLockout(), .none)
    }

    func testFifthFailureTriggersLockout() {
        for _ in 1...4 {
            guard case .wrongPIN = pm.verify(pin: "000000", state: &state) else {
                return XCTFail("前 4 次应为 wrongPIN")
            }
        }
        guard case .lockedOut(let until) = pm.verify(pin: "000000", state: &state) else {
            return XCTFail("第 5 次应锁定")
        }
        XCTAssertEqual(until.timeIntervalSince(now), 60, accuracy: 0.1)
        XCTAssertEqual(credentialStore.loadLockout().failedAttempts, 5)
    }

    func testLockoutDoublesAndCaps() {
        for _ in 1...5 { _ = pm.verify(pin: "000000", state: &state) }
        now = now.addingTimeInterval(61) // 第一次冷却结束
        guard case .lockedOut(let until2) = pm.verify(pin: "000000", state: &state) else {
            return XCTFail()
        }
        XCTAssertEqual(until2.timeIntervalSince(now), 120, accuracy: 0.1)
        credentialStore.saveLockout(PINLockout(failedAttempts: 20, lockoutUntil: nil))
        guard case .lockedOut(let untilCap) = pm.verify(pin: "000000", state: &state) else {
            return XCTFail()
        }
        XCTAssertLessThanOrEqual(untilCap.timeIntervalSince(now), 3600)
    }

    func testVerifyDuringLockoutReturnsLockedOutWithoutCounting() {
        for _ in 1...5 { _ = pm.verify(pin: "000000", state: &state) }
        let attempts = credentialStore.loadLockout().failedAttempts
        guard case .lockedOut = pm.verify(pin: "123456", state: &state) else {
            return XCTFail("冷却期内即使 PIN 正确也应拒绝")
        }
        XCTAssertEqual(credentialStore.loadLockout().failedAttempts, attempts)
    }

    func testSuccessAfterLockoutExpiresResetsCounter() {
        for _ in 1...5 { _ = pm.verify(pin: "000000", state: &state) }
        now = now.addingTimeInterval(61)
        XCTAssertEqual(pm.verify(pin: "123456", state: &state), .success)
        XCTAssertEqual(credentialStore.loadLockout(), .none)
    }

    func testMissingCredentialAndNoLegacyReturnsWrongPINWithoutCounting() {
        let freshStore = InMemoryPINCredentialStore()
        let freshPM = PINManager(now: { self.now }, store: freshStore, hasher: .testFast)
        var emptyState = LockerState()
        XCTAssertEqual(freshPM.verify(pin: "123456", state: &emptyState), .wrongPIN)
        XCTAssertEqual(freshStore.loadLockout(), .none) // 未设置 PIN 时不计失败
    }

    // MARK: - 旧版落盘凭据迁移(单次 SHA256 → PBKDF2 + Keychain)

    private func legacyState(pin: String, failedAttempts: Int = 0) -> LockerState {
        let salt = Data(repeating: 0xAB, count: 16)
        var state = LockerState()
        state.pinSalt = salt
        state.pinHash = Data(SHA256.hash(data: salt + Data(pin.utf8)))
        state.failedPINAttempts = failedAttempts
        return state
    }

    // 迁移场景需要空 Keychain:setUp 的 store 里已有凭据,这里用全新 store
    private func freshPM() -> (PINManager, InMemoryPINCredentialStore) {
        let store = InMemoryPINCredentialStore()
        return (PINManager(now: { self.now }, store: store, hasher: .testFast), store)
    }

    func testLegacyBlobCredentialMigratesToKeychainOnSuccess() {
        let (freshPM, freshStore) = freshPM()
        var legacyState = legacyState(pin: "123456", failedAttempts: 2)
        legacyState.pinLockoutUntil = now.addingTimeInterval(-10) // 已过期的冷却

        XCTAssertEqual(freshPM.verify(pin: "123456", state: &legacyState), .success)
        XCTAssertNotNil(freshStore.loadCredential()) // 已换 PBKDF2 迁入 Keychain
        XCTAssertNil(legacyState.pinSalt)            // 旧档凭据清除
        XCTAssertNil(legacyState.pinHash)
        XCTAssertEqual(legacyState.failedPINAttempts, 0)
        XCTAssertNil(legacyState.pinLockoutUntil)
    }

    func testLegacyWrongPINCountsFailureInKeychain() {
        let (freshPM, freshStore) = freshPM()
        var legacyState = legacyState(pin: "123456")

        guard case .wrongPIN = freshPM.verify(pin: "654321", state: &legacyState) else {
            return XCTFail("错误 PIN 必须拒绝")
        }
        XCTAssertEqual(freshStore.loadLockout().failedAttempts, 1)
        XCTAssertNotNil(legacyState.pinSalt) // 未验证通过:旧凭据保留,不迁移
    }

    func testLegacyLockoutCountersAreAdopted() {
        let (freshPM, freshStore) = freshPM()
        var legacyState = legacyState(pin: "123456", failedAttempts: 5)
        legacyState.pinLockoutUntil = now.addingTimeInterval(300)

        XCTAssertEqual(freshPM.verify(pin: "123456", state: &legacyState),
                       .lockedOut(until: now.addingTimeInterval(300)))
        // 冷却已同步进 Keychain:重启后依然生效
        XCTAssertEqual(freshStore.loadLockout().lockoutUntil, now.addingTimeInterval(300))
    }

    // MARK: - Keychain 写失败不得当作成功(静默失败会清凭据、绕过锁屏)

    func testSetReturnsFalseAndKeepsLegacyWhenKeychainWriteFails() {
        let failingStore = FailingPINCredentialStore()
        failingStore.failsCredentialSave = true
        let failingPM = PINManager(now: { self.now }, store: failingStore, hasher: .testFast)

        var legacyState = legacyState(pin: "123456")
        XCTAssertFalse(failingPM.set(pin: "654321", hint: nil, in: &legacyState))
        XCTAssertNotNil(legacyState.pinSalt) // 旧凭据原样保留
        XCTAssertNotNil(legacyState.pinHash)
        XCTAssertNil(failingStore.loadCredential())
    }

    func testSetReturnsFalseWhenLockoutWriteFails() {
        let failingStore = FailingPINCredentialStore()
        failingStore.failsLockoutSave = true
        let failingPM = PINManager(now: { self.now }, store: failingStore, hasher: .testFast)

        // 部分写入(凭据成功、冷却失败)也返回 false:状态档不得有任何改动
        var legacyState = legacyState(pin: "123456")
        XCTAssertFalse(failingPM.set(pin: "654321", hint: "新提示", in: &legacyState))
        XCTAssertNotNil(legacyState.pinSalt) // 旧凭据原样保留
        XCTAssertNotNil(legacyState.pinHash)
        XCTAssertNil(legacyState.pinHint)    // 提示文案也未写入
    }

    func testMigrationKeepsLegacyWhenKeychainWriteFails() {
        let failingStore = FailingPINCredentialStore()
        failingStore.failsCredentialSave = true
        let failingPM = PINManager(now: { self.now }, store: failingStore, hasher: .testFast)
        var legacyState = legacyState(pin: "123456")

        XCTAssertEqual(failingPM.verify(pin: "123456", state: &legacyState), .success)
        XCTAssertNotNil(legacyState.pinSalt) // 迁移没写进去:旧凭据必须保留,下次验证重试
        XCTAssertNotNil(legacyState.pinHash)
        XCTAssertNil(failingStore.loadCredential())
    }

    // MARK: - hasPIN / lockoutUntil

    func testHasPINReflectsKeychainAndLegacyBlob() {
        let freshStore = InMemoryPINCredentialStore()
        let freshPM = PINManager(store: freshStore, hasher: .testFast)
        XCTAssertFalse(freshPM.hasPIN(in: LockerState()))

        var seeded = LockerState()
        freshPM.set(pin: "123456", hint: nil, in: &seeded)
        XCTAssertTrue(freshPM.hasPIN(in: LockerState()))

        var legacy = LockerState()
        legacy.pinSalt = Data([1])
        legacy.pinHash = Data([2])
        XCTAssertTrue(PINManager(store: InMemoryPINCredentialStore(), hasher: .testFast).hasPIN(in: legacy))
    }

    func testLockoutUntilReflectsKeychainState() {
        XCTAssertNil(pm.lockoutUntil())
        credentialStore.saveLockout(PINLockout(failedAttempts: 5, lockoutUntil: now.addingTimeInterval(120)))
        XCTAssertEqual(pm.lockoutUntil(), now.addingTimeInterval(120))
        credentialStore.saveLockout(PINLockout(failedAttempts: 5, lockoutUntil: now.addingTimeInterval(-1)))
        XCTAssertNil(pm.lockoutUntil()) // 已过期
    }

    // MARK: - 真实 PBKDF2 派生

    func testPBKDF2DerivesDeterministic32Bytes() {
        let salt = Data(repeating: 0x11, count: 16)
        let a = PINKeyDerivation.derive(pin: "123456", salt: salt, iterations: 1000)
        let b = PINKeyDerivation.derive(pin: "123456", salt: salt, iterations: 1000)
        XCTAssertEqual(a, b) // 同盐同 PIN 结果确定
        XCTAssertEqual(a?.count, 32)
        XCTAssertNotEqual(PINKeyDerivation.derive(pin: "654321", salt: salt, iterations: 1000), a)
    }

    func testCalibratedIterationsMeetMinimum() {
        XCTAssertGreaterThanOrEqual(PINKeyDerivation.calibratedIterations,
                                    PINKeyDerivation.minimumIterations)
    }
}
