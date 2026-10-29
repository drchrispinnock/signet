import Foundation

/// A fungible balance shown in the asset list: tez, Etherlink, or any other token.
struct AssetBalance: Identifiable, Hashable, Sendable {
    enum Kind: Hashable, Sendable {
        case tez
        case etherlink
        /// The account's shielded tez on the TzEL rollup (shown while shielded transactions are on).
        case shielded
        case token(contract: String, tokenId: String)
    }

    /// One line of a balance breakdown, e.g. "Staked 21,315.69 tz".
    struct Detail: Identifiable, Hashable, Sendable {
        let id: String
        let label: String
        let amount: Decimal
    }

    var id: String
    let kind: Kind
    let name: String
    let symbol: String
    /// Amount in whole units (already divided by the token's decimals). For tez this is the full balance.
    let amount: Decimal
    /// How `amount` splits up, if there is anything to show.
    var details: [Detail] = []
    /// The token's logo, one URL per gateway to try (tokens only).
    var iconURLs: [URL] = []
    /// `fa1.2` / `fa2` for tokens.
    var standard: String?
    /// Why the amount could not be read (the Etherlink node unreachable); the row shows this
    /// instead of a figure.
    var unavailable: String? = nil

    var formattedAmount: String { Self.format(amount, symbol: symbol) }

    /// Where the token lives: 1 on Tezos, 2 on Etherlink's Michelson interface (read from
    /// Etherlink's TzKT). The dashboard's own rows (tez, Etherlink, Shielded) are layer 1.
    var layer = 1
    var isLayer2: Bool { layer == 2 }

    /// The same token tagged as Etherlink's, its id prefixed so it cannot collide with a
    /// layer 1 token of the same contract and token id.
    func onLayer2() -> AssetBalance {
        var copy = self
        copy.layer = 2
        copy.id = "l2:" + id
        return copy
    }

    /// The Shielded row before the TzEL wallet exists: always 0 tz.
    static let shieldedPlaceholder = AssetBalance(id: "shielded", kind: .shielded, name: "Shielded", symbol: "tz", amount: 0)

    static func format(_ amount: Decimal, symbol: String) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 6
        formatter.usesGroupingSeparator = true
        let number = formatter.string(from: amount as NSDecimalNumber) ?? "\(amount)"
        return "\(number) \(symbol)"
    }
}
