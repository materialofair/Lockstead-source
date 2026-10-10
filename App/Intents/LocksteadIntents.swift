import AppIntents
import Foundation

// 快捷指令只暴露「加强守护」方向的动作(见 GuardActions 的安全边界说明)。
// 两个 Intent 都无需打开 App、无需 PIN——因为它们只可能让设备更受保护。

struct LockNowIntent: AppIntent {
    static let title: LocalizedStringResource = "intent.locknow.title"
    static let description = IntentDescription("intent.locknow.desc")

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let guestActive = GuardActions.lockNow(store: AppGroupStore(),
                                               restrictions: ManagedSettingsRestrictions(),
                                               unlockScheduler: DeviceActivityUnlockScheduler(),
                                               now: Date())
        // 诚实文案:访客模式生效期间锁定不会立即接管(访客计划优先且更严格)
        return .result(dialog: guestActive
            ? IntentDialog("intent.locknow.done.guest")
            : IntentDialog("intent.locknow.done"))
    }
}

struct StartGuestModeIntent: AppIntent {
    static let title: LocalizedStringResource = "intent.guest.title"
    static let description = IntentDescription("intent.guest.desc")

    // 与 App 内自定义时长同一范围(GuardActions.minGuestMinutes...maxGuestMinutes)
    @Parameter(title: "intent.guest.duration", default: 30, inclusiveRange: (15, 720))
    var minutes: Int

    func perform() async throws -> some IntentResult & ProvidesDialog {
        do {
            _ = try GuardActions.startGuestMode(minutes: minutes,
                                                store: AppGroupStore(),
                                                restrictions: ManagedSettingsRestrictions(),
                                                guestScheduler: DeviceActivityGuestScheduler(),
                                                now: Date())
        } catch let error as GuardActionError {
            throw IntentGuardError(error)
        }
        return .result(dialog: IntentDialog("intent.guest.done"))
    }
}

/// 把 GuardActionError 翻译成快捷指令里用户可读的失败原因
struct IntentGuardError: Error, CustomLocalizedStringResourceConvertible {
    let underlying: GuardActionError
    init(_ underlying: GuardActionError) { self.underlying = underlying }

    var localizedStringResource: LocalizedStringResource {
        switch underlying {
        case .guestNeedsVIP: "intent.guest.error.vip"
        case .guestListEmpty: "intent.guest.error.empty"
        case .guestSchedulingFailed, .invalidDuration: "intent.guest.error.failed"
        }
    }
}

struct LocksteadShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: LockNowIntent(),
            phrases: [
                "Lock apps with \(.applicationName)",
                "Turn on \(.applicationName)",
            ],
            shortTitle: "intent.locknow.short",
            systemImageName: "lock.shield.fill"
        )
        AppShortcut(
            intent: StartGuestModeIntent(),
            phrases: [
                "Start guest mode in \(.applicationName)",
                "\(.applicationName) guest mode",
            ],
            shortTitle: "intent.guest.short",
            systemImageName: "person.badge.clock"
        )
    }
}
