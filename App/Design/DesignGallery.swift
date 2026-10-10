#if DEBUG
import SwiftUI

/// 设计验收画廊(仅 DEBUG):`XL_PREVIEW` 环境变量选择屏幕,
/// 供模拟器截图验收使用。模拟器无法真实授权/选 App/加载 StoreKit 商品,
/// 因此部分形态用注入状态与纯组件采样呈现。
@MainActor
enum DesignGallery {
    static var screen: String? {
        ProcessInfo.processInfo.environment["XL_PREVIEW"]
    }

    /// `XL_THEME` 环境变量选择画廊主题,供截图验收用。
    private static func applyThemeOverride() {
        if let raw = ProcessInfo.processInfo.environment["XL_THEME"],
           let theme = XLThemeID(rawValue: raw) {
            ThemeStore.shared.current = theme
        }
    }

    @ViewBuilder
    static func view(for name: String) -> some View {
        let _ = applyThemeOverride()
        switch name {
        case "calculator":
            CalculatorLoginView(onUnlocked: {})
        case "onboarding":
            OnboardingView(onAuthorized: {})
        case "pinsetup":
            PINSetupView(onDone: {})
        case "pinentry":
            seededThen(Self.seedPIN) { PINEntryView(onUnlocked: {}) }
        case "home":
            seededThen(Self.seedInactive) { HomeView() }
        case "home_temp":
            seededThen(Self.seedTempUnlock) { HomeView() }
        case "diagnostics":
            GuardDiagnosticsView()
        case "schedule":
            ScheduleEditorView(rules: [ScheduleRule(weekdays: Set(2...6), startMinutes: 21 * 60, endMinutes: 7 * 60)]) { _ in true }
        case "scenes":
            seededThen(Self.seedScene) { ScenesView() }
        case "access":
            TemporaryAccessView()
        case "pinmanage":
            PINManagementView(hintOnly: false)
        case "pinhelp":
            PINRecoveryHelpView()
        case "paywall":
            PaywallView()
        case "settings":
            seededThen(Self.seedInactive) { SettingsView() }
        case "sampler":
            ComponentSampler()
        default:
            Text(verbatim: "unknown XL_PREVIEW: \(name)")
        }
    }

    /// 先写入 App Group 种子状态,再构造读取该状态的视图。
    @ViewBuilder
    private static func seededThen<V: View>(_ seed: () -> Void, _ build: () -> V) -> some View {
        let _ = seed()
        build()
            .environment(LockerViewModel())
            .environment(EntitlementStore())
    }

    /// Fictional screenshot samples, never user content or production defaults.
    private static var demoCopy: (hint: String, scene: String) {
        let samples: [String: (hint: String, scene: String)] = [
            "en": ("My favorite place", "Bedtime"),
            "zh-Hans": ("我喜欢的地方", "睡前"),
            "zh-Hant": ("我喜歡的地方", "睡前"),
            "ja": ("お気に入りの場所", "就寝時間"),
            "de": ("Mein Lieblingsort", "Schlafenszeit"),
            "fr": ("Mon endroit préféré", "Heure du coucher"),
            "es": ("Mi lugar favorito", "Hora de dormir"),
            "pt-BR": ("Meu lugar favorito", "Hora de dormir"),
            "pl": ("Moje ulubione miejsce", "Pora snu"),
            "id": ("Tempat favorit saya", "Waktu tidur")
        ]
        let language = Bundle.main.preferredLocalizations.first ?? "en"
        return samples[language] ?? samples["en"]!
    }

    private static func seedPIN() {
        let store = AppGroupStore()
        var s = store.load()
        PINManager().set(pin: "123456", hint: demoCopy.hint, in: &s)
        store.save(s)
    }

    private static func seedInactive() {
        seedPIN()
        let store = AppGroupStore()
        var s = store.load()
        s.isLockEnabled = false
        s.temporaryUnlockUntil = nil
        store.save(s)
    }

    private static func seedScene() {
        seedInactive()
        let store = AppGroupStore()
        var state = store.load()
        state.scenes = [GuardScene(name: demoCopy.scene, state: state)]
        store.save(state)
    }

    private static func seedTempUnlock() {
        seedPIN()
        let store = AppGroupStore()
        var s = store.load()
        s.isLockEnabled = true
        store.save(s)
        // 限时字段单独落 timed 键:encode 刻意不写它们,直接 save(state) 会被静默丢弃
        store.saveTimed(TimedModeState(temporaryUnlockUntil: Date().addingTimeInterval(28 * 60)))
    }
}

/// 组件采样屏:覆盖模拟器上无法真实到达的形态
/// (守护中状态卡、套餐卡、开关行、chips、PIN 组件)。
private struct ComponentSampler: View {
    @State private var on = true
    @State private var off = false

    var body: some View {
        XLScreen {
            XLSectionTitle(key: "sampler.status")
            StatusCard(state: .active(appCount: 3))
            StatusCard(state: .tempUnlock(until: Date().addingTimeInterval(1700)))
            StatusCard(state: .scheduledIdle(startsAt: "21:00"))
            StatusCard(state: .guestActive(until: Date().addingTimeInterval(1800)))
            StatusCard(state: .inactive)

            XLSectionTitle(key: "sampler.plans")
            PlanCard(title: String(localized: "paywall.plan.lifetime"), price: "—", isSelected: true, isRecommended: true) {}
            PlanCard(title: String(localized: "paywall.plan.yearly"), price: "—", isSelected: false, isRecommended: false) {}

            XLSectionTitle(key: "sampler.rows")
            XLCard(padding: XL.Space.m) {
                VStack(spacing: XL.Space.m) {
                    XLToggleRow(icon: "lock.fill", title: "home.toggle.lock",
                                subtitle: "home.toggle.lock.sub", isOn: $on)
                    Divider().overlay(XL.border)
                }
            }
            HStack(spacing: XL.Space.m) {
                XLChip(key: "home.tempunlock.minutes \(15)") {}
                XLChip(key: "home.tempunlock.minutes \(30)") {}
                XLChip(key: "home.tempunlock.minutes \(60)") {}
            }

            XLSectionTitle(key: "sampler.pin")
            HStack {
                Spacer()
                PINDots(entered: 4, isError: false)
                Spacer()
            }
            Button("pin.entry.submit") {}
                .buttonStyle(XLPrimaryButtonStyle())
        }
    }
}
#endif
