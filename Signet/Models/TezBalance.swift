import Foundation

/// An account's tez, split the way the protocol splits it. All amounts in whole tez.
///
/// `balance` from the node is only the spendable part; staked tez and tez being unstaked
/// (frozen for the unbonding period, then finalizable until claimed) are held separately but
/// still belong to the account.
struct TezBalance: Hashable, Sendable {
    var spendable: Decimal
    var staked: Decimal
    var unstakedFrozen: Decimal
    var unstakedFinalizable: Decimal

    init(spendable: Decimal, staked: Decimal = 0, unstakedFrozen: Decimal = 0, unstakedFinalizable: Decimal = 0) {
        self.spendable = spendable
        self.staked = staked
        self.unstakedFrozen = unstakedFrozen
        self.unstakedFinalizable = unstakedFinalizable
    }

    /// Everything the account owns, matching the node's `full_balance`.
    var total: Decimal { spendable + staked + unstakedFrozen + unstakedFinalizable }

    /// Builds from mutez strings as the RPC returns them.
    init?(mutezSpendable: String?, staked: String?, unstakedFrozen: String?, unstakedFinalizable: String?) {
        func tez(_ s: String?) -> Decimal? { s.flatMap { Decimal(string: $0) }.map { $0 / 1_000_000 } }
        guard let spendable = tez(mutezSpendable) else { return nil }
        self.init(spendable: spendable, staked: tez(staked) ?? 0, unstakedFrozen: tez(unstakedFrozen) ?? 0, unstakedFinalizable: tez(unstakedFinalizable) ?? 0)
    }

    /// Lines for the breakdown. Spendable and staked always; unstaked lines only when non-zero.
    var breakdown: [AssetBalance.Detail] {
        var lines = [
            AssetBalance.Detail(id: "spendable", label: "Spendable", amount: spendable),
            AssetBalance.Detail(id: "staked", label: "Staked", amount: staked),
        ]
        if unstakedFrozen > 0 { lines.append(AssetBalance.Detail(id: "unstaking", label: "Unstaking", amount: unstakedFrozen)) }
        if unstakedFinalizable > 0 { lines.append(AssetBalance.Detail(id: "finalizable", label: "Ready to finalize", amount: unstakedFinalizable)) }
        return lines
    }
}
