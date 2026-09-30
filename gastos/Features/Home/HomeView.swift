import SwiftUI
import SwiftData

struct HomeView: View {
    @Query(sort: [SortDescriptor(\Account.sortOrder), SortDescriptor(\Account.createdAt)]) private var accounts: [Account]
    @Query(sort: \Entry.date, order: .reverse) private var entries: [Entry]
    @Query private var recurring: [RecurringTransaction]
    @AppStorage(SettingsKey.currency) private var currency = "PHP"
    @AppStorage(SettingsKey.showSafeToSpend) private var showSafeToSpend = true
    @State private var addingWallet = false
    @State private var editing: Entry?

    private var month: DateInterval { Period.month.interval() }

    var body: some View {
        NavigationStack {
            ScrollView {
                if accounts.isEmpty {
                    EmptyStateView(
                        title: "Your money starts here.",
                        message: "Add your first wallet to start tracking where your money goes.",
                        buttonTitle: "Add Wallet"
                    ) { addingWallet = true }
                    .padding(.top, 60)
                } else {
                    VStack(alignment: .leading, spacing: 32) {
                        header
                        monthSummary
                        if showSafeToSpend { SafeToSpendCard(accounts: accounts, recurring: recurring, currency: currency) }
                        WhereItWent(entries: entries, interval: month, currency: currency)
                        ComingUp(recurring: recurring)
                        recent
                    }
                    .padding(20)
                }
            }
            .canvasBackground()
            .refreshable { await SyncService.shared.sync() }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink { SettingsView() } label: { Image(systemName: "gearshape") }
                        .accessibilityLabel("Settings")
                }
            }
            .sheet(isPresented: $addingWallet) { WalletEditor(account: nil) }
            .sheet(item: $editing) { AddEntryView(editing: $0) }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(greeting).font(.title3.weight(.semibold)).foregroundStyle(Color.muted)
            HeroAmount(value: Finance.totalMoney(accounts, currency: currency), currency: currency)
                .padding(.top, 8)
            Text("Total money").font(.subheadline).foregroundStyle(Color.muted)
        }
        .accessibilityElement(children: .combine)
    }

    private var greeting: String {
        switch Calendar.current.component(.hour, from: .now) {
        case 5..<12: "Good morning 👋"
        case 12..<18: "Good afternoon 👋"
        default: "Good evening 👋"
        }
    }

    private var monthSummary: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("This month").font(.headline).foregroundStyle(Color.ink)
            HStack(spacing: 12) {
                stat("Income", Finance.total(entries, .income, in: month, currency: currency), color: .success)
                stat("Spent", Finance.total(entries, .expense, in: month, currency: currency), color: .brand)
            }
        }
    }

    private func stat(_ label: String, _ value: Decimal, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.subheadline.weight(.semibold)).foregroundStyle(color)
            Text(value.moneyRounded(currency))
                .font(.system(.title2, design: .rounded, weight: .bold))
                .foregroundStyle(Color.ink)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
                .contentTransition(.numericText(value: value.double))
        }
        .card(padding: 16)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var recent: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle("Recent")
            if entries.isEmpty {
                Text("Nothing yet. Tap + to track your first peso.")
                    .font(.subheadline)
                    .foregroundStyle(Color.muted)
                    .card()
            } else {
                VStack(spacing: 4) {
                    ForEach(entries.prefix(5)) { entry in
                        Button { editing = entry } label: { EntryRow(entry: entry) }
                            .buttonStyle(.plain)
                    }
                }
                .card(padding: 14)
            }
        }
    }
}

struct SafeToSpendCard: View {
    let accounts: [Account]
    let recurring: [RecurringTransaction]
    let currency: String
    @State private var showDetails = false

    var body: some View {
        let result = Finance.safeToSpend(accounts: accounts, recurring: recurring, currency: currency)
        Button { withAnimation(.snappy) { showDetails.toggle() } } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("You can spend").font(.subheadline.weight(.semibold)).foregroundStyle(Color.muted)
                    Spacer()
                    Image(systemName: "info.circle").foregroundStyle(Color.muted)
                }
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(result.perDay.moneyRounded(currency))
                        .font(.system(.largeTitle, design: .rounded, weight: .bold))
                        .foregroundStyle(Color.ink)
                        .contentTransition(.numericText(value: result.perDay.double))
                    Text("/ day").font(.headline).foregroundStyle(Color.muted)
                }
                if showDetails {
                    VStack(alignment: .leading, spacing: 4) {
                        row("Total money", result.available)
                        row(result.untilPayday ? "Bills before payday" : "Bills still due this month", -result.upcoming)
                        row(result.untilPayday ? "Days until payday (\(result.until.friendlyDay))" : "Days left this month", nil, text: "\(result.daysLeft)")
                    }
                    .font(.subheadline)
                    .padding(.top, 4)
                    Text("Turn this off in Settings.").font(.footnote).foregroundStyle(Color.muted)
                }
            }
            .card()
        }
        .buttonStyle(.plain)
        .accessibilityHint("Shows how this is calculated")
    }

    private func row(_ label: String, _ value: Decimal?, text: String? = nil) -> some View {
        HStack {
            Text(label).foregroundStyle(Color.muted)
            Spacer()
            Text(text ?? value?.moneyRounded(currency) ?? "").foregroundStyle(Color.ink).monospacedDigit()
        }
    }
}

/// Spending per category with budget or share bars. Tap a category for the wallet breakdown.
struct WhereItWent: View {
    let entries: [Entry]
    let interval: DateInterval
    let currency: String
    var title = "Where did it go?"

    var body: some View {
        let rows = Finance.spendingByCategory(entries, in: interval, currency: currency)
        let total = rows.reduce(Decimal(0)) { $0 + $1.amount }
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(title)
            if rows.isEmpty {
                Text("No spending yet. Nice.").font(.subheadline).foregroundStyle(Color.muted).card()
            } else {
                VStack(spacing: 18) {
                    ForEach(rows, id: \.category?.id) { row in
                        NavigationLink {
                            CategoryDetailView(category: row.category, interval: interval, currency: currency)
                        } label: {
                            CategoryBar(category: row.category, amount: row.amount, total: total, currency: currency)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .card()
            }
        }
    }
}

struct CategoryBar: View {
    let category: Category?
    let amount: Decimal
    let total: Decimal
    let currency: String

    var body: some View {
        // With a budget the bar shows budget used; otherwise share of all spending.
        let budget = category?.budget?.amount ?? 0
        let ratio = budget > 0 ? (amount / budget).double : (total > 0 ? (amount / total).double : 0)
        VStack(spacing: 8) {
            HStack {
                Text(category?.icon ?? "📦")
                Text(category?.name ?? "Uncategorized").font(.body.weight(.semibold)).foregroundStyle(Color.ink)
                Spacer()
                Text(amount.money(currency)).font(.body.weight(.semibold).monospacedDigit()).foregroundStyle(Color.ink)
            }
            HStack(spacing: 10) {
                ProgressBar(value: ratio, color: budget > 0 && ratio > 1 ? .brand : Color(hex: category?.colorHex ?? "8E8E93"))
                Text(ratio.formatted(.percent.precision(.fractionLength(0))))
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(budget > 0 && ratio > 1 ? Color.brand : Color.muted)
                    .frame(width: 44, alignment: .trailing)
            }
            if budget > 0 {
                Text("\(amount.moneyRounded(currency)) of \(budget.moneyRounded(currency)) budget")
                    .font(.caption)
                    .foregroundStyle(Color.muted)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }
}

struct ComingUp: View {
    let recurring: [RecurringTransaction]

    var body: some View {
        let horizon = Calendar.current.date(byAdding: .day, value: 30, to: .now)!
        let upcoming = recurring
            .filter { $0.isActive && $0.nextDate <= horizon }
            .sorted { $0.nextDate < $1.nextDate }
            .prefix(4)
        if !upcoming.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                SectionTitle("Coming up") {
                    NavigationLink("See all") { RecurringListView() }
                }
                VStack(spacing: 14) {
                    ForEach(Array(upcoming)) { rule in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(rule.name.isEmpty ? (rule.category?.name ?? "Recurring") : rule.name)
                                    .font(.body.weight(.semibold)).foregroundStyle(Color.ink)
                                Text(rule.nextDate.friendlyDay).font(.subheadline).foregroundStyle(Color.muted)
                            }
                            Spacer()
                            Text((rule.type == .income ? "+" : "") + rule.amount.money(rule.currency))
                                .font(.body.weight(.semibold).monospacedDigit())
                                .foregroundStyle(rule.type == .income ? Color.success : Color.ink)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
                .card()
            }
        }
    }
}
