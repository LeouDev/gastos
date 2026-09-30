import WidgetKit
import SwiftUI
import SwiftData

@main
struct GastosWidgets: WidgetBundle {
    var body: some Widget {
        MoneyWidget()
    }
}

struct MoneySnapshot: TimelineEntry {
    var date = Date.now
    var total: Decimal = 0
    var perDay: Decimal?
    var currency = "PHP"
    var hasWallets = false
}

struct MoneyProvider: TimelineProvider {
    func placeholder(in context: Context) -> MoneySnapshot {
        MoneySnapshot(total: 39_770, perDay: 1_023, hasWallets: true)
    }

    func getSnapshot(in context: Context, completion: @escaping (MoneySnapshot) -> Void) {
        completion(context.isPreview ? placeholder(in: context) : load())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<MoneySnapshot>) -> Void) {
        // The app reloads timelines when it goes to the background; midnight refresh keeps "per day" right.
        let midnight = Calendar.current.startOfDay(for: .now.addingTimeInterval(86_400))
        completion(Timeline(entries: [load()], policy: .after(midnight)))
    }

    private func load() -> MoneySnapshot {
        let defaults = AppGroup.defaults
        let currency = defaults.string(forKey: SettingsKey.currency) ?? "PHP"
        guard let container = try? Store.container() else { return MoneySnapshot(currency: currency) }
        let context = ModelContext(container)
        let accounts = (try? context.fetch(FetchDescriptor<Account>())) ?? []
        let recurring = (try? context.fetch(FetchDescriptor<RecurringTransaction>())) ?? []
        let total = Finance.totalMoney(accounts, currency: currency)
        var perDay: Decimal?
        if defaults.object(forKey: SettingsKey.showSafeToSpend) as? Bool ?? true {
            perDay = Finance.safeToSpend(accounts: accounts, recurring: recurring, currency: currency).perDay
        }
        return MoneySnapshot(total: total, perDay: perDay, currency: currency, hasWallets: !accounts.isEmpty)
    }
}

struct MoneyWidgetView: View {
    let entry: MoneySnapshot
    @Environment(\.widgetFamily) private var family

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text("gastos").font(.system(.headline, design: .rounded, weight: .heavy)).foregroundStyle(Color.brand)
                Spacer(minLength: 4)
                if entry.hasWallets {
                    figure(entry.total, "total money")
                    if let perDay = entry.perDay {
                        figure(perDay, "safe to spend today").padding(.top, 6)
                    }
                } else {
                    Text("Add a wallet to start.").font(.subheadline).foregroundStyle(Color.muted)
                }
            }
            if family == .systemMedium {
                Spacer()
                VStack(spacing: 8) {
                    quickAdd("Expense", "minus", "gastos://add/expense")
                    quickAdd("Income", "plus", "gastos://add/income")
                    quickAdd("Transfer", "arrow.left.arrow.right", "gastos://add/transfer")
                }
                .frame(maxWidth: 130)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .containerBackground(Color.canvas, for: .widget)
        .widgetURL(URL(string: "gastos://home"))
    }

    private func figure(_ value: Decimal, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(value.moneyRounded(entry.currency))
                .font(.system(.title2, design: .rounded, weight: .bold))
                .foregroundStyle(Color.ink)
                .minimumScaleFactor(0.5)
                .lineLimit(1)
            Text(label).font(.caption).foregroundStyle(Color.muted)
        }
    }

    private func quickAdd(_ title: String, _ icon: String, _ url: String) -> some View {
        Link(destination: URL(string: url)!) {
            Label(title, systemImage: icon)
                .font(.caption.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: 32)
                .foregroundStyle(title == "Expense" ? .white : Color.ink)
                .background(title == "Expense" ? Color.brand : Color.card, in: .capsule)
        }
    }
}

struct MoneyWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "MoneyWidget", provider: MoneyProvider()) { entry in
            MoneyWidgetView(entry: entry)
        }
        .configurationDisplayName("Money")
        .description("Your total money and what you can spend today.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
