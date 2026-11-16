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
    case unknown

    static let publicKeyPrefixes = ["edpk", "sppk", "p2pk", "BLpk", "mdpk"]
    static let secretKeyPrefixes = ["edsk", "spsk", "p2sk", "BLsk", "mdsk", "edesk", "spesk", "p2esk", "BLesk", "mdesk"]
    /// Longer than any QR code can carry; anything bigger is not worth decoding.
    static let maximumLength = 8192

    /// True for the cases that carry a secret, which must never be shown or logged.
    var isSecret: Bool {
        switch self {
        case .secretKey, .recoveryPhrase: true
        default: false
        }
    }

    static func classify(_ raw: String) -> QRPayload {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text.utf8.count <= maximumLength else { return .unknown }

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

/// What the Import account sheet opens on when a scan found a key.
enum ImportPrefill: Equatable, Sendable {
    case secretKey(String)
    case recoveryPhrase(String)
}
