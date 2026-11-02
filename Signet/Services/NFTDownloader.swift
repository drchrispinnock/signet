import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Saves an NFT's artwork to disk: the full artifact (the video, sound or full-size image the
/// token points at), or the display image when the metadata names no artifact. Content comes
/// through the pinned public client like the tiles do, one gateway after another, and lands
/// in the `nfts` folder of the wallet directory under a name made of the token's name, its
/// contract and its id, so every token has one file and a second download replaces the first.
struct NFTDownloader: Sendable {
    /// The largest artwork saved: videos run to tens of megabytes, generative pieces more.
    static let maxBytes = 256 << 20
    static let folderName = "nfts"

    enum Failure: Error, LocalizedError, Equatable {
        /// The metadata names neither an artifact nor an image.
        case noArtwork
        /// The content is larger than `maxBytes` on every gateway.
        case tooLarge
        /// No gateway served it.
        case unavailable

        var errorDescription: String? {
            switch self {
            case .noArtwork: "The token's metadata names no artwork"
            case .tooLarge: "The artwork is larger than \(NFTDownloader.maxBytes >> 20) MB"
            case .unavailable: "The artwork could not be fetched"
            }
        }
    }

    struct Fetched: Sendable {
        let data: Data
        let contentType: String?
    }

    typealias Fetch = @Sendable (URL) async throws -> Fetched

    /// Where the files go.
    let directory: URL
    private let fetch: Fetch

    /// The downloads folder beside a wallet directory's key files.
    static func directory(under walletDirectory: URL) -> URL {
        walletDirectory.appendingPathComponent(folderName, isDirectory: true)
    }

    init(directory: URL, fetch: Fetch? = nil) {
        self.directory = directory
        self.fetch = fetch ?? Self.publicFetch
    }

    /// Downloads `nft`'s artwork and returns the file it was written to.
    func download(_ nft: NFT) async throws -> URL {
        let usesArtifact = !nft.artifactURLs.isEmpty
        let candidates = usesArtifact ? nft.artifactURLs : nft.imageURLs
        guard !candidates.isEmpty else { throw Failure.noArtwork }
        var fetched: Fetched?
        var from: URL?
        for url in candidates {
            try Task.checkCancellation()
            do {
                fetched = try await fetch(url)
                from = url
                break
            } catch let error as URLError where error.code == .dataLengthExceedsMaximum {
                // The same content sits behind every gateway: another one will not be smaller.
                throw Failure.tooLarge
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                continue
            }
        }
        guard let fetched, let from else { throw Failure.unavailable }
        let name = Self.fileName(for: nft, contentType: fetched.contentType, declaredType: usesArtifact ? nft.artifactMime : nil, url: from)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent(name, isDirectory: false)
        try fetched.data.write(to: file, options: .atomic)
        return file
    }

    // MARK: Naming

    /// `<name> (<contract> <id>).<ext>`: readable, unique per token, and safe as a file name.
    static func fileName(for nft: NFT, contentType: String?, declaredType: String?, url: URL?) -> String {
        let ext = fileExtension(contentType: contentType, declaredType: declaredType, url: url)
        return "\(sanitised(nft.name)) (\(nft.contract) \(nft.tokenId)).\(ext)"
    }

    /// A token's name as a file name: no path separators or control characters, no leading
    /// dot, at most 80 characters, "NFT" when nothing is left.
    static func sanitised(_ name: String) -> String {
        var cleaned = name.unicodeScalars.map { scalar -> Character in
            if scalar == "/" || scalar == ":" || scalar == "\\" { return "-" }
            if CharacterSet.controlCharacters.contains(scalar) || CharacterSet.newlines.contains(scalar) { return " " }
            return Character(scalar)
        }
        while cleaned.count > 80 { cleaned.removeLast() }
        var result = String(cleaned).trimmingCharacters(in: .whitespacesAndNewlines)
        while result.hasPrefix(".") { result.removeFirst() }
        return result.isEmpty ? "NFT" : result
    }

    /// The extension the content deserves: from the gateway's content type when it is a real
    /// one, else the type the metadata declares, else the URL's own extension, else `bin`.
    static func fileExtension(contentType: String?, declaredType: String?, url: URL?) -> String {
        for type in [contentType, declaredType] {
            if let ext = extensions[mime(type)] { return ext }
        }
        if let ext = url?.pathExtension.lowercased(), !ext.isEmpty, ext.count <= 5, ext.allSatisfy({ $0.isLetter || $0.isNumber }) {
            return ext
        }
        return "bin"
    }

    /// `image/png; charset=binary` → `image/png`.
    private static func mime(_ type: String?) -> String {
        (type ?? "").lowercased().split(separator: ";").first.map { $0.trimmingCharacters(in: .whitespaces) } ?? ""
    }

    /// What NFTs on Tezos are made of; `application/octet-stream` is deliberately absent so a
    /// gateway that does not know the type falls through to the metadata and the URL.
    private static let extensions: [String: String] = [
        "image/png": "png", "image/jpeg": "jpg", "image/jpg": "jpg", "image/gif": "gif", "image/webp": "webp",
        "image/svg+xml": "svg", "image/avif": "avif", "image/bmp": "bmp", "image/tiff": "tiff", "image/heic": "heic",
        "video/mp4": "mp4", "video/quicktime": "mov", "video/webm": "webm", "video/x-matroska": "mkv", "video/ogg": "ogv",
        "audio/mpeg": "mp3", "audio/mp3": "mp3", "audio/wav": "wav", "audio/x-wav": "wav", "audio/ogg": "ogg",
        "audio/flac": "flac", "audio/aac": "aac", "audio/mp4": "m4a",
        "model/gltf-binary": "glb", "model/gltf+json": "gltf", "application/pdf": "pdf", "text/html": "html",
        "application/x-directory": "zip", "application/zip": "zip", "application/json": "json", "text/plain": "txt",
    ]

    // MARK: Network

    /// The pinned public client, as the tiles use it, with the download's own size cap.
    private static let publicFetch: Fetch = { url in
        let reply = try await PublicHTTPClient.data(for: URLRequest(url: url), limit: maxBytes, followRedirects: true)
        guard (200..<300).contains(reply.status) else { throw URLError(.badServerResponse) }
        return Fetched(data: reply.data, contentType: reply.headers["content-type"])
    }
}
