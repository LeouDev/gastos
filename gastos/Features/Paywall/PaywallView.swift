import SwiftUI
import StoreKit

/// Shown after onboarding until the subscription is active. Apple's subscription store handles
/// the price, purchase, restore and offer codes (e.g. GASTOS for a free month).
struct PaywallView: View {
    @State private var redeeming = false

    var body: some View {
        SubscriptionStoreView(productIDs: [Subscription.productID]) {
            VStack(spacing: 18) {
                LogoSphere(size: 120)
                Text("gastos")
                    .font(.system(size: 40, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color.brand)
                Text("Know where your money goes.")
                    .font(.title3.weight(.medium))
                    .foregroundStyle(Color.ink)
                VStack(alignment: .leading, spacing: 10) {
                    perk("bolt.fill", "Add an expense in seconds")
                    perk("chart.pie.fill", "See where it went, and which wallet paid")
                    perk("creditcard.fill", "Wallet cards, cards & passes")
                    perk("arrow.triangle.2.circlepath", "Sync across your devices")
                    perk("lock.fill", "Private: no ads, no tracking")
                }
                .padding(.top, 6)
                Button("Have a code? Redeem it") { redeeming = true }
                    .buttonStyle(.plain)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.brand)
                    .padding(.top, 4)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
        }
        .storeButton(.visible, for: .restorePurchases)
        .subscriptionStoreButtonLabel(.multiline)
        .subscriptionStorePolicyDestination(url: URL(string: "https://gastos-eta-one.vercel.app/privacy/")!, for: .privacyPolicy)
        .subscriptionStorePolicyDestination(url: URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!, for: .termsOfService)
        .containerBackground(Color.canvas, for: .subscriptionStore)
        .tint(.brand)
        .offerCodeRedemption(isPresented: $redeeming) { _ in
            Task { await Subscription.shared.refresh() }
        }
        .onInAppPurchaseCompletion { _, _ in
            await Subscription.shared.refresh()
        }
    }

    private func perk(_ icon: String, _ text: String) -> some View {
        Label {
            Text(text).foregroundStyle(Color.ink)
        } icon: {
            Image(systemName: icon).foregroundStyle(Color.brand)
        }
        .font(.body)
    }
}
