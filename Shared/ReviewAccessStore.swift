import Foundation
import Security
import os

/// Public-source review-access logic with a synthetic, openly documented fixture.
/// This contains no production review credential. The original default expiry is retained.
/// Fixture: LOCKSTEAD-PUBLIC-TEST-ONLY; never use it as a private access credential.
struct ReviewAccessStore {
    static let defaultExpiryDate = Date(timeIntervalSince1970: 1_790_812_800) // 2026-10-01 00:00 UTC

    // Synthetic public fixture only. Salt/hash differ from the private product source.
    private static let codeSalt = Data([0x50, 0x75, 0x62, 0x6C, 0x69, 0x63, 0x46, 0x69, 0x78, 0x74, 0x75, 0x72, 0x65, 0x56, 0x31, 0x21])
    private static let codeIterations = 100_000
    private static let codeHash = Data([0xA6, 0x06, 0x82, 0xD6, 0x02, 0x78, 0xEC, 0x9C, 0x52, 0x12, 0x82, 0x58, 0xEA, 0xE8, 0x20, 0x14, 0x6D, 0x3D, 0x89, 0xF2, 0xDC, 0x58, 0xA7, 0x5A, 0x39, 0x49, 0x12, 0x79, 0x60, 0x22, 0x36, 0x3D])

    private static let logger = Logger(subsystem: "zeronet.lockstead", category: "ReviewAccess")

    private let flagStore: ReviewAccessFlagStoring
    let expiryDate: Date

    init(flagStore: ReviewAccessFlagStoring = KeychainReviewAccessFlagStore(),
         expiryDate: Date = Self.defaultExpiryDate) {
        self.flagStore = flagStore
        self.expiryDate = expiryDate
    }

    var wasActivated: Bool {
        flagStore.load()
    }

    @discardableResult
    func activate(code: String, at date: Date = Date()) -> Bool {
        guard date < expiryDate else { return false }
        let normalized = code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let candidate = Self.hash(normalized)
        guard PINCredential.constantTimeEquals(candidate, Self.codeHash) else { return false }
        flagStore.save(true)
        return true
    }

    func isActive(at date: Date = Date()) -> Bool {
        guard wasActivated else { return false }
        guard date < expiryDate else {
            clear()
            return false
        }
        return true
    }

    func clear() {
        flagStore.save(false)
    }

    private static func hash(_ code: String) -> Data {
        PINKeyDerivation.derive(pin: code, salt: codeSalt, iterations: codeIterations) ?? Data()
    }
}

/// 激活标志的存储抽象:生产走 Keychain,单测注入内存实现
protocol ReviewAccessFlagStoring {
    func load() -> Bool
    func save(_ activated: Bool)
}

struct KeychainReviewAccessFlagStore: ReviewAccessFlagStoring {
    private static let service = "zeronet.lockstead.review"
    private static let account = "activated.v1"
    private static let logger = Logger(subsystem: "zeronet.lockstead", category: "ReviewAccess")

    func load() -> Bool {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: Self.account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return false }
        return data == Data([1])
    }

    func save(_ activated: Bool) {
        let data = Data([activated ? 1 : 0])
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: Self.account,
        ]
        if !activated {
            let status = SecItemDelete(query as CFDictionary)
            if status != errSecSuccess && status != errSecItemNotFound {
                Self.logger.error("Keychain 删除失败: \(status, privacy: .public)")
            }
            return
        }
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecItemNotFound {
            query.merge(attributes) { _, new in new }
            let addStatus = SecItemAdd(query as CFDictionary, nil)
            if addStatus != errSecSuccess {
                Self.logger.error("Keychain 写入失败: \(addStatus, privacy: .public)")
            }
        } else if updateStatus != errSecSuccess {
            Self.logger.error("Keychain 更新失败: \(updateStatus, privacy: .public)")
        }
    }
}
