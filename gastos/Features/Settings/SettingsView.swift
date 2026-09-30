import SwiftUI
import SwiftData
import AuthenticationServices

struct SettingsView: View {
    @AppStorage(SettingsKey.currency) private var currency = "PHP"
    @AppStorage(SettingsKey.appLock) private var appLock = false
    @AppStorage(SettingsKey.showSafeToSpend) private var showSafeToSpend = true
    @AppStorage(SettingsKey.appearance) private var appearance = "dark"
    @AppStorage(SettingsKey.showBalanceOnCards) private var showBalanceOnCards = true
    @State private var lockUnavailable = false
    @State private var confirmingDelete = false
    @State private var customizingHomeCard = false
    @Environment(\.colorScheme) private var colorScheme
    private var sync: SyncService { .shared }

    var body: some View {
        Form {
            Section {
                Picker("Main currency", selection: $currency) {
                    ForEach(commonCurrencies, id: \.self) { Text("\($0) \(currencySymbol($0))").tag($0) }
                }
                Toggle("Show “You can spend”", isOn: $showSafeToSpend)
            } header: {
                Text("Money")
            } footer: {
                Text("Totals use wallets in your main currency. “You can spend” is your total money, minus recurring bills still due, divided by the days until your next recurring income — or until the end of the month if you haven't set one.")
            }

            Section("Look") {
                Picker("Appearance", selection: $appearance) {
                    Text("Dark").tag("dark")
                    Text("Light").tag("light")
                    Text("Match iPhone").tag("system")
                }
                Toggle("Show balances on cards", isOn: $showBalanceOnCards)
                Button("Home card style") { customizingHomeCard = true }
            }

            Section("Organize") {
                NavigationLink { CategoriesView() } label: { Label("Categories", systemImage: "square.grid.2x2") }
                NavigationLink { BudgetsView() } label: { Label("Budgets", systemImage: "chart.pie") }
                NavigationLink { RecurringListView() } label: { Label("Recurring", systemImage: "repeat") }
            }

            Section {
                if sync.isSignedIn {
                    LabeledContent("Signed in", value: sync.email ?? "Apple ID")
                    Button {
                        Task { await sync.sync() }
                    } label: {
                        HStack {
                            Text("Sync now")
                            Spacer()
                            if sync.isSyncing {
                                ProgressView()
                            } else if let last = sync.lastSynced {
                                Text(last, format: .relative(presentation: .named)).foregroundStyle(Color.muted)
                            }
                        }
                    }
                    .disabled(sync.isSyncing)
                    Button("Sign out") { Task { await sync.signOut() } }
                    Button("Delete account", role: .destructive) { confirmingDelete = true }
                } else {
                    SignInWithAppleButton(.signIn) { request in
                        sync.prepare(request)
                    } onCompletion: { result in
                        Task { await sync.completeSignIn(result) }
                    }
                    .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
                    .frame(height: 48)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                }
                if let error = sync.lastError {
                    Text(error).font(.footnote).foregroundStyle(Color.brand)
                }
            } header: {
                Text("Sync")
            } footer: {
                Text(sync.isSignedIn
                     ? "Syncs when you open or leave gastos. Signing out or deleting your account keeps everything on this iPhone."
                     : "Optional. Sign in to back up and sync across your devices. gastos works fully without an account.")
            }

            Section {
                Toggle("Lock gastos with \(AppLock.methodName)", isOn: Binding(get: { appLock }, set: setLock))
            } header: {
                Text("Privacy")
            } footer: {
                Text("Your money data lives on this iPhone. If you sign in, it's also stored in your private gastos account so it can sync. Only you can read it. No ads, no tracking, and nothing is ever sold or shared.")
            }

            Section {
                LabeledContent("Version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0")
            } footer: {
                Text("gastos — know where your money goes.")
                    .frame(maxWidth: .infinity)
                    .padding(.top, 12)
            }
        }
        .tint(.brand)
        .canvasBackground()
        .navigationTitle("Settings")
        .sheet(isPresented: $customizingHomeCard) { CardCustomizeView(account: nil) }
        .confirmationDialog("Delete your gastos account?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete Account", role: .destructive) { Task { await sync.deleteAccount() } }
        } message: {
            Text("Everything stored in your account is deleted from the server. Data on this iPhone stays.")
        }
        .alert("Set a device passcode first", isPresented: $lockUnavailable) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("gastos uses your iPhone's Face ID, Touch ID or passcode to lock.")
        }
    }

    private func setLock(_ on: Bool) {
        guard on else { appLock = false; return }
        guard AppLock.isAvailable else { lockUnavailable = true; return }
        Task {
            if await AppLock.authenticate(reason: "Turn on app lock") { appLock = true }
        }
    }
}

struct CategoriesView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Category.sortOrder) private var categories: [Category]
    @State private var editing: Category?
    @State private var adding = false
    @State private var deleting: Category?

    var body: some View {
        List {
            ForEach(categories) { category in
                Button { editing = category } label: {
                    HStack(spacing: 14) {
                        EmojiBadge(emoji: category.icon, colorHex: category.colorHex, size: 36)
                        Text(category.name).foregroundStyle(Color.ink)
                    }
                }
                .swipeActions {
                    Button("Delete", systemImage: "trash", role: .destructive) { deleting = category }
                }
            }
            .onMove(perform: move)
        }
        .canvasBackground()
        .navigationTitle("Categories")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { EditButton() }
            ToolbarItem(placement: .topBarTrailing) {
                Button("Add Category", systemImage: "plus") { adding = true }
            }
        }
        .sheet(item: $editing) { CategoryEditor(category: $0) }
        .sheet(isPresented: $adding) { CategoryEditor(category: nil) }
        .confirmationDialog("Delete \(deleting?.name ?? "")?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) {
            Button("Delete Category", role: .destructive) {
                if let deleting { context.delete(deleting) }
                deleting = nil
            }
        } message: {
            Text("Its transactions stay and show as Uncategorized.")
        }
    }

    private func move(from source: IndexSet, to destination: Int) {
        var ordered = categories
        ordered.move(fromOffsets: source, toOffset: destination)
        for (index, category) in ordered.enumerated() { category.sortOrder = index }
    }
}

struct CategoryEditor: View {
    let category: Category?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query private var all: [Category]
    @State private var name = ""
    @State private var icon = "🏷️"
    @State private var colorHex = "FF8A00"

    var body: some View {
        NavigationStack {
            Form {
                Section { TextField("Name", text: $name).font(.headline) }
                Section {
                    EmojiField(emoji: $icon, suggestions: ["🍔", "☕", "🛒", "🏠", "🚕", "⛽", "🛍️", "🎮", "💊", "📚", "✈️", "💅", "📺", "🐶", "👶", "🎁", "🙏", "📦"])
                    ColorField(hex: $colorHex)
                }
            }
            .navigationTitle(category == nil ? "New Category" : "Edit Category")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save).disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear {
                guard let category else { return }
                name = category.name
                icon = category.icon
                colorHex = category.colorHex
            }
        }
    }

    private func save() {
        let target = category ?? {
            let new = Category(name: "", icon: "", colorHex: "", sortOrder: (all.map(\.sortOrder).max() ?? 0) + 1)
            context.insert(new)
            return new
        }()
        target.name = name.trimmingCharacters(in: .whitespaces)
        target.icon = icon.isEmpty ? "🏷️" : icon
        target.colorHex = colorHex
        dismiss()
    }
}
