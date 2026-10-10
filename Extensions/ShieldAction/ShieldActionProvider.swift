import ManagedSettings

class ShieldActionProvider: ShieldActionDelegate {
    override func handle(action: ShieldAction, for application: ApplicationToken,
                         completionHandler: @escaping (ShieldActionResponse) -> Void) {
        switch action {
        case .primaryButtonPressed:
            completionHandler(.close)
        default:
            completionHandler(.none)
        }
    }
}
