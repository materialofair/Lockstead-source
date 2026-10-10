import Foundation
import FamilyControls
import ManagedSettings
import os

struct RestrictionsPlan: Equatable {
    /// 白名单模式:锁全部、只放行这些 App(nil = 非白名单)
    var shieldAllExcept: Set<ApplicationToken>?
    var shieldedCategories: Set<ActivityCategoryToken>?
    var blockedApps: Set<ApplicationToken>?
    var categoryExceptions: Set<ApplicationToken> = []
    var denyAppRemoval: Bool

    /// 「此刻锁定是否应该生效」的唯一权威判断:
    /// 总开关开 && 无生效中的临时解锁 && (未启用时间表 || 当前在时间窗内)
    static func lockActive(state: LockerState, now: Date, calendar: Calendar = .current) -> Bool {
        guard state.isLockEnabled else { return false }
        if (state.temporaryUnlockUntil ?? .distantPast) > now, state.temporaryUnlockSelectionData == nil { return false }
        if state.scheduleEnabled {
            return LockSchedule.isActive(rules: state.effectiveScheduleRules, skippedDay: state.scheduleSkippedDay,
                                         now: now, calendar: calendar)
        }
        return true
    }

    /// 访客模式此刻是否生效:有截止时间且未过期,且访客白名单非空
    static func guestModeActive(state: LockerState, now: Date) -> Bool {
        guestModeActive(guestModeUntil: state.guestModeUntil,
                        guestApplications: decodeSelection(state.guestSelectionData).applicationTokens,
                        now: now)
    }

    static func guestModeActive<App: Hashable>(guestModeUntil: Date?,
                                               guestApplications: Set<App>,
                                               now: Date) -> Bool {
        (guestModeUntil ?? .distantPast) > now && !guestApplications.isEmpty
    }

    /// 黑名单模式下,具体 App 用 blockedApplications 阻止启动(系统可精确报告);
    /// 白名单与类别规则无法由具体 App 集合表达,继续使用 shield。
    static func blockedApplications<T: Hashable>(tokens: Set<T>,
                                                 lockActive: Bool,
                                                 allowlistMode: Bool) -> Set<T>? {
        guard !tokens.isEmpty, lockActive, !allowlistMode else { return nil }
        return tokens
    }

    private static func decodeSelection(_ data: Data?) -> FamilyActivitySelection {
        data.flatMap { try? JSONDecoder().decode(FamilyActivitySelection.self, from: $0) }
            ?? FamilyActivitySelection()
    }

    static func make(from state: LockerState, now: Date, calendar: Calendar = .current) -> RestrictionsPlan {
        // App Group 不可用 = 读不到任何用户配置:fail-closed 全量盾牌(每个 App 启动都被拦,
        // 用户可逐个关闭),而不是空计划静默放行一切——这是执行面的兜底,与 AppGroup.defaults
        // 的标准域降级互补:UI 面继续渲染,执行面绝不放开。
        guard AppGroup.isSuiteAvailable else {
            return RestrictionsPlan(shieldAllExcept: [], shieldedCategories: nil,
                                    blockedApps: nil, denyAppRemoval: false)
        }
        let selection = decodeSelection(state.selectionData)
        let guest = decodeSelection(state.guestSelectionData)
        let spec = makeSpec(selectionApplications: selection.applicationTokens,
                            selectionCategories: selection.categoryTokens,
                            guestApplications: guest.applicationTokens,
                            temporaryApplications: decodeSelection(state.temporaryUnlockSelectionData).applicationTokens,
                            state: state, now: now, calendar: calendar)
        return RestrictionsPlan(shieldAllExcept: spec.shieldAllExcept,
                                shieldedCategories: spec.shieldedCategories,
                                blockedApps: spec.blockedApps, categoryExceptions: spec.categoryExceptions,
                                denyAppRemoval: spec.denyAppRemoval)
    }

    /// 决策纯函数:与 token 具体类型解耦,模拟器上可以用普通值伪造 token 覆盖全部生产分支。
    /// make(from:) 只负责解码真实 token 并适配到本函数。
    static func makeSpec<App: Hashable, Category: Hashable>(
        selectionApplications: Set<App>,
        selectionCategories: Set<Category>,
        guestApplications: Set<App>,
        temporaryApplications: Set<App> = [],
        state: LockerState,
        now: Date,
        calendar: Calendar = .current
    ) -> RestrictionsPlanSpec<App, Category> {
        // 访客模式:最高优先级,覆盖锁定模式/时间表/临时解锁。
        // 只放行访客白名单,其余 App 由系统盾牌阻止启动。
        if guestModeActive(guestModeUntil: state.guestModeUntil,
                           guestApplications: guestApplications,
                           now: now) {
            return RestrictionsPlanSpec(shieldAllExcept: guestApplications,
                                        shieldedCategories: nil,
                                        blockedApps: nil,
                                        denyAppRemoval: state.isAntiRemovalEnabled && state.isVIP)
        }

        let active = lockActive(state: state, now: now, calendar: calendar)
        // 白名单是 VIP 能力;VIP 过期回落黑名单行为(与防卸载先例一致)
        let allowlistMode = state.lockMode == .allowlist && state.isVIP

        let exceptions: Set<App> = (state.temporaryUnlockUntil ?? .distantPast) > now
            && state.temporaryUnlockSelectionData != nil ? temporaryApplications : []
        let blocked = blockedApplications(tokens: selectionApplications.subtracting(exceptions),
                                          lockActive: active,
                                          allowlistMode: allowlistMode)
        var shieldedCategories: Set<Category>?
        var shieldAllExcept: Set<App>?
        if active {
            if allowlistMode {
                // 空选择不生效:避免一个误触把整台设备全部锁死
                if !selectionApplications.isEmpty { shieldAllExcept = selectionApplications.union(exceptions) }
            } else if state.isVIP, !selectionCategories.isEmpty {
                // 类别锁定同为 VIP 能力
                shieldedCategories = selectionCategories
            }
        }

        return RestrictionsPlanSpec(shieldAllExcept: shieldAllExcept,
                                    shieldedCategories: shieldedCategories,
                                    blockedApps: blocked,
                                    categoryExceptions: exceptions,
                                    denyAppRemoval: state.isAntiRemovalEnabled && state.isVIP)
    }
}

/// 与 token 类型解耦的计划结果:单测用伪造 token 覆盖所有生产分支
struct RestrictionsPlanSpec<App: Hashable, Category: Hashable>: Equatable {
    var shieldAllExcept: Set<App>?
    var shieldedCategories: Set<Category>?
    var blockedApps: Set<App>?
    var categoryExceptions: Set<App> = []
    var denyAppRemoval: Bool
}

protocol RestrictionsApplying {
    func apply(_ plan: RestrictionsPlan)
    func clearAll()
}

enum RestrictionsTokenRefresh {
    private static let logger = Logger(subsystem: "zeronet.lockstead", category: "ManagedSettings")

    static func refresh<T: Hashable>(_ references: [Set<T>?],
                                     using operation: (inout [T]) throws -> Void) throws -> [Set<T>?] {
        let uniqueTokens = references.compactMap { $0 }.reduce(into: Set<T>()) { result, tokens in
            result.formUnion(tokens)
        }
        guard !uniqueTokens.isEmpty else { return references }

        let originalTokens = Array(uniqueTokens)
        var refreshedTokens = originalTokens
        try operation(&refreshedTokens)
        guard refreshedTokens.count == originalTokens.count else {
            logger.error("Token refresh returned an unexpected token count; preserving previous tokens")
            return references
        }

        let replacements = Dictionary(uniqueKeysWithValues: zip(originalTokens, refreshedTokens))
        return references.map { tokens in
            tokens.map { Set($0.map { replacements[$0] ?? $0 }) }
        }
    }

    static func refreshOrOriginal<T: Hashable>(_ references: [Set<T>?],
                                               using operation: (inout [T]) throws -> Void) -> [Set<T>?] {
        do {
            return try refresh(references, using: operation)
        } catch {
            logger.error("Token refresh failed; preserving previous tokens: \(error.localizedDescription, privacy: .public)")
            return references
        }
    }
}

final class ManagedSettingsRestrictions: RestrictionsApplying {
    private let store = ManagedSettingsStore()

    static func needsUpdate<Value: Equatable>(current: Value?, desired: Value?) -> Bool {
        current != desired
    }

    func apply(_ plan: RestrictionsPlan) {
        let plan = refreshingTokens(in: plan)
        let desiredBlockedApps = plan.blockedApps.map { Set($0.map(Application.init)) }
        if Self.needsUpdate(current: store.application.blockedApplications, desired: desiredBlockedApps) {
            store.application.blockedApplications = desiredBlockedApps
        }

        // 具体 App 的盾牌恒为 nil(具体 App 走 blockedApplications),清掉任何历史残留
        if Self.needsUpdate(current: store.shield.applications, desired: nil) {
            store.shield.applications = nil
        }
        let desiredShieldedCategories: ShieldSettings.ActivityCategoryPolicy<Application>?
        if let except = plan.shieldAllExcept {
            desiredShieldedCategories = .all(except: except)
        } else {
            desiredShieldedCategories = plan.shieldedCategories.map { .specific($0, except: plan.categoryExceptions) }
        }
        if Self.needsUpdate(current: store.shield.applicationCategories, desired: desiredShieldedCategories) {
            store.shield.applicationCategories = desiredShieldedCategories
        }

        let desiredDenyAppRemoval = plan.denyAppRemoval ? true : nil
        if Self.needsUpdate(current: store.application.denyAppRemoval, desired: desiredDenyAppRemoval) {
            store.application.denyAppRemoval = desiredDenyAppRemoval
        }
    }

    func clearAll() {
        store.clearAllSettings()
    }

    private func refreshingTokens(in plan: RestrictionsPlan) -> RestrictionsPlan {
        guard #available(iOS 26.5, *) else { return plan }
        var refreshed = plan

        let applicationReferences = RestrictionsTokenRefresh.refreshOrOriginal(
            [plan.shieldAllExcept, plan.blockedApps, plan.categoryExceptions]
        ) { tokens in
            try ManagedSettingsStore.refresh(&tokens)
        }
        refreshed.shieldAllExcept = applicationReferences[0]
        refreshed.blockedApps = applicationReferences[1]
        refreshed.categoryExceptions = applicationReferences[2] ?? []

        let categoryReferences = RestrictionsTokenRefresh.refreshOrOriginal(
            [plan.shieldedCategories]
        ) { tokens in
            try ManagedSettingsStore.refresh(&tokens)
        }
        refreshed.shieldedCategories = categoryReferences[0]
        return refreshed
    }
}
