import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins

enum QRCode {
    /// A crisp QR code for `text`, rendered at `size` points without smoothing.
    static func image(for text: String, size: CGFloat = 240, correction: String = "M") -> NSImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = correction
        guard let output = filter.outputImage else { return nil }

        // Scale the tiny module grid up with nearest-neighbour so squares stay sharp.
        let scale = size / output.extent.width
        let scaled = output.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let context = CIContext(options: [.useSoftwareRenderer: false])
        guard let cgImage = context.createCGImage(scaled, from: scaled.extent) else { return nil }
        return NSImage(cgImage: cgImage, size: NSSize(width: size, height: size))
    }

    /// Decodes the first QR code found in `image`, for tests and round-trip checks.
    static func decode(_ image: NSImage) -> String? {
        guard let tiff = image.tiffRepresentation, let ciImage = CIImage(data: tiff) else { return nil }
        let detector = CIDetector(ofType: CIDetectorTypeQRCode, context: nil, options: [CIDetectorAccuracy: CIDetectorAccuracyHigh])
        return detector?.features(in: ciImage).compactMap { ($0 as? CIQRCodeFeature)?.messageString }.first
    }
}
