import SwiftUI
import SwiftData
import Charts

struct InsightsView: View {
    @Query(sort: \Entry.date, order: .reverse) private var entries: [Entry]
    @Query(sort: \Category.sortOrder) private var categories: [Category]
    @AppStorage(SettingsKey.currency) private var currency = "PHP"
    @AppStorage("insightsPeriod") private var period = Period.month

    var body: some View {
        let interval = period.interval()
        let spent = Finance.total(entries, .expense, in: interval, currency: currency)
        let previous = Finance.total(entries, .expense, in: period.previousToDate(interval), currency: currency)
        let byCategory = Finance.spendingByCategory(entries, in: interval, currency: currency)
        let byAccount = Finance.spendingByAccount(entries, in: interval, currency: currency)

        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    Picker("Period", selection: $period) {
                        ForEach(Period.allCases) { Text($0.shortLabel).tag($0) }
                    }
                    .pickerStyle(.segmented)

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Spent · \(period.label.lowercased())").font(.subheadline).foregroundStyle(Color.muted)
                        HeroAmount(value: spent, currency: currency, size: 44)
                        if let change = Finance.change(current: spent, previous: previous) {
                            Label(
                                "\(change.formatted(.percent.precision(.fractionLength(0)).sign(strategy: .always()))) vs \(previousLabel)",
                                systemImage: change > 0 ? "arrow.up.right" : "arrow.down.right"
                            )
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(change > 0 ? Color.warning : Color.success)
                        }
                    }
                    .accessibilityElement(children: .combine)

                    chart(interval: interval)

                    HStack(spacing: 12) {
                        highlight("Top category", icon: byCategory.first?.category?.icon ?? "📦",
                                  name: byCategory.first.map { $0.category?.name ?? "Uncategorized" }, amount: byCategory.first?.amount)
                        highlight("Most used wallet", icon: byAccount.first?.account?.icon ?? "👛",
                                  name: byAccount.first.map { $0.account?.name ?? "Deleted wallet" }, amount: byAccount.first?.amount)
                    }

                    budgets

                    WhereItWent(entries: entries, interval: interval, currency: currency, title: "By category")
                }
                .padding(20)
            }
            .canvasBackground()
            .navigationTitle("Insights")
        }
    }

    private var previousLabel: String {
        switch period {
        case .week: "this time last week"
        case .month: "this time last month"
        case .quarter: "the 3 months before"
        case .year: "this time last year"
        }
    }

    @ViewBuilder
    private func chart(interval: DateInterval) -> some View {
        let series = Finance.spendingSeries(entries, in: interval, unit: period.unit, currency: currency)
        VStack(alignment: .leading, spacing: 12) {
            Text(period.unit == .day ? "Daily spending" : period.unit == .weekOfYear ? "Weekly spending" : "Monthly spending")
                .font(.headline).foregroundStyle(Color.ink)
            Chart(series, id: \.date) { point in
                BarMark(
                    x: .value("Date", point.date, unit: period.unit),
                    y: .value("Spent", point.amount.double)
                )
                .foregroundStyle(Color.brand.gradient)
                .cornerRadius(4)
            }
            .chartYAxis {
                AxisMarks { value in
                    AxisGridLine().foregroundStyle(Color.track)
                    AxisValueLabel {
                        if let amount = value.as(Double.self) {
                            Text(Decimal(amount).formatted(.currency(code: currency).notation(.compactName).precision(.fractionLength(0))))
                        }
                    }
                }
            }
            .frame(height: 180)
            .accessibilityLabel("Spending chart for \(period.label.lowercased())")
        }
        .card()
    }

    private func highlight(_ title: String, icon: String, name: String?, amount: Decimal?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(Color.muted)
            Text(icon).font(.title2)
            Text(name ?? "—").font(.headline).foregroundStyle(Color.ink).lineLimit(1)
            Text(amount?.moneyRounded(currency) ?? " ").font(.subheadline.monospacedDigit()).foregroundStyle(Color.muted)
        }
        .card(padding: 16)
        .accessibilityElement(children: .combine)
    }

    private var budgets: some View {
        let month = Period.month.interval()
        let budgeted = categories.filter { ($0.budget?.amount ?? 0) > 0 }
        return VStack(alignment: .leading, spacing: 12) {
            SectionTitle("Budgets") {
                NavigationLink(budgeted.isEmpty ? "Set up" : "Edit") { BudgetsView() }
            }
            if budgeted.isEmpty {
                Text("Set a monthly limit for a category to see how much is left.")
                    .font(.subheadline).foregroundStyle(Color.muted).card()
            } else {
                VStack(spacing: 18) {
                    ForEach(budgeted) { category in
                        let spent = Finance.entries(entries, .expense, in: month, currency: currency)
                            .filter { $0.category == category }
                            .reduce(Decimal(0)) { $0 + $1.amount }
                        BudgetRow(category: category, spent: spent, currency: currency)
                    }
                }
                .card()
            }
        }
    }
}

struct BudgetRow: View {
    let category: Category
    let spent: Decimal
    let currency: String

    var body: some View {
        let limit = category.budget?.amount ?? 0
        let ratio = limit > 0 ? (spent / limit).double : 0
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("\(category.icon) \(category.name)").font(.body.weight(.semibold)).foregroundStyle(Color.ink)
                Spacer()
                Text(ratio.formatted(.percent.precision(.fractionLength(0))))
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .foregroundStyle(ratio > 1 ? Color.brand : ratio > 0.85 ? Color.warning : Color.muted)
            }
            ProgressBar(value: ratio, color: ratio > 1 ? .brand : Color(hex: category.colorHex))
            Text("\(spent.moneyRounded(currency)) / \(limit.moneyRounded(currency))")
                .font(.caption.monospacedDigit()).foregroundStyle(Color.muted)
        }
        .accessibilityElement(children: .combine)
    }
}

