import Foundation
import CryptoKit
import os

enum PINVerifyResult: Equatable {
    case success
    case wrongPIN
    case storageFailure
    case lockedOut(until: Date)
}

enum PINUpdateResult: Equatable {
    case success, invalidFormat, mismatch, verification(PINVerifyResult), storageFailure
}

struct PINManager {
    private static let logger = Logger(subsystem: "zeronet.lockstead", category: "PINManager")
    private static let lockoutThreshold = 5
    private static let baseLockout: TimeInterval = 60
    private static let maxLockout: TimeInterval = 3600

    private let now: () -> Date
    private let store: PINCredentialStoring
    private let hasher: PINHasher

    init(now: @escaping () -> Date = { Date() },
         store: PINCredentialStoring = KeychainPINCredentialStore(),
         hasher: PINHasher = .standard) {
        self.now = now
        self.store = store
        self.hasher = hasher
    }

    static func isValidFormat(_ pin: String) -> Bool {
        pin.count == 6 && pin.allSatisfy(\.isNumber)
    }

    /// 是否已设置 PIN:Keychain 凭据或旧版落盘凭据均视为已设置(旧档在下次验证通过时迁移)
    func hasPIN(in state: LockerState) -> Bool {
        store.loadCredential() != nil || (state.pinSalt != nil && state.pinHash != nil)
    }

    /// 当前锁定期截止时间(冷启动恢复锁定期显示);无锁定期返回 nil
    func lockoutUntil(in state: LockerState? = nil) -> Date? {
        [store.loadLockout().lockoutUntil, state?.pinLockoutUntil]
            .compactMap { $0 }.filter { $0 > now() }.max()
    }

    /// 设置 PIN:凭据(PBKDF2)与冷却计数写入 Keychain,状态档只留提示文案。
    /// - Returns: 凭据派生失败或 Keychain 写入失败时返回 false,调用方不得当作已设置——
    ///   此时旧档凭据原样保留,避免「没写进去却清掉旧凭据」导致锁屏被绕过。
    @discardableResult
    func set(pin: String, hint: String?, in state: inout LockerState) -> Bool {
        guard Self.isValidFormat(pin), let credential = PINCredential.make(pin: pin, hasher: hasher) else {
            Self.logger.error("PIN 凭据派生失败,放弃写入")
            return false
        }
        // Reset cooldown first: once the credential write succeeds there are no fallible writes left.
        guard store.saveLockout(.none), store.saveCredential(credential) else {
            Self.logger.error("PIN 凭据写入 Keychain 失败,保留旧凭据,不得当作已设置")
            return false
        }
        state.pinHint = hint
        // 旧版落盘凭据已被 Keychain 取代,清掉残留
        state.pinSalt = nil
        state.pinHash = nil
        state.failedPINAttempts = 0
        state.pinLockoutUntil = nil
        return true
    }

    func change(oldPIN: String, newPIN: String, confirmation: String, hint: String?,
                state: inout LockerState) -> PINUpdateResult {
        guard Self.isValidFormat(newPIN) else { return .invalidFormat }
        guard newPIN == confirmation else { return .mismatch }
        let result = verify(pin: oldPIN, state: &state)
        guard result == .success else { return .verification(result) }
        return set(pin: newPIN, hint: hint, in: &state) ? .success : .storageFailure
    }

    func updateHint(oldPIN: String, hint: String?, state: inout LockerState) -> PINUpdateResult {
        let result = verify(pin: oldPIN, state: &state)
        guard result == .success else { return .verification(result) }
        state.pinHint = hint
        return .success
    }

    func verify(pin: String, state: inout LockerState) -> PINVerifyResult {
        let current = now()
        var lockout = store.loadLockout()
        // 一次性迁移:Keychain 尚无记录时,沿用旧存档的失败计数/冷却,防升级后冷却清零
        if state.failedPINAttempts > lockout.failedAttempts {
            lockout.failedAttempts = state.failedPINAttempts
            lockout.lockoutUntil = state.pinLockoutUntil
        }
        if let until = lockout.lockoutUntil, until > current {
            store.saveLockout(lockout)
            return .lockedOut(until: until)
        }

        if let credential = store.loadCredential() {
            guard PINCredential.verify(pin: pin, against: credential, hasher: hasher) else {
                return registerFailure(lockout: lockout, current: current, state: &state)
            }
            guard store.saveLockout(.none) else { return .storageFailure }
            state.failedPINAttempts = 0
            state.pinLockoutUntil = nil
            return .success
        }

        if let legacySalt = state.pinSalt, let legacyHash = state.pinHash {
            // 旧版单次 SHA256 凭据:验证通过即换成 PBKDF2 + Keychain,失败则继续沿用旧档
            let legacyCandidate = Self.legacyHash(pin: pin, salt: legacySalt)
            guard PINCredential.constantTimeEquals(legacyCandidate, legacyHash) else {
                return registerFailure(lockout: lockout, current: current, state: &state)
            }
            guard store.saveLockout(.none) else { return .storageFailure }
            state.failedPINAttempts = 0
            state.pinLockoutUntil = nil
            if let migrated = PINCredential.make(pin: pin, hasher: hasher) {
                // 只有确认写入 Keychain 后才清旧档;写失败则保留旧凭据,下次验证时重试迁移
                guard store.saveCredential(migrated) else {
                    Self.logger.error("PIN 凭据迁移写入 Keychain 失败,保持旧凭据待下次重试")
                    return .success
                }
                state.pinSalt = nil
                state.pinHash = nil
            } else {
                Self.logger.error("PIN 凭据迁移失败,保持旧凭据待下次重试")
            }
            return .success
        }

        // 未设置 PIN:不计失败,避免凭空的锁定
        return .wrongPIN
    }

    private func registerFailure(lockout: PINLockout, current: Date, state: inout LockerState) -> PINVerifyResult {
        var lockout = lockout
        lockout.failedAttempts += 1
        if lockout.failedAttempts >= Self.lockoutThreshold {
            let exponent = lockout.failedAttempts - Self.lockoutThreshold
            let duration = min(Self.baseLockout * pow(2, Double(exponent)), Self.maxLockout)
            let until = current.addingTimeInterval(duration)
            lockout.lockoutUntil = until
            state.failedPINAttempts = lockout.failedAttempts
            state.pinLockoutUntil = until
            store.saveLockout(lockout)
            return .lockedOut(until: until)
        }
        state.failedPINAttempts = lockout.failedAttempts
        state.pinLockoutUntil = lockout.lockoutUntil
        guard store.saveLockout(lockout) else { return .storageFailure }
        return .wrongPIN
    }

    /// 旧版凭据的哈希方式:单次 SHA256(盐 + PIN),仅用于存量迁移
    private static func legacyHash(pin: String, salt: Data) -> Data {
        Data(SHA256.hash(data: salt + Data(pin.utf8)))
    }
}
