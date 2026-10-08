import AppKit
import Foundation
import ImageIO

/// Downloads an image from the first URL that works and downsamples it for display.
/// Decoded images are cached in memory; the shared URLCache keeps the bytes.
actor ImageLoader {
    static let shared = ImageLoader()

    private let cache = NSCache<NSString, NSImage>()
    private var inFlight: [String: Task<NSImage?, Never>] = [:]
    private let session: URLSession

    init() {
        let config = URLSessionConfiguration.default
        config.urlCache = URLCache(memoryCapacity: 64 << 20, diskCapacity: 512 << 20, diskPath: "org.tezos.signet.images")
        config.requestCachePolicy = .returnCacheDataElseLoad
        config.timeoutIntervalForRequest = 20
        config.httpMaximumConnectionsPerHost = 4
        session = URLSession(configuration: config)
        cache.countLimit = 300
    }

    /// Tries `candidates` in order; returns the first that yields a decodable image.
    func image(for candidates: [URL], maxPixelSize: Int = 400) async -> NSImage? {
        guard let key = candidates.first?.absoluteString else { return nil }
        if let cached = cache.object(forKey: key as NSString) { return cached }
        if let task = inFlight[key] { return await task.value }

        let task = Task<NSImage?, Never> { [session] in
            for url in candidates {
                guard !Task.isCancelled else { return nil }
                do {
                    let (data, response) = try await session.data(from: url)
                    guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { continue }
                    if let image = Self.downsample(data, maxPixelSize: maxPixelSize) { return image }
                } catch {
                    continue
                }
            }
            return nil
        }
        inFlight[key] = task
        let image = await task.value
        inFlight[key] = nil
        if let image { cache.setObject(image, forKey: key as NSString) }
        return image
    }

    /// Decodes at most `maxPixelSize` on the long edge so a grid of large artworks stays cheap.
    /// ImageIO does not read SVG (common for token logos), so those go through NSImage instead.
    nonisolated static func downsample(_ data: Data, maxPixelSize: Int) -> NSImage? {
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
        guard let image = NSImage(data: data), image.size.width > 0, image.size.height > 0 else { return nil }
        return image
    }
}
