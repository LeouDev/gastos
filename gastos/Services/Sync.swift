import Foundation
import SwiftData
import Supabase
import AuthenticationServices
import CryptoKit
import os
import WidgetKit

/// Optional account + sync through Supabase. The on-device SwiftData store stays the source the
/// UI reads; sync pushes local changes (read from SwiftData history, so cascaded deletes are
/// included) and pulls rows changed on the server since the last pull. Last write wins.
@MainActor @Observable
final class SyncService {
    static let shared = SyncService()

    private(set) var email: String?
    private(set) var userID: UUID?
    private(set) var isSyncing = false
    private(set) var lastSynced: Date?
    private(set) var lastError: String?
    var isSignedIn: Bool { userID != nil }

    private let client = SupabaseClient(
        supabaseURL: URL(string: "https://ctdgkkyljnrkudcstncr.supabase.co")!,
        // Publishable key: safe to ship, every table is protected by row-level security.
        supabaseKey: "sb_publishable_9qii6kIKpESSUs-dn9DOeQ_8GQRoWpk",
        // Session lives in the Keychain (SDK default). A stored session counts as signed in even if
        // its access token expired; the SDK refreshes it on the next request.
        options: .init(auth: .init(emitLocalSessionAsInitialSession: true))
    )
    private var container: ModelContainer?
    private static let author = "sync"
    private let log = Logger(subsystem: "com.leoudev.gastos", category: "sync")

    func start(container: ModelContainer) {
        guard self.container == nil else { return }
        self.container = container
        Task {
            for await (event, session) in client.auth.authStateChanges {
                userID = session?.user.id
                email = session?.user.email
                if session != nil, event == .initialSession || event == .signedIn { await sync() }
            }
        }
    }

    // MARK: Account

    /// Hashed into the Apple request; the raw value goes to Supabase so a stolen token can't be replayed.
    private var nonce = ""

    func prepare(_ request: ASAuthorizationAppleIDRequest) {
        nonce = UUID().uuidString + UUID().uuidString
        request.requestedScopes = [.email]
        request.nonce = SHA256.hash(data: Data(nonce.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    func completeSignIn(_ result: Result<ASAuthorization, Error>) async {
        do {
            guard let credential = try result.get().credential as? ASAuthorizationAppleIDCredential,
                  let token = credential.identityToken.flatMap({ String(data: $0, encoding: .utf8) })
            else { throw SyncError("Apple didn't return a sign-in token.") }
            try await client.auth.signInWithIdToken(credentials: .init(provider: .apple, idToken: token, nonce: nonce))
        } catch let error as ASAuthorizationError where error.code == .canceled {
            return
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Stops syncing. Data on this iPhone stays.
    func signOut() async {
        try? await client.auth.signOut()
        forgetProgress()
    }

    /// Removes the account and everything stored on the server. Data on this iPhone stays.
    func deleteAccount() async {
        do {
            try await client.rpc("delete_my_account").execute()
            try? await client.auth.signOut()
            forgetProgress()
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func forgetProgress() {
        if let userID {
            UserDefaults.standard.removeObject(forKey: pushKey(userID))
            UserDefaults.standard.removeObject(forKey: pullKey(userID))
            UserDefaults.standard.removeObject(forKey: pushedAllKey(userID))
        }
        userID = nil
        email = nil
        lastSynced = nil
    }

    // MARK: Sync

    func sync() async {
        guard let container, let userID, !isSyncing else { return }
        isSyncing = true
        defer { isSyncing = false }
        do {
            let context = container.mainContext
            try context.save()
            try await push(context, userID: userID)
            try await pull(context, userID: userID)
            // Pulls can bring in copies made on another device before they synced.
            SyncCleanup.run(in: context)
            IconUpgrade.run(in: context)
            try context.save()
            WidgetCenter.shared.reloadAllTimelines()
            lastSynced = .now
            lastError = nil
        } catch {
            log.error("sync failed: \(error.localizedDescription)")
            lastError = error.localizedDescription
        }
    }

    private func push(_ context: ModelContext, userID: UUID) async throws {
        let stored = UserDefaults.standard.data(forKey: pushKey(userID))
            .flatMap { try? JSONDecoder().decode(DefaultHistoryToken.self, from: $0) }
        let pushedAll = UserDefaults.standard.bool(forKey: pushedAllKey(userID))

        let local = try LocalChanges.since(stored, in: context, ignoring: Self.author)
        let changed = pushedAll ? local.changed : []
        let deleted = pushedAll ? local.deleted : [:]
        // First sync for this account: send everything on this iPhone.
        let everything = !pushedAll
        func pick<T: PersistentModel>(_: T.Type) throws -> [T] {
            try context.fetch(FetchDescriptor<T>()).filter { everything || changed.contains($0.persistentModelID) }
        }

        try await upsert("accounts", try pick(Account.self).map(AccountRecord.init))
        try await upsert("categories", try pick(Category.self).map(CategoryRecord.init))
        try await upsert("recurring_transactions", try pick(RecurringTransaction.self).map(RecurringRecord.init))
        try await upsert("budgets", try pick(Budget.self).map(BudgetRecord.init))
        try await upsert("entries", try pick(Entry.self).map(EntryRecord.init))
        for (table, ids) in deleted where !ids.isEmpty {
            try await client.from(table).update(["deleted": true]).in("id", values: ids.map(\.uuidString)).execute()
        }

        if let last = local.lastToken {
            UserDefaults.standard.set(try JSONEncoder().encode(last), forKey: pushKey(userID))
        }
        UserDefaults.standard.set(true, forKey: pushedAllKey(userID))
    }

    private func upsert<Row: Encodable>(_ table: String, _ rows: [Row]) async throws {
        for batch in stride(from: 0, to: rows.count, by: 500).map({ Array(rows[$0..<min($0 + 500, rows.count)]) }) {
            try await client.from(table).upsert(batch).execute()
        }
    }

    private func pull(_ context: ModelContext, userID: UUID) async throws {
        // Overlap the window a little: a slow transaction can commit with a timestamp just
        // before the last cursor. Re-applying a row is harmless.
        let since = (UserDefaults.standard.object(forKey: pullKey(userID)) as? Date)?.addingTimeInterval(-300) ?? .distantPast
        let accounts: [AccountRecord] = try await fetch("accounts", AccountRecord.columns, since: since)
        let categories: [CategoryRecord] = try await fetch("categories", CategoryRecord.columns, since: since)
        let rules: [RecurringRecord] = try await fetch("recurring_transactions", RecurringRecord.columns, since: since)
        let budgets: [BudgetRecord] = try await fetch("budgets", BudgetRecord.columns, since: since)
        let entries: [EntryRecord] = try await fetch("entries", EntryRecord.columns, since: since)

        // Save edits made while we were waiting on the network, then apply without awaiting,
        // so nothing the user did gets labelled "sync" (which would stop it being pushed).
        try context.save()
        context.author = Self.author
        defer { context.author = nil }
        var accountsByID = try Self.index(context, Account.self)
        var categoriesByID = try Self.index(context, Category.self)
        var rulesByID = try Self.index(context, RecurringTransaction.self)
        let budgetsByID = try Self.index(context, Budget.self)
        let entriesByID = try Self.index(context, Entry.self)

        apply(accounts, into: &accountsByID, context) { $0.apply(to: $1) }
        apply(categories, into: &categoriesByID, context) { $0.apply(to: $1) }
        var budgetsMap = budgetsByID, entriesMap = entriesByID
        apply(rules, into: &rulesByID, context) { $0.apply(to: $1, accounts: accountsByID, categories: categoriesByID) }
        apply(budgets, into: &budgetsMap, context) { $0.apply(to: $1, categories: categoriesByID) }
        apply(entries, into: &entriesMap, context) { $0.apply(to: $1, accounts: accountsByID, categories: categoriesByID) }
        try context.save()

        let newest = ([accounts.map(\.updated_at), categories.map(\.updated_at), rules.map(\.updated_at),
                       budgets.map(\.updated_at), entries.map(\.updated_at)].joined().compactMap { $0 }).max()
        if let newest { UserDefaults.standard.set(newest, forKey: pullKey(userID)) }
    }

    private func fetch<Row: Decodable>(_ table: String, _ columns: String, since: Date) async throws -> [Row] {
        var rows: [Row] = []
        let page = 1000
        while true {
            let batch: [Row] = try await client.from(table)
                .select(columns)
                .gt("updated_at", value: since.ISO8601Format(.iso8601.year().month().day().time(includingFractionalSeconds: true)))
                .order("updated_at")
                .range(from: rows.count, to: rows.count + page - 1)
                .execute().value
            rows += batch
            if batch.count < page { return rows }
        }
    }

    private func apply<Row: SyncRecord, Model: PersistentModel>(_ rows: [Row], into models: inout [UUID: Model], _ context: ModelContext, _ update: (Row, Model) -> Void) where Row.Model == Model {
        for row in rows {
            if row.deleted {
                if let model = models.removeValue(forKey: row.id) { context.delete(model) }
                continue
            }
            let model = models[row.id] ?? {
                let new = Row.make(row.id)
                context.insert(new)
                return new
            }()
            update(row, model)
            models[row.id] = model
        }
    }

    private static func index<T: PersistentModel & Identified>(_ context: ModelContext, _: T.Type) throws -> [UUID: T] {
        Dictionary(try context.fetch(FetchDescriptor<T>()).map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    private func pushKey(_ user: UUID) -> String { "sync.pushToken.\(user.uuidString)" }
    private func pullKey(_ user: UUID) -> String { "sync.pullCursor.\(user.uuidString)" }
    private func pushedAllKey(_ user: UUID) -> String { "sync.pushedAll.\(user.uuidString)" }
}

/// What changed locally since a history token, read from SwiftData history. Transactions written
/// by `ignoring` (the sync itself) are skipped so pulled rows aren't pushed straight back.
struct LocalChanges {
    var changed = Set<PersistentIdentifier>()
    /// Table name → ids, including rows removed by cascade.
    var deleted: [String: [UUID]] = [:]
    var lastToken: DefaultHistoryToken?

    static func since(_ token: DefaultHistoryToken?, in context: ModelContext, ignoring author: String) throws -> LocalChanges {
        var descriptor = HistoryDescriptor<DefaultHistoryTransaction>()
        if let token { descriptor.predicate = #Predicate { $0.token > token } }
        let history = try context.fetchHistory(descriptor)
        var result = LocalChanges(lastToken: history.last?.token)
        for transaction in history where transaction.author != author {
            for change in transaction.changes {
                switch change {
                case .insert(let insert): result.changed.insert(insert.changedPersistentIdentifier)
                case .update(let update): result.changed.insert(update.changedPersistentIdentifier)
                case .delete(let delete):
                    if let (table, id) = tombstone(delete) { result.deleted[table, default: []].append(id) }
                @unknown default: break
                }
            }
        }
        return result
    }

    private static func tombstone(_ delete: any HistoryDelete) -> (String, UUID)? {
        if let d = delete as? DefaultHistoryDelete<Account>, let id = d.tombstone[\.id] as? UUID { return ("accounts", id) }
        if let d = delete as? DefaultHistoryDelete<Category>, let id = d.tombstone[\.id] as? UUID { return ("categories", id) }
        if let d = delete as? DefaultHistoryDelete<Entry>, let id = d.tombstone[\.id] as? UUID { return ("entries", id) }
        if let d = delete as? DefaultHistoryDelete<Budget>, let id = d.tombstone[\.id] as? UUID { return ("budgets", id) }
        if let d = delete as? DefaultHistoryDelete<RecurringTransaction>, let id = d.tombstone[\.id] as? UUID { return ("recurring_transactions", id) }
        return nil
    }

}

struct SyncError: LocalizedError {
    let errorDescription: String?
    init(_ message: String) { errorDescription = message }
}

protocol Identified { var id: UUID { get } }
extension Account: Identified {}
extension Category: Identified {}
extension Entry: Identified {}
extension Budget: Identified {}
extension RecurringTransaction: Identified {}

// MARK: - Wire records
// Field names match the Postgres columns. Money travels as text so no Double ever touches it.

protocol SyncRecord: Codable {
    associatedtype Model: PersistentModel
    var id: UUID { get }
    var deleted: Bool { get }
    static func make(_ id: UUID) -> Model
}

private func money(_ text: String) -> Decimal { Decimal(string: text) ?? 0 }

struct AccountRecord: SyncRecord {
    static let columns = "id,name,type,opening_balance::text,currency,icon,color_hex,is_active,sort_order,card_skin,card_emblem,created_at,updated_at,deleted"
    var id: UUID, name: String, type: String, opening_balance: String, currency: String, icon: String
    var color_hex: String, is_active: Bool, sort_order: Int, card_skin: String, card_emblem: String, created_at: Date, deleted = false
    var updated_at: Date?

    init(_ a: Account) {
        (id, name, type, opening_balance, currency, icon) = (a.id, a.name, a.typeRaw, "\(a.openingBalance)", a.currency, a.icon)
        (color_hex, is_active, sort_order, created_at) = (a.colorHex, a.isActive, a.sortOrder, a.createdAt)
        (card_skin, card_emblem) = (a.cardSkin, a.cardEmblem)
    }

    static func make(_ id: UUID) -> Account {
        let account = Account(name: "", type: .cash, currency: "PHP")
        account.id = id
        return account
    }

    func apply(to a: Account) {
        (a.name, a.typeRaw, a.openingBalance, a.currency, a.icon) = (name, type, money(opening_balance), currency, icon)
        (a.colorHex, a.isActive, a.sortOrder, a.createdAt) = (color_hex, is_active, sort_order, created_at)
        // A photo skin can't show without the photo, which never leaves the device it was picked on.
        a.cardSkin = card_skin == "photo" && a.cardPhoto == nil ? "" : card_skin
        a.cardEmblem = card_emblem
    }
}

struct CategoryRecord: SyncRecord {
    static let columns = "id,name,icon,color_hex,is_default,sort_order,updated_at,deleted"
    var id: UUID, name: String, icon: String, color_hex: String, is_default: Bool, sort_order: Int, deleted = false
    var updated_at: Date?

    init(_ c: Category) {
        (id, name, icon, color_hex, is_default, sort_order) = (c.id, c.name, c.icon, c.colorHex, c.isDefault, c.sortOrder)
    }

    static func make(_ id: UUID) -> Category {
        let category = Category(name: "", icon: "", colorHex: "")
        category.id = id
        return category
    }

    func apply(to c: Category) {
        (c.name, c.icon, c.colorHex, c.isDefault, c.sortOrder) = (name, icon, color_hex, is_default, sort_order)
    }
}

struct EntryRecord: SyncRecord {
    static let columns = "id,type,amount::text,currency,date,note,account_id,to_account_id,category_id,recurring_id,created_at,updated_at,deleted"
    var id: UUID, type: String, amount: String, currency: String, date: Date, note: String
    var account_id: UUID?, to_account_id: UUID?, category_id: UUID?, recurring_id: UUID?
    var created_at: Date, deleted = false
    var updated_at: Date?

    init(_ e: Entry) {
        (id, type, amount, currency, date, note) = (e.id, e.typeRaw, "\(e.amount)", e.currency, e.date, e.note)
        (account_id, to_account_id, category_id, recurring_id, created_at) = (e.account?.id, e.toAccount?.id, e.category?.id, e.recurringID, e.createdAt)
    }

    static func make(_ id: UUID) -> Entry {
        let entry = Entry(type: .expense, amount: 0, account: nil)
        entry.id = id
        return entry
    }

    func apply(to e: Entry, accounts: [UUID: Account], categories: [UUID: Category]) {
        (e.typeRaw, e.amount, e.currency, e.date, e.note) = (type, money(amount), currency, date, note)
        e.account = account_id.flatMap { accounts[$0] }
        e.toAccount = to_account_id.flatMap { accounts[$0] }
        e.category = category_id.flatMap { categories[$0] }
        (e.recurringID, e.createdAt) = (recurring_id, created_at)
    }
}

struct BudgetRecord: SyncRecord {
    static let columns = "id,amount::text,period,category_id,updated_at,deleted"
    var id: UUID, amount: String, period: String, category_id: UUID?, deleted = false
    var updated_at: Date?

    init(_ b: Budget) {
        (id, amount, period, category_id) = (b.id, "\(b.amount)", b.period, b.category?.id)
    }

    static func make(_ id: UUID) -> Budget {
        let budget = Budget(amount: 0, category: nil)
        budget.id = id
        return budget
    }

    func apply(to b: Budget, categories: [UUID: Category]) {
        (b.amount, b.period) = (money(amount), period)
        b.category = category_id.flatMap { categories[$0] }
    }
}

struct RecurringRecord: SyncRecord {
    static let columns = "id,name,amount::text,type,currency,frequency,start_date,posted_count,is_active,account_id,category_id,created_at,updated_at,deleted"
    var id: UUID, name: String, amount: String, type: String, currency: String, frequency: String
    var start_date: Date, posted_count: Int, is_active: Bool, account_id: UUID?, category_id: UUID?
    var created_at: Date, deleted = false
    var updated_at: Date?

    init(_ r: RecurringTransaction) {
        (id, name, amount, type, currency, frequency) = (r.id, r.name, "\(r.amount)", r.typeRaw, r.currency, r.frequencyRaw)
        (start_date, posted_count, is_active) = (r.startDate, r.postedCount, r.isActive)
        (account_id, category_id, created_at) = (r.account?.id, r.category?.id, r.createdAt)
    }

    static func make(_ id: UUID) -> RecurringTransaction {
        let rule = RecurringTransaction(name: "", amount: 0, type: .expense, frequency: .monthly, startDate: .now, account: nil, category: nil)
        rule.id = id
        return rule
    }

    func apply(to r: RecurringTransaction, accounts: [UUID: Account], categories: [UUID: Category]) {
        (r.name, r.amount, r.typeRaw, r.currency, r.frequencyRaw) = (name, money(amount), type, currency, frequency)
        (r.startDate, r.postedCount, r.isActive, r.createdAt) = (start_date, posted_count, is_active, created_at)
        r.account = account_id.flatMap { accounts[$0] }
        r.category = category_id.flatMap { categories[$0] }
    }
}
