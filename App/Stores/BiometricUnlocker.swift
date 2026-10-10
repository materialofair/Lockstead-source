import Foundation
import LocalAuthentication

/// 生物识别解锁。只接受生物识别(.deviceOwnerAuthenticationWithBiometrics),
/// 不回落设备密码——递手机场景下孩子往往知道设备密码,回落会绕过家长 PIN。
enum BiometricUnlocker {
    enum Kind {
        case faceID, touchID

        /// Face ID / Touch ID 是产品名,不参与本地化
        var displayName: String {
            switch self {
            case .faceID: "Face ID"
            case .touchID: "Touch ID"
            }
        }

        var symbolName: String {
            switch self {
            case .faceID: "faceid"
            case .touchID: "touchid"
            }
        }
    }

    /// 设备可用的生物识别类型;不可用(未录入/无硬件/被系统锁定)返回 nil。
    /// 能力在进程生命周期内不变(录入状态变化需重启才可见),缓存一次,
    /// 避免 PINEntryView/SettingsView 每次渲染都新建 LAContext 并做系统策略查询。
    static func availableKind() -> Kind? {
        cachedKind
    }

    private static let cachedKind: Kind? = {
        let context = LAContext()
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil) else {
            return nil
        }
        switch context.biometryType {
        case .faceID: return .faceID
        case .touchID: return .touchID
        default: return nil
        }
    }()

    static func authenticate() async -> Bool {
        let context = LAContext()
        context.localizedFallbackTitle = "" // 隐藏「输入密码」回落按钮
        do {
            return try await context.evaluatePolicy(
                .deviceOwnerAuthenticationWithBiometrics,
                localizedReason: String(localized: "biometric.reason")
            )
        } catch {
            return false
        }
    }
}
