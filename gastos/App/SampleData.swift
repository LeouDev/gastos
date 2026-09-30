#if DEBUG
import Foundation
import SwiftData

/// Demo data for previews and screenshots only (launch with `-sampleData`). Never used in release builds.
enum SampleData {
    static func insert(into context: ModelContext) {
        let categories = Category.defaults.enumerated().map { index, item in
            Category(name: item.0, icon: item.1, colorHex: item.2, isDefault: true, sortOrder: index)
        }
        categories.forEach(context.insert)
        func category(_ name: String) -> Category? { categories.first { $0.name == name } }

        let bpi = Account(name: "BPI Savings", type: .bank, openingBalance: 12_000, currency: "PHP", colorHex: "D8141A")
        let gcash = Account(name: "GCash", type: .eWallet, openingBalance: 3_000, currency: "PHP", colorHex: "0096D6")
        let cash = Account(name: "Cash", type: .cash, openingBalance: 2_500, currency: "PHP", colorHex: "34A853")
        let card = Account(name: "BPI Credit Card", type: .creditCard, currency: "PHP", colorHex: "8E44AD")
        (bpi.cardSkin, card.cardSkin, cash.cardSkin, gcash.cardSkin) = ("ember", "midnight", "linen", "ocean")
        (bpi.cardEmblem, card.cardEmblem, cash.cardEmblem) = ("BPI", "VISA", "₱")
        for (index, account) in [bpi, gcash, cash, card].enumerated() {
            account.sortOrder = index
            context.insert(account)
        }

        let calendar = Calendar.current
        func day(_ offset: Int) -> Date { calendar.date(byAdding: .day, value: -offset, to: .now)! }
        let items: [Entry] = [
            Entry(type: .income, amount: 72_000, date: calendar.dateInterval(of: .month, for: .now)!.start.addingTimeInterval(3600 * 10), note: "Salary", account: bpi),
            Entry(type: .expense, amount: 350, date: day(0), note: "Lunch", account: gcash, category: category("Food")),
            Entry(type: .expense, amount: 180, date: day(0), note: "Coffee", account: cash, category: category("Food")),
            Entry(type: .expense, amount: 1_250, date: day(1), note: "Groceries", account: card, category: category("Groceries")),
            Entry(type: .expense, amount: 280, date: day(1), note: "Grab", account: gcash, category: category("Transport")),
            Entry(type: .expense, amount: 12_500, date: day(3), note: "Rent", account: bpi, category: category("Bills")),
            Entry(type: .expense, amount: 4_280, date: day(4), note: "Shoes", account: card, category: category("Shopping")),
            Entry(type: .transfer, amount: 5_000, date: day(2), note: "Top up", account: bpi, toAccount: gcash),
            Entry(type: .expense, amount: 2_150, date: day(5), note: "Gas", account: bpi, category: category("Transport")),
            Entry(type: .expense, amount: 1_890, date: day(6), note: "Movies", account: gcash, category: category("Entertainment")),
            Entry(type: .expense, amount: 3_100, date: day(34), note: "Dinner out", account: card, category: category("Food")),
        ]
        items.forEach(context.insert)

        let loyalty = Pass(name: "Suki Card", kind: .loyalty)
        (loyalty.number, loyalty.holder, loyalty.code, loyalty.cardEmblem) = ("7788 1234 5566", "Juan Dela Cruz", "SUKI-7788123455660", "SUKI")
        let vaccine = Pass(name: "Vaccination Card", kind: .health)
        (vaccine.holder, vaccine.codeFormat, vaccine.code) = ("Juan Dela Cruz", .pdf417, "VAX|DELA CRUZ, JUAN|DOSE 3")
        context.insert(loyalty)
        context.insert(vaccine)

        context.insert(Budget(amount: 10_000, category: category("Food")!))
        context.insert(Budget(amount: 15_000, category: category("Bills")!))

        context.insert(RecurringTransaction(name: "Netflix", amount: 549, type: .expense, frequency: .monthly, startDate: day(-1), account: card, category: category("Subscriptions")))
        context.insert(RecurringTransaction(name: "Salary", amount: 36_000, type: .income, frequency: .monthly, startDate: day(-15), account: bpi, category: nil))
        context.insert(RecurringTransaction(name: "Internet", amount: 1_699, type: .expense, frequency: .monthly, startDate: day(-5), account: bpi, category: category("Bills")))
    }
}
#endif
