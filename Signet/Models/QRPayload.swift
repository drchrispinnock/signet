#if canImport(CryptoKit)
import CryptoKit
#else
import Crypto
#endif
import Foundation

/// What the text of a scanned QR code (or a pasted string) is, as far as Signet can use it.
/// Classification is by shape and checksum only: nothing is sent anywhere and no key is opened.
/// The sheet each case is handed to does the real validation.
enum QRPayload: Equatable, Sendable {
    /// An Octez Connect / Beacon pairing code, bare or carried by a `…?type=tzip10&data=…` link.
    case pairing(code: String)
    /// A tz1 to tz6 or KT1 address.
    case address(Address)
    /// A base58 public key (edpk, sppk, p2pk, BLpk, mdpk); its address is derived before use.
    case publicKey(String)
    /// A base58 secret key, clear or octez-encrypted.
    case secretKey(String)
    /// 12, 15, 18, 21 or 24 lower-case words: a BIP39 recovery phrase by shape.
    case recoveryPhrase(String)
    /// One of several codes that together carry a secret key too long for one (a tz5 key on a
    /// recovery sheet); `KeyPartCollector` puts them together.
    case keyPart(KeyPart)
    case unknown

    static let publicKeyPrefixes = ["edpk", "sppk", "p2pk", "BLpk", "mdpk"]
    static let secretKeyPrefixes = ["edsk", "spsk", "p2sk", "BLsk", "mdsk", "edesk", "spesk", "p2esk", "BLesk", "mdesk"]
    /// Longer than any QR code can carry; anything bigger is not worth decoding.
    static let maximumLength = 8192

    /// True for the cases that carry a secret, which must never be shown or logged.
    var isSecret: Bool {
        switch self {
        case .secretKey, .recoveryPhrase, .keyPart: true
        default: false
        }
    }

    static func classify(_ raw: String) -> QRPayload {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text.utf8.count <= maximumLength else { return .unknown }

        if text.hasPrefix(KeyPart.scheme) { return KeyPart(text: text).map(QRPayload.keyPart) ?? .unknown }
        if let code = DAppPairingLink.code(fromScanned: text) { return .pairing(code: code) }

        // Some wallets write an address as a `tezos:` URI.
        let bare = strippingTezosScheme(text)
        if Address(bare).isValidAccount { return .address(Address(bare)) }

        if let phrase = recoveryPhrase(text) { return .recoveryPhrase(phrase) }

        // Everything else Signet reads is one base58check word.
        guard !text.contains(where: \.isWhitespace), let body = Base58.checkDecode(text) else { return .unknown }
        if secretKeyPrefixes.contains(where: text.hasPrefix) { return .secretKey(text) }
        if publicKeyPrefixes.contains(where: text.hasPrefix) { return .publicKey(text) }
        // A bare pairing code is base58check over the pairing request's JSON.
        if body.first == UInt8(ascii: "{"), body.last == UInt8(ascii: "}") { return .pairing(code: text) }
        return .unknown
    }

    private static func strippingTezosScheme(_ text: String) -> String {
        guard text.lowercased().hasPrefix("tezos:") else { return text }
        var rest = text.dropFirst("tezos:".count)
        while rest.hasPrefix("/") { rest = rest.dropFirst() }
        return String(rest)
    }

    /// The phrase with single spaces when `text` has the shape of one, else `nil`. The word list
    /// and checksum are checked by the Import sheet, through the bridge.
    private static func recoveryPhrase(_ text: String) -> String? {
        let words = text.split(whereSeparator: \.isWhitespace)
        guard [12, 15, 18, 21, 24].contains(words.count),
              words.allSatisfy({ (3...8).contains($0.count) && $0.allSatisfy { $0.isASCII && $0.isLowercase } })
        else { return nil }
        return words.joined(separator: " ")
    }
}

/// One QR code of a secret key printed across several: `signet-key:<index>/<count>:<id>:<chunk>`.
/// The id is the same on every part of one key, so parts of different keys are never joined,
/// and the joined text must still pass the key's own base58 checksum. The format is Signet's
/// own; no other wallet reads it.
struct KeyPart: Equatable, Sendable {
    /// 1-based.
    let index: Int
    let count: Int
    let id: String
    let chunk: String

    static let scheme = "signet-key:"
    static let maximumParts = 32
    static let maximumChunkLength = 2000
    /// Short enough for a code a webcam reads easily from a printed page (QR version 18 at level L).
    static let defaultChunkLength = 680

    var text: String { "\(Self.scheme)\(index)/\(count):\(id):\(chunk)" }

    init(index: Int, count: Int, id: String, chunk: String) {
        self.index = index
        self.count = count
        self.id = id
        self.chunk = chunk
    }

    init?(text: String) {
        guard text.hasPrefix(Self.scheme) else { return nil }
        let fields = text.dropFirst(Self.scheme.count).split(separator: ":", omittingEmptySubsequences: false)
        guard fields.count == 3 else { return nil }
        let numbers = fields[0].split(separator: "/", omittingEmptySubsequences: false)
        guard numbers.count == 2, let index = Int(numbers[0]), let count = Int(numbers[1]),
              (2...Self.maximumParts).contains(count), (1...count).contains(index),
              fields[1].count == 8, fields[1].allSatisfy(\.isHexDigit),
              !fields[2].isEmpty, fields[2].count <= Self.maximumChunkLength,
              fields[2].allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber) })
        else { return nil }
        self.init(index: index, count: count, id: String(fields[1]), chunk: String(fields[2]))
    }

    /// What ties the parts of one key together: the start of the key's SHA-256.
    static func id(for key: String) -> String {
        SHA256.hash(data: Data(key.utf8)).prefix(4).map { String(format: "%02x", $0) }.joined()
    }

    /// The key cut into equal parts of at most `chunkLength` characters; empty when it would
    /// take more parts than a sheet should carry, or fits one code anyway.
    static func split(_ key: String, chunkLength: Int = defaultChunkLength) -> [KeyPart] {
        let count = (key.count + chunkLength - 1) / chunkLength
        guard (2...maximumParts).contains(count) else { return [] }
        let size = (key.count + count - 1) / count
        let id = id(for: key)
        var parts: [KeyPart] = []
        var rest = Substring(key)
        for index in 1...count {
            parts.append(KeyPart(index: index, count: count, id: id, chunk: String(rest.prefix(size))))
            rest = rest.dropFirst(size)
        }
        return parts
    }
}

/// Gathers the parts of one key as they are scanned, in any order.
struct KeyPartCollector: Equatable, Sendable {
    private(set) var id: String?
    private(set) var count = 0
    private var chunks: [Int: String] = [:]

    enum Outcome: Equatable, Sendable {
        /// Kept (or already held); more parts are needed.
        case needMore
        /// Every part is in and the key they make is sound.
        case complete(String)
        /// Every part is in but they do not make a key; the collector has been emptied.
        case invalid
    }

    var isEmpty: Bool { chunks.isEmpty }
    var received: Int { chunks.count }
    /// The parts still to scan, by number.
    var missing: [Int] { count == 0 ? [] : (1...count).filter { chunks[$0] == nil } }

    /// Adds a part. A part of another key starts a new collection, dropping the old one.
    mutating func add(_ part: KeyPart) -> Outcome {
        if part.id != id || part.count != count {
            id = part.id
            count = part.count
            chunks = [:]
        }
        chunks[part.index] = part.chunk
        guard missing.isEmpty else { return .needMore }
        let key = (1...count).compactMap { chunks[$0] }.joined()
        let wanted = id
        self = KeyPartCollector()
        guard KeyPart.id(for: key) == wanted, case .secretKey = QRPayload.classify(key) else { return .invalid }
        return .complete(key)
    }
}

/// What the Import account sheet opens on when a scan found a key.
enum ImportPrefill: Equatable, Sendable {
    case secretKey(String)
    case recoveryPhrase(String)
}
