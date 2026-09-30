import SwiftUI
import SwiftData

/// One optional monthly limit per category. Empty means no budget.
struct BudgetsView: View {
    @Query(sort: \Category.sortOrder) private var categories: [Category]
    @Query(sort: \Entry.date, order: .reverse) private var entries: [Entry]
    @AppStorage(SettingsKey.currency) private var currency = "PHP"

    var body: some View {
        let month = Period.month.interval()
        let spending = Finance.spendingByCategory(entries, in: month, currency: currency)
        List {
            Section {
                ForEach(categories) { category in
                    BudgetEditRow(
                        category: category,
                        spent: spending.first { $0.category == category }?.amount ?? 0,
                        currency: currency
                    )
                }
            } footer: {
                Text("Budgets reset every month. They're just a guide — gastos never blocks spending.")
            }
        }
        .canvasBackground()
        .navigationTitle("Monthly Budgets")
        .scrollDismissesKeyboard(.interactively)
    }
}

private struct BudgetEditRow: View {
    let category: Category
    let spent: Decimal
    let currency: String
    @Environment(\.modelContext) private var context
    @State private var text = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("\(category.icon) \(category.name)")
                Spacer()
                Text(currencySymbol(currency)).foregroundStyle(Color.muted)
                TextField("No budget", text: $text)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 120)
                    .font(.body.monospacedDigit())
            }
            if let limit = category.budget?.amount, limit > 0 {
                ProgressBar(value: (spent / limit).double, color: spent > limit ? .brand : Color(hex: category.colorHex), height: 6)
                Text("\(spent.moneyRounded(currency)) spent this month")
                    .font(.caption).foregroundStyle(Color.muted)
            }
        }
        .onAppear {
            if let amount = category.budget?.amount, amount > 0 { text = amount.formatted(.number.grouping(.never)) }
        }
        .onChange(of: text) { _, new in save(new) }
    }

    private func save(_ text: String) {
        let amount = parseAmount(text) ?? 0
        if amount > 0 {
            if let budget = category.budget { budget.amount = amount } else { context.insert(Budget(amount: amount, category: category)) }
        } else if let budget = category.budget {
            context.delete(budget)
        }
    }
}
