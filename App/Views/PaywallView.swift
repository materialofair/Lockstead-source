import SwiftUI
import StoreKit

/// 法务链接:EULA 用 Apple 标准协议,隐私政策托管于公开的 lockstead-site 仓库(GitHub Pages)
enum LegalLinks {
    static let termsOfUse = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!
    static let privacyPolicy = URL(string: "https://materialofair.github.io/lockstead-site/privacy.html")!
}

struct PaywallView: View {
    @Environment(EntitlementStore.self) private var entitlements
    @Environment(\.dismiss) private var dismiss
    @State private var purchasing = false
    @State private var selectedID: String?
    var pendingItemCount: Int?

    init(pendingItemCount: Int? = nil) {
        self.pendingItemCount = pendingItemCount
    }

    var body: some View {
        NavigationStack {
            XLScreen(spacing: XL.Space.l) {
                VStack(alignment: .leading, spacing: XL.Space.s) {
                    Text("paywall.title")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(XL.ink)
                    Text("paywall.body")
                        .font(.subheadline)
                        .foregroundStyle(XL.muted)
                }
                .padding(.top, XL.Space.s)

                if let pendingItemCount {
                    XLCard {
                        Label {
                            Text("paywall.selection.context \(pendingItemCount)")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(XL.ink)
                        } icon: {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(XL.primary)
                        }
                    }
                }

                // 权益列表:先讲开发者构建的管理与隐私工作流,不把系统 API 当作商品。
                VStack(alignment: .leading, spacing: XL.Space.m) {
                    perkRow(icon: "square.grid.2x2.fill", key: "paywall.perk.unlimited")
                    perkRow(icon: "checklist", key: "paywall.perk.modes")
                    perkRow(icon: "person.badge.shield.checkmark.fill", key: "paywall.perk.guest")
                    perkRow(icon: "trash.slash.fill", key: "paywall.perk.antiremoval")
                    perkRow(icon: "paintpalette.fill", key: "paywall.perk.personalization")
                }
                .padding(.vertical, XL.Space.xs)

                if entitlements.products.isEmpty {
                    XLCard {
                        if entitlements.isLoadingProducts || entitlements.lastError == nil {
                            HStack(spacing: XL.Space.m) {
                                ProgressView().tint(XL.primary)
                                Text("paywall.loading")
                                    .font(.subheadline)
                                    .foregroundStyle(XL.muted)
                            }
                            .frame(maxWidth: .infinity, alignment: .center)
                        } else {
                            VStack(alignment: .leading, spacing: XL.Space.m) {
                                Label("paywall.load.failed", systemImage: "exclamationmark.triangle.fill")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(XL.danger)
                                if let error = entitlements.lastError {
                                    Text(error)
                                        .font(.footnote)
                                        .foregroundStyle(XL.muted)
                                }
                                Button("paywall.retry") {
                                    Task { await entitlements.loadProducts() }
                                }
                                .buttonStyle(XLTintedButtonStyle())
                            }
                        }
                    }
                } else {
                    VStack(spacing: XL.Space.m) {
                        ForEach(entitlements.products, id: \.id) { product in
                            PlanCard(
                                title: localizedPlanName(for: product),
                                price: product.displayPrice,
                                isSelected: product.id == effectiveSelectedID,
                                isRecommended: product.id == VIPProducts.lifetime
                            ) {
                                selectedID = product.id
                            }
                        }
                    }
                }

                if !entitlements.products.isEmpty, let err = entitlements.lastError {
                    Text(err) // 具体错误,不静默
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(XL.danger)
                }

                Button {
                    guard let product = selectedProduct else { return }
                    purchasing = true
                    Task {
                        await entitlements.purchase(product)
                        purchasing = false
                        if entitlements.isVIP { dismiss() }
                    }
                } label: {
                    if purchasing {
                        ProgressView().tint(XL.onPrimary)
                    } else if let product = selectedProduct {
                        Text("paywall.cta \(product.displayPrice)")
                    } else {
                        Text("paywall.cta.empty")
                    }
                }
                .buttonStyle(XLPrimaryButtonStyle())
                .disabled(purchasing || selectedProduct == nil)
                .padding(.top, XL.Space.s)

                Button {
                    Task {
                        await entitlements.restore()
                        if entitlements.isVIP { dismiss() } // 找回 VIP 直接放行,不多留一步
                    }
                } label: {
                    if entitlements.isRestoring {
                        ProgressView().tint(XL.muted)
                    } else {
                        Text("paywall.restore")
                    }
                }
                .font(.footnote)
                .foregroundStyle(XL.muted)
                .frame(maxWidth: .infinity)
                .disabled(entitlements.isRestoring)

                if let outcome = entitlements.restoreOutcome, outcome != .restoredVIP {
                    RestoreStatusText(outcome: outcome)
                        .frame(maxWidth: .infinity)
                }

                // 审核指南 3.1.2:自动续订说明 + 使用条款/隐私政策链接,缺一必拒
                VStack(spacing: XL.Space.s) {
                    Text("paywall.autorenew.note")
                        .font(.caption2)
                        .foregroundStyle(XL.muted)
                        .multilineTextAlignment(.center)
                    HStack(spacing: XL.Space.l) {
                        Link("paywall.terms", destination: LegalLinks.termsOfUse)
                        Link("paywall.privacy", destination: LegalLinks.privacyPolicy)
                    }
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(XL.muted)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, XL.Space.s)
            }
            .task { await entitlements.loadProducts() }
            .toolbar {
                Button("common.close") { dismiss() }
                    .foregroundStyle(XL.ink)
            }
            .toolbarBackground(XL.bg, for: .navigationBar)
        }
        .tint(XL.primary)
    }

    // Plan labels follow the app language; StoreKit remains the source of price and terms.
    private func localizedPlanName(for product: Product) -> String {
        switch product.id {
        case VIPProducts.monthly: String(localized: "paywall.plan.monthly")
        case VIPProducts.yearly: String(localized: "paywall.plan.yearly")
        case VIPProducts.lifetime: String(localized: "paywall.plan.lifetime")
        default: product.displayName
        }
    }

    private var effectiveSelectedID: String? {
        selectedID ?? entitlements.products.first(where: { $0.id == VIPProducts.lifetime })?.id
            ?? entitlements.products.first?.id
    }

    private var selectedProduct: Product? {
        entitlements.products.first(where: { $0.id == effectiveSelectedID })
    }

    private func perkRow(icon: String, key: LocalizedStringKey) -> some View {
        HStack(spacing: XL.Space.m) {
            IconBadge(systemName: icon, style: .accent, size: 24)
            Text(key)
                .font(.subheadline)
                .foregroundStyle(XL.ink)
        }
    }
}

/// 恢复购买结果:成功绿、无购买灰、失败红——必须有反馈,不能静默。
struct RestoreStatusText: View {
    let outcome: RestoreOutcome

    var body: some View {
        switch outcome {
        case .restoredVIP:
            Text("restore.success")
                .font(.footnote.weight(.medium))
                .foregroundStyle(XL.primary)
        case .nothingToRestore:
            Text("restore.nothing")
                .font(.footnote)
                .foregroundStyle(XL.muted)
        case .failed(let message):
            Text(message)
                .font(.footnote.weight(.medium))
                .foregroundStyle(XL.danger)
        }
    }
}

/// 可选套餐卡:选中 = primary 2px 边 + 绿洗底;终身档带「推荐」角标。
struct PlanCard: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let title: String
    let price: String
    let isSelected: Bool
    let isRecommended: Bool
    var onTap: () -> Void

    @ViewBuilder
    private var cardContent: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: XL.Space.s) {
                HStack(alignment: .top, spacing: XL.Space.m) {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(isSelected ? XL.primary : XL.border)
                    Text(title)
                        .font(.body.weight(.medium))
                        .foregroundStyle(XL.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if isRecommended {
                    Text("paywall.recommended")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(XL.accent)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, XL.Space.s)
                        .padding(.vertical, 2)
                        .background(RoundedRectangle(cornerRadius: 12).fill(XL.accentTint))
                }
                Text(price)
                    .font(.body.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(XL.ink)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            HStack(spacing: XL.Space.m) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? XL.primary : XL.border)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: XL.Space.s) {
                        Text(title)
                            .font(.body.weight(.medium))
                            .foregroundStyle(XL.ink)
                        if isRecommended {
                            Text("paywall.recommended")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(XL.accent)
                                .padding(.horizontal, XL.Space.s)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(XL.accentTint))
                        }
                    }
                }
                Spacer(minLength: XL.Space.s)
                Text(price)
                    .font(.body.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(XL.ink)
            }
        }
    }

    var body: some View {
        Button(action: onTap) {
            cardContent
            .padding(XL.Space.l)
            .background(
                RoundedRectangle(cornerRadius: XL.cardRadius, style: .continuous)
                    .fill(isSelected ? XL.primaryTint : XL.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: XL.cardRadius, style: .continuous)
                    .strokeBorder(isSelected ? XL.primary : XL.border, lineWidth: isSelected ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
        .animation(.easeOut(duration: 0.15), value: isSelected)
    }
}
