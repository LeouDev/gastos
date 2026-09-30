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
                redeemButton
                VStack(alignment: .leading, spacing: 10) {
                    perk("bolt.fill", "Add an expense in seconds")
                    perk("chart.pie.fill", "See where it went, and which wallet paid")
                    perk("creditcard.fill", "Wallet cards, cards & passes")
                    perk("arrow.triangle.2.circlepath", "Sync across your devices")
                    perk("lock.fill", "Private: no ads, no tracking")
                }
                .padding(.top, 6)
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

    /// Codes only give a free month before the first payment, so this sits above Subscribe.
    private var redeemButton: some View {
        Button { redeeming = true } label: {
            HStack(spacing: 12) {
                Image(systemName: "gift.fill")
                    .font(.title3)
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(Color.brand, in: .circle)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Got the GASTOS code?").font(.headline).foregroundStyle(Color.ink)
                    Text("Enter it first for 1 month free").font(.subheadline).foregroundStyle(Color.muted)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.subheadline.weight(.semibold)).foregroundStyle(Color.muted)
            }
            .padding(12)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 22))
        .accessibilityLabel("Redeem a code. Enter the GASTOS code first for 1 month free.")
        .padding(.top, 4)
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
