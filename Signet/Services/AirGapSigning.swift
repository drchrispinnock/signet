#if canImport(AppKit)
import AppKit
import AVFoundation
import SwiftUI
#else
import Foundation
import Observation
#endif

/// Signing with AirGap Vault. When the bridge's AirGap signer needs a signature it calls here
/// with the forged operation; a panel slides down over whatever sheet is open and shows the
/// operation as AirGap's transaction sign request (an animated QR code when it does not fit
/// one), the user scans it with the Vault, checks and approves it there, and holds up the
/// Vault's signed reply to the camera (or pastes a screenshot of it). The reply must answer
/// this request and carry exactly the bytes sent; the bridge then checks the signature against
/// the account's key before anything reaches a node. One request at a time.
@MainActor
final class AirGapSigning {
    static let shared = AirGapSigning()

    enum Failure: LocalizedError, Equatable {
        case cancelled, busy, unavailable, badRequest, differentOperation

        var errorDescription: String? {
            switch self {
            case .cancelled: "Signing in AirGap Vault was cancelled. Nothing was sent."
            case .busy: "Another operation is waiting for AirGap Vault. Finish or cancel it first."
            case .unavailable: "AirGap Vault signing is not available here."
            case .badRequest: "Signet could not make an AirGap Vault request for this operation."
            case .differentOperation: "AirGap Vault signed other bytes than Signet sent, so its signature was not used. Nothing was sent."
            }
        }
    }

    private var active: AirGapSignSession?
    #if canImport(AppKit)
    private var window: NSWindow?
    #endif

    /// The 64-byte signature for `{address, publicKey, forged}` (forged as hex), or an error.
    func sign(requestJSON: String) async throws -> [UInt8] {
        guard !SignetApp.isTestHost else { throw Failure.unavailable }
        guard active == nil else { throw Failure.busy }
        guard let data = requestJSON.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let address = object["address"] as? String, let publicKey = object["publicKey"] as? String,
              let forgedHex = object["forged"] as? String, let forged = Hex.decode(forgedHex), !forged.isEmpty,
              let session = AirGapSignSession(address: address, publicKey: publicKey, forged: forged)
        else { throw Failure.badRequest }
        active = session
        return try await withCheckedThrowingContinuation { continuation in
            session.onFinish = { [weak self] result in
                self?.dismiss()
                continuation.resume(with: result)
            }
            present(session)
        }
    }

    #if canImport(AppKit)
    private func present(_ session: AirGapSignSession) {
        let panel = NSWindow(contentViewController: NSHostingController(rootView: AirGapSignView(session: session).appliesStoredAppearance()))
        panel.styleMask = [.titled]
        panel.title = "Sign with AirGap Vault"
        window = panel
        // Over the deepest sheet of the window in front, so it belongs to the Send (or other) sheet that asked.
        if var parent = NSApp.keyWindow ?? NSApp.mainWindow ?? NSApp.windows.first(where: { $0.isVisible && $0.canBecomeMain }) {
            while let sheet = parent.attachedSheet { parent = sheet }
            parent.beginSheet(panel)
        } else {
            panel.center()
            panel.makeKeyAndOrderFront(nil)
        }
    }

    private func dismiss() {
        if let window {
            if let parent = window.sheetParent { parent.endSheet(window) } else { window.orderOut(nil) }
        }
        window = nil
        active = nil
    }
    #else
    // Off the Mac the port shows the panel (`presentPanel`, `closePanel`).
    private func present(_ session: AirGapSignSession) { presentPanel(session) }

    private func dismiss() {
        closePanel()
        active = nil
    }
    #endif
}

/// One request to the Vault: the code to show, then the reply being read.
@MainActor
@Observable
final class AirGapSignSession {
    enum Phase { case showing, scanning }

    let address: String
    let forged: [UInt8]
    let id: UInt64
    /// The request as QR code texts; more than one is shown in turn.
    let frames: [String]
    var phase: Phase = .showing
    var note: String?
    private(set) var decoder = UniformResource.Decoder()
    @ObservationIgnored var onFinish: ((Result<[UInt8], Error>) -> Void)?
    private var finished = false

    /// Bytes per QR frame: small enough for a phone to read off a laptop screen at a glance.
    static let fragmentSize = 200

    init?(address: String, publicKey: String, forged: [UInt8], id: UInt64 = AirGap.newID()) {
        guard let request = AirGap.signRequest(publicKey: publicKey, forged: forged, id: id) else { return nil }
        self.address = address
        self.forged = forged
        self.id = id
        frames = UniformResource.encode(AirGap.payload(for: [request]), maximumFragment: Self.fragmentSize)
    }

    var isCollecting: Bool { !decoder.isEmpty }

    /// A code read from the camera, the clipboard or an image.
    func receive(_ text: String) {
        guard !finished else { return }
        switch QRPayload.classify(text) {
        case .uniformResource(let part):
            do {
                guard case .complete(let payload) = try decoder.receive(part) else { note = nil; return }
                decoder = UniformResource.Decoder()
                let messages = try AirGap.messages(from: payload)
                if messages.contains(where: { $0.type == AirGap.MessageType.transactionSignRequest.rawValue }) {
                    note = "That is Signet's own request. Scan it with AirGap Vault, approve it there, then hold up the code the Vault shows."
                    return
                }
                finish(.success(try AirGap.signature(in: messages, id: id, forged: forged)))
            } catch AirGap.Error.differentOperation {
                finish(.failure(AirGapSigning.Failure.differentOperation))
            } catch AirGap.Error.wrongResponse {
                note = "That AirGap code is not the Vault's reply to this request. Hold up the code the Vault shows after you approve this operation."
            } catch AirGap.Error.unsupportedVersion {
                note = "That AirGap code is in a format Signet does not read. In AirGap Vault, choose QR Code V3 under QR Details."
            } catch {
                decoder = UniformResource.Decoder()
                note = "That code could not be read as an AirGap reply. Try again."
            }
        case .airGapLegacy:
            note = "That AirGap code is in the old format. In AirGap Vault, choose QR Code V3 under QR Details."
        default:
            note = "That code is not AirGap Vault's signed reply."
        }
    }

    func cancel() { finish(.failure(AirGapSigning.Failure.cancelled)) }

    private func finish(_ result: Result<[UInt8], Error>) {
        guard !finished else { return }
        finished = true
        onFinish?(result)
    }
}

#if canImport(AppKit)
/// The panel: the request code, then the camera for the reply.
struct AirGapSignView: View {
    @Bindable var session: AirGapSignSession

    private enum CameraState { case starting, running, denied, missing }
    @State private var capture = QRCaptureSession()
    @State private var cameraState: CameraState = .starting
    @State private var devices: [CameraDevice] = []
    @State private var deviceID: String?
    @State private var frameIndex = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Sign with AirGap Vault", systemImage: "iphone.and.arrow.forward")
                .font(.title2.weight(.semibold))
            Text("Account \(Address(session.address).shortened())")
                .font(.callout.monospaced()).foregroundStyle(.secondary)

            switch session.phase {
            case .showing: requestCode
            case .scanning: replyScanner
            }

            if let note = session.note {
                Label(note, systemImage: "exclamationmark.triangle")
                    .font(.callout).foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                if session.phase == .scanning {
                    Button("Show Request Again") { show() }
                    Button("Paste from Clipboard", action: paste)
                        .keyboardShortcut("v", modifiers: .command)
                        .help("Reads the Vault's reply from a screenshot or image on the clipboard")
                }
                Spacer()
                Button("Cancel", role: .cancel) { capture.stop(); session.cancel() }
                    .keyboardShortcut(.cancelAction)
                if session.phase == .showing {
                    Button("Scan Vault's Reply") { scan() }
                        .keyboardShortcut(.defaultAction)
                        .buttonStyle(.borderedProminent)
                }
            }
        }
        .padding(20)
        .frame(width: 480)
        .task { for await code in capture.codes { session.receive(code) } }
        .onChange(of: deviceID) { if let deviceID, session.phase == .scanning, cameraState == .running { capture.start(deviceID: deviceID) } }
        .onDisappear { capture.stop() }
    }

    // MARK: The request

    private var requestCode: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Spacer()
                Group {
                    if let image = QRCode.image(for: session.frames[frameIndex % session.frames.count], size: 300, correction: "L") {
                        Image(nsImage: image).interpolation(.none)
                    }
                }
                .padding(10)
                .background(.white, in: RoundedRectangle(cornerRadius: 8))
                Spacer()
            }
            .task(id: session.frames.count) {
                guard session.frames.count > 1 else { return }
                while !Task.isCancelled {
                    try? await Task.sleep(for: .milliseconds(250))
                    frameIndex += 1
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("1. In AirGap Vault, tap Scan and point the phone at this code\(session.frames.count > 1 ? " until it has read every part" : "").")
                Text("2. Check the operation on the phone and approve it.")
                Text("3. Click Scan Vault's Reply and hold the code the Vault shows up to this Mac's camera.")
            }
            .font(.callout)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: The reply

    private var replyScanner: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 10).fill(.black.opacity(0.85))
                switch cameraState {
                case .running:
                    QRCameraPreview(session: capture.session).clipShape(RoundedRectangle(cornerRadius: 10))
                case .starting:
                    ProgressView().controlSize(.small).colorScheme(.dark)
                case .denied:
                    VStack(spacing: 10) {
                        Image(systemName: "video.slash").font(.largeTitle)
                        Text("Signet may not use the camera.")
                        Button("Open Privacy Settings…") {
                            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera") { NSWorkspace.shared.open(url) }
                        }
                    }
                    .foregroundStyle(.white.opacity(0.8))
                case .missing:
                    VStack(spacing: 10) {
                        Image(systemName: "video.slash").font(.largeTitle)
                        Text("No camera is connected. Paste a screenshot of the Vault's code instead.")
                            .multilineTextAlignment(.center)
                    }
                    .foregroundStyle(.white.opacity(0.8))
                    .padding()
                }
            }
            .frame(height: 300)

            if devices.count > 1, cameraState == .running {
                Picker("Camera", selection: $deviceID) {
                    ForEach(devices) { Text($0.name).tag(Optional($0.id)) }
                }
            }

            if session.isCollecting {
                Label {
                    Text("An animated code: \(session.decoder.receivedFragments) of \(session.decoder.expectedParts) parts read. Keep it in view.")
                } icon: {
                    ProgressView(value: session.decoder.progress).progressViewStyle(.circular).controlSize(.small)
                }
                .font(.callout)
            } else {
                Text("Hold up the signed code AirGap Vault shows after you approve. Signet checks it signs exactly this operation before sending.")
                    .font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func show() {
        capture.stop()
        session.note = nil
        session.phase = .showing
    }

    private func scan() {
        session.note = nil
        session.phase = .scanning
        Task { await startCamera() }
    }

    private func paste() {
        let texts = QRCamera.textsFromPasteboard()
        guard !texts.isEmpty else {
            session.note = "The clipboard holds no QR code image and no text."
            return
        }
        texts.forEach(session.receive)
    }

    private func startCamera() async {
        devices = QRCamera.devices()
        if deviceID == nil || !devices.contains(where: { $0.id == deviceID }) { deviceID = QRCamera.preferred(among: devices)?.id }
        guard let deviceID else { cameraState = .missing; return }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: break
        case .notDetermined:
            guard await AVCaptureDevice.requestAccess(for: .video) else { cameraState = .denied; return }
        default:
            cameraState = .denied
            return
        }
        guard session.phase == .scanning else { return }
        capture.start(deviceID: deviceID)
        cameraState = .running
    }
}
#endif
