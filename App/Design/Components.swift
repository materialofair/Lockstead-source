import SwiftUI

// MARK: - 卡片

/// 标准卡片:surface 填充 + 1px 边线 + 连续圆角。不嵌套、不叠阴影。
struct XLCard<Content: View>: View {
    var padding: CGFloat = XL.Space.l
    var fill: Color = XL.surface
    var stroke: Color = XL.border
    var cornerRadius: CGFloat = XL.cardRadius
    @ViewBuilder var content: Content

    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(fill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(stroke, lineWidth: 1)
            )
    }
}

/// 区块标题:卡片组上方的小标题。
struct XLSectionTitle: View {
    let key: LocalizedStringKey
    var body: some View {
        Text(key)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(XL.muted)
            .padding(.leading, XL.Space.xs)
    }
}

// MARK: - 图标徽章

struct IconBadge: View {
    enum Style { case primary, accent, muted, danger }
    let systemName: String
    var style: Style = .primary
    var size: CGFloat = 28

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: size * 0.5, weight: .medium))
            .foregroundStyle(fg)
            .frame(width: size, height: size)
            .background(
                RoundedRectangle(cornerRadius: XL.badgeRadius, style: .continuous)
                    .fill(bg)
            )
            .accessibilityHidden(true)
    }

    private var fg: Color {
        switch style {
        case .primary: XL.primary
        case .accent: XL.accent
        case .muted: XL.muted
        case .danger: XL.danger
        }
    }

    private var bg: Color {
        switch style {
        case .primary: XL.primaryTint
        case .accent: XL.accentTint
        case .muted: XL.surface2
        case .danger: XL.danger.opacity(0.12)
        }
    }
}

// MARK: - 按钮

/// 全宽主按钮:primary 填充,按压 primaryDeep。
struct XLPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .foregroundStyle(XL.onPrimary)
            .frame(maxWidth: .infinity, minHeight: XL.buttonHeight)
            .background(
                RoundedRectangle(cornerRadius: XL.buttonRadius, style: .continuous)
                    .fill(configuration.isPressed ? XL.primaryDeep : XL.primary)
            )
            .opacity(isEnabled ? 1 : 0.4)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

/// 全宽次按钮:primaryTint 底、primary 字。
struct XLTintedButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .foregroundStyle(XL.primary)
            .frame(maxWidth: .infinity, minHeight: XL.buttonHeight)
            .background(
                RoundedRectangle(cornerRadius: XL.buttonRadius, style: .continuous)
                    .fill(XL.primaryTint)
            )
            .opacity(configuration.isPressed ? 0.7 : (isEnabled ? 1 : 0.4))
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

/// 时长胶囊 chip。
struct XLChip: View {
    let key: LocalizedStringKey
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(key)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(XL.primary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, XL.Space.l)
                .padding(.vertical, XL.Space.s + 2)
                .background(Capsule().fill(XL.primaryTint))
        }
        .buttonStyle(.plain)
        .frame(minHeight: 44) // HIG 最小点击区域,视觉胶囊保持原尺寸
    }
}

// MARK: - 行组件

/// 开关行:图标徽章 + 标题/副题 + Toggle。
struct XLToggleRow: View {
    let icon: String
    let title: LocalizedStringKey
    var subtitle: LocalizedStringKey? = nil
    @Binding var isOn: Bool
    var disabled: Bool = false

    var body: some View {
        Toggle(isOn: $isOn) {
            HStack(spacing: XL.Space.m) {
                IconBadge(systemName: icon, style: disabled ? .muted : .primary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.body)
                        .foregroundStyle(XL.ink)
                    if let subtitle {
                        Text(subtitle)
                            .font(.footnote)
                            .foregroundStyle(XL.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .toggleStyle(.switch)
        .tint(XL.primary)
        .disabled(disabled)
    }
}

/// 导航行:图标徽章 + 标题 + 尾注 + chevron。
struct XLNavRow: View {
    let icon: String
    let title: LocalizedStringKey
    var detail: Text? = nil
    var style: IconBadge.Style = .primary
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: XL.Space.m) {
                IconBadge(systemName: icon, style: style)
                Text(title)
                    .font(.body)
                    .foregroundStyle(XL.ink)
                Spacer(minLength: XL.Space.s)
                if let detail {
                    detail
                        .font(.subheadline)
                        .foregroundStyle(XL.muted)
                }
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(XL.muted)
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 状态卡(Home 首位,状态先行)

enum GuardState: Equatable {
    case active(appCount: Int)
    case inactive
    case partialUnlock(until: Date)
    case tempUnlock(until: Date)
    case scheduledIdle(startsAt: String) // 时间表已开启,当前在窗外待命
    case guestActive(until: Date)        // 访客模式:只放行白名单
}

struct StatusCard: View {
    let state: GuardState
    var setupProgress: GuardSetupProgress? = nil
    var actionTitle: LocalizedStringKey? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        XLCard(
            padding: XL.dashboardPadding,
            fill: fill,
            stroke: .clear,
            cornerRadius: XL.dashboardRadius
        ) {
            VStack(alignment: .leading, spacing: XL.Space.m) {
                HStack(spacing: XL.Space.l) {
                    Image(systemName: icon)
                        .font(.system(size: 30, weight: .medium))
                        .foregroundStyle(iconColor)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(title)
                            .font(.title3.weight(.bold))
                            .foregroundStyle(XL.ink)
                        subtitle
                            .font(.subheadline)
                            .foregroundStyle(XL.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .accessibilityElement(children: .combine)
                if let setupProgress, setupProgress != .complete {
                    HStack(spacing: XL.Space.s) {
                        Text(verbatim: setupProgress == .chooseApps ? "1 / 2" : "2 / 2")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(XL.primary)
                            .padding(.horizontal, XL.Space.s)
                            .padding(.vertical, XL.Space.xs)
                            .background(
                                RoundedRectangle(cornerRadius: XL.badgeRadius, style: .continuous)
                                    .fill(XL.surface.opacity(0.78))
                            )
                        Text(setupProgress == .chooseApps ? "home.setup.choose" : "home.setup.enable")
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(XL.ink)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .accessibilityElement(children: .combine)
                }
                if let actionTitle, let action {
                    if setupProgress != nil {
                        Button(actionTitle, action: action)
                            .buttonStyle(XLPrimaryButtonStyle())
                    } else {
                        Button(action: action) {
                            Text(actionTitle)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(iconColor)
                                .frame(maxWidth: .infinity, minHeight: 36)
                                .background(
                                    RoundedRectangle(cornerRadius: XL.buttonRadius, style: .continuous)
                                        .fill(XL.surface.opacity(0.72))
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var fill: Color {
        switch state {
        case .active: XL.primaryTint
        case .inactive: XL.surface2
        case .tempUnlock, .partialUnlock: XL.accentTint
        case .scheduledIdle: XL.surface2
        case .guestActive: XL.primaryTint
        }
    }

    private var icon: String {
        switch state {
        case .active: "checkmark.shield.fill"
        case .inactive: "shield.slash"
        case .tempUnlock, .partialUnlock: "clock.badge.exclamationmark"
        case .scheduledIdle: "clock.badge.checkmark"
        case .guestActive: "person.badge.shield.checkmark.fill"
        }
    }

    private var iconColor: Color {
        switch state {
        case .active: XL.primary
        case .inactive: XL.muted
        case .tempUnlock, .partialUnlock: XL.accent
        case .scheduledIdle: XL.primary
        case .guestActive: XL.primary
        }
    }

    private var title: LocalizedStringKey {
        switch state {
        case .active: "home.status.active.title"
        case .inactive: "home.status.inactive.title"
        case .tempUnlock: "home.status.tempunlock.title"
        case .partialUnlock: "experience.access.partial.active"
        case .scheduledIdle: "home.status.scheduled.title"
        case .guestActive: "home.status.guest.title"
        }
    }

    private var subtitle: Text {
        switch state {
        case .active(let count):
            Text("home.status.active.subtitle \(count)")
        case .inactive:
            Text("home.status.inactive.subtitle")
        case .tempUnlock(let until), .partialUnlock(let until):
            Text("home.status.tempunlock.until \(until.formatted(date: .omitted, time: .shortened))")
                .monospacedDigit()
        case .scheduledIdle(let startsAt):
            Text("home.status.scheduled.subtitle \(startsAt)")
                .monospacedDigit()
        case .guestActive(let until):
            Text("home.status.guest.until \(until.formatted(date: .omitted, time: .shortened))")
                .monospacedDigit()
        }
    }
}

struct OperationFeedbackBanner: View {
    let feedback: OperationFeedback

    var body: some View {
        HStack(spacing: XL.Space.m) {
            Image(systemName: feedback.isFailure ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                .foregroundStyle(feedback.isFailure ? XL.danger : XL.primary)
            message
                .font(.subheadline.weight(.medium))
                .foregroundStyle(XL.ink)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, XL.Space.l)
        .frame(minHeight: 48)
        .background(
            RoundedRectangle(cornerRadius: XL.buttonRadius, style: .continuous)
                .fill(XL.surface)
                .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
        )
        .overlay(
            RoundedRectangle(cornerRadius: XL.buttonRadius, style: .continuous)
                .strokeBorder(feedback.isFailure ? XL.danger.opacity(0.35) : XL.border, lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
    }

    private var message: Text {
        switch feedback {
        case .lockEnabled:
            Text("feedback.lock.enabled")
        case .temporaryUnlockStarted(let until):
            Text("feedback.temp.started \(until.formatted(date: .omitted, time: .shortened))")
        case .temporaryUnlockFailed:
            Text("feedback.temp.failed")
        case .temporaryUnlockEnded:
            Text("feedback.temp.ended")
        case .guestModeStarted(let until):
            Text("feedback.guest.started \(until.formatted(date: .omitted, time: .shortened))")
        case .guestModeFailed:
            Text("feedback.guest.failed")
        case .guestModeEnded:
            Text("feedback.guest.ended")
        case .scheduleEnabled:
            Text("feedback.schedule.enabled")
        case .scheduleFailed:
            Text("feedback.schedule.failed")
        case .scheduleDisabled:
            Text("feedback.schedule.disabled")
        case .selectionApplied(let itemCount):
            Text("feedback.selection.applied \(itemCount)")
        case .restrictionsCleared:
            Text("feedback.restrictions.cleared")
        }
    }
}

private struct OperationFeedbackModifier: ViewModifier {
    let vm: LockerViewModel

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .top) {
                if let feedback = vm.feedback {
                    OperationFeedbackBanner(feedback: feedback)
                        .padding(.horizontal, XL.screenPadding)
                        .padding(.top, XL.Space.s)
                        .onTapGesture { vm.dismissFeedback() }
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .zIndex(10)
                }
            }
            .animation(.easeOut(duration: 0.2), value: vm.feedback)
            .task(id: vm.feedback) {
                guard let current = vm.feedback else { return }
                try? await Task.sleep(for: .seconds(3))
                if vm.feedback == current { vm.dismissFeedback() }
            }
            .sensoryFeedback(.success, trigger: vm.feedback) { _, newValue in
                newValue?.isFailure == false
            }
            .sensoryFeedback(.error, trigger: vm.feedback) { _, newValue in
                newValue?.isFailure == true
            }
    }
}

extension View {
    func operationFeedback(_ vm: LockerViewModel) -> some View {
        modifier(OperationFeedbackModifier(vm: vm))
    }
}

// MARK: - PIN 组件

/// PIN 圆点指示器:已输入=实心,错误=danger 抖动(减弱动态时仅变色)。
struct PINDots: View {
    let entered: Int
    var total: Int = 6
    var isError: Bool = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: XL.Space.l) {
            ForEach(0..<total, id: \.self) { i in
                Circle()
                    .fill(i < entered ? (isError ? XL.danger : XL.primary) : XL.surface2)
                    .overlay(Circle().strokeBorder(isError ? XL.danger : XL.border, lineWidth: 1))
                    .frame(width: 14, height: 14)
            }
        }
        .offset(x: isError && !reduceMotion ? shakeOffset : 0)
        .animation(
            isError && !reduceMotion
                ? .easeOut(duration: 0.08).repeatCount(5, autoreverses: true)
                : .easeOut(duration: 0.15),
            value: isError
        )
        // 盲操作用户依赖 VoiceOver 得知输入进度(圆点只有视觉反馈)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("pin.dots"))
        .accessibilityValue(Text(isError ? "pin.dots.count.error \(entered)" : "pin.dots.count \(entered)"))
    }

    private var shakeOffset: CGFloat { 6 }
}

/// 自绘数字键盘:3×4,对齐 iOS 锁屏惯例。
struct PINPad: View {
    var disabled: Bool = false
    var onDigit: (String) -> Void
    var onDelete: () -> Void

    private let rows: [[String]] = [["1", "2", "3"], ["4", "5", "6"], ["7", "8", "9"]]

    var body: some View {
        VStack(spacing: XL.Space.m) {
            ForEach(rows, id: \.self) { row in
                HStack(spacing: XL.Space.xxl) {
                    ForEach(row, id: \.self) { d in
                        key(digit: d)
                    }
                }
            }
            HStack(spacing: XL.Space.xxl) {
                Color.clear.frame(width: keySize, height: keySize)
                key(digit: "0")
                Button(action: onDelete) {
                    Image(systemName: "delete.backward")
                        .font(.title3.weight(.medium))
                        .foregroundStyle(disabled ? XL.muted : XL.ink)
                        .frame(width: keySize, height: keySize)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .disabled(disabled)
                .accessibilityLabel(Text("pin.pad.delete"))
            }
        }
        .opacity(disabled ? 0.45 : 1)
    }

    private var keySize: CGFloat { 72 }

    private func key(digit: String) -> some View {
        Button {
            onDigit(digit)
        } label: {
            Text(digit)
                .font(.title2.weight(.medium))
                .monospacedDigit()
                .foregroundStyle(XL.ink)
                .frame(width: keySize, height: keySize)
                .background(Circle().fill(XL.surface2))
        }
        .buttonStyle(PINKeyStyle())
        .disabled(disabled)
    }
}

private struct PINKeyStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(Circle().fill(configuration.isPressed ? XL.primaryTint : .clear))
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

// MARK: - 升级入口(安静的一行)

struct UpgradeRow: View {
    var action: () -> Void

    var body: some View {
        XLCard(padding: XL.Space.m) {
            Button(action: action) {
                HStack(spacing: XL.Space.m) {
                    IconBadge(systemName: "crown.fill", style: .accent)
                    Text("home.upgrade.banner")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(XL.ink)
                    Spacer(minLength: XL.Space.s)
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(XL.muted)
                }
            }
            .buttonStyle(.plain)
        }
    }
}
