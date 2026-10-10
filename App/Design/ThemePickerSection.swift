import SwiftUI

/// 设置页「主题」区:6 色样圆片,当前打勾,VIP 主题带锁角标。
struct ThemePickerSection: View {
    @Environment(EntitlementStore.self) private var entitlements
    var onVIPBlocked: () -> Void

    var body: some View {
        XLSectionTitle(key: "settings.theme.section")
        XLCard(padding: XL.Space.l) {
            HStack(spacing: XL.Space.l) {
                ForEach(XLThemeID.allCases, id: \.self) { theme in
                    swatch(theme)
                }
                Spacer(minLength: 0)
            }
        }
    }

    private func swatch(_ theme: XLThemeID) -> some View {
        let isCurrent = ThemeStore.shared.current == theme
        let locked = !ThemePolicy.canUse(theme, isVIP: entitlements.isVIP)
        return Button {
            if locked {
                onVIPBlocked() // 弹 Paywall,不切换
            } else {
                withAnimation(.easeOut(duration: 0.2)) {
                    ThemeStore.shared.current = theme
                }
            }
        } label: {
            ZStack(alignment: .topTrailing) {
                Circle()
                    .fill(Color(XLThemeCatalog.swatch(for: theme)))
                    .frame(width: 36, height: 36)
                    .overlay(
                        Circle().strokeBorder(
                            isCurrent ? XL.ink.opacity(0.85) : XL.border,
                            lineWidth: isCurrent ? 2 : 1
                        )
                    )
                    .overlay {
                        if isCurrent {
                            Image(systemName: "checkmark")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.white)
                        }
                    }
                if locked {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(XL.muted)
                        .padding(3)
                        .background(Circle().fill(XL.surface))
                        .overlay(Circle().strokeBorder(XL.border, lineWidth: 0.5))
                        .offset(x: 4, y: -4)
                }
            }
            .frame(width: 44, height: 44) // 视觉 36pt 圆片,点击区域补足 HIG 44pt
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(nameKey(theme)))
        .accessibilityAddTraits(isCurrent ? [.isSelected] : [])
        .accessibilityHint(locked ? Text("settings.vip.locked.hint") : Text(verbatim: ""))
    }

    private func nameKey(_ theme: XLThemeID) -> LocalizedStringKey {
        switch theme {
        case .guardGreen: "theme.name.guardGreen"
        case .teal: "theme.name.teal"
        case .indigo: "theme.name.indigo"
        case .amber: "theme.name.amber"
        case .plum: "theme.name.plum"
        case .coral: "theme.name.coral"
        }
    }
}
