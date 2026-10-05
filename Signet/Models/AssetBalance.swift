import Foundation

/// A fungible balance shown in the asset list: tez, Etherlink, or any other token.
struct AssetBalance: Identifiable, Hashable, Sendable {
    enum Kind: Hashable, Sendable {
        case tez
        case etherlink
        case token(contract: String, tokenId: String)
    }

    /// One line of a balance breakdown, e.g. "Staked 21,315.69 tz".
    struct Detail: Identifiable, Hashable, Sendable {
        let id: String
        let label: String
        let amount: Decimal
    }

    let id: String
    let kind: Kind
    let name: String
    let symbol: String
    /// Amount in whole units (already divided by the token's decimals). For tez this is the full balance.
    let amount: Decimal
    /// How `amount` splits up, if there is anything to show.
    var details: [Detail] = []

    var formattedAmount: String { Self.format(amount, symbol: symbol) }

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
