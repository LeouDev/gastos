import Foundation
import StoreKit
import os

/// gastos Premium: one auto-renewing monthly subscription sold through the App Store.
/// Access comes from StoreKit's own signed transactions, which work offline, so there is no server check.
@MainActor @Observable
final class Subscription {
    static let shared = Subscription()

    /// Must match the product created in App Store Connect.
    static let productID = "com.leoudev.gastos.premium.monthly"

    enum State: Equatable { case checking, active, inactive }
    private(set) var state = State.checking

    private let log = Logger(subsystem: "com.leoudev.gastos", category: "subscription")
    private var listening = false

    /// Reads current entitlements, then keeps watching for renewals, refunds, codes redeemed elsewhere
    /// and purchases finished while the app was closed.
    func start() {
        guard !listening else { return }
        listening = true
        Task { await refresh() }
        Task {
            for await update in Transaction.updates {
                if case .verified(let transaction) = update { await transaction.finish() }
                await refresh()
            }
        }
    }

    func refresh() async {
        var active = false
        // The latest renewal of our one product; only trust transactions Apple signed for this device.
        if case .verified(let transaction)? = await Transaction.latest(for: Self.productID) {
            active = Self.grantsAccess(transaction.productID, revoked: transaction.revocationDate != nil, expires: transaction.expirationDate)
        }
        state = active ? .active : .inactive
        log.info("subscription \(active ? "active" : "inactive")")
    }

    /// The access rule on its own, so it can be tested without the App Store.
    nonisolated static func grantsAccess(_ productID: String, revoked: Bool, expires: Date?, now: Date = .now) -> Bool {
        guard productID == Self.productID, !revoked else { return false }
        return expires.map { $0 > now } ?? true
    }
}
