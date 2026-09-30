import Foundation
import StoreKit
import StoreKitTest
import Testing
@testable import gastos

struct SubscriptionAccessTests {
    @Test func accessRule() {
        let id = Subscription.productID
        let later = Date.now.addingTimeInterval(86_400)
        #expect(Subscription.grantsAccess(id, revoked: false, expires: later))
        #expect(!Subscription.grantsAccess(id, revoked: false, expires: .now.addingTimeInterval(-60)))  // lapsed
        #expect(!Subscription.grantsAccess(id, revoked: true, expires: later))                          // refunded
        #expect(!Subscription.grantsAccess("com.example.other", revoked: false, expires: later))
    }
}

/// The local StoreKit file sells what App Store Connect must sell: ₱99 for 1 month.
/// (Buying in a test session isn't checked here: the simulator's test service returns transaction id 0
/// and records nothing. Purchases are verified with a sandbox account on a device instead.)
@MainActor
struct SubscriptionProductTests {
    @Test func productIs99PesosMonthly() async throws {
        // Also sets up the simulator's test store for the app and empties it, which PaywallUITests
        // (run after the unit tests) relies on to start unsubscribed.
        let session = try SKTestSession(configurationFileNamed: "Products")
        session.resetToDefaultState()
        session.clearTransactions()
        let product = try #require(try await Product.products(for: [Subscription.productID]).first)
        #expect(product.displayPrice.contains("99"))
        #expect(product.subscription?.subscriptionPeriod.unit == .month)
        #expect(product.subscription?.subscriptionPeriod.value == 1)
    }
}
