import SwiftUI

/// How a wallet card looks. Stored as a string on `Account.cardSkin` so it syncs.
enum CardSkin: Hashable {
    case texture(Texture)
    case color(String)
    case photo

    enum Texture: String, CaseIterable, Identifiable {
        case ember, ocean, jeepney, linen, midnight, mint
        var id: String { rawValue }
        var label: String { rawValue.capitalized }
    }

    init(raw: String, fallbackHex: String) {
        if let texture = Texture(rawValue: raw) {
            self = .texture(texture)
        } else if raw == "photo" {
            self = .photo
        } else if raw.hasPrefix("color:") {
            self = .color(String(raw.dropFirst(6)))
        } else {
            self = .color(fallbackHex)
        }
    }

    var raw: String {
        switch self {
        case .texture(let t): t.rawValue
        case .color(let hex): "color:" + hex
        case .photo: "photo"
        }
    }

    /// Text color that stays readable on this skin.
    var ink: Color {
        switch self {
        case .texture(.linen): Color(rgb: 0x1C1A19)
        case .texture: .white
        case .color(let hex): CardSkin.isLight(hex) ? Color(rgb: 0x1C1A19) : .white
        case .photo: .white
        }
    }

    /// Relative luminance > 0.6 means dark text reads better.
    static func isLight(_ hex: String) -> Bool {
        let rgb = UInt32(hex, radix: 16) ?? 0
        let r = Double((rgb >> 16) & 0xFF) / 255, g = Double((rgb >> 8) & 0xFF) / 255, b = Double(rgb & 0xFF) / 255
        return 0.2126 * r + 0.7152 * g + 0.0722 * b > 0.6
    }
}

/// Apple Wallet–style card for a wallet, or for "All wallets" on Home.
struct WalletCardView: View {
    var title: String
    var kind: String
    var caption: String
    var amount: Decimal
    var currency: String
    var emblem: String
    var skin: CardSkin
    var photo: Data?
    @AppStorage(SettingsKey.showBalanceOnCards) private var showBalance = true

    var body: some View {
        let ink = skin.ink
        ZStack {
            CardBackground(skin: skin, photo: photo)
            VStack(alignment: .leading) {
                HStack(alignment: .firstTextBaseline) {
                    Text(title).font(.headline).lineLimit(1)
                    Spacer()
                    Text(kind.uppercased()).font(.caption2.weight(.semibold)).tracking(1.2).opacity(0.8)
                }
                Spacer(minLength: 8)
                HStack(alignment: .lastTextBaseline) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(caption).font(.caption).opacity(0.8)
                        if showBalance {
                            HStack(alignment: .firstTextBaseline, spacing: 2) {
                                Text(currencySymbol(currency)).font(.system(.title3, design: .rounded, weight: .light)).opacity(0.75)
                                Text(amount.formatted(.number.precision(.fractionLength(0...2))))
                                    .font(.system(size: 34, weight: .medium, design: .rounded))
                                    .contentTransition(.numericText(value: amount.double))
                            }
                            .minimumScaleFactor(0.6)
                            .lineLimit(1)
                        } else {
                            Text("••••••").font(.system(size: 30, weight: .medium, design: .rounded))
                        }
                    }
                    Spacer()
                    Text(emblem).font(.headline.weight(.bold)).opacity(0.9).lineLimit(1)
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
            .foregroundStyle(ink)
        }
        .frame(height: 216)
        .frame(maxWidth: .infinity)
        .clipShape(.rect(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(.white.opacity(0.12), lineWidth: 1))
        .shadow(color: .black.opacity(0.35), radius: 14, y: 10)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title) card, \(caption) \(showBalance ? amount.money(currency) : "hidden")")
    }
}

extension WalletCardView {
    init(account: Account) {
        let balance = account.balance
        let owed = account.type == .creditCard && balance < 0
        self.init(
            title: account.name,
            kind: account.type.label,
            caption: owed ? "Owed" : "Balance",
            amount: owed ? -balance : balance,
            currency: account.currency,
            emblem: account.cardEmblem.isEmpty ? String(account.name.prefix(1)).uppercased() : account.cardEmblem,
            skin: CardSkin(raw: account.cardSkin, fallbackHex: account.colorHex),
            photo: account.cardPhoto
        )
    }
}

/// The card's printed surface. Textures are drawn, not images, so they stay crisp at any size.
struct CardBackground: View {
    let skin: CardSkin
    var photo: Data?

    var body: some View {
        switch skin {
        case .texture(let texture):
            Canvas { context, size in draw(texture, in: &context, size: size) }
                .overlay {
                    // Keeps the balance readable over busy textures.
                    if texture != .linen {
                        LinearGradient(colors: [.clear, .black.opacity(0.28)], startPoint: .center, endPoint: .bottom)
                    }
                }
        case .color(let hex):
            ZStack {
                Color(hex: hex)
                LinearGradient(colors: [.white.opacity(0.2), .clear, .black.opacity(0.18)], startPoint: .topLeading, endPoint: .bottomTrailing)
            }
        case .photo:
            ZStack {
                Color(rgb: 0x3A3532)
                if let photo, let image = UIImage(data: photo) {
                    Image(uiImage: image).resizable().scaledToFill()
                }
                // Keeps white text readable on any photo.
                LinearGradient(colors: [.black.opacity(0.35), .clear, .black.opacity(0.45)], startPoint: .top, endPoint: .bottom)
            }
        }
    }

    private func draw(_ texture: CardSkin.Texture, in context: inout GraphicsContext, size: CGSize) {
        let rect = CGRect(origin: .zero, size: size)
        let (w, h) = (size.width, size.height)
        switch texture {
        case .ember:
            context.fill(Path(rect), with: .radialGradient(
                Gradient(colors: [Color(rgb: 0xFF7A2E), Color(rgb: 0xE0301C), Color(rgb: 0x8E0B12)]),
                center: CGPoint(x: w * 0.15, y: 0), startRadius: 0, endRadius: w * 1.1))
            // Halftone dots.
            let step = 12.0, dot = step * 0.34
            var dots = Path()
            for y in stride(from: step / 2, to: h, by: step) {
                for x in stride(from: step / 2, to: w, by: step) {
                    dots.addEllipse(in: CGRect(x: x - dot, y: y - dot, width: dot * 2, height: dot * 2))
                }
            }
            context.fill(dots, with: .color(Color(red: 1, green: 0.77, blue: 0.47).opacity(0.3)))
        case .ocean:
            context.fill(Path(rect), with: .linearGradient(
                Gradient(colors: [Color(rgb: 0x2A7BC4), Color(rgb: 0x0B2F55)]),
                startPoint: .zero, endPoint: CGPoint(x: w, y: h)))
            let center = CGPoint(x: w * 0.85, y: h * 0.15)
            var rings = Path()
            for r in stride(from: 13.0, to: w * 1.2, by: 13) {
                rings.addEllipse(in: CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2))
            }
            context.stroke(rings, with: .color(.white.opacity(0.16)), lineWidth: 1)
        case .jeepney:
            let colors = [Color(rgb: 0xD8141A), Color(rgb: 0xF4C430), Color(rgb: 0x1E4FB8), Color(rgb: 0xF4C430)]
            var stripes = context
            stripes.rotate(by: .degrees(-45))
            let band = 12.0
            for (i, x) in stride(from: -h * 2, to: w * 2, by: band).enumerated() {
                stripes.fill(Path(CGRect(x: x, y: -h * 2, width: band, height: h * 4)), with: .color(colors[i % colors.count]))
            }
            context.fill(Path(rect), with: .linearGradient(
                Gradient(stops: [.init(color: Color(rgb: 0x161210).opacity(0.92), location: 0),
                                 .init(color: Color(rgb: 0x161210).opacity(0.86), location: 0.52),
                                 .init(color: Color(rgb: 0x161210).opacity(0), location: 0.8)]),
                startPoint: .zero, endPoint: CGPoint(x: w, y: 0)))
        case .linen:
            context.fill(Path(rect), with: .color(Color(rgb: 0xEFE7DA)))
            var weave = Path()
            for y in stride(from: 0, to: h, by: 3) { weave.addRect(CGRect(x: 0, y: y, width: w, height: 1)) }
            for x in stride(from: 0, to: w, by: 3) { weave.addRect(CGRect(x: x, y: 0, width: 1, height: h)) }
            context.fill(weave, with: .color(Color(rgb: 0x3C2814).opacity(0.05)))
        case .midnight:
            context.fill(Path(rect), with: .color(Color(rgb: 0x141212)))
            var grid = Path()
            for y in stride(from: 0, to: h, by: 22) { grid.addRect(CGRect(x: 0, y: y, width: w, height: 1)) }
            for x in stride(from: 0, to: w, by: 22) { grid.addRect(CGRect(x: x, y: 0, width: 1, height: h)) }
            context.fill(grid, with: .color(.white.opacity(0.05)))
            var streak = Path()
            streak.move(to: CGPoint(x: w * 0.52, y: h)); streak.addLine(to: CGPoint(x: w * 0.72, y: h))
            streak.addLine(to: CGPoint(x: w * 1.02, y: 0)); streak.addLine(to: CGPoint(x: w * 0.82, y: 0)); streak.closeSubpath()
            context.fill(streak, with: .linearGradient(
                Gradient(colors: [Color(rgb: 0xFF4543).opacity(0.4), .clear]),
                startPoint: CGPoint(x: w * 0.6, y: h), endPoint: CGPoint(x: w, y: 0)))
        case .mint:
            context.fill(Path(rect), with: .color(Color(rgb: 0x1E9E5A)))
            context.fill(Path(rect), with: .radialGradient(Gradient(colors: [Color(rgb: 0x8BE6B8), .clear]),
                center: CGPoint(x: w * 0.92, y: h * 0.08), startRadius: 0, endRadius: w * 0.75))
            context.fill(Path(rect), with: .radialGradient(Gradient(colors: [Color(rgb: 0x0B4D2C), .clear]),
                center: CGPoint(x: 0, y: h), startRadius: 0, endRadius: w * 0.7))
        }
    }
}
