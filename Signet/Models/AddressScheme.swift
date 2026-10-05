import Foundation

/// The signature scheme behind a Tezos implicit account, identified by its address prefix.
///
/// Every known prefix is listed so the rest of the app can reason about it, but only the
/// schemes marked `isSupported` can be created, imported or signed with today. tz5 (ML-DSA-44)
/// and tz6 are deferred until the chain library and Apple's crypto stack support them.
enum AddressScheme: String, CaseIterable, Codable, Sendable {
    case tz1, tz2, tz3, tz4, tz5, tz6

    var displayName: String {
        switch self {
        case .tz1: "Ed25519"
        case .tz2: "secp256k1"
        case .tz3: "P-256"
        case .tz4: "BLS12-381"
        case .tz5: "ML-DSA-44 (post-quantum)"
        case .tz6: "Post-quantum (TBD)"
        }
    }

    /// Whether this app can currently manage keys for the scheme.
    var isSupported: Bool {
        switch self {
        case .tz1, .tz2, .tz3, .tz4: true
        case .tz5, .tz6: false
        }
    }

    /// Shown in the UI next to schemes that cannot be created yet.
    var unavailableReason: String? {
        switch self {
        case .tz5: "ML-DSA-44 keys are not yet supported by the wallet libraries. Coming when Taquito and Apple CryptoKit add ML-DSA-44."
        case .tz6: "Not yet specified by the Tezos protocol."
        default: nil
        }
    }

    /// Detects the scheme from an address string, or `nil` if the prefix is not an implicit account.
    init?(address: String) {
        guard address.count >= 3 else { return nil }
        self.init(rawValue: String(address.prefix(3)))
    }
}
