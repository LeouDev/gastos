import SwiftUI

// MARK: - Environment

extension EnvironmentValues {
    /// Opens the add-transaction sheet from anywhere. `nil` shows the "What happened?" chooser.
    @Entry var addEntry: (EntryType?) -> Void = { _ in }
}

// MARK: - Layout

struct CardModifier: ViewModifier {
    var padding: CGFloat = 20

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.card, in: .rect(cornerRadius: 24, style: .continuous))
            .shadow(color: .black.opacity(0.04), radius: 12, y: 4)
    }
}

extension View {
    func card(padding: CGFloat = 20) -> some View { modifier(CardModifier(padding: padding)) }

    /// Warm canvas behind scroll views and lists.
    func canvasBackground() -> some View {
        scrollContentBackground(.hidden).background(Color.canvas.ignoresSafeArea())
    }
}

struct SectionTitle<Trailing: View>: View {
    let title: String
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.title3.weight(.bold)).foregroundStyle(Color.ink)
            Spacer()
            trailing.font(.subheadline.weight(.semibold)).tint(.brand)
        }
        .accessibilityAddTraits(.isHeader)
    }
}

extension SectionTitle where Trailing == EmptyView {
    init(_ title: String) {
        self.title = title
        self.trailing = EmptyView()
    }
}

extension SectionTitle {
    init(_ title: String, @ViewBuilder trailing: () -> Trailing) {
        self.title = title
        self.trailing = trailing()
    }
}

// MARK: - Money

/// Large rounded money figure that rolls smoothly when it changes.
struct HeroAmount: View {
    let value: Decimal
    let currency: String
    var size: CGFloat = 52
    @ScaledMetric private var scale: CGFloat = 1
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Text(value.isWhole ? value.moneyRounded(currency) : value.money(currency))
            .font(.system(size: size * scale, weight: .bold, design: .rounded))
            .foregroundStyle(Color.ink)
            .minimumScaleFactor(0.5)
            .lineLimit(1)
            .contentTransition(.numericText(value: value.double))
            .animation(reduceMotion ? nil : .snappy, value: value)
    }
}

struct ProgressBar: View {
    let value: Double
    var color: Color = .brand
    var height: CGFloat = 8
    @State private var shown = 0.0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.track)
                Capsule().fill(color).frame(width: geo.size.width * min(max(shown, 0), 1))
            }
        }
        .frame(height: height)
        .onAppear { update() }
        .onChange(of: value) { update() }
        .accessibilityHidden(true)
    }

    private func update() {
        if reduceMotion { shown = value } else { withAnimation(.spring(duration: 0.6)) { shown = value } }
    }
}

struct EmojiBadge: View {
    let emoji: String
    var colorHex: String = "8E8E93"
    var size: CGFloat = 44

    var body: some View {
        Text(emoji)
            .font(.system(size: size * 0.5))
            .frame(width: size, height: size)
            .background(Color(hex: colorHex).opacity(0.15), in: .rect(cornerRadius: size * 0.32, style: .continuous))
            .accessibilityHidden(true)
    }
}

// MARK: - Controls

struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 56)
            .background(Color.brand.opacity(isEnabled ? 1 : 0.4), in: .capsule)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.snappy(duration: 0.15), value: configuration.isPressed)
    }
}

/// Big tappable pill used to pick a category or wallet.
struct Chip: View {
    let icon: String
    let title: String
    var selected: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(icon)
                Text(title).font(.subheadline.weight(.semibold)).lineLimit(1)
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 44)
            .foregroundStyle(selected ? .white : Color.ink)
            .background(selected ? Color.brand : Color.card, in: .capsule)
            .overlay(Capsule().strokeBorder(selected ? .clear : Color.track, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: selected)
        .accessibilityLabel(title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// One-emoji text field with quick suggestions.
struct EmojiField: View {
    @Binding var emoji: String
    var suggestions: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Icon")
                Spacer()
                TextField("🙂", text: $emoji)
                    .multilineTextAlignment(.trailing)
                    .font(.title)
                    .frame(width: 60)
                    .onChange(of: emoji) { _, new in
                        if new.count > 1 { emoji = String(new.suffix(1)) }
                    }
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(suggestions, id: \.self) { item in
                        Button(item) { emoji = item }
                            .font(.title2)
                            .frame(width: 44, height: 44)
                            .background(item == emoji ? Color.brand.opacity(0.15) : .clear, in: .circle)
                            .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}

struct ColorField: View {
    @Binding var hex: String

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 12) {
            ForEach(Color.palette, id: \.self) { item in
                Button { hex = item } label: {
                    Circle()
                        .fill(Color(hex: item))
                        .frame(width: 36, height: 36)
                        .overlay(Circle().strokeBorder(.white, lineWidth: item == hex ? 3 : 0).padding(3))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Color \(item)")
                .accessibilityAddTraits(item == hex ? .isSelected : [])
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Rows & states

struct EntryRow: View {
    let entry: Entry
    /// When shown inside a wallet, transfers read as in (+) or out (−) of that wallet.
    var perspective: Account?

    var body: some View {
        HStack(spacing: 14) {
            EmojiBadge(emoji: entry.displayIcon, colorHex: entry.category?.colorHex ?? "8E8E93")
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.title).font(.body.weight(.semibold)).foregroundStyle(Color.ink).lineLimit(1)
                Text(entry.subtitle).font(.subheadline).foregroundStyle(Color.muted).lineLimit(1)
            }
            Spacer(minLength: 8)
            Text(amountText)
                .font(.body.weight(.semibold).monospacedDigit())
                .foregroundStyle(entry.amountColor)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    private var amountText: String {
        guard entry.type == .transfer, let perspective else { return entry.displayAmount }
        let incoming = entry.toAccount?.persistentModelID == perspective.persistentModelID
        return (incoming ? "+" : "-") + entry.amount.money(entry.currency)
    }
}

struct EmptyStateView: View {
    let title: String
    let message: String
    var buttonTitle: String?
    var action: () -> Void = {}

    var body: some View {
        VStack(spacing: 16) {
            LogoSphere(size: 110)
            Text(title)
                .font(.title2.weight(.bold))
                .foregroundStyle(Color.ink)
                .multilineTextAlignment(.center)
            Text(message)
                .font(.body)
                .foregroundStyle(Color.muted)
                .multilineTextAlignment(.center)
            if let buttonTitle {
                Button(action: action) { Label(buttonTitle, systemImage: "plus") }
                    .buttonStyle(PrimaryButtonStyle())
                    .padding(.top, 8)
                    .frame(maxWidth: 260)
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity)
    }
}

/// The gastos sphere with a soft grounded shadow.
struct LogoSphere: View {
    var size: CGFloat

    var body: some View {
        Image("Logo")
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .shadow(color: .black.opacity(0.08), radius: size * 0.06, y: size * 0.05)
            .shadow(color: Color.brand.opacity(0.12), radius: size * 0.12, y: size * 0.1)
            .accessibilityHidden(true)
    }
}

/// "₱" for PHP, "$" for USD, following the device locale.
func currencySymbol(_ code: String) -> String {
    Decimal(0).formatted(.currency(code: code).precision(.fractionLength(0)))
        .replacingOccurrences(of: "0", with: "")
        .trimmingCharacters(in: .whitespaces)
}

func parseAmount(_ text: String) -> Decimal? {
    let trimmed = text.trimmingCharacters(in: .whitespaces)
    guard !trimmed.isEmpty else { return nil }
    return try? Decimal(trimmed, format: .number)
}

enum Haptics {
    static func success() { UINotificationFeedbackGenerator().notificationOccurred(.success) }
    static func warning() { UINotificationFeedbackGenerator().notificationOccurred(.warning) }
}

let commonCurrencies = ["PHP", "USD", "EUR", "GBP", "JPY", "SGD", "HKD", "AUD", "CAD", "KRW", "CNY", "INR", "AED", "SAR", "MYR", "THB", "IDR", "VND", "NZD", "CHF"]

extension Date {
    /// "Today", "Yesterday", "Tomorrow", or "Oct 3".
    var friendlyDay: String {
        let calendar = Calendar.current
        if calendar.isDateInToday(self) { return "Today" }
        if calendar.isDateInYesterday(self) { return "Yesterday" }
        if calendar.isDateInTomorrow(self) { return "Tomorrow" }
        let sameYear = calendar.isDate(self, equalTo: .now, toGranularity: .year)
        return formatted(sameYear ? .dateTime.month(.abbreviated).day() : .dateTime.month(.abbreviated).day().year())
    }
}
