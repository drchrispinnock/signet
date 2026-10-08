import Foundation
import Testing
@testable import Signet

struct TransactionParsingTests {
    static let me = Address("tz1dCaMnnMJk76UodjewCK67ABiXWjcKj73N")
    static let fixture = """
    [
      {"type":"transaction","id":1,"hash":"ooOUT","level":100,"timestamp":"2026-09-16T15:43:01Z","status":"applied","amount":1500000,"bakerFee":594,
       "sender":{"alias":"Captain Stake","address":"tz1dCaMnnMJk76UodjewCK67ABiXWjcKj73N"},"target":{"address":"tz1VSUr8wwNhLAzempoch5d6hLRiTh8Cjcjb"}},
      {"type":"transaction","id":2,"hash":"ooIN","level":99,"timestamp":"2026-09-15T10:00:00Z","status":"applied","amount":250000,"bakerFee":400,
       "sender":{"alias":"objkt.com Treasury","address":"tz2BFTyPeYRzxd5aiBchbXN3WCZhx7BqbMBq"},"target":{"alias":"Captain Stake","address":"tz1dCaMnnMJk76UodjewCK67ABiXWjcKj73N"}},
      {"type":"transaction","id":3,"hash":"ooCALL","level":98,"timestamp":"2026-09-14T10:00:00Z","status":"failed","amount":0,"bakerFee":799,
       "sender":{"address":"tz1dCaMnnMJk76UodjewCK67ABiXWjcKj73N"},"target":{"alias":"objkt.com Marketplace","address":"KT1RJ6PbjHpwc3M5rw5s2Nbmefwbuwbdxton"},"parameter":{"entrypoint":"collect","value":{"int":"1"}}},
      {"type":"delegation","id":4,"hash":"ooDEL","level":97,"timestamp":"2026-09-13T10:00:00Z","status":"applied","bakerFee":300,"amount":5000000,
       "sender":{"address":"tz1dCaMnnMJk76UodjewCK67ABiXWjcKj73N"},"newDelegate":{"alias":"Everstake","address":"tz1aRoaRhSpRYvFdyvgWLL6TGyRoGF51wDjM"}},
      {"type":"delegation","id":6,"hash":"ooJOIN","level":95,"timestamp":"2026-09-11T10:00:00Z","status":"applied","bakerFee":300,"amount":6118049,
       "sender":{"address":"tz1SoQEinkjove9bCc5XanTpmvw9mPWzLBaq"},"prevDelegate":{"alias":"Kiln","address":"tz3Vq38qYD3GEbWcXHMLt5PaASZrkDtEiA8D"},"newDelegate":{"alias":"Captain Stake","address":"tz1dCaMnnMJk76UodjewCK67ABiXWjcKj73N"}},
      {"type":"delegation","id":7,"hash":"ooLEAVE","level":94,"timestamp":"2026-09-10T10:00:00Z","status":"applied","bakerFee":300,"amount":7261872,
       "sender":{"address":"tz1ghpncFJry1RKLEtKuLaEpdeP8HfFEFXsG"},"prevDelegate":{"alias":"Captain Stake","address":"tz1dCaMnnMJk76UodjewCK67ABiXWjcKj73N"},"newDelegate":null},
      {"type":"transaction","id":5,"hash":"ooSELF","level":96,"timestamp":"2026-09-12T10:00:00Z","status":"applied","amount":1,"bakerFee":1,
       "sender":{"address":"tz1dCaMnnMJk76UodjewCK67ABiXWjcKj73N"},"target":{"address":"tz1dCaMnnMJk76UodjewCK67ABiXWjcKj73N"}}
    ]
    """.data(using: .utf8)!

    @Test func classifiesDirectionCounterpartyAndAmounts() throws {
        let txs = TzKTService.parseOperations(Self.fixture, for: Self.me)
        #expect(txs.count == 7)

        let out = txs[0]
        #expect(out.direction == .outgoing)
        #expect(out.counterparty?.value == "tz1VSUr8wwNhLAzempoch5d6hLRiTh8Cjcjb")
        #expect(out.counterpartyAlias == nil)
        #expect(out.amount == Decimal(string: "1.5"))
        #expect(out.fee == Decimal(string: "0.000594"))

        let incoming = txs[1]
        #expect(incoming.direction == .incoming)
        #expect(incoming.counterpartyAlias == "objkt.com Treasury")
        #expect(incoming.amount == Decimal(string: "0.25"))

        let call = txs[2]
        #expect(call.entrypoint == "collect")
        #expect(call.isContractCall)
        #expect(!call.isApplied)

        let delegation = txs[3]
        #expect(delegation.kind == .delegation)
        #expect(delegation.counterpartyAlias == "Everstake")
        #expect(delegation.amount == 0)                        // the amount field is a balance, not a transfer
        #expect(delegation.delegatedBalance == 5)
        #expect(delegation.delegationRole(for: Self.me) == .weDelegated)

        // Fixture order: out, in, call, our delegation, join, leave, self-transfer.
        let join = txs[4]
        #expect(join.direction == .incoming)
        #expect(join.counterparty?.value == "tz1SoQEinkjove9bCc5XanTpmvw9mPWzLBaq")
        #expect(join.delegationRole(for: Self.me) == .delegatorJoined)
        #expect(join.delegatedBalance == Decimal(string: "6.118049"))

        let leave = txs[5]
        #expect(leave.delegationRole(for: Self.me) == .delegatorLeft)
        #expect(leave.previousDelegate == Self.me)
        #expect(leave.newDelegate == nil)

        #expect(txs[6].direction == .selfTransfer)
    }

    @MainActor
    @Test func namesPreferOurRecordsThenTheIndexer() {
        let model = WalletViewModel(wallets: WalletViewModel.sampleWallets, chain: MockChainService())
        let mine = model.displayName(for: WalletViewModel.sampleWallets[1].address, indexerAlias: "Somebody Else")
        #expect(mine == ("Savings", true))
        let known = model.displayName(for: MockChainService.captainStake, indexerAlias: "Captain Stake")
        #expect(known == ("Captain Stake", false))
        let stranger = Address("tz3WXYtyDUNL91qfiCJtVUX746QpNv5i5ve5")
        let unknown = model.displayName(for: stranger, indexerAlias: nil)
        #expect(unknown == (stranger.shortened(), false))
    }

    @MainActor
    @Test func refreshLoadsTransactions() async {
        let model = WalletViewModel(wallets: WalletViewModel.sampleWallets, chain: MockChainService())
        await model.refresh()
        #expect(model.transactions.count == 4)
        #expect(model.activityTab == .transactions)
    }

    @Test(.tags(.network), .timeLimit(.minutes(1)))
    func captainStakeHasHistoryOnTzKT() async throws {
        let txs = try await TzKTService(baseURL: Network.mainnet.tzktURL!).recentOperations(for: Self.me, limit: 10)
        #expect(!txs.isEmpty)
        #expect(txs.count <= 10)
        #expect(txs.allSatisfy { $0.hash.hasPrefix("o") })
    }
}
