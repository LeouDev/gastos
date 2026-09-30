import SwiftUI
import SwiftData

struct HomeView: View {
    @Query(sort: [SortDescriptor(\Account.sortOrder), SortDescriptor(\Account.createdAt)]) private var accounts: [Account]
    @Query(sort: \Entry.date, order: .reverse) private var entries: [Entry]
    @Query private var recurring: [RecurringTransaction]
    @AppStorage(SettingsKey.currency) private var currency = "PHP"
    @AppStorage(SettingsKey.homeCardSkin) private var homeSkin = CardSkin.Texture.ember.rawValue
    @Environment(\.addEntry) private var addEntry
    @State private var addingWallet = false
    @State private var editing: Entry?
    @State private var cardPage: String? = HomeView.allWalletsID
    @State private var customizing: CustomizeTarget?

    private static let allWalletsID = "all"
    private var month: DateInterval { Period.month.interval() }
    private var activeAccounts: [Account] { accounts.filter(\.isActive) }

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
                    VStack(alignment: .leading, spacing: 26) {
                        topBar
                        title
                        cards
                        quickActions
                        monthSummary
                        WhereItWent(entries: entries, interval: month, currency: currency)
                        ComingUp(recurring: recurring)
                        recent
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)
                }
            }
            .canvasBackground()
            .refreshable { await SyncService.shared.sync() }
            .toolbarVisibility(.hidden, for: .navigationBar)
            .navigationDestination(for: Account.self) { WalletDetailView(account: $0) }
            .sheet(isPresented: $addingWallet) { WalletEditor(account: nil) }
            .sheet(item: $editing) { AddEntryView(editing: $0) }
            .sheet(item: $customizing) { CardCustomizeView(account: $0.account) }
        }
    }

    // MARK: Header

    private var topBar: some View {
        HStack(spacing: 10) {
            LogoSphere(size: 34)
            Text("\(greeting), ").foregroundStyle(Color.muted) + Text("welcome back").foregroundStyle(Color.ink)
            Spacer(minLength: 0)
            NavigationLink { SettingsView() } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.ink)
                    .frame(width: 38, height: 38)
                    .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 13))
            }
            .accessibilityLabel("Settings")
        }
        .font(.subheadline)
        .padding(6)
        .padding(.leading, 2)
        .glassEffect(.regular, in: .rect(cornerRadius: 22))
        .padding(.top, 8)
    }

    private var title: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("\(greeting)!").foregroundStyle(Color.ink)
            Text("Let's see where it went.").foregroundStyle(Color.muted)
        }
        .font(.system(.largeTitle, weight: .medium))
        .tracking(-0.6)
        .accessibilityElement(children: .combine)
    }

    private var greeting: String {
        switch Calendar.current.component(.hour, from: .now) {
        case 5..<12: "Good morning"
        case 12..<18: "Good afternoon"
        default: "Good evening"
        }
    }

    // MARK: Cards

    private var cards: some View {
        let total = Finance.totalMoney(accounts, currency: currency)
        let ids = [Self.allWalletsID] + activeAccounts.map(\.id.uuidString)
        return VStack(spacing: 12) {
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 12) {
                    WalletCardView(title: "All wallets", kind: "\(activeAccounts.count) wallets", caption: "Total money",
                                   amount: total, currency: currency, emblem: "gastos",
                                   skin: CardSkin(raw: homeSkin, fallbackHex: "D8141A"))
                        .containerRelativeFrame(.horizontal) { width, _ in width - 40 }
                        .id(Self.allWalletsID)
                    ForEach(activeAccounts) { account in
                        NavigationLink(value: account) { WalletCardView(account: account) }
                            .buttonStyle(.plain)
                            .containerRelativeFrame(.horizontal) { width, _ in width - 40 }
                            .id(account.id.uuidString)
                    }
                }
                .scrollTargetLayout()
            }
            .contentMargins(.horizontal, 20, for: .scrollContent)
            .scrollTargetBehavior(.viewAligned)
            .scrollPosition(id: $cardPage)
            .scrollClipDisabled()
            .padding(.horizontal, -20)
            .overlay(alignment: .topTrailing) {
                Button { customizing = CustomizeTarget(account: activeAccounts.first { $0.id.uuidString == cardPage }) } label: {
                    Label("Customize", systemImage: "paintbrush.pointed")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.ink)
                }
                .buttonStyle(.glass)
                .offset(x: -10, y: -16)
            }

            HStack(spacing: 6) {
                ForEach(ids, id: \.self) { id in
                    Capsule()
                        .fill(id == (cardPage ?? Self.allWalletsID) ? Color.ink : Color.muted.opacity(0.4))
                        .frame(width: id == (cardPage ?? Self.allWalletsID) ? 16 : 6, height: 6)
                }
            }
            .animation(.snappy, value: cardPage)
            .accessibilityHidden(true)
        }
    }

    // MARK: Actions

    private var quickActions: some View {
        GlassEffectContainer {
            HStack(spacing: 10) {
                quickAction("Expense", icon: "minus", type: .expense)
                quickAction("Income", icon: "plus", type: .income)
                quickAction("Transfer", icon: "arrow.left.arrow.right", type: .transfer)
            }
        }
    }

    private func quickAction(_ label: String, icon: String, type: EntryType) -> some View {
        Button { addEntry(type, from: activeAccounts.first { $0.id.uuidString == cardPage }) } label: {
            VStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .heavy))
                    .foregroundStyle(Color.canvas)
                    .frame(width: 26, height: 26)
                    .background(Color.ink, in: .circle)
                Text(label).font(.subheadline.weight(.medium)).foregroundStyle(Color.ink)
            }
            .frame(maxWidth: .infinity, minHeight: 88)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 22))
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

/// Which card the customize sheet edits; `account == nil` is the Home "All wallets" card.
struct CustomizeTarget: Identifiable {
    let id = UUID()
    var account: Account?
}

/// The strip above the tab bar: what's safe to spend today, tap for the math.
struct SafeToSpendAccessory: View {
    @Query private var accounts: [Account]
    @Query private var recurring: [RecurringTransaction]
    @Query(sort: \Entry.date, order: .reverse) private var entries: [Entry]
    @AppStorage(SettingsKey.currency) private var currency = "PHP"
    @AppStorage(SettingsKey.showSafeToSpend) private var showSafeToSpend = true
    @State private var showingMath = false

    var body: some View {
        Button { if canShowMath { showingMath = true } } label: {
            HStack(spacing: 12) {
                badge
                VStack(alignment: .leading, spacing: 0) {
                    Text(headline).font(.subheadline.weight(.semibold)).foregroundStyle(Color.ink).lineLimit(1)
                    Text(subline).font(.caption).foregroundStyle(Color.muted).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showingMath) {
            SafeToSpendCard(accounts: accounts, recurring: recurring, currency: currency, alwaysExpanded: true)
                .padding(20)
                .presentationDetents([.height(320)])
                .presentationBackground(Color.canvas)
        }
    }

    private var canShowMath: Bool { !accounts.isEmpty && showSafeToSpend }
    private var result: Finance.SafeToSpend { Finance.safeToSpend(accounts: accounts, recurring: recurring, currency: currency) }

    private var badge: some View {
        Text(canShowMath ? "\(result.daysLeft)d" : "₱")
            .font(.caption.weight(.bold))
            .foregroundStyle(.white)
            .frame(width: 34, height: 34)
            .background(Color.brand, in: .circle)
    }

    private var headline: String {
        if accounts.isEmpty { return "Add a wallet to start" }
        if showSafeToSpend { return "\(result.perDay.moneyRounded(currency)) left today" }
        return "\(Finance.total(entries, .expense, in: Period.month.interval(), currency: currency).moneyRounded(currency)) spent this month"
    }

    private var subline: String {
        if accounts.isEmpty { return "Tap + below" }
        if showSafeToSpend { return result.untilPayday ? "Until payday · bills set aside" : "Until month end · bills set aside" }
        return "gastos"
    }
}

struct SafeToSpendCard: View {
    let accounts: [Account]
    let recurring: [RecurringTransaction]
    let currency: String
    var alwaysExpanded = false
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
                if showDetails || alwaysExpanded {
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
                IconBadge(icon: category?.icon ?? "square.grid.2x2.fill", colorHex: category?.colorHex ?? "8E8E93", size: 30)
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
