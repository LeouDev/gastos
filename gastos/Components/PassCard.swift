import SwiftUI
import CoreImage.CIFilterBuiltins

/// A loyalty card, membership, ticket, health or ID card, drawn like the wallet cards.
struct PassCardView: View {
    var title: String
    var kind: String
    var number: String
    var holder: String
    var emblem: String
    var skin: CardSkin
    var photo: Data?
    var hasCode: Bool
    var photoOnly = false

    /// Photo only: the card is just the picture, like the physical card.
    private var showsText: Bool { !(photoOnly && skin == .photo && photo != nil) }
    var showsTextForTesting: Bool { showsText }

    var body: some View {
        // The background sits behind the text rather than sizing the card, so a tall photo
        // can't stretch the layout and push the title past the top edge.
        VStack(alignment: .leading) {
            if showsText {
                HStack(alignment: .firstTextBaseline) {
                    Text(title.isEmpty ? "New card" : title).font(.headline).lineLimit(1)
                    Spacer()
                    Text(kind.uppercased()).font(.caption2.weight(.semibold)).tracking(1.2).opacity(0.8)
                }
                Spacer(minLength: 8)
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 2) {
                        if !holder.isEmpty { Text(holder).font(.caption).opacity(0.85).lineLimit(1) }
                        if !number.isEmpty {
                            Text(number).font(.system(.title3, design: .monospaced, weight: .medium)).lineLimit(1).minimumScaleFactor(0.6)
                        }
                    }
                    Spacer()
                    if hasCode {
                        Image(systemName: "qrcode").font(.title2.weight(.semibold)).opacity(0.9)
                    } else if !emblem.isEmpty {
                        Text(emblem).font(.headline.weight(.bold)).opacity(0.9)
                    }
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .foregroundStyle(skin.ink)
        .frame(maxWidth: .infinity)
        .frame(height: 216)
        .background { CardBackground(skin: skin, photo: photo, plain: !showsText) }
        .clipShape(.rect(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(.white.opacity(0.12), lineWidth: 1))
        .shadow(color: .black.opacity(0.35), radius: 14, y: 10)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title) \(kind) card")
    }
}

extension PassCardView {
    init(pass: Pass) {
        self.init(title: pass.name, kind: pass.kind.label, number: pass.number, holder: pass.holder,
                  emblem: pass.cardEmblem, skin: CardSkin(raw: pass.cardSkin, fallbackHex: pass.colorHex),
                  photo: pass.cardPhoto, hasCode: !pass.code.isEmpty && pass.codeFormat != .none, photoOnly: pass.photoOnly)
    }
}

/// Draws QR codes and barcodes with Core Image, so any code a cashier scans can be recreated.
enum CodeRenderer {
    static func image(for payload: String, format: CodeFormat) -> UIImage? {
        guard !payload.isEmpty else { return nil }
        let output: CIImage?
        switch format {
        case .qr:
            let filter = CIFilter.qrCodeGenerator()
            filter.message = Data(payload.utf8)
            filter.correctionLevel = "M"
            output = filter.outputImage
        case .code128:
            // Code 128 only encodes ASCII.
            guard let data = payload.data(using: .ascii) else { return nil }
            let filter = CIFilter.code128BarcodeGenerator()
            filter.message = data
            filter.quietSpace = 4
            output = filter.outputImage
        case .pdf417:
            let filter = CIFilter.pdf417BarcodeGenerator()
            filter.message = Data(payload.utf8)
            output = filter.outputImage
        case .aztec:
            let filter = CIFilter.aztecCodeGenerator()
            filter.message = Data(payload.utf8)
            output = filter.outputImage
        case .none:
            return nil
        }
        guard let output else { return nil }
        let scaled = output.transformed(by: CGAffineTransform(scaleX: 10, y: 10))
        guard let cgImage = CIContext().createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}

/// The other cards peeking out at the bottom of a card's screen, like Apple Wallet. Tap to go back.
struct CardPile: View {
    let skins: [CardSkin]
    var onTap: () -> Void

    var body: some View {
        if !skins.isEmpty {
            Button(action: onTap) {
                ZStack(alignment: .top) {
                    ForEach(Array(skins.prefix(3).enumerated()), id: \.offset) { index, skin in
                        CardBackground(skin: skin)
                            .frame(height: 70)
                            .clipShape(UnevenRoundedRectangle(topLeadingRadius: 18, topTrailingRadius: 18, style: .continuous))
                            .overlay(UnevenRoundedRectangle(topLeadingRadius: 18, topTrailingRadius: 18, style: .continuous)
                                .strokeBorder(.white.opacity(0.12), lineWidth: 1))
                            .padding(.horizontal, CGFloat(min(skins.count, 3) - 1 - index) * 8)
                            .offset(y: CGFloat(index) * 12)
                            .shadow(color: .black.opacity(0.3), radius: 8, y: -4)
                    }
                }
                .frame(height: 70 + CGFloat(min(skins.count, 3) - 1) * 12, alignment: .top)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Other cards")
            .accessibilityHint("Goes back to all cards")
        }
    }
}
