import Foundation

/// A Tezos address with helpers for display. Validation of the base58 payload lives in the
/// chain service; this type only understands the textual shape.
struct Address: Hashable, Codable, Sendable {
    let value: String

    init(_ value: String) {
        self.value = value
    }

    var scheme: AddressScheme? { AddressScheme(address: value) }

    /// Shortened form for headers, e.g. `tz1VSUr8wwN...Th8Cjcjb`. Keeps the full prefix so the
    /// scheme stays visible and enough of each end to tell similar addresses apart.
    func shortened(prefix: Int = 11, suffix: Int = 8) -> String {
        guard value.count > prefix + suffix + 3 else { return value }
        return "\(value.prefix(prefix))...\(value.suffix(suffix))"
    }
}
