import Foundation
import Testing
@testable import Signet

/// Etherlink (0.9): per-network Etherlink settings and the dashboard's Etherlink balance row.
extension Network {
    /// The network with Layer 2 switched on at its shipped node, as a user would in Settings.
    var l2On: Network { usingL2(enabled: true, node: l2RPCURL) }
}

struct EtherlinkNetworkTests {
    @Test func layerTwoIsOffByDefaultAndShippedForMainnetAndShadownet() {
        #expect(!Network.mainnet.hasL2 && Network.mainnet.l2RPCURL?.host() == "michelson.etherlink.mainnet.octez.io")
        #expect(!Network.shadownet.hasL2 && Network.shadownet.l2RPCURL?.host() == "michelson.etherlink.shadownet.octez.io")
        #expect(Network.mainnet.l2On.hasL2 && Network.mainnet.l2On.isUsingDefaultL2Node && Network.mainnet.l2On != Network.mainnet)
        #expect(Network.mainnet.expectedL2ChainID == "NetXohUVN5QWR4f" && Network.shadownet.expectedL2ChainID == "NetXtLrzvQDobza")
        for network in [Network.bakingnet, .ushuaianet, .quantumnet, .custom] {
            #expect(!network.l2Enabled && network.l2RPCURL == nil && !network.hasL2, "\(network.name)")
        }
        // Switched on without a node is not usable yet; off with a node keeps the node for later.
        let on = Network.bakingnet.usingL2(enabled: true, node: nil)
        #expect(on.l2Enabled && !on.hasL2)
        let off = Network.mainnet.l2On.usingL2(enabled: false, node: Network.mainnet.l2RPCURL)
        #expect(!off.hasL2 && off.isUsingDefaultL2Node && off == Network.mainnet)
    }

    @Test func theLayer2NetworkIsTheMichelsonInterfaceWithItsOwnIndexer() throws {
        #expect(Network.shadownet.layer2 == nil)   // off by default
        let l2 = try #require(Network.shadownet.l2On.layer2)
        #expect(l2.rpcURL == Network.shadownet.l2RPCURL && l2.expectedChainID == "NetXtLrzvQDobza" && l2.layerNumber == 2)
        #expect(l2.tzktURL?.host() == "api.shadownet.etherlink.tzkt.io" && l2.explorerURL(operation: "ooX")?.absoluteString == "https://shadownet.etherlink.tzkt.io/ooX")
        #expect(l2.layer2 == nil && !l2.hasL2 && !l2.isMainnet)
        #expect(Network.mainnet.l2On.layer2?.tzktURL?.host() == "api.etherlink.tzkt.io")
        #expect(Network.bakingnet.l2On.layer2 == nil)
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
        #expect(model.network.name == "Mainnet" && !model.isL2Enabled(for: .mainnet) && !model.network.hasL2)

        // On, on the network in use: applied at once and saved because it differs from the default.
        model.setL2Enabled(true, for: .mainnet)
        #expect(model.network.hasL2 && model.network.isUsingDefaultL2Node && model.isL2Enabled(for: .mainnet))
        #expect(state.load().l2Enabled == ["Mainnet": true] && state.load().l2NodeURLs == nil)
        // Changing the layer 1 node keeps the Etherlink choice.
        #expect(model.setNode("rpc.example.org"))
        #expect(model.network.hasL2 && model.network.rpcURL.host() == "rpc.example.org")
        model.useDefaultNode()
        #expect(model.network.hasL2)
        model.setL2Enabled(false, for: .mainnet)
        #expect(!model.network.hasL2 && state.load().l2Enabled == nil)

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
        model.setL2Enabled(true, for: .mainnet)
        let again = WalletViewModel(wallets: WalletViewModel.sampleWallets, chain: MockChainService(), stateStore: state)
        #expect(again.network.name == "Bakingnet" && again.isL2Enabled(for: .bakingnet) && again.isL2Enabled(for: .mainnet))
        #expect(again.l2NodeURL(for: .mainnet) == Network.mainnet.l2DefaultRPCURL && !again.isL2Enabled(for: .shadownet))
    }
}

@MainActor
struct EtherlinkRowTests {
    static let tz4 = Wallet(alias: "bls", address: Address("tz4HVR6aty9KwsQFHh81C1G7gBdhxT8kuytm"), keyKind: .unencrypted)

    private func etherlinkRow(_ model: WalletViewModel) -> AssetBalance? { model.assets.first { $0.kind == .etherlink } }

    @Test func rowFollowsTheNetworkSettingAndTheKeyKind() async {
        let model = WalletViewModel(wallets: WalletViewModel.sampleWallets + [Self.tz4], chain: MockChainService())
        await model.refresh()
        #expect(model.assets.map(\.id) == ["tez"])          // Layer 2 is off by default
        model.setL2Enabled(true, for: .mainnet)
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
        model.setL2Enabled(true, for: .mainnet)
        await model.refresh()
        #expect(model.errorMessage == nil && model.assets.map(\.id) == ["tez", "etherlink"])
        #expect(etherlinkRow(model)?.unavailable?.contains("Etherlink balance unavailable") == true)
    }

    @Test func anAccountNotOnLayer1ShowsNoEtherlinkRow() async {
        let model = WalletViewModel(wallets: WalletViewModel.sampleWallets, chain: FailingEtherlink(notOnChain: true))
        model.setL2Enabled(true, for: .mainnet)
        await model.refresh()
        #expect(model.accountNotOnChain && model.assets.isEmpty)
    }
}

/// Live: the Shadownet Etherlink endpoint answers as a Tezos node and refuses a wrong chain id.
struct EtherlinkLiveTests {
    /// A transfer between two tz accounts on the Michelson interface, through the ordinary
    /// Taquito path against the Layer 2 node: fund on layer 1, deposit through the bridge, then
    /// send on Etherlink and watch both balances move.
    @Test(.tags(.network), .liveNetwork, .timeLimit(.minutes(8)))
    func sendsTezBetweenAccountsOnEtherlink() async throws {
        let layer1 = TaquitoChainService(network: Network.shadownet.l2On)
        let layer2 = TaquitoChainService(network: try #require(Network.shadownet.l2On.layer2))
        let generator = KeyGenerator()
        let payer = try await generator.generate(scheme: .tz1)
        let payee = try await generator.generate(scheme: .tz2)
        let wallet = Wallet(alias: "l2-payer", address: Address(payer.address), scheme: .tz1, publicKey: payer.publicKey, keyKind: .unencrypted)
        let signer = SigningKey.secret(payer.secretKey, passphrase: nil, address: wallet.address)

        let faucet = try #require(FaucetService(network: .shadownet))
        _ = try await faucet.requestTez(to: wallet.address, amount: 10)
        var funded = false
        for _ in 0..<40 { try await Task.sleep(for: .seconds(4)); if let b = try? await layer1.tezBalance(for: wallet.address), b.spendable >= 10 { funded = true; break } }
        #expect(funded)

        let deposit = try await layer1.estimateEtherlinkDeposit(from: wallet, amount: 3)
        let sent = try await layer1.sendEtherlinkDeposit(from: wallet, signer: signer, amount: 3, limits: try #require(deposit.limits))
        _ = try await layer1.waitForConfirmation(of: sent.hash)
        var credited = false
        for _ in 0..<45 { try await Task.sleep(for: .seconds(4)); if let b = try? await layer1.etherlinkBalance(for: wallet.address), b >= 3 { credited = true; break } }
        #expect(credited)

        // Now the account is on Etherlink: an ordinary transfer there, fee and all.
        let before = try await layer2.tezBalance(for: wallet.address)
        #expect(before.spendable == 3)
        let estimate = try await layer2.estimateTransfer(from: wallet, to: Address(payee.address), amount: 1)
        #expect(estimate.limits != nil)
        let transfer = try await layer2.sendTransfer(from: wallet, signer: signer, to: Address(payee.address), amount: 1, limits: try #require(estimate.limits))
        print("etherlink transfer \(transfer.hash)")
        let level = try await layer2.waitForConfirmation(of: transfer.hash)
        #expect(level > 0)
        #expect(try await layer2.tezBalance(for: Address(payee.address)).spendable == 1)
        #expect(try await layer2.tezBalance(for: wallet.address).spendable < 2)
    }

    @Test(.tags(.network), .liveNetwork, .timeLimit(.minutes(1)))
    func readsABalanceFromShadownetEtherlink() async throws {
        let chain = TaquitoChainService(network: Network.shadownet.l2On)
        let balance = try await chain.etherlinkBalance(for: Address("tz1KqTpEZ7Yob7QbPE4Hy4Wo8fHG8LhKxZSx"))
        #expect(balance >= 0)
        await #expect(throws: ChainError.noEtherlinkNode) { _ = try await TaquitoChainService(network: .shadownet).etherlinkBalance(for: Address("tz1KqTpEZ7Yob7QbPE4Hy4Wo8fHG8LhKxZSx")) }
        var wrongChain = Network.shadownet.l2On
        wrongChain.expectedL2ChainID = Network.mainnet.expectedL2ChainID
        await #expect(throws: ChainError.wrongChain(expected: Network.mainnet.expectedL2ChainID!, found: Network.shadownet.expectedL2ChainID!)) {
            try await TaquitoChainService(network: wrongChain).etherlinkBalance(for: Address("tz1KqTpEZ7Yob7QbPE4Hy4Wo8fHG8LhKxZSx"))
        }
    }
}

// MARK: - Alias linking (0.9.3)

/// The EVM-side address is shown only once it exists on chain; before that the account links
/// itself with a gateway no-op on the Layer 2 node.
@MainActor
struct EtherlinkAliasTests {
    @Test func statusAndLinkGoThroughTheLayer2Service() async throws {
        let store = InMemoryWalletStore()
        try store.add(WalletViewModel.sampleWallets[0], secretKey: "edskSAMPLE")
        try store.add(WalletViewModel.sampleWallets[1], secretKey: "edeskSAMPLE")
        let model = WalletViewModel(wallets: WalletViewModel.sampleWallets, chain: MockChainService(), walletStore: store)
        MockChainService.linkedAliases = []
        let me = WalletViewModel.sampleWallets[0]
        let alias = EtherlinkAlias.address(for: me.address)

        #expect(try await model.etherlinkAliasStatus() == nil)                                   // Layer 2 off
        model.setL2Enabled(true, for: .mainnet)
        #expect(try await model.etherlinkAliasStatus() == .unlinked(evmAddress: alias))
        await #expect(throws: WalletViewModel.WalletError.notEstimated) { _ = try await model.linkToEtherlink(limits: nil, passphrase: nil) }
        let estimate = try await model.estimateEtherlinkLink()
        #expect(estimate.fee > 0 && estimate.limits != nil)
        let (hash, level) = try await model.linkToEtherlink(limits: estimate.limits, passphrase: nil)
        #expect(hash == "ooMockLink" && level > 0)
        #expect(try await model.etherlinkAliasStatus() == .linked(evmAddress: alias))

        // An encrypted key needs its password; a watch-only or tz4 account cannot link at all.
        model.select(WalletViewModel.sampleWallets[1])
        let again = try await model.estimateEtherlinkLink()
        await #expect(throws: ChainError.wrongPassphrase) { _ = try await model.linkToEtherlink(limits: again.limits, passphrase: "wrong") }
        let watch = Wallet(alias: "watch", address: Address("tz3WXYtyDUNL91qfiCJtVUX746QpNv5i5ve5"))
        let tz4 = Wallet(alias: "bls", address: Address("tz4HVR6aty9KwsQFHh81C1G7gBdhxT8kuytm"), publicKey: "BLpk", keyKind: .unencrypted)
        let others = WalletViewModel(wallets: [watch, tz4], chain: MockChainService())
        others.setL2Enabled(true, for: .mainnet)
        await #expect(throws: SendViewModel.SendError.self) { _ = try await others.estimateEtherlinkLink() }
        others.select(tz4)
        #expect(try await others.etherlinkAliasStatus() == nil)
    }

    @Test func viewRepliesAreParsedAndCheckedAgainstTheDerivedAddress() throws {
        let me = Address("tz1VSVEv2mCtMYczcTDyeVg4DRUvy57ENN8E")
        let alias = "0x68767b38768e554a31735268b2d356d5cc75d96c"
        func reply(_ kind: String, _ named: String) -> Data {
            Data(#"{"data":{"prim":"Some","args":[{"prim":"Pair","args":[{"int":"\#(kind)"},{"string":"\#(named)"}]}]}}"#.utf8)
        }
        // As the Shadownet gateway answered, checksum-cased.
        #expect(try TaquitoChainService.aliasStatus(from: reply("0", "0x68767b38768E554A31735268b2d356d5Cc75D96c"), for: me) == .linked(evmAddress: alias))
        #expect(try TaquitoChainService.aliasStatus(from: reply("1", alias), for: me) == .unlinked(evmAddress: alias))
        #expect(throws: (any Error).self) { try TaquitoChainService.aliasStatus(from: reply("0", "0x16142132dd616dd8f61b8972ae4b9fcf8a22a450"), for: me) }
        #expect(throws: (any Error).self) { try TaquitoChainService.aliasStatus(from: reply("2", alias), for: me) }
        #expect(throws: (any Error).self) { try TaquitoChainService.aliasStatus(from: Data(#"{"data":{"prim":"None"}}"#.utf8), for: me) }
    }

    @Test func layer1ServicesRefuseAliasCalls() async throws {
        let layer1 = TaquitoChainService(network: Network.shadownet.l2On)
        await #expect(throws: ChainError.notALayer2Service) { _ = try await layer1.etherlinkAliasStatus(for: Address("tz1VSUr8wwNhLAzempoch5d6hLRiTh8Cjcjb")) }
        await #expect(throws: ChainError.notALayer2Service) { _ = try await layer1.estimateEtherlinkLink(from: WalletViewModel.sampleWallets[0]) }
        #expect(TaquitoBridge.kind(of: "sendEtherlinkLink") == .signing)
    }
}

extension EtherlinkLiveTests {
    /// A fresh account is only derived on Etherlink until it links itself; after the gateway
    /// no-op the view records it. The account needs tez on Etherlink first (bridge deposit).
    @Test(.tags(.network), .liveNetwork, .timeLimit(.minutes(8)))
    func linksAFreshAccountToItsEtherlinkAlias() async throws {
        let layer1 = TaquitoChainService(network: Network.shadownet.l2On)
        let layer2 = TaquitoChainService(network: try #require(Network.shadownet.l2On.layer2))
        let material = try await KeyGenerator().generate(scheme: .tz1)
        let wallet = Wallet(alias: "link-test", address: Address(material.address), scheme: .tz1, publicKey: material.publicKey, keyKind: .unencrypted)
        let signer = SigningKey.secret(material.secretKey, passphrase: nil, address: wallet.address)
        let alias = EtherlinkAlias.address(for: wallet.address)
        #expect(try await layer2.etherlinkAliasStatus(for: wallet.address) == .unlinked(evmAddress: alias))

        let faucet = try #require(FaucetService(network: .shadownet))
        _ = try await faucet.requestTez(to: wallet.address, amount: 10)
        var funded = false
        for _ in 0..<40 { try await Task.sleep(for: .seconds(4)); if let b = try? await layer1.tezBalance(for: wallet.address), b.spendable >= 10 { funded = true; break } }
        #expect(funded)
        let deposit = try await layer1.estimateEtherlinkDeposit(from: wallet, amount: 2)
        let sent = try await layer1.sendEtherlinkDeposit(from: wallet, signer: signer, amount: 2, limits: try #require(deposit.limits))
        _ = try await layer1.waitForConfirmation(of: sent.hash)
        var credited = false
        for _ in 0..<45 { try await Task.sleep(for: .seconds(4)); if let b = try? await layer1.etherlinkBalance(for: wallet.address), b >= 2 { credited = true; break } }
        #expect(credited)
        // Money on the Michelson side does not link the EVM side.
        #expect(try await layer2.etherlinkAliasStatus(for: wallet.address) == .unlinked(evmAddress: alias))

        let estimate = try await layer2.estimateEtherlinkLink(from: wallet)
        #expect(estimate.fee > 0 && estimate.limits != nil)
        let link = try await layer2.sendEtherlinkLink(from: wallet, signer: signer, limits: try #require(estimate.limits))
        print("etherlink link \(link.hash)")
        #expect(try await layer2.waitForConfirmation(of: link.hash) > 0)
        #expect(try await layer2.etherlinkAliasStatus(for: wallet.address) == .linked(evmAddress: alias))
    }
}
