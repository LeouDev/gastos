import SwiftUI
import SwiftData

/// Apple Wallet–style stack: each card shows its top edge; tap one to open it.
/// Pulling down spreads the cards apart like Apple Wallet.
struct WalletsView: View {
    @Query(sort: [SortDescriptor(\Account.sortOrder), SortDescriptor(\Account.createdAt)]) private var accounts: [Account]
    @Query(sort: [SortDescriptor(\Pass.sortOrder), SortDescriptor(\Pass.createdAt)]) private var passes: [Pass]
    @AppStorage(SettingsKey.currency) private var currency = "PHP"
    @State private var adding = false
    @State private var addingPass = false
    @State private var showHidden = false
    /// How far the list is pulled down past the top; spreads the cards.
    @State private var pull: CGFloat = 0
    @Namespace private var cards

    /// How much of each card peeks out above the next.
    private let peek: CGFloat = 62
    /// Extra gap per card for each point pulled.
    private let stretch: CGFloat = 0.22

    var body: some View {
        let active = accounts.filter(\.isActive)
        let hidden = accounts.filter { !$0.isActive }
        let walletSpread = CGFloat(max(active.count - 1, 0)) * pull * stretch
        NavigationStack {
            ScrollView {
                if accounts.isEmpty {
                    EmptyStateView(
                        title: "Your money starts here.",
                        message: "Add your first wallet to start tracking where your money goes.",
                        buttonTitle: "Add Wallet"
                    ) { adding = true }
                    .padding(.top, 60)
                } else {
                    VStack(alignment: .leading, spacing: 20) {
                        HStack {
                            Text("Total across wallets").foregroundStyle(Color.muted)
                            Spacer()
                            Text(Finance.totalMoney(accounts, currency: currency).money(currency))
                                .fontWeight(.semibold).foregroundStyle(Color.ink).monospacedDigit()
                        }
                        .font(.subheadline)
                        .accessibilityElement(children: .combine)

                        stack(active.map(StackItem.wallet))

                        VStack(alignment: .leading, spacing: 20) {
                            if !hidden.isEmpty {
                                Button { withAnimation(.snappy) { showHidden.toggle() } } label: {
                                    HStack {
                                        Image(systemName: "eye.slash")
                                        Text("\(hidden.count) hidden \(hidden.count == 1 ? "wallet" : "wallets")")
                                        Spacer()
                                        Text(showHidden ? "Hide" : "Show").foregroundStyle(Color.muted)
                                    }
                                    .font(.subheadline)
                                    .foregroundStyle(Color.ink)
                                    .padding(.horizontal, 16)
                                    .frame(minHeight: 50)
                                    .contentShape(.rect)
                                }
                                .buttonStyle(.plain)
                                .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 20))

                                if showHidden { stack(hidden.map(StackItem.wallet)).opacity(0.7) }
                            }

                            HStack {
                                Text("Cards & passes").font(.title3.weight(.bold)).foregroundStyle(Color.ink)
                                Spacer()
                                Button("Add", systemImage: "plus") { addingPass = true }
                                    .font(.subheadline.weight(.semibold))
                                    .buttonStyle(.glass)
                            }
                            .padding(.top, 8)
                            if passes.isEmpty {
                                Button { addingPass = true } label: {
                                    VStack(spacing: 8) {
                                        Image(systemName: "qrcode.viewfinder").font(.title)
                                        Text("Add a loyalty card, membership, ticket or ID").font(.subheadline.weight(.medium))
                                        Text("Scan its QR code or barcode and it's ready at the counter.")
                                            .font(.footnote).foregroundStyle(Color.muted)
                                    }
                                    .multilineTextAlignment(.center)
                                    .foregroundStyle(Color.ink)
                                    .frame(maxWidth: .infinity, minHeight: 150)
                                    .padding(.horizontal, 20)
                                    .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous)
                                        .strokeBorder(Color.muted.opacity(0.5), style: StrokeStyle(lineWidth: 1.5, dash: [6, 5])))
                                    .contentShape(.rect)
                                }
                                .buttonStyle(.plain)
                            } else {
                                stack(passes.map(StackItem.pass))
                            }
                        }
                        // Content below the wallet stack moves with it as the cards spread.
                        .offset(y: walletSpread)
                    }
                    .padding(20)
                }
            }
            .onScrollGeometryChange(for: CGFloat.self) { geometry in
                -(geometry.contentOffset.y + geometry.contentInsets.top)
            } action: { _, overscroll in
                pull = max(0, overscroll)
            }
            .canvasBackground()
            .navigationTitle("Wallets")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Add Wallet", systemImage: "wallet.bifold") { adding = true }
                        Button("Add Card or Pass", systemImage: "qrcode") { addingPass = true }
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Add")
                }
            }
            .navigationDestination(for: Account.self) { account in
                WalletDetailView(account: account, pile: pile(excluding: account.id))
                    .navigationTransition(.zoom(sourceID: account.id, in: cards))
            }
            .navigationDestination(for: Pass.self) { pass in
                PassDetailView(pass: pass, pile: pile(excluding: pass.id))
                    .navigationTransition(.zoom(sourceID: pass.id, in: cards))
            }
            .sheet(isPresented: $adding) { WalletEditor(account: nil) }
            .sheet(isPresented: $addingPass) { PassEditor() }
        }
    }

    private enum StackItem: Identifiable {
        case wallet(Account), pass(Pass)
        var id: UUID {
            switch self { case .wallet(let a): a.id; case .pass(let p): p.id }
        }
    }

    /// The other cards' looks, for the pile at the bottom of a card's screen.
    private func pile(excluding id: UUID) -> [CardSkin] {
        let wallets = accounts.filter { $0.isActive && $0.id != id }.map { CardSkin(raw: $0.cardSkin, fallbackHex: $0.colorHex) }
        let others = passes.filter { $0.id != id }.map { CardSkin(raw: $0.cardSkin, fallbackHex: $0.colorHex) }
        return Array((wallets + others).prefix(3))
    }

    private func stack(_ items: [StackItem]) -> some View {
        let gap = peek + pull * stretch
        return ZStack(alignment: .top) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                Group {
                    switch item {
                    case .wallet(let account):
                        NavigationLink(value: account) { WalletCardView(account: account) }
                    case .pass(let pass):
                        NavigationLink(value: pass) { PassCardView(pass: pass) }
                    }
                }
                .buttonStyle(.plain)
                .matchedTransitionSource(id: item.id, in: cards)
                .offset(y: CGFloat(index) * gap)
            }
        }
        .frame(height: 216 + CGFloat(max(items.count - 1, 0)) * peek, alignment: .top)
    }
}

/// Credit cards read as "Owed ₱2,000" instead of a negative balance.
struct BalanceLabel: View {
    let account: Account
    var font: Font = .body.weight(.semibold)

    var body: some View {
        let balance = account.balance
        VStack(alignment: .trailing, spacing: 0) {
            if account.type == .creditCard && balance < 0 {
                Text((-balance).money(account.currency)).font(font.monospacedDigit()).foregroundStyle(Color.ink)
                Text("owed").font(.caption).foregroundStyle(Color.muted)
            } else {
                Text(balance.money(account.currency)).font(font.monospacedDigit())
                    .foregroundStyle(balance < 0 ? Color.brand : Color.ink)
            }
        }
        .contentTransition(.numericText(value: balance.double))
    }
}

struct WalletDetailView: View {
    let account: Account
    var pile: [CardSkin] = []
    @Environment(\.addEntry) private var addEntry
    @Environment(\.dismiss) private var dismiss
    @State private var editingWallet = false
    @State private var customizing = false
    @State private var editing: Entry?

    var body: some View {
        let entries = ((account.entries ?? []) + (account.incomingTransfers ?? []))
            .sorted { $0.date > $1.date }
        let month = Period.month.interval()
        let spent = Finance.total(entries.filter { $0.account == account }, .expense, in: month, currency: account.currency)

        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                WalletCardView(account: account)

                GlassEffectContainer {
                    HStack(spacing: 10) {
                        ForEach(actions, id: \.label) { action in
                            Button(action: action.run) {
                                VStack(spacing: 6) {
                                    Image(systemName: action.icon).font(.system(size: 17, weight: .semibold))
                                    Text(action.label).font(.footnote.weight(.medium))
                                }
                                .foregroundStyle(Color.ink)
                                .frame(maxWidth: .infinity, minHeight: 66)
                                .contentShape(.rect)
                            }
                            .buttonStyle(.plain)
                            .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 20))
                        }
                    }
                }

                VStack(spacing: 0) {
                    HStack {
                        Text("Latest")
                        Spacer()
                        Text("Spent this month · \(spent.money(account.currency))")
                    }
                    .font(.footnote)
                    .foregroundStyle(Color.muted)
                    .frame(minHeight: 40)

                    if entries.isEmpty {
                        Text("No activity yet.").font(.subheadline).foregroundStyle(Color.muted)
                            .frame(maxWidth: .infinity, minHeight: 60)
                    }
                    ForEach(entries) { entry in
                        Divider()
                        Button { editing = entry } label: { EntryRow(entry: entry, perspective: account) }
                            .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
                .background(Color.card, in: .rect(cornerRadius: 22, style: .continuous))
            }
            .padding(20)
            .padding(.bottom, pile.isEmpty ? 0 : 80)
        }
        .canvasBackground()
        .navigationTitle(account.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarVisibility(pile.isEmpty ? .automatic : .hidden, for: .tabBar)
        .onAppear { if !pile.isEmpty { TabChrome.shared.hidesAccessory = true } }
        .onDisappear { TabChrome.shared.hidesAccessory = false }
        .overlay(alignment: .bottom) {
            CardPile(skins: pile) { dismiss() }
                .padding(.horizontal, 20)
                .offset(y: 30)
                .ignoresSafeArea(edges: .bottom)
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Card Style", systemImage: "paintbrush.pointed") { customizing = true }
                    Button("Edit Wallet", systemImage: "pencil") { editingWallet = true }
                } label: {
                    Text("Edit")
                }
            }
        }
        .sheet(isPresented: $editingWallet) { WalletEditor(account: account) { dismiss() } }
        .sheet(isPresented: $customizing) { CardCustomizeView(account: account) }
        .sheet(item: $editing) { AddEntryView(editing: $0) }
    }

    private struct Action { let label: String; let icon: String; let run: () -> Void }

    private var actions: [Action] {
        if account.type == .creditCard {
            return [
                Action(label: "Spend", icon: "minus") { addEntry(.expense, from: account) },
                Action(label: "Pay card", icon: "creditcard") { addEntry(.transfer, to: account) },
                Action(label: "Refund", icon: "arrow.uturn.backward") { addEntry(.income, from: account) },
            ]
        }
        return [
            Action(label: "Pay", icon: "minus") { addEntry(.expense, from: account) },
            Action(label: "Top up", icon: "plus") { addEntry(.income, from: account) },
            Action(label: "Move", icon: "arrow.left.arrow.right") { addEntry(.transfer, from: account) },
        ]
    }
}
