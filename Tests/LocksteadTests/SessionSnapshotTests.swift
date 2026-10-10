import XCTest
@testable import Lockstead

private final class ChangingSessionDefaults: UserDefaults {
    var firstSession: Data?
    var sessionReads = 0

    override func data(forKey defaultName: String) -> Data? {
        guard defaultName == AppGroup.temporarySessionKey else { return super.data(forKey: defaultName) }
        sessionReads += 1
        // Simulate an extension clearing the session immediately after the first read.
        return sessionReads == 1 ? firstSession : nil
    }
}

final class SessionSnapshotTests: XCTestCase {
    func testConcurrentClearCannotTurnScopedAccessIntoFullAccess() throws {
        let suite = "session-snapshot-\(UUID().uuidString)"
        let defaults = ChangingSessionDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let session = TemporaryAccessSession(until: Date().addingTimeInterval(1800), selectionData: Data([1, 2]))
        let encoded = try JSONEncoder().encode(session)
        defaults.set(encoded, forKey: AppGroup.temporarySessionKey)
        defaults.firstSession = encoded
        defaults.sessionReads = 0

        let state = AppGroupStore(defaults: defaults).load()

        XCTAssertEqual(defaults.sessionReads, 1)
        XCTAssertEqual(state.temporaryUnlockUntil, session.until)
        XCTAssertEqual(state.temporaryUnlockSelectionData, session.selectionData)
        XCTAssertTrue(RestrictionsPlan.lockActive(state: {
            var protected = state
            protected.isLockEnabled = true
            return protected
        }(), now: Date()))
    }
}
