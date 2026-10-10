import Foundation
import Observation
import FamilyControls
import ManagedSettings

enum GuardSetupProgress: Equatable {
    case chooseApps
    case enableProtection
    case complete

    static func resolve(selectedItemCount: Int, lockEnabled: Bool) -> Self {
        guard selectedItemCount > 0 else { return .chooseApps }
        return lockEnabled ? .complete : .enableProtection
    }
}

struct GuestModePreview: Equatable {
    let allowedAppCount: Int
    let durationMinutes: Int
    let endsAt: Date

    init(allowedAppCount: Int, durationMinutes: Int, now: Date) {
        self.allowedAppCount = allowedAppCount
        self.durationMinutes = durationMinutes
        endsAt = now.addingTimeInterval(TimeInterval(durationMinutes * 60))
    }
}

enum OperationFeedback: Equatable {
    case lockEnabled
    case temporaryUnlockStarted(until: Date)
    case temporaryUnlockFailed
    case temporaryUnlockEnded
    case guestModeStarted(until: Date)
    case guestModeFailed
    case guestModeEnded
    case scheduleEnabled
    case scheduleFailed
    case scheduleDisabled
    case selectionApplied(itemCount: Int)
    case restrictionsCleared

    var isFailure: Bool {
        switch self {
        case .temporaryUnlockFailed, .guestModeFailed, .scheduleFailed: true
        default: false
        }
    }
}

private final class TokenExpiryObservation {
    private let observer: NSObjectProtocol

    init(name: Notification.Name, handler: @escaping () -> Void) {
        observer = NotificationCenter.default.addObserver(
            forName: name,
            object: nil,
            queue: .main
        ) { _ in
            handler()
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(observer)
    }
}

@Observable @MainActor
final class LockerViewModel {
    var selection: FamilyActivitySelection
    var guestSelection: FamilyActivitySelection
    var showPaywall = false
    var selectionError: SelectionOutcome?
    var feedback: OperationFeedback?
    private(set) var state: LockerState
    private(set) var pendingSelectionCount: Int?
    private var pendingSelection: FamilyActivitySelection?

    private let store: AppGroupStore
    private let restrictions: RestrictionsApplying
    private let scheduler: UnlockScheduling
    private let lockScheduler: LockScheduleScheduling
    private let guestScheduler: GuestModeScheduling
    private let now: () -> Date
    private var tokenExpiryObservation: TokenExpiryObservation?
    static let temporaryAccessMinutes = 15...720

    init(store: AppGroupStore = AppGroupStore(),
         restrictions: RestrictionsApplying = ManagedSettingsRestrictions(),
         scheduler: UnlockScheduling = DeviceActivityUnlockScheduler(),
         lockScheduler: LockScheduleScheduling = DeviceActivityLockScheduler(),
         guestScheduler: GuestModeScheduling = DeviceActivityGuestScheduler(),
         now: @escaping () -> Date = { Date() }) {
        self.store = store
        self.restrictions = restrictions
        self.scheduler = scheduler
        self.lockScheduler = lockScheduler
        self.guestScheduler = guestScheduler
        self.now = now
        let loaded = store.load()
        state = loaded
        selection = Self.decodeSelection(loaded.selectionData)
        guestSelection = Self.decodeSelection(loaded.guestSelectionData)
        if #available(iOS 26.5, *) {
            tokenExpiryObservation = TokenExpiryObservation(
                name: ManagedSettingsStore.TokenExpiryMessage.name
            ) { [weak self] in
                MainActor.assumeIsolated {
                    self?.reapplyCurrentRestrictions()
                }
            }
        }
    }

    func commitSelection() {
        let freshVIP = store.load().isVIP
        let outcome = SelectionPolicy.evaluate(
            appCount: selection.applicationTokens.count,
            categoryCount: selection.categoryTokens.count,
            webDomainCount: selection.webDomainTokens.count,
            isVIP: freshVIP
        )
        switch outcome {
        case .needsPaywall:
            selectionError = nil
            stageSelectionForPaywall(
                selection,
                selectedItemCount: selection.applicationTokens.count + selection.categoryTokens.count
            )
            selection = Self.decodeSelection(state.selectionData)
        case .unsupportedKinds:
            selectionError = .unsupportedKinds
            selection = Self.decodeSelection(state.selectionData)
        case .ok:
            selectionError = nil
            state.selectionData = try? JSONEncoder().encode(selection)
            mergeAndPersist()
        }
    }

    /// 免费额度超限时暂存用户刚刚做出的选择。Paywall 关闭后仅在 VIP 已生效时提交，
    /// 普通关闭则丢弃，避免未付费配置悄悄写入或购买后要求用户重选一次。
    func stageSelectionForPaywall(_ selection: FamilyActivitySelection, selectedItemCount: Int) {
        pendingSelection = selection
        pendingSelectionCount = selectedItemCount
        showPaywall = true
    }

    func resolvePendingSelectionAfterPaywall(isVIP: Bool) {
        defer {
            pendingSelection = nil
            pendingSelectionCount = nil
            showPaywall = false
        }
        guard isVIP, let pendingSelection else { return }

        selection = pendingSelection
        selectionError = nil
        state.selectionData = try? JSONEncoder().encode(pendingSelection)
        mergeAndPersist()
        feedback = .selectionApplied(itemCount: pendingSelectionCount ?? 0)
    }

    func setLock(_ on: Bool) {
        state.isLockEnabled = on
        mergeAndPersist()
        if on { feedback = .lockEnabled }
    }

    func setAntiRemoval(_ on: Bool) { state.isAntiRemovalEnabled = on; mergeAndPersist() }
    func setDiscreetShield(_ on: Bool) { state.isDiscreetShieldEnabled = on; mergeAndPersist() }
    func setBiometricUnlock(_ on: Bool) { state.isBiometricUnlockEnabled = on; mergeAndPersist() }
    func setLoginMode(_ mode: LoginMode) { state.loginMode = mode; mergeAndPersist() }

    func setLockMode(_ mode: LockMode) {
        if mode == .allowlist && !store.load().isVIP {
            showPaywall = true
            return
        }
        state.lockMode = mode
        mergeAndPersist()
    }

    func setScheduleEnabled(_ on: Bool) {
        state.scheduleEnabled = on
        state.scheduleRegistrationFailed = false
        mergeAndPersist()
        if on {
            _ = syncLockSchedule()
        } else {
            lockScheduler.stop()
            feedback = .scheduleDisabled
        }
    }

    func setScheduleWindow(startMinutes: Int, endMinutes: Int) {
        guard LockSchedule.isValidWindow(startMinutes: startMinutes, endMinutes: endMinutes) else { return }
        state.scheduleRules = []
        state.scheduleSkippedDay = nil
        state.scheduleStartMinutes = startMinutes
        state.scheduleEndMinutes = endMinutes
        mergeAndPersist()
        if state.scheduleEnabled { _ = syncLockSchedule() }
    }

    func configureAndEnableSchedule(startMinutes: Int, endMinutes: Int) {
        guard LockSchedule.isValidWindow(startMinutes: startMinutes, endMinutes: endMinutes) else { return }
        state.scheduleRules = []
        state.scheduleSkippedDay = nil
        state.scheduleStartMinutes = startMinutes
        state.scheduleEndMinutes = endMinutes
        state.scheduleEnabled = true
        mergeAndPersist()
        _ = syncLockSchedule()
    }

    @discardableResult
    private func syncLockSchedule() -> Bool {
        guard state.scheduleEnabled else { return true }
        let scheduled = lockScheduler.start(rules: state.effectiveScheduleRules)
        state.scheduleRegistrationFailed = !scheduled
        mergeAndPersist()
        if scheduled {
            feedback = .scheduleEnabled
        } else {
            feedback = .scheduleFailed
        }
        return scheduled
    }

    @discardableResult
    func configureSchedule(rules: [ScheduleRule], enable: Bool) -> Bool {
        guard LockSchedule.isValid(rules: rules) else { return false }
        state.scheduleRules = rules
        state.scheduleStartMinutes = rules[0].startMinutes
        state.scheduleEndMinutes = rules[0].endMinutes
        state.scheduleSkippedDay = nil
        state.scheduleEnabled = enable || state.scheduleEnabled
        state.scheduleRegistrationFailed = false
        mergeAndPersist()
        return !state.scheduleEnabled || syncLockSchedule()
    }

    func skipScheduleToday(_ skip: Bool) {
        guard state.scheduleEnabled else { return }
        state.scheduleSkippedDay = skip ? Calendar.current.startOfDay(for: now()) : nil
        mergeAndPersist()
    }

    /// Configuration repair is not proof that another app was actually blocked.
    @discardableResult
    func reapplyProtection(isAuthorized: Bool) -> Bool {
        guard isAuthorized else { return false }
        reloadFromAppGroup()
        let success = !state.scheduleEnabled || syncLockSchedule()
        restrictions.apply(RestrictionsPlan.make(from: state, now: now()))
        return success
    }

    var activeScene: GuardScene? {
        state.scenes.first { $0.id == state.activeSceneID }
    }

    @discardableResult
    func saveScene(name: String) -> Bool {
        let name = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(40))
        guard !name.isEmpty else { return false }
        let scene = GuardScene(name: name, state: state)
        state.scenes.append(scene)
        state.activeSceneID = scene.id
        mergeAndPersist()
        return true
    }

    func renameScene(_ id: UUID, name: String) {
        let name = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(40))
        guard !name.isEmpty, let index = state.scenes.firstIndex(where: { $0.id == id }) else { return }
        state.scenes[index].name = name
        mergeAndPersist()
    }

    func deleteScene(_ id: UUID) {
        state.scenes.removeAll { $0.id == id }
        if state.activeSceneID == id { state.activeSceneID = nil }
        mergeAndPersist()
    }

    @discardableResult
    func applyScene(_ id: UUID) -> Bool {
        guard let scene = state.scenes.first(where: { $0.id == id }),
              LockSchedule.isValid(rules: scene.scheduleRules) else { return false }
        let chosen: FamilyActivitySelection
        if let data = scene.selectionData {
            guard let decoded = try? JSONDecoder().decode(FamilyActivitySelection.self, from: data) else { return false }
            chosen = decoded
        } else {
            chosen = FamilyActivitySelection()
        }
        let vip = store.load().isVIP
        let outcome = SelectionPolicy.evaluate(appCount: chosen.applicationTokens.count,
                                               categoryCount: chosen.categoryTokens.count,
                                               webDomainCount: chosen.webDomainTokens.count, isVIP: vip)
        guard outcome == .ok, scene.lockMode != .allowlist || vip else {
            if outcome == .needsPaywall || (scene.lockMode == .allowlist && !vip) { showPaywall = true }
            return false
        }
        state.selectionData = scene.selectionData
        selection = chosen
        state.lockMode = scene.lockMode
        state.isLockEnabled = scene.isLockEnabled
        state.scheduleEnabled = scene.scheduleEnabled
        state.scheduleRules = scene.scheduleRules
        state.scheduleStartMinutes = scene.scheduleRules[0].startMinutes
        state.scheduleEndMinutes = scene.scheduleRules[0].endMinutes
        state.scheduleSkippedDay = nil
        state.scheduleRegistrationFailed = false
        state.activeSceneID = scene.id
        state.temporaryUnlockUntil = nil
        persistTemporaryUnlock()
        scheduler.cancelRelock()
        mergeAndPersist()
        if state.scheduleEnabled {
            return syncLockSchedule()
        }
        lockScheduler.stop()
        return true
    }

    // MARK: - 访客模式

    var isGuestModeActive: Bool {
        RestrictionsPlan.guestModeActive(state: state, now: now())
    }

    /// 访客白名单只支持具体 App(.all(except:) 的例外只收 ApplicationToken)
    func commitGuestSelection() {
        if !guestSelection.categoryTokens.isEmpty || !guestSelection.webDomainTokens.isEmpty {
            selectionError = .unsupportedKinds
            guestSelection = Self.decodeSelection(state.guestSelectionData)
            return
        }
        selectionError = nil
        state.guestSelectionData = try? JSONEncoder().encode(guestSelection)
        mergeAndPersist()
    }

    func startGuestMode(minutes: Int) {
        guard GuardActions.isValidGuestDuration(minutes) else { return }
        guard !guestSelection.applicationTokens.isEmpty else { return }
        guard store.load().isVIP else { // 激活门控在这里;计划层刻意不校验 VIP(见 RestrictionsPlan)
            showPaywall = true
            return
        }
        let until = now().addingTimeInterval(TimeInterval(minutes * 60))
        state.guestModeUntil = until
        persistGuestMode() // 先落 timed 键,mergeAndPersist 回读时才能带出新值
        mergeAndPersist()
        if guestScheduler.scheduleRestore(until: until) {
            feedback = .guestModeStarted(until: until)
        } else {
            state.guestModeUntil = nil
            persistGuestMode()
            mergeAndPersist()
            feedback = .guestModeFailed
        }
    }

    func endGuestModeNow() {
        state.guestModeUntil = nil
        persistGuestMode()
        mergeAndPersist()
        guestScheduler.cancelRestore()
        feedback = .guestModeEnded
    }

    func temporaryUnlock(minutes: Int) {
        _ = temporaryUnlock(minutes: minutes, selection: nil)
    }

    @discardableResult
    func temporaryUnlock(minutes: Int, selection access: FamilyActivitySelection?) -> Bool {
        guard Self.temporaryAccessMinutes.contains(minutes), !isGuestModeActive else { return false }
        if let access {
            guard !access.applicationTokens.isEmpty, access.categoryTokens.isEmpty,
                  access.webDomainTokens.isEmpty else { return false }
        }
        let encoded = access.flatMap { try? JSONEncoder().encode($0) }
        guard access == nil || encoded != nil else { return false }
        state.temporaryUnlockSelectionData = encoded
        let until = now().addingTimeInterval(TimeInterval(minutes * 60))
        state.temporaryUnlockUntil = until
        persistTemporaryUnlock()
        mergeAndPersist()
        if scheduler.scheduleRelock(until: until) {
            feedback = .temporaryUnlockStarted(until: until)
            return true
        } else {
            state.temporaryUnlockUntil = nil
            persistTemporaryUnlock()
            mergeAndPersist()
            feedback = .temporaryUnlockFailed
            return false
        }
    }

    func endTemporaryUnlockNow() {
        state.temporaryUnlockUntil = nil
        persistTemporaryUnlock()
        mergeAndPersist()
        scheduler.cancelRelock()
        feedback = .temporaryUnlockEnded
    }

    /// App 停留在前台跨过截止时间时，立即收敛本地状态并重算限制；
    /// 不必等待 scenePhase 变化或后台扩展的下一次回调才更新界面。
    func refreshTimedModes(at date: Date) {
        let temporaryExpired = state.temporaryUnlockUntil.map { $0 <= date } ?? false
        let guestExpired = state.guestModeUntil.map { $0 <= date } ?? false
        guard temporaryExpired || guestExpired else {
            if state.scheduleEnabled {
                restrictions.apply(RestrictionsPlan.make(from: state, now: date))
            }
            return
        }

        if temporaryExpired {
            state.temporaryUnlockUntil = nil
            scheduler.cancelRelock()
            persistTemporaryUnlock()
        }
        if guestExpired {
            state.guestModeUntil = nil
            guestScheduler.cancelRestore()
            persistGuestMode()
        }
        mergeAndPersist()
    }

    func clearAllRestrictions() {
        state.isLockEnabled = false
        state.isAntiRemovalEnabled = false
        state.temporaryUnlockUntil = nil
        state.scheduleEnabled = false
        state.scheduleRegistrationFailed = false
        state.scheduleSkippedDay = nil
        state.guestModeUntil = nil
        store.saveTimed(TimedModeState())
        mergeAndPersist()
        restrictions.clearAll()
        scheduler.cancelRelock()
        lockScheduler.stop()
        guestScheduler.cancelRestore()
        feedback = .restrictionsCleared
    }

    func dismissFeedback() {
        feedback = nil
    }

    func reloadFromAppGroup() {
        state = store.load()
        selection = Self.decodeSelection(state.selectionData)
        guestSelection = Self.decodeSelection(state.guestSelectionData)
    }

    private func reapplyCurrentRestrictions() {
        state = store.load()
        restrictions.apply(RestrictionsPlan.make(from: state, now: now()))
    }

    private static func decodeSelection(_ data: Data?) -> FamilyActivitySelection {
        data.flatMap { try? JSONDecoder().decode(FamilyActivitySelection.self, from: $0) }
            ?? FamilyActivitySelection()
    }

    /// 限时字段走独立键,按字段写入:任何一次写入都不会波及另一字段(跨进程竞态面最小化)
    private func persistTemporaryUnlock() {
        store.saveTemporarySession(state.temporaryUnlockUntil.map {
            TemporaryAccessSession(until: $0, selectionData: state.temporaryUnlockSelectionData)
        })
    }

    private func persistGuestMode() {
        store.saveGuestModeUntil(state.guestModeUntil)
    }

    /// 合并写入:先读取 App Group 最新状态(可能已被 PIN/VIP 等其他写入者更新),
    /// 只覆盖 vm 自己拥有的字段,避免整体覆写(wholesale save)丢失别处写入的字段。
    /// 限时字段不在此列:它们落在独立 timed 键上,由 persistTemporaryUnlock/persistGuestMode 负责。
    private func mergeAndPersist() {
        var fresh = store.load()
        fresh.selectionData = state.selectionData
        fresh.isLockEnabled = state.isLockEnabled
        fresh.isAntiRemovalEnabled = state.isAntiRemovalEnabled
        fresh.isDiscreetShieldEnabled = state.isDiscreetShieldEnabled
        fresh.isBiometricUnlockEnabled = state.isBiometricUnlockEnabled
        fresh.loginMode = state.loginMode
        fresh.lockMode = state.lockMode
        fresh.scheduleEnabled = state.scheduleEnabled
        fresh.scheduleStartMinutes = state.scheduleStartMinutes
        fresh.scheduleEndMinutes = state.scheduleEndMinutes
        fresh.scheduleRules = state.scheduleRules
        fresh.scheduleSkippedDay = state.scheduleSkippedDay
        fresh.scheduleRegistrationFailed = state.scheduleRegistrationFailed
        fresh.scenes = state.scenes
        fresh.activeSceneID = state.activeSceneID
        fresh.guestSelectionData = state.guestSelectionData
        state = fresh
        store.save(fresh)
        restrictions.apply(RestrictionsPlan.make(from: state, now: now()))
    }
}
