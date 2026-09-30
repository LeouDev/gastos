import SwiftUI
import PhotosUI

/// Pick a card's texture, color or photo, and its emblem. `account == nil` edits the Home "All wallets" card.
struct CardCustomizeView: View {
    let account: Account?

    private enum Tab: String, CaseIterable { case textures = "Textures", colors = "Colors", photo = "Photo" }

    @Environment(\.dismiss) private var dismiss
    @AppStorage(SettingsKey.homeCardSkin) private var homeSkin = CardSkin.Texture.ember.rawValue
    @AppStorage(SettingsKey.showBalanceOnCards) private var showBalance = true
    @State private var skin = CardSkin.texture(.ember)
    @State private var emblem = ""
    @State private var photo: Data?
    @State private var tab = Tab.textures
    @State private var pickedItem: PhotosPickerItem?
    @State private var customColor = Color.brand

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 22) {
                    preview
                    Picker("Style", selection: $tab) {
                        ForEach(tabs, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)

                    switch tab {
                    case .textures: textures
                    case .colors: colors
                    case .photo: photoPicker
                    }

                    VStack(spacing: 0) {
                        Toggle("Show balances on cards", isOn: $showBalance)
                            .padding(.horizontal, 16).frame(minHeight: 50)
                        if account != nil {
                            Divider().padding(.leading, 16)
                            HStack {
                                Text("Emblem")
                                Spacer()
                                TextField("Auto", text: $emblem)
                                    .multilineTextAlignment(.trailing)
                                    .textInputAutocapitalization(.characters)
                                    .onChange(of: emblem) { _, new in if new.count > 4 { emblem = String(new.prefix(4)) } }
                            }
                            .padding(.horizontal, 16).frame(minHeight: 50)
                        }
                    }
                    .background(Color.card, in: .rect(cornerRadius: 18, style: .continuous))
                }
                .padding(20)
            }
            .canvasBackground()
            .navigationTitle("Card style")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Done", action: save).fontWeight(.semibold) }
            }
            .onAppear(perform: load)
            .onChange(of: pickedItem) { _, item in Task { await loadPhoto(item) } }
        }
        .presentationDragIndicator(.visible)
    }

    private var tabs: [Tab] { account == nil ? [.textures, .colors] : Tab.allCases }

    private var preview: some View {
        Group {
            if let account {
                let base = WalletCardView(account: account)
                WalletCardView(title: base.title, kind: base.kind, caption: base.caption, amount: base.amount, currency: base.currency,
                               emblem: emblem.isEmpty ? String(account.name.prefix(1)).uppercased() : emblem, skin: skin, photo: photo)
            } else {
                WalletCardView(title: "All wallets", kind: "Total", caption: "Total money", amount: 0, currency: "PHP", emblem: "gastos", skin: skin)
            }
        }
        .animation(.snappy, value: skin)
    }

    private var textures: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3), spacing: 14) {
            ForEach(CardSkin.Texture.allCases) { texture in
                swatch(.texture(texture), label: texture.label)
            }
        }
    }

    private var colors: some View {
        VStack(alignment: .leading, spacing: 14) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 4), spacing: 14) {
                ForEach(Color.palette + ["1C1A19", "F3EFE9"], id: \.self) { hex in
                    swatch(.color(hex), label: nil)
                }
            }
            ColorPicker("Any color", selection: $customColor, supportsOpacity: false)
                .onChange(of: customColor) { _, color in skin = .color(color.hex) }
                .padding(.horizontal, 16).frame(minHeight: 50)
                .background(Color.card, in: .rect(cornerRadius: 18, style: .continuous))
        }
    }

    private var photoPicker: some View {
        VStack(spacing: 12) {
            PhotosPicker(selection: $pickedItem, matching: .images) {
                Label(photo == nil ? "Choose a photo" : "Choose another photo", systemImage: "photo")
                    .frame(maxWidth: .infinity, minHeight: 50)
            }
            .buttonStyle(.glass)
            Text("Photos stay on this iPhone. Your other devices show the wallet's color.")
                .font(.footnote).foregroundStyle(Color.muted).multilineTextAlignment(.center)
        }
    }

    private func swatch(_ option: CardSkin, label: String?) -> some View {
        Button { withAnimation(.snappy) { skin = option } } label: {
            VStack(spacing: 6) {
                CardBackground(skin: option)
                    .frame(height: label == nil ? 48 : 64)
                    .clipShape(.rect(cornerRadius: 12, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(skin == option ? Color.ink : .white.opacity(0.12), lineWidth: skin == option ? 2.5 : 1)
                    }
                if let label { Text(label).font(.caption).foregroundStyle(Color.ink) }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label ?? "Color")
        .accessibilityAddTraits(skin == option ? .isSelected : [])
    }

    private func load() {
        if let account {
            skin = CardSkin(raw: account.cardSkin, fallbackHex: account.colorHex)
            emblem = account.cardEmblem
            photo = account.cardPhoto
        } else {
            skin = CardSkin(raw: homeSkin, fallbackHex: "D8141A")
        }
        if case .photo = skin { tab = .photo } else if case .color(let hex) = skin { tab = .colors; customColor = Color(hex: hex) }
    }

    private func loadPhoto(_ item: PhotosPickerItem?) async {
        guard let data = try? await item?.loadTransferable(type: Data.self), let image = UIImage(data: data) else { return }
        // Cards are small; keep the stored photo small too.
        let scale = min(1, 1000 / max(image.size.width, image.size.height))
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let resized = UIGraphicsImageRenderer(size: size).image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
        photo = resized.jpegData(compressionQuality: 0.8)
        skin = .photo
    }

    private func save() {
        if let account {
            account.cardSkin = skin.raw
            account.cardEmblem = emblem.trimmingCharacters(in: .whitespaces)
            account.cardPhoto = skin == .photo ? photo : nil
        } else {
            homeSkin = skin.raw
        }
        Haptics.success()
        dismiss()
    }
}

extension Color {
    /// "RRGGBB" for storing a picked color.
    var hex: String {
        let ui = UIColor(self)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        ui.getRed(&r, green: &g, blue: &b, alpha: &a)
        return String(format: "%02X%02X%02X", Int((min(max(r, 0), 1)) * 255), Int((min(max(g, 0), 1)) * 255), Int((min(max(b, 0), 1)) * 255))
    }
}
