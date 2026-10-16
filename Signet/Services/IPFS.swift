import Foundation

enum IPFS {
    /// Public gateways in the order we try them. ipfs.io and dweb.link rate-limit aggressively
    /// (HTTP 429) so they are last resorts; Filebase has been fast and reliable.
    static let gateways: [URL] = [
        URL(string: "https://ipfs.filebase.io/ipfs/")!,
        URL(string: "https://gateway.pinata.cloud/ipfs/")!,
        URL(string: "https://ipfs.io/ipfs/")!,
    ]

    /// A content path as it is appended to a gateway: the CID, then zero or more path components
    /// (each percent-encoded, none empty, `.` or `..`), then an optional query. Built only through
    /// `validated`, so a path from token metadata cannot climb out of `/ipfs/` on the gateway.
    struct ContentPath: Equatable, Sendable {
        let cid: String
        let components: [String]
        /// `ipfs://<cid>/` keeps its slash: some gateways treat the directory index differently without it.
        var trailingSlash = false
        let query: String?

        /// `cid/a/b?query`, the components percent-encoded.
        var encoded: String {
            let allowed = CharacterSet.urlPathAllowed.subtracting(CharacterSet(charactersIn: "/;"))
            let encodedComponents = components.map { $0.addingPercentEncoding(withAllowedCharacters: allowed) ?? "" }
            var text = ([cid] + encodedComponents).joined(separator: "/")
            if trailingSlash { text += "/" }
            if let query { text += "?" + query }
            return text
        }

        /// Validates `<cid>[/path][?query]` as it appears after `ipfs://` or `/ipfs/` on a gateway.
        static func validated(_ raw: String) -> ContentPath? {
            var rest = raw
            if let hash = rest.firstIndex(of: "#") { rest = String(rest[..<hash]) }
            var query: String?
            if let mark = rest.firstIndex(of: "?") {
                let q = String(rest[rest.index(after: mark)...])
                rest = String(rest[..<mark])
                let allowed = CharacterSet.urlQueryAllowed.subtracting(CharacterSet(charactersIn: "#"))
                guard q.unicodeScalars.allSatisfy(allowed.contains) else { return nil }
                query = q.isEmpty ? nil : q
            }
            var parts = rest.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
            // A trailing slash (`ipfs://Qm…/`) is fine; an empty component anywhere else is not.
            var trailingSlash = false
            if parts.count > 1, parts.last == "" { parts.removeLast(); trailingSlash = true }
            guard let cid = parts.first, looksLikeCID(cid) else { return nil }
            let components = Array(parts.dropFirst())
            guard components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." && !$0.contains("\\") && $0.removingPercentEncoding != "." && $0.removingPercentEncoding != ".." }),
                  components.allSatisfy({ $0.removingPercentEncoding?.contains("/") != true }) else { return nil }
            return ContentPath(cid: cid, components: components, trailingSlash: trailingSlash, query: query)
        }
    }

    /// The `<cid>[/path]` part of an `ipfs://` URI (also accepts `ipfs://ipfs/<cid>`), or `nil`.
    static func path(of uri: String) -> String? {
        contentPath(of: uri)?.encoded
    }

    static func contentPath(of uri: String) -> ContentPath? {
        let trimmed = uri.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.lowercased().hasPrefix("ipfs://") else { return nil }
        var path = String(trimmed.dropFirst("ipfs://".count))
        if path.hasPrefix("ipfs/") { path.removeFirst("ipfs/".count) }
        return path.isEmpty ? nil : ContentPath.validated(path)
    }

    /// The `<cid>[/path]` behind an HTTP(S) gateway URL, in either the path form
    /// (`https://host/ipfs/<cid>/x`) or the subdomain form (`https://<cid>.ipfs.host/x`), or `nil`.
    static func gatewayContentPath(of url: URL) -> ContentPath? {
        let components = url.pathComponents.filter { $0 != "/" }
        let query = url.query.map { "?" + $0 } ?? ""
        if let index = components.firstIndex(of: "ipfs"), index + 1 < components.count {
            return ContentPath.validated(components[(index + 1)...].joined(separator: "/") + query)
        }
        let labels = (url.host() ?? "").split(separator: ".")
        if labels.count >= 3, labels[1] == "ipfs", Self.looksLikeCID(String(labels[0])) {
            let rest = components.joined(separator: "/")
            return ContentPath.validated(rest.isEmpty ? String(labels[0]) + query : "\(labels[0])/\(rest)" + query)
        }
        return nil
    }

    /// `/ipfs/` in the path, or a `<cid>.ipfs.` subdomain: the URL names IPFS content.
    static func looksLikeGatewayURL(_ url: URL) -> Bool {
        if url.pathComponents.contains("ipfs") { return true }
        let labels = (url.host() ?? "").split(separator: ".")
        return labels.count >= 3 && labels[1] == "ipfs"
    }

    /// CIDv0 (`Qm…`, 46 base58 chars) or CIDv1 base32 (`b…`, lower-case letters and digits).
    static func looksLikeCID(_ text: String) -> Bool {
        if text.hasPrefix("Qm") {
            return text.count == 46 && text.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber) && !"0OIl".contains($0) }
        }
        return text.hasPrefix("b") && text.count >= 50 && text.allSatisfy { $0.isASCII && (($0.isLetter && $0.isLowercase) || ("2"..."7").contains($0)) }
    }

    /// `path` appended to a gateway, if the result still points at that gateway's `/ipfs/`.
    private static func gatewayURL(_ gateway: URL, _ path: ContentPath) -> URL? {
        guard let url = URL(string: gateway.absoluteString + path.encoded), url.host() == gateway.host(),
              url.pathComponents.filter({ $0 != "/" }).prefix(2) == ["ipfs", path.cid] else { return nil }
        return url
    }

    /// Every HTTPS URL worth trying for `uri`, best first. An `ipfs://` URI yields one URL per
    /// gateway. An HTTP(S) URL on some other IPFS gateway is widened to our gateways too, with
    /// the original last (public gateways such as dweb.link rate-limit, HTTP 429). Any other
    /// URL passes through as the only candidate when it is HTTPS to a public host; anything
    /// else (http, credentials, loopback, link-local, private ranges, local names) yields none,
    /// so token metadata cannot make the wallet poke at services on this machine or its network.
    static func candidateURLs(for uri: String) -> [URL] {
        if let path = contentPath(of: uri) {
            return gateways.compactMap { gatewayURL($0, path) }
        }
        let trimmed = uri.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http" else { return [] }
        if looksLikeGatewayURL(url) {
            // A gateway URL whose content path does not validate is not tried at all.
            guard let path = gatewayContentPath(of: url) else { return [] }
            var urls = gateways.compactMap { gatewayURL($0, path) }
            if EndpointPolicy.isPublicHTTPS(url), !urls.contains(url) { urls.append(url) }
            return urls
        }
        return EndpointPolicy.isPublicHTTPS(url) ? [url] : []
    }

    /// The preferred HTTPS URL for `uri`, or `nil`.
    static func httpURL(for uri: String) -> URL? {
        candidateURLs(for: uri).first
    }
}
