import SwiftUI
import SwiftData

/// Apple Wallet–style stack: each card shows its top edge; tap one to open it.
struct WalletsView: View {
    @Query(sort: [SortDescriptor(\Account.sortOrder), SortDescriptor(\Account.createdAt)]) private var accounts: [Account]
    @AppStorage(SettingsKey.currency) private var currency = "PHP"
    @State private var adding = false
    @State private var showHidden = false
    @Namespace private var cards

    /// How much of each card peeks out above the next.
    private let peek: CGFloat = 62

    var body: some View {
        let active = accounts.filter(\.isActive)
        let hidden = accounts.filter { !$0.isActive }
        NavigationStack {
            ScrollView {
                if accounts.isEmpty {
                    EmptyStateView(
                        title: "Your money starts here.",
                        message: "Add your first wallet to start tracking where your money goes.",
                        buttonTitle: "Add Wallet"
                    ) { adding = true }
                    .padding(.top, 60)
                } else {
                    VStack(alignment: .leading, spacing: 20) {
                        HStack {
                            Text("Total across wallets").foregroundStyle(Color.muted)
                            Spacer()
                            Text(Finance.totalMoney(accounts, currency: currency).money(currency))
                                .fontWeight(.semibold).foregroundStyle(Color.ink).monospacedDigit()
                        }
                        .font(.subheadline)
                        .accessibilityElement(children: .combine)

                        stack(active)

                        if !hidden.isEmpty {
                            Button { withAnimation(.snappy) { showHidden.toggle() } } label: {
                                HStack {
                                    Image(systemName: "eye.slash")
                                    Text("\(hidden.count) hidden \(hidden.count == 1 ? "wallet" : "wallets")")
                                    Spacer()
                                    Text(showHidden ? "Hide" : "Show").foregroundStyle(Color.muted)
                                }
                                .font(.subheadline)
                                .foregroundStyle(Color.ink)
                                .padding(.horizontal, 16)
                                .frame(minHeight: 50)
                                .contentShape(.rect)
                            }
                            .buttonStyle(.plain)
                            .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 20))

                            if showHidden { stack(hidden).opacity(0.7) }
                        }
                    }
                    .padding(20)
                }
            }
            .canvasBackground()
            .navigationTitle("Wallets")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Add Wallet", systemImage: "plus") { adding = true }
                }
            }
            .navigationDestination(for: Account.self) { account in
                WalletDetailView(account: account)
                    .navigationTransition(.zoom(sourceID: account.id, in: cards))
            }
            .sheet(isPresented: $adding) { WalletEditor(account: nil) }
        }
    }

    private func stack(_ wallets: [Account]) -> some View {
        ZStack(alignment: .top) {
            ForEach(Array(wallets.enumerated()), id: \.element.id) { index, account in
                NavigationLink(value: account) {
                    WalletCardView(account: account)
                }
                .buttonStyle(.plain)
                .matchedTransitionSource(id: account.id, in: cards)
                .offset(y: CGFloat(index) * peek)
            }
        }
        .frame(height: 216 + CGFloat(max(wallets.count - 1, 0)) * peek, alignment: .top)
    }
}

/// Credit cards read as "Owed ₱2,000" instead of a negative balance.
struct BalanceLabel: View {
    let account: Account
    var font: Font = .body.weight(.semibold)

    var body: some View {
        let balance = account.balance
        VStack(alignment: .trailing, spacing: 0) {
            if account.type == .creditCard && balance < 0 {
                Text((-balance).money(account.currency)).font(font.monospacedDigit()).foregroundStyle(Color.ink)
                Text("owed").font(.caption).foregroundStyle(Color.muted)
            } else {
                Text(balance.money(account.currency)).font(font.monospacedDigit())
                    .foregroundStyle(balance < 0 ? Color.brand : Color.ink)
            }
        }
        .contentTransition(.numericText(value: balance.double))
    }
}

struct WalletDetailView: View {
    let account: Account
    @Environment(\.addEntry) private var addEntry
    @Environment(\.dismiss) private var dismiss
    @State private var editingWallet = false
    @State private var customizing = false
    @State private var editing: Entry?

    var body: some View {
        let entries = ((account.entries ?? []) + (account.incomingTransfers ?? []))
            .sorted { $0.date > $1.date }
        let month = Period.month.interval()
        let spent = Finance.total(entries.filter { $0.account == account }, .expense, in: month, currency: account.currency)

        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                WalletCardView(account: account)

                GlassEffectContainer {
                    HStack(spacing: 10) {
                        ForEach(actions, id: \.label) { action in
                            Button(action: action.run) {
                                VStack(spacing: 6) {
                                    Image(systemName: action.icon).font(.system(size: 17, weight: .semibold))
                                    Text(action.label).font(.footnote.weight(.medium))
                                }
                                .foregroundStyle(Color.ink)
                                .frame(maxWidth: .infinity, minHeight: 66)
                                .contentShape(.rect)
                            }
                            .buttonStyle(.plain)
                            .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 20))
                        }
                    }
                }

                VStack(spacing: 0) {
                    HStack {
                        Text("Latest")
                        Spacer()
                        Text("Spent this month · \(spent.money(account.currency))")
                    }
                    .font(.footnote)
                    .foregroundStyle(Color.muted)
                    .frame(minHeight: 40)

                    if entries.isEmpty {
                        Text("No activity yet.").font(.subheadline).foregroundStyle(Color.muted)
                            .frame(maxWidth: .infinity, minHeight: 60)
                    }
                    ForEach(entries) { entry in
                        Divider()
                        Button { editing = entry } label: { EntryRow(entry: entry, perspective: account) }
                            .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
                .background(Color.card, in: .rect(cornerRadius: 22, style: .continuous))
            }
            .padding(20)
        }
        .canvasBackground()
        .navigationTitle(account.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Card Style", systemImage: "paintbrush.pointed") { customizing = true }
                    Button("Edit Wallet", systemImage: "pencil") { editingWallet = true }
                } label: {
                    Text("Edit")
                }
            }
        }
        .sheet(isPresented: $editingWallet) { WalletEditor(account: account) { dismiss() } }
        .sheet(isPresented: $customizing) { CardCustomizeView(account: account) }
        .sheet(item: $editing) { AddEntryView(editing: $0) }
    }

    private struct Action { let label: String; let icon: String; let run: () -> Void }

    private var actions: [Action] {
        if account.type == .creditCard {
            return [
                Action(label: "Spend", icon: "minus") { addEntry(.expense, from: account) },
                Action(label: "Pay card", icon: "creditcard") { addEntry(.transfer, to: account) },
                Action(label: "Refund", icon: "arrow.uturn.backward") { addEntry(.income, from: account) },
            ]
        }
        return [
            Action(label: "Pay", icon: "minus") { addEntry(.expense, from: account) },
            Action(label: "Top up", icon: "plus") { addEntry(.income, from: account) },
            Action(label: "Move", icon: "arrow.left.arrow.right") { addEntry(.transfer, from: account) },
        ]
    }
}
