import AVFoundation
import SwiftUI
import UniformTypeIdentifiers

/// Scan QR code: reads a code with the camera, from an image on the clipboard or from an image
/// file, and hands it to the sheet that deals with it. A dApp pairing code goes to dApps, a
/// secret key or recovery phrase to Import account, and an address or public key is shown here
/// with the choice of adding it to the address book or sending to it. Nothing is acted on
/// without that next sheet, and what was scanned is never displayed unless it is an address.
struct ScanQRSheet: View {
    @Bindable var model: WalletViewModel
    @Environment(\.dismiss) private var dismiss

    private enum CameraState { case starting, running, denied, missing }

    /// An address the scan found, waiting for the user to say what to do with it.
    private struct Found: Equatable {
        let address: Address
        let fromPublicKey: Bool
    }

    @State private var capture = QRCaptureSession()
    @State private var cameraState: CameraState = .starting
    @State private var devices: [CameraDevice] = []
    @State private var deviceID: String?
    @State private var found: Found?
    @State private var note: String?
    /// The parts read so far of a key that a recovery sheet printed across several codes.
    @State private var keyParts = KeyPartCollector()
    @State private var isChoosingImage = false

    /// With no account yet the sheet is a way in: keys and phrases, or an address to watch.
    private var isFirstRun: Bool { model.wallets.isEmpty }
    private var existing: Wallet? { found.flatMap { f in model.wallets.first { $0.address == f.address } } }
    private var canSend: Bool { found.map { model.canSendFromSelected && $0.address != model.selectedWallet?.address } ?? false }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(isFirstRun ? "Import from QR code" : "Scan QR code")
                .font(.title2.weight(.semibold))

            if let found {
                foundPanel(found)
            } else {
                scanner
            }

            if found == nil, !keyParts.isEmpty {
                Label {
                    Text("A secret key in \(keyParts.count) codes: \(keyParts.received) read. Still needed: \(keyParts.missing.map(String.init).joined(separator: ", ")). Scan them in any order.")
                } icon: {
                    ProgressView(value: Double(keyParts.received), total: Double(keyParts.count)).progressViewStyle(.circular).controlSize(.small)
                }
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
            }

            if let note {
                Label(note, systemImage: "exclamationmark.triangle")
                    .font(.callout)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                if found == nil {
                    Button("Paste from Clipboard", action: paste)
                        .keyboardShortcut("v", modifiers: .command)
                        .help("Reads a QR code from an image on the clipboard, such as a screenshot, or a copied code")
                    Button("Choose Image…") { isChoosingImage = true }
                } else {
                    Button("Scan Again", action: scanAgain)
                }
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(20)
        .frame(width: 480)
        .task { await startCamera() }
        .task { for await code in capture.codes { handle(code) } }
        .onChange(of: deviceID) { if let deviceID, found == nil, cameraState == .running { capture.start(deviceID: deviceID) } }
        .onChange(of: model.hasCamera) { Task { await startCamera() } }
        .onDisappear { capture.stop() }
        .fileImporter(isPresented: $isChoosingImage, allowedContentTypes: [.image]) { result in
            guard case .success(let url) = result else { return }
            let codes = NSImage(contentsOf: url).map(QRCode.decodeAll) ?? []
            guard !codes.isEmpty else {
                note = "No QR code was found in that image."
                return
            }
            codes.forEach(handle)
        }
    }

    // MARK: Scanning

    private var scanner: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 10).fill(.black.opacity(0.85))
                switch cameraState {
                case .running:
                    CameraPreview(session: capture.session)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                case .starting:
                    ProgressView().controlSize(.small).colorScheme(.dark)
                case .denied:
                    placeholder("Signet may not use the camera.", symbol: "video.slash") {
                        Button("Open Privacy Settings…") {
                            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera") { NSWorkspace.shared.open(url) }
                        }
                    }
                case .missing:
                    placeholder("No camera is connected.", symbol: "video.slash") { EmptyView() }
                }
            }
            .frame(height: 330)

            if devices.count > 1, cameraState == .running {
                Picker("Camera", selection: $deviceID) {
                    ForEach(devices) { Text($0.name).tag(Optional($0.id)) }
                }
            }

            Text(isFirstRun
                 ? "Hold up a QR code of a secret key or a recovery phrase to import it, or of an address to watch it. A code shown on this Mac's own screen can be read from a screenshot on the clipboard."
                 : "Hold up a QR code: a dApp's pairing code, an address or public key, or a secret key or recovery phrase. A code shown on this Mac's own screen can be read from a screenshot on the clipboard.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func placeholder(_ text: String, symbol: String, @ViewBuilder action: () -> some View) -> some View {
        VStack(spacing: 10) {
            Image(systemName: symbol).font(.largeTitle)
            Text(text)
            action()
        }
        .foregroundStyle(.white.opacity(0.8))
    }

    private func startCamera() async {
        guard found == nil else { return }
        devices = QRCamera.devices()
        if deviceID == nil || !devices.contains(where: { $0.id == deviceID }) { deviceID = QRCamera.preferred(among: devices)?.id }
        guard let deviceID else {
            capture.stop()
            cameraState = .missing
            return
        }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: break
        case .notDetermined:
            guard await AVCaptureDevice.requestAccess(for: .video) else { cameraState = .denied; return }
        default:
            cameraState = .denied
            return
        }
        guard found == nil else { return }
        capture.start(deviceID: deviceID)
        cameraState = .running
    }

    private func scanAgain() {
        found = nil
        note = nil
        keyParts = KeyPartCollector()
        Task { await startCamera() }
    }

    private func paste() {
        let texts = QRCamera.textsFromPasteboard()
        guard !texts.isEmpty else {
            note = "The clipboard holds no QR code image and no text."
            return
        }
        texts.forEach(handle)
    }

    // MARK: What was scanned

    private func handle(_ text: String) {
        guard found == nil else { return }
        note = nil
        switch QRPayload.classify(text) {
        case .pairing(let code):
            guard model.wallets.contains(where: { $0.keyKind.canSign }) else {
                note = "That is a dApp's pairing code. Create or import an account first, then scan it again."
                return
            }
            finish(.pair(code: code))
        case .secretKey(let key):
            finish(.importKey(.secretKey(key)))
        case .recoveryPhrase(let phrase):
            finish(.importKey(.recoveryPhrase(phrase)))
        case .keyPart(let part):
            switch keyParts.add(part) {
            case .needMore: break
            case .complete(let key): finish(.importKey(.secretKey(key)))
            case .invalid: note = "Those codes do not fit together into a key. Scan every part of the same recovery sheet again."
            }
        case .address(let address):
            show(Found(address: address, fromPublicKey: false))
        case .publicKey(let key):
            Task {
                do {
                    show(Found(address: try await model.address(forScannedPublicKey: key), fromPublicKey: true))
                } catch {
                    note = "That looks like a public key, but Signet could not read it."
                }
            }
        case .unknown:
            note = "That code is not a pairing code, an address or a key that Signet can use."
        }
    }

    private func show(_ result: Found) {
        guard found == nil else { return }
        capture.stop()
        found = result
    }

    /// Stops the camera and closes; the home view opens the next sheet once this one has gone.
    private func finish(_ handoff: WalletViewModel.ScanHandoff) {
        guard model.pendingScan == nil else { return }
        capture.stop()
        model.pendingScan = handoff
        dismiss()
    }

    // MARK: An address

    private func foundPanel(_ found: Found) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                AccountAvatarView(address: found.address, network: model.network, size: 44)
                VStack(alignment: .leading, spacing: 3) {
                    Text(found.address.value)
                        .font(.callout.monospaced())
                        .textSelection(.enabled)
                    if let existing {
                        Label("In your list as “\(existing.alias)”", systemImage: "checkmark.seal")
                            .font(.callout).foregroundStyle(.secondary)
                    } else if found.address.isContract {
                        Text("Smart contract").font(.caption).foregroundStyle(.secondary)
                    } else if let scheme = found.address.scheme {
                        Text(found.fromPublicKey ? "\(scheme.displayName), from the scanned public key" : scheme.displayName)
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.secondary.opacity(0.08)))

            Text("Check the address against where the code came from before you use it.")
                .font(.callout)
                .foregroundStyle(.secondary)

            HStack {
                Spacer()
                if existing == nil {
                    Button(isFirstRun ? "Watch This Address…" : "Add to Address Book…") { finish(.addAddress(found.address)) }
                }
                if canSend {
                    Button("Send…") { finish(.send(found.address)) }
                        .buttonStyle(.borderedProminent)
                }
            }
        }
    }
}

/// The live picture from the camera.
private struct CameraPreview: NSViewRepresentable {
    let session: AVCaptureSession

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        view.layer = layer
        view.wantsLayer = true
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {}
}

#Preview {
    ScanQRSheet(model: .preview())
}
