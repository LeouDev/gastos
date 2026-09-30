import Foundation
import SwiftData
import Testing
@testable import gastos

@MainActor
/// Guards lightweight migration: a store from the previous schema must open with the current one.
struct MigrationTests {
    @Test func addingPassToAnExistingStoreMigrates() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "probe-\(UUID().uuidString).store")
        let old = Schema([Account.self, Entry.self, gastos.Category.self, Budget.self, RecurringTransaction.self])
        do {
            let container = try ModelContainer(for: old, configurations: ModelConfiguration(schema: old, url: url, cloudKitDatabase: .none))
            container.mainContext.insert(Account(name: "BPI", type: .bank, currency: "PHP"))
            try container.mainContext.save()
        }
        let container = try ModelContainer(for: Store.schema, configurations: ModelConfiguration(schema: Store.schema, url: url, cloudKitDatabase: .none))
        #expect(try container.mainContext.fetchCount(FetchDescriptor<Account>()) == 1)
    }
}
