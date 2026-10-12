import Foundation
import Testing
@testable import Signet

/// Etherlink (0.9): per-network Etherlink settings and the dashboard's Etherlink balance row.
struct EtherlinkNetworkTests {
    @Test func mainnetAndShadownetShipAnEtherlinkEndpointOthersStartOff() {
        #expect(Network.mainnet.hasL2 && Network.mainnet.l2RPCURL?.host() == "michelson.etherlink.mainnet.octez.io")
        #expect(Network.shadownet.hasL2 && Network.shadownet.l2RPCURL?.host() == "michelson.etherlink.shadownet.octez.io")
        #expect(Network.mainnet.expectedL2ChainID == "NetXohUVN5QWR4f" && Network.shadownet.expectedL2ChainID == "NetXtLrzvQDobza")
        for network in [Network.bakingnet, .ushuaianet, .quantumnet, .custom] {
            #expect(!network.l2Enabled && network.l2RPCURL == nil && !network.hasL2, "\(network.name)")
        }
        // Switched on without a node is not usable yet; off with a node keeps the node for later.
        let on = Network.bakingnet.usingL2(enabled: true, node: nil)
        #expect(on.l2Enabled && !on.hasL2)
        let off = Network.mainnet.usingL2(enabled: false, node: Network.mainnet.l2RPCURL)
        #expect(!off.hasL2 && off.isUsingDefaultL2Node && off != Network.mainnet)
    }

    @Test func onlyTz1ToTz3KeysAreUsableOnTheRollup() {
        #expect(WalletViewModel.usableOnEtherlink(Address("tz1VSUr8wwNhLAzempoch5d6hLRiTh8Cjcjb")))
        #expect(WalletViewModel.usableOnEtherlink(Address("tz2BFTyPeYRzxd5aiBchbXN3WCZhx7BqbMBq")))
        #expect(WalletViewModel.usableOnEtherlink(Address("tz3WXYtyDUNL91qfiCJtVUX746QpNv5i5ve5")))
        #expect(!WalletViewModel.usableOnEtherlink(Address("tz4HVR6aty9KwsQFHh81C1G7gBdhxT8kuytm")))
        #expect(!WalletViewModel.usableOnEtherlink(Address("KT1Mkqf6TnMVmhAAuBJCizkzAu4Nhg6DTPmM")))
    }
}

@MainActor
struct EtherlinkSettingsTests {
    @Test func etherlinkChoicesAreKeptPerNetworkAndSurviveNodeChanges() {
        let state = InMemoryAppStateStore()
        let model = WalletViewModel(wallets: WalletViewModel.sampleWallets, chain: MockChainService(), stateStore: state)
        #expect(model.network.name == "Mainnet" && model.isL2Enabled(for: .mainnet) && model.network.hasL2)

        // Off on the network in use: applied at once, saved only because it differs from the default.
        model.setL2Enabled(false, for: .mainnet)
        #expect(!model.network.hasL2 && !model.isL2Enabled(for: .mainnet))
        #expect(state.load().l2Enabled == ["Mainnet": false] && state.load().l2NodeURLs == nil)
        // Changing the layer 1 node keeps the Etherlink choice.
        #expect(model.setNode("rpc.example.org"))
        #expect(!model.network.l2Enabled && model.network.rpcURL.host() == "rpc.example.org")
        model.useDefaultNode()
        #expect(!model.network.l2Enabled)
        model.setL2Enabled(true, for: .mainnet)
        #expect(model.network.hasL2 && model.network.isUsingDefaultL2Node && state.load().l2Enabled == nil)

        // Another network, without switching: on needs a node before it counts.
        model.setL2Enabled(true, for: .bakingnet)
        #expect(model.isL2Enabled(for: .bakingnet) && model.l2NodeURL(for: .bakingnet) == nil)
        #expect(!model.setL2Node("not a url", for: .bakingnet))
        #expect(model.setL2Node("l2.example.org", for: .bakingnet))
        #expect(state.load().l2NodeURLs == ["Bakingnet": "https://l2.example.org"] && state.load().l2Enabled == ["Bakingnet": true])
        model.switchNetwork(to: .bakingnet)
        #expect(model.network.hasL2 && model.network.l2RPCURL?.host() == "l2.example.org")
        model.useDefaultL2Node(for: .bakingnet)
        #expect(model.network.l2Enabled && !model.network.hasL2 && state.load().l2NodeURLs == nil)

        // A fresh model over the same state resolves the same choices.
        let again = WalletViewModel(wallets: WalletViewModel.sampleWallets, chain: MockChainService(), stateStore: state)
        #expect(again.network.name == "Bakingnet" && again.isL2Enabled(for: .bakingnet) && again.isL2Enabled(for: .mainnet))
        #expect(again.l2NodeURL(for: .mainnet) == Network.mainnet.l2DefaultRPCURL)
    }
}

@MainActor
struct EtherlinkRowTests {
    static let tz4 = Wallet(alias: "bls", address: Address("tz4HVR6aty9KwsQFHh81C1G7gBdhxT8kuytm"), keyKind: .unencrypted)

    private func etherlinkRow(_ model: WalletViewModel) -> AssetBalance? { model.assets.first { $0.kind == .etherlink } }

    @Test func rowFollowsTheNetworkSettingAndTheKeyKind() async {
        let model = WalletViewModel(wallets: WalletViewModel.sampleWallets + [Self.tz4], chain: MockChainService())
        await model.refresh()
        #expect(model.assets.map(\.id) == ["tez", "etherlink"])
        #expect(etherlinkRow(model)?.amount == Decimal(string: "5432.1") && etherlinkRow(model)?.unavailable == nil)

        model.setL2Enabled(false, for: .mainnet)
        await model.refresh()
        #expect(model.assets.map(\.id) == ["tez"])

        model.setL2Enabled(true, for: .mainnet)
        model.select(Self.tz4)
        await model.refresh()
        #expect(model.assets.map(\.id) == ["tez"])

        model.select(WalletViewModel.sampleWallets[0])
        model.switchNetwork(to: .bakingnet)
        await model.refresh()
        #expect(model.assets.map(\.id) == ["tez"])
    }

    struct FailingEtherlink: TestChainService {
        let notOnChain: Bool
        func tezBalance(for address: Address) async throws -> TezBalance {
            if notOnChain { throw ChainError.accountNotOnChain(address) }
            return TezBalance(spendable: 12)
        }
        func etherlinkBalance(for address: Address) async throws -> Decimal { throw URLError(.cannotConnectToHost) }
    }

    @Test func anUnreachableEtherlinkNodeBlanksOnlyThatRow() async {
        let model = WalletViewModel(wallets: WalletViewModel.sampleWallets, chain: FailingEtherlink(notOnChain: false))
        await model.refresh()
        #expect(model.errorMessage == nil && model.assets.map(\.id) == ["tez", "etherlink"])
        #expect(etherlinkRow(model)?.unavailable?.contains("Etherlink balance unavailable") == true)
    }

    @Test func anAccountNotOnLayer1ShowsNoEtherlinkRow() async {
        let model = WalletViewModel(wallets: WalletViewModel.sampleWallets, chain: FailingEtherlink(notOnChain: true))
        await model.refresh()
        #expect(model.accountNotOnChain && model.assets.isEmpty)
    }
}

/// Live: the Shadownet Etherlink endpoint answers as a Tezos node and refuses a wrong chain id.
struct EtherlinkLiveTests {
    @Test(.tags(.network), .liveNetwork, .timeLimit(.minutes(1)))
    func readsABalanceFromShadownetEtherlink() async throws {
        let chain = TaquitoChainService(network: .shadownet)
        let balance = try await chain.etherlinkBalance(for: Address("tz1KqTpEZ7Yob7QbPE4Hy4Wo8fHG8LhKxZSx"))
        #expect(balance >= 0)
        var wrongChain = Network.shadownet
        wrongChain.expectedL2ChainID = Network.mainnet.expectedL2ChainID
        await #expect(throws: ChainError.wrongChain(expected: Network.mainnet.expectedL2ChainID!, found: Network.shadownet.expectedL2ChainID!)) {
            try await TaquitoChainService(network: wrongChain).etherlinkBalance(for: Address("tz1KqTpEZ7Yob7QbPE4Hy4Wo8fHG8LhKxZSx"))
        }
    }
}
