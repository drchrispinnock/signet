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
    private var inFlight: [String: Task<NSImage?, Never>] = [:]
    private let session: URLSession
    private var active = 0
    private var waiting: [CheckedContinuation<Void, Never>] = []

    init() {
        let config = URLSessionConfiguration.default
        config.urlCache = URLCache(memoryCapacity: 64 << 20, diskCapacity: 512 << 20, diskPath: "org.tezos.signet.images")
        config.requestCachePolicy = .returnCacheDataElseLoad
        config.timeoutIntervalForRequest = 20
        config.timeoutIntervalForResource = 60
        config.httpMaximumConnectionsPerHost = 4
        config.httpShouldSetCookies = false
        config.httpCookieAcceptPolicy = .never
        session = URLSession(configuration: config)
        cache.countLimit = 300
        cache.totalCostLimit = 96 << 20
    }

    /// Tries `candidates` in order; returns the first that yields a decodable image.
    func image(for candidates: [URL], maxPixelSize: Int = 400) async -> NSImage? {
        guard let key = candidates.first?.absoluteString else { return nil }
        if let cached = cache.object(forKey: key as NSString) { return cached }
        if let task = inFlight[key] { return await task.value }

        let task = Task<NSImage?, Never> { [session] in
            for url in candidates {
                guard !Task.isCancelled else { return nil }
                guard EndpointPolicy.isPublicHTTPS(url), let host = url.host() else { continue }
                // Resolve off the cooperative pool: getaddrinfo blocks.
                let publicHost = await Task.detached(priority: .utility) { EndpointPolicy.resolvesPublicly(host) }.value
                guard publicHost else { continue }
                guard let data = await Self.download(url, with: session) else { continue }
                if let image = Self.downsample(data, maxPixelSize: maxPixelSize) { return image }
            }
            return nil
        }
        inFlight[key] = task
        await acquireSlot()
        let image = await task.value
        releaseSlot()
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
        active += 1
    }

    private func releaseSlot() {
        active -= 1
        if !waiting.isEmpty { waiting.removeFirst().resume() }
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
    private static func download(_ url: URL, with session: URLSession) async -> Data? {
        await withCheckedContinuation { continuation in
            let delegate = BoundedDownload(maxBytes: maxBytes, continuation: continuation)
            var request = URLRequest(url: url)
            request.setValue("image/*", forHTTPHeaderField: "Accept")
            let task = session.dataTask(with: request)
            task.delegate = delegate
            task.resume()
        }
    }

    /// Streams one artwork download: refuses redirects to anywhere but public HTTPS, non-image
    /// responses and anything past `maxBytes`, cancelling the task as soon as a rule is broken.
    private final class BoundedDownload: NSObject, URLSessionDataDelegate, @unchecked Sendable {
        private let maxBytes: Int
        private let lock = NSLock()
        private var data = Data()
        private var refused = false
        private var continuation: CheckedContinuation<Data?, Never>?

        init(maxBytes: Int, continuation: CheckedContinuation<Data?, Never>) {
            self.maxBytes = maxBytes
            self.continuation = continuation
        }

        private func finish(_ result: Data?) {
            let c: CheckedContinuation<Data?, Never>? = lock.withLock { let c = continuation; continuation = nil; return c }
            c?.resume(returning: result)
        }

        func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
            guard let next = request.url, EndpointPolicy.isPublicHTTPS(next), let host = next.host(), EndpointPolicy.resolvesPublicly(host) else {
                lock.withLock { refused = true }
                completionHandler(nil)
                task.cancel()
                return
            }
            var redirected = request
            redirected.setValue("image/*", forHTTPHeaderField: "Accept")
            completionHandler(redirected)
        }

        func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping @Sendable (URLSession.ResponseDisposition) -> Void) {
            let http = response as? HTTPURLResponse
            let length = response.expectedContentLength >= 0 ? response.expectedContentLength : nil
            guard let http, ImageLoader.acceptsResponse(status: http.statusCode, contentType: http.value(forHTTPHeaderField: "Content-Type"), contentLength: length, maxBytes: maxBytes) else {
                lock.withLock { refused = true }
                completionHandler(.cancel)
                return
            }
            completionHandler(.allow)
        }

        func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive chunk: Data) {
            let over: Bool = lock.withLock {
                data.append(chunk)
                return data.count > maxBytes
            }
            if over {
                lock.withLock { refused = true }
                dataTask.cancel()
            }
        }

        func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
            let (result, wasRefused): (Data, Bool) = lock.withLock { (data, refused) }
            finish(error == nil && !wasRefused && !result.isEmpty ? result : nil)
        }
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
        guard let image = NSImage(data: data), image.size.width > 0, image.size.height > 0 else { return nil }
        return image
    }
}
