import SwiftUI

struct PINManagementView: View {
    let hintOnly: Bool
    @Environment(LockerViewModel.self) private var vm
    @Environment(\.dismiss) private var dismiss
    @State private var oldPIN = ""
    @State private var newPIN = ""
    @State private var confirmation = ""
    @State private var hint = ""
    @State private var errorKey: String?
    @State private var lockedUntil: Date?
    private let store = AppGroupStore()

    var body: some View {
        NavigationStack {
            XLScreen {
                Text("pin.manage.reauthenticate", tableName: "PINExperience")
                    .foregroundStyle(XL.muted)
                XLCard {
                    VStack(spacing: XL.Space.m) {
                        pinField("pin.manage.old", text: $oldPIN)
                        if !hintOnly {
                            Divider()
                            pinField("pin.manage.new", text: $newPIN)
                            pinField("pin.manage.confirm", text: $confirmation)
                        }
                    }
                }
                XLCard {
                    TextField(String(localized: "pin.manage.hint", table: "PINExperience"), text: $hint)
                        .autocorrectionDisabled()
                }
                Text("pin.manage.hint.note", tableName: "PINExperience")
                    .font(.footnote).foregroundStyle(XL.muted)
                if let errorKey {
                    Text(LocalizedStringKey(errorKey), tableName: "PINExperience")
                        .foregroundStyle(XL.danger)
                }
                if let lockedUntil {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        if context.date < lockedUntil {
                            Text("pin.entry.lockedout \(lockedUntil.formatted(date: .omitted, time: .standard))")
                                .foregroundStyle(XL.danger)
                        }
                    }
                }
                Button { save() } label: {
                    Text("pin.manage.save", tableName: "PINExperience")
                }
                .buttonStyle(XLPrimaryButtonStyle())
                .disabled(!PINManager.isValidFormat(oldPIN) || (!hintOnly &&
                    (!PINManager.isValidFormat(newPIN) || !PINManager.isValidFormat(confirmation))))
            }
            .navigationTitle(String(localized: hintOnly ? "pin.manage.hint.title" : "pin.manage.title", table: "PINExperience"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { Button("common.cancel") { dismiss() } }
        }
        .tint(XL.primary)
        .onAppear {
            hint = store.load().pinHint ?? ""
            lockedUntil = PINManager().lockoutUntil(in: store.load())
        }
    }

    private func pinField(_ key: String, text: Binding<String>) -> some View {
        SecureField(String(localized: String.LocalizationValue(key), table: "PINExperience"), text: text)
            .keyboardType(.numberPad)
            .textContentType(.password)
            .onChange(of: text.wrappedValue) { _, value in
                text.wrappedValue = String(value.filter { $0.isASCII && $0.isNumber }.prefix(6))
            }
    }

    private func save() {
        var state = store.load()
        let trimmed = hint.trimmingCharacters(in: .whitespacesAndNewlines)
        let result = hintOnly
            ? PINManager().updateHint(oldPIN: oldPIN, hint: trimmed.isEmpty ? nil : trimmed, state: &state)
            : PINManager().change(oldPIN: oldPIN, newPIN: newPIN, confirmation: confirmation,
                                  hint: trimmed.isEmpty ? nil : trimmed, state: &state)
        // Persist migrations and fallback cooldown counters even when verification fails.
        store.save(state)
        vm.reloadFromAppGroup()
        errorKey = nil
        switch result {
        case .success:
            dismiss()
        case .invalidFormat:
            errorKey = "pin.manage.format"
        case .mismatch:
            errorKey = "pin.manage.mismatch"
        case .storageFailure, .verification(.storageFailure):
            errorKey = "pin.manage.storage"
        case .verification(.wrongPIN):
            oldPIN = ""
            errorKey = "pin.manage.wrong"
        case .verification(.lockedOut(let until)):
            oldPIN = ""
            lockedUntil = until
        case .verification(.success):
            break
        }
    }
}
