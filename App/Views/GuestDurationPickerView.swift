import SwiftUI

/// 访客模式自定义时长:小时 + 分钟滚轮,范围 15 分钟–12 小时(见 GuardActions)
struct GuestDurationPickerView: View {
    let onStart: (Int) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var hours = 2
    @State private var minutes = 0

    private var totalMinutes: Int { hours * 60 + minutes }
    private var isValid: Bool { GuardActions.isValidGuestDuration(totalMinutes) }

    var body: some View {
        NavigationStack {
            XLScreen(spacing: XL.Space.l) {
                XLCard(padding: XL.Space.m) {
                    HStack(spacing: 0) {
                        Picker("guest.custom.hours", selection: $hours) {
                            ForEach(0...12, id: \.self) { h in
                                Text("guest.custom.hours \(h)").tag(h)
                            }
                        }
                        .pickerStyle(.wheel)
                        Picker("guest.custom.minutes", selection: $minutes) {
                            ForEach(Array(stride(from: 0, through: 55, by: 5)), id: \.self) { m in
                                Text("guest.custom.minutes \(m)").tag(m)
                            }
                        }
                        .pickerStyle(.wheel)
                    }
                    .frame(height: 180)
                }

                // 诚实即品牌:边界直接写在功能旁边
                if !isValid {
                    Text("guest.custom.invalid")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(XL.danger)
                        .padding(.horizontal, XL.Space.xs)
                }

                Button("guest.custom.start") {
                    onStart(totalMinutes)
                    dismiss()
                }
                .buttonStyle(XLPrimaryButtonStyle())
                .disabled(!isValid)
                .padding(.top, XL.Space.s)
            }
            .navigationTitle("guest.custom.title")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                Button("common.close") { dismiss() }
                    .foregroundStyle(XL.ink)
            }
            .toolbarBackground(XL.bg, for: .navigationBar)
        }
        .tint(XL.primary)
        .presentationDetents([.medium])
    }
}

struct GuestModePreflightView: View {
    let preview: GuestModePreview
    let onConfirm: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            XLScreen(spacing: XL.Space.l) {
                XLCard(padding: XL.Space.m, fill: XL.primaryTint) {
                    VStack(alignment: .leading, spacing: XL.Space.m) {
                        impactRow(icon: "checkmark.circle.fill", text: Text("guest.preflight.allowed \(preview.allowedAppCount)"))
                        impactRow(icon: "shield.slash.fill", text: Text("guest.preflight.blocked"))
                        impactRow(
                            icon: "clock.fill",
                            text: Text("guest.preflight.ends \(preview.endsAt.formatted(date: .omitted, time: .shortened))")
                                .monospacedDigit()
                        )
                    }
                }

                Text("guest.preflight.warning")
                    .font(.footnote)
                    .foregroundStyle(XL.muted)
                    .padding(.horizontal, XL.Space.xs)

                Button("guest.preflight.confirm") {
                    onConfirm()
                    dismiss()
                }
                .buttonStyle(XLPrimaryButtonStyle())
            }
            .navigationTitle("guest.preflight.title")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                Button("common.close") { dismiss() }
                    .foregroundStyle(XL.ink)
            }
            .toolbarBackground(XL.bg, for: .navigationBar)
        }
        .tint(XL.primary)
        .presentationDetents([.medium])
    }

    private func impactRow(icon: String, text: Text) -> some View {
        HStack(spacing: XL.Space.m) {
            IconBadge(systemName: icon)
            text
                .font(.subheadline)
                .foregroundStyle(XL.ink)
        }
    }
}
