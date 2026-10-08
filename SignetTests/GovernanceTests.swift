import Foundation
import Testing
@testable import Signet

struct GovernanceTests {
    @Test func parsesBridgePayload() throws {
        let json = """
        {"kind":"exploration","index":185,"position":10,"remaining":990,
         "proposals":[{"hash":"PtSeouLouXkxhg39oWzjxDWaCydNfR3RxCUrNe4Q9Ro8BTehcbh","votingPower":"5"},{"hash":"PsRiotumaAMotcRoDWW1bysEhQy2n1M5fy8JgRp8jjRfHGmfeA7","votingPower":"9"}],
         "currentProposal":"PtSeouLouXkxhg39oWzjxDWaCydNfR3RxCUrNe4Q9Ro8BTehcbh",
         "votingPower":"1234","totalVotingPower":"10000","quorumPerTenThousand":5500,
         "ballots":{"yay":"600","nay":"100","pass":"300"},"myBallot":"pass","proposalCount":2}
        """
        let value = JSONValue(bridged: try JSONSerialization.jsonObject(with: Data(json.utf8)))
        let info = TaquitoChainService.governanceInfo(from: value)
        #expect(info.kind == .exploration)
        #expect(info.index == 185)
        #expect(info.remaining == 990)
        #expect(info.proposals.map(\.hash).first == "PsRiotumaAMotcRoDWW1bysEhQy2n1M5fy8JgRp8jjRfHGmfeA7")   // most power first
        #expect(info.votingPower == 1234)
        #expect(info.canVote)
        #expect(info.share(of: 1234) == 0.1234)
        #expect(info.ballots.total == 1000)
        #expect(info.myBallot == .pass)
        #expect(info.proposalCount == 2)
        #expect(info.kind?.acceptsBallots == true && info.kind?.acceptsUpvotes == false)

        let none = TaquitoChainService.governanceInfo(from: JSONValue(bridged: ["kind": "cooldown", "votingPower": NSNull()]))
        #expect(none.kind == .cooldown)
        #expect(!none.canVote)
    }

    @Test func recognisesProposalHashes() {
        #expect(GovernanceOperation.isProposalHash("PtSeouLouXkxhg39oWzjxDWaCydNfR3RxCUrNe4Q9Ro8BTehcbh"))
        #expect(GovernanceOperation.isProposalHash("PsRiotumaAMotcRoDWW1bysEhQy2n1M5fy8JgRp8jjRfHGmfeA7"))
        #expect(!GovernanceOperation.isProposalHash("PtSeouLouXkxhg39oWzjxDWaCydNfR3RxCUrNe4Q9Ro8BTehcbX"))   // bad checksum
        #expect(!GovernanceOperation.isProposalHash("tz1VSUr8wwNhLAzempoch5d6hLRiTh8Cjcjb"))
        #expect(!GovernanceOperation.isProposalHash(""))
    }

    @Test func operationsEncodeForTheBridge() {
        let up = GovernanceOperation.upvote(["PtA", "PtB"])
        #expect(up.bridgeKind == "proposals")
        #expect(up.bridgeArgument["proposals"] as? [String] == ["PtA", "PtB"])
        #expect(up.title == "Upvote 2 proposals")
        let vote = GovernanceOperation.ballot(proposal: "PtA", vote: .nay)
        #expect(vote.bridgeKind == "ballot")
        #expect(vote.bridgeArgument["ballot"] as? String == "nay")
        #expect(vote.title == "Vote Nay")
    }

    @Test @MainActor func governanceMenuNeedsABakerWeCanSignFor() async throws {
        let model = WalletViewModel(wallets: WalletViewModel.sampleWallets, chain: MockChainService())
        await model.refresh()
        #expect(!model.canGovern)   // sample wallet delegates to Captain Stake, it is not a baker itself
        let baker = Wallet(alias: "captain", address: MockChainService.captainStake, publicKey: "edpkX", keyKind: .unencrypted)
        let store = InMemoryWalletStore()
        try store.add(baker, secretKey: "edskX")
        let bakerModel = WalletViewModel(chain: MockChainService(), walletStore: store)
        await bakerModel.refresh()
        #expect(bakerModel.canGovern)
        let watch = WalletViewModel(wallets: [Wallet(alias: "captain", address: MockChainService.captainStake, keyKind: .none)], chain: MockChainService())
        await watch.refresh()
        #expect(!watch.canGovern)
        let result = try await bakerModel.performGovernance(.ballot(proposal: "PtA", vote: .yay), passphrase: nil)
        #expect(result.hash == "ooMockGovernanceballot")
    }

    @Test(.tags(.network), .timeLimit(.minutes(1)))
    func readsTheLivePeriodOnShadownet() async throws {
        let info = try await TaquitoChainService(network: .shadownet).governanceInfo(for: Address("tz1VSUr8wwNhLAzempoch5d6hLRiTh8Cjcjb"))
        #expect(info.kind != nil)
        #expect(info.totalVotingPower > 0)
    }
}
