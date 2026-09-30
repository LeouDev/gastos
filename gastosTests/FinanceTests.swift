import Foundation
import SwiftData
import Testing
@testable import gastos

@MainActor
struct FinanceTests {
    let container: ModelContainer
    let context: ModelContext
    let calendar: Calendar

    init() throws {
        container = try Store.inMemory()
        context = container.mainContext
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Manila")!
        self.calendar = calendar
    }

    private func account(_ name: String, _ type: AccountType = .bank, _ opening: Decimal = 0, currency: String = "PHP") -> Account {
        let account = Account(name: name, type: type, openingBalance: opening, currency: currency)
        context.insert(account)
        return account
    }

    @discardableResult
    private func add(_ type: EntryType, _ amount: Decimal, from: Account?, to: Account? = nil, category: gastos.Category? = nil, date: Date = .now) -> Entry {
        let entry = Entry(type: type, amount: amount, date: date, account: from, toAccount: to, category: category)
        context.insert(entry)
        return entry
    }

    private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 12, _ min: Int = 0, _ s: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min, second: s))!
    }

    private let allTime = DateInterval(start: .distantPast, end: .distantFuture)

    // MARK: - The spec scenarios

    @Test func incomeMinusExpense() throws {
        let bpi = account("BPI")
        add(.income, 72_000, from: bpi)
        add(.expense, 2_000, from: bpi)
        try context.save()
        #expect(bpi.balance == 70_000)
    }

    @Test func transferMovesMoneyButKeepsTotal() throws {
        let bpi = account("BPI", .bank, 10_000)
        let gcash = account("GCash", .eWallet)
        add(.transfer, 2_000, from: bpi, to: gcash)
        try context.save()
        #expect(bpi.balance == 8_000)
        #expect(gcash.balance == 2_000)
        #expect(Finance.totalMoney([bpi, gcash], currency: "PHP") == 10_000)
        #expect(Finance.total([bpi, gcash].flatMap { $0.entries ?? [] }, .expense, in: allTime, currency: "PHP") == 0)
    }

    @Test func creditCardPurchaseIsSpendingButNotBankMoney() throws {
        let bpi = account("BPI", .bank, 10_000)
        let card = account("Card", .creditCard)
        let purchase = add(.expense, 2_000, from: card)
        try context.save()
        #expect(bpi.balance == 10_000)
        #expect(card.balance == -2_000)  // 2,000 owed
        #expect(Finance.total([purchase], .expense, in: allTime, currency: "PHP") == 2_000)
    }

    @Test func creditCardPaymentIsNotCountedAgain() throws {
        let bpi = account("BPI", .bank, 10_000)
        let card = account("Card", .creditCard)
        let purchase = add(.expense, 2_000, from: card)
        let payment = add(.transfer, 2_000, from: bpi, to: card)
        try context.save()
        #expect(bpi.balance == 8_000)
        #expect(card.balance == 0)
        #expect(Finance.total([purchase, payment], .expense, in: allTime, currency: "PHP") == 2_000)
        #expect(Finance.total([purchase, payment], .income, in: allTime, currency: "PHP") == 0)
        #expect(Finance.totalMoney([bpi, card], currency: "PHP") == 8_000)
    }

    // MARK: - Edge cases

    @Test func validationRejectsZeroNegativeAndMissingAmounts() {
        let bpi = account("BPI")
        #expect(EntryDraft(type: .expense, amount: 0, account: bpi).problem != nil)
        #expect(EntryDraft(type: .expense, amount: -5, account: bpi).problem != nil)
        #expect(EntryDraft(type: .expense, amount: nil, account: bpi).problem != nil)
        #expect(EntryDraft(type: .expense, amount: 5, account: nil).problem != nil)
        #expect(EntryDraft(type: .expense, amount: 5, account: bpi).problem == nil)
    }

    @Test func validationRejectsSameAccountAndCrossCurrencyTransfers() throws {
        let bpi = account("BPI")
        let usd = account("USD", .bank, 0, currency: "USD")
        let gcash = account("GCash")
        try context.save()
        #expect(EntryDraft(type: .transfer, amount: 5, account: bpi, toAccount: bpi).problem == "Pick two different wallets")
        #expect(EntryDraft(type: .transfer, amount: 5, account: bpi, toAccount: nil).problem != nil)
        #expect(EntryDraft(type: .transfer, amount: 5, account: bpi, toAccount: usd).problem != nil)
        #expect(EntryDraft(type: .transfer, amount: 5, account: bpi, toAccount: gcash).problem == nil)
    }

    @Test func deletingAWalletRemovesItsEntriesAndKeepsTheOtherSideOfTransfers() throws {
        let bpi = account("BPI", .bank, 10_000)
        let gcash = account("GCash")
        add(.expense, 500, from: bpi)
        add(.transfer, 1_000, from: bpi, to: gcash)
        try context.save()
        context.delete(bpi)
        try context.save()
        #expect(try context.fetchCount(FetchDescriptor<Entry>()) == 0)
        #expect(gcash.balance == 0)

        // Money sent *into* a deleted wallet stays gone from the source.
        let cash = account("Cash", .cash, 3_000)
        let old = account("Old")
        add(.transfer, 1_000, from: cash, to: old)
        try context.save()
        context.delete(old)
        try context.save()
        #expect(cash.balance == 2_000)
    }

    @Test func deletingACategoryKeepsItsTransactionsAsUncategorized() throws {
        let bpi = account("BPI")
        let food = gastos.Category(name: "Food", icon: "🍔", colorHex: "FF8A00")
        context.insert(food)
        context.insert(Budget(amount: 1_000, category: food))
        let entry = add(.expense, 350, from: bpi, category: food)
        try context.save()
        context.delete(food)
        try context.save()
        #expect(entry.category == nil)
        #expect(try context.fetchCount(FetchDescriptor<Budget>()) == 0)
        let rows = Finance.spendingByCategory([entry], in: allTime, currency: "PHP")
        #expect(rows.count == 1 && rows[0].category == nil && rows[0].amount == 350)
    }

    @Test func largeAmountsStayExact() throws {
        // Decimal float literals round-trip through Double, so build them from strings like the UI does.
        let bpi = account("BPI", .bank, Decimal(string: "999999999999.99")!)
        add(.expense, Decimal(string: "0.01")!, from: bpi)
        add(.income, parseAmount("0.1")!, from: bpi)
        add(.income, parseAmount("0.2")!, from: bpi)
        try context.save()
        #expect(bpi.balance == Decimal(string: "1000000000000.28"))
    }

    @Test func totalsOnlyCountTheMainCurrency() throws {
        let php = account("BPI", .bank, 1_000)
        let usd = account("Chase", .bank, 50, currency: "USD")
        let a = add(.expense, 100, from: php)
        let b = add(.expense, 20, from: usd)
        try context.save()
        #expect(Finance.totalMoney([php, usd], currency: "PHP") == 900)
        #expect(Finance.totalMoney([php, usd], currency: "USD") == 30)
        #expect(Finance.total([a, b], .expense, in: allTime, currency: "PHP") == 100)
        #expect(b.currency == "USD")
    }

    @Test func hiddenWalletsAreLeftOutOfTotalMoney() {
        let bpi = account("BPI", .bank, 1_000)
        let old = account("Old", .bank, 500)
        old.isActive = false
        #expect(Finance.totalMoney([bpi, old], currency: "PHP") == 1_000)
    }

    @Test func settingCurrentBalanceKeepsHistory() throws {
        let bpi = account("BPI", .bank, 1_000)
        add(.expense, 300, from: bpi)
        try context.save()
        bpi.setCurrentBalance(5_000)
        #expect(bpi.balance == 5_000)
        #expect(bpi.entries?.count == 1)
    }

    // MARK: - Dates

    @Test func monthBoundaryIsHalfOpen() throws {
        let bpi = account("BPI")
        let lastSecondOfSept = add(.expense, 100, from: bpi, date: date(2026, 9, 30, 23, 59, 59))
        let midnightOct = add(.expense, 200, from: bpi, date: date(2026, 10, 1, 0, 0, 0))
        let entries = [lastSecondOfSept, midnightOct]
        let september = Period.month.interval(containing: date(2026, 9, 15), calendar: calendar)
        let october = Period.month.interval(containing: date(2026, 10, 15), calendar: calendar)
        #expect(Finance.total(entries, .expense, in: september, currency: "PHP") == 100)
        #expect(Finance.total(entries, .expense, in: october, currency: "PHP") == 200)
        #expect(Period.month.previous(october, calendar: calendar) == september)
    }

    @Test func yearChangeForPreviousMonth() {
        let january = Period.month.interval(containing: date(2027, 1, 10), calendar: calendar)
        let december = Period.month.previous(january, calendar: calendar)
        #expect(december.start == date(2026, 12, 1, 0))
        #expect(december.end == january.start)
    }

    @Test func spendingSeriesIncludesEmptyDays() {
        let bpi = account("BPI")
        let entry = add(.expense, 150, from: bpi, date: date(2026, 9, 3, 9))
        let week = DateInterval(start: date(2026, 9, 1, 0), end: date(2026, 9, 8, 0))
        let series = Finance.spendingSeries([entry], in: week, unit: .day, currency: "PHP", calendar: calendar)
        #expect(series.count == 7)
        #expect(series[2].amount == 150)
        #expect(series.filter { $0.amount == 0 }.count == 6)
    }

    @Test func comparisonUsesTheSameElapsedTime() {
        let now = date(2026, 9, 10, 12)
        let september = Period.month.interval(containing: now, calendar: calendar)
        let slice = Period.month.previousToDate(september, now: now, calendar: calendar)
        #expect(slice.start == date(2026, 8, 1, 0))
        #expect(slice.end == date(2026, 8, 10, 12))
        // A finished period compares against the whole previous one.
        let august = Period.month.interval(containing: date(2026, 8, 5), calendar: calendar)
        #expect(Period.month.previousToDate(august, now: now, calendar: calendar) == Period.month.previous(august, calendar: calendar))
    }

    @Test func syncCleanupMergesDuplicateDefaultCategories() throws {
        let bpi = account("BPI")
        let foodA = gastos.Category(name: "Food", icon: "🍔", colorHex: "FF8A00", isDefault: true, sortOrder: 0)
        let foodB = gastos.Category(name: "Food", icon: "🍔", colorHex: "FF8A00", isDefault: true, sortOrder: 0)
        let mine = gastos.Category(name: "Food", icon: "🍜", colorHex: "FF8A00", isDefault: false, sortOrder: 20)
        [foodA, foodB, mine].forEach(context.insert)
        context.insert(Budget(amount: 5_000, category: foodB))
        add(.expense, 100, from: bpi, category: foodA)
        add(.expense, 200, from: bpi, category: foodB)
        try context.save()

        SyncCleanup.run(in: context)
        try context.save()

        let defaults = try context.fetch(FetchDescriptor<gastos.Category>()).filter(\.isDefault)
        #expect(defaults.count == 1)
        #expect(defaults[0].entries?.count == 2)
        #expect(defaults[0].budget?.amount == 5_000)
        #expect(try context.fetchCount(FetchDescriptor<gastos.Category>()) == 2)  // the user's own "Food" stays
    }

    @Test func syncCleanupRemovesRecurringEntriesPostedTwice() throws {
        let bpi = account("BPI", .bank, 1_000)
        let rule = RecurringTransaction(name: "Netflix", amount: 549, type: .expense, frequency: .monthly, startDate: date(2026, 9, 1), account: bpi, category: nil)
        context.insert(rule)
        for _ in 0..<2 {  // two devices, same occurrence
            let entry = add(.expense, 549, from: bpi, date: date(2026, 9, 1))
            entry.recurringID = rule.id
        }
        add(.expense, 549, from: bpi, date: date(2026, 9, 1))  // a manual one with the same amount stays
        try context.save()

        SyncCleanup.run(in: context)
        try context.save()

        #expect(try context.fetchCount(FetchDescriptor<Entry>()) == 2)
        #expect(bpi.balance == Decimal(-98))  // 1,000 − 549 − 549; spell out Decimal, #expect mistypes the literal math
    }

    @Test func percentChange() {
        #expect(Finance.change(current: 108, previous: 100) == 0.08)
        #expect(Finance.change(current: 50, previous: 0) == nil)
    }

    // MARK: - Safe to spend & recurring

    @Test func safeToSpendSpreadsMoneyOverDaysLeft() {
        // Sept 13 → 18 days left including today.
        let result = Finance.safeToSpend(available: 18_420, upcoming: 0, today: date(2026, 9, 13, 8), until: date(2026, 10, 1, 0), calendar: calendar)
        #expect(result.daysLeft == 18)
        #expect(result.perDay == 1_023)
    }

    @Test func safeToSpendSubtractsUpcomingAndNeverGoesNegative() {
        let withBills = Finance.safeToSpend(available: 10_000, upcoming: 4_000, today: date(2026, 9, 30, 20), until: date(2026, 10, 1, 0), calendar: calendar)
        #expect(withBills.daysLeft == 1)
        #expect(withBills.perDay == 6_000)
        let broke = Finance.safeToSpend(available: 1_000, upcoming: 4_000, today: date(2026, 9, 10), until: date(2026, 10, 1, 0), calendar: calendar)
        #expect(broke.perDay == 0)
    }

    @Test func safeToSpendRunsUntilPaydayWhenThereIsOne() {
        let today = date(2026, 9, 30, 9)
        let bpi = account("BPI", .bank, 15_000)
        let salary = RecurringTransaction(name: "Salary", amount: 30_000, type: .income, frequency: .monthly, startDate: date(2026, 10, 15, 9), account: bpi, category: nil)
        let rent = RecurringTransaction(name: "Rent", amount: 5_000, type: .expense, frequency: .monthly, startDate: date(2026, 10, 5, 9), account: bpi, category: nil)
        let later = RecurringTransaction(name: "Insurance", amount: 9_999, type: .expense, frequency: .monthly, startDate: date(2026, 10, 20, 9), account: bpi, category: nil)
        let result = Finance.safeToSpend(accounts: [bpi], recurring: [salary, rent, later], currency: "PHP", today: today, calendar: calendar)
        #expect(result.untilPayday)
        #expect(result.daysLeft == 15)          // Sept 30 … Oct 14
        #expect(result.upcoming == 5_000)       // insurance is after payday
        #expect(result.perDay == 666)           // 10,000 / 15, rounded down

        let noPayday = Finance.safeToSpend(accounts: [bpi], recurring: [], currency: "PHP", today: today, calendar: calendar)
        #expect(!noPayday.untilPayday && noPayday.daysLeft == 1)
    }

    @Test func monthlyRecurringDoesNotDriftAfterShortMonths() {
        let rule = RecurringTransaction(name: "Rent", amount: 1, type: .expense, frequency: .monthly, startDate: date(2026, 1, 31), account: nil, category: nil)
        #expect(calendar.component(.day, from: rule.occurrence(1, calendar: calendar)) == 28)
        #expect(calendar.component(.day, from: rule.occurrence(2, calendar: calendar)) == 31)
    }

    @Test func recurringPostsEachDueOccurrenceOnce() throws {
        let bpi = account("BPI", .bank, 10_000)
        let start = calendar.date(byAdding: .day, value: -14, to: .now)!
        let rule = RecurringTransaction(name: "Allowance", amount: 100, type: .expense, frequency: .weekly, startDate: start, account: bpi, category: nil)
        context.insert(rule)
        #expect(RecurringPoster.postDue(in: context) == 3)  // 14 days ago, 7 days ago, today
        #expect(RecurringPoster.postDue(in: context) == 0)
        try context.save()
        #expect(bpi.balance == 9_700)
        #expect(rule.nextDate > .now)
    }

    @Test func upcomingExpensesCountEveryOccurrenceBeforeTheEnd() {
        let bpi = account("BPI")
        let start = calendar.date(byAdding: .day, value: 1, to: .now)!
        let weekly = RecurringTransaction(name: "Gym", amount: 200, type: .expense, frequency: .weekly, startDate: start, account: bpi, category: nil)
        let salary = RecurringTransaction(name: "Salary", amount: 50_000, type: .income, frequency: .monthly, startDate: start, account: bpi, category: nil)
        let end = calendar.date(byAdding: .day, value: 15, to: .now)!
        #expect(Finance.upcomingExpenses([weekly, salary], through: end, currency: "PHP") == 600)
    }
}

struct IntroMotionTests {
    @Test func ballStartsOffScreenAndEndsUprightAtRest() {
        let start = IntroMotion.ball(at: 0)
        #expect(start.x == -430 && start.y == -760)
        #expect(abs(start.rotation - (-430.0 / 110 * 180 / .pi)) < 0.001)  // ≈ −224°

        let rest = IntroMotion.ball(at: IntroMotion.duration)
        #expect(rest == IntroMotion.Ball())
        #expect(rest.grounded == 1)
    }

    @Test func ballLandsThenHopsThreeTimes() {
        #expect(IntroMotion.ball(at: 0.6).y == 0)
        #expect(abs(IntroMotion.ball(at: 0.6 + 0.21).y - -105.6) < 0.001)   // hop 1 peak, 96 × 1.1
        #expect(abs(IntroMotion.ball(at: 1.02 + 0.13).y - -33) < 0.001)     // hop 2 peak
        #expect(abs(IntroMotion.ball(at: 1.28 + 0.08).y - -9.9) < 0.001)    // hop 3 peak
        #expect(IntroMotion.ball(at: 1.5).y == 0)
    }

    @Test func ballSquashesOnImpactAndOvershootsBeforeSettling() {
        let impact = IntroMotion.ball(at: 0.6 + 0.08)  // mid-squash
        #expect(abs(impact.scaleX - 1.18) < 0.001 && abs(impact.scaleY - 0.82) < 0.001)
        #expect(abs(IntroMotion.ball(at: 2.15).x - 18) < 0.001)
        #expect(IntroMotion.ball(at: 2.65).x == 0)
    }

    @Test func revealOrderAndButtonUnlock() {
        func near(_ a: IntroMotion.Rise, _ b: IntroMotion.Rise) -> Bool {
            abs(a.opacity - b.opacity) < 1e-9 && abs(a.y - b.y) < 1e-9 && abs(a.scale - b.scale) < 1e-9
        }
        #expect(IntroMotion.wordmark(at: 3.0).opacity < 1e-9)
        #expect(near(IntroMotion.wordmark(at: 3.6), IntroMotion.Rise()))
        #expect(IntroMotion.tagline(at: 3.28).opacity < 1e-9)
        #expect(IntroMotion.button(at: 3.55).opacity < 1e-9)
        #expect(near(IntroMotion.button(at: 4.15), IntroMotion.Rise()))
        #expect(abs(IntroMotion.interactiveAt - 4.15) < 1e-9)
    }
}

@MainActor
struct SyncRecordTests {
    @Test func recordsRoundTripThroughJSONWithExactMoney() throws {
        let container = try Store.inMemory()
        let context = container.mainContext
        let bpi = Account(name: "BPI", type: .bank, openingBalance: Decimal(string: "999999999999.99")!, currency: "PHP")
        let food = gastos.Category(name: "Food", icon: "🍔", colorHex: "FF8A00")
        let entry = Entry(type: .expense, amount: Decimal(string: "0.1")!, note: "Lunch", account: bpi, category: food)
        context.insert(bpi); context.insert(food); context.insert(entry)
        try context.save()

        func roundTrip<T: Codable>(_ value: T) throws -> T {
            let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
            let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(T.self, from: encoder.encode(value))
        }

        let accountCopy = AccountRecord.make(bpi.id)
        try roundTrip(AccountRecord(bpi)).apply(to: accountCopy)
        #expect(accountCopy.openingBalance == Decimal(string: "999999999999.99"))
        #expect(accountCopy.id == bpi.id && accountCopy.type == .bank)

        let categoryCopy = CategoryRecord.make(food.id)
        try roundTrip(CategoryRecord(food)).apply(to: categoryCopy)

        let entryCopy = EntryRecord.make(entry.id)
        try roundTrip(EntryRecord(entry)).apply(to: entryCopy, accounts: [bpi.id: accountCopy], categories: [food.id: categoryCopy])
        #expect(entryCopy.amount == Decimal(string: "0.1"))
        #expect(entryCopy.account === accountCopy && entryCopy.category === categoryCopy)
        #expect(entryCopy.note == "Lunch" && entryCopy.type == .expense)
    }
}

@MainActor
struct LocalChangesTests {
    /// History needs a real SQLite store, not an in-memory one.
    private func diskContainer() throws -> ModelContainer {
        let url = FileManager.default.temporaryDirectory.appending(path: "gastos-history-\(UUID().uuidString).store")
        return try ModelContainer(for: Store.schema, configurations: ModelConfiguration(schema: Store.schema, url: url, cloudKitDatabase: .none))
    }

    @Test func deletingAWalletReportsItsCascadedEntriesForSync() throws {
        let container = try diskContainer()  // must outlive its context
        let context = container.mainContext
        let bpi = Account(name: "BPI", type: .bank, currency: "PHP")
        context.insert(bpi)
        let lunch = Entry(type: .expense, amount: 350, account: bpi)
        let rent = Entry(type: .expense, amount: 12_500, account: bpi)
        context.insert(lunch); context.insert(rent)
        try context.save()
        let before = try LocalChanges.since(nil, in: context, ignoring: "sync")
        #expect(before.changed.count >= 3)

        let (walletID, entryIDs) = (bpi.id, Set([lunch.id, rent.id]))
        context.delete(bpi)
        try context.save()

        let after = try LocalChanges.since(before.lastToken, in: context, ignoring: "sync")
        #expect(after.deleted["accounts"] == [walletID])
        #expect(Set(after.deleted["entries"] ?? []) == entryIDs)
    }

    @Test func changesWrittenBySyncAreNotPushedBack() throws {
        let container = try diskContainer()  // must outlive its context
        let context = container.mainContext
        context.insert(Account(name: "Mine", type: .cash, currency: "PHP"))
        try context.save()
        let start = try LocalChanges.since(nil, in: context, ignoring: "sync")

        context.author = "sync"
        context.insert(Account(name: "From server", type: .cash, currency: "PHP"))
        try context.save()
        context.author = nil

        let next = try LocalChanges.since(start.lastToken, in: context, ignoring: "sync")
        #expect(next.changed.isEmpty)
        #expect(next.lastToken != nil)  // still advances past it
    }
}
