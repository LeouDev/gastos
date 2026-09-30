import SwiftUI
import SwiftData

/// "What happened?" → the right form. Also used to edit or duplicate an entry.
struct AddEntryView: View {
    var initialType: EntryType?
    var editing: Entry?

    @Environment(\.dismiss) private var dismiss
    @Query(filter: #Predicate<Account> { $0.isActive }, sort: [SortDescriptor(\Account.sortOrder), SortDescriptor(\Account.createdAt)])
    private var accounts: [Account]
    @State private var type: EntryType?
    @State private var addingWallet = false

    var body: some View {
        NavigationStack {
            Group {
                if accounts.isEmpty {
                    EmptyStateView(
                        title: "Add a wallet first",
                        message: "Tell gastos where your money lives — cash, a bank, GCash or a card.",
                        buttonTitle: "Add Wallet"
                    ) { addingWallet = true }
                } else if let type = type ?? editing?.type {
                    EntryForm(type: type, editing: editing, accounts: accounts) { dismiss() }
                } else {
                    TypeChooser { picked in withAnimation(.snappy) { type = picked } }
                }
            }
            .canvasBackground()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", systemImage: "xmark") { dismiss() }
                }
            }
        }
        .presentationDetents(type == nil && editing == nil && !accounts.isEmpty ? [.medium] : [.large])
        .presentationDragIndicator(.visible)
        .onAppear { type = initialType }
        .sheet(isPresented: $addingWallet) { WalletEditor(account: nil) }
    }
}

private struct TypeChooser: View {
    var pick: (EntryType) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("What happened?")
                .font(.title2.weight(.bold))
                .foregroundStyle(Color.ink)
                .padding(.bottom, 4)
            ForEach(EntryType.allCases) { type in
                Button { pick(type) } label: {
                    HStack(spacing: 16) {
                        Text(type.icon).font(.title)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(type.label).font(.headline).foregroundStyle(Color.ink)
                            Text(hint(type)).font(.subheadline).foregroundStyle(Color.muted)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").foregroundStyle(Color.muted)
                    }
                    .card(padding: 16)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
        }
        .padding(20)
    }

    private func hint(_ type: EntryType) -> String {
        switch type {
        case .expense: "Money you spent"
        case .income: "Money you received"
        case .transfer: "Moving money, or paying a card"
        }
    }
}

struct EntryForm: View {
    let type: EntryType
    let editing: Entry?
    let accounts: [Account]
    var onDone: () -> Void

    @Environment(\.modelContext) private var context
    @Query(sort: \Category.sortOrder) private var categories: [Category]
    @AppStorage(SettingsKey.lastAccountID) private var lastAccountID = ""
    @AppStorage(SettingsKey.currency) private var currency = "PHP"

    @State private var amountText = ""
    @State private var note = ""
    @State private var category: Category?
    @State private var account: Account?
    @State private var toAccount: Account?
    @State private var date = Date.now
    @State private var problem: String?
    @FocusState private var amountFocused: Bool
    @ScaledMetric(relativeTo: .largeTitle) private var amountSize: CGFloat = 56

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                amountField

                if type == .expense {
                    field("Category") {
                        // Two rows that scroll together, so every category is one tap away.
                        let half = (categories.count + 1) / 2
                        ScrollView(.horizontal, showsIndicators: false) {
                            VStack(alignment: .leading, spacing: 8) {
                                categoryRow(categories.prefix(half))
                                categoryRow(categories.dropFirst(half))
                            }
                        }
                        .scrollClipDisabled()
                    }
                }

                field(type == .expense ? "Paid with" : type == .income ? "Received in" : "From") {
                    accountPicker(selection: $account, excluding: nil)
                }

                if type == .transfer {
                    field("To") {
                        accountPicker(selection: $toAccount, excluding: account)
                    }
                }

                field(type == .transfer ? "Note" : "What was it?") {
                    TextField(placeholder, text: $note)
                        .font(.body)
                        .padding(.horizontal, 16)
                        .frame(minHeight: 48)
                        .background(Color.card, in: .rect(cornerRadius: 14, style: .continuous))
                        .submitLabel(.done)
                }

                DatePicker("Date", selection: $date, displayedComponents: .date)
                    .font(.headline)
                    .foregroundStyle(Color.ink)
            }
            .padding(20)
        }
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 8) {
                if let problem {
                    Text(problem).font(.footnote.weight(.semibold)).foregroundStyle(Color.brand)
                }
                Button(buttonTitle, action: save)
                    .buttonStyle(PrimaryButtonStyle())
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(Color.canvas.opacity(0.95))
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: populate)
    }

    // MARK: Pieces

    private var amountField: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(currencySymbol(account?.currency ?? currency))
                .font(.system(size: amountSize * 0.7, weight: .bold, design: .rounded))
                .foregroundStyle(Color.muted)
            TextField("0", text: $amountText)
                .font(.system(size: amountSize, weight: .bold, design: .rounded))
                .foregroundStyle(Color.ink)
                .keyboardType(.decimalPad)
                .focused($amountFocused)
                .minimumScaleFactor(0.5)
                .accessibilityLabel("Amount")
        }
        .padding(.top, 8)
    }

    private func field(_ label: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(label).font(.headline).foregroundStyle(Color.ink)
            content()
        }
    }

    private func categoryRow(_ items: ArraySlice<Category>) -> some View {
        HStack(spacing: 8) {
            ForEach(items) { item in
                Chip(icon: item.icon, title: item.name, selected: item == category) {
                    category = item == category ? nil : item
                    amountFocused = false
                }
            }
        }
    }

    private func accountPicker(selection: Binding<Account?>, excluding: Account?) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(accounts.filter { $0 != excluding }) { item in
                    Chip(icon: item.icon, title: item.name, selected: item == selection.wrappedValue) {
                        selection.wrappedValue = item
                        amountFocused = false
                    }
                }
            }
        }
        .scrollClipDisabled()
    }

    private var title: String {
        if editing != nil { return "Edit \(type.label)" }
        return type == .transfer ? "Transfer" : "Add \(type.label)"
    }

    private var buttonTitle: String {
        if editing != nil { return "Save" }
        return type == .transfer ? "Transfer" : "Add \(type.label)"
    }

    private var placeholder: String {
        switch type {
        case .expense: "Lunch, Grab, groceries…"
        case .income: "Salary, freelance…"
        case .transfer: "Card payment, top up…"
        }
    }

    // MARK: Actions

    private func populate() {
        if let editing {
            amountText = editing.amount.formatted(.number.grouping(.never))
            note = editing.note
            category = editing.category
            account = editing.account
            toAccount = editing.toAccount
            date = editing.date
        } else {
            account = accounts.first { $0.id.uuidString == lastAccountID } ?? accounts.first
            amountFocused = true
        }
    }

    private func save() {
        let amount = parseAmount(amountText)
        let draft = EntryDraft(type: type, amount: amount, account: account, toAccount: toAccount)
        if let issue = draft.problem {
            withAnimation { problem = issue }
            Haptics.warning()
            return
        }
        guard let amount, let account else { return }

        let entry = editing ?? {
            let new = Entry(type: type, amount: amount, account: account)
            context.insert(new)
            return new
        }()
        entry.type = type
        entry.amount = amount
        entry.note = note.trimmingCharacters(in: .whitespacesAndNewlines)
        entry.account = account
        entry.toAccount = type == .transfer ? toAccount : nil
        entry.category = type == .transfer ? nil : category
        entry.currency = account.currency
        entry.date = date
        entry.updatedAt = .now

        lastAccountID = account.id.uuidString
        Haptics.success()
        onDone()
    }
}
