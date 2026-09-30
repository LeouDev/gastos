import Foundation
import SwiftData

// All stored properties have defaults and all relationships are optional, so the schema
// migrates lightweight. `id` survives deletion in SwiftData history so deletes can sync.

enum AccountType: String, Codable, CaseIterable, Identifiable {
    case cash, bank, debit, creditCard, eWallet, other

    var id: String { rawValue }

    var label: String {
        switch self {
        case .cash: "Cash"
        case .bank: "Bank"
        case .debit: "Debit"
        case .creditCard: "Credit Card"
        case .eWallet: "E-wallet"
        case .other: "Other"
        }
    }

    var pluralLabel: String {
        switch self {
        case .cash: "Cash"
        case .bank: "Banks"
        case .debit: "Debit"
        case .creditCard: "Credit Cards"
        case .eWallet: "E-wallets"
        case .other: "Other"
        }
    }

    var defaultIcon: String {
        switch self {
        case .cash: "💵"
        case .bank: "🏦"
        case .debit: "💳"
        case .creditCard: "💳"
        case .eWallet: "📱"
        case .other: "👛"
        }
    }
}

enum EntryType: String, Codable, CaseIterable, Identifiable {
    case expense, income, transfer

    var id: String { rawValue }

    var label: String {
        switch self {
        case .expense: "Expense"
        case .income: "Income"
        case .transfer: "Transfer"
        }
    }

    var icon: String {
        switch self {
        case .expense: "💸"
        case .income: "💰"
        case .transfer: "↔️"
        }
    }
}

enum Frequency: String, Codable, CaseIterable, Identifiable {
    case daily, weekly, monthly, yearly

    var id: String { rawValue }
    var label: String { rawValue.capitalized }

    var component: Calendar.Component {
        switch self {
        case .daily: .day
        case .weekly: .weekOfYear
        case .monthly: .month
        case .yearly: .year
        }
    }
}

@Model
final class Account {
    @Attribute(.preserveValueOnDeletion) var id: UUID = UUID()
    var name: String = ""
    var typeRaw: String = AccountType.cash.rawValue
    /// Balance before any recorded entry. Current balance is derived, see `balance`.
    var openingBalance: Decimal = 0
    var currency: String = "PHP"
    var icon: String = "💵"
    var colorHex: String = "D8141A"
    var isActive: Bool = true
    var sortOrder: Int = 0
    var createdAt: Date = Date()
    /// Card look: a texture name ("ember"), "color:RRGGBB" or "photo". Empty = the wallet's color.
    var cardSkin: String = ""
    /// Short text in the card's corner ("BPI", "G"). Empty = the name's first letter.
    var cardEmblem: String = ""
    /// Only for the "photo" skin. Stays on this device; other devices fall back to the wallet color.
    @Attribute(.externalStorage) var cardPhoto: Data?

    @Relationship(deleteRule: .cascade, inverse: \Entry.account)
    var entries: [Entry]? = []
    @Relationship(deleteRule: .nullify, inverse: \Entry.toAccount)
    var incomingTransfers: [Entry]? = []
    @Relationship(deleteRule: .cascade, inverse: \RecurringTransaction.account)
    var recurring: [RecurringTransaction]? = []

    init(name: String, type: AccountType, openingBalance: Decimal = 0, currency: String, icon: String? = nil, colorHex: String = "D8141A") {
        self.name = name
        self.typeRaw = type.rawValue
        self.openingBalance = openingBalance
        self.currency = currency
        self.icon = icon ?? type.defaultIcon
        self.colorHex = colorHex
    }

    var type: AccountType {
        get { AccountType(rawValue: typeRaw) ?? .other }
        set { typeRaw = newValue.rawValue }
    }
}

/// A single transaction: an expense, an income, or a transfer between two accounts.
@Model
final class Entry {
    @Attribute(.preserveValueOnDeletion) var id: UUID = UUID()
    var typeRaw: String = EntryType.expense.rawValue
    /// Always positive. The type decides the direction.
    var amount: Decimal = 0
    var currency: String = "PHP"
    var date: Date = Date()
    /// "What was it?" — e.g. "Lunch".
    var note: String = ""
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    /// Set when a recurring rule created this entry; used to drop duplicates made on another device.
    var recurringID: UUID?

    /// Paid with / received in / transferred from.
    var account: Account?
    /// Transfers only.
    var toAccount: Account?
    /// Expenses (and optionally income).
    var category: Category?

    init(type: EntryType, amount: Decimal, date: Date = .now, note: String = "", account: Account?, toAccount: Account? = nil, category: Category? = nil) {
        self.typeRaw = type.rawValue
        self.amount = amount
        self.date = date
        self.note = note
        self.account = account
        self.toAccount = type == .transfer ? toAccount : nil
        self.category = type == .transfer ? nil : category
        self.currency = account?.currency ?? "PHP"
    }

    var type: EntryType {
        get { EntryType(rawValue: typeRaw) ?? .expense }
        set { typeRaw = newValue.rawValue }
    }
}

@Model
final class Category {
    @Attribute(.preserveValueOnDeletion) var id: UUID = UUID()
    var name: String = ""
    var icon: String = "🏷️"
    var colorHex: String = "8E8E93"
    var isDefault: Bool = false
    var sortOrder: Int = 0

    @Relationship(deleteRule: .nullify, inverse: \Entry.category)
    var entries: [Entry]? = []
    @Relationship(deleteRule: .cascade, inverse: \Budget.category)
    var budgets: [Budget]? = []
    @Relationship(deleteRule: .nullify, inverse: \RecurringTransaction.category)
    var recurring: [RecurringTransaction]? = []

    init(name: String, icon: String, colorHex: String, isDefault: Bool = false, sortOrder: Int = 0) {
        self.name = name
        self.icon = icon
        self.colorHex = colorHex
        self.isDefault = isDefault
        self.sortOrder = sortOrder
    }

    var budget: Budget? { budgets?.first }

    static let defaults: [(String, String, String)] = [
        ("Food", "🍔", "FF8A00"),
        ("Groceries", "🛒", "34A853"),
        ("Bills", "🏠", "2F6FEB"),
        ("Transport", "🚕", "00A6A6"),
        ("Shopping", "🛍️", "E83E8C"),
        ("Entertainment", "🎮", "8E44AD"),
        ("Health", "💊", "E53935"),
        ("Education", "📚", "3F51B5"),
        ("Travel", "✈️", "0096D6"),
        ("Personal", "💅", "F4B400"),
        ("Subscriptions", "📺", "10B981"),
        ("Other", "📦", "8E8E93"),
    ]
}

@Model
final class Budget {
    @Attribute(.preserveValueOnDeletion) var id: UUID = UUID()
    var amount: Decimal = 0
    /// Only "monthly" today; stored so other periods can be added later.
    var period: String = "monthly"
    var category: Category?

    init(amount: Decimal, category: Category?) {
        self.amount = amount
        self.category = category
    }
}

@Model
final class RecurringTransaction {
    @Attribute(.preserveValueOnDeletion) var id: UUID = UUID()
    var name: String = ""
    var amount: Decimal = 0
    var typeRaw: String = EntryType.expense.rawValue
    var currency: String = "PHP"
    var frequencyRaw: String = Frequency.monthly.rawValue
    var startDate: Date = Date()
    /// How many occurrences have been turned into entries. Next date = occurrence(postedCount).
    var postedCount: Int = 0
    var isActive: Bool = true
    var createdAt: Date = Date()

    var account: Account?
    var category: Category?

    init(name: String, amount: Decimal, type: EntryType, frequency: Frequency, startDate: Date, account: Account?, category: Category?) {
        self.name = name
        self.amount = amount
        self.typeRaw = type.rawValue
        self.frequencyRaw = frequency.rawValue
        self.startDate = startDate
        self.account = account
        self.category = category
        self.currency = account?.currency ?? "PHP"
    }

    var type: EntryType {
        get { EntryType(rawValue: typeRaw) ?? .expense }
        set { typeRaw = newValue.rawValue }
    }

    var frequency: Frequency {
        get { Frequency(rawValue: frequencyRaw) ?? .monthly }
        set { frequencyRaw = newValue.rawValue }
    }
}

// MARK: - Cards & passes (non-money cards). Local to this device; never synced.

enum PassKind: String, CaseIterable, Identifiable {
    case loyalty, membership, ticket, health, id, other
    var id: String { rawValue }

    var label: String {
        switch self {
        case .loyalty: "Loyalty"
        case .membership: "Membership"
        case .ticket: "Ticket"
        case .health: "Health"
        case .id: "ID"
        case .other: "Card"
        }
    }

    /// Starting look for a new pass of this kind.
    var defaultSkin: String {
        switch self {
        case .loyalty: "ember"
        case .membership: "midnight"
        case .ticket: "jeepney"
        case .health: "mint"
        case .id: "ocean"
        case .other: "linen"
        }
    }
}

enum CodeFormat: String, CaseIterable, Identifiable {
    case qr, code128, pdf417, aztec, none
    var id: String { rawValue }

    var label: String {
        switch self {
        case .qr: "QR code"
        case .code128: "Barcode"
        case .pdf417: "PDF417"
        case .aztec: "Aztec"
        case .none: "No code"
        }
    }
}

@Model
final class Pass {
    var id: UUID = UUID()
    var name: String = ""
    var kindRaw: String = PassKind.loyalty.rawValue
    /// Printed on the card, e.g. a member number.
    var number: String = ""
    var holder: String = ""
    var notes: String = ""
    /// What the QR/barcode encodes.
    var code: String = ""
    var codeFormatRaw: String = CodeFormat.qr.rawValue
    var cardSkin: String = ""
    var cardEmblem: String = ""
    var colorHex: String = "8E8E93"
    @Attribute(.externalStorage) var cardPhoto: Data?
    /// With a photo skin: show the photo exactly as it is, no text or shading on top.
    var photoOnly: Bool = false
    var sortOrder: Int = 0
    var createdAt: Date = Date()

    init(name: String = "", kind: PassKind = .loyalty) {
        self.name = name
        self.kindRaw = kind.rawValue
        self.cardSkin = kind.defaultSkin
    }

    var kind: PassKind {
        get { PassKind(rawValue: kindRaw) ?? .other }
        set { kindRaw = newValue.rawValue }
    }

    var codeFormat: CodeFormat {
        get { CodeFormat(rawValue: codeFormatRaw) ?? .qr }
        set { codeFormatRaw = newValue.rawValue }
    }
}
