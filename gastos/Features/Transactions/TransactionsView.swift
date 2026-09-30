import SwiftUI
import SwiftData

struct TransactionsView: View {
    enum DateFilter: String, CaseIterable, Identifiable {
        case all = "All time", week = "This week", month = "This month", lastMonth = "Last month", year = "This year"
        var id: String { rawValue }

        var interval: DateInterval? {
            switch self {
            case .all: nil
            case .week: Period.week.interval()
            case .month: Period.month.interval()
            case .lastMonth: Period.month.previous(Period.month.interval())
            case .year: Period.year.interval()
            }
        }
    }

    @Environment(\.modelContext) private var context
    @Environment(\.addEntry) private var addEntry
    @Query(sort: \Entry.date, order: .reverse) private var entries: [Entry]
    @Query(sort: [SortDescriptor(\Account.sortOrder), SortDescriptor(\Account.createdAt)]) private var accounts: [Account]
    @Query(sort: \Category.sortOrder) private var categories: [Category]

    @State private var search = ""
    @State private var categoryFilter: Category?
    @State private var accountFilter: Account?
    @State private var dateFilter = DateFilter.all
    @State private var editing: Entry?

    private var filtered: [Entry] {
        let query = search.trimmingCharacters(in: .whitespaces)
        let interval = dateFilter.interval
        return entries.filter { entry in
            if let interval, !interval.containsHalfOpen(entry.date) { return false }
            if let categoryFilter, entry.category != categoryFilter { return false }
            if let accountFilter, entry.account != accountFilter && entry.toAccount != accountFilter { return false }
            guard !query.isEmpty else { return true }
            return [entry.note, entry.category?.name ?? "", entry.account?.name ?? "", entry.toAccount?.name ?? "", entry.amount.formatted()]
                .contains { $0.localizedStandardContains(query) }
        }
    }

    private var isFiltering: Bool { categoryFilter != nil || accountFilter != nil || dateFilter != .all }

    var body: some View {
        let days = Dictionary(grouping: filtered) { Calendar.current.startOfDay(for: $0.date) }
            .sorted { $0.key > $1.key }

        NavigationStack {
            List {
                ForEach(days, id: \.key) { day, items in
                    Section(day.friendlyDay) {
                        ForEach(items) { entry in
                            Button { editing = entry } label: { EntryRow(entry: entry) }
                                .buttonStyle(.plain)
                                .swipeActions(edge: .trailing) {
                                    Button("Delete", systemImage: "trash", role: .destructive) { delete(entry) }
                                }
                                .swipeActions(edge: .leading) {
                                    Button("Duplicate", systemImage: "plus.square.on.square") { duplicate(entry) }
                                        .tint(.brand)
                                }
                                .contextMenu {
                                    Button("Edit", systemImage: "pencil") { editing = entry }
                                    Button("Duplicate", systemImage: "plus.square.on.square") { duplicate(entry) }
                                    Button("Delete", systemImage: "trash", role: .destructive) { delete(entry) }
                                }
                        }
                    }
                }
            }
            .canvasBackground()
            .overlay {
                if entries.isEmpty {
                    ContentUnavailableView {
                        Label("No transactions yet", systemImage: "list.bullet")
                    } description: {
                        Text("Everything you add shows up here.")
                    } actions: {
                        Button("Add Expense") { addEntry(.expense) }.buttonStyle(.borderedProminent)
                    }
                } else if filtered.isEmpty {
                    ContentUnavailableView.search
                }
            }
            .navigationTitle("Transactions")
            .searchable(text: $search, prompt: "Search")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { filterMenu }
            }
            .sheet(item: $editing) { AddEntryView(editing: $0) }
        }
    }

    private var filterMenu: some View {
        Menu {
            Picker("Date", selection: $dateFilter) {
                ForEach(DateFilter.allCases) { Text($0.rawValue).tag($0) }
            }
            Picker("Category", selection: $categoryFilter) {
                Text("All categories").tag(Category?.none)
                ForEach(categories) { Text("\($0.icon) \($0.name)").tag(Optional($0)) }
            }
            .pickerStyle(.menu)
            Picker("Wallet", selection: $accountFilter) {
                Text("All wallets").tag(Account?.none)
                ForEach(accounts) { Text("\($0.icon) \($0.name)").tag(Optional($0)) }
            }
            .pickerStyle(.menu)
            if isFiltering {
                Button("Clear filters", systemImage: "xmark") {
                    categoryFilter = nil
                    accountFilter = nil
                    dateFilter = .all
                }
            }
        } label: {
            Image(systemName: isFiltering ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
        }
        .accessibilityLabel("Filter")
    }

    private func delete(_ entry: Entry) {
        withAnimation { context.delete(entry) }
    }

    private func duplicate(_ entry: Entry) {
        let copy = Entry(type: entry.type, amount: entry.amount, date: .now, note: entry.note, account: entry.account, toAccount: entry.toAccount, category: entry.category)
        withAnimation(.spring) { context.insert(copy) }
        Haptics.success()
    }
}
