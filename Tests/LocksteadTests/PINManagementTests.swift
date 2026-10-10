import XCTest
@testable import Lockstead

final class PINManagementTests: XCTestCase {
    func testChangeRequiresOldPINAndConfirmation() {
        let store = InMemoryPINCredentialStore()
        let manager = PINManager(store: store, hasher: .testFast)
        var state = LockerState()
        XCTAssertTrue(manager.set(pin: "123456", hint: "old", in: &state))
        XCTAssertEqual(manager.change(oldPIN: "000000", newPIN: "654321", confirmation: "654321", hint: "new", state: &state), .verification(.wrongPIN))
        XCTAssertEqual(manager.change(oldPIN: "123456", newPIN: "654321", confirmation: "654322", hint: "new", state: &state), .mismatch)
        XCTAssertEqual(state.pinHint, "old")
        XCTAssertEqual(manager.change(oldPIN: "123456", newPIN: "654321", confirmation: "654321", hint: "new", state: &state), .success)
        XCTAssertEqual(manager.verify(pin: "123456", state: &state), .wrongPIN)
        XCTAssertEqual(manager.verify(pin: "654321", state: &state), .success)
        XCTAssertEqual(state.pinHint, "new")
    }

    func testHintChangeSharesLoginLockout() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let store = InMemoryPINCredentialStore()
        let manager = PINManager(now: { now }, store: store, hasher: .testFast)
        var state = LockerState()
        manager.set(pin: "123456", hint: "old", in: &state)
        for _ in 0..<4 { _ = manager.verify(pin: "000000", state: &state) }
        XCTAssertEqual(manager.updateHint(oldPIN: "000000", hint: nil, state: &state), .verification(.lockedOut(until: now.addingTimeInterval(60))))
        XCTAssertEqual(manager.change(oldPIN: "123456", newPIN: "654321", confirmation: "654321", hint: nil, state: &state), .verification(.lockedOut(until: now.addingTimeInterval(60))))
        XCTAssertEqual(state.pinHint, "old")
    }

    func testHintCanBeRemovedWithoutChangingPIN() {
        let store = InMemoryPINCredentialStore()
        let manager = PINManager(store: store, hasher: .testFast)
        var state = LockerState()
        manager.set(pin: "123456", hint: "old", in: &state)
        let credential = store.credential
        XCTAssertEqual(manager.updateHint(oldPIN: "123456", hint: nil, state: &state), .success)
        XCTAssertNil(state.pinHint)
        XCTAssertEqual(store.credential, credential)
    }

    func testFailedCooldownWriteNeverReplacesCredential() {
        let store = FailingPINCredentialStore()
        let manager = PINManager(store: store, hasher: .testFast)
        var state = LockerState()
        manager.set(pin: "123456", hint: "old", in: &state)
        let original = store.credential
        store.failsLockoutSave = true
        XCTAssertFalse(manager.set(pin: "654321", hint: "new", in: &state))
        XCTAssertEqual(store.credential, original)
        XCTAssertEqual(state.pinHint, "old")
        XCTAssertEqual(manager.change(oldPIN: "123456", newPIN: "654321", confirmation: "654321", hint: nil, state: &state), .verification(.storageFailure))
    }

    func testFailedCredentialWritePreservesOldPINAndHint() {
        let store = FailingPINCredentialStore()
        let manager = PINManager(store: store, hasher: .testFast)
        var state = LockerState()
        manager.set(pin: "123456", hint: "old", in: &state)
        store.failsCredentialSave = true
        XCTAssertEqual(manager.change(oldPIN: "123456", newPIN: "654321", confirmation: "654321", hint: "new", state: &state), .storageFailure)
        XCTAssertEqual(state.pinHint, "old")
        XCTAssertEqual(manager.verify(pin: "123456", state: &state), .success)
        XCTAssertEqual(manager.verify(pin: "654321", state: &state), .wrongPIN)
    }

    func testFailedAttemptPersistenceRetainsFallbackCooldown() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let store = FailingPINCredentialStore()
        let manager = PINManager(now: { now }, store: store, hasher: .testFast)
        var state = LockerState()
        manager.set(pin: "123456", hint: nil, in: &state)
        store.failsLockoutSave = true
        for _ in 0..<4 {
            XCTAssertEqual(manager.verify(pin: "000000", state: &state), .storageFailure)
        }
        XCTAssertEqual(manager.verify(pin: "000000", state: &state), .lockedOut(until: now.addingTimeInterval(60)))
        XCTAssertEqual(manager.verify(pin: "123456", state: &state), .lockedOut(until: now.addingTimeInterval(60)))
        XCTAssertEqual(manager.lockoutUntil(in: state), now.addingTimeInterval(60))
    }
}
