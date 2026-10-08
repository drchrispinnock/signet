import Foundation

/// The curves the Tezos Wallet app on a Ledger can derive keys for. Names and derivation types
/// follow octez-client (`ledger://…/<curve>/…`) and Taquito's `DerivationType`.
enum LedgerCurve: String, CaseIterable, Codable, Sendable, Identifiable {
    case ed25519
    case secp256k1
    case p256
    case bip25519

    var id: String { rawValue }

    /// The name octez-client writes in the locator.
    var octezName: String {
        switch self {
        case .ed25519: "ed25519"
        case .secp256k1: "secp256k1"
        case .p256: "P-256"
        case .bip25519: "bip25519"
        }
    }

    /// Taquito's `DerivationType` number.
    var derivationType: Int {
        switch self {
        case .ed25519: 0
        case .secp256k1: 1
        case .p256: 2
        case .bip25519: 3
        }
    }

    var scheme: AddressScheme {
        switch self {
        case .ed25519, .bip25519: .tz1
        case .secp256k1: .tz2
        case .p256: .tz3
        }
    }

    var displayName: String {
        switch self {
        case .ed25519: "Ed25519 (tz1)"
        case .secp256k1: "secp256k1 (tz2)"
        case .p256: "P-256 (tz3)"
        case .bip25519: "BIP32-Ed25519 (tz1)"
        }
    }

    /// Parses octez's spellings, case-insensitively: ed25519, secp256k1, P-256 / secp256r1 / p256, bip25519 / bip32-ed25519.
    init?(octezName name: String) {
        switch name.lowercased() {
        case "ed25519": self = .ed25519
        case "secp256k1": self = .secp256k1
        case "p-256", "p256", "secp256r1": self = .p256
        case "bip25519", "bip32-ed25519": self = .bip25519
        default: return nil
        }
    }
}

/// A key held on a Ledger: which device (octez's "ledger id": the root key's tz1 address, or
/// its four-animal name), which curve, and the BIP32 path under `44'/1729'`.
///
/// Locator form, as octez-client writes it: `ledger://<id>/<curve>/0h/0h` where the path is
/// relative to `44h/1729h`. `h` and `'` both mark hardened indexes; an explicit `44h/1729h`
/// prefix is accepted too.
struct LedgerKey: Hashable, Codable, Sendable {
    static let rootPath = ["44'", "1729'"]

    var rootID: String
    var curve: LedgerCurve
    /// Path components below `44'/1729'`, normalised to `'` (e.g. `["0'", "0'"]`).
    var relativePath: [String]

    init(rootID: String, curve: LedgerCurve, relativePath: [String]) {
        self.rootID = rootID
        self.curve = curve
        self.relativePath = relativePath.map(Self.normalise)
    }

    /// The default path for account `n`: `44'/1729'/n'/0'`.
    init(rootID: String, curve: LedgerCurve, account: Int) {
        self.init(rootID: rootID, curve: curve, relativePath: ["\(account)'", "0'"])
    }

    init?(locator: String) {
        guard locator.lowercased().hasPrefix("ledger://") else { return nil }
        var parts = locator.dropFirst("ledger://".count).split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        guard parts.count >= 2, let curve = LedgerCurve(octezName: parts[1]) else { return nil }
        let root = parts.removeFirst()
        parts.removeFirst()
        var path = parts.map(Self.normalise)
        if path.count >= 2, path[0] == "44'", path[1] == "1729'" { path.removeFirst(2) }
        guard path.allSatisfy({ Int($0.dropLast($0.hasSuffix("'") ? 1 : 0)) != nil }) else { return nil }
        self.rootID = root
        self.curve = curve
        self.relativePath = path
    }

    private static func normalise(_ component: String) -> String {
        var c = component
        if c.hasSuffix("h") || c.hasSuffix("H") { c = String(c.dropLast()) + "'" }
        return c
    }

    /// Full BIP32 path as Taquito wants it: `44'/1729'/0'/0'`.
    var fullPath: String { (Self.rootPath + relativePath).joined(separator: "/") }

    /// The `secret_keys` / `public_keys` locator in octez-client's form (`h` for hardened).
    var locator: String {
        let path = relativePath.map { $0.replacingOccurrences(of: "'", with: "h") }
        return (["ledger://\(rootID)", curve.octezName] + path).joined(separator: "/")
    }

    /// The account index when the path is the usual `n'/0'`.
    var account: Int? {
        guard relativePath.count == 2, relativePath[1] == "0'" else { return nil }
        return Int(relativePath[0].dropLast())
    }
}

/// What an operation is signed with. Built on demand for the one operation and not kept.
enum SigningKey: Sendable, Equatable {
    /// A base58 secret key from the wallet directory, with the password if it is encrypted.
    case secret(String, passphrase: String?)
    /// A key on a Ledger; the device signs after the user approves on it.
    case ledger(LedgerKey, address: Address)

    var isLedger: Bool { if case .ledger = self { return true } else { return false } }

    /// The JSON the bridge's `signerFor` understands.
    var bridgeSpec: String {
        let object: [String: Any]
        switch self {
        case .secret(let key, let passphrase):
            object = ["kind": "secret", "secretKey": key, "passphrase": passphrase ?? ""]
        case .ledger(let key, let address):
            object = ["kind": "ledger", "path": key.fullPath, "derivationType": key.curve.derivationType, "address": address.value]
        }
        let data = try! JSONSerialization.data(withJSONObject: object)
        return String(data: data, encoding: .utf8)!
    }
}
