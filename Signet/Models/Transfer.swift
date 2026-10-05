import Foundation

/// What a transfer will cost, in tez.
struct TransferEstimate: Hashable, Sendable {
    let fee: Decimal
    /// Storage burn, e.g. the allocation cost when the destination has never held tez.
    let burn: Decimal
    let total: Decimal
    let gasLimit: Int
    let storageLimit: Int
}

/// Public identity an indexer knows for an address: the TzProfiles data TzKT carries.
struct AccountProfile: Hashable, Sendable {
    let name: String?
    let twitter: String?
    let description: String?
}

/// 1 tez = 1,000,000 mutez.
enum Mutez {
    static let perTez = Decimal(1_000_000)

    static func fromTez(_ tez: Decimal) -> String {
        var scaled = tez * perTez
        var rounded = Decimal()
        NSDecimalRound(&rounded, &scaled, 0, .down)
        return NSDecimalNumber(decimal: rounded).stringValue
    }

    static func toTez(_ mutez: String?) -> Decimal? {
        mutez.flatMap { Decimal(string: $0) }.map { $0 / perTez }
    }
}
