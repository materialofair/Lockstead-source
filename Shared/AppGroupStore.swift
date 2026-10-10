import Foundation
import os

/// App Group 状态持久化,键分治消除跨进程整档覆写竞态:
/// - `stateKey`:主状态(选择、开关、提示等)——只由主 App 写(扩展目标也编译本文件,
///   但写主档的边界只靠这条约定,扩展内勿调用 save(_:));
/// - 临时放行会话与访客截止分开存；放行范围和截止时间共用一份原子快照,任何一方回写
///   都不再波及另一字段(主 App 与 ActivityMonitor 扩展都可能写);
/// 主档另存一份备份键:整档损坏时回退上一份完好状态,而不是静默回落全新配置(等于清空保护)。
struct AppGroupStore {
    private static let logger = Logger(subsystem: "zeronet.lockstead", category: "AppGroupStore")

    private let defaults: UserDefaults

    init(defaults: UserDefaults = AppGroup.defaults) {
        self.defaults = defaults
    }

    func load() -> LockerState {
        var state = loadMainBlob()
        if !defaults.bool(forKey: AppGroup.timedMigrationKey),
           defaults.object(forKey: AppGroup.timedStateKey) == nil,
           state.temporaryUnlockUntil != nil || state.guestModeUntil != nil {
            // 一次性迁移:旧版把限时字段写在主档里,迁往独立键
            saveTimed(TimedModeState(temporaryUnlockUntil: state.temporaryUnlockUntil,
                                     guestModeUntil: state.guestModeUntil))
        }
        let timed = loadTimed()
        state.temporaryUnlockUntil = timed.temporaryUnlockUntil
        state.guestModeUntil = timed.guestModeUntil
        state.temporaryUnlockSelectionData = timed.temporaryUnlockSelectionData
        return state
    }

    func save(_ state: LockerState) {
        guard let data = try? JSONEncoder().encode(state) else {
            Self.logger.error("状态编码失败,放弃写入")
            return
        }
        // 只把「能成功解码」的旧主档挪作备份,保证备份档永远可用
        if let current = defaults.data(forKey: AppGroup.stateKey),
           (try? JSONDecoder().decode(LockerState.self, from: current)) != nil {
            defaults.set(current, forKey: AppGroup.stateBackupKey)
        }
        defaults.set(data, forKey: AppGroup.stateKey)
    }

    func loadTimed() -> TimedModeState {
        // 一次性迁移:旧版两个字段合存 timed 键 → 拆成各自独立键(迁移成功才删旧键)
        if defaults.object(forKey: AppGroup.timedStateKey) != nil,
           let data = defaults.data(forKey: AppGroup.timedStateKey),
           let timed = try? JSONDecoder().decode(TimedModeState.self, from: data) {
            saveTemporaryUnlockUntil(timed.temporaryUnlockUntil)
            saveGuestModeUntil(timed.guestModeUntil)
            defaults.removeObject(forKey: AppGroup.timedStateKey)
        }
        if defaults.object(forKey: AppGroup.temporarySessionKey) == nil,
           let legacy = defaults.object(forKey: AppGroup.temporaryUnlockKey) as? Date {
            saveTemporarySession(TemporaryAccessSession(until: legacy, selectionData: nil))
        }
        defaults.set(true, forKey: AppGroup.timedMigrationKey)
        let session = loadTemporarySession()
        return TimedModeState(
            temporaryUnlockUntil: session?.until,
            guestModeUntil: defaults.object(forKey: AppGroup.guestModeKey) as? Date,
            temporaryUnlockSelectionData: session?.selectionData
        )
    }

    func loadTemporarySession() -> TemporaryAccessSession? {
        guard let data = defaults.data(forKey: AppGroup.temporarySessionKey) else { return nil }
        // A corrupt scoped session must never degrade into a full-rule pause.
        return try? JSONDecoder().decode(TemporaryAccessSession.self, from: data)
    }

    func saveTemporarySession(_ session: TemporaryAccessSession?) {
        if let session, let data = try? JSONEncoder().encode(session) {
            defaults.set(data, forKey: AppGroup.temporarySessionKey)
        } else {
            defaults.removeObject(forKey: AppGroup.temporarySessionKey)
        }
        defaults.removeObject(forKey: AppGroup.temporaryUnlockKey)
        defaults.set(true, forKey: AppGroup.timedMigrationKey)
    }

    /// Compatibility entry point: starting a deadline pauses all rules, clearing ends any scope.
    func saveTemporaryUnlockUntil(_ until: Date?) {
        saveTemporarySession(until.map { TemporaryAccessSession(until: $0, selectionData: nil) })
    }

    /// 只写访客截止,不触碰临时解锁字段
    func saveGuestModeUntil(_ until: Date?) {
        if let until {
            defaults.set(until, forKey: AppGroup.guestModeKey)
        } else {
            defaults.removeObject(forKey: AppGroup.guestModeKey)
        }
    }

    /// 两个限时字段一起覆写:只用于「清空全部限时状态」这类整体写
    func saveTimed(_ timed: TimedModeState) {
        saveTemporarySession(timed.temporaryUnlockUntil.map {
            TemporaryAccessSession(until: $0, selectionData: timed.temporaryUnlockSelectionData)
        })
        saveGuestModeUntil(timed.guestModeUntil)
    }

    private func loadMainBlob() -> LockerState {
        if let data = defaults.data(forKey: AppGroup.stateKey),
           let state = try? JSONDecoder().decode(LockerState.self, from: data) {
            return state
        }
        if let data = defaults.data(forKey: AppGroup.stateBackupKey),
           let state = try? JSONDecoder().decode(LockerState.self, from: data) {
            Self.logger.error("主状态档损坏,已回退到备份档")
            return state
        }
        Self.logger.error("主状态档与备份档均不可用,返回全新状态")
        return LockerState()
    }
}

/// 限时状态读模型：临时放行范围与截止来自同一会话快照，访客截止独立存储。
struct TimedModeState: Codable, Equatable {
    var temporaryUnlockUntil: Date?
    var guestModeUntil: Date?
    var temporaryUnlockSelectionData: Data?
}
