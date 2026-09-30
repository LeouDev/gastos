import SwiftUI
import SwiftData

struct RecurringListView: View {
    @Query(sort: \RecurringTransaction.createdAt) private var rules: [RecurringTransaction]
    @State private var editing: RecurringTransaction?
    @State private var adding = false

    var body: some View {
        List {
            if rules.isEmpty {
                ContentUnavailableView {
                    Label("Nothing recurring yet", systemImage: "repeat")
                } description: {
                    Text("Add your salary, rent, bills and subscriptions. gastos records them on the day they happen.")
                } actions: {
                    Button("Add Recurring") { adding = true }.buttonStyle(.borderedProminent)
                }
                .listRowBackground(Color.clear)
            }
            ForEach(rules.sorted { ($0.isActive ? 0 : 1, $0.nextDate) < ($1.isActive ? 0 : 1, $1.nextDate) }) { rule in
                Button { editing = rule } label: {
                    HStack(spacing: 14) {
                        EmojiBadge(emoji: rule.type == .income ? "💰" : rule.category?.icon ?? "🔁", colorHex: rule.category?.colorHex ?? "8E8E93")
                        VStack(alignment: .leading, spacing: 2) {
                            Text(rule.name.isEmpty ? "Recurring" : rule.name).font(.body.weight(.semibold)).foregroundStyle(Color.ink)
                            Text(rule.isActive ? "\(rule.frequency.label) · next \(rule.nextDate.friendlyDay)" : "Paused")
                                .font(.subheadline).foregroundStyle(Color.muted)
                        }
                        Spacer()
                        Text((rule.type == .income ? "+" : "") + rule.amount.money(rule.currency))
                            .font(.body.weight(.semibold).monospacedDigit())
                            .foregroundStyle(rule.type == .income ? Color.success : Color.ink)
                    }
                    .opacity(rule.isActive ? 1 : 0.5)
                }
                .buttonStyle(.plain)
            }
        }
        .canvasBackground()
        .navigationTitle("Recurring")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Add Recurring", systemImage: "plus") { adding = true }
            }
        }
        .sheet(item: $editing) { RecurringEditor(rule: $0) }
        .sheet(isPresented: $adding) { RecurringEditor(rule: nil) }
    }
}

struct RecurringEditor: View {
    let rule: RecurringTransaction?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(filter: #Predicate<Account> { $0.isActive }, sort: [SortDescriptor(\Account.sortOrder), SortDescriptor(\Account.createdAt)])
    private var accounts: [Account]
    @Query(sort: \Category.sortOrder) private var categories: [Category]

    @State private var name = ""
    @State private var type = EntryType.expense
    @State private var amountText = ""
    @State private var category: Category?
    @State private var account: Account?
    @State private var frequency = Frequency.monthly
    @State private var nextDate = Date.now
    @State private var isActive = true
    @State private var problem: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Type", selection: $type) {
                        Text("Expense").tag(EntryType.expense)
                        Text("Income").tag(EntryType.income)
                    }
                    .pickerStyle(.segmented)
                    TextField(type == .income ? "Salary" : "Netflix, rent, internet…", text: $name)
                    HStack {
                        Text(currencySymbol(account?.currency ?? "PHP")).foregroundStyle(Color.muted)
                        TextField("Amount", text: $amountText).keyboardType(.decimalPad).font(.body.monospacedDigit())
                    }
                }
                Section {
                    if type == .expense {
                        Picker("Category", selection: $category) {
                            Text("None").tag(Category?.none)
                            ForEach(categories) { Text("\($0.icon) \($0.name)").tag(Optional($0)) }
                        }
                    }
                    Picker(type == .income ? "Received in" : "Paid with", selection: $account) {
                        Text("Choose").tag(Account?.none)
                        ForEach(accounts) { Text("\($0.icon) \($0.name)").tag(Optional($0)) }
                    }
                }
                Section {
                    Picker("Repeats", selection: $frequency) {
                        ForEach(Frequency.allCases) { Text($0.label).tag($0) }
                    }
                    DatePicker("Next date", selection: $nextDate, displayedComponents: .date)
                    if rule != nil { Toggle("Active", isOn: $isActive) }
                } footer: {
                    Text("On each date gastos adds it to your transactions automatically. Upcoming ones show in Coming Up and in “You can spend”.")
                }
                if let problem {
                    Section { Text(problem).foregroundStyle(Color.brand) }
                }
                if let rule {
                    Section {
                        Button("Delete", role: .destructive) {
                            context.delete(rule)
                            dismiss()
                        }
                    } footer: {
                        Text("Transactions already recorded stay.")
                    }
                }
            }
            .navigationTitle(rule == nil ? "New Recurring" : "Edit Recurring")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save", action: save) }
            }
            .onAppear(perform: populate)
        }
    }

    private func populate() {
        guard let rule else {
            account = accounts.first
            nextDate = Calendar.current.startOfDay(for: .now).addingTimeInterval(9 * 3600)
            return
        }
        name = rule.name
        type = rule.type
        amountText = rule.amount.formatted(.number.grouping(.never))
        category = rule.category
        account = rule.account
        frequency = rule.frequency
        nextDate = rule.nextDate
        isActive = rule.isActive
    }

    private func save() {
        guard let amount = parseAmount(amountText), amount > 0 else { problem = "Enter an amount"; return }
        guard let account else { problem = "Pick a wallet"; return }
        let target = rule ?? {
            let new = RecurringTransaction(name: "", amount: 0, type: type, frequency: frequency, startDate: nextDate, account: account, category: nil)
            context.insert(new)
            return new
        }()
        target.name = name.trimmingCharacters(in: .whitespaces)
        target.type = type
        target.amount = amount
        target.category = type == .expense ? category : nil
        target.account = account
        target.currency = account.currency
        target.frequency = frequency
        // The chosen date becomes the new anchor for all future occurrences.
        target.startDate = nextDate
        target.postedCount = 0
        target.isActive = isActive
        RecurringPoster.postDue(in: context)
        Haptics.success()
        dismiss()
    }
}
