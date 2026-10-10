import Foundation

/// A scene stores rules only. Credentials, purchases and active timers never travel with it.
struct GuardScene: Codable, Equatable, Identifiable {
    var id = UUID()
    var name: String
    var selectionData: Data?
    var lockMode: LockMode
    var isLockEnabled: Bool
    var scheduleEnabled: Bool
    var scheduleRules: [ScheduleRule]

    init(name: String, state: LockerState) {
        self.name = name
        selectionData = state.selectionData
        lockMode = state.lockMode
        isLockEnabled = state.isLockEnabled
        scheduleEnabled = state.scheduleEnabled
        scheduleRules = state.effectiveScheduleRules
    }

    func matches(_ state: LockerState) -> Bool {
        selectionData == state.selectionData && lockMode == state.lockMode
            && isLockEnabled == state.isLockEnabled && scheduleEnabled == state.scheduleEnabled
            && scheduleRules == state.effectiveScheduleRules
    }
}

struct TemporaryAccessSession: Codable, Equatable {
    var until: Date
    /// nil pauses the full rule; a nonnil payload always means selected apps only.
    var selectionData: Data?
}
