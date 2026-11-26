import Foundation
import Testing
@testable import Signet

/// Experimental "Consolidated balances": tez, Layer 2 and Shielded fold into one tez row that
/// expands into its parts; unreadable rows add nothing and say so; tokens are untouched.
struct ConsolidatedBalancesTests {
    let tez = AssetBalance(id: "tez", kind: .tez, name: "Tezos", symbol: "tz", amount: 100,
                           details: TezBalance(spendable: 40, staked: 60).breakdown)
    let etherlink = AssetBalance(id: "etherlink", kind: .etherlink, name: "Etherlink", symbol: "tz", amount: 5)
    let shielded = AssetBalance(id: "shielded", kind: .shielded, name: "Shielded", symbol: "tz", amount: Decimal(string: "2.5")!)
    let token = AssetBalance(id: "KT1:0", kind: .token(contract: "KT1", tokenId: "0"), name: "Token", symbol: "TOK", amount: 7)

    @Test func everythingInTezBecomesOneRow() throws {
        let rows = AssetBalance.consolidated([tez, etherlink, shielded, token])
        #expect(rows.map(\.id) == ["tez", "KT1:0"])
        let merged = try #require(rows.first)
        #expect(merged.kind == .tez && merged.amount == Decimal(string: "107.5")!)
        #expect(merged.details.map(\.label) == ["Spendable", "Staked", "Etherlink", "Shielded"])
        #expect(merged.details.map(\.amount) == [40, 60, 5, Decimal(string: "2.5")!])
    }

    @Test func anUnreadableLayerAddsNothingAndSaysSo() throws {
        var down = etherlink
        down = AssetBalance(id: down.id, kind: .etherlink, name: "Etherlink", symbol: "tz", amount: 0, unavailable: "node unreachable")
        let merged = try #require(AssetBalance.consolidated([tez, down]).first)
        #expect(merged.amount == 100)
        #expect(merged.details.last?.unavailable == "node unreachable")
    }

    @Test func nothingToFoldLeavesTheListAlone() {
        #expect(AssetBalance.consolidated([tez, token]) == [tez, token])
        #expect(AssetBalance.consolidated([etherlink]) == [etherlink])          // no tez row (account not on chain)
        #expect(AssetBalance.consolidated([]) == [])
    }
}
