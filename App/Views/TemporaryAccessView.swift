import SwiftUI
import FamilyControls

struct TemporaryAccessView: View {
    @Environment(LockerViewModel.self) private var vm
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var minutesText = "30"
    @FocusState private var durationFocused: Bool
    private var minutes: Int { Int(minutesText) ?? 0 }
    @State private var selectedOnly = true
    @State private var selection = FamilyActivitySelection()
    @State private var picker = false
    @State private var failed = false

    private var validSelection: Bool {
        !selection.applicationTokens.isEmpty && selection.categoryTokens.isEmpty && selection.webDomainTokens.isEmpty
    }

    var body: some View {
        NavigationStack {
            XLScreen {
                XLCard {
                    VStack(alignment: .leading, spacing: XL.Space.m) {
                        if dynamicTypeSize.isAccessibilitySize {
                            VStack(alignment: .leading, spacing: XL.Space.m) {
                                Text("experience.access.scope").font(.headline)
                                scopeOption("experience.access.selected", value: true)
                                scopeOption("experience.access.all", value: false)
                            }
                        } else {
                            Picker("experience.access.scope", selection: $selectedOnly) {
                                Text("experience.access.selected").tag(true)
                                Text("experience.access.all").tag(false)
                            }
                            .pickerStyle(.menu)
                        }
                        if selectedOnly {
                            Button("home.apps.choose") { picker = true }
                            SelectionPreview(selection: selection, title: "experience.access.selected")
                            if !selection.categoryTokens.isEmpty || !selection.webDomainTokens.isEmpty {
                                Text("experience.access.apps.only").font(.footnote).foregroundStyle(XL.danger)
                            }
                        }
                        HStack {
                            Text("experience.access.duration")
                            Spacer()
                            TextField("30", text: $minutesText)
                                .keyboardType(.numberPad)
                                .focused($durationFocused)
                                .multilineTextAlignment(.trailing)
                                .monospacedDigit()
                                .frame(width: 90)
                                .textFieldStyle(.roundedBorder)
                                .accessibilityLabel("experience.access.duration")
                                .onChange(of: minutesText) { _, value in
                                    minutesText = String(value.filter { $0.isASCII && $0.isNumber }.prefix(3))
                                }
                        }
                        if !LockerViewModel.temporaryAccessMinutes.contains(minutes) {
                            Text("experience.access.duration.invalid").font(.footnote).foregroundStyle(XL.danger)
                        }
                        Text("experience.access.duration.note").font(.footnote).foregroundStyle(XL.muted)
                    }
                }
                XLCard {
                    VStack(alignment: .leading, spacing: XL.Space.s) {
                        Text("experience.access.restores").font(.headline)
                        SelectionPreview(selection: vm.selection, title: vm.state.lockMode == .allowlist
                                         ? "experience.apps.allowed" : "experience.apps.blocked")
                        Text(vm.state.scheduleEnabled ? "experience.access.schedule.resume" : "experience.access.lock.resume")
                            .font(.footnote).foregroundStyle(XL.muted)
                        Text("experience.access.latest").font(.footnote).foregroundStyle(XL.muted)
                    }
                }
                if vm.isGuestModeActive {
                    Text("experience.access.guest").foregroundStyle(XL.muted)
                }
                if failed { Text("feedback.temp.failed").foregroundStyle(XL.danger) }
                Button("experience.access.start") {
                    if vm.temporaryUnlock(minutes: minutes, selection: selectedOnly ? selection : nil) { dismiss() }
                    else { failed = true }
                }
                .buttonStyle(XLPrimaryButtonStyle())
                .disabled((selectedOnly && !validSelection) || vm.isGuestModeActive || !LockerViewModel.temporaryAccessMinutes.contains(minutes))
            }
            .navigationTitle("experience.access.title")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("common.close") { dismiss() } }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("common.ok") { durationFocused = false }
                }
            }
            .familyActivityPicker(isPresented: $picker, selection: $selection)
        }
        .tint(XL.primary)
    }

    @ViewBuilder
    private func scopeOption(_ title: LocalizedStringKey, value: Bool) -> some View {
        Button { selectedOnly = value } label: {
            HStack(alignment: .top, spacing: XL.Space.m) {
                Image(systemName: selectedOnly == value ? "checkmark.circle.fill" : "circle")
                    .accessibilityHidden(true)
                Text(title)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selectedOnly == value ? .isSelected : [])
    }
}
