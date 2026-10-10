import SwiftUI

struct PINEntryView: View {
    let onUnlocked: () -> Void
    @State private var showRecovery = false
    @State private var storageFailure = false
    @State private var pin = ""
    @State private var showWrong = false
    @State private var lockedUntil: Date?
    @State private var biometricAttempted = false
    @State private var biometricKind: BiometricUnlocker.Kind?
    @State private var pinHint: String?
    private let store = AppGroupStore()

    var body: some View {
        GeometryReader { geometry in
            ScrollView(.vertical) {
                VStack(spacing: 0) {
                    Spacer(minLength: XL.Space.xxl)

                    Image(systemName: "lock.fill")
                        .font(.system(size: 32, weight: .medium))
                        .foregroundStyle(XL.primary)
                        .frame(width: 68, height: 68)
                        .background(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .fill(XL.primaryTint)
                        )

                    Text("pin.entry.title")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(XL.ink)
                        .padding(.top, XL.Space.xl)

                    PINDots(entered: pin.count, isError: showWrong)
                        .padding(.top, XL.Space.xxl)

                    Group {
                        if let lockedUntil {
                            TimelineView(.periodic(from: .now, by: 1)) { context in
                                if context.date >= lockedUntil {
                                    Color.clear.frame(height: 18)
                                        .onAppear { self.lockedUntil = nil }
                                } else {
                                    Text("pin.entry.lockedout \(lockedUntil.formatted(date: .omitted, time: .standard))")
                                        .font(.footnote.weight(.medium))
                                        .monospacedDigit()
                                        .foregroundStyle(XL.danger)
                                }
                            }
                        } else if storageFailure {
                            Text("pin.manage.storage", tableName: "PINExperience")
                                .font(.footnote).foregroundStyle(XL.danger)
                        } else if showWrong {
                            Text("pin.entry.wrong")
                                .font(.footnote.weight(.medium))
                                .foregroundStyle(XL.danger)
                        } else if let pinHint {
                            Text("pin.entry.hint \(pinHint)")
                                .font(.footnote)
                                .foregroundStyle(XL.muted)
                        } else {
                            Color.clear.frame(height: 18)
                        }
                    }
                    .padding(.top, XL.Space.l)

                    if let kind = biometricKind {
                        Button {
                            Task { await tryBiometric() }
                        } label: {
                            Label {
                                Text("pin.entry.biometric \(kind.displayName)")
                                    .font(.subheadline.weight(.medium))
                            } icon: {
                                Image(systemName: kind.symbolName)
                            }
                            .foregroundStyle(XL.primary)
                        }
                        .disabled(isLockedOut)
                        .padding(.top, XL.Space.l)
                    }

                    Button { showRecovery = true } label: {
                        Text("pin.recovery.title", tableName: "PINExperience")
                    }
                    .font(.footnote).padding(.top, XL.Space.l)

                    Spacer(minLength: XL.Space.xl)

                    PINPad(disabled: isLockedOut) { digit in
                        guard pin.count < 6 else { return }
                        showWrong = false
                        let candidate = pin + digit
                        pin = candidate
                        if candidate.count == 6 {
                            attempt(candidate)
                        }
                    } onDelete: {
                        showWrong = false
                        if !pin.isEmpty { pin.removeLast() }
                    }
                }
                .padding(.horizontal, XL.screenPadding)
                .padding(.bottom, XL.Space.xl)
                .frame(maxWidth: .infinity, minHeight: geometry.size.height)
            }
            .scrollBounceBehavior(.basedOnSize)
            .scrollIndicators(.hidden)
        }
        .background(XL.bg)
        .sheet(isPresented: $showRecovery) { PINRecoveryHelpView() }
        .task {
            // 进屏一次性读取:本界面存续期间设置不可能变化,
            // 不再每次重绘整档 JSON 解码 + 系统生物识别策略查询
            let snapshot = store.load()
            pinHint = snapshot.pinHint
            biometricKind = snapshot.isBiometricUnlockEnabled ? BiometricUnlocker.availableKind() : nil
            // 冷启动恢复锁定期显示(冷却状态在 Keychain,重启不丢)
            if lockedUntil == nil, let until = PINManager().lockoutUntil(in: snapshot) {
                lockedUntil = until
            }
            // 进入即自动弹一次生物识别;失败/取消则安静回落 PIN,不弹错误
            guard !biometricAttempted, biometricKind != nil, !isLockedOut else { return }
            biometricAttempted = true
            await tryBiometric()
        }
    }

    private func tryBiometric() async {
        if await BiometricUnlocker.authenticate() {
            onUnlocked()
        }
    }

    private var isLockedOut: Bool {
        if let lockedUntil { return lockedUntil > Date() }
        return false
    }

    private func attempt(_ candidate: String) {
        storageFailure = false
        var state = store.load()
        let result = PINManager().verify(pin: candidate, state: &state)
        store.save(state) // 旧档凭据迁移后的清理需要持久化
        switch result {
        case .success:
            onUnlocked()
        case .storageFailure:
            storageFailure = true
            pin = ""
        case .wrongPIN:
            showWrong = true
            pin = ""
        case .lockedOut(let until):
            lockedUntil = until
            pin = ""
        }
    }
}
