enum SelectionOutcome: Equatable {
    case ok
    case needsPaywall
    case unsupportedKinds
}

enum SelectionPolicy {
    static func evaluate(appCount: Int, categoryCount: Int, webDomainCount: Int, isVIP: Bool) -> SelectionOutcome {
        if webDomainCount > 0 { return .unsupportedKinds }
        // 类别 = 无限量 App,免费档 1 个 App 的边界不能被一个类别绕过
        if categoryCount > 0 && !isVIP { return .needsPaywall }
        if FreeTierGate.requiresPaywall(newCount: appCount, isVIP: isVIP) { return .needsPaywall }
        return .ok
    }
}
