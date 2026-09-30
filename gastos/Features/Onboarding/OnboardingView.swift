import SwiftUI
import SwiftData

struct OnboardingView: View {
    struct Suggestion: Identifiable {
        let name: String
        let icon: String
        let type: AccountType
        let colorHex: String
        var id: String { name }
    }

    static let suggestions = [
        Suggestion(name: "Cash", icon: "banknote.fill", type: .cash, colorHex: "34A853"),
        Suggestion(name: "GCash", icon: "iphone.gen3", type: .eWallet, colorHex: "0096D6"),
        Suggestion(name: "Maya", icon: "iphone.gen3", type: .eWallet, colorHex: "10B981"),
        Suggestion(name: "BPI Savings", icon: "building.columns.fill", type: .bank, colorHex: "D8141A"),
        Suggestion(name: "BDO Savings", icon: "building.columns.fill", type: .bank, colorHex: "2F6FEB"),
        Suggestion(name: "Credit Card", icon: "creditcard.fill", type: .creditCard, colorHex: "8E44AD"),
    ]

    @Environment(\.modelContext) private var context
    @AppStorage(SettingsKey.hasOnboarded) private var hasOnboarded = false
    @AppStorage(SettingsKey.currency) private var currency = "PHP"
    @State private var page = 0
    @State private var picked: [String: String] = [:]  // name → balance text
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The roll-in plays once; state lives here so swiping back to the welcome page doesn't replay it.
    @State private var introStart: Date?
    @State private var introFinished = false
    @State private var reducedShown = false

    var body: some View {
        TimelineView(.animation(paused: introFinished)) { context in
            let t = introTime(at: context.date)
            let button = page == 0 ? IntroMotion.button(at: t) : IntroMotion.Rise()
            VStack {
                TabView(selection: $page) {
                    welcome(t: t).tag(0)
                    wallets.tag(1)
                    ready.tag(2)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))

                Button(page == 2 ? "Start" : "Continue") {
                    if page == 2 { finish() } else { withAnimation { page += 1 } }
                }
                .buttonStyle(PrimaryButtonStyle())
                .padding(.horizontal, 24)
                .padding(.bottom, 8)
                .opacity(button.opacity)
                .offset(y: button.y)
                .disabled(t < IntroMotion.interactiveAt)

            Button(page == 1 ? "Skip for now" : " ") { withAnimation { page = 2 } }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.muted)
                .disabled(page != 1)
                .padding(.bottom, 12)
            }
            .opacity(reduceMotion && !reducedShown ? 0 : 1)
            .sensoryFeedback(.impact(weight: .light), trigger: t >= IntroMotion.landing)
        }
        .background(Color.canvas.ignoresSafeArea())
        .scrollDismissesKeyboard(.interactively)
        .task { await playIntro() }
    }

    private func introTime(at date: Date) -> Double {
        guard !introFinished, !reduceMotion, let introStart else { return introStart == nil && !reduceMotion ? 0 : IntroMotion.duration }
        return date.timeIntervalSince(introStart)
    }

    private func playIntro() async {
        guard introStart == nil else { return }
        if reduceMotion {
            // No drop or roll: everything simply fades in.
            introFinished = true
            withAnimation(.easeOut(duration: 0.3)) { reducedShown = true }
            return
        }
        introStart = .now
        try? await Task.sleep(for: .seconds(IntroMotion.duration))
        introFinished = true
    }

    private func welcome(t: Double) -> some View {
        let ball = IntroMotion.ball(at: t)
        let word = IntroMotion.wordmark(at: t)
        let tag = IntroMotion.tagline(at: t)
        return VStack(spacing: 24) {
            Spacer()
            RollingSphere(ball: ball)
                .padding(.bottom, 12)
            Text("gastos")
                .font(.system(size: 48, weight: .heavy, design: .rounded))
                .foregroundStyle(Color.brand)
                .opacity(word.opacity)
                .scaleEffect(word.scale)
                .offset(y: word.y)
            Text("Know where your money goes.")
                .font(.title3.weight(.medium))
                .foregroundStyle(Color.ink)
                .opacity(tag.opacity)
                .offset(y: tag.y)
            Spacer()
        }
        .padding(24)
    }

    private var wallets: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Add your wallets")
                    .font(.largeTitle.weight(.bold))
                    .foregroundStyle(Color.ink)
                    .padding(.top, 40)
                Text("Where does your money live? Pick any — you can add others later.")
                    .foregroundStyle(Color.muted)
                ForEach(Self.suggestions) { item in
                    let selected = picked[item.name] != nil
                    VStack(alignment: .leading, spacing: 12) {
                        Button {
                            withAnimation(.snappy) { picked[item.name] = selected ? nil : "" }
                        } label: {
                            HStack(spacing: 14) {
                                IconBadge(icon: item.icon, colorHex: item.colorHex)
                                Text(item.name).font(.headline).foregroundStyle(Color.ink)
                                Spacer()
                                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                                    .font(.title2)
                                    .foregroundStyle(selected ? Color.brand : Color.track)
                            }
                            .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                        .sensoryFeedback(.selection, trigger: selected)
                        .accessibilityLabel(item.name)
                        .accessibilityAddTraits(selected ? .isSelected : [])
                        if selected {
                            HStack {
                                Text(item.type == .creditCard ? "Amount owed" : "Balance now").foregroundStyle(Color.muted)
                                Spacer()
                                Text(currencySymbol(currency)).foregroundStyle(Color.muted)
                                TextField("0", text: Binding(get: { picked[item.name] ?? "" }, set: { picked[item.name] = $0 }))
                                    .keyboardType(.decimalPad)
                                    .fixedSize()
                                    .accessibilityLabel("\(item.name) balance")
                                    .font(.body.monospacedDigit())
                            }
                        }
                    }
                    .card(padding: 16)
                }
            }
            .padding(24)
        }
    }

    private var ready: some View {
        VStack(spacing: 20) {
            Spacer()
            Text("🎉").font(.system(size: 72))
            Text("You're ready.")
                .font(.largeTitle.weight(.bold))
                .foregroundStyle(Color.ink)
            Text("Let's track your first peso.")
                .font(.title3)
                .foregroundStyle(Color.muted)
            Spacer()
        }
        .padding(24)
    }

    private func finish() {
        for (index, item) in Self.suggestions.enumerated() {
            guard let text = picked[item.name] else { continue }
            let amount = parseAmount(text) ?? 0
            let account = Account(name: item.name, type: item.type, openingBalance: item.type == .creditCard ? -amount : amount, currency: currency, icon: item.icon, colorHex: item.colorHex)
            account.sortOrder = index
            context.insert(account)
        }
        Haptics.success()
        withAnimation { hasOnboarded = true }
    }
}

/// The logo sphere at one frame of the roll-in, with its floor shadow.
private struct RollingSphere: View {
    let ball: IntroMotion.Ball
    private let size = IntroMotion.size

    var body: some View {
        let height = -ball.y
        let shadowScale = min(max(1 - height / 700, 0.35), 1)
        ZStack {
            // Contact shadow stays on the floor: follows x, never y.
            Ellipse()
                .fill(Color(rgb: 0x1C1A19).opacity(0.22))
                .frame(width: 170, height: 26)
                .blur(radius: 9)
                .scaleEffect(x: shadowScale * (1 + (ball.scaleX - 1) * 0.8), y: shadowScale)
                .opacity(0.25 + 0.75 * shadowScale * (1 - 0.55 * ball.grounded))
                .offset(x: ball.x, y: size / 2 - 1)
            LogoSphere(size: size, rotation: .degrees(ball.rotation), grounded: ball.grounded)
                .scaleEffect(x: ball.scaleX, y: ball.scaleY, anchor: .bottom)
                .offset(x: ball.x, y: ball.y)
        }
        .frame(width: size, height: size)
        .accessibilityLabel("gastos logo")
    }
}
