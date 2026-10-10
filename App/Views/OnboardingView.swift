import SwiftUI
import FamilyControls

struct OnboardingView: View {
    let onAuthorized: () -> Void
    @State private var errorText: String?
    @State private var requesting = false

    var body: some View {
        GeometryReader { geometry in
            ScrollView(.vertical) {
                VStack(spacing: 0) {
                    Spacer(minLength: XL.Space.xxxl)

                    // 品牌盾徽
                    Image(systemName: "lock.shield.fill")
                        .font(.system(size: 44, weight: .medium))
                        .foregroundStyle(XL.primary)
                        .frame(width: 92, height: 92)
                        .background(
                            RoundedRectangle(cornerRadius: 24, style: .continuous)
                                .fill(XL.primaryTint)
                        )

                    Text("welcome.title")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(XL.ink)
                        .multilineTextAlignment(.center)
                        .padding(.top, XL.Space.xxl)

                    Text("welcome.body")
                        .font(.subheadline)
                        .foregroundStyle(XL.muted)
                        .multilineTextAlignment(.center)
                        .padding(.top, XL.Space.s)

                    // 三行能力
                    VStack(alignment: .leading, spacing: XL.Space.l) {
                        featureRow(icon: "lock.fill", key: "onboarding.feature.lock")
                        featureRow(icon: "calendar.badge.clock", key: "onboarding.feature.schedule")
                        featureRow(icon: "timer", key: "onboarding.feature.temp")
                    }
                    .padding(.top, XL.Space.xxxl)
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Spacer(minLength: XL.Space.xl)

                    if let errorText {
                        XLCard(padding: XL.Space.m, stroke: XL.danger.opacity(0.5)) {
                            VStack(alignment: .leading, spacing: XL.Space.xs) {
                                Text(errorText)
                                    .font(.footnote.weight(.medium))
                                    .foregroundStyle(XL.danger)
                                Text("auth.failure.reasons")
                                    .font(.footnote)
                                    .foregroundStyle(XL.muted)
                            }
                        }
                        .padding(.bottom, XL.Space.m)
                    }

                    // 信任行
                    Label {
                        Text("onboarding.privacy")
                            .font(.footnote)
                            .foregroundStyle(XL.muted)
                    } icon: {
                        Image(systemName: "hand.raised.fill")
                            .font(.footnote)
                            .foregroundStyle(XL.primary)
                    }
                    .padding(.bottom, XL.Space.m)

                    Button(action: requestAuth) {
                        if requesting {
                            ProgressView().tint(XL.onPrimary)
                        } else {
                            Text("auth.button")
                        }
                    }
                    .buttonStyle(XLPrimaryButtonStyle())
                    .disabled(requesting)
                }
                .padding(.horizontal, XL.screenPadding)
                .padding(.bottom, XL.Space.xl)
                .frame(maxWidth: .infinity, minHeight: geometry.size.height)
            }
            .scrollBounceBehavior(.basedOnSize)
            .scrollIndicators(.hidden)
        }
        .background(XL.bg)
    }

    private func featureRow(icon: String, key: LocalizedStringKey) -> some View {
        HStack(spacing: XL.Space.m) {
            IconBadge(systemName: icon)
            Text(key)
                .font(.body)
                .foregroundStyle(XL.ink)
        }
    }

    private func requestAuth() {
        requesting = true
        Task {
            do {
                try await AuthorizationCenter.shared.requestAuthorization(for: .individual)
                errorText = nil
                onAuthorized()
            } catch {
                errorText = error.localizedDescription // 可重试,不卡死
            }
            requesting = false
        }
    }
}
