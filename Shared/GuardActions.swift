import Foundation
import FamilyControls

enum GuardActionError: Error, Equatable {
    case invalidDuration
    case guestNeedsVIP
    case guestListEmpty
    case guestSchedulingFailed
}

/// 快捷指令(App Intents)的无头动作层。
///
/// 安全边界:只提供「加强守护」方向的动作(上锁、开访客模式)。
/// 解除方向(解锁、结束访客、关时间表)一律不做成 Intent——
/// 快捷指令不需要 PIN 即可运行,提供解除动作等于给孩子留一个绕过 PIN 的后门。
enum GuardActions {
    /// 首页快捷档位;更长/更细的时长走「自定义」(范围校验见 isValidGuestDuration)
    static let guestPresetMinutes: [Int] = [30, 60]
    /// 下限来自 DeviceActivity 的最小监控时长(15 分钟);上限是「访客必须限时」的产品承诺
    static let minGuestMinutes = 15
    static let maxGuestMinutes = 12 * 60

    static func isValidGuestDuration(_ minutes: Int) -> Bool {
        (minGuestMinutes...maxGuestMinutes).contains(minutes)
    }

    /// 立即上锁:开启锁定总开关,并终止生效中的临时解锁(两者都是加强方向)。
    /// 刻意不结束访客模式——访客计划比普通锁定更严格(只放行访客白名单),
    /// 结束它属于解除方向;访客期间上锁只是让锁定在访客结束后立即接管。
    /// - Returns: 访客模式是否正在生效(生效时调用方应如实告知「访客结束后接管」)
    @discardableResult
    static func lockNow(store: AppGroupStore,
                        restrictions: RestrictionsApplying,
                        unlockScheduler: UnlockScheduling,
                        now: Date) -> Bool {
        var state = store.load()
        state.isLockEnabled = true
        state.temporaryUnlockUntil = nil
        store.save(state)
        store.saveTemporaryUnlockUntil(nil)
        unlockScheduler.cancelRelock()
        restrictions.apply(RestrictionsPlan.make(from: state, now: now))
        return RestrictionsPlan.guestModeActive(state: state, now: now)
    }

    /// 开启访客模式:门控与 LockerViewModel.startGuestMode 一致(VIP + 非空白名单 + 合法档位)。
    ///
    /// 无 PIN 触发为什么安全:访客计划只放行家长配置的白名单,
    /// 所以孩子用 Siri 开访客模式只会让设备更受限制,不构成解除路径。
    /// 已知取舍:按「类别」锁定的 App 若被家长明确加进访客白名单,访客期间可用——
    /// 这是家长显式配置的结果(白名单语义即「访客可用」),不在此处拦截。
    /// - Returns: 访客模式的截止时间
    static func startGuestMode(minutes: Int,
                               store: AppGroupStore,
                               restrictions: RestrictionsApplying,
                               guestScheduler: GuestModeScheduling,
                               now: Date) throws -> Date {
        guard isValidGuestDuration(minutes) else { throw GuardActionError.invalidDuration }
        var state = store.load()
        let guestApps = (state.guestSelectionData
            .flatMap { try? JSONDecoder().decode(FamilyActivitySelection.self, from: $0) })?
            .applicationTokens ?? []
        guard !guestApps.isEmpty else { throw GuardActionError.guestListEmpty }
        guard state.isVIP else { throw GuardActionError.guestNeedsVIP }

        let until = now.addingTimeInterval(TimeInterval(minutes * 60))
        state.guestModeUntil = until
        store.save(state)
        store.saveGuestModeUntil(until)
        restrictions.apply(RestrictionsPlan.make(from: state, now: now))
        let scheduled = guestScheduler.scheduleRestore(until: until)
        // 调度失败会同步终止访客模式(GuestModeEnforcer.end 清掉截止时间)——回读确认真实状态
        guard scheduled, store.load().guestModeUntil != nil else {
            throw GuardActionError.guestSchedulingFailed
        }
        return until
    }
}
