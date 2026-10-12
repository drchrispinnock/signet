import Foundation

/// Where the app is allowed to send requests on behalf of untrusted input (a dApp's RPC, a
/// token's artwork URL). Local and private destinations are refused unless the caller says the
/// user chose them deliberately, so a metadata or request field cannot make the wallet poke at
/// services on this machine or its network (S12, S13).
enum EndpointPolicy {
    enum Verdict: Equatable, Sendable {
        case allowed
        case notHTTPS
        case hasUserInfo
        case noHost
        case localOrPrivate(String)
    }

    /// Hosts that are this machine or an internal name: refused for untrusted destinations.
    static func isLocalOrPrivateHost(_ rawHost: String) -> Bool {
        let host = rawHost.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
        if host.isEmpty || host == "localhost" || host.hasSuffix(".localhost") || host.hasSuffix(".local")
            || host.hasSuffix(".internal") || host.hasSuffix(".home.arpa") || host.hasSuffix(".lan") || !host.contains(".") && !host.contains(":") {
            return true
        }
        if let v4 = ipv4(host) { return isPrivateIPv4(v4) }
        if host.contains(":") { return isPrivateIPv6(host) }
        return false
    }

    /// `https`, with a host, without credentials, and not local or private.
    static func check(_ url: URL, allowHTTP: Bool = false) -> Verdict {
        guard let scheme = url.scheme?.lowercased(), scheme == "https" || (allowHTTP && scheme == "http") else { return .notHTTPS }
        if url.user != nil || url.password != nil { return .hasUserInfo }
        guard let host = url.host(percentEncoded: false), !host.isEmpty else { return .noHost }
        if isLocalOrPrivateHost(host) { return .localOrPrivate(host) }
        return .allowed
    }

    /// A public HTTPS destination fit for untrusted input.
    static func isPublicHTTPS(_ url: URL) -> Bool { check(url) == .allowed }

    /// Resolves the host and refuses any address in a private range: a public-looking name that
    /// points at this machine or the LAN (DNS rebinding, split-horizon) is caught here. Blocking;
    /// call it off the main actor. Hosts that do not resolve are refused too.
    static func resolvesPublicly(_ host: String) -> Bool { !publicAddresses(host).isEmpty }

    static func publicAddresses(_ host: String) -> [String] {
        if isLocalOrPrivateHost(host) { return [] }
        var hints = addrinfo()
        hints.ai_socktype = SOCK_STREAM
        var result: UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo(host, nil, &hints, &result) == 0, let first = result else { return [] }
        defer { freeaddrinfo(first) }
        var pointer: UnsafeMutablePointer<addrinfo>? = first
        var addresses: [String] = []
        while let info = pointer {
            guard let text = numericAddress(info), !isLocalOrPrivateHost(text) else { return [] }
            if !addresses.contains(text) { addresses.append(text) }
            pointer = info.pointee.ai_next
        }
        return addresses
    }

    private static func numericAddress(_ info: UnsafeMutablePointer<addrinfo>) -> String? {
        var buffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
        guard getnameinfo(info.pointee.ai_addr, info.pointee.ai_addrlen, &buffer, socklen_t(buffer.count), nil, 0, NI_NUMERICHOST) == 0 else { return nil }
        return String(cString: buffer)
    }

    // MARK: Address ranges

    static func ipv4(_ host: String) -> [UInt8]? {
        let parts = host.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return nil }
        var bytes: [UInt8] = []
        for part in parts {
            guard !part.isEmpty, part.count <= 3, part.allSatisfy(\.isNumber), let value = UInt8(part) else { return nil }
            bytes.append(value)
        }
        return bytes
    }

    /// Loopback, link-local, RFC 1918, CGNAT, "this network", broadcast and multicast.
    static func isPrivateIPv4(_ b: [UInt8]) -> Bool {
        switch (b[0], b[1]) {
        case (0, _), (10, _), (127, _): return true
        case (169, 254), (192, 168): return true
        case (172, 16...31): return true
        case (100, 64...127): return true
        case (224...255, _): return true
        default: return false
        }
    }

    /// Loopback, unspecified, unique-local, link-local, multicast and IPv4-mapped private addresses.
    static func isPrivateIPv6(_ host: String) -> Bool {
        var text = host.lowercased()
        if let zone = text.firstIndex(of: "%") { text = String(text[..<zone]) }
        if text == "::1" || text == "::" { return true }
        if let mapped = text.range(of: "::ffff:"), mapped.lowerBound == text.startIndex {
            let tail = String(text[mapped.upperBound...])
            if let v4 = ipv4(tail) { return isPrivateIPv4(v4) }
        }
        guard let first = text.split(separator: ":", omittingEmptySubsequences: false).first, let value = UInt16(first.isEmpty ? "0" : String(first), radix: 16) else { return true }
        if value & 0xfe00 == 0xfc00 { return true }   // fc00::/7 unique local
        if value & 0xffc0 == 0xfe80 { return true }   // fe80::/10 link local
        if value & 0xff00 == 0xff00 { return true }   // multicast
        if value == 0 { return true }                  // ::/8 incl. mapped and compatible forms
        return false
    }
}
