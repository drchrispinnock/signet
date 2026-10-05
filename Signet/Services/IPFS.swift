import Foundation

enum IPFS {
    /// Public gateways in the order we try them. ipfs.io and dweb.link rate-limit aggressively
    /// (HTTP 429) so they are last resorts; Filebase has been fast and reliable.
    static let gateways: [URL] = [
        URL(string: "https://ipfs.filebase.io/ipfs/")!,
        URL(string: "https://gateway.pinata.cloud/ipfs/")!,
        URL(string: "https://ipfs.io/ipfs/")!,
    ]

    /// The `<cid>[/path]` part of an `ipfs://` URI (also accepts `ipfs://ipfs/<cid>`), or `nil`.
    static func path(of uri: String) -> String? {
        let trimmed = uri.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("ipfs://") else { return nil }
        var path = String(trimmed.dropFirst("ipfs://".count))
        if path.hasPrefix("ipfs/") { path.removeFirst("ipfs/".count) }
        return path.isEmpty ? nil : path
    }

    /// Every HTTPS URL worth trying for `uri`, best first. An `ipfs://` URI yields one URL per
    /// gateway; an HTTP(S) URL passes through as the only candidate; anything else yields none.
    static func candidateURLs(for uri: String) -> [URL] {
        if let path = path(of: uri) {
            return gateways.compactMap { URL(string: path, relativeTo: $0)?.absoluteURL }
        }
        let trimmed = uri.trimmingCharacters(in: .whitespacesAndNewlines)
        if let url = URL(string: trimmed), let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http" {
            return [url]
        }
        return []
    }

    /// The preferred HTTPS URL for `uri`, or `nil`.
    static func httpURL(for uri: String) -> URL? {
        candidateURLs(for: uri).first
    }
}
