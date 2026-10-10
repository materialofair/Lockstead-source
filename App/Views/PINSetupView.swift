import SwiftUI

struct PINSetupView: View {
    private enum Stage { case enter, confirm, hint }

    let onDone: () -> Void
    @State private var showStorageError = false
    @State private var stage: Stage = .enter
    @State private var first = ""
    @State private var confirm = ""
    @State private var hint = ""
    @State private var showMismatch = false
    private let store = AppGroupStore()

    var body: some View {
        GeometryReader { geometry in
            ScrollView(.vertical) {
                VStack(spacing: 0) {
                    Spacer(minLength: XL.Space.xxl)

                    Image(systemName: "lock.rotation")
                        .font(.system(size: 32, weight: .medium))
                        .foregroundStyle(XL.primary)
                        .frame(width: 68, height: 68)
                        .background(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .fill(XL.primaryTint)
                        )

                    Text("pin.setup.title")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(XL.ink)
                        .padding(.top, XL.Space.xl)

                    Text(stageSubtitle)
                        .font(.subheadline)
                        .foregroundStyle(showMismatch ? XL.danger : XL.muted)
                        .padding(.top, XL.Space.s)

                    switch stage {
                    case .enter, .confirm:
                        PINDots(entered: currentInput.count, isError: showMismatch)
                            .padding(.top, XL.Space.xxl)

                        Spacer(minLength: XL.Space.xl)

                        PINPad { digit in
                            guard currentInput.count < 6 else { return }
                            showMismatch = false
                            appendDigit(digit)
                        } onDelete: {
                            showMismatch = false
                            deleteDigit()
                        }

                        Button(stage == .enter ? "pin.setup.continue" : "pin.setup.done.confirm") {
                            advance()
                        }
                        .buttonStyle(XLPrimaryButtonStyle())
                        .disabled(!PINManager.isValidFormat(currentInput))
                        .padding(.top, XL.Space.xxl)

                        if stage == .confirm {
                            Button("pin.setup.restart") {
                                first = ""
                                confirm = ""
                                showMismatch = false
                                stage = .enter
                            }
                            .font(.subheadline)
                            .foregroundStyle(XL.muted)
                            .padding(.top, XL.Space.m)
                        }

                    case .hint:
                        XLCard {
                            TextField("pin.setup.hint", text: $hint)
                                .font(.body)
                                .foregroundStyle(XL.ink)
                        }
                        .padding(.top, XL.Space.xxl)

                        Text("pin.recovery.persistence", tableName: "PINExperience") // 忘记 PIN 的兜底路径说明
                            .font(.footnote)
                            .foregroundStyle(XL.muted)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, XL.Space.m)

                        Spacer(minLength: XL.Space.xl)

                        Button("pin.setup.done") { save() }
                            .buttonStyle(XLPrimaryButtonStyle())
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
        .alert(String(localized: "pin.manage.storage.title", table: "PINExperience"), isPresented: $showStorageError) {
            Button("common.ok", role: .cancel) {}
        } message: {
            Text("pin.manage.storage", tableName: "PINExperience")
        }
        .animation(.easeOut(duration: 0.2), value: stage)
    }

    private var currentInput: String {
        stage == .enter ? first : confirm
    }

    private var stageSubtitle: LocalizedStringKey {
        if showMismatch { return "pin.error.mismatch" }
        switch stage {
        case .enter: return "pin.setup.enter"
        case .confirm: return "pin.setup.confirm"
        case .hint: return "pin.setup.hint.subtitle"
        }
    }

    private func appendDigit(_ d: String) {
        if stage == .enter { first += d } else { confirm += d }
    }

    private func deleteDigit() {
        if stage == .enter {
            if !first.isEmpty { first.removeLast() }
        } else {
            if !confirm.isEmpty { confirm.removeLast() }
        }
    }

    private func advance() {
        switch stage {
        case .enter:
            guard PINManager.isValidFormat(first) else { return }
            stage = .confirm
        case .confirm:
            if confirm == first {
                showMismatch = false
                stage = .hint
            } else {
                showMismatch = true
                confirm = ""
            }
        case .hint:
            break
        }
    }

    private func save() {
        guard PINManager.isValidFormat(first) else { return }
        var state = store.load()
        // 凭据派生失败时停留在设置页,不得当作已设置(否则用户会被锁在门外)
        guard PINManager().set(pin: first, hint: hint.isEmpty ? nil : hint, in: &state) else { showStorageError = true; return }
        store.save(state)
        onDone()
    }
}
