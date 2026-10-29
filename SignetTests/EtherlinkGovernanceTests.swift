import Foundation
import Testing
@testable import Signet

/// Etherlink governance: the layer 1 contracts per network, their settings, the state as the
/// bridge reports it, the operations, and when the Governance item and its Etherlink tab show.
struct EtherlinkGovernanceTests {
    @Test func mainnetShipsTheGaneshaContractsAndTestnetsNone() {
        #expect(Network.mainnet.defaultEtherlinkGovernance[.slow]?.value == "KT1AXRU3wLc87WNhLhVGrgqDGubLACUMUgPb")
        #expect(Network.mainnet.defaultEtherlinkGovernance[.fast]?.value == "KT19oUVQPnVLuUBYXrBVd46WJnNAMpqkKSwo")
        #expect(Network.mainnet.etherlinkGovernance == Network.mainnet.defaultEtherlinkGovernance)
        // Shown only with Layer 2 on, and never where no contract is set.
        #expect(!Network.mainnet.canGovernEtherlink && Network.mainnet.l2On.canGovernEtherlink)
        #expect(Network.mainnet.l2On.etherlinkGovernanceProcesses == [.slow, .fast])
        for network in [Network.shadownet, .bakingnet, .ushuaianet, .quantumnet, .custom] {
            #expect(network.etherlinkGovernance.isEmpty && !network.l2On.canGovernEtherlink, Comment(rawValue: network.name))
        }
        let fastOnly = Network.mainnet.l2On.usingEtherlinkGovernance(nil, for: .slow)
        #expect(fastOnly.canGovernEtherlink && fastOnly.etherlinkGovernanceProcesses == [.fast] && !fastOnly.isUsingDefaultEtherlinkGovernance(.slow))
        #expect(!fastOnly.usingEtherlinkGovernance(nil, for: .fast).canGovernEtherlink)
    }

    @Test func kernelHashesAndContractAddressesAreChecked() {
        let hash = "0x009e07373751a43acbf0cd747b404f45130e0ad561c4b7da937e02eb812bd0f7e8"
        #expect(EtherlinkGovernance.kernelHash(from: " \(hash.uppercased()) ") == hash)
        #expect(EtherlinkGovernance.kernelHash(from: String(hash.dropFirst(2))) == hash)
        #expect(EtherlinkGovernance.kernelHash(from: hash + "00") == nil)
        #expect(EtherlinkGovernance.kernelHash(from: String(hash.dropLast())) == nil)
        #expect(EtherlinkGovernance.kernelHash(from: "0xzz" + hash.dropFirst(4)) == nil)
        #expect(!EtherlinkGovernance.isKernelHash(""))
        #expect(EtherlinkGovernance.contractAddress(from: " KT1AXRU3wLc87WNhLhVGrgqDGubLACUMUgPb ")?.value == "KT1AXRU3wLc87WNhLhVGrgqDGubLACUMUgPb")
        #expect(EtherlinkGovernance.contractAddress(from: "tz1VSUr8wwNhLAzempoch5d6hLRiTh8Cjcjb") == nil)
        #expect(EtherlinkGovernance.contractAddress(from: "KT1AXRU3wLc87WNhLhVGrgqDGubLACUMUgPX") == nil)   // bad checksum
    }

    @Test func operationsNameTheirEntrypointAndPayload() {
        let hash = "0x009e07373751a43acbf0cd747b404f45130e0ad561c4b7da937e02eb812bd0f7e8"
        let propose = EtherlinkGovernance.Operation.newProposal(hash: hash)
        #expect(propose.entrypoint == "new_proposal" && propose.payload == String(hash.dropFirst(2)) && propose.kernelHash == hash && propose.title == "Propose kernel")
        let upvote = EtherlinkGovernance.Operation.upvote(hash: hash)
        #expect(upvote.entrypoint == "upvote_proposal" && upvote.payload == String(hash.dropFirst(2)) && upvote.title == "Upvote proposal")
        let vote = EtherlinkGovernance.Operation.vote(.nay)
        #expect(vote.entrypoint == "vote" && vote.payload == "nay" && vote.kernelHash == nil && vote.title == "Vote Nay")
        #expect(EtherlinkGovernance.Vote.allCases.map(\.rawValue) == ["yea", "nay", "pass"])   // the contract's spelling, not the protocol's "yay"
    }

    @Test func parsesTheBridgeState() throws {
        let json = """
        {"periodIndex":42,"periodKind":"promotion","remainingBlocks":100,
         "config":{"periodLength":4800,"upvotingLimit":20,"scale":100,"proposalQuorum":5,"promotionQuorum":15,"promotionSupermajority":80},
         "totalVotingPower":"700","current":"promotion",
         "candidate":"0x009e07373751a43acbf0cd747b404f45130e0ad561c4b7da937e02eb812bd0f7e8",
         "tallies":{"yea":"10","nay":"20","pass":"30"},
         "proposals":[{"hash":"0x009e07373751a43acbf0cd747b404f45130e0ad561c4b7da937e02eb812bd0f7e8","proposers":["tz1dCaMnnMJk76UodjewCK67ABiXWjcKj73N"],"upvotes":"50","upvoted":true}],
         "proposalsKnown":false,"votingPower":"70","votesFor":["tz1dCaMnnMJk76UodjewCK67ABiXWjcKj73N"],"upvotesUsed":2,"myVote":"pass"}
        """
        let contract = Address("KT19oUVQPnVLuUBYXrBVd46WJnNAMpqkKSwo")
        let state = try TaquitoChainService.etherlinkGovernanceState(from: JSONValue(bridged: try JSONSerialization.jsonObject(with: Data(json.utf8))), contract: contract)
        #expect(state.contract == contract && state.periodIndex == 42 && state.periodKind == .promotion && state.remainingBlocks == 100)
        #expect(state.config.periodLength == 4800 && state.config.promotionSupermajority == 80 && state.config.fraction(state.config.promotionQuorum) == 0.15)
        #expect(state.totalVotingPower == 700 && state.share(of: 70) == 0.1)
        #expect(state.candidate == "0x009e07373751a43acbf0cd747b404f45130e0ad561c4b7da937e02eb812bd0f7e8")
        #expect(state.tallies.total == 60 && state.tallies.pass == 30)
        #expect(state.proposals.count == 1 && state.proposals[0].upvoted && state.proposals[0].proposers == [MockChainService.captainStake] && state.proposals[0].upvotes == 50)
        #expect(!state.proposalsKnown && state.votingPower == 70 && state.canVote && state.votesFor == [MockChainService.captainStake] && state.upvotesUsed == 2 && state.myVote == .pass)

        // Every number is checked (S20): a negative count, a non-numeric power or a bad hash is an error, never a trap.
        for broken in [
            json.replacingOccurrences(of: "\"remainingBlocks\":100", with: "\"remainingBlocks\":-1"),
            json.replacingOccurrences(of: "\"votingPower\":\"70\"", with: "\"votingPower\":\"7e1\""),
            json.replacingOccurrences(of: "\"periodKind\":\"promotion\"", with: "\"periodKind\":\"cooldown\""),
            json.replacingOccurrences(of: "\"candidate\":\"0x009e", with: "\"candidate\":\"0x9e"),
        ] {
            #expect(throws: TaquitoBridge.BridgeError.self) {
                try TaquitoChainService.etherlinkGovernanceState(from: JSONValue(bridged: try JSONSerialization.jsonObject(with: Data(broken.utf8))), contract: contract)
            }
        }
    }

    @Test @MainActor func contractsAreKeptPerNetworkOnlyWhereTheyDiffer() {
        let store = InMemoryAppStateStore()
        let model = WalletViewModel(wallets: WalletViewModel.sampleWallets, chain: MockChainService(), stateStore: store)
        #expect(model.etherlinkGovernanceContract(for: .slow, in: .mainnet) == "KT1AXRU3wLc87WNhLhVGrgqDGubLACUMUgPb")
        #expect(model.etherlinkGovernanceContract(for: .slow, in: .shadownet) == "")
        // A replacement on the network in use is applied and saved; the default is not saved.
        #expect(model.setEtherlinkGovernanceContract(" KT1VZVNCNnhUp7s15d9RsdycP7C1iwYhAQ8r ", for: .slow, in: .mainnet))
        #expect(model.network.etherlinkGovernance[.slow]?.value == "KT1VZVNCNnhUp7s15d9RsdycP7C1iwYhAQ8r")
        #expect(store.load().etherlinkGovernance == ["Mainnet": ["slow": "KT1VZVNCNnhUp7s15d9RsdycP7C1iwYhAQ8r"]])
        #expect(!model.setEtherlinkGovernanceContract("tz1VSUr8wwNhLAzempoch5d6hLRiTh8Cjcjb", for: .slow, in: .mainnet))
        #expect(model.network.etherlinkGovernance[.slow]?.value == "KT1VZVNCNnhUp7s15d9RsdycP7C1iwYhAQ8r")
        // Empty turns the process off and is remembered as "".
        #expect(model.setEtherlinkGovernanceContract("", for: .fast, in: .mainnet))
        #expect(model.network.etherlinkGovernance[.fast] == nil && store.load().etherlinkGovernance?["Mainnet"]?["fast"] == "")
        model.useDefaultEtherlinkGovernanceContract(for: .slow, in: .mainnet)
        model.useDefaultEtherlinkGovernanceContract(for: .fast, in: .mainnet)
        #expect(model.network.etherlinkGovernance == Network.mainnet.defaultEtherlinkGovernance && store.load().etherlinkGovernance == nil)
        // Another network, without switching: a contract can be given where we ship none.
        #expect(model.setEtherlinkGovernanceContract("KT1DxndcFitAbxLdJCN3C1pPivqbC3RJxD1R", for: .fast, in: .shadownet))
        #expect(model.network.name == "Mainnet" && model.etherlinkGovernanceContract(for: .fast, in: .shadownet) == "KT1DxndcFitAbxLdJCN3C1pPivqbC3RJxD1R")
        // A relaunch reads the same choices back.
        let again = WalletViewModel(wallets: WalletViewModel.sampleWallets, chain: MockChainService(), stateStore: store)
        #expect(again.resolved(.shadownet).etherlinkGovernance == [.fast: Address("KT1DxndcFitAbxLdJCN3C1pPivqbC3RJxD1R")])
    }

    @Test @MainActor func theEtherlinkTabNeedsLayer2AndABakerOrVotingKey() async throws {
        // The sample account is Captain Stake's voting key in the mock, but not a baker.
        let model = WalletViewModel(wallets: WalletViewModel.sampleWallets, chain: MockChainService(), stateStore: InMemoryAppStateStore())
        await model.refresh()
        #expect(!model.canGovern && !model.canGovernEtherlink && model.etherlinkVotesFor.isEmpty)   // Layer 2 off: nothing is asked
        model.setL2Enabled(true, for: .mainnet)
        await model.refresh()
        #expect(model.etherlinkVotesFor == [MockChainService.captainStake])
        #expect(model.canGovernEtherlink && model.canGovern)
        // Off again, or no contract: the item goes.
        model.setEtherlinkGovernanceContract("", for: .slow, in: .mainnet)
        model.setEtherlinkGovernanceContract("", for: .fast, in: .mainnet)
        await model.refresh()
        #expect(!model.canGovernEtherlink && !model.canGovern)

        // A baker with Layer 2 on gets both tabs; a watch-only baker gets nothing.
        let baker = Wallet(alias: "captain", address: MockChainService.captainStake, publicKey: "edpkX", keyKind: .unencrypted)
        let store = InMemoryWalletStore()
        try store.add(baker, secretKey: "edskX")
        let bakerModel = WalletViewModel(chain: MockChainService(), walletStore: store, stateStore: InMemoryAppStateStore())
        bakerModel.setL2Enabled(true, for: .mainnet)
        await bakerModel.refresh()
        #expect(bakerModel.canGovern && bakerModel.canGovernEtherlink && bakerModel.etherlinkVotesFor.isEmpty)
        let watch = WalletViewModel(wallets: [Wallet(alias: "captain", address: MockChainService.captainStake, keyKind: .none)], chain: MockChainService(), stateStore: InMemoryAppStateStore())
        watch.setL2Enabled(true, for: .mainnet)
        await watch.refresh()
        #expect(!watch.canGovernEtherlink)

        // Reading the state, estimating and sending through the approved-limits path.
        let state = try await bakerModel.etherlinkGovernanceState(for: .fast)
        #expect(state.periodKind == .proposal && state.canVote && state.proposals.first?.hash == MockChainService.mockKernelHash)
        let upvote = EtherlinkGovernance.Operation.upvote(hash: MockChainService.mockKernelHash)
        let approved = try await bakerModel.estimateEtherlinkGovernance(upvote, process: .fast)
        #expect(approved.contract.value == "KT19oUVQPnVLuUBYXrBVd46WJnNAMpqkKSwo" && approved.estimate.limits != nil)
        let result = try await bakerModel.performEtherlinkGovernance(upvote, process: .fast, approved: approved, passphrase: nil)
        #expect(result.hash == "ooMockEtherlinkupvote_proposal")
        // The estimate is for one operation on one contract in one context (S31).
        await #expect(throws: WalletViewModel.WalletError.contextChanged) {
            try await bakerModel.performEtherlinkGovernance(.vote(.yea), process: .fast, approved: approved, passphrase: nil)
        }
        await #expect(throws: WalletViewModel.WalletError.contextChanged) {
            try await bakerModel.performEtherlinkGovernance(upvote, process: .slow, approved: approved, passphrase: nil)
        }
        await #expect(throws: WalletViewModel.WalletError.notEstimated) {
            try await bakerModel.performEtherlinkGovernance(upvote, process: .fast, approved: nil, passphrase: nil)
        }
        await #expect(throws: WalletViewModel.WalletError.invalidKernelHash) {
            _ = try await bakerModel.estimateEtherlinkGovernance(.newProposal(hash: "0x1234"), process: .fast)
        }
        bakerModel.setL2Enabled(false, for: .mainnet)
        await #expect(throws: ChainError.noEtherlinkNode) {
            _ = try await bakerModel.etherlinkGovernanceState(for: .fast)
        }
    }

    /// Mainnet's fast contract is read live: the period is one of the two kinds, the
    /// thresholds are Ganesha's, and a known voting key lists the bakers it votes for.
    @Test(.tags(.network), .liveNetwork, .timeLimit(.minutes(2)))
    func readsTheLiveMainnetContracts() async throws {
        let service = TaquitoChainService(network: .mainnet)
        let fast = Address("KT19oUVQPnVLuUBYXrBVd46WJnNAMpqkKSwo")
        let votingKey = Address("tz1XjYbYEdJgoUK2ERHD5iVaquJQwPbvYjDJ")
        let bakers = try await service.etherlinkVotingRights(for: votingKey, contract: fast)
        #expect(!bakers.isEmpty && bakers.allSatisfy { $0.value.hasPrefix("tz3") })
        let state = try await service.etherlinkGovernanceState(contract: fast, for: votingKey)
        #expect(state.config.periodLength == 4800 && state.config.promotionSupermajority == 80 && state.config.upvotingLimit == 20)
        #expect(state.remainingBlocks > 0 && state.remainingBlocks <= 4800 && state.totalVotingPower > 0)
        #expect(state.votesFor == bakers && state.votingPower > 0 && state.proposalsKnown)
        if state.periodKind == .promotion { #expect(state.candidate != nil) }
    }
}
