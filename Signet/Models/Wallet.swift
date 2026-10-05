import Foundation

/// How a wallet's secret key is held, taken from the URI scheme of its `secret_keys` entry.
enum KeyKind: String, Codable, Sendable {
    /// `unencrypted:edsk...` — the secret is in the file in clear.
    case unencrypted
    /// `encrypted:edesk...` — octez-client passphrase encryption; needs the passphrase to sign.
    case encrypted
    /// `ledger://...`
    case ledger
    /// `http(s)://`, `tcp://`, `unix:`, `remote:` — a remote signer such as octez-signer.
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
        case "http", "https", "tcp", "unix", "remote": self = .remote
        default: self = .unknown
        }
    }

    var canSign: Bool { self == .unencrypted }
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

    init(alias: String, address: Address, scheme: AddressScheme? = nil, publicKey: String? = nil, keyKind: KeyKind = .none) {
        self.alias = alias
        self.address = address
        self.scheme = scheme ?? address.scheme ?? .tz1
        self.publicKey = publicKey
        self.keyKind = keyKind
    }
}
