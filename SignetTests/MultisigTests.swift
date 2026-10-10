import Foundation
import Testing
@testable import Signet

/// The embedded generic multisig script is byte-for-byte octez-client's: its hash is the one
/// octez-client recognises (`octez-client hash script`), so contracts deployed by either tool
/// are multisigs to the other.
struct MultisigScriptTests {
    @Test func embeddedScriptHashesLikeOctezClient() async throws {
        let r = try await TaquitoBridge.shared.call("multisigScriptHash", [])
        #expect(r["hash"]?.stringValue == "exprub9UzpxmhedNQnsv1J1DazWGJnj1dLhtG1fxkUoWSdFLBGLqJ4")
    }

    /// The bytes we ask signers to sign are the ones `octez-client prepare multisig transaction on
    /// KT1UqzPQCEb6bVYKeab9EXjVcQsUGT8iLC2m … --bytes-only` printed on Shadownet (chain
    /// NetXsqzbfFenSTS) at counter 0, for a transfer, a new delegate and a withdrawn delegate.
    @Test(arguments: [
        (#"{"kind":"transfer","amountMutez":"1000000","destination":"tz1VSUr8wwNhLAzempoch5d6hLRiTh8Cjcjb"}"#,
         "05070707070a00000004d052218e0a0000001601de437531484fc04f7bebc2f6a90580b8e0b5de8e0007070000050502000000340320053d036d0743035d0a00000015006b82198cb179e8306c1bedd08f12dc863f328886031e0743036a0080897a034f034d031b"),
        (#"{"kind":"delegate","delegate":"tz1VSUr8wwNhLAzempoch5d6hLRiTh8Cjcjb"}"#,
         "05070707070a00000004d052218e0a0000001601de437531484fc04f7bebc2f6a90580b8e0b5de8e00070700000505020000002a0320053d036d0743035d0a00000015006b82198cb179e8306c1bedd08f12dc863f3288860346034e031b"),
        (#"{"kind":"delegate","delegate":null}"#,
         "05070707070a00000004d052218e0a0000001601de437531484fc04f7bebc2f6a90580b8e0b5de8e00070700000505020000000e0320053d036d053e035d034e031b"),
    ])
    func signedBytesMatchOctezClient(action: String, expected: String) async throws {
        let r = try await TaquitoBridge.shared.call("multisigPayloadLocal", ["NetXsqzbfFenSTS", "KT1UqzPQCEb6bVYKeab9EXjVcQsUGT8iLC2m", 0, action])
        #expect(r["bytes"]?.stringValue == expected)
    }
}

struct MultisigStorageTests {
    private func tempDir() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("signet-multisig-\(UUID().uuidString)", isDirectory: true)
    }

    @Test func contractsFileIsOctezClientFormat() throws {
        let dir = tempDir()
        let store = TezosClientStore(directory: dir)
        #expect(try store.loadContracts().isEmpty)
        try store.addContract(MultisigContract(alias: "treasury", address: Address("KT1BEqzn5Wx8uJrZNvuS9DVHmLvG9td3fDLi")))
        #expect(throws: TezosClientStore.StoreError.self) { try store.addContract(MultisigContract(alias: "treasury", address: Address("KT1XXX"))) }
        let raw = try JSONSerialization.jsonObject(with: Data(contentsOf: dir.appendingPathComponent("contracts"))) as? [[String: Any]]
        #expect(raw?.first?["name"] as? String == "treasury")
        #expect(raw?.first?["value"] as? String == "KT1BEqzn5Wx8uJrZNvuS9DVHmLvG9td3fDLi")
        #expect(try store.loadContracts() == [MultisigContract(alias: "treasury", address: Address("KT1BEqzn5Wx8uJrZNvuS9DVHmLvG9td3fDLi"))])
    }

    /// Named contracts are the KT1 half of the address book: `load()` lists them as watch-only, a
    /// KT1 added as an address lands in `contracts` (octez-client refuses a `public_key_hashs`
    /// holding one), aliases are unique across both, and rename/forget work on them.
    @Test func contractsAreAddressBookEntries() throws {
        let dir = tempDir()
        let store = TezosClientStore(directory: dir)
        let alice = Wallet(alias: "alice", address: Address("tz1VSUr8wwNhLAzempoch5d6hLRiTh8Cjcjb"), publicKey: "edpkALICE", keyKind: .unencrypted)
        try store.add(alice, secretKey: "edskALICE")
        try store.addWatchOnly(Wallet(alias: "treasury", address: Address("KT1BEqzn5Wx8uJrZNvuS9DVHmLvG9td3fDLi")))
        try store.addContract(MultisigContract(alias: "vault", address: Address("KT1UqzPQCEb6bVYKeab9EXjVcQsUGT8iLC2m")))
        let hashes = try JSONSerialization.jsonObject(with: Data(contentsOf: dir.appendingPathComponent("public_key_hashs"))) as? [[String: Any]]
        #expect(hashes?.count == 1)
        #expect(try store.loadContracts().map(\.alias) == ["treasury", "vault"])
        let loaded = try store.load()
        #expect(loaded.map(\.alias) == ["alice", "treasury", "vault"])
        #expect(loaded[1].keyKind == KeyKind.none && loaded[1].address.isContract && loaded[1].publicKey == nil)

        #expect(throws: TezosClientStore.StoreError.self) { try store.addContract(MultisigContract(alias: "alice", address: Address("KT1XXX"))) }
        #expect(throws: TezosClientStore.StoreError.self) { try store.addWatchOnly(Wallet(alias: "vault", address: Address("tz3WXYtyDUNL91qfiCJtVUX746QpNv5i5ve5"))) }
        #expect(throws: TezosClientStore.StoreError.self) { try store.add(Wallet(alias: "treasury", address: alice.address, publicKey: "edpkX", keyKind: .unencrypted), secretKey: "edskX") }
        #expect(throws: TezosClientStore.StoreError.self) { try store.rename(alias: "alice", to: "vault") }

        try store.rename(alias: "treasury", to: "funds")
        #expect(try store.loadContracts().map(\.alias) == ["funds", "vault"])
        let funds = try #require(try store.load().first { $0.alias == "funds" })
        try store.remove(funds)
        #expect(try store.load().map(\.alias) == ["alice", "vault"])
        #expect(throws: TezosClientStore.StoreError.self) { try store.remove(funds) }
    }

    @Test func proposalsRoundTripThroughTheFile() throws {
        let dir = tempDir()
        let store = FileMultisigProposalStore(directory: dir)
        #expect(store.load().isEmpty)
        var p = MultisigProposal(contractAlias: "treasury", contractAddress: "KT1BEqzn5Wx8uJrZNvuS9DVHmLvG9td3fDLi", networkName: "Shadownet", chainID: "NetXnHfVqm9iesp",
                                 counter: 4, threshold: 2, keys: ["edpkA", "edpkB", "edpkC"], action: .transfer(amountMutez: "5000000", destination: "tz1VSUr8wwNhLAzempoch5d6hLRiTh8Cjcjb"), bytes: "0507")
        p.signatures = [MultisigSignature(publicKey: "edpkA", signature: "edsigA")]
        p.created = Date(timeIntervalSince1970: 1_760_000_000)  // whole seconds survive ISO 8601
        try store.save([p])
        let back = store.load()
        #expect(back == [p])
        #expect(back[0].amount == 5)
        #expect(back[0].missing == 1 && !back[0].isReady)
    }
}

@MainActor
struct MultisigFlowTests {
    static let alice = Wallet(alias: "alice", address: Address("tz1VSUr8wwNhLAzempoch5d6hLRiTh8Cjcjb"), publicKey: "edpkALICE", keyKind: .unencrypted)
    static let bob = Wallet(alias: "bob", address: Address("tz2BFTyPeYRzxd5aiBchbXN3WCZhx7BqbMBq"), publicKey: "sppkBOB", keyKind: .encrypted)
    static let watch = Wallet(alias: "watch", address: Address("tz3WXYtyDUNL91qfiCJtVUX746QpNv5i5ve5"))

    private func makeModel(_ service: MockMultisigService, store: InMemoryWalletStore = InMemoryWalletStore()) -> WalletViewModel {
        let model = WalletViewModel(wallets: [Self.alice, Self.bob, Self.watch], chain: MockChainService(), multisig: service, walletStore: store)
        try? store.add(Self.alice, secretKey: "edskALICE")
        try? store.add(Self.bob, secretKey: "edeskBOB")
        try? store.addWatchOnly(Self.watch)
        return model
    }

    @Test func addRefusesForeignOrNonGenericContracts() async throws {
        let service = MockMultisigService(keys: ["edpkSOMEONE", "edpkELSE"], threshold: 1)
        let model = makeModel(service)
        await #expect(throws: WalletViewModel.MultisigError.self) { try await model.addMultisig(alias: "x", address: "KT1BEqzn5Wx8uJrZNvuS9DVHmLvG9td3fDLi") }
        service.keys = ["edpkALICE", "edpkELSE"]
        service.isGeneric = false
        await #expect(throws: WalletViewModel.MultisigError.self) { try await model.addMultisig(alias: "x", address: "KT1BEqzn5Wx8uJrZNvuS9DVHmLvG9td3fDLi") }
        await #expect(throws: WalletViewModel.MultisigError.self) { try await model.addMultisig(alias: "x", address: "tz1VSUr8wwNhLAzempoch5d6hLRiTh8Cjcjb") }
        service.isGeneric = true
        let added = try await model.addMultisig(alias: " treasury ", address: "KT1BEqzn5Wx8uJrZNvuS9DVHmLvG9td3fDLi")
        #expect(added.alias == "treasury")
        #expect(model.multisigContracts == [added])
        // It joins the address book under its name and is shown.
        #expect(model.wallets.map(\.alias) == ["alice", "bob", "watch", "treasury"])
        #expect(model.selectedWallet?.alias == "treasury" && model.selectedWallet?.keyKind == KeyKind.none)
        await #expect(throws: WalletViewModel.WalletError.self) { try await model.addMultisig(alias: "alice", address: "KT1UqzPQCEb6bVYKeab9EXjVcQsUGT8iLC2m") }
        await #expect(throws: WalletViewModel.WalletError.self) { try await model.addMultisig(alias: "again", address: "KT1BEqzn5Wx8uJrZNvuS9DVHmLvG9td3fDLi") }
        await #expect(throws: WalletViewModel.WalletError.self) { try await model.addMultisig(alias: "treasury", address: "KT1BEqzn5Wx8uJrZNvuS9DVHmLvG9td3fDLi") }
    }

    @Test func createChecksThresholdAndKeysThenRecordsTheAlias() async throws {
        let service = MockMultisigService()
        let model = makeModel(service)
        model.select(Self.alice)
        await #expect(throws: WalletViewModel.MultisigError.self) { try await model.createMultisig(alias: "t", threshold: 3, keys: ["edpkALICE", "sppkBOB"], passphrase: nil) }
        await #expect(throws: WalletViewModel.MultisigError.self) { try await model.createMultisig(alias: "t", threshold: 1, keys: ["edpkALICE", "notakey"], passphrase: nil) }
        let contract = try await model.createMultisig(alias: "treasury", threshold: 2, keys: ["edpkALICE", "sppkBOB", "edpkOTHERpublickeyxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"], passphrase: nil)
        #expect(contract.address == MockMultisigService.sampleAddress)
        #expect(service.threshold == 2 && service.keys.count == 3)
        #expect(model.multisigContracts.map(\.alias) == ["treasury"])
    }

    @Test func proposeSignGatherAndSubmit() async throws {
        let service = MockMultisigService(keys: ["edpkALICE", "sppkBOB", "edpkOTHER"], threshold: 2)
        let model = makeModel(service)
        let treasury = try await model.addMultisig(alias: "treasury", address: MockMultisigService.sampleAddress.value)
        let info = try await model.multisigInfo(treasury)
        #expect(info.signers(among: model.wallets).map(\.alias) == ["alice", "bob"])

        let proposal = try await model.proposeMultisigTransfer(from: treasury, amount: 5, to: Self.watch.address)
        #expect(proposal.counter == 3 && proposal.threshold == 2 && proposal.action == .transfer(amountMutez: "5000000", destination: Self.watch.address.value))
        #expect(proposal.summary == "5 tz to tz3WXYtyDUN...Nv5i5ve5")
        #expect(model.currentMultisigProposals.count == 1)
        // Proposing the same transfer again is the same proposal.
        #expect(try await model.proposeMultisigTransfer(from: treasury, amount: 5, to: Self.watch.address).id == proposal.id)

        // Watch-only cannot sign; a non-member cannot sign; alice signs once.
        await #expect(throws: WalletViewModel.MultisigError.self) { try await model.signMultisigProposal(proposal, with: Self.watch, passphrase: nil) }
        let sig = try await model.signMultisigProposal(proposal, with: Self.alice, passphrase: nil)
        #expect(sig.signature.hasPrefix("edsigMock"))
        var current = try #require(model.multisigProposals.first { $0.id == proposal.id })
        #expect(current.signatures.count == 1 && !current.isReady)
        await #expect(throws: WalletViewModel.MultisigError.self) { try await model.signMultisigProposal(current, with: Self.alice, passphrase: nil) }

        // Bob's signature arrives by paste; blank and duplicate pastes are ignored.
        try model.addMultisigSignature("  spsigBOBBOB  ", to: current)
        try model.addMultisigSignature("spsigBOBBOB", to: current)
        try model.addMultisigSignature("   ", to: current)
        current = try #require(model.multisigProposals.first { $0.id == proposal.id })
        #expect(current.signatures.map(\.signature) == [sig.signature, "spsigBOBBOB"])
        #expect(current.isReady)

        let hash = try await model.submitMultisig(current, from: Self.alice, passphrase: nil)
        #expect(hash == "ooMockSubmit")
        #expect(service.submitted.count == 1 && service.submitted[0].signatures.count == 2)
        #expect(model.multisigProposals.isEmpty)
    }

    @Test func signersComeFromKeysOurAccountsTheAddressBookOrTheChain() async throws {
        let service = MockMultisigService()
        service.revealed = ["tz3WXYtyDUNL91qfiCJtVUX746QpNv5i5ve5": "p2pkWATCHrevealed"]
        let model = makeModel(service)
        #expect(try await model.multisigSignerKey(from: " edpkPASTEDpublickey ") == "edpkPASTEDpublickey")
        #expect(try await model.multisigSignerKey(from: Self.alice.address.value) == "edpkALICE")          // ours: no lookup
        #expect(try await model.multisigSignerKey(from: Self.watch.address.value) == "p2pkWATCHrevealed")  // address book: revealed key
        service.revealed = [:]
        await #expect(throws: WalletViewModel.MultisigError.self) { try await model.multisigSignerKey(from: Self.watch.address.value) }
        await #expect(throws: WalletViewModel.MultisigError.self) { try await model.multisigSignerKey(from: "KT1BEqzn5Wx8uJrZNvuS9DVHmLvG9td3fDLi") }
        await #expect(throws: WalletViewModel.MultisigError.self) { try await model.multisigSignerKey(from: "hello") }
    }

    /// A multisig delegates like it spends: a proposal the signers sign, then one submission.
    @Test func delegateChangesAreProposalsToo() async throws {
        let service = MockMultisigService(keys: ["edpkALICE", "sppkBOB"], threshold: 2)
        let model = makeModel(service)
        let treasury = try await model.addMultisig(alias: "treasury", address: MockMultisigService.sampleAddress.value)
        let baker = "tz1dCaMnnMJk76UodjewCK67ABiXWjcKj73N"
        let setDelegate = try await model.proposeMultisig(.setDelegate(delegate: baker), from: treasury)
        let withdraw = try await model.proposeMultisig(.setDelegate(delegate: nil), from: treasury)
        let transfer = try await model.proposeMultisigTransfer(from: treasury, amount: 1, to: Self.watch.address)
        #expect(Set([setDelegate.bytes, withdraw.bytes, transfer.bytes]).count == 3)
        #expect(setDelegate.summary == "Delegate to tz1dCaMnnMJ...WjcKj73N" && withdraw.summary == "Remove delegate")
        #expect(setDelegate.amount == 0 && withdraw.amount == 0)
        #expect(model.currentMultisigProposals.count == 3)

        try await model.signMultisigProposal(setDelegate, with: Self.alice, passphrase: nil)
        try await model.signMultisigProposal(setDelegate, with: Self.bob, passphrase: "pw")
        let ready = try #require(model.multisigProposals.first { $0.id == setDelegate.id })
        #expect(ready.isReady)
        _ = try await model.submitMultisig(ready, from: Self.alice, passphrase: nil)
        #expect(service.submitted.last?.proposal.action == .setDelegate(delegate: baker))
        #expect(model.currentMultisigProposals.count == 2)
    }

    @Test func proposalsAreKeptPerNetwork() async throws {
        let service = MockMultisigService(keys: ["edpkALICE"], threshold: 1)
        let model = makeModel(service)
        let treasury = try await model.addMultisig(alias: "t", address: MockMultisigService.sampleAddress.value)
        _ = try await model.proposeMultisigTransfer(from: treasury, amount: 1, to: Self.watch.address)
        #expect(model.currentMultisigProposals.count == 1)
        model.switchNetwork(to: .shadownet)
        #expect(model.currentMultisigProposals.isEmpty)
    }
}

/// Live, on Shadownet: a 2-of-3 multisig deployed by Signet on 2026-10-10 reads back as a generic
/// multisig with its three keys (one per curve).
struct ShadownetMultisigReadTests {
    @Test(.tags(.network), .timeLimit(.minutes(1)))
    func readsADeployedMultisig() async throws {
        let info = try await BridgeMultisigService().info(rpcURL: Network.shadownet.rpcURL, address: Address("KT1UqzPQCEb6bVYKeab9EXjVcQsUGT8iLC2m"))
        #expect(info.isGenericMultisig)
        #expect(info.threshold == 2)
        #expect(info.keys == ["edpktnKyTBhma1YNJdJz63gPJSf41FnreC1XmFDwUtUiDHBQpUPscy", "sppk7bh9rrWgzanNhBqCwyKeEHDKXBdGFcJw1F9Eixt1prn8oB6ot5Z", "p2pk68NJBPLa6KmK3Yk4NoKjMuT9j8F6oknXRmKqwNCErwqyiS8YjiD"])
        #expect(info.counter >= 0)
        // Printed so the bytes can be compared with `octez-client prepare multisig transaction on
        // KT1UqzPQCEb6bVYKeab9EXjVcQsUGT8iLC2m transferring 1 to tz1VSUr8wwNhLAzempoch5d6hLRiTh8Cjcjb`.
        let (_, _, bytes) = try await BridgeMultisigService().prepare(rpcURL: Network.shadownet.rpcURL, contract: info.address, action: .transfer(amountMutez: "1000000", destination: "tz1VSUr8wwNhLAzempoch5d6hLRiTh8Cjcjb"))
        // A contract's balance reads like an account's (the node refuses full_balance for KT1s).
        let balance = try await TaquitoChainService(network: .shadownet).tezBalance(for: info.address)
        #expect(balance.total == info.balance && balance.staked == 0)
        print("bytes to sign (counter \(info.counter)): 0x\(bytes)")
    }
}

/// Live, on Shadownet: deploy a 2-of-3 multisig from a faucet-funded key, fund it, propose a
/// transfer, sign with two keys, submit, and see the tez arrive. Also checks our local packing of
/// the signed bytes against the node's `pack_data`, since that is what octez-client signs.
struct ShadownetMultisigTests {
    @Test(.tags(.network), .timeLimit(.minutes(8)))
    func twoOfThreeTransferEndToEnd() async throws {
        let chain = TaquitoChainService(network: .shadownet)
        let service = BridgeMultisigService()
        let rpc = Network.shadownet.rpcURL
        let generator = KeyGenerator()
        let payer = try await generator.generate(scheme: .tz1)
        let second = try await generator.generate(scheme: .tz2)
        let third = try await generator.generate(scheme: .tz3)
        let recipient = try await generator.generate(scheme: .tz1)
        let payerWallet = Wallet(alias: "payer", address: Address(payer.address), scheme: .tz1, publicKey: payer.publicKey, keyKind: .unencrypted)
        let payerKey = SigningKey.secret(payer.secretKey, passphrase: nil, address: payerWallet.address)

        let faucet = try #require(FaucetService(network: .shadownet))
        _ = try await faucet.requestTez(to: payerWallet.address, amount: 20)
        var funded = false
        for _ in 0..<40 { try await Task.sleep(for: .seconds(4)); if let b = try? await chain.tezBalance(for: payerWallet.address), b.spendable >= 20 { funded = true; break } }
        #expect(funded)

        let keys = [payer.publicKey, second.publicKey, third.publicKey]
        let estimate = try await service.estimateOriginate(rpcURL: rpc, from: payerWallet, threshold: 2, keys: keys)
        #expect(estimate.fee > 0 && estimate.burn > 0)
        let (_, contract) = try await service.originate(rpcURL: rpc, signer: payerKey, threshold: 2, keys: keys)
        #expect(contract.isContract)
        print("multisig deployed at \(contract.value)")

        let info = try await service.info(rpcURL: rpc, address: contract)
        #expect(info.isGenericMultisig && info.threshold == 2 && info.keys == keys && info.counter == 0)
        // Originating revealed the payer's key, so its address alone now identifies a signer; the
        // recipient has never sent anything and has no revealed key.
        #expect(try await service.revealedPublicKey(rpcURL: rpc, address: payerWallet.address) == payer.publicKey)
        #expect(try await service.revealedPublicKey(rpcURL: rpc, address: Address(recipient.address)) == nil)

        // Fund the multisig (its default entrypoint takes tez).
        let fundHash = try await chain.sendTransfer(from: payerWallet, signer: payerKey, to: contract, amount: 3)
        _ = try await chain.waitForConfirmation(of: fundHash)

        // Propose 1 tez to the recipient; our packed bytes must equal the node's packing.
        let transfer = MultisigAction.transfer(amountMutez: "1000000", destination: recipient.address)
        let (state, chainID, bytes) = try await service.prepare(rpcURL: rpc, contract: contract, action: transfer)
        #expect(state.counter == 0 && bytes.hasPrefix("05"))
        let viaNode = try await TaquitoBridge.shared.call("multisigPayloadViaNode", [rpc.absoluteString, chainID, contract.value, 0, try BridgeMultisigService.json(transfer)])
        #expect(viaNode["bytes"]?.stringValue == bytes)
        #expect(viaNode["local"]?.stringValue == bytes)

        // Sign with two of the three keys (different curves), then submit from the payer.
        let sig1 = try await chain.signPayload(signer: payerKey, payloadHex: bytes)
        let sig3 = try await chain.signPayload(signer: .secret(third.secretKey, passphrase: nil, address: Address(third.address)), payloadHex: bytes)
        let proposal = MultisigProposal(contractAlias: "test", contractAddress: contract.value, networkName: "Shadownet", chainID: chainID, counter: 0, threshold: 2, keys: keys,
                                        action: transfer, bytes: bytes)
        // One signature is not enough, and a signature over other bytes does not count.
        await #expect(throws: (any Error).self) { try await service.estimateSubmit(rpcURL: rpc, from: payerWallet, proposal: proposal, signatures: [sig1.signature]) }
        let bogus = try await chain.signPayload(signer: payerKey, payloadHex: "0501000000026869")
        await #expect(throws: (any Error).self) { try await service.estimateSubmit(rpcURL: rpc, from: payerWallet, proposal: proposal, signatures: [sig1.signature, bogus.signature]) }

        let fee = try await service.estimateSubmit(rpcURL: rpc, from: payerWallet, proposal: proposal, signatures: [sig3.signature, sig1.signature])
        #expect(fee.fee > 0)
        let hash = try await service.submit(rpcURL: rpc, signer: payerKey, proposal: proposal, signatures: [sig3.signature, sig1.signature])
        print("multisig transfer \(hash)")

        try await Task.sleep(for: .seconds(4))
        let after = try await service.info(rpcURL: rpc, address: contract)
        #expect(after.counter == 1)
        #expect(after.balance == 2)
        let received = try await chain.tezBalance(for: Address(recipient.address))
        #expect(received.spendable == 1)
        // The same signatures cannot be replayed: the counter moved on.
        await #expect(throws: (any Error).self) { try await service.estimateSubmit(rpcURL: rpc, from: payerWallet, proposal: proposal, signatures: [sig3.signature, sig1.signature]) }
        // The dashboard's balance path works for the contract too.
        let contractBalance = try await chain.tezBalance(for: contract)
        #expect(contractBalance.total == 2 && contractBalance.spendable == 2)

        // Now delegate the multisig to an active baker, signed by the other two keys.
        let (data, _) = try await URLSession.shared.data(from: rpc.appendingPathComponent("chains/main/blocks/head/context/delegates").appending(queryItems: [URLQueryItem(name: "active", value: "true")]))
        let baker = try #require((try JSONSerialization.jsonObject(with: data) as? [String])?.first)
        let delegateAction = MultisigAction.setDelegate(delegate: baker)
        let (state2, _, bytes2) = try await service.prepare(rpcURL: rpc, contract: contract, action: delegateAction)
        #expect(state2.counter == 1)
        let viaNode2 = try await TaquitoBridge.shared.call("multisigPayloadViaNode", [rpc.absoluteString, chainID, contract.value, 1, try BridgeMultisigService.json(delegateAction)])
        #expect(viaNode2["bytes"]?.stringValue == bytes2)
        let dsig2 = try await chain.signPayload(signer: .secret(second.secretKey, passphrase: nil, address: Address(second.address)), payloadHex: bytes2)
        let dsig3 = try await chain.signPayload(signer: .secret(third.secretKey, passphrase: nil, address: Address(third.address)), payloadHex: bytes2)
        let delegation = MultisigProposal(contractAlias: "test", contractAddress: contract.value, networkName: "Shadownet", chainID: chainID, counter: 1, threshold: 2, keys: keys,
                                          action: delegateAction, bytes: bytes2)
        let delegateHash = try await service.submit(rpcURL: rpc, signer: payerKey, proposal: delegation, signatures: [dsig2.signature, dsig3.signature])
        print("multisig delegation \(delegateHash)")
        try await Task.sleep(for: .seconds(4))
        let delegated = try await chain.delegateInfo(for: contract)
        #expect(delegated.delegate?.value == baker)
        #expect(try await service.info(rpcURL: rpc, address: contract).counter == 2)
    }
}
