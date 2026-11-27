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
        /// Why the amount could not be read; the line shows "unavailable" instead of a figure.
        var unavailable: String? = nil
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
    /// A token's balance in its smallest unit, exactly as the indexer gave it, and its decimal
    /// places: what a transfer is made of (`amount` is only for display).
    var rawAmount: String? = nil
    var decimals = 0
    var isFA12: Bool { standard?.lowercased() == "fa1.2" }
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

    /// Experimental "Consolidated balances": the tez, Layer 2 and Shielded rows become one tez
    /// row whose amount is everything the account holds in tez, and whose breakdown is the tez
    /// lines (spendable, staked, unstaking) followed by one line per other row. A row that could
    /// not be read adds nothing to the total and its line says so. Token rows are left as they
    /// are; without a tez row (an account not on chain) nothing is folded.
    static func consolidated(_ assets: [AssetBalance]) -> [AssetBalance] {
        guard let tez = assets.first(where: { $0.kind == .tez }), tez.unavailable == nil else { return assets }
        let folded = assets.filter { $0.kind == .etherlink || $0.kind == .shielded }
        guard !folded.isEmpty else { return assets }
        var details = tez.details.isEmpty ? [Detail(id: "spendable", label: "Spendable", amount: tez.amount)] : tez.details
        var total = tez.amount
        for row in folded {
            details.append(Detail(id: row.id, label: row.name, amount: row.unavailable == nil ? row.amount : 0, unavailable: row.unavailable))
            if row.unavailable == nil { total += row.amount }
        }
        var merged = AssetBalance(id: tez.id, kind: .tez, name: tez.name, symbol: tez.symbol, amount: total, details: details)
        merged.layer = tez.layer
        var result = [merged]
        result.append(contentsOf: assets.filter { $0.kind != .tez && $0.kind != .etherlink && $0.kind != .shielded })
        return result
    }

    /// The Shielded row before the TzEL wallet exists: always 0 tz.
    static let shieldedPlaceholder = AssetBalance(id: "shielded", kind: .shielded, name: "Shielded", symbol: "tz", amount: 0)

    /// A smallest-unit amount as plain decimal text in whole units, every digit kept and no
    /// grouping (`"1500000"` with 6 decimals is `"1.5"`), for an amount field.
    static func plainAmount(raw: String, decimals: Int) -> String {
        guard decimals > 0 else { return raw }
        let padded = String(repeating: "0", count: max(0, decimals + 1 - raw.count)) + raw
        let whole = padded.dropLast(decimals), fraction = padded.suffix(decimals).replacingOccurrences(of: "0+$", with: "", options: .regularExpression)
        return fraction.isEmpty ? String(whole) : "\(whole).\(fraction)"
    }

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
