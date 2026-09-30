import SwiftUI
import SwiftData

enum AppGroup {
    static let id = "group.com.leoudev.gastos"
    static let defaults: UserDefaults = {
        #if DEBUG
        // UI tests start from a clean slate every launch.
        if ProcessInfo.processInfo.arguments.contains("-uiTesting") {
            let suite = "gastos.uitests"
            UserDefaults().removePersistentDomain(forName: suite)
            return UserDefaults(suiteName: suite)!
        }
        #endif
        return UserDefaults(suiteName: id) ?? .standard
    }()
}

enum SettingsKey {
    static let currency = "currency"
    static let appLock = "appLock"
    static let showSafeToSpend = "showSafeToSpend"
    static let hasOnboarded = "hasOnboarded"
    static let lastAccountID = "lastAccountID"
}

enum Store {
    static let schema = Schema([Account.self, Entry.self, Category.self, Budget.self, RecurringTransaction.self])

    /// The app's store lives in the app group so the widget can read it.
    /// `.automatic` turns on CloudKit sync only when the iCloud entitlement is present.
    static func container(cloud: Bool) throws -> ModelContainer {
        let config = ModelConfiguration(schema: schema, groupContainer: .automatic, cloudKitDatabase: cloud ? .automatic : .none)
        return try ModelContainer(for: schema, configurations: config)
    }

    static func inMemory() throws -> ModelContainer {
        try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none))
    }
}

// MARK: - Colors

extension Color {
    /// Inspired by the red on the gastos sphere.
    static let brand = Color(light: 0xD8141A, dark: 0xFF4543)
    static let canvas = Color(light: 0xFAF7F2, dark: 0x161413)
    static let card = Color(light: 0xFFFFFF, dark: 0x252220)
    static let ink = Color(light: 0x1C1A19, dark: 0xF5F2EE)
    static let muted = Color(light: 0x8A847E, dark: 0x9E9892)
    static let track = Color(light: 0xF0EBE4, dark: 0x34302D)
    static let success = Color(light: 0x1E9E5A, dark: 0x3DD68C)
    static let warning = Color(light: 0xE0960B, dark: 0xFFB940)

    init(hex: String) {
        self.init(rgb: UInt32(hex, radix: 16) ?? 0x8E8E93)
    }

    init(rgb: UInt32) {
        self.init(
            red: Double((rgb >> 16) & 0xFF) / 255,
            green: Double((rgb >> 8) & 0xFF) / 255,
            blue: Double(rgb & 0xFF) / 255
        )
    }

    init(light: UInt32, dark: UInt32) {
        self.init(UIColor { $0.userInterfaceStyle == .dark ? UIColor(Color(rgb: dark)) : UIColor(Color(rgb: light)) })
    }

    static let palette = ["D8141A", "FF8A00", "F4B400", "34A853", "10B981", "00A6A6", "0096D6", "2F6FEB", "3F51B5", "8E44AD", "E83E8C", "8E8E93"]
}

// MARK: - Money formatting

extension Decimal {
    /// "₱350", "₱1,250.50". Uses the device locale with the given currency.
    func money(_ currency: String) -> String {
        formatted(.currency(code: currency).precision(.fractionLength(0...2)))
    }

    /// Whole-number money for big headline figures.
    func moneyRounded(_ currency: String) -> String {
        formatted(.currency(code: currency).precision(.fractionLength(0)))
    }

    var isWhole: Bool { self == rounded }

    var rounded: Decimal {
        var value = self
        var result = Decimal()
        NSDecimalRound(&result, &value, 0, .plain)
        return result
    }

    var double: Double { NSDecimalNumber(decimal: self).doubleValue }
}

extension Entry {
    /// "-₱350", "+₱72,000", "₱5,000" for transfers.
    var displayAmount: String {
        switch type {
        case .expense: "-" + amount.money(currency)
        case .income: "+" + amount.money(currency)
        case .transfer: amount.money(currency)
        }
    }

    var amountColor: Color {
        switch type {
        case .expense: .ink
        case .income: .success
        case .transfer: .muted
        }
    }

    var displayIcon: String {
        switch type {
        case .expense: category?.icon ?? "📦"
        case .income: category?.icon ?? "💰"
        case .transfer: "↔️"
        }
    }

    var title: String {
        if !note.isEmpty { return note }
        switch type {
        case .expense: return category?.name ?? "Expense"
        case .income: return category?.name ?? "Income"
        case .transfer: return "Transfer"
        }
    }

    var subtitle: String {
        switch type {
        case .transfer:
            return "\(account?.name ?? "Deleted wallet") → \(toAccount?.name ?? "Deleted wallet")"
        case .expense:
            return [category?.name ?? "Uncategorized", account?.name ?? "Deleted wallet"].joined(separator: " · ")
        case .income:
            return [category?.name ?? "Income", account?.name ?? "Deleted wallet"].joined(separator: " · ")
        }
    }
}
