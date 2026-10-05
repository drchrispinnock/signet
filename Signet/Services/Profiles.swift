import Foundation

/// Identity data for an address. TzProfiles are mainnet identities, so pictures and names always
/// come from mainnet services no matter which network balances are being read from.
enum Profiles {
    /// TzKT's avatar service: TzProfiles logo, known-account logo, or an identicon.
    static let avatarService = URL(string: "https://services.tzkt.io/v1/avatars/")!

    static func avatarURL(for address: Address) -> URL? {
        URL(string: address.value, relativeTo: avatarService)?.absoluteURL
    }

    /// The indexer that carries TzProfiles data (`extras.profile`) for name lookups.
    static let profileIndexer = Network.mainnet.tzktURL!
}
