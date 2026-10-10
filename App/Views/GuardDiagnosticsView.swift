import SwiftUI
import FamilyControls
import DeviceActivity

struct GuardDiagnosticsView: View {
    @Environment(LockerViewModel.self) private var vm
    @Environment(\.dismiss) private var dismiss
    @State private var repairMessage: LocalizedStringKey?

    var body: some View {
        NavigationStack {
            TimelineView(.periodic(from: .now, by: 30)) { context in
                XLScreen {
                    Text("experience.check.honest").font(.footnote).foregroundStyle(XL.muted)
                    XLCard {
                        VStack(alignment: .leading, spacing: XL.Space.l) {
                            check("experience.check.authorization", passed: authorized)
                            check("experience.check.storage", passed: AppGroup.isSuiteAvailable)
                            if vm.state.scheduleEnabled {
                                check("experience.check.monitors", passed: monitorsRegistered)
                                if vm.state.scheduleRegistrationFailed {
                                    Text("experience.check.schedule.failed").foregroundStyle(XL.danger)
                                }
                            }
                            if let until = vm.state.temporaryUnlockUntil, until > context.date {
                                Text("experience.check.access.ends \(until.formatted(date: .abbreviated, time: .shortened))")
                                    .font(.footnote)
                                check("experience.check.access.monitor", passed: DeviceActivityCenter().activities.contains(DeviceActivityUnlockScheduler.activityName))
                            }
                            if let until = vm.state.guestModeUntil, until > context.date {
                                Text("experience.check.guest.ends \(until.formatted(date: .abbreviated, time: .shortened))")
                                    .font(.footnote)
                                check("experience.check.guest.monitor", passed: DeviceActivityCenter().activities.contains(DeviceActivityGuestScheduler.activityName))
                            }
                            Text(currentRule(at: context.date)).font(.subheadline.weight(.semibold))
                            if vm.state.scheduleEnabled,
                               let next = LockSchedule.nextTransition(rules: vm.state.effectiveScheduleRules,
                                  skippedDay: vm.state.scheduleSkippedDay, after: context.date) {
                                Text("experience.check.next \(next.formatted(date: .abbreviated, time: .shortened))")
                                    .font(.footnote).foregroundStyle(XL.muted)
                            }
                        }
                    }
                    if let repairMessage { Text(repairMessage).font(.footnote).foregroundStyle(XL.muted) }
                    Button("experience.check.reapply") {
                        repairMessage = vm.reapplyProtection(isAuthorized: authorized)
                            ? "experience.check.reapplied" : "experience.check.repair.failed"
                    }
                    .buttonStyle(XLPrimaryButtonStyle())
                    .disabled(!authorized)
                    XLCard {
                        VStack(alignment: .leading, spacing: XL.Space.m) {
                            Text("experience.check.test.title").font(.headline)
                            Text("experience.check.test.steps").font(.subheadline)
                            Text("experience.check.timers").font(.footnote).foregroundStyle(XL.muted)
                        }
                    }
                    XLCard {
                        VStack(alignment: .leading, spacing: XL.Space.m) {
                            Text("experience.check.help.title").font(.headline)
                            Text("experience.check.help.body").font(.subheadline)
                            Link("experience.check.feedback", destination: URL(string: "https://github.com/materialofair/lockstead-site/issues")!)
                        }
                    }
                }
            }
            .navigationTitle("experience.check.title")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { Button("common.close") { dismiss() } }
        }
        .tint(XL.primary)
    }

    private var authorized: Bool { AuthorizationCenter.shared.authorizationStatus == .approved }

    private var monitorsRegistered: Bool {
        DeviceActivityLockScheduler.expectedActivityNames(rules: vm.state.effectiveScheduleRules)
            .isSubset(of: Set(DeviceActivityCenter().activities))
    }

    private func check(_ title: LocalizedStringKey, passed: Bool) -> some View {
        HStack(alignment: .top) {
            Image(systemName: passed ? "checkmark.circle" : "exclamationmark.triangle")
                .foregroundStyle(passed ? XL.primary : XL.danger)
            Text(title)
            Spacer()
            Text(passed ? "experience.check.available" : "experience.check.attention")
                .font(.footnote).foregroundStyle(XL.muted)
        }
        .accessibilityElement(children: .combine)
    }

    private func currentRule(at date: Date) -> LocalizedStringKey {
        if vm.isGuestModeActive { return "experience.check.rule.guest" }
        if let until = vm.state.temporaryUnlockUntil, until > date {
            return vm.state.temporaryUnlockSelectionData == nil
                ? "experience.check.rule.pause" : "experience.check.rule.partial"
        }
        return RestrictionsPlan.lockActive(state: vm.state, now: date)
            ? "experience.check.rule.lock" : "experience.check.rule.idle"
    }
}
