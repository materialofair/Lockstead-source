import SwiftUI
import FamilyControls

struct HomeView: View {
    @Environment(LockerViewModel.self) private var vm
    @Environment(EntitlementStore.self) private var entitlements
    @State private var showDiagnostics = false
    @State private var showScenes = false
    @State private var showTemporaryAccess = false
    @State private var pickerPresented = false
    @State private var guestPickerPresented = false
    @State private var customGuestPickerPresented = false
    @State private var guestPreflightPresented = false
    @State private var pendingGuestMinutes: Int?
    @State private var showSettings = false
    @State private var showScheduleEditor = false
    @State private var scheduleEditorEnablesOnSave = false

    private var isAllowlist: Bool { vm.state.lockMode == .allowlist }

    var body: some View {
        @Bindable var vm = vm
        NavigationStack {
            // 限时状态逐秒刷新；其他状态每分钟检查时间表边界。
            // 避免空闲期每秒全屏重算，同时让前台跨时段立即更新。
            TimelineView(tickingEverySecond
                         ? .periodic(from: .now, by: 1)
                         : .periodic(from: .now, by: 60)) { context in
                XLScreen {
                // 状态先行:守护状态是主角
                let currentGuardState = guardState(at: context.date)
                VStack(spacing: XL.Space.m) {
                    HomeHeader(isVIP: entitlements.isVIP) {
                        showSettings = true
                    }

                    StatusCard(
                        state: currentGuardState,
                        setupProgress: setupProgress == .complete ? nil : setupProgress,
                        actionTitle: statusActionTitle(for: currentGuardState),
                        action: { performStatusAction(for: currentGuardState) }
                    )
                }
                .padding(.bottom, XL.Space.s)

                if vm.state.scheduleRegistrationFailed {
                    Button { showDiagnostics = true } label: {
                        Label("experience.check.schedule.failed", systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote).foregroundStyle(XL.danger)
                    }
                }
                XLCard(padding: XL.Space.m) {
                    VStack(spacing: XL.Space.m) {
                        XLNavRow(icon: "square.stack", title: "experience.scenes.title",
                                 detail: vm.activeScene.map { Text(verbatim: $0.name) }) { showScenes = true }
                        Divider()
                        XLNavRow(icon: "checkmark.shield", title: "experience.check.title") { showDiagnostics = true }
                    }
                }

                // 受管理的 App
                XLSectionTitle(key: "home.apps.section")
                XLCard(padding: XL.Space.m) {
                    VStack(alignment: .leading, spacing: XL.Space.m) {
                    XLNavRow(
                        icon: "square.grid.2x2",
                        title: "home.apps.choose",
                        detail: Text("home.apps.count \(selectedItemCount)")
                    ) {
                        pickerPresented = true
                    }
                    SelectionPreview(selection: vm.selection, title: isAllowlist ? "experience.apps.allowed" : "experience.apps.blocked")
                    }
                }

                // 锁定模式
                XLSectionTitle(key: "home.mode.section")
                XLCard(padding: XL.Space.m) {
                    VStack(spacing: XL.Space.m) {
                        LockModeRow(
                            title: "home.mode.blocklist",
                            subtitle: "home.mode.blocklist.sub",
                            isSelected: !isAllowlist,
                            showsVIPBadge: false
                        ) { vm.setLockMode(.blocklist) }
                        Divider().overlay(XL.border)
                        LockModeRow(
                            title: "home.mode.allowlist",
                            subtitle: "home.mode.allowlist.sub",
                            isSelected: isAllowlist,
                            showsVIPBadge: !entitlements.isVIP
                        ) { vm.setLockMode(.allowlist) }
                    }
                }

                // 管控开关
                XLSectionTitle(key: "home.controls.section")
                XLCard(padding: XL.Space.m) {
                    VStack(spacing: XL.Space.m) {
                        XLToggleRow(
                            icon: "lock.fill",
                            title: "home.toggle.lock",
                            subtitle: "home.toggle.lock.sub",
                            isOn: Binding(
                                get: { vm.state.isLockEnabled },
                                set: { vm.setLock($0) }
                            )
                        )
                        Divider().overlay(XL.border)
                        XLToggleRow(
                            icon: "calendar.badge.clock",
                            title: "home.schedule.toggle",
                            subtitle: "home.schedule.sub",
                            isOn: Binding(
                                get: { vm.state.scheduleEnabled },
                                set: { enabled in
                                    if enabled {
                                        scheduleEditorEnablesOnSave = true
                                        showScheduleEditor = true
                                    } else {
                                        vm.setScheduleEnabled(false)
                                    }
                                }
                            )
                        )
                        if vm.state.scheduleEnabled {
                            Divider().overlay(XL.border)
                            XLNavRow(
                                icon: "clock",
                                title: "home.schedule.window",
                                detail: Text("experience.schedule.count \(vm.state.effectiveScheduleRules.count)")
                                    .monospacedDigit()
                            ) {
                                scheduleEditorEnablesOnSave = false
                                showScheduleEditor = true
                            }
                            Button(isScheduleSkippedToday ? "experience.schedule.resume" : "experience.schedule.skip") {
                                vm.skipScheduleToday(!isScheduleSkippedToday)
                            }
                            .font(.subheadline.weight(.medium))
                            if isScheduleSkippedToday {
                                Text("experience.schedule.skipped").font(.footnote).foregroundStyle(XL.muted)
                            }
                        }
                    }
                }
                Text("home.lock.note")
                    .font(.footnote)
                    .foregroundStyle(XL.muted)
                    .padding(.horizontal, XL.Space.xs)

                // 临时解锁
                if vm.state.isLockEnabled {
                    XLSectionTitle(key: "home.tempunlock.section")
                    XLCard(padding: XL.Space.m) {
                        VStack(alignment: .leading, spacing: XL.Space.m) {
                        if let until = vm.state.temporaryUnlockUntil, until > context.date {
                            HStack(spacing: XL.Space.m) {
                                IconBadge(systemName: "clock.fill", style: .accent)
                                Text("home.tempunlock.active \(until.formatted(date: .omitted, time: .shortened))")
                                    .font(.subheadline)
                                    .monospacedDigit()
                                    .foregroundStyle(XL.ink)
                                Spacer(minLength: XL.Space.s)
                                Button("home.tempunlock.end") { vm.endTemporaryUnlockNow() }
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(XL.accent)
                            }
                        } else {
                            ViewThatFits(in: .horizontal) {
                                temporaryUnlockChips(horizontal: true)
                                temporaryUnlockChips(horizontal: false)
                            }
                            .disabled(vm.isGuestModeActive)
                            Text("experience.access.presets.all").font(.footnote).foregroundStyle(XL.muted)
                        }
                        if vm.state.temporaryUnlockSelectionData != nil,
                           let until = vm.state.temporaryUnlockUntil, until > context.date {
                            Text("experience.access.partial.active").font(.footnote).foregroundStyle(XL.accent)
                        }
                        Button("experience.access.custom") { showTemporaryAccess = true }
                            .font(.subheadline.weight(.semibold))
                            .disabled(vm.isGuestModeActive)
                        if vm.isGuestModeActive {
                            Text("experience.access.guest").font(.footnote).foregroundStyle(XL.muted)
                        }
                        }
                    }
                }

                // 访客模式:把手机递出去前开启——只留访客白名单中的 App 可用
                XLSectionTitle(key: "home.guest.section")
                XLCard(padding: XL.Space.m) {
                    if RestrictionsPlan.guestModeActive(state: vm.state, now: context.date),
                       let until = vm.state.guestModeUntil {
                        HStack(spacing: XL.Space.m) {
                            IconBadge(systemName: "person.badge.shield.checkmark.fill", style: .primary)
                            Text("home.guest.active \(until.formatted(date: .omitted, time: .shortened))")
                                .font(.subheadline)
                                .monospacedDigit()
                                .foregroundStyle(XL.ink)
                            Spacer(minLength: XL.Space.s)
                            Button("home.guest.end") { vm.endGuestModeNow() }
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(XL.accent)
                        }
                    } else {
                        VStack(spacing: XL.Space.m) {
                            XLNavRow(
                                icon: "person.crop.circle.badge.checkmark",
                                title: "home.guest.choose",
                                detail: Text("home.apps.count \(vm.guestSelection.applicationTokens.count)")
                            ) {
                                guestPickerPresented = true
                            }
                            SelectionPreview(selection: vm.guestSelection, title: "experience.apps.allowed")
                            if !vm.guestSelection.applicationTokens.isEmpty {
                                Divider().overlay(XL.border)
                                ViewThatFits(in: .horizontal) {
                                    guestModeChips(horizontal: true)
                                    guestModeChips(horizontal: false)
                                }
                            }
                        }
                    }
                }
                Text("home.guest.note")
                    .font(.footnote)
                    .foregroundStyle(XL.muted)
                    .padding(.horizontal, XL.Space.xs)

                // 升级入口(非 VIP,安静的一行)
                if !entitlements.isVIP {
                    UpgradeRow { vm.showPaywall = true }
                        .padding(.top, XL.Space.s)
                }
                }
                .onChange(of: context.date) { _, date in
                    vm.refreshTimedModes(at: date)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .familyActivityPicker(isPresented: $pickerPresented, selection: $vm.selection)
            .onChange(of: pickerPresented) { _, presented in
                if !presented { vm.commitSelection() }
            }
            .familyActivityPicker(isPresented: $guestPickerPresented, selection: $vm.guestSelection)
            .sheet(isPresented: $customGuestPickerPresented, onDismiss: {
                if pendingGuestMinutes != nil {
                    guestPreflightPresented = true
                }
            }) {
                GuestDurationPickerView { minutes in
                    pendingGuestMinutes = minutes
                }
            }
            .sheet(isPresented: $guestPreflightPresented, onDismiss: {
                pendingGuestMinutes = nil
            }) {
                if let preview = guestModePreview {
                    GuestModePreflightView(preview: preview) {
                        vm.startGuestMode(minutes: preview.durationMinutes)
                    }
                }
            }
            .onChange(of: guestPickerPresented) { _, presented in
                if !presented { vm.commitGuestSelection() }
            }
            .alert("selection.unsupported.title",
                   isPresented: .constant(vm.selectionError == .unsupportedKinds)) {
                Button("common.ok") { vm.selectionError = nil }
            } message: { Text("selection.unsupported.body") }
            .sheet(isPresented: $vm.showPaywall, onDismiss: {
                vm.resolvePendingSelectionAfterPaywall(isVIP: entitlements.isVIP)
            }) {
                PaywallView(pendingItemCount: vm.pendingSelectionCount)
            }
            .sheet(isPresented: $showSettings) { SettingsView() }
            .sheet(isPresented: $showDiagnostics) { GuardDiagnosticsView() }
            .sheet(isPresented: $showScenes) { ScenesView() }
            .sheet(isPresented: $showTemporaryAccess) { TemporaryAccessView() }
            .sheet(isPresented: $showScheduleEditor) {
                ScheduleEditorView(rules: vm.state.effectiveScheduleRules,
                                   isEnabling: scheduleEditorEnablesOnSave) { rules in
                    vm.configureSchedule(rules: rules, enable: scheduleEditorEnablesOnSave)
                }
            }
        }
        .tint(XL.primary)
        .operationFeedback(vm)
    }

    private var isScheduleSkippedToday: Bool {
        vm.state.scheduleSkippedDay.map { Calendar.current.isDateInToday($0) } ?? false
    }

    private var selectedItemCount: Int {
        vm.selection.applicationTokens.count + vm.selection.categoryTokens.count
    }

    private var tickingEverySecond: Bool {
        (vm.state.temporaryUnlockUntil ?? .distantPast) > Date()
            || (vm.state.guestModeUntil ?? .distantPast) > Date()
    }

    private var setupProgress: GuardSetupProgress {
        GuardSetupProgress.resolve(
            selectedItemCount: selectedItemCount,
            lockEnabled: vm.state.isLockEnabled
        )
    }

    private var guestModePreview: GuestModePreview? {
        guard let pendingGuestMinutes else { return nil }
        return GuestModePreview(
            allowedAppCount: vm.guestSelection.applicationTokens.count,
            durationMinutes: pendingGuestMinutes,
            now: Date()
        )
    }

    private func prepareGuestMode(minutes: Int) {
        pendingGuestMinutes = minutes
        guestPreflightPresented = true
    }

    @ViewBuilder
    private func temporaryUnlockChips(horizontal: Bool) -> some View {
        if horizontal {
            HStack(spacing: XL.Space.m) { temporaryUnlockChipContent }
        } else {
            VStack(alignment: .leading, spacing: XL.Space.s) { temporaryUnlockChipContent }
        }
    }

    @ViewBuilder
    private var temporaryUnlockChipContent: some View {
        ForEach([15, 30, 60], id: \.self) { minutes in
            XLChip(key: "home.tempunlock.minutes \(minutes)") {
                vm.temporaryUnlock(minutes: minutes)
            }
        }
    }

    @ViewBuilder
    private func guestModeChips(horizontal: Bool) -> some View {
        if horizontal {
            HStack(spacing: XL.Space.m) { guestModeChipContent }
        } else {
            VStack(alignment: .leading, spacing: XL.Space.s) { guestModeChipContent }
        }
    }

    @ViewBuilder
    private var guestModeChipContent: some View {
        ForEach(GuardActions.guestPresetMinutes, id: \.self) { minutes in
            XLChip(key: "home.tempunlock.minutes \(minutes)") {
                prepareGuestMode(minutes: minutes)
            }
        }
        XLChip(key: "home.guest.custom") {
            customGuestPickerPresented = true
        }
    }

    private func statusActionTitle(for state: GuardState) -> LocalizedStringKey? {
        switch state {
        case .tempUnlock, .partialUnlock: "home.tempunlock.end"
        case .guestActive: "home.guest.end"
        case .scheduledIdle: "home.schedule.window"
        case .inactive:
            switch setupProgress {
            case .chooseApps: "home.apps.choose"
            case .enableProtection: "home.setup.enable.action"
            case .complete: nil
            }
        case .active: nil
        }
    }

    private func performStatusAction(for state: GuardState) {
        switch state {
        case .tempUnlock, .partialUnlock:
            vm.endTemporaryUnlockNow()
        case .guestActive:
            vm.endGuestModeNow()
        case .scheduledIdle:
            scheduleEditorEnablesOnSave = false
            showScheduleEditor = true
        case .inactive:
            switch setupProgress {
            case .chooseApps:
                pickerPresented = true
            case .enableProtection:
                vm.setLock(true)
            case .complete:
                break
            }
        case .active:
            break
        }
    }

    private func guardState(at date: Date) -> GuardState {
        if RestrictionsPlan.guestModeActive(state: vm.state, now: date),
           let until = vm.state.guestModeUntil {
            return .guestActive(until: until)
        }
        if let until = vm.state.temporaryUnlockUntil, until > date {
            return vm.state.temporaryUnlockSelectionData == nil
                ? .tempUnlock(until: until) : .partialUnlock(until: until)
        }
        guard vm.state.isLockEnabled, selectedItemCount > 0 else {
            return .inactive
        }
        // 与限制引擎共用同一权威判断,状态卡不许说谎
        if RestrictionsPlan.lockActive(state: vm.state, now: date) {
            return .active(appCount: selectedItemCount)
        }
        if vm.state.scheduleEnabled {
            let next = LockSchedule.nextStart(rules: vm.state.effectiveScheduleRules,
                                              skippedDay: vm.state.scheduleSkippedDay, after: date)
            return .scheduledIdle(startsAt: next?.formatted(date: .abbreviated, time: .shortened) ?? "—")
        }
        return .inactive
    }

}

private struct HomeHeader: View {
    let isVIP: Bool
    var openSettings: () -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        HStack(spacing: XL.Space.m) {
            brandMark
            Text(verbatim: "Lockstead")
                .font(.system(.title2, design: .rounded, weight: .bold))
                .foregroundStyle(XL.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            if isVIP && !dynamicTypeSize.isAccessibilitySize {
                Text(verbatim: "VIP")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(XL.accent)
                    .padding(.horizontal, XL.Space.s)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(XL.accentTint))
            }
            Spacer(minLength: XL.Space.s)
            settingsButton
        }
        .padding(.horizontal, XL.Space.xs)
        .frame(minHeight: 48)
    }

    private var brandMark: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(XL.primaryTint)
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(XL.primary)
        }
        .frame(width: 40, height: 40)
        .accessibilityHidden(true)
    }

    private var settingsButton: some View {
        Button(action: openSettings) {
            Image(systemName: "slider.horizontal.3")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(XL.ink)
                .frame(width: 44, height: 44)
                .background(
                    RoundedRectangle(cornerRadius: XL.buttonRadius, style: .continuous)
                        .fill(XL.primaryTint)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("settings.title"))
    }
}

/// 锁定模式单选行:黑名单/白名单;白名单对非 VIP 显示角标,点击走 Paywall
private struct LockModeRow: View {
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey
    let isSelected: Bool
    let showsVIPBadge: Bool
    var onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: XL.Space.m) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? XL.primary : XL.border)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: XL.Space.s) {
                        Text(title)
                            .font(.body.weight(.medium))
                            .foregroundStyle(XL.ink)
                        if showsVIPBadge {
                            Text(verbatim: "VIP")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(XL.accent)
                                .padding(.horizontal, XL.Space.s)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(XL.accentTint))
                        }
                    }
                    Text(subtitle)
                        .font(.footnote)
                        .foregroundStyle(XL.muted)
                }
                Spacer(minLength: 0)
            }
        }
        .buttonStyle(.plain)
    }
}
