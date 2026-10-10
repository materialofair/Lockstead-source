import SwiftUI
import UIKit

struct AppIconPickerSection: View {
    @Environment(EntitlementStore.self) private var entitlements
    @State private var selectedIconName = UIApplication.shared.alternateIconName
    @State private var errorMessage: String?
    var onVIPBlocked: () -> Void

    private let icons: [AppIconOption] = [
        .init(id: "midnight", name: "appicon.name.midnight", iconName: nil, previewAsset: "IconPreview-Primary", requiresVIP: false),
        .init(id: "paper", name: "appicon.name.paper", iconName: "AppIcon-Paper", previewAsset: "IconPreview-Paper", requiresVIP: true),
        .init(id: "pebble", name: "appicon.name.pebble", iconName: "AppIcon-Pebble", previewAsset: "IconPreview-Pebble", requiresVIP: true),
        .init(id: "calculator", name: "appicon.name.calculator", iconName: "AppIcon-Calculator", previewAsset: "IconPreview-Calculator", requiresVIP: true)
    ]

    var body: some View {
        Text("settings.appicon.section")
            .font(.headline)
            .foregroundStyle(XL.ink)

        XLCard(padding: XL.Space.m) {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: XL.Space.l) {
                ForEach(icons) { icon in
                    Button { select(icon) } label: {
                        VStack(spacing: XL.Space.xs) {
                            Image(icon.previewAsset)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 64, height: 64)
                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .strokeBorder(isSelected(icon) ? XL.primary : XL.border,
                                                      lineWidth: isSelected(icon) ? 2 : 1)
                                }
                                .overlay(alignment: .bottomTrailing) {
                                    if isSelected(icon) {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(XL.primary)
                                            .background(Circle().fill(XL.surface))
                                            .offset(x: 4, y: 4)
                                    }
                                }
                                .overlay(alignment: .topTrailing) {
                                    if icon.requiresVIP && !entitlements.isVIP {
                                        Image(systemName: "lock.fill")
                                            .font(.system(size: 10, weight: .bold))
                                            .foregroundStyle(XL.accent)
                                            .padding(5)
                                            .background(Circle().fill(XL.surface))
                                            .overlay(Circle().strokeBorder(XL.border, lineWidth: 0.5))
                                            .offset(x: 4, y: -4)
                                    }
                                }
                            Text(icon.name)
                                .font(.caption.weight(.medium))
                                .foregroundStyle(XL.ink)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(icon.name)
                    .accessibilityAddTraits(isSelected(icon) ? .isSelected : [])
                    .accessibilityHint(icon.requiresVIP && !entitlements.isVIP
                                       ? Text("settings.vip.locked.hint") : Text(verbatim: ""))
                }
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(XL.danger)
                    .padding(.top, XL.Space.s)
            }
        }
    }

    private func isSelected(_ icon: AppIconOption) -> Bool {
        selectedIconName == icon.iconName
    }

    private func select(_ icon: AppIconOption) {
        guard !isSelected(icon) else { return }
        guard !icon.requiresVIP || entitlements.isVIP else {
            onVIPBlocked()
            return
        }
        guard UIApplication.shared.supportsAlternateIcons else {
            errorMessage = String(localized: "appicon.error.unsupported")
            return
        }

        UIApplication.shared.setAlternateIconName(icon.iconName) { error in
            DispatchQueue.main.async {
                if error == nil {
                    selectedIconName = icon.iconName
                    errorMessage = nil
                } else {
                    errorMessage = String(localized: "appicon.error.failed")
                }
            }
        }
    }
}

private struct AppIconOption: Identifiable {
    let id: String
    let name: LocalizedStringKey
    let iconName: String?
    let previewAsset: String
    let requiresVIP: Bool
}
