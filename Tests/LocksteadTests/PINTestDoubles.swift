import Foundation
import CryptoKit
@testable import Lockstead

/// 内存版 PIN 凭据存储:单测不触碰真实 Keychain,避免测试间的持久残留
final class InMemoryPINCredentialStore: PINCredentialStoring {
    private(set) var credential: PINCredential?
    private(set) var lockout = PINLockout.none

    func loadCredential() -> PINCredential? { credential }
    @discardableResult
    func saveCredential(_ credential: PINCredential) -> Bool { self.credential = credential; return true }
    func loadLockout() -> PINLockout { lockout }
    @discardableResult
    func saveLockout(_ lockout: PINLockout) -> Bool { self.lockout = lockout; return true }
}

/// 可注入 Keychain 写失败的内存存储:验证「写不进去就不得清旧凭据/当作已设置」
final class FailingPINCredentialStore: PINCredentialStoring {
    private(set) var credential: PINCredential?
    private(set) var lockout = PINLockout.none
    var failsCredentialSave = false
    var failsLockoutSave = false

    func loadCredential() -> PINCredential? { credential }
    @discardableResult
    func saveCredential(_ credential: PINCredential) -> Bool {
        guard !failsCredentialSave else { return false }
        self.credential = credential
        return true
    }
    func loadLockout() -> PINLockout { lockout }
    @discardableResult
    func saveLockout(_ lockout: PINLockout) -> Bool {
        guard !failsLockoutSave else { return false }
        self.lockout = lockout
        return true
    }
}

extension PINHasher {
    /// 快速确定性哈希:单测专用,避免真实 PBKDF2 的迭代耗时(真实派生另测)
    static let testFast = PINHasher(
        iterations: { 1 },
        derive: { pin, salt, _ in Data(SHA256.hash(data: salt + Data(pin.utf8))) }
    )
}
