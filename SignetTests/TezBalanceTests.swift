import Foundation
import Testing
@testable import Signet

struct TezBalanceTests {
    @Test func totalIsTheSumOfAllParts() {
        let balance = TezBalance(spendable: 10, staked: 20, unstakedFrozen: 3, unstakedFinalizable: 4)
        #expect(balance.total == 37)
    }

    @Test func parsesMutezStringsLikeTheNodeReturns() throws {
        let balance = try #require(TezBalance(mutezSpendable: "1386761464", staked: "21315693554",
                                              unstakedFrozen: "0", unstakedFinalizable: "0"))
        #expect(balance.spendable == Decimal(string: "1386.761464"))
        #expect(balance.staked == Decimal(string: "21315.693554"))
        #expect(balance.total == Decimal(string: "22702.455018"))
        #expect(TezBalance(mutezSpendable: nil, staked: "1", unstakedFrozen: nil, unstakedFinalizable: nil) == nil)
    }

    @Test func breakdownAlwaysShowsSpendableAndStakedButOnlyNonZeroUnstaking() {
        let quiet = TezBalance(spendable: 5, staked: 0)
        #expect(quiet.breakdown.map(\.label) == ["Spendable", "Staked"])

        let busy = TezBalance(spendable: 5, staked: 10, unstakedFrozen: 1, unstakedFinalizable: 2)
        #expect(busy.breakdown.map(\.label) == ["Spendable", "Staked", "Unstaking", "Ready to finalize"])
        #expect(busy.breakdown.map(\.amount) == [5, 10, 1, 2])
    }

    /// Captain Stake is a baker, so staked tez dominates. Both fetch paths must agree with the
    /// node's own full_balance and with each other.
    @Test(.tags(.network), .timeLimit(.minutes(1)))
    func captainStakeFullBalanceIncludesStake() async throws {
        let address = Address("tz1dCaMnnMJk76UodjewCK67ABiXWjcKj73N")
        let service = TaquitoChainService(network: .mainnet)

        let viaTaquito = try await service.tezBalance(for: address)
        let viaRPC = try await service.directTezBalance(for: address)

        #expect(viaTaquito.staked > viaTaquito.spendable)
        #expect(viaTaquito.total > viaTaquito.spendable)
        // Both paths read head; allow for a block landing between calls.
        #expect(abs((viaTaquito.total - viaRPC.total) as NSDecimalNumber as! Double) < 100)
    }
}
