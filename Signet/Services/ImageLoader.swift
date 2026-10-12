import AppKit
import Foundation
import ImageIO

/// Downloads an image from the first URL that works and downsamples it for display.
/// Decoded images are cached in memory; the shared URLCache keeps the bytes.
///
/// Artwork URLs come from token metadata, so they are untrusted (S13): only public HTTPS
/// destinations are contacted (checked by name and again after DNS resolution), redirects
/// may only lead to other public HTTPS destinations, the response must be an image, and the
/// download is cut off at `maxBytes` while it streams. At most `maxConcurrent` loads run at once.
actor ImageLoader {
    static let shared = ImageLoader()

    /// The most a single artwork may download; a thumbnail never needs more.
    static let maxBytes = 8 << 20
    static let maxConcurrent = 6

    private let cache = NSCache<NSString, NSImage>()
    private let downloader: @Sendable (URL) async -> Data?
    private var inFlight: [String: Task<NSImage?, Never>] = [:]
    private var active = 0
    private var waiting: [CheckedContinuation<Void, Never>] = []

    init(download: (@Sendable (URL) async -> Data?)? = nil) {
        downloader = download ?? { await ImageLoader.download($0) }
        cache.countLimit = 300
        cache.totalCostLimit = 96 << 20
    }

    /// Tries `candidates` in order; returns the first that yields a decodable image.
    func image(for candidates: [URL], maxPixelSize: Int = 400) async -> NSImage? {
        guard let key = candidates.first?.absoluteString else { return nil }
        if let cached = cache.object(forKey: key as NSString) { return cached }
        if let task = inFlight[key] { return await task.value }

        guard inFlight.count < 128, candidates.count <= 16 else { return nil }
        let maxPixelSize = min(max(1, maxPixelSize), 2048)
        let task = Task<NSImage?, Never> {
            await self.acquireSlot()
            defer { self.releaseSlot() }
            for url in candidates {
                guard !Task.isCancelled else { return nil }
                guard EndpointPolicy.isPublicHTTPS(url) else { continue }
                guard let data = await downloader(url) else { continue }
                if let image = Self.downsample(data, maxPixelSize: maxPixelSize) { return image }
            }
            return nil
        }
        inFlight[key] = task
        let image = await task.value
        inFlight[key] = nil
        if let image { cache.setObject(image, forKey: key as NSString, cost: Self.cost(of: image)) }
        return image
    }

    /// Bytes an image roughly occupies once decoded, for the cache's cost limit.
    nonisolated static func cost(of image: NSImage) -> Int {
        let pixels = image.representations.map { $0.pixelsWide * $0.pixelsHigh }.max() ?? Int(image.size.width * image.size.height)
        return max(1, pixels * 4)
    }

    private func acquireSlot() async {
        if active < Self.maxConcurrent { active += 1; return }
        await withCheckedContinuation { waiting.append($0) }
    }

    private func releaseSlot() {
        if !waiting.isEmpty { waiting.removeFirst().resume() }
        else { active -= 1 }
    }

    // MARK: Bounded download

    /// Is this response worth reading? 2xx, an image (or SVG) and not declared larger than the limit.
    nonisolated static func acceptsResponse(status: Int, contentType: String?, contentLength: Int64?, maxBytes: Int = ImageLoader.maxBytes) -> Bool {
        guard (200..<300).contains(status) else { return false }
        if let contentLength, contentLength > Int64(maxBytes) { return false }
        let type = (contentType ?? "").lowercased().split(separator: ";").first.map { $0.trimmingCharacters(in: .whitespaces) } ?? ""
        // Gateways sometimes serve artwork as octet-stream; the decoder is the final judge then.
        return type.hasPrefix("image/") || type == "application/octet-stream" || type == "application/xml" || type == "text/xml" || type.isEmpty
    }

    /// Downloads `url` with the per-task policy delegate; `nil` on any refusal or failure.
    private static func download(_ url: URL) async -> Data? {
        do {
            let reply = try await PublicHTTPClient.data(for: URLRequest(url: url), limit: maxBytes, followRedirects: true)
            guard acceptsResponse(status: reply.status, contentType: reply.headers["content-type"], contentLength: Int64(reply.data.count)) else { return nil }
            return reply.data
        } catch { return nil }
    }

    /// Decodes at most `maxPixelSize` on the long edge so a grid of large artworks stays cheap.
    /// ImageIO does not read SVG (common for token logos), so those go through NSImage instead.
    nonisolated static func downsample(_ data: Data, maxPixelSize: Int) -> NSImage? {
        guard data.count <= maxBytes else { return nil }
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return svg(data) }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return svg(data) }
        return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
    }

    /// An SVG document as a (vector) NSImage, or `nil` if the data is not one.
    nonisolated static func svg(_ data: Data) -> NSImage? {
        guard let head = String(data: data.prefix(512), encoding: .utf8)?.lowercased(), head.contains("<svg") || head.contains("<?xml") else { return nil }
        guard let image = NSImage(data: data), image.size.width > 0, image.size.height > 0, image.size.width <= 16384, image.size.height <= 16384 else { return nil }
        return image
    }
}
