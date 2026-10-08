import Foundation
import Testing
@testable import Signet

struct StakingOperationTests {
    @Test func mapsToBridgeKindsAndArguments() {
        #expect(StakingOperation.delegate(to: nil).bridgeKind == "setDelegate")
        #expect(StakingOperation.delegate(to: nil).bridgeArgument["delegate"] as? String == "")
        #expect(StakingOperation.delegate(to: MockChainService.captainStake).bridgeArgument["delegate"] as? String == MockChainService.captainStake.value)
        #expect(StakingOperation.stake(Decimal(string: "1.5")!).bridgeArgument["amountMutez"] as? String == "1500000")
        #expect(StakingOperation.unstake(2).bridgeKind == "unstake")
        #expect(StakingOperation.finalizeUnstake.bridgeArgument.isEmpty)
        #expect(StakingOperation.updateConsensusKey(publicKey: "edpkX", proof: nil).bridgeArgument.keys.sorted() == ["pk"])
        #expect(StakingOperation.updateCompanionKey(publicKey: "BLpkX", proof: "BLsigP").bridgeArgument.keys.sorted() == ["pk", "proof"])
        #expect(StakingOperation.registerAsBaker.title == "Register as a baker")
    }

    @Test func bakersCanAlwaysStakeOthersNeedAWillingDelegate() {
        let me = Address("tz1VSUr8wwNhLAzempoch5d6hLRiTh8Cjcjb")
        let baker = DelegateInfo.Baker(deactivated: false, gracePeriod: nil, consensusKey: nil, pendingConsensusKeys: [], companionKey: nil, pendingCompanionKeys: [])
        // A baker with the default limit of 0 does not accept outside stakers but can still stake its own tez.
        #expect(DelegateInfo(delegate: me, baker: baker, delegateAcceptsStaking: false).canStake)
        #expect(DelegateInfo(delegate: me, baker: baker, delegateAcceptsStaking: nil).canStake)
        #expect(DelegateInfo(delegate: MockChainService.captainStake, baker: nil, delegateAcceptsStaking: true).canStake)
        #expect(DelegateInfo(delegate: MockChainService.captainStake, baker: nil, delegateAcceptsStaking: nil).canStake)
        #expect(!DelegateInfo(delegate: MockChainService.captainStake, baker: nil, delegateAcceptsStaking: false).canStake)
        #expect(!DelegateInfo(delegate: nil, baker: nil, delegateAcceptsStaking: nil).canStake)
    }

    @Test func parsesBakersFromTzKT() {
        let json = """
        [{"address":"tz3cqThj23Feu55KDynm7Vg81mCMpWDgzQZq","alias":"Tezos Foundation Baker 1","stakingBalance":24666552157412,"numDelegators":18,"stakersCount":4,"limitOfStakingOverBaking":9000000},
         {"address":"tz1irJKkXS2DBWkU1NnmFQx1c1L7pbGg4yhk","alias":"Coinbase Baker","stakingBalance":104790106393592,"numDelegators":2810,"stakersCount":0,"limitOfStakingOverBaking":null}]
        """.data(using: .utf8)!
        let bakers = TzKTService.parseBakers(json)
        #expect(bakers.count == 2)
        #expect(bakers[0].alias == "Tezos Foundation Baker 1")
        #expect(bakers[0].acceptsStaking == true)
        #expect(bakers[0].stakingBalance == Decimal(string: "24666552.157412"))
        #expect(bakers[1].acceptsStaking == nil)
        #expect(bakers[1].delegators == 2810)
    }
}

@MainActor
struct StakingViewModelTests {
    @Test func refreshLoadsDelegateInfoAndOperationsRoundTrip() async throws {
        let store = InMemoryWalletStore()
        for wallet in WalletViewModel.sampleWallets { try store.add(wallet, secretKey: "edsk\(wallet.alias)") }
        let model = WalletViewModel(wallets: nil, chain: MockChainService(), walletStore: store)
        await model.refresh()
        #expect(model.delegateInfo?.delegate == MockChainService.captainStake)
        #expect(model.delegateInfo?.isBaker == false)

        let estimate = try await model.estimateStaking(.stake(1))
        #expect(estimate.fee > 0)
        let result = try await model.performStaking(.delegate(to: MockChainService.captainStake), passphrase: nil)
        #expect(result.hash == "ooMockStakingsetDelegate")
        #expect(result.level == 9_000_000)
        #expect((await model.bakers()).first?.alias == "Captain Stake")
    }

    @Test func encryptedWalletNeedsThePassword() async {
        let vault = Wallet(alias: "Vault", address: Address("tz1VSUr8wwNhLAzempoch5d6hLRiTh8Cjcjb"), publicKey: "edpkV", keyKind: .encrypted)
        let store = InMemoryWalletStore()
        try? store.add(vault, secretKey: "edeskFAKE")
        let model = WalletViewModel(wallets: nil, chain: MockChainService(), walletStore: store)
        await #expect(throws: ChainError.wrongPassphrase) {
            _ = try await model.performStaking(.finalizeUnstake, passphrase: "nope")
        }
        let ok = try? await model.performStaking(.finalizeUnstake, passphrase: "correct horse")
        #expect(ok?.hash == "ooMockStakingfinalizeUnstake")
    }
}

/// Live: a fresh tz1 on Quantumnet delegates to a baker, stakes, and registers as a baker itself.
struct QuantumnetStakingTests {
    @Test(.tags(.network), .timeLimit(.minutes(6)))
    func delegateStakeAndRegisterOnQuantumnet() async throws {
        let chain = TaquitoChainService(network: .quantumnet)
        let material = try await KeyGenerator().generate(scheme: .tz1)
        let wallet = Wallet(alias: "stake-test", address: Address(material.address), scheme: .tz1, publicKey: material.publicKey, keyKind: .unencrypted)
        let faucet = try #require(FaucetService(network: .quantumnet))
        _ = try await faucet.requestTez(to: wallet.address, amount: 20)
        var funded = false
        for _ in 0..<30 {
            try await Task.sleep(for: .seconds(4))
            if let b = try? await chain.tezBalance(for: wallet.address), b.spendable >= 20 { funded = true; break }
        }
        #expect(funded)

        let before = try await chain.delegateInfo(for: wallet.address)
        #expect(before.delegate == nil && !before.isBaker)

        let bakers = try await chain.bakers(limit: 10)
        let baker = try #require(bakers.first(where: { $0.acceptsStaking == true }) ?? bakers.first, "no bakers listed on Quantumnet")

        let d = try await chain.performStaking(.delegate(to: baker.address), from: wallet, signer: .secret(material.secretKey, passphrase: nil))
        _ = try await chain.waitForConfirmation(of: d)
        let delegated = try await chain.delegateInfo(for: wallet.address)
        #expect(delegated.delegate == baker.address)

        if delegated.delegateAcceptsStaking == true {
            let s = try await chain.performStaking(.stake(5), from: wallet, signer: .secret(material.secretKey, passphrase: nil))
            _ = try await chain.waitForConfirmation(of: s)
            try await Task.sleep(for: .seconds(8))
            let after = try await chain.tezBalance(for: wallet.address)
            #expect(after.staked >= 5, Comment(rawValue: "staked \(after.staked)"))
        } else {
            print("baker \(baker.alias ?? baker.address.value) does not accept staking; skipped the stake step")
        }

        let r = try await chain.performStaking(.registerAsBaker, from: wallet, signer: .secret(material.secretKey, passphrase: nil))
        _ = try await chain.waitForConfirmation(of: r)
        let registered = try await chain.delegateInfo(for: wallet.address)
        #expect(registered.isBaker)
        #expect(registered.delegate == wallet.address)
        print("Quantumnet: delegated \(d), registered \(r)")
    }
}

struct StakingParametersTests {
    @Test func convertsBetweenProtocolUnitsAndHumanNumbers() throws {
        let p = StakingParameters(limitMillionth: 9_000_000, edgeBillionth: 10_000_000)
        #expect(p.limitMultiplier == 9)
        #expect(p.edgePercent == 1)
        let q = try #require(StakingParameters(limitMultiplier: Decimal(string: "2.5")!, edgePercent: 15))
        #expect(q.limitMillionth == 2_500_000)
        #expect(q.edgeBillionth == 150_000_000)
        #expect(StakingParameters(limitMultiplier: 10, edgePercent: 0) == nil)
        #expect(StakingParameters(limitMultiplier: 1, edgePercent: 101) == nil)
        let op = StakingOperation.setStakingParameters(q, source: MockChainService.captainStake)
        #expect(op.bridgeKind == "setDelegateParameters")
        #expect(op.bridgeArgument["limitMillionth"] as? Int == 2_500_000)
        #expect(op.bridgeArgument["source"] as? String == MockChainService.captainStake.value)
        #expect(TaquitoChainService.taquitoEncodablePublicKey("edpkX") && !TaquitoChainService.taquitoEncodablePublicKey("xmpkX"))
    }
}

/// Live: a freshly registered Quantumnet baker sets its staking parameters, and if an XMSS (tz6)
/// public key is available from the local octez-client wallet, points its consensus key at it
/// through the raw node-forged path.
struct QuantumnetBakerParametersTests {
    @Test(.tags(.network), .timeLimit(.minutes(6)))
    func setsParametersAndMaybeATz6ConsensusKey() async throws {
        let chain = TaquitoChainService(network: .quantumnet)
        let material = try await KeyGenerator().generate(scheme: .tz1)
        let wallet = Wallet(alias: "baker-test", address: Address(material.address), scheme: .tz1, publicKey: material.publicKey, keyKind: .unencrypted)
        _ = try await FaucetService(network: .quantumnet)!.requestTez(to: wallet.address, amount: 20)
        var funded = false
        for _ in 0..<30 { try await Task.sleep(for: .seconds(4)); if let b = try? await chain.tezBalance(for: wallet.address), b.spendable >= 20 { funded = true; break } }
        #expect(funded)

        let reg = try await chain.performStaking(.registerAsBaker, from: wallet, signer: .secret(material.secretKey, passphrase: nil))
        _ = try await chain.waitForConfirmation(of: reg)

        let params = try #require(StakingParameters(limitMultiplier: 5, edgePercent: 10))
        let estimate = try await chain.estimateStaking(.setStakingParameters(params, source: wallet.address), from: wallet)
        #expect(estimate.fee > 0)
        let setHash = try await chain.performStaking(.setStakingParameters(params, source: wallet.address), from: wallet, signer: .secret(material.secretKey, passphrase: nil))
        _ = try await chain.waitForConfirmation(of: setHash)
        try await Task.sleep(for: .seconds(4))
        let info = try await chain.delegateInfo(for: wallet.address)
        #expect(info.isBaker)
        #expect(info.baker?.pendingStakingParameters.contains { $0.limitMillionth == 5_000_000 && $0.edgeBillionth == 100_000_000 } == true,
                Comment(rawValue: "pending: \(String(describing: info.baker?.pendingStakingParameters))"))

        // tz6 consensus key via the raw path, if we have an xmpk public key to hand.
        let octezKeys = TezosClientStore.octezClientDirectory.appendingPathComponent("public_keys")
        if let data = try? Data(contentsOf: octezKeys), let rows = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
           let xmpk = rows.compactMap({ ($0["value"] as? [String: Any])?["key"] as? String }).first(where: { $0.hasPrefix("xmpk") }) {
            let est = try await chain.estimateStaking(.updateConsensusKey(publicKey: xmpk, proof: nil), from: wallet)
            #expect(est.fee > 0)
            let hash: String
            do {
                hash = try await chain.performStaking(.updateConsensusKey(publicKey: xmpk, proof: nil), from: wallet, signer: .secret(material.secretKey, passphrase: nil))
            } catch TaquitoBridge.BridgeError.javaScript(let message) where message.contains("consensus_key.active") {
                // A consensus key serves one baker at a time; an earlier run of this test already took it.
                print("xmpk \(xmpk.prefix(12))… is already another baker's consensus key; skipped the tz6 step")
                return
            }
            let level = try await chain.waitForConfirmation(of: hash)
            #expect(level > 0)
            try await Task.sleep(for: .seconds(4))
            let after = try await chain.delegateInfo(for: wallet.address)
            #expect(!(after.baker?.pendingConsensusKeys.isEmpty ?? true) || after.baker?.consensusKey != nil, Comment(rawValue: "baker after: \(String(describing: after.baker))"))
            print("tz6 consensus key set on Quantumnet in block \(level): \(hash)")
        } else {
            print("no xmpk public key in ~/.tezos-client; skipped the tz6 consensus-key step")
        }
    }
}
