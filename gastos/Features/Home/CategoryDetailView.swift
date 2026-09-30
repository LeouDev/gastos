import SwiftUI
import SwiftData

/// "Food — ₱8,420 spent", then which wallets paid for it.
struct CategoryDetailView: View {
    let category: Category?
    let interval: DateInterval
    let currency: String

    @Query(sort: \Entry.date, order: .reverse) private var allEntries: [Entry]
    @State private var editing: Entry?

    private var entries: [Entry] {
        Finance.entries(allEntries, .expense, in: interval, currency: currency)
            .filter { $0.category?.persistentModelID == category?.persistentModelID }
    }

    var body: some View {
        let entries = entries
        let total = entries.reduce(Decimal(0)) { $0 + $1.amount }
        let byWallet = Finance.spendingByAccount(entries, in: interval, currency: currency)

        List {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    HeroAmount(value: total, currency: currency, size: 44)
                    Text("spent · \(intervalLabel)").font(.subheadline).foregroundStyle(Color.muted)
                    if let budget = category?.budget, budget.amount > 0 {
                        ProgressBar(value: (total / budget.amount).double, color: total > budget.amount ? .brand : Color(hex: category?.colorHex ?? "8E8E93"))
                            .padding(.top, 8)
                        Text("\(total.moneyRounded(currency)) of \(budget.amount.moneyRounded(currency)) monthly budget")
                            .font(.caption).foregroundStyle(Color.muted)
                    }
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 8, leading: 4, bottom: 8, trailing: 4))
            }

            Section("Paid with") {
                ForEach(byWallet, id: \.account?.id) { row in
                    HStack {
                        IconBadge(icon: row.account?.icon ?? "wallet.bifold.fill", colorHex: row.account?.colorHex ?? "8E8E93", size: 30)
                        Text(row.account?.name ?? "Deleted wallet").foregroundStyle(Color.ink)
                        Spacer()
                        Text(row.amount.money(currency)).font(.body.weight(.semibold).monospacedDigit())
                    }
                    .accessibilityElement(children: .combine)
                }
            }

            Section("Transactions") {
                ForEach(entries) { entry in
                    Button { editing = entry } label: { EntryRow(entry: entry) }
                        .buttonStyle(.plain)
                }
            }
        }
        .canvasBackground()
        .navigationTitle(category?.name ?? "Uncategorized")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $editing) { AddEntryView(editing: $0) }
    }

    private var intervalLabel: String {
        let end = interval.end.addingTimeInterval(-1)
        if Calendar.current.isDate(interval.start, equalTo: end, toGranularity: .month) {
            return interval.start.formatted(.dateTime.month(.wide).year())
        }
        return "\(interval.start.formatted(.dateTime.month(.abbreviated).day())) – \(end.formatted(.dateTime.month(.abbreviated).day()))"
    }
}
