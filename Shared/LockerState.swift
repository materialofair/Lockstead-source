import Foundation

enum LockMode: String, Codable {
    case blocklist // 锁定选中的 App(默认)
    case allowlist // 只放行选中的 App,其余全锁(VIP)
}

enum LoginMode: String, Codable {
    case pin
    case calculator
}

struct LockerState: Equatable {
    var selectionData: Data? = nil
    var isLockEnabled = false
    var isVIP = false
    var isAntiRemovalEnabled = false
    var temporaryUnlockSelectionData: Data? = nil // nil = all apps; nonnil = scoped access
    var temporaryUnlockUntil: Date? = nil
    var pinSalt: Data? = nil
    var pinHash: Data? = nil
    var pinHint: String? = nil
    var failedPINAttempts = 0
    var pinLockoutUntil: Date? = nil
    var isDiscreetShieldEnabled = false
    var isBiometricUnlockEnabled = false
    var loginMode: LoginMode = .pin
    var lockMode: LockMode = .blocklist
    var scheduleEnabled = false
    var scheduleStartMinutes = 21 * 60 // 21:00
    var scheduleEndMinutes = 7 * 60    // 07:00(跨夜)
    var scheduleRules: [ScheduleRule] = [] // Empty means the legacy daily window.
    var scheduleSkippedDay: Date? = nil
    var scheduleRegistrationFailed = false
    var scenes: [GuardScene] = []
    var activeSceneID: UUID? = nil

    var effectiveScheduleRules: [ScheduleRule] {
        scheduleRules.isEmpty
            ? [ScheduleRule(id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
                            weekdays: Set(1...7), startMinutes: scheduleStartMinutes, endMinutes: scheduleEndMinutes)]
            : scheduleRules
    }

    var guestSelectionData: Data? = nil // 访客模式白名单(与主选择分开)
    var guestModeUntil: Date? = nil     // 访客模式截止(必须限时,无「无限期」)
}

extension LockerState: Codable {
    private enum CodingKeys: String, CodingKey {
        case selectionData, isLockEnabled, isVIP, isAntiRemovalEnabled
        case temporaryUnlockUntil, pinSalt, pinHash, pinHint, failedPINAttempts, pinLockoutUntil
        case isDiscreetShieldEnabled, isBiometricUnlockEnabled
        case loginMode
        case lockMode, scheduleEnabled, scheduleStartMinutes, scheduleEndMinutes
        case guestSelectionData, guestModeUntil
        case scheduleRules, scheduleSkippedDay, scheduleRegistrationFailed, scenes, activeSceneID
    }

    private enum LegacyCodingKeys: String, CodingKey {
        case isHideEnabled, isStrictBlockEnabled
    }

    // 逐键 decodeIfPresent:旧版本存档缺新增键时不能整档解码失败——
    // 那会让 load() 回落到全新状态,连带清掉用户的 PIN 与锁定配置。
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let legacy = try decoder.container(keyedBy: LegacyCodingKeys.self)
        selectionData = try c.decodeIfPresent(Data.self, forKey: .selectionData)
        let previousStrictBlock = try legacy.decodeIfPresent(Bool.self, forKey: .isStrictBlockEnabled) ?? false
        let previousHide = try legacy.decodeIfPresent(Bool.self, forKey: .isHideEnabled) ?? false
        isLockEnabled = (try c.decodeIfPresent(Bool.self, forKey: .isLockEnabled) ?? false)
            || previousStrictBlock
            || previousHide
        isVIP = try c.decodeIfPresent(Bool.self, forKey: .isVIP) ?? false
        isAntiRemovalEnabled = try c.decodeIfPresent(Bool.self, forKey: .isAntiRemovalEnabled) ?? false
        temporaryUnlockUntil = try c.decodeIfPresent(Date.self, forKey: .temporaryUnlockUntil)
        pinSalt = try c.decodeIfPresent(Data.self, forKey: .pinSalt)
        pinHash = try c.decodeIfPresent(Data.self, forKey: .pinHash)
        pinHint = try c.decodeIfPresent(String.self, forKey: .pinHint)
        failedPINAttempts = try c.decodeIfPresent(Int.self, forKey: .failedPINAttempts) ?? 0
        pinLockoutUntil = try c.decodeIfPresent(Date.self, forKey: .pinLockoutUntil)
        isDiscreetShieldEnabled = try c.decodeIfPresent(Bool.self, forKey: .isDiscreetShieldEnabled) ?? false
        isBiometricUnlockEnabled = try c.decodeIfPresent(Bool.self, forKey: .isBiometricUnlockEnabled) ?? false
        loginMode = (try c.decodeIfPresent(String.self, forKey: .loginMode))
            .flatMap(LoginMode.init(rawValue:)) ?? .pin
        // 经 String 中转:未来新增的未知模式值降级为默认,而不是抛错整档失败
        lockMode = (try c.decodeIfPresent(String.self, forKey: .lockMode))
            .flatMap(LockMode.init(rawValue:)) ?? .blocklist
        scheduleEnabled = try c.decodeIfPresent(Bool.self, forKey: .scheduleEnabled) ?? false
        scheduleStartMinutes = try c.decodeIfPresent(Int.self, forKey: .scheduleStartMinutes) ?? 21 * 60
        scheduleEndMinutes = try c.decodeIfPresent(Int.self, forKey: .scheduleEndMinutes) ?? 7 * 60
        scheduleRules = try c.decodeIfPresent([ScheduleRule].self, forKey: .scheduleRules) ?? []
        scheduleSkippedDay = try c.decodeIfPresent(Date.self, forKey: .scheduleSkippedDay)
        scheduleRegistrationFailed = try c.decodeIfPresent(Bool.self, forKey: .scheduleRegistrationFailed) ?? false
        scenes = try c.decodeIfPresent([GuardScene].self, forKey: .scenes) ?? []
        activeSceneID = try c.decodeIfPresent(UUID.self, forKey: .activeSceneID)
        guestSelectionData = try c.decodeIfPresent(Data.self, forKey: .guestSelectionData)
        guestModeUntil = try c.decodeIfPresent(Date.self, forKey: .guestModeUntil)
    }

    // encode 刻意不写 temporaryUnlockUntil/guestModeUntil:限时字段单独存 timed 键,
    // 避免主 App 与 ActivityMonitor 扩展对同一整档做读改写时互相覆写对方字段。
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(selectionData, forKey: .selectionData)
        try c.encode(isLockEnabled, forKey: .isLockEnabled)
        try c.encode(isVIP, forKey: .isVIP)
        try c.encode(isAntiRemovalEnabled, forKey: .isAntiRemovalEnabled)
        try c.encodeIfPresent(pinSalt, forKey: .pinSalt)
        try c.encodeIfPresent(pinHash, forKey: .pinHash)
        try c.encodeIfPresent(pinHint, forKey: .pinHint)
        try c.encode(failedPINAttempts, forKey: .failedPINAttempts)
        try c.encodeIfPresent(pinLockoutUntil, forKey: .pinLockoutUntil)
        try c.encode(isDiscreetShieldEnabled, forKey: .isDiscreetShieldEnabled)
        try c.encode(isBiometricUnlockEnabled, forKey: .isBiometricUnlockEnabled)
        try c.encode(loginMode, forKey: .loginMode)
        try c.encode(lockMode, forKey: .lockMode)
        try c.encode(scheduleEnabled, forKey: .scheduleEnabled)
        try c.encode(scheduleStartMinutes, forKey: .scheduleStartMinutes)
        try c.encode(scheduleEndMinutes, forKey: .scheduleEndMinutes)
        try c.encode(scheduleRules, forKey: .scheduleRules)
        try c.encodeIfPresent(scheduleSkippedDay, forKey: .scheduleSkippedDay)
        try c.encode(scheduleRegistrationFailed, forKey: .scheduleRegistrationFailed)
        try c.encode(scenes, forKey: .scenes)
        try c.encodeIfPresent(activeSceneID, forKey: .activeSceneID)
        try c.encodeIfPresent(guestSelectionData, forKey: .guestSelectionData)
    }
}
