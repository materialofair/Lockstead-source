import SwiftUI
import FamilyControls

struct ScenesView: View {
    @Environment(LockerViewModel.self) private var vm
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var renaming: GuardScene?
    @State private var pending: GuardScene?
    @State private var showRename = false
    @State private var error = false
    @State private var showUpgrade = false
    @State private var renameName = ""

    var body: some View {
        NavigationStack {
            XLScreen {
                Text("experience.scenes.intro").font(.footnote).foregroundStyle(XL.muted)
                XLCard {
                    VStack(spacing: XL.Space.m) {
                        TextField("experience.scenes.name", text: $name)
                            .onChange(of: name) { _, value in name = String(value.prefix(40)) }
                        Button("experience.scenes.save") {
                            if vm.saveScene(name: name) { name = "" }
                        }
                        .buttonStyle(XLTintedButtonStyle())
                        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
                if vm.state.scenes.isEmpty {
                    Text("experience.scenes.empty").foregroundStyle(XL.muted)
                }
                ForEach(vm.state.scenes) { scene in
                    XLCard {
                        VStack(alignment: .leading, spacing: XL.Space.m) {
                            HStack {
                                Text(scene.name).font(.headline)
                                Spacer()
                                if vm.state.activeSceneID == scene.id {
                                    Text(scene.matches(vm.state) ? "experience.scenes.current" : "experience.scenes.modified")
                                        .font(.caption).foregroundStyle(XL.primary)
                                }
                                Menu {
                                    Button("experience.scenes.rename") {
                                        renaming = scene
                                        renameName = scene.name
                                        showRename = true
                                    }
                                    Button("experience.scenes.delete", role: .destructive) { vm.deleteScene(scene.id) }
                                } label: {
                                    Image(systemName: "ellipsis.circle").frame(width: 44, height: 44)
                                }
                                .accessibilityLabel("experience.scenes.actions")
                            }
                            SelectionPreview(selection: decode(scene.selectionData), title: scene.lockMode == .allowlist
                                             ? "experience.apps.allowed" : "experience.apps.blocked")
                            Text(scene.isLockEnabled ? "experience.scenes.lock.on" : "experience.scenes.lock.off")
                                .font(.footnote).foregroundStyle(XL.muted)
                            if scene.scheduleEnabled {
                                Text("experience.schedule.count \(scene.scheduleRules.count)")
                                    .font(.footnote).foregroundStyle(XL.muted)
                            }
                            Button("experience.scenes.apply") { pending = scene }
                                .buttonStyle(XLTintedButtonStyle())
                        }
                    }
                }
            }
            .navigationTitle("experience.scenes.title")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { Button("common.close") { dismiss() } }
            .alert("experience.scenes.rename", isPresented: $showRename) {
                TextField("experience.scenes.name", text: $renameName)
                Button("common.cancel", role: .cancel) {}
                Button("schedule.save") {
                    if let renaming { vm.renameScene(renaming.id, name: renameName) }
                }
            }
            .confirmationDialog("experience.scenes.apply", isPresented: Binding(
                get: { pending != nil }, set: { if !$0 { pending = nil } }
            ), titleVisibility: .visible) {
                if let pending {
                    Button(pending.name) {
                        if vm.applyScene(pending.id) { dismiss() }
                        else if vm.showPaywall {
                            vm.showPaywall = false
                            showUpgrade = true
                        } else { error = true }
                        self.pending = nil
                    }
                }
                Button("common.cancel", role: .cancel) { pending = nil }
            } message: {
                Text("experience.scenes.confirm")
            }
            .alert("experience.scenes.failed", isPresented: $error) {
                Button("common.ok", role: .cancel) {}
            }
            .sheet(isPresented: $showUpgrade) { PaywallView() }
        }
        .tint(XL.primary)
    }

    private func decode(_ data: Data?) -> FamilyActivitySelection {
        data.flatMap { try? JSONDecoder().decode(FamilyActivitySelection.self, from: $0) } ?? FamilyActivitySelection()
    }
}
