import Foundation
import Observation
import StoreKit

enum VIPProducts {
    static let monthly = "lockstead.vip.monthly"
    static let yearly = "lockstead.vip.yearly"
    static let lifetime = "lockstead.vip.lifetime"
    static let all: Set<String> = [monthly, yearly, lifetime]

    static func isVIP(activeProductIDs: Set<String>) -> Bool {
        !activeProductIDs.isDisjoint(with: all)
    }
}

enum RestoreOutcome: Equatable {
    case restoredVIP      // 找回了 VIP
    case nothingToRestore // 同步成功但没有可恢复的购买
    case failed(String)   // 同步失败(网络/账号)
}

@Observable @MainActor
final class EntitlementStore {
    typealias ActiveProductIDsProvider = @MainActor () async -> Set<String>
    typealias ProductsProvider = @MainActor () async throws -> [Product]

    private(set) var isVIP = false
    private(set) var products: [Product] = []
    private(set) var lastError: String?
    private(set) var restoreOutcome: RestoreOutcome?
    private(set) var isRestoring = false
    private(set) var isLoadingProducts = false
    private(set) var hasPurchasedVIP = false

    private let appGroupStore: AppGroupStore
    private let reviewAccessStore: ReviewAccessStore
    private let now: @MainActor () -> Date
    private let activeProductIDsProvider: ActiveProductIDsProvider
    private let productsProvider: ProductsProvider
    private var updatesTask: Task<Void, Never>?

    init(
        appGroupStore: AppGroupStore = AppGroupStore(),
        reviewAccessStore: ReviewAccessStore = ReviewAccessStore(),
        now: @escaping @MainActor () -> Date = Date.init,
        activeProductIDsProvider: @escaping ActiveProductIDsProvider = {
            await EntitlementStore.loadActiveProductIDs()
        },
        productsProvider: @escaping ProductsProvider = {
            try await Product.products(for: VIPProducts.all)
        }
    ) {
        self.appGroupStore = appGroupStore
        self.reviewAccessStore = reviewAccessStore
        self.now = now
        self.activeProductIDsProvider = activeProductIDsProvider
        self.productsProvider = productsProvider

        let mirroredVIP = appGroupStore.load().isVIP
        let hadReviewActivation = reviewAccessStore.wasActivated
        let reviewIsActive = reviewAccessStore.isActive(at: now())
        // 审核入口到期后不能继续信任由它写入的 VIP 镜像；普通购买用户仍先用镜像秒开，
        // 随后的 refresh 再用 Apple 当前权益校准。
        isVIP = hadReviewActivation ? reviewIsActive : mirroredVIP
        hasPurchasedVIP = mirroredVIP && !hadReviewActivation
        if hadReviewActivation && !reviewIsActive {
            setVIP(false)
        }
    }

    var isReviewAccessActive: Bool {
        reviewAccessStore.isActive(at: now())
    }

    func start() {
        // Transaction.updates 是永不结束的流:闭包必须弱引用 self,
        // 否则 self → updatesTask → self 形成永久强引用环,可重建的 store 全部泄漏
        updatesTask = Task { [weak self] in
            for await result in Transaction.updates {
                guard let self else { return }
                switch result {
                case .verified(let transaction):
                    if Self.isActiveVIP(transaction) {
                        await self.completeVerifiedPurchase(productID: transaction.productID) {
                            await transaction.finish()
                        }
                    } else {
                        await transaction.finish()
                        await self.refresh()
                    }
                case .unverified:
                    // 无法信任这笔更新;回到 Apple 当前权益快照校准,不凭未验证数据放权。
                    await self.refresh()
                }
            }
        }
        Task { await refresh() }
    }

    func refresh() async {
        let active = await activeProductIDsProvider()
        hasPurchasedVIP = VIPProducts.isVIP(activeProductIDs: active)
        if hasPurchasedVIP {
            reviewAccessStore.clear()
        }
        setVIP(hasPurchasedVIP || reviewAccessStore.isActive(at: now()))
    }

    /// 审核备注披露的限时入口。它只授予本地功能权限，不伪造 StoreKit 交易。
    @discardableResult
    func activateReviewAccess(code: String) -> Bool {
        guard reviewAccessStore.activate(code: code, at: now()) else { return false }
        setVIP(true)
        return true
    }

    /// 回前台时只校准限时入口；StoreKit 权益仍由 refresh / Transaction.updates 管理。
    func syncReviewAccess() {
        let hadReviewActivation = reviewAccessStore.wasActivated
        let reviewIsActive = reviewAccessStore.isActive(at: now())
        if reviewIsActive {
            setVIP(true)
        } else if hadReviewActivation {
            setVIP(hasPurchasedVIP)
        }
    }

    func loadProducts() async {
        guard !isLoadingProducts else { return }
        isLoadingProducts = true
        defer { isLoadingProducts = false }
        do {
            let loadedProducts = try await productsProvider()
                .sorted { $0.price < $1.price }
            products = loadedProducts
            lastError = loadedProducts.isEmpty ? String(localized: "paywall.load.empty") : nil
        } catch {
            lastError = error.localizedDescription // 展示具体错误,不静默
        }
    }

    func purchase(_ product: Product) async {
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                if case .verified(let t) = verification {
                    await completeVerifiedPurchase(productID: t.productID) {
                        await t.finish()
                    }
                    lastError = nil
                } else {
                    lastError = String(localized: "purchase.error.unverified")
                }
            case .pending:
                lastError = String(localized: "purchase.pending")
            case .userCancelled:
                break // 用户主动取消,不算错误
            @unknown default:
                break
            }
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// 已验证购买就是本次交付的权威结果:先授予并持久化权益,再结束交易。
    /// 不在这里立即二次枚举 currentEntitlements——本地 StoreKit 会话刚完成购买时,
    /// 该快照可能尚未同步;若用空快照覆盖,就会出现「已购买但仍是免费版」。
    func completeVerifiedPurchase(productID: String, finish: () async -> Void) async {
        if VIPProducts.isVIP(activeProductIDs: [productID]) {
            hasPurchasedVIP = true
            reviewAccessStore.clear()
            setVIP(true)
        }
        await finish()
    }

    /// 恢复购买必须给结果反馈——「恢复失败无提示」是同类产品差评的最大来源之一。
    func restore() async {
        isRestoring = true
        defer { isRestoring = false }
        restoreOutcome = nil
        do {
            try await AppStore.sync()
            await refresh()
            lastError = nil
            restoreOutcome = hasPurchasedVIP ? .restoredVIP : .nothingToRestore
        } catch {
            restoreOutcome = .failed(error.localizedDescription)
        }
    }

    private func setVIP(_ value: Bool) {
        isVIP = value
        var state = appGroupStore.load()
        if state.isVIP != value {
            state.isVIP = value
            appGroupStore.save(state)
        }
    }

    private static func isActiveVIP(_ transaction: Transaction, now: Date = Date()) -> Bool {
        guard VIPProducts.isVIP(activeProductIDs: [transaction.productID]),
              transaction.revocationDate == nil
        else { return false }
        return (transaction.expirationDate ?? .distantFuture) > now
    }

    private static func loadActiveProductIDs() async -> Set<String> {
        var active: Set<String> = []
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result,
                  isActiveVIP(transaction)
            else { continue }
            active.insert(transaction.productID)
        }

        guard !VIPProducts.isVIP(activeProductIDs: active) else { return active }

        // Xcode 本地 StoreKit 在真机冷启动时偶尔给出空 currentEntitlements，
        // 但购买历史仍存在。按产品查询最新交易，避免把已验证 VIP 错写回 false。
        for productID in VIPProducts.all {
            guard let result = await Transaction.latest(for: productID),
                  case .verified(let transaction) = result,
                  isActiveVIP(transaction)
            else { continue }
            active.insert(transaction.productID)
        }
        return active
    }
}
