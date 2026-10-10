enum RootRoute: Equatable {
    case onboarding, pinSetup, pinEntry, home

    static func determine(isAuthorized: Bool, hasPIN: Bool, sessionUnlocked: Bool) -> RootRoute {
        if !isAuthorized { return .onboarding }
        if !hasPIN { return .pinSetup }
        if sessionUnlocked { return .home }
        return .pinEntry
    }
}
