import Foundation

/// A Tezos address with helpers for display. Validation of the base58 payload lives in the
/// chain service; this type only understands the textual shape.
struct Address: Hashable, Codable, Sendable {
    let value: String

    init(_ value: String) {
        self.value = value
    }

    var scheme: AddressScheme? { AddressScheme(address: value) }

    /// Prefixes that denote an account something can be sent to: implicit (tz1–tz6) or contract (KT1).
    static let accountPrefixes: Set<String> = Set(AddressScheme.allCases.map(\.rawValue)).union(["KT1"])

    /// True when this is a well-formed Tezos account address: known prefix, 20-byte hash, valid checksum.
    /// Works for every scheme including tz5/tz6, which Taquito does not yet know.
    var isValidAccount: Bool {
        guard Self.accountPrefixes.contains(String(value.prefix(3))), value.count == 36,
              let body = Base58.checkDecode(value)
        else { return false }
        return body.count == 3 + 20
    }

    var isContract: Bool { value.hasPrefix("KT1") }

    /// Whether the Etherlink rollup accepts this key through its Tezos-style RPC: a scheme check
    /// only (tz1 to tz3 for now), not validity or anything about the account on chain.
    var isUsableOnEtherlink: Bool {
        scheme.map { [.tz1, .tz2, .tz3].contains($0) } ?? false
    }

    /// Shortened form for headers, e.g. `tz1VSUr8wwN...Th8Cjcjb`. Keeps the full prefix so the
    /// scheme stays visible and enough of each end to tell similar addresses apart.
    func shortened(prefix: Int = 11, suffix: Int = 8) -> String {
        guard value.count > prefix + suffix + 3 else { return value }
        return "\(value.prefix(prefix))...\(value.suffix(suffix))"
    }
}

/// A Tezos Domains name tied to an account: one it owns, one that points at it, or both.
struct TezosDomain: Identifiable, Equatable, Sendable {
    var id: String { name }
    let name: String
    /// Where the name points; `nil` when it points nowhere.
    let address: Address?
    let owner: Address?
    /// `nil` for a subdomain, which lives as long as its parent.
    let expires: Date?
    /// The name this account publishes as its own (reverse record).
    let isReverseRecord: Bool

    func isOwned(by account: Address) -> Bool { owner == account }
    func pointsAt(_ account: Address) -> Bool { address == account }

    /// The name's page on the Tezos Domains app (mainnet).
    var appURL: URL? { URL(string: "https://app.tezos.domains/domain/\(name)") }
}
