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

        let d = try await chain.performStaking(.delegate(to: baker.address), from: wallet, signer: .secret(material.secretKey, passphrase: nil, address: wallet.address))
        _ = try await chain.waitForConfirmation(of: d)
        let delegated = try await chain.delegateInfo(for: wallet.address)
        #expect(delegated.delegate == baker.address)

        if delegated.delegateAcceptsStaking == true {
            let s = try await chain.performStaking(.stake(5), from: wallet, signer: .secret(material.secretKey, passphrase: nil, address: wallet.address))
            _ = try await chain.waitForConfirmation(of: s)
            try await Task.sleep(for: .seconds(8))
            let after = try await chain.tezBalance(for: wallet.address)
            #expect(after.staked >= 5, Comment(rawValue: "staked \(after.staked)"))
        } else {
            print("baker \(baker.alias ?? baker.address.value) does not accept staking; skipped the stake step")
        }

        let r = try await chain.performStaking(.registerAsBaker, from: wallet, signer: .secret(material.secretKey, passphrase: nil, address: wallet.address))
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

        let reg = try await chain.performStaking(.registerAsBaker, from: wallet, signer: .secret(material.secretKey, passphrase: nil, address: wallet.address))
        _ = try await chain.waitForConfirmation(of: reg)

        let params = try #require(StakingParameters(limitMultiplier: 5, edgePercent: 10))
        let estimate = try await chain.estimateStaking(.setStakingParameters(params, source: wallet.address), from: wallet)
        #expect(estimate.fee > 0)
        let setHash = try await chain.performStaking(.setStakingParameters(params, source: wallet.address), from: wallet, signer: .secret(material.secretKey, passphrase: nil, address: wallet.address))
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
            let hash: String
            do {
                let est = try await chain.estimateStaking(.updateConsensusKey(publicKey: xmpk, proof: nil), from: wallet)
                #expect(est.fee > 0)
                hash = try await chain.performStaking(.updateConsensusKey(publicKey: xmpk, proof: nil), from: wallet, signer: .secret(material.secretKey, passphrase: nil, address: wallet.address))
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

/// S01: the raw path signs bytes Signet forges itself, and only when the node forges the same.
struct RawForgingTests {
    static let branch = "BLockGenesisGenesisGenesisGenesisGenesisf79b5d1CoW2"
    static let bridge = TaquitoBridge.shared

    private func ours(_ contents: [[String: Any]]) async throws -> String {
        let json = String(data: try JSONSerialization.data(withJSONObject: contents), encoding: .utf8)!
        return try #require(try await Self.bridge.call("forgeRawForTest", [Self.branch, json]).stringValue)
    }

    private func taquitos(_ contents: [[String: Any]]) async throws -> String {
        let json = String(data: try JSONSerialization.data(withJSONObject: contents), encoding: .utf8)!
        return try #require(try await Self.bridge.call("taquitoForgeForTest", [Self.branch, json]).stringValue)
    }

    private func header(_ kind: String, source: String, counter: String, fee: String = "1234", gas: String = "10100", storage: String = "0") -> [String: Any] {
        ["kind": kind, "source": source, "fee": fee, "counter": counter, "gas_limit": gas, "storage_limit": storage]
    }

    @Test(arguments: [AddressScheme.tz1, .tz2, .tz3, .tz4, .tz5])
    func forgesRevealAndConsensusKeyUpdatesLikeTaquito(scheme: AddressScheme) async throws {
        let baker = try await KeyGenerator().generate(scheme: .tz1)
        let key = try await KeyGenerator().generate(scheme: scheme)
        var reveal = header("reveal", source: baker.address, counter: "7", fee: "0")
        reveal["public_key"] = baker.publicKey
        var update = header("update_consensus_key", source: baker.address, counter: "8", fee: "300000", gas: "1040000", storage: "60000")
        update["pk"] = key.publicKey
        let contents = [reveal, update]
        #expect(try await ours(contents) == taquitos(contents))
    }

    @Test(arguments: [AddressScheme.tz2, .tz3, .tz4, .tz5])
    func forgesForEverySourceKind(scheme: AddressScheme) async throws {
        let baker = try await KeyGenerator().generate(scheme: scheme)
        let key = try await KeyGenerator().generate(scheme: .tz1)
        var reveal = header("reveal", source: baker.address, counter: "1", fee: "0")
        reveal["public_key"] = baker.publicKey
        var update = header("update_companion_key", source: baker.address, counter: "2")
        update["pk"] = key.publicKey
        #expect(try await ours([reveal, update]) == taquitos([reveal, update]))
    }

    @Test func forgesABLSProofLikeTaquito() async throws {
        let baker = try await KeyGenerator().generate(scheme: .tz1)
        let bls = try await KeyGenerator().generate(scheme: .tz4)
        let proof = try #require(try await Self.bridge.call("provePossession", [SigningKey.secret(bls.secretKey, passphrase: nil, address: Address(bls.address)).bridgeSpec])["proof"]?.stringValue)
        #expect(proof.hasPrefix("BLsig"))
        var update = header("update_consensus_key", source: baker.address, counter: "3")
        update["pk"] = bls.publicKey
        update["proof"] = proof
        #expect(try await ours([update]) == taquitos([update]))
    }

    @Test func zarithAndLargeNumbersMatchTaquito() async throws {
        let baker = try await KeyGenerator().generate(scheme: .tz1)
        var update = header("update_consensus_key", source: baker.address, counter: "123456789", fee: "99999999999", gas: "1040000", storage: "60000")
        update["pk"] = baker.publicKey
        #expect(try await ours([update]) == taquitos([update]))
    }

    /// The audit's attack: the node returns a forged transfer where a consensus-key update was asked for.
    @Test func refusesNodeBytesThatDifferFromOurs() async throws {
        let baker = try await KeyGenerator().generate(scheme: .tz1)
        var update = header("update_consensus_key", source: baker.address, counter: "5")
        update["pk"] = baker.publicKey
        let json = String(data: try JSONSerialization.data(withJSONObject: [update]), encoding: .utf8)!
        let honest = try await ours([update])

        var transfer = header("transaction", source: baker.address, counter: "5", fee: "1234", gas: "1500")
        transfer["amount"] = "50000000"
        transfer["destination"] = "tz1KqTpEZ7Yob7QbPE4Hy4Wo8fHG8LhKxZSx"
        let substituted = try await taquitos([transfer])
        #expect(substituted != honest)

        await #expect(throws: (any Error).self) { try await Self.bridge.call("verifyRawForgingForTest", [Self.branch, json, substituted]) }
        // A single changed byte (fee, branch, key…) is refused too; the honest bytes pass.
        var tampered = honest; tampered.replaceSubrange(tampered.index(tampered.startIndex, offsetBy: 70)..<tampered.index(tampered.startIndex, offsetBy: 72), with: "ff")
        await #expect(throws: (any Error).self) { try await Self.bridge.call("verifyRawForgingForTest", [Self.branch, json, tampered]) }
        await #expect(throws: (any Error).self) { try await Self.bridge.call("verifyRawForgingForTest", [Self.branch, json, honest + "00"]) }
        await #expect(throws: (any Error).self) { try await Self.bridge.call("verifyRawForgingForTest", [Self.branch, json, ""]) }
        #expect(try await Self.bridge.call("verifyRawForgingForTest", [Self.branch, json, honest.uppercased()]).stringValue == honest)
    }

    /// Live: the one key kind Taquito cannot oracle. The Quantumnet node's forge helper must agree
    /// with our encoding of an XMSS (tz6) consensus key, taken from the local octez-client wallet.
    @Test(.tags(.network), .timeLimit(.minutes(1)))
    func forgesAnXMSSKeyLikeTheQuantumnetNode() async throws {
        let octezKeys = TezosClientStore.octezClientDirectory.appendingPathComponent("public_keys")
        guard let data = try? Data(contentsOf: octezKeys), let rows = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
              let xmpk = rows.compactMap({ ($0["value"] as? [String: Any])?["key"] as? String }).first(where: { $0.hasPrefix("xmpk") }) else {
            print("no xmpk in ~/.tezos-client; skipped")
            return
        }
        let rpc = Network.quantumnet.rpcURL
        let head = try await URLSession.shared.data(from: rpc.appendingPathComponent("chains/main/blocks/head/hash")).0
        let branch = try #require(try JSONSerialization.jsonObject(with: head, options: [.fragmentsAllowed]) as? String)
        let baker = try await KeyGenerator().generate(scheme: .tz1)
        var update = header("update_consensus_key", source: baker.address, counter: "9", fee: "4321")
        update["pk"] = xmpk
        let contents: [[String: Any]] = [update]

        var request = URLRequest(url: rpc.appendingPathComponent("chains/main/blocks/head/helpers/forge/operations"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["branch": branch, "contents": contents])
        let (reply, _) = try await URLSession.shared.data(for: request)
        let nodeHex = try #require(try JSONSerialization.jsonObject(with: reply, options: [.fragmentsAllowed]) as? String, Comment(rawValue: String(data: reply, encoding: .utf8) ?? ""))

        let json = String(data: try JSONSerialization.data(withJSONObject: contents), encoding: .utf8)!
        #expect(try await Self.bridge.call("forgeRawForTest", [branch, json]).stringValue == nodeHex)
    }

    @Test func refusesKindsItCannotForge() async throws {
        let baker = try await KeyGenerator().generate(scheme: .tz1)
        var transfer = header("transaction", source: baker.address, counter: "5")
        transfer["amount"] = "1"; transfer["destination"] = baker.address
        await #expect(throws: (any Error).self) { try await ours([transfer]) }
        var bad = header("update_consensus_key", source: baker.address, counter: "5")
        bad["pk"] = "edpkNotARealKeyAtAll"
        await #expect(throws: (any Error).self) { try await ours([bad]) }
    }
}
