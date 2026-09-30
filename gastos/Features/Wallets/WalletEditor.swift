import SwiftUI
import SwiftData

struct WalletEditor: View {
    let account: Account?
    var onDelete: () -> Void = {}

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @AppStorage(SettingsKey.currency) private var defaultCurrency = "PHP"
    @Query private var allAccounts: [Account]

    @State private var name = ""
    @State private var type = AccountType.eWallet
    @State private var icon = AccountType.eWallet.defaultIcon
    @State private var colorHex = "2F6FEB"
    @State private var currency = "PHP"
    @State private var balanceText = ""
    @State private var isActive = true
    @State private var confirmingDelete = false

    private var isCard: Bool { type == .creditCard }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name, e.g. GCash or BPI Savings", text: $name)
                        .font(.headline)
                    Picker("Type", selection: $type) {
                        ForEach(AccountType.allCases) { Text($0.label).tag($0) }
                    }
                    .onChange(of: type) { old, new in
                        if icon == old.defaultIcon { icon = new.defaultIcon }
                    }
                }

                Section {
                    HStack {
                        Text(isCard ? "Amount owed" : "Current balance")
                        Spacer()
                        TextField("0", text: $balanceText)
                            .keyboardType(.numbersAndPunctuation)
                            .multilineTextAlignment(.trailing)
                            .font(.body.monospacedDigit())
                    }
                    Picker("Currency", selection: $currency) {
                        ForEach(currencies, id: \.self) { Text("\($0) \(currencySymbol($0))").tag($0) }
                    }
                    // Existing transactions were recorded in the old currency.
                    .disabled(!(account?.entries?.isEmpty ?? true))
                } footer: {
                    Text(isCard
                         ? "Card purchases count as spending. Paying the card is a transfer, so it's never counted twice."
                         : "Changing this later adjusts the balance without touching your transactions.")
                }

                Section("Look") {
                    IconField(icon: $icon, colorHex: colorHex)
                    ColorField(hex: $colorHex)
                }

                if account != nil {
                    Section {
                        Toggle("Include in total money", isOn: $isActive)
                    } footer: {
                        Text("Turn off to hide an old wallet without deleting its history.")
                    }
                    Section {
                        Button("Delete Wallet", role: .destructive) { confirmingDelete = true }
                    }
                }
            }
            .navigationTitle(account == nil ? "New Wallet" : "Edit Wallet")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .confirmationDialog("Delete \(account?.name ?? "wallet")?", isPresented: $confirmingDelete, titleVisibility: .visible) {
                Button("Delete Wallet and Its Transactions", role: .destructive, action: delete)
            } message: {
                Text("\(account?.entries?.count ?? 0) transactions paid from this wallet will be deleted too. To keep them, turn off “Include in total money” instead.")
            }
            .onAppear(perform: populate)
        }
    }

    private var currencies: [String] {
        commonCurrencies.contains(currency) ? commonCurrencies : [currency] + commonCurrencies
    }

    private func populate() {
        guard let account else {
            currency = defaultCurrency
            return
        }
        name = account.name
        type = account.type
        icon = account.icon
        colorHex = account.colorHex
        currency = account.currency
        isActive = account.isActive
        let balance = account.type == .creditCard ? -account.balance : account.balance
        balanceText = balance == 0 ? "" : balance.formatted(.number)
    }

    private func save() {
        let entered = parseAmount(balanceText) ?? 0
        let balance = isCard ? -entered : entered
        let trimmed = name.trimmingCharacters(in: .whitespaces)

        if let account {
            account.name = trimmed
            account.type = type
            account.icon = icon.isEmpty ? type.defaultIcon : icon
            account.colorHex = colorHex
            account.currency = currency
            account.isActive = isActive
            account.setCurrentBalance(balance)
        } else {
            let new = Account(name: trimmed, type: type, openingBalance: balance, currency: currency, icon: icon.isEmpty ? nil : icon, colorHex: colorHex)
            new.sortOrder = (allAccounts.map(\.sortOrder).max() ?? 0) + 1
            context.insert(new)
        }
        Haptics.success()
        dismiss()
    }

    private func delete() {
        dismiss()
        if let account {
            onDelete()
            context.delete(account)
        }
    }
}
