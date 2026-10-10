import Foundation
import CommonCrypto
import Security
import os

/// PIN 校验凭据:PBKDF2 派生值 + 盐 + 迭代次数(迭代次数随设备校准,必须随凭据保存)
struct PINCredential: Codable, Equatable {
    let salt: Data
    let hash: Data
    let iterations: Int

    static func make(pin: String, hasher: PINHasher) -> PINCredential? {
        let salt = randomSalt()
        let iterations = max(hasher.iterations(), 1)
        guard let hash = hasher.derive(pin, salt, iterations) else { return nil }
        return PINCredential(salt: salt, hash: hash, iterations: iterations)
    }

    static func verify(pin: String, against credential: PINCredential, hasher: PINHasher) -> Bool {
        guard let candidate = hasher.derive(pin, credential.salt, credential.iterations) else { return false }
        return constantTimeEquals(candidate, credential.hash)
    }

    /// 常量时间比较:不随匹配前缀长度提前返回,不给时序侧信道留入口
    static func constantTimeEquals(_ a: Data, _ b: Data) -> Bool {
        guard a.count == b.count else { return false }
        var difference: UInt8 = 0
        for (x, y) in zip(a, b) { difference |= x ^ y }
        return difference == 0
    }

    private static func randomSalt() -> Data {
        var salt = Data(count: 16)
        let status = salt.withUnsafeMutableBytes {
            SecRandomCopyBytes(kSecRandomDefault, 16, $0.baseAddress!)
        }
        if status != errSecSuccess {
            var rng = SystemRandomNumberGenerator()
            salt = Data((0..<16).map { _ in UInt8.random(in: .min ... .max, using: &rng) })
        }
        return salt
    }
}

/// 失败计数与冷却时间:与凭据一起进 Keychain,备份编辑无法清零
struct PINLockout: Codable, Equatable {
    var failedAttempts = 0
    var lockoutUntil: Date?

    static let none = PINLockout()
}

/// 凭据/冷却的存储抽象:生产走 Keychain(ThisDeviceOnly,不进备份),
/// 单测注入内存实现,避免触碰真实 Keychain。
/// 写入方法返回是否确实落盘:Keychain 写入可能失败(entitlement/恢复/设备策略),
/// 调用方必须依据返回值决定是否当作已设置——静默失败会清掉用户凭据、绕过锁屏。
protocol PINCredentialStoring {
    func loadCredential() -> PINCredential?
    @discardableResult
    func saveCredential(_ credential: PINCredential) -> Bool
    func loadLockout() -> PINLockout
    @discardableResult
    func saveLockout(_ lockout: PINLockout) -> Bool
}

/// 主 App 专用:扩展目标不编译本文件(见 project.yml),也未配置 keychain-access-groups——
/// 凭据/冷却只在主 App 进程内读写。若未来扩展需要校验 PIN,需先加 access group 与 entitlement。
struct KeychainPINCredentialStore: PINCredentialStoring {
    private static let logger = Logger(subsystem: "zeronet.lockstead", category: "PINKeychain")
    private static let service = "zeronet.lockstead.pin"
    private static let credentialAccount = "credential.v1"
    private static let lockoutAccount = "lockout.v1"

    func loadCredential() -> PINCredential? {
        load(account: Self.credentialAccount)
    }

    @discardableResult
    func saveCredential(_ credential: PINCredential) -> Bool {
        save(credential, account: Self.credentialAccount)
    }

    func loadLockout() -> PINLockout {
        load(account: Self.lockoutAccount) ?? .none
    }

    @discardableResult
    func saveLockout(_ lockout: PINLockout) -> Bool {
        save(lockout, account: Self.lockoutAccount)
    }

    private func load<T: Decodable>(account: String) -> T? {
        var query = Self.baseQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        guard let value = try? JSONDecoder().decode(T.self, from: data) else {
            Self.logger.error("Keychain 数据解码失败: \(account, privacy: .public)")
            return nil
        }
        return value
    }

    private func save<T: Encodable>(_ value: T, account: String) -> Bool {
        guard let data = try? JSONEncoder().encode(value) else {
            Self.logger.error("Keychain 数据编码失败: \(account, privacy: .public)")
            return false
        }
        var query = Self.baseQuery(account: account)
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            // ThisDeviceOnly:不随备份迁移、不跨设备恢复——离线篡改备份的路径就此封死
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecItemNotFound {
            query.merge(attributes) { _, new in new }
            let addStatus = SecItemAdd(query as CFDictionary, nil)
            if addStatus != errSecSuccess {
                Self.logger.error("Keychain 写入失败: \(addStatus, privacy: .public)")
                return false
            }
        } else if updateStatus != errSecSuccess {
            Self.logger.error("Keychain 更新失败: \(updateStatus, privacy: .public)")
            return false
        }
        return true
    }

    private static func baseQuery(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: account,
        ]
    }
}

/// 可注入的派生配置:生产用 PBKDF2,单测注入快速确定性实现
struct PINHasher {
    var iterations: () -> Int
    var derive: (String, Data, Int) -> Data?

    static let standard = PINHasher(
        iterations: { PINKeyDerivation.calibratedIterations },
        derive: { PINKeyDerivation.derive(pin: $0, salt: $1, iterations: $2) }
    )
}

enum PINKeyDerivation {
    static let saltLength = 16
    static let derivedKeyLength = 32
    /// 校准结果下限:任何设备上都不低于这个量级,保证离线穷举成本
    static let minimumIterations = 100_000

    /// 按设备校准到目标耗时(Apple 建议 ~100ms):新机迭代次数高、老机低,解锁体验一致。
    /// 校准本身约 100ms,进程内缓存一次——set/迁移在主线程上不应每次重复校准。
    static let calibratedIterations: Int = {
        let calibrated = CCCalibratePBKDF(
            CCPBKDFAlgorithm(kCCPBKDF2),
            6, // PIN 固定 6 位
            saltLength,
            CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
            derivedKeyLength,
            100
        )
        return max(Int(calibrated), minimumIterations)
    }()

    static func derive(pin: String, salt: Data, iterations: Int) -> Data? {
        var output = Data(count: derivedKeyLength)
        let saltLength = salt.count
        let outputLength = output.count
        let status = salt.withUnsafeBytes { saltBytes in
            output.withUnsafeMutableBytes { outputBytes in
                CCKeyDerivationPBKDF(
                    CCPBKDFAlgorithm(kCCPBKDF2),
                    pin, pin.lengthOfBytes(using: .utf8),
                    saltBytes.bindMemory(to: UInt8.self).baseAddress, saltLength,
                    CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                    UInt32(iterations),
                    outputBytes.bindMemory(to: UInt8.self).baseAddress, outputLength
                )
            }
        }
        return status == kCCSuccess ? output : nil
    }
}
