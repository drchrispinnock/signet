import Foundation

/// The signature scheme behind a Tezos implicit account, identified by its address prefix.
///
/// Every known prefix is listed so the rest of the app can reason about it, but only the
/// schemes marked `isSupported` can be created or signed with today. tz5 (ML-DSA-44) and
/// tz6 (XMSS) keys made by octez-client are still shown and their balances fetched.
enum AddressScheme: String, CaseIterable, Codable, Sendable {
    case tz1, tz2, tz3, tz4, tz5, tz6

    var displayName: String {
        switch self {
        case .tz1: "Ed25519"
        case .tz2: "secp256k1"
        case .tz3: "P-256"
        case .tz4: "BLS12-381"
        case .tz5: "ML-DSA-44 (post-quantum)"
        case .tz6: "XMSS (post-quantum)"
        }
    }

    /// Base58 prefix of public keys for this scheme (edpk, sppk, p2pk, BLpk, mdpk, xmpk).
    var publicKeyPrefix: String {
        switch self {
        case .tz1: "edpk"
        case .tz2: "sppk"
        case .tz3: "p2pk"
        case .tz4: "BLpk"
        case .tz5: "mdpk"
        case .tz6: "xmpk"
        }
    }

    /// Whether this app can currently generate keys and sign for the scheme.
    var isSupported: Bool {
        switch self {
        case .tz1, .tz2, .tz3, .tz4: true
        case .tz5, .tz6: false
        }
    }

    /// Shown in the UI next to schemes that cannot be created yet.
    var unavailableReason: String? {
        switch self {
        case .tz5: "ML-DSA-44 keys are not yet supported by the wallet libraries. Use octez-client to create one; Signet will show it."
        case .tz6: "XMSS keys are stateful and not yet supported by the wallet libraries. Use octez-client to create one; Signet will show it."
        default: nil
        }
    }

    /// Detects the scheme from an address string, or `nil` if the prefix is not an implicit account.
    init?(address: String) {
        guard address.count >= 3 else { return nil }
        self.init(rawValue: String(address.prefix(3)))
    }
}
