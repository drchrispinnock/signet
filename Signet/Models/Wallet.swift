import Foundation

/// One address with the alias the user gave it at creation time. The app holds many wallets,
/// possibly of different schemes, and shows one at a time.
struct Wallet: Identifiable, Hashable, Codable, Sendable {
    let id: UUID
    var alias: String
    var address: Address
    var scheme: AddressScheme
    /// Base58 public key. `nil` for watch-only wallets whose key we do not hold.
    var publicKey: String?

    init(id: UUID = UUID(), alias: String, address: Address, scheme: AddressScheme? = nil, publicKey: String? = nil) {
        self.id = id
        self.alias = alias
        self.address = address
        self.scheme = scheme ?? address.scheme ?? .tz1
        self.publicKey = publicKey
    }
}
