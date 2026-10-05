import Foundation

/// A fungible balance shown in the asset list: tez, Etherlink, or any other token.
struct AssetBalance: Identifiable, Hashable, Sendable {
    enum Kind: Hashable, Sendable {
        case tez
        case etherlink
        case token(contract: String, tokenId: String)
    }

    let id: String
    let kind: Kind
    let name: String
    let symbol: String
    /// Amount in whole units (already divided by the token's decimals).
    let amount: Decimal

    var formattedAmount: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 6
        formatter.usesGroupingSeparator = true
        let number = formatter.string(from: amount as NSDecimalNumber) ?? "\(amount)"
        return "\(number) \(symbol)"
    }
}
