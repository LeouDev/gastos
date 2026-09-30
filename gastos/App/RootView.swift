import SwiftUI
import AppIntents

enum AppTab: Hashable {
    case home, transactions, add, wallets, insights
}

struct AddRequest: Identifiable {
    let id = UUID()
    var type: EntryType?
}

struct RootView: View {
    @State private var tab: AppTab = .home
    @State private var addRequest: AddRequest?

    var body: some View {
        // The middle "+" is a tab that never becomes selected; tapping it opens the add sheet.
        TabView(selection: Binding(get: { tab }, set: { new in
            if new == .add { addRequest = AddRequest() } else { tab = new }
        })) {
            Tab("Home", systemImage: "house.fill", value: AppTab.home) { HomeView() }
            Tab("Transactions", systemImage: "list.bullet", value: AppTab.transactions) { TransactionsView() }
            Tab("Add", systemImage: "plus.circle.fill", value: AppTab.add) { Color.canvas }
            Tab("Wallets", systemImage: "wallet.bifold.fill", value: AppTab.wallets) { WalletsView() }
            Tab("Insights", systemImage: "chart.bar.fill", value: AppTab.insights) { InsightsView() }
        }
        .environment(\.addEntry) { type in addRequest = AddRequest(type: type) }
        .sheet(item: $addRequest) { request in
            AddEntryView(initialType: request.type)
        }
        .onOpenURL(perform: open)
    }

    /// gastos://add, gastos://add/expense, gastos://add/income, gastos://add/transfer
    private func open(_ url: URL) {
        guard url.scheme == "gastos", url.host() == "add" else { return }
        addRequest = AddRequest(type: EntryType(rawValue: url.lastPathComponent))
    }
}

// MARK: - Shortcuts

struct AddExpenseIntent: AppIntent {
    static let title: LocalizedStringResource = "Add Expense"
    static let description = IntentDescription("Opens gastos ready to record an expense.")

    func perform() async throws -> some IntentResult & OpensIntent {
        .result(opensIntent: OpenURLIntent(URL(string: "gastos://add/expense")!))
    }
}

struct GastosShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: AddExpenseIntent(),
            phrases: ["Add an expense in \(.applicationName)", "Log spending in \(.applicationName)"],
            shortTitle: "Add Expense",
            systemImageName: "plus.circle.fill"
        )
    }
}
