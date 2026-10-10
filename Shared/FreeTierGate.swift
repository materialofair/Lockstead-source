enum FreeTierGate {
    static let freeAppLimit = 1

    static func canManage(appCount: Int, isVIP: Bool) -> Bool {
        isVIP || appCount <= freeAppLimit
    }

    static func requiresPaywall(newCount: Int, isVIP: Bool) -> Bool {
        !canManage(appCount: newCount, isVIP: isVIP)
    }
}
