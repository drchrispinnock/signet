import Foundation

/// Where an account's key lives when octez-signer holds it: the `secret_keys` locator
/// octez-client writes for a remote signer, `http://host:port/tz1…`, `https://host:port/tz1…`,
/// `tcp://host:port/tz1…` or `unix:/path?pkh=tz1…`. Signet never sees the secret; it sends the
/// bytes to sign and checks the signature that comes back against the account's public key.
struct RemoteSignerLocator: Hashable, Codable, Sendable {
    enum Transport: String, Codable, CaseIterable, Sendable, Identifiable {
        case http, https, tcp, unix

        var id: String { rawValue }

        /// octez-signer's own defaults (`main_signer.ml`): HTTP 6732, HTTPS 443, TCP 7732.
        var defaultPort: Int? {
            switch self {
            case .http: 6732
            case .https: 443
            case .tcp: 7732
            case .unix: nil
            }
        }

        var title: String {
            switch self {
            case .http: "HTTP"
            case .https: "HTTPS"
            case .tcp: "TCP"
            case .unix: "Unix socket"
            }
        }

        /// What octez-signer is started with to listen this way.
        var signerCommand: String {
            switch self {
            case .http: "octez-signer launch http signer"
            case .https: "octez-signer launch https signer <cert> <key>"
            case .tcp: "octez-signer launch socket signer"
            case .unix: "octez-signer launch local signer"
            }
        }
    }

    var transport: Transport
    var host: String
    var port: Int
    /// The URL path in front of `/keys/…` for HTTP(S) (usually empty); the socket's path for Unix.
    var path: String
    var address: Address

    init(transport: Transport, host: String, port: Int, path: String = "", address: Address) {
        self.transport = transport
        self.host = host
        self.port = port
        self.path = path
        self.address = address
    }

    /// Reads octez-client's locator. `remote:tz1…` needs the client's configured signer and is
    /// not read.
    init?(locator: String) {
        let lower = locator.lowercased()
        if lower.hasPrefix("unix:") {
            guard let components = URLComponents(string: locator),
                  let pkh = components.queryItems?.first(where: { $0.name == "pkh" })?.value,
                  Address(pkh).isImplicitAccount, !components.path.isEmpty
            else { return nil }
            self.init(transport: .unix, host: "", port: 0, path: components.path, address: Address(pkh))
            return
        }
        guard let components = URLComponents(string: locator),
              let scheme = components.scheme?.lowercased(), let transport = Transport(rawValue: scheme), transport != .unix,
              let host = components.host, !host.isEmpty, components.user == nil, components.password == nil,
              components.query == nil, components.fragment == nil
        else { return nil }
        var segments = components.path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        guard let last = segments.popLast(), Address(last).isImplicitAccount else { return nil }
        let port: Int
        switch transport {
        case .tcp:
            guard let given = components.port, segments.isEmpty else { return nil }
            port = given
        case .http: port = components.port ?? 80
        case .https: port = components.port ?? 443
        case .unix: return nil
        }
        guard (1...65535).contains(port) else { return nil }
        self.init(transport: transport, host: host, port: port, path: segments.isEmpty ? "" : "/" + segments.joined(separator: "/"), address: Address(last))
    }

    /// The host as it goes in a URL: an IPv6 literal in brackets.
    private var urlHost: String { host.contains(":") && !host.hasPrefix("[") ? "[\(host)]" : host }

    /// The signer itself, without the key: `tcp://localhost:7732`.
    var endpoint: String {
        switch transport {
        case .unix: "unix:\(path)"
        default: "\(transport.rawValue)://\(urlHost):\(port)\(path)"
        }
    }

    /// The `secret_keys` (and `public_keys`) locator octez-client reads.
    var locator: String {
        switch transport {
        case .unix: "unix:\(path)?pkh=\(address.value)"
        default: "\(endpoint)/\(address.value)"
        }
    }

    /// The HTTP(S) signer's root, in front of `/keys/…`.
    var baseURL: URL? {
        guard transport == .http || transport == .https else { return nil }
        return URL(string: endpoint)
    }

    /// The same signer for another of its keys.
    func with(address: Address) -> RemoteSignerLocator {
        var copy = self
        copy.address = address
        return copy
    }
}

extension Address {
    /// tz1 to tz5: an account a signer could hold a key for.
    var isImplicitAccount: Bool {
        guard let scheme, scheme != .tz6 else { return false }
        return isValidAccount && value.hasPrefix(scheme.rawValue)
    }
}

/// octez-signer's binary protocol over TCP and Unix sockets (`signer_messages.ml`): every
/// message is a 2-byte big-endian length and a Data_encoding payload; a request is a one-byte
/// kind and its fields, a reply is `00` and the value or `01` and an error trace.
enum SignerWire {
    /// Base58 prefixes of tz1…tz5 in the order of the signer's key hash tags 0…4.
    static let addressPrefixes: [[UInt8]] = [[6, 161, 159], [6, 161, 161], [6, 161, 164], [6, 161, 166], [6, 161, 169]]
    /// Public key prefixes and sizes by tag: edpk, sppk, p2pk, BLpk, mdpk.
    static let publicKeyFormats: [(prefix: [UInt8], size: Int)] = [
        ([13, 15, 37, 217], 32), ([3, 254, 226, 86], 33), ([3, 178, 139, 127], 33), ([6, 149, 135, 204], 48), ([13, 7, 237, 67], 1312),
    ]
    /// The signature version tz4 requests name (`Signature.V_latest`, version 3).
    static let blsSignatureVersion: UInt8 = 3

    enum Failure: LocalizedError, Equatable {
        case malformed
        case refused(String?)

        var errorDescription: String? {
            switch self {
            case .malformed: "The remote signer's reply could not be read."
            case .refused(let reason): "The remote signer refused" + (reason.map { ": \($0)" } ?? ".")
            }
        }
    }

    /// The key hash as the signer encodes it: its tag and 20 bytes.
    static func keyHash(_ address: Address) -> [UInt8]? {
        guard let bytes = Base58.checkDecode(address.value), bytes.count == 23,
              let tag = addressPrefixes.firstIndex(of: Array(bytes[0..<3])) else { return nil }
        return [UInt8(tag)] + bytes[3...]
    }

    static func address(fromKeyHash bytes: ArraySlice<UInt8>) -> Address? {
        guard bytes.count == 21, let tag = bytes.first, Int(tag) < addressPrefixes.count else { return nil }
        return Address(Base58.checkEncode(prefix: addressPrefixes[Int(tag)], payload: Array(bytes.dropFirst())))
    }

    /// A sign request names a tz4 key with its signature version (`pkh_encoding`, tag 3). An
    /// older signer (before Octez 23) takes the bare hash, but it also signs BLS with the
    /// augmented scheme the chain no longer accepts, so it is not asked that way.
    private static func signingKeyHash(_ address: Address) -> [UInt8]? {
        guard let hash = keyHash(address) else { return nil }
        return hash[0] == 3 ? [3] + hash + [blsSignatureVersion] : hash
    }

    /// The authentication signature is the last field and of variable size, so when absent it
    /// is simply not there (Data_encoding writes no option tag for it).
    static func signRequest(address: Address, data: [UInt8]) -> [UInt8]? {
        guard let pkh = signingKeyHash(address) else { return nil }
        let length = UInt32(data.count)
        return [0] + pkh + [UInt8(length >> 24), UInt8(length >> 16 & 0xff), UInt8(length >> 8 & 0xff), UInt8(length & 0xff)] + data
    }

    static func publicKeyRequest(address: Address) -> [UInt8]? { keyHash(address).map { [1] + $0 } }
    static let authorizedKeysRequest: [UInt8] = [2]
    static let knownKeysRequest: [UInt8] = [6]
    /// A BLS proof of possession for the key itself: no other public key (a fixed-size option,
    /// tag 00), no authentication (the variable last field, left out).
    static func provePossessionRequest(address: Address) -> [UInt8]? { keyHash(address).map { [7] + $0 + [0] } }

    static func frame(_ payload: [UInt8]) -> [UInt8]? {
        guard payload.count <= 0xffff else { return nil }
        return [UInt8(payload.count >> 8), UInt8(payload.count & 0xff)] + payload
    }

    /// The value in a reply, or the signer's error.
    static func value(_ reply: [UInt8]) throws -> ArraySlice<UInt8> {
        guard let tag = reply.first else { throw Failure.malformed }
        switch tag {
        case 0: return reply.dropFirst()
        case 1: throw Failure.refused(errorID(in: Array(reply.dropFirst())))
        default: throw Failure.malformed
        }
    }

    /// The first error id in a trace, when the signer wrote one (errors are carried as JSON).
    static func errorID(in bytes: [UInt8]) -> String? {
        let text = String(decoding: bytes, as: UTF8.self)
        guard let range = text.range(of: #""id"\s*:\s*"([^"]{1,200})""#, options: .regularExpression) else { return nil }
        let match = text[range]
        guard let start = match.dropLast().lastIndex(of: "\"") else { return nil }
        return String(match[match.index(after: start)..<match.index(before: match.endIndex)])
    }

    static func publicKey(fromValue value: ArraySlice<UInt8>) throws -> String {
        guard let tag = value.first, Int(tag) < publicKeyFormats.count else { throw Failure.malformed }
        let format = publicKeyFormats[Int(tag)]
        guard value.count == 1 + format.size else { throw Failure.malformed }
        return Base58.checkEncode(prefix: format.prefix, payload: Array(value.dropFirst()))
    }

    /// A list of key hashes, 21 bytes each; inside a union octez writes it behind a 4-byte
    /// length (`00000000` for none), which cannot be mistaken for whole items.
    static func addresses(fromValue whole: ArraySlice<UInt8>) throws -> [Address] {
        var value = whole
        if value.count % 21 == 4 {
            let length = value.prefix(4).reduce(0) { $0 << 8 | Int($1) }
            guard length == value.count - 4 else { throw Failure.malformed }
            value = value.dropFirst(4)
        }
        guard value.count % 21 == 0 else { throw Failure.malformed }
        return try stride(from: value.startIndex, to: value.endIndex, by: 21).map { start in
            guard let address = address(fromKeyHash: value[start..<(start + 21)]) else { throw Failure.malformed }
            return address
        }
    }

    /// `nil` when the signer takes unauthenticated requests, else the keys it accepts.
    static func authorizedKeys(fromValue value: ArraySlice<UInt8>) throws -> [Address]? {
        switch value.first {
        case 0 where value.count == 1: return nil
        case 1: return try addresses(fromValue: value.dropFirst())
        default: throw Failure.malformed
        }
    }
}
