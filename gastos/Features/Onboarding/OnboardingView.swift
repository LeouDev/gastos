import SwiftUI
import SwiftData

struct OnboardingView: View {
    struct Suggestion: Identifiable {
        let name: String
        let icon: String
        let type: AccountType
        let colorHex: String
        var id: String { name }
    }

    static let suggestions = [
        Suggestion(name: "Cash", icon: "💵", type: .cash, colorHex: "34A853"),
        Suggestion(name: "GCash", icon: "📱", type: .eWallet, colorHex: "0096D6"),
        Suggestion(name: "Maya", icon: "💚", type: .eWallet, colorHex: "10B981"),
        Suggestion(name: "BPI Savings", icon: "🏦", type: .bank, colorHex: "D8141A"),
        Suggestion(name: "BDO Savings", icon: "🏦", type: .bank, colorHex: "2F6FEB"),
        Suggestion(name: "Credit Card", icon: "💳", type: .creditCard, colorHex: "8E44AD"),
    ]

    @Environment(\.modelContext) private var context
    @AppStorage(SettingsKey.hasOnboarded) private var hasOnboarded = false
    @AppStorage(SettingsKey.currency) private var currency = "PHP"
    @State private var page = 0
    @State private var picked: [String: String] = [:]  // name → balance text

    var body: some View {
        VStack {
            TabView(selection: $page) {
                welcome.tag(0)
                wallets.tag(1)
                ready.tag(2)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))

            Button(page == 2 ? "Start" : "Continue") {
                if page == 2 { finish() } else { withAnimation { page += 1 } }
            }
            .buttonStyle(PrimaryButtonStyle())
            .padding(.horizontal, 24)
            .padding(.bottom, 8)

            Button(page == 1 ? "Skip for now" : " ") { withAnimation { page = 2 } }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.muted)
                .disabled(page != 1)
                .padding(.bottom, 12)
        }
        .background(Color.canvas.ignoresSafeArea())
        .scrollDismissesKeyboard(.interactively)
    }

    private var welcome: some View {
        VStack(spacing: 24) {
            Spacer()
            LogoSphere(size: 220)
                .padding(.bottom, 12)
            Text("gastos")
                .font(.system(size: 48, weight: .heavy, design: .rounded))
                .foregroundStyle(Color.brand)
            Text("Know where your money goes.")
                .font(.title3.weight(.medium))
                .foregroundStyle(Color.ink)
            Spacer()
        }
        .padding(24)
    }

    private var wallets: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Add your wallets")
                    .font(.largeTitle.weight(.bold))
                    .foregroundStyle(Color.ink)
                    .padding(.top, 40)
                Text("Where does your money live? Pick any — you can add others later.")
                    .foregroundStyle(Color.muted)
                ForEach(Self.suggestions) { item in
                    let selected = picked[item.name] != nil
                    VStack(alignment: .leading, spacing: 12) {
                        Button {
                            withAnimation(.snappy) { picked[item.name] = selected ? nil : "" }
                        } label: {
                            HStack(spacing: 14) {
                                EmojiBadge(emoji: item.icon, colorHex: item.colorHex)
                                Text(item.name).font(.headline).foregroundStyle(Color.ink)
                                Spacer()
                                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                                    .font(.title2)
                                    .foregroundStyle(selected ? Color.brand : Color.track)
                            }
                            .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                        .sensoryFeedback(.selection, trigger: selected)
                        if selected {
                            HStack {
                                Text(item.type == .creditCard ? "Amount owed" : "Balance now").foregroundStyle(Color.muted)
                                Spacer()
                                Text(currencySymbol(currency)).foregroundStyle(Color.muted)
                                TextField("0", text: Binding(get: { picked[item.name] ?? "" }, set: { picked[item.name] = $0 }))
                                    .keyboardType(.decimalPad)
                                    .fixedSize()
                                    .font(.body.monospacedDigit())
                            }
                        }
                    }
                    .card(padding: 16)
                }
            }
            .padding(24)
        }
    }

    private var ready: some View {
        VStack(spacing: 20) {
            Spacer()
            Text("🎉").font(.system(size: 72))
            Text("You're ready.")
                .font(.largeTitle.weight(.bold))
                .foregroundStyle(Color.ink)
            Text("Let's track your first peso.")
                .font(.title3)
                .foregroundStyle(Color.muted)
            Spacer()
        }
        .padding(24)
    }

    private func finish() {
        for (index, item) in Self.suggestions.enumerated() {
            guard let text = picked[item.name] else { continue }
            let amount = parseAmount(text) ?? 0
            let account = Account(name: item.name, type: item.type, openingBalance: item.type == .creditCard ? -amount : amount, currency: currency, icon: item.icon, colorHex: item.colorHex)
            account.sortOrder = index
            context.insert(account)
        }
        Haptics.success()
        withAnimation { hasOnboarded = true }
    }
}
