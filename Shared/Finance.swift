import Foundation

// The financial rules of gastos, in one place:
// - Expense: money leaves an account and counts as spending.
// - Income: money enters an account.
// - Transfer: money moves between accounts. Never spending, never income.
// - A credit card is an account whose balance goes negative when you owe.
//   Buying with it is an expense; paying it off is a transfer.

extension Account {
    /// Current balance. Negative for a credit card means money owed.
    var balance: Decimal {
        var total = openingBalance
        for entry in entries ?? [] {
            switch entry.type {
            case .expense, .transfer: total -= entry.amount
            case .income: total += entry.amount
            }
        }
        for entry in incomingTransfers ?? [] where entry.type == .transfer {
            total += entry.amount
        }
        return total
    }

    /// Sets the balance the user sees today by adjusting the opening balance.
    func setCurrentBalance(_ value: Decimal) {
        openingBalance += value - balance
    }
}

extension Entry {
    /// Signed amount as seen from `account` (the source account for transfers).
    var signedAmount: Decimal {
        switch type {
        case .expense: -amount
        case .income: amount
        case .transfer: 0
        }
    }
}

extension RecurringTransaction {
    func occurrence(_ n: Int, calendar: Calendar = .current) -> Date {
        // Computed from the start date so "31st monthly" doesn't drift to the 28th forever.
        calendar.date(byAdding: frequency.component, value: n, to: startDate) ?? startDate
    }

    var nextDate: Date { occurrence(postedCount) }

    /// Future occurrences up to and including `end`, capped to keep a daily rule cheap.
    func upcomingDates(through end: Date, calendar: Calendar = .current) -> [Date] {
        var dates: [Date] = []
        var n = postedCount
        while dates.count < 400 {
            let date = occurrence(n, calendar: calendar)
            guard date <= end else { break }
            dates.append(date)
            n += 1
        }
        return dates
    }
}

enum Finance {
    /// Net of every active account in `currency`. Credit card debt reduces it.
    static func totalMoney(_ accounts: [Account], currency: String) -> Decimal {
        accounts
            .filter { $0.isActive && $0.currency == currency }
            .reduce(0) { $0 + $1.balance }
    }

    static func entries(_ entries: [Entry], _ type: EntryType, in interval: DateInterval, currency: String) -> [Entry] {
        entries.filter {
            $0.type == type && $0.currency == currency && interval.containsHalfOpen($0.date)
        }
    }

    static func total(_ entries: [Entry], _ type: EntryType, in interval: DateInterval, currency: String) -> Decimal {
        self.entries(entries, type, in: interval, currency: currency).reduce(0) { $0 + $1.amount }
    }

    /// Spending per category, largest first. `nil` means uncategorized.
    static func spendingByCategory(_ entries: [Entry], in interval: DateInterval, currency: String) -> [(category: Category?, amount: Decimal)] {
        let expenses = self.entries(entries, .expense, in: interval, currency: currency)
        return Dictionary(grouping: expenses, by: \.category)
            .map { (category: $0.key, amount: $0.value.reduce(0) { $0 + $1.amount }) }
            .sorted { $0.amount > $1.amount }
    }

    /// Spending per wallet/card, largest first.
    static func spendingByAccount(_ entries: [Entry], in interval: DateInterval, currency: String) -> [(account: Account?, amount: Decimal)] {
        let expenses = self.entries(entries, .expense, in: interval, currency: currency)
        return Dictionary(grouping: expenses, by: \.account)
            .map { (account: $0.key, amount: $0.value.reduce(0) { $0 + $1.amount }) }
            .sorted { $0.amount > $1.amount }
    }

    /// Spending bucketed by `unit` (day/week/month) across `interval`, including empty buckets.
    static func spendingSeries(_ entries: [Entry], in interval: DateInterval, unit: Calendar.Component, currency: String, calendar: Calendar = .current) -> [(date: Date, amount: Decimal)] {
        let expenses = self.entries(entries, .expense, in: interval, currency: currency)
        let grouped = Dictionary(grouping: expenses) { calendar.dateInterval(of: unit, for: $0.date)?.start ?? $0.date }
        var result: [(Date, Decimal)] = []
        var cursor = calendar.dateInterval(of: unit, for: interval.start)?.start ?? interval.start
        while cursor < interval.end {
            result.append((cursor, grouped[cursor]?.reduce(0) { $0 + $1.amount } ?? 0))
            guard let next = calendar.date(byAdding: unit, value: 1, to: cursor) else { break }
            cursor = next
        }
        return result
    }

    /// Relative change, e.g. 0.08 for +8%. Nil when there is nothing to compare against.
    static func change(current: Decimal, previous: Decimal) -> Double? {
        guard previous > 0 else { return nil }
        return NSDecimalNumber(decimal: (current - previous) / previous).doubleValue
    }

    /// Sum of recurring expenses due from `now` through `end`.
    static func upcomingExpenses(_ recurring: [RecurringTransaction], through end: Date, currency: String) -> Decimal {
        recurring
            .filter { $0.isActive && $0.type == .expense && $0.currency == currency }
            .reduce(0) { $0 + $1.amount * Decimal($1.upcomingDates(through: end).count) }
    }

    struct SafeToSpend: Equatable {
        var available: Decimal
        var upcoming: Decimal
        var daysLeft: Int
        var perDay: Decimal
        /// Payday (next recurring income) or the start of next month.
        var until: Date
        var untilPayday: Bool
    }

    /// Money is spread until the next recurring income (payday), or to the end of the month when
    /// there is none. Upcoming recurring expenses before then are set aside first.
    static func safeToSpend(accounts: [Account], recurring: [RecurringTransaction], currency: String, today: Date = .now, calendar: Calendar = .current) -> SafeToSpend {
        let monthEnd = calendar.dateInterval(of: .month, for: today)!.end
        let payday = recurring
            .filter { $0.isActive && $0.type == .income && $0.currency == currency && $0.nextDate > today }
            .map { calendar.startOfDay(for: $0.nextDate) }
            .filter { $0 > calendar.startOfDay(for: today) }
            .min()
        let end = payday ?? monthEnd
        return safeToSpend(
            available: totalMoney(accounts, currency: currency),
            upcoming: upcomingExpenses(recurring, through: end.addingTimeInterval(-1), currency: currency),
            today: today,
            until: end,
            untilPayday: payday != nil,
            calendar: calendar
        )
    }

    /// (available − upcoming) spread over the days from today until `until` (exclusive). Never negative.
    static func safeToSpend(available: Decimal, upcoming: Decimal, today: Date, until: Date, untilPayday: Bool = false, calendar: Calendar = .current) -> SafeToSpend {
        let startOfToday = calendar.startOfDay(for: today)
        let daysLeft = max(1, calendar.dateComponents([.day], from: startOfToday, to: calendar.startOfDay(for: until)).day ?? 1)
        let spendable = max(0, available - upcoming)
        var perDay = spendable / Decimal(daysLeft)
        var rounded = Decimal()
        NSDecimalRound(&rounded, &perDay, 0, .down)
        return SafeToSpend(available: available, upcoming: upcoming, daysLeft: daysLeft, perDay: rounded, until: until, untilPayday: untilPayday)
    }
}

enum Period: String, CaseIterable, Identifiable {
    case week, month, quarter, year

    var id: String { rawValue }

    var label: String {
        switch self {
        case .week: "This week"
        case .month: "This month"
        case .quarter: "3 months"
        case .year: "This year"
        }
    }

    var shortLabel: String {
        switch self {
        case .week: "Week"
        case .month: "Month"
        case .quarter: "3M"
        case .year: "Year"
        }
    }

    /// Chart bucket size.
    var unit: Calendar.Component {
        switch self {
        case .week, .month: .day
        case .quarter: .weekOfYear
        case .year: .month
        }
    }

    func interval(containing date: Date = .now, calendar: Calendar = .current) -> DateInterval {
        switch self {
        case .week: return calendar.dateInterval(of: .weekOfYear, for: date)!
        case .month: return calendar.dateInterval(of: .month, for: date)!
        case .year: return calendar.dateInterval(of: .year, for: date)!
        case .quarter:
            // The current month plus the two before it.
            let month = calendar.dateInterval(of: .month, for: date)!
            let start = calendar.date(byAdding: .month, value: -2, to: month.start)!
            return DateInterval(start: start, end: month.end)
        }
    }

    func previous(_ interval: DateInterval, calendar: Calendar = .current) -> DateInterval {
        let (component, value): (Calendar.Component, Int) = switch self {
        case .week: (.weekOfYear, -1)
        case .month: (.month, -1)
        case .quarter: (.month, -3)
        case .year: (.year, -1)
        }
        let start = calendar.date(byAdding: component, value: value, to: interval.start)!
        return DateInterval(start: start, end: interval.start)
    }
}

extension DateInterval {
    /// `DateInterval.contains` includes the end instant, which would double-count midnight on the 1st.
    func containsHalfOpen(_ date: Date) -> Bool { date >= start && date < end }
}

/// Validation for a transaction before it is saved.
struct EntryDraft {
    var type: EntryType = .expense
    var amount: Decimal?
    var account: Account?
    var toAccount: Account?

    var problem: String? {
        guard let amount, amount > 0 else { return "Enter an amount" }
        guard amount < 1_000_000_000_000 else { return "That amount is too large" }
        guard let account else { return type == .income ? "Pick where it went" : "Pick a wallet" }
        if type == .transfer {
            guard let toAccount else { return "Pick where it goes" }
            if toAccount.persistentModelID == account.persistentModelID { return "Pick two different wallets" }
            if toAccount.currency != account.currency { return "Both wallets need the same currency" }
        }
        return nil
    }
}
