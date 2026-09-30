import Foundation
import LocalAuthentication
import SwiftData

enum AppLock {
    /// Face ID / Touch ID with passcode fallback. Returns true when the device has no passcode,
    /// since there is nothing to lock with and we must never lock people out of their data.
    static func authenticate(reason: String = "Unlock gastos") async -> Bool {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else { return true }
        return (try? await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)) ?? false
    }

    static var isAvailable: Bool {
        LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: nil)
    }

    static var methodName: String {
        let context = LAContext()
        _ = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        switch context.biometryType {
        case .faceID: return "Face ID"
        case .touchID: return "Touch ID"
        case .opticID: return "Optic ID"
        default: return "Passcode"
        }
    }
}

enum Seed {
    /// Default categories on first launch only, so deleting them all sticks.
    static func categoriesIfNeeded(in context: ModelContext) {
        let key = "seededCategories"
        guard !AppGroup.defaults.bool(forKey: key) else { return }
        AppGroup.defaults.set(true, forKey: key)
        guard (try? context.fetchCount(FetchDescriptor<Category>())) == 0 else { return }
        // A second device may seed its own copy; SyncCleanup merges them after sync.
        for (index, item) in Category.defaults.enumerated() {
            context.insert(Category(name: item.0, icon: item.1, colorHex: item.2, isDefault: true, sortOrder: index))
        }
    }
}

/// iCloud merges records from every device, so two devices can each seed the default categories
/// or each post the same recurring occurrence before they sync. This folds those back together.
enum SyncCleanup {
    static func run(in context: ModelContext) {
        mergeDuplicateDefaultCategories(in: context)
        removeDuplicateRecurringEntries(in: context)
    }

    static func mergeDuplicateDefaultCategories(in context: ModelContext) {
        let categories = (try? context.fetch(FetchDescriptor<Category>(sortBy: [SortDescriptor(\.sortOrder)]))) ?? []
        let groups = Dictionary(grouping: categories.filter(\.isDefault)) { $0.name.lowercased() }
        for group in groups.values where group.count > 1 {
            let keeper = group.min { ($0.sortOrder, $0.id.uuidString) < ($1.sortOrder, $1.id.uuidString) }!
            for duplicate in group where duplicate != keeper {
                for entry in duplicate.entries ?? [] { entry.category = keeper }
                for rule in duplicate.recurring ?? [] { rule.category = keeper }
                if keeper.budget == nil, let budget = duplicate.budget { budget.category = keeper }
                context.delete(duplicate)
            }
        }
    }

    static func removeDuplicateRecurringEntries(in context: ModelContext) {
        let posted = (try? context.fetch(FetchDescriptor<Entry>(predicate: #Predicate { $0.recurringID != nil }))) ?? []
        let groups = Dictionary(grouping: posted) { "\($0.recurringID!.uuidString)|\($0.date.timeIntervalSinceReferenceDate)" }
        for group in groups.values where group.count > 1 {
            // Keep the same one on every device so they converge.
            let keeper = group.min { $0.id.uuidString < $1.id.uuidString }!
            for duplicate in group where duplicate != keeper { context.delete(duplicate) }
        }
    }
}

enum RecurringPoster {
    /// Turns every due occurrence into a real entry. Safe to call often.
    @discardableResult
    static func postDue(in context: ModelContext, now: Date = .now) -> Int {
        let rules = (try? context.fetch(FetchDescriptor<RecurringTransaction>())) ?? []
        var posted = 0
        for rule in rules where rule.isActive && rule.amount > 0 {
            guard let account = rule.account else { continue }
            // Cap catch-up so a years-old daily rule can't stall launch.
            while rule.nextDate <= now && posted < 1000 {
                let entry = Entry(type: rule.type, amount: rule.amount, date: rule.nextDate, note: rule.name, account: account, category: rule.category)
                entry.recurringID = rule.id
                context.insert(entry)
                rule.postedCount += 1
                posted += 1
            }
        }
        return posted
    }
}
