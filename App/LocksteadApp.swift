import SwiftUI
import FamilyControls

@main
struct LocksteadApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @State private var lockerVM = LockerViewModel()
    @State private var entitlements = EntitlementStore()
    @State private var sessionUnlocked = false
    @State private var authStatusTick = 0 // 授权后触发重算
    @State private var lastSyncedAuthorized: Bool? = nil // 上次前台校准时的授权状态(nil = 本次启动尚未校准)

    var body: some Scene {
        WindowGroup {
            content
                .environment(lockerVM)
                .environment(entitlements)
                .tint(XL.primary)
                .background(XL.bg)
                .onAppear { entitlements.start() }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active {
                        syncAuthorization()
                        entitlements.syncReviewAccess()
                        lockerVM.reloadFromAppGroup() // 冷启动/回前台校准(spec 第 5 节)
                        authStatusTick += 1
                    } else if phase == .background {
                        sessionUnlocked = false // 后台后必须重新验证 PIN,已解锁会话不得跨后台存活
                    }
                }
        }
    }

    @ViewBuilder
    private var content: some View {
        #if DEBUG
        if let preview = DesignGallery.screen {
            DesignGallery.view(for: preview)
                .environment(lockerVM)
                .environment(entitlements)
        } else {
            routedContent
        }
        #else
        routedContent
        #endif
    }

    @ViewBuilder
    private var routedContent: some View {
        let _ = authStatusTick
        let route = RootRoute.determine(
            isAuthorized: AuthorizationCenter.shared.authorizationStatus == .approved,
            hasPIN: PINManager().hasPIN(in: AppGroupStore().load()),
            sessionUnlocked: sessionUnlocked
        )
        switch route {
        case .onboarding: OnboardingView { syncAuthorization(); authStatusTick += 1 }
        case .pinSetup: PINSetupView { sessionUnlocked = true; authStatusTick += 1 }
        case .pinEntry:
            if AppGroupStore().load().loginMode == .calculator {
                CalculatorLoginView { sessionUnlocked = true }
            } else {
                PINEntryView { sessionUnlocked = true }
            }
        case .home: HomeView()
        }
    }

    /// 回前台/授权变化时校准:授权在则重算自愈,撤销则清残留(见 AuthorizationGuard)
    private func syncAuthorization() {
        let isAuthorized = AuthorizationCenter.shared.authorizationStatus == .approved
        AuthorizationGuard.foregroundSync(
            isAuthorized: isAuthorized,
            previousAuthorized: lastSyncedAuthorized,
            store: AppGroupStore(),
            restrictions: ManagedSettingsRestrictions(),
            unlockScheduler: DeviceActivityUnlockScheduler(),
            lockScheduler: DeviceActivityLockScheduler(),
            guestScheduler: DeviceActivityGuestScheduler(),
            now: Date()
        )
        lastSyncedAuthorized = isAuthorized
    }
}
