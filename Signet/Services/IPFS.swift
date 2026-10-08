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

    /// The `<cid>[/path]` behind an HTTP(S) gateway URL, in either the path form
    /// (`https://host/ipfs/<cid>/x`) or the subdomain form (`https://<cid>.ipfs.host/x`), or `nil`.
    static func gatewayPath(of url: URL) -> String? {
        let components = url.pathComponents.filter { $0 != "/" }
        if let index = components.firstIndex(of: "ipfs"), index + 1 < components.count {
            return components[(index + 1)...].joined(separator: "/")
        }
        let labels = (url.host() ?? "").split(separator: ".")
        if labels.count >= 3, labels[1] == "ipfs", Self.looksLikeCID(String(labels[0])) {
            let rest = components.joined(separator: "/")
            return rest.isEmpty ? String(labels[0]) : "\(labels[0])/\(rest)"
        }
        return nil
    }

    /// CIDv0 (`Qm…`, 46 chars) or CIDv1 base32 (`b…`).
    static func looksLikeCID(_ text: String) -> Bool {
        (text.hasPrefix("Qm") && text.count == 46) || (text.hasPrefix("b") && text.count >= 50 && text.allSatisfy { $0.isLetter || $0.isNumber })
    }

    /// Every HTTPS URL worth trying for `uri`, best first. An `ipfs://` URI yields one URL per
    /// gateway. An HTTP(S) URL on some other IPFS gateway is widened to our gateways too, with
    /// the original last (public gateways such as dweb.link rate-limit, HTTP 429). Any other
    /// HTTP(S) URL passes through as the only candidate; anything else yields none.
    static func candidateURLs(for uri: String) -> [URL] {
        if let path = path(of: uri) {
            return gateways.compactMap { URL(string: path, relativeTo: $0)?.absoluteURL }
        }
        let trimmed = uri.trimmingCharacters(in: .whitespacesAndNewlines)
        if let url = URL(string: trimmed), let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http" {
            if let path = gatewayPath(of: url) {
                var urls = gateways.compactMap { URL(string: path, relativeTo: $0)?.absoluteURL }
                if !urls.contains(url) { urls.append(url) }
                return urls
            }
            return [url]
        }
        return []
    }

    /// The preferred HTTPS URL for `uri`, or `nil`.
    static func httpURL(for uri: String) -> URL? {
        candidateURLs(for: uri).first
    }
}
