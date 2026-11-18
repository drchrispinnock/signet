import Foundation

/// How a wallet's secret key is held, taken from the URI scheme of its `secret_keys` entry.
enum KeyKind: String, Codable, Sendable {
    /// `unencrypted:edsk...` — the secret is in the file in clear.
    case unencrypted
    /// `encrypted:edesk...` — octez-client passphrase encryption; needs the passphrase to sign.
    case encrypted
    /// `ledger://...`
    case ledger
    /// `airgap://<fingerprint>/<path>` — the key is in AirGap Vault on a phone; Signet holds the
    /// public key, and operations go to the Vault and back by QR code.
    case airgap
    /// `http(s)://`, `tcp://`, `unix:` — a remote signer such as octez-signer, holding the key
    /// elsewhere; Signet sends what is to be signed and checks the signature it gets back.
    /// (`remote:tz1…` names a signer configured in octez-client and is `.unknown` here.)
    case remote
    /// Some other scheme we do not understand.
    case unknown
    /// No `secret_keys` entry: watch-only.
    case none

    init(locator: String?) {
        guard let locator, let colon = locator.firstIndex(of: ":") else {
            self = locator == nil ? .none : .unknown
            return
        }
        switch locator[..<colon].lowercased() {
        case "unencrypted": self = .unencrypted
        case "encrypted": self = .encrypted
        case "ledger": self = .ledger
        case "airgap": self = .airgap
        case "http", "https", "tcp", "unix": self = .remote
        default: self = .unknown
        }
    }

    /// Kinds Signet can sign operations with: clear-text keys, encrypted keys once the user
    /// supplies the password, Ledger keys when the device is plugged in, AirGap Vault keys by a
    /// QR round trip with the phone, and keys on a remote signer.
    var canSign: Bool { self == .unencrypted || self == .encrypted || self == .ledger || self == .airgap || self == .remote }

    /// Kinds that can also sign raw bytes without the operation watermark: a dApp's
    /// sign_payload, a multisig proposal, Mt Pelerin's address check. AirGap Vault's transaction
    /// sign request carries operations only.
    var signsMessages: Bool { canSign && self != .airgap }

    /// Base58 prefixes of octez-encrypted secret keys.
    static let encryptedKeyPrefixes: Set<String> = ["edesk", "spesk", "p2esk", "BLesk", "mdesk"]

    /// The `secret_keys` locator for a base58 secret key: `encrypted:` for edesk-style keys, else `unencrypted:`.
    static func locator(forSecretKey key: String) -> String {
        let prefix = String(key.prefix(5))
        return (encryptedKeyPrefixes.contains(prefix) ? "encrypted:" : "unencrypted:") + key
    }
}

/// One address with the alias the user gave it: an octez-client alias. The app holds many
/// wallets, possibly of different schemes, and shows one at a time.
struct Wallet: Identifiable, Hashable, Codable, Sendable {
    /// Aliases are unique within a client directory, so the alias is the identity.
    var id: String { alias }

    var alias: String
    var address: Address
    var scheme: AddressScheme
    /// Base58 public key. `nil` when the client directory has no `public_keys` entry.
    var publicKey: String?
    var keyKind: KeyKind
    /// Where the key lives on a Ledger, when `keyKind` is `.ledger` and the locator parsed.
    var ledgerKey: LedgerKey?
    /// Where the key is held when `keyKind` is `.remote` and the locator parsed.
    var remoteSigner: RemoteSignerLocator?
    /// A paper key imported for this run only: its secret is in memory (`SessionKeyStore`), not
    /// in the wallet directory, and is gone when Signet quits.
    var isSessionOnly = false
    /// The BLS proof of possession a tz4 account's reveal carries (`BLsig…`, the key's signature
    /// over its own public key), once made with the secret key. Only an estimate for an
    /// unrevealed tz4 account needs it; it is never stored (the reveal publishes it on chain).
    var proofOfPossession: String?

    init(alias: String, address: Address, scheme: AddressScheme? = nil, publicKey: String? = nil, keyKind: KeyKind = .none, ledgerKey: LedgerKey? = nil, remoteSigner: RemoteSignerLocator? = nil) {
        self.alias = alias
        self.address = address
        self.scheme = scheme ?? address.scheme ?? .tz1
        self.publicKey = publicKey
        self.keyKind = keyKind
        self.ledgerKey = ledgerKey
        self.remoteSigner = remoteSigner
    }

    enum CodingKeys: String, CodingKey { case alias, address, scheme, publicKey, keyKind, ledgerKey, remoteSigner, isSessionOnly }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        alias = try values.decode(String.self, forKey: .alias)
        address = try values.decode(Address.self, forKey: .address)
        scheme = try values.decode(AddressScheme.self, forKey: .scheme)
        publicKey = try values.decodeIfPresent(String.self, forKey: .publicKey)
        keyKind = try values.decode(KeyKind.self, forKey: .keyKind)
        ledgerKey = try values.decodeIfPresent(LedgerKey.self, forKey: .ledgerKey)
        remoteSigner = try values.decodeIfPresent(RemoteSignerLocator.self, forKey: .remoteSigner)
        isSessionOnly = try values.decodeIfPresent(Bool.self, forKey: .isSessionOnly) ?? false
    }
}
