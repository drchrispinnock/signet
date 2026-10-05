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

    /// Shortened form for headers, e.g. `tz1VSUr8wwN...Th8Cjcjb`. Keeps the full prefix so the
    /// scheme stays visible and enough of each end to tell similar addresses apart.
    func shortened(prefix: Int = 11, suffix: Int = 8) -> String {
        guard value.count > prefix + suffix + 3 else { return value }
        return "\(value.prefix(prefix))...\(value.suffix(suffix))"
    }
}
