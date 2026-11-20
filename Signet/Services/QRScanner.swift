import AppKit
@preconcurrency import AVFoundation
import Vision

/// A camera the scanner can use.
struct CameraDevice: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
}

enum QRCamera {
    /// Built-in, external (USB, display) and Continuity cameras; not Desk View, which looks at
    /// the table.
    static func devices() -> [CameraDevice] {
        discovery().devices.map { CameraDevice(id: $0.uniqueID, name: $0.localizedName) }
    }

    /// The camera the user chose in the system's video menu when it is one of ours, else the first.
    static func preferred(among devices: [CameraDevice]) -> CameraDevice? {
        if let chosen = AVCaptureDevice.userPreferredCamera, let match = devices.first(where: { $0.id == chosen.uniqueID }) { return match }
        return devices.first
    }

    fileprivate static func discovery() -> AVCaptureDevice.DiscoverySession {
        AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInWideAngleCamera, .external, .continuityCamera], mediaType: .video, position: .unspecified)
    }

    /// The QR code in an image on the pasteboard, or the pasteboard's text when it holds no
    /// image: a screenshot of a code and a copied code are both worth reading.
    @MainActor static func textFromPasteboard(_ pasteboard: NSPasteboard = .general) -> String? {
        textsFromPasteboard(pasteboard).first
    }

    /// The same, with every code of an image that shows several (a recovery sheet's page of parts).
    @MainActor static func textsFromPasteboard(_ pasteboard: NSPasteboard = .general) -> [String] {
        if let image = NSImage(pasteboard: pasteboard) {
            let codes = QRCode.decodeAll(image)
            if !codes.isEmpty { return codes }
        }
        return pasteboard.string(forType: .string).map { [$0] } ?? []
    }
}

/// Tells the model whether a camera is attached, now and as cameras come and go (a webcam
/// plugged in, an iPhone coming into range as a Continuity Camera, a lid closed). The app makes
/// one and keeps it for as long as it runs.
@MainActor
final class CameraWatcher {
    private var observers: [NSObjectProtocol] = []

    init(onChange: @escaping @MainActor (Bool) -> Void) {
        let report = { onChange(!QRCamera.devices().isEmpty) }
        for name in [AVCaptureDevice.wasConnectedNotification, AVCaptureDevice.wasDisconnectedNotification] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated(report)
            })
        }
        report()
    }
}

/// Reads QR codes from a camera: frames go to Vision on a private queue and each distinct code
/// is yielded on `codes`. Nothing is recorded, kept or logged; a code may be a secret key.
final class QRCaptureSession: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    let session = AVCaptureSession()
    let codes: AsyncStream<String>

    private let continuation: AsyncStream<String>.Continuation
    private let queue = DispatchQueue(label: "org.tezos.signet.qr-capture")
    // Touched on `queue` only.
    private var output: AVCaptureVideoDataOutput?
    private var seen: [String: Date] = [:]

    override init() {
        (codes, continuation) = AsyncStream.makeStream(of: String.self, bufferingPolicy: .bufferingNewest(32))
        super.init()
    }

    /// Starts (or switches to) the camera with this id.
    func start(deviceID: String) {
        queue.async { [self] in
            session.beginConfiguration()
            session.inputs.forEach(session.removeInput)
            if let device = AVCaptureDevice(uniqueID: deviceID), let input = try? AVCaptureDeviceInput(device: device), session.canAddInput(input) {
                session.addInput(input)
            }
            if output == nil {
                let output = AVCaptureVideoDataOutput()
                output.alwaysDiscardsLateVideoFrames = true
                output.setSampleBufferDelegate(self, queue: queue)
                if session.canAddOutput(output) {
                    session.addOutput(output)
                    self.output = output
                }
            }
            session.commitConfiguration()
            seen = [:]
            if !session.isRunning { session.startRunning() }
        }
    }

    /// Stops the camera; its light goes out.
    func stop() {
        queue.async { [self] in
            if session.isRunning { session.stopRunning() }
            seen = [:]
        }
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pixels = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let request = VNDetectBarcodesRequest()
        request.symbologies = [.qr]
        guard (try? VNImageRequestHandler(cvPixelBuffer: pixels).perform([request])) != nil else { return }
        // Every code in view is reported (a recovery sheet can show several parts of one key at
        // once). A code stays in view for many frames; say it once, and again after a pause so
        // a code the sheet could not use can be tried again.
        let now = Date()
        seen = seen.filter { now.timeIntervalSince($0.value) <= 3 }
        for code in request.results?.compactMap(\.payloadStringValue) ?? [] where seen[code] == nil {
            seen[code] = now
            continuation.yield(code)
        }
    }
}
