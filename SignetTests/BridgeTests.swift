import Foundation
import Testing
@testable import Signet

/// The Etherlink bridge (0.9.1): where it is offered and how a deposit is carried out.
struct BridgeNetworkTests {
    @Test func shippedNetworksKnowTheirBridgeOthersDoNot() {
        #expect(!Network.mainnet.canDepositToL2)   // Layer 2 is off by default
        #expect(Network.mainnet.l2On.canDepositToL2 && Network.mainnet.l2BridgeHelper?.value == "KT1Wj8SUGmnEPFqyahHAcjcNQwe6YGhEXJb5" && Network.mainnet.l2Rollup == "sr1Ghq66tYK9y3r8CC1Tf8i8m5nxh8nTvZEf")
        #expect(Network.shadownet.l2On.canDepositToL2 && Network.shadownet.l2BridgeHelper?.value == "KT19aBsSWvWtvEkbiqReJnD8UzQMWcD8SHUD" && Network.shadownet.l2Rollup == "sr19fMYrr5C4qqvQqQrDSjtP31GcrWjodzvg")
        // A user-supplied Layer 2 node brings no bridge with it.
        let bakingnet = Network.bakingnet.usingL2(enabled: true, node: URL(string: "https://l2.example.org")!)
        #expect(bakingnet.hasL2 && !bakingnet.canDepositToL2)
        // Layer 2 off hides the bridge too.
        #expect(!Network.mainnet.l2On.usingL2(enabled: false, node: Network.mainnet.l2RPCURL).canDepositToL2)
    }
}

@MainActor
struct BridgeModelTests {
    static let tz4 = Wallet(alias: "bls", address: Address("tz4HVR6aty9KwsQFHh81C1G7gBdhxT8kuytm"), publicKey: "BLpk", keyKind: .unencrypted)
    static let watch = Wallet(alias: "watch", address: Address("tz3WXYtyDUNL91qfiCJtVUX746QpNv5i5ve5"))

    @Test func bridgeIsOfferedOnlyWhereItCanWork() {
        let model = WalletViewModel(wallets: WalletViewModel.sampleWallets + [Self.tz4, Self.watch], chain: MockChainService())
        #expect(model.network.name == "Mainnet" && !model.canBridge)             // Layer 2 off by default
        model.setL2Enabled(true, for: .mainnet)
        #expect(model.canBridge)                                                  // tz1 we can sign for
        model.select(WalletViewModel.sampleWallets[1])
        #expect(model.canBridge)                                                  // tz2, encrypted: password at confirm time
        model.select(Self.tz4)
        #expect(!model.canBridge)                                                 // no tz4 on the rollup yet
        model.select(Self.watch)
        #expect(!model.canBridge)                                                 // nothing to sign with
        model.select(WalletViewModel.sampleWallets[0])
        model.setL2Enabled(false, for: .mainnet)
        #expect(!model.canBridge)
        model.setL2Enabled(true, for: .mainnet)
        model.switchNetwork(to: .bakingnet)
        #expect(!model.canBridge)                                                 // no bridge shipped there
    }

    @Test func depositNeedsAnEstimateAPositiveAmountAndTheRightPassword() async throws {
        let store = InMemoryWalletStore()
        try store.add(WalletViewModel.sampleWallets[0], secretKey: "edskSAMPLE")
        try store.add(WalletViewModel.sampleWallets[1], secretKey: "edeskSAMPLE")
        let model = WalletViewModel(wallets: WalletViewModel.sampleWallets, chain: MockChainService(), walletStore: store)
        model.setL2Enabled(true, for: .mainnet)
        let approved = try await model.estimateBridgeDeposit(amount: 2)
        let estimate = approved.estimate
        #expect(estimate.limits != nil && estimate.total == 2 + estimate.fee)
        await #expect(throws: SendViewModel.SendError.self) { _ = try await model.estimateBridgeDeposit(amount: 0) }
        await #expect(throws: WalletViewModel.WalletError.notEstimated) { _ = try await model.bridgeToEtherlink(amount: 2, approved: nil, passphrase: nil) }
        await #expect(throws: SendViewModel.SendError.self) { _ = try await model.bridgeToEtherlink(amount: -1, approved: approved, passphrase: nil) }
        let (hash, level) = try await model.bridgeToEtherlink(amount: 2, approved: approved, passphrase: nil)
        #expect(hash == "ooMockDeposit" && level > 0)

        model.select(WalletViewModel.sampleWallets[1])   // encrypted
        // The estimate was for the other account (S31): it must be made again for this one.
        await #expect(throws: WalletViewModel.WalletError.contextChanged) { _ = try await model.bridgeToEtherlink(amount: 1, approved: approved, passphrase: "correct horse") }
        let again = try await model.estimateBridgeDeposit(amount: 1)
        await #expect(throws: ChainError.wrongPassphrase) { _ = try await model.bridgeToEtherlink(amount: 1, approved: again, passphrase: "wrong") }
        _ = try await model.bridgeToEtherlink(amount: 1, approved: again, passphrase: "correct horse")

        model.setL2Enabled(false, for: .mainnet)
        await #expect(throws: WalletViewModel.WalletError.contextChanged) { _ = try await model.bridgeToEtherlink(amount: 1, approved: again, passphrase: "correct horse") }
    }

    /// Every part of the context a deposit was estimated in must still hold when it is sent (S31).
    @Test func depositEstimatesAreBoundToAccountNetworkNodeAndDirectory() async throws {
        let store = InMemoryWalletStore()
        try store.add(WalletViewModel.sampleWallets[0], secretKey: "edskSAMPLE")
        let model = WalletViewModel(wallets: WalletViewModel.sampleWallets, chain: MockChainService(), walletStore: store)
        model.setL2Enabled(true, for: .mainnet)
        let changes: [(String, @MainActor () -> Void)] = [
            ("network", { model.switchNetwork(to: .shadownet); model.setL2Enabled(true, for: .shadownet) }),
            ("layer 1 node", { _ = model.setNode("https://rpc.example.org") }),
            ("layer 2 node", { _ = model.setL2Node("https://l2.example.org", for: .mainnet) }),
            ("layer 2 off and on again", { model.setL2Enabled(false, for: .mainnet); model.setL2Enabled(true, for: .mainnet) }),
            ("account", { model.select(WalletViewModel.sampleWallets[1]) }),
        ]
        for (what, change) in changes {
            model.switchNetwork(to: .mainnet)
            model.select(WalletViewModel.sampleWallets[0])
            let approved = try await model.estimateBridgeDeposit(amount: 1)
            change()
            if what == "layer 2 off and on again" {
                // Same context again: the estimate still fits it.
                _ = try await model.bridgeToEtherlink(amount: 1, approved: approved, passphrase: nil)
                continue
            }
            await #expect(throws: WalletViewModel.WalletError.contextChanged, "\(what)") { _ = try await model.bridgeToEtherlink(amount: 1, approved: approved, passphrase: nil) }
        }
        model.useDefaultNode(); model.useDefaultL2Node(for: .mainnet); model.select(WalletViewModel.sampleWallets[0])
        // A context that moved while the node was being asked is refused at the estimate itself.
        let box = ModelBox()
        let slow = SlowEstimateChain { box.model?.select(WalletViewModel.sampleWallets[1]) }
        let moving = WalletViewModel(wallets: WalletViewModel.sampleWallets, chain: slow, walletStore: store)
        box.model = moving
        moving.setL2Enabled(true, for: .mainnet)
        await #expect(throws: WalletViewModel.WalletError.contextChanged) { _ = try await moving.estimateBridgeDeposit(amount: 1) }
    }
}

/// Live: a fresh Shadownet account deposits 1 tez to itself on Etherlink through the bridge and
/// the rollup credits it.
struct ShadownetBridgeTests {
    @Test(.tags(.network), .liveNetwork, .timeLimit(.minutes(6)))
    func depositsTezToTheSameAccountOnEtherlink() async throws {
        let chain = TaquitoChainService(network: Network.shadownet.l2On)
        let material = try await KeyGenerator().generate(scheme: .tz1)
        let wallet = Wallet(alias: "bridge-test", address: Address(material.address), scheme: .tz1, publicKey: material.publicKey, keyKind: .unencrypted)
        let signer = SigningKey.secret(material.secretKey, passphrase: nil, address: wallet.address)

        let faucet = try #require(FaucetService(network: .shadownet))
        _ = try await faucet.requestTez(to: wallet.address, amount: 10)
        var funded = false
        for _ in 0..<40 { try await Task.sleep(for: .seconds(4)); if let b = try? await chain.tezBalance(for: wallet.address), b.spendable >= 10 { funded = true; break } }
        #expect(funded)
        #expect(try await chain.etherlinkBalance(for: wallet.address) == 0)

        let estimate = try await chain.estimateEtherlinkDeposit(from: wallet, amount: 1)
        #expect(estimate.fee > 0 && estimate.limits != nil)
        let sent = try await chain.sendEtherlinkDeposit(from: wallet, signer: signer, amount: 1, limits: try #require(estimate.limits))
        print("bridge deposit \(sent.hash)")
        let level = try await chain.waitForConfirmation(of: sent.hash)
        #expect(level > 0)

        var credited: Decimal = 0
        for _ in 0..<45 {
            try await Task.sleep(for: .seconds(4))
            if let balance = try? await chain.etherlinkBalance(for: wallet.address), balance > 0 { credited = balance; break }
        }
        #expect(credited == 1, "the rollup never credited the deposit")
        let after = try await chain.tezBalance(for: wallet.address)
        #expect(after.spendable < 9)
    }
}


private final class ModelBox: @unchecked Sendable { var model: WalletViewModel? }

/// A chain whose deposit estimate lets the test move the model before answering.
private struct SlowEstimateChain: TestChainService {
    let during: @MainActor @Sendable () -> Void
    init(during: @escaping @MainActor @Sendable () -> Void) { self.during = during }
    func tezBalance(for address: Address) async throws -> TezBalance { TezBalance(spendable: 10, staked: 0, unstakedFrozen: 0, unstakedFinalizable: 0) }
    func estimateEtherlinkDeposit(from wallet: Wallet, amount: Decimal) async throws -> TransferEstimate {
        await during()
        return TransferEstimate(fee: 0.001, burn: 0, total: amount + 0.001, gasLimit: 0, storageLimit: 0, limits: OperationLimits(feeMutez: "1000", gasLimit: 0, storageLimit: 0))
    }
}

/// A chain service that remembers which network it was built for.
private struct LabelledChain: TestChainService {
    let network: Network
    func tezBalance(for address: Address) async throws -> TezBalance { TezBalance(spendable: 10, staked: 0, unstakedFrozen: 0, unstakedFinalizable: 0) }
}

/// The Send sheet keeps the network it shows and the service it signs through together (S31).
@MainActor
struct SendSideContextTests {
    @Test func capturedSidesSurviveSettingsChanges() throws {
        let model = WalletViewModel(wallets: WalletViewModel.sampleWallets, chainFactory: { LabelledChain(network: $0) })
        model.setL2Enabled(true, for: .mainnet)
        let (layer1, layer2) = SendSheet.capture(model)
        let etherlink = try #require(layer2)
        #expect(layer1.network.name == "Mainnet" && layer1.network.hasL2 && (layer1.chain as? LabelledChain)?.network == layer1.network && !layer1.implicitAccountsOnly)
        #expect(etherlink.network.layerNumber == 2 && (etherlink.chain as? LabelledChain)?.network == etherlink.network && etherlink.implicitAccountsOnly)

        // Layer 2 turned off, the network switched and the node changed after the sheet opened:
        // the captured pair is untouched and still matched, and the live model no longer offers Layer 2.
        model.setL2Enabled(false, for: .mainnet)
        #expect(model.layer2Chain == nil && model.network.layer2 == nil)
        model.switchNetwork(to: .shadownet)
        _ = model.setNode("https://rpc.example.org")
        #expect((etherlink.chain as? LabelledChain)?.network == etherlink.network && etherlink.network.chain == "etherlink-mainnet")
        #expect((layer1.chain as? LabelledChain)?.network == layer1.network && layer1.network.name == "Mainnet")

        // With Layer 2 off when the sheet opens there is no Etherlink side at all: no fallback to layer 1.
        #expect(SendSheet.capture(model).layer2 == nil)
    }
}
