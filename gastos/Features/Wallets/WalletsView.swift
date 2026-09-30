import SwiftUI
import SwiftData

struct WalletsView: View {
    @Query(sort: [SortDescriptor(\Account.sortOrder), SortDescriptor(\Account.createdAt)]) private var accounts: [Account]
    @AppStorage(SettingsKey.currency) private var currency = "PHP"
    @State private var adding = false

    var body: some View {
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
                    VStack(alignment: .leading, spacing: 28) {
                        VStack(alignment: .leading, spacing: 4) {
                            HeroAmount(value: Finance.totalMoney(accounts, currency: currency), currency: currency, size: 44)
                            Text("Total across active wallets").font(.subheadline).foregroundStyle(Color.muted)
                        }
                        .accessibilityElement(children: .combine)

                        ForEach(AccountType.allCases) { type in
                            let group = accounts.filter { $0.type == type && $0.isActive }
                            if !group.isEmpty {
                                section(type.pluralLabel, group)
                            }
                        }
                        let hidden = accounts.filter { !$0.isActive }
                        if !hidden.isEmpty {
                            section("Hidden", hidden)
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
            .sheet(isPresented: $adding) { WalletEditor(account: nil) }
        }
    }

    private func section(_ title: String, _ group: [Account]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.headline).foregroundStyle(Color.muted)
            ForEach(group) { account in
                NavigationLink { WalletDetailView(account: account) } label: { WalletCard(account: account) }
                    .buttonStyle(.plain)
            }
        }
    }
}

struct WalletCard: View {
    let account: Account

    var body: some View {
        HStack(spacing: 14) {
            EmojiBadge(emoji: account.icon, colorHex: account.colorHex, size: 48)
            VStack(alignment: .leading, spacing: 2) {
                Text(account.name).font(.body.weight(.semibold)).foregroundStyle(Color.ink)
                Text(account.type.label).font(.subheadline).foregroundStyle(Color.muted)
            }
            Spacer()
            BalanceLabel(account: account)
        }
        .card(padding: 16)
        .opacity(account.isActive ? 1 : 0.6)
        .accessibilityElement(children: .combine)
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
    @AppStorage(SettingsKey.currency) private var currency = "PHP"
    @Environment(\.addEntry) private var addEntry
    @Environment(\.dismiss) private var dismiss
    @State private var editingWallet = false
    @State private var editing: Entry?

    var body: some View {
        let entries = ((account.entries ?? []) + (account.incomingTransfers ?? []))
            .sorted { $0.date > $1.date }
        let month = Period.month.interval()
        let byCategory = Finance.spendingByCategory(entries.filter { $0.account == account }, in: month, currency: account.currency)

        List {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 12) {
                        EmojiBadge(emoji: account.icon, colorHex: account.colorHex, size: 52)
                        Text(account.type.label).font(.headline).foregroundStyle(Color.muted)
                    }
                    if account.type == .creditCard {
                        HeroAmount(value: max(0, -account.balance), currency: account.currency, size: 44)
                        Text(account.balance > 0 ? "Credit of \(account.balance.money(account.currency))" : "Owed on this card")
                            .font(.subheadline).foregroundStyle(Color.muted)
                        Button("Pay this card", systemImage: "arrow.left.arrow.right") { addEntry(.transfer) }
                            .buttonStyle(.bordered)
                            .padding(.top, 8)
                    } else {
                        HeroAmount(value: account.balance, currency: account.currency, size: 44)
                        Text("Balance").font(.subheadline).foregroundStyle(Color.muted)
                    }
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 8, leading: 4, bottom: 8, trailing: 4))
            }

            if !byCategory.isEmpty {
                Section("Spent this month") {
                    ForEach(byCategory, id: \.category?.id) { row in
                        HStack {
                            Text(row.category?.icon ?? "📦")
                            Text(row.category?.name ?? "Uncategorized")
                            Spacer()
                            Text(row.amount.money(account.currency)).font(.body.weight(.semibold).monospacedDigit())
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            }

            Section("Activity") {
                if entries.isEmpty {
                    Text("No activity yet.").foregroundStyle(Color.muted)
                }
                ForEach(entries) { entry in
                    Button { editing = entry } label: { EntryRow(entry: entry, perspective: account) }
                        .buttonStyle(.plain)
                }
            }
        }
        .canvasBackground()
        .navigationTitle(account.name)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Edit") { editingWallet = true }
            }
        }
        .sheet(isPresented: $editingWallet) { WalletEditor(account: account) { dismiss() } }
        .sheet(item: $editing) { AddEntryView(editing: $0) }
    }
}
