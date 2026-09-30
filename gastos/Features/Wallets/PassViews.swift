import SwiftUI
import SwiftData
import PhotosUI
import Vision
import VisionKit

/// A pass opened from the stack: its card, then the code big and bright for the cashier.
struct PassDetailView: View {
    let pass: Pass
    var pile: [CardSkin] = []

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @State private var editing = false
    @State private var customizing = false
    @State private var confirmingDelete = false
    @State private var savedBrightness: CGFloat?

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                PassCardView(pass: pass)

                if let image = CodeRenderer.image(for: pass.code, format: pass.codeFormat) {
                    VStack(spacing: 12) {
                        Image(uiImage: image)
                            .interpolation(.none)
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: pass.codeFormat == .code128 || pass.codeFormat == .pdf417 ? 120 : 230)
                            .accessibilityLabel("\(pass.codeFormat.label) for \(pass.name)")
                        Text(pass.code)
                            .font(.system(.footnote, design: .monospaced))
                            .foregroundStyle(Color(rgb: 0x1C1A19))
                            .lineLimit(2)
                            .textSelection(.enabled)
                    }
                    .padding(22)
                    .frame(maxWidth: .infinity)
                    .background(.white, in: .rect(cornerRadius: 24, style: .continuous))
                } else {
                    Text("No code on this card. Tap Edit to scan or type one.")
                        .font(.subheadline).foregroundStyle(Color.muted).multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity, minHeight: 80)
                        .card()
                }

                if !pass.notes.isEmpty {
                    Text(pass.notes).font(.body).foregroundStyle(Color.ink).frame(maxWidth: .infinity, alignment: .leading).card()
                }
            }
            .padding(20)
            .padding(.bottom, 80)
        }
        .canvasBackground()
        .navigationTitle(pass.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarVisibility(.hidden, for: .tabBar)
        .onAppear { TabChrome.shared.hidesAccessory = true }
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
                    Button("Edit Card", systemImage: "pencil") { editing = true }
                    Button("Card Style", systemImage: "paintbrush.pointed") { customizing = true }
                    Button("Delete Card", systemImage: "trash", role: .destructive) { confirmingDelete = true }
                } label: { Text("Edit") }
            }
        }
        .sheet(isPresented: $editing) { PassEditor(pass: pass) }
        .sheet(isPresented: $customizing) { CardCustomizeView(pass: pass) }
        .confirmationDialog("Delete \(pass.name)?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete Card", role: .destructive) {
                dismiss()
                context.delete(pass)
            }
        }
        // Scanners read screens better at full brightness, as in Apple Wallet.
        .onAppear { if pass.codeFormat != .none && !pass.code.isEmpty { boostBrightness() } }
        .onDisappear(perform: restoreBrightness)
    }

    private var screen: UIScreen? {
        (UIApplication.shared.connectedScenes.first { $0.activationState == .foregroundActive } as? UIWindowScene)?.screen
    }

    private func boostBrightness() {
        guard let screen, savedBrightness == nil else { return }
        savedBrightness = screen.brightness
        screen.brightness = 1
    }

    private func restoreBrightness() {
        if let savedBrightness, let screen { screen.brightness = savedBrightness }
        savedBrightness = nil
    }
}

/// Add or edit a pass: what it is, its number and code, and its look.
struct PassEditor: View {
    var pass: Pass?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query private var allPasses: [Pass]
    @State private var draft = Pass()
    @State private var name = ""
    @State private var kind = PassKind.loyalty
    @State private var number = ""
    @State private var holder = ""
    @State private var notes = ""
    @State private var code = ""
    @State private var format = CodeFormat.qr
    @State private var scanning = false
    @State private var photoItem: PhotosPickerItem?
    @State private var customizing = false
    @State private var scanMessage: String?

    private var target: Pass { pass ?? draft }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    PassCardView(title: name, kind: kind.label, number: number, holder: holder, emblem: target.cardEmblem,
                                 skin: CardSkin(raw: target.cardSkin, fallbackHex: target.colorHex), photo: target.cardPhoto,
                                 hasCode: !code.isEmpty && format != .none)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                    Button("Card style", systemImage: "paintbrush.pointed") { customizing = true }
                }

                Section {
                    TextField("Name, e.g. SM Advantage", text: $name).font(.headline)
                    Picker("Type", selection: $kind) {
                        ForEach(PassKind.allCases) { Text($0.label).tag($0) }
                    }
                    .onChange(of: kind) { old, new in
                        if target.cardSkin == old.defaultSkin { target.cardSkin = new.defaultSkin }
                    }
                    TextField("Card number", text: $number).font(.body.monospaced())
                    TextField("Name on card", text: $holder)
                }

                Section {
                    Picker("Code", selection: $format) {
                        ForEach(CodeFormat.allCases) { Text($0.label).tag($0) }
                    }
                    if format != .none {
                        TextField("What the code says", text: $code, axis: .vertical)
                            .font(.body.monospaced())
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                        if DataScannerViewController.isSupported {
                            Button("Scan with camera", systemImage: "camera.viewfinder") { scanning = true }
                        }
                        PhotosPicker(selection: $photoItem, matching: .images) {
                            Label("Scan from a photo or screenshot", systemImage: "photo")
                        }
                        if let scanMessage { Text(scanMessage).font(.footnote).foregroundStyle(Color.muted) }
                        if !code.isEmpty && CodeRenderer.image(for: code, format: format) == nil {
                            Text("This \(format.label.lowercased()) can't hold these characters. Try QR code.")
                                .font(.footnote).foregroundStyle(Color.brand)
                        }
                    }
                } header: {
                    Text("QR code or barcode")
                } footer: {
                    Text("Shown big and bright when you open the card, so it scans at the counter.")
                }

                Section("Notes") {
                    TextField("Expiry, perks, anything", text: $notes, axis: .vertical)
                }
            }
            .canvasBackground()
            .navigationTitle(pass == nil ? "New Card" : "Edit Card")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save).disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .sheet(isPresented: $customizing) { CardCustomizeView(pass: target) }
            .sheet(isPresented: $scanning) {
                BarcodeScanner { payload, found in
                    code = payload
                    format = found
                    scanning = false
                    Haptics.success()
                }
                .ignoresSafeArea()
            }
            .onChange(of: photoItem) { _, item in Task { await scanPhoto(item) } }
            .onAppear(perform: load)
        }
    }

    private func load() {
        guard let pass else { return }
        (name, kind, number, holder, notes, code, format) = (pass.name, pass.kind, pass.number, pass.holder, pass.notes, pass.code, pass.codeFormat)
    }

    private func save() {
        let target = self.target
        target.name = name.trimmingCharacters(in: .whitespaces)
        target.kind = kind
        target.number = number.trimmingCharacters(in: .whitespaces)
        target.holder = holder.trimmingCharacters(in: .whitespaces)
        target.notes = notes
        target.code = code.trimmingCharacters(in: .whitespacesAndNewlines)
        target.codeFormat = format
        if pass == nil {
            target.sortOrder = (allPasses.map(\.sortOrder).max() ?? 0) + 1
            context.insert(target)
        }
        Haptics.success()
        dismiss()
    }

    private func scanPhoto(_ item: PhotosPickerItem?) async {
        guard let data = try? await item?.loadTransferable(type: Data.self),
              let image = UIImage(data: data), let cgImage = image.cgImage else { return }
        if let (payload, found) = BarcodeScanner.detect(in: cgImage) {
            code = payload
            format = found
            scanMessage = nil
            Haptics.success()
        } else {
            scanMessage = "No code found in that photo."
        }
    }
}

/// Live camera scanner (VisionKit). Calls back once with the first code it reads.
struct BarcodeScanner: UIViewControllerRepresentable {
    var onFound: (String, CodeFormat) -> Void

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(recognizedDataTypes: [.barcode()], qualityLevel: .balanced,
                                                isHighlightingEnabled: true)
        scanner.delegate = context.coordinator
        return scanner
    }

    func updateUIViewController(_ scanner: DataScannerViewController, context: Context) {
        if !scanner.isScanning { try? scanner.startScanning() }
    }

    func makeCoordinator() -> Coordinator { Coordinator(onFound: onFound) }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let onFound: (String, CodeFormat) -> Void
        private var done = false
        init(onFound: @escaping (String, CodeFormat) -> Void) { self.onFound = onFound }

        func dataScanner(_ scanner: DataScannerViewController, didAdd items: [RecognizedItem], allItems: [RecognizedItem]) {
            guard !done else { return }
            for item in items {
                if case .barcode(let barcode) = item, let payload = barcode.payloadStringValue {
                    done = true
                    scanner.stopScanning()
                    onFound(payload, BarcodeScanner.format(for: barcode.observation.symbology))
                    return
                }
            }
        }
    }

    /// Finds the first code in a still image (photo or screenshot).
    static func detect(in image: CGImage) -> (String, CodeFormat)? {
        let request = VNDetectBarcodesRequest()
        try? VNImageRequestHandler(cgImage: image).perform([request])
        guard let result = request.results?.first(where: { $0.payloadStringValue != nil }),
              let payload = result.payloadStringValue else { return nil }
        return (payload, format(for: result.symbology))
    }

    /// Codes we can't redraw exactly (EAN, UPC…) are shown as Code 128 with the same digits.
    static func format(for symbology: VNBarcodeSymbology) -> CodeFormat {
        switch symbology {
        case .qr, .microQR: .qr
        case .pdf417, .microPDF417: .pdf417
        case .aztec: .aztec
        default: .code128
        }
    }
}
