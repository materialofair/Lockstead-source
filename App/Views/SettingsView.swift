import SwiftUI

struct SettingsView: View {
    @Environment(LockerViewModel.self) private var vm
    @Environment(EntitlementStore.self) private var entitlements
    @Environment(\.dismiss) private var dismiss
    @State private var showPINChange = false
    @State private var showHintChange = false
    @State private var showPINRecovery = false
    @State private var showDiagnostics = false
    @State private var confirmClear = false
    @State private var showPaywall = false
    @State private var reviewTapCount = 0
    @State private var lastReviewTapAt = Date.distantPast
    @State private var showReviewCodeInput = false
    @State private var reviewCodeInput = ""
    @State private var showReviewAccessSuccess = false
    @State private var showReviewAccessError = false

    var body: some View {
        @Bindable var vm = vm
        NavigationStack {
            XLScreen {
                // 转化触点③:设置页升级入口(非 VIP)
                if !entitlements.isVIP {
                    UpgradeRow { showPaywall = true }
                }

                // 主题
                ThemePickerSection { showPaywall = true }

                AppIconPickerSection { showPaywall = true }

                // 隐私
                XLSectionTitle(key: "settings.privacy.section")
                XLCard(padding: XL.Space.m) {
                    VStack(alignment: .leading, spacing: XL.Space.m) {
                        XLToggleRow(
                            icon: "eye.slash.fill",
                            title: "settings.discreetshield",
                            subtitle: "settings.discreetshield.detail",
                            isOn: Binding(
                                get: { vm.state.isDiscreetShieldEnabled },
                                set: { vm.setDiscreetShield($0) }
                            )
                        )
                        if let kind = BiometricUnlocker.availableKind() {
                            Divider().overlay(XL.border)
                            XLToggleRow(
                                icon: kind.symbolName,
                                title: "settings.biometric \(kind.displayName)",
                                subtitle: "settings.biometric.detail",
                                isOn: Binding(
                                    get: { vm.state.isBiometricUnlockEnabled },
                                    set: { vm.setBiometricUnlock($0) }
                                )
                            )
                        }
                        Divider().overlay(XL.border)
                        XLToggleRow(
                            icon: "function",
                            title: "settings.calculatorlogin",
                            subtitle: "settings.calculatorlogin.detail",
                            isOn: Binding(
                                get: { vm.state.loginMode == .calculator },
                                set: { vm.setLoginMode($0 ? .calculator : .pin) }
                            )
                        )
                    }
                }

                Text("pin.manage.section", tableName: "PINExperience")
                    .font(.headline).foregroundStyle(XL.ink)
                XLCard(padding: XL.Space.m) {
                    VStack(alignment: .leading, spacing: XL.Space.m) {
                        Button { showPINChange = true } label: {
                            Label { Text("pin.manage.title", tableName: "PINExperience") }
                            icon: { Image(systemName: "key.fill") }
                        }
                        Divider()
                        Button { showHintChange = true } label: {
                            Label { Text("pin.manage.hint.title", tableName: "PINExperience") }
                            icon: { Image(systemName: "text.bubble") }
                        }
                    }
                }

                // VIP 功能
                XLSectionTitle(key: "settings.vip.section")
                XLCard(padding: XL.Space.m) {
                    VStack(alignment: .leading, spacing: XL.Space.m) {
                        XLToggleRow(
                            icon: "trash.slash.fill",
                            title: "settings.antiremoval",
                            subtitle: entitlements.isVIP ? nil : "settings.antiremoval.viponly",
                            isOn: Binding(
                                get: { vm.state.isAntiRemovalEnabled },
                                set: { vm.setAntiRemoval($0) }
                            ),
                            disabled: !entitlements.isVIP
                        )
                        Divider().overlay(XL.border)
                        XLNavRow(icon: "arrow.clockwise", title: "settings.restore") {
                            Task { await entitlements.restore() }
                        }
                        if entitlements.isRestoring {
                            ProgressView().tint(XL.primary)
                        } else if let outcome = entitlements.restoreOutcome {
                            RestoreStatusText(outcome: outcome)
                        } else if let err = entitlements.lastError {
                            Text(err)
                                .font(.footnote.weight(.medium))
                                .foregroundStyle(XL.danger)
                        }
                    }
                }

                // 管理
                XLSectionTitle(key: "settings.manage.section")
                XLCard(padding: XL.Space.m) {
                    XLNavRow(icon: "shield.slash", title: "settings.clear.all", style: .danger) {
                        confirmClear = true
                    }
                }
                Text("settings.clear.footer") // 卸载前请先执行
                    .font(.footnote)
                    .foregroundStyle(XL.muted)
                    .padding(.horizontal, XL.Space.xs)

                XLCard(padding: XL.Space.m) {
                    XLNavRow(icon: "checkmark.shield", title: "experience.check.title") { showDiagnostics = true }
                }

                // 帮助
                XLSectionTitle(key: "settings.faq.section")
                XLCard(padding: XL.Space.m) {
                    HStack(alignment: .top, spacing: XL.Space.m) {
                        IconBadge(systemName: "questionmark.circle", style: .muted)
                        Button { showPINRecovery = true } label: {
                            Text("pin.recovery.title", tableName: "PINExperience")
                        }
                            .font(.footnote)
                            .foregroundStyle(XL.ink)
                    }
                }

                // 关于
                VStack(spacing: XL.Space.xs) {
                    Image(systemName: "lock.shield.fill")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(XL.primary)
                        .frame(width: 44, height: 44)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(XL.primaryTint)
                        )
                        .contentShape(Rectangle())
                        .onTapGesture { registerReviewTap() }
                    Text("settings.about \(appVersion)")
                        .font(.footnote)
                        .foregroundStyle(XL.muted)
                    if entitlements.isReviewAccessActive {
                        Label("settings.review.active", systemImage: "checkmark.seal.fill")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(XL.accent)
                    }
                    Label {
                        Text("onboarding.privacy")
                            .font(.footnote)
                            .foregroundStyle(XL.muted)
                    } icon: {
                        Image(systemName: "hand.raised.fill")
                            .font(.caption)
                            .foregroundStyle(XL.primary)
                    }
                    Link("settings.privacypolicy", destination: LegalLinks.privacyPolicy)
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(XL.muted)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, XL.Space.l)
            }
            .navigationTitle("settings.title")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                Button("common.close") { dismiss() }
                    .foregroundStyle(XL.ink)
            }
            .toolbarBackground(XL.bg, for: .navigationBar)
            .sheet(isPresented: $showPINChange) { PINManagementView(hintOnly: false) }
            .sheet(isPresented: $showHintChange) { PINManagementView(hintOnly: true) }
            .sheet(isPresented: $showPINRecovery) { PINRecoveryHelpView() }
            .sheet(isPresented: $showDiagnostics) { GuardDiagnosticsView() }
            .sheet(isPresented: $showPaywall) { PaywallView() }
            .confirmationDialog("settings.clear.confirm", isPresented: $confirmClear) {
                Button("settings.clear.all", role: .destructive) { vm.clearAllRestrictions() }
            }
            .alert("settings.review.title", isPresented: $showReviewCodeInput) {
                TextField("settings.review.placeholder", text: $reviewCodeInput)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                Button("common.cancel", role: .cancel) { reviewCodeInput = "" }
                Button("common.confirm") { activateReviewAccess() }
            } message: {
                Text("settings.review.message")
            }
            .alert("settings.review.success.title", isPresented: $showReviewAccessSuccess) {
                Button("common.ok", role: .cancel) {}
            } message: {
                Text("settings.review.success.message")
            }
            .alert("settings.review.error.title", isPresented: $showReviewAccessError) {
                Button("common.ok", role: .cancel) {}
            } message: {
                Text("settings.review.error.message")
            }
        }
        .tint(XL.primary)
        .operationFeedback(vm)
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.2"
    }

    private func registerReviewTap() {
        let date = Date()
        reviewTapCount = date.timeIntervalSince(lastReviewTapAt) <= 5 ? reviewTapCount + 1 : 1
        lastReviewTapAt = date
        guard reviewTapCount >= 7 else { return }
        reviewTapCount = 0
        reviewCodeInput = ""
        showReviewCodeInput = true
    }

    private func activateReviewAccess() {
        let activated = entitlements.activateReviewAccess(code: reviewCodeInput)
        reviewCodeInput = ""
        if activated {
            vm.reloadFromAppGroup()
            showReviewAccessSuccess = true
        } else {
            showReviewAccessError = true
        }
    }
}
