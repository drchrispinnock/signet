import Foundation
import Testing
@testable import Signet

// MARK: - Vectors

/// The tzel cross-implementation vectors, read from a checkout (`TZEL_VECTORS` or the sibling
/// `../tzel`), never copied here: the tzel licence forbids it. `nil` when there is none.
enum TzELVectors {
    static func load() -> [String: Any]? {
        let env = ProcessInfo.processInfo.environment["TZEL_VECTORS"]
        let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let path = env ?? repo.deletingLastPathComponent().appendingPathComponent("tzel/specs/ocaml_vectors/protocol_v1.json").path
        guard let data = FileManager.default.contents(atPath: path), let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return json
    }
}

// MARK: - BLAKE2s

struct Blake2sTests {
    private func hex(_ bytes: [UInt8], _ personal: String? = nil) -> String {
        Hex.encode(Blake2s.hash(bytes, personalization: personal.flatMap(Blake2s.Personalization.init) ?? .none))
    }

    @Test func matchesTheRFCVectorAndNoble() {
        // RFC 7693 appendix: BLAKE2s-256("abc"); the rest were computed with @noble/hashes, the bridge's BLAKE2s.
        #expect(hex(Array("abc".utf8)) == "508c5e8c327c14e2e1a72ba34eeb452f37458b209ed63a294d999b4c86675982")
        #expect(hex([]) == "69217a3079908094e11121d042354a7c1f55b6482ca1a51e1b250dfd1ed0eef9")
        #expect(hex([UInt8](repeating: 0, count: 64), "mrklSP__") == "c25fa43362917ce953ec2b680c0b1475c534e19d84ac8dc660907bd3633e3586")
        #expect(hex([UInt8](repeating: 0xff, count: 96), "sighSP__") == "95d4d347cd6df1d063a95d17e8364acb1754b2ec3b224a11f392cfc5f917acc3")
        #expect(hex((0..<128).map { UInt8($0) }) == "1fa877de67259d19863a2a34bcc6962a2b25fcbf5cbecd7ede8f1fa36688a796")
        #expect(hex((0..<200).map { UInt8(($0 * 7) & 255) }) == "4954f84ca29ed06714c1732e2a8a199a9e784009e9495d04dc7736bdca41233d")
        #expect(Blake2s.Personalization("short") == nil && Blake2s.Personalization("mrklSP__") != nil)
    }

    @Test func matchesEveryBlake2sVector() throws {
        guard let vectors = TzELVectors.load(), let cases = vectors["blake2s"] as? [[String: Any]] else { return }
        for c in cases {
            let input = try #require(Hex.decode(c["input"] as? String ?? ""))
            let personal = c["personal"] as? String ?? ""
            #expect(hex(input, personal.isEmpty ? nil : personal) == c["output"] as? String)
        }
    }
}

// MARK: - Auth tree

struct XMSSAuthTreeTests {
    /// The native leaves are the bridge's leaves, so a tree built here signs with keys the
    /// bridge's `wotsSign` holds.
    @Test func leavesAndSeedsAgreeWithTheBridge() async throws {
        let bridge = TaquitoBridge.shared
        let masterSk = Hex.encode(XMSSAuthTree.feltOfInt(777))
        let account = try await bridge.call("tzelAccount", [masterSk])
        let keys = try await bridge.call("tzelAddressKeys", [try WalletViewModel.json(account), 0])
        let askJHex = try #require(keys["askJ"]?.stringValue), pubSeedHex = try #require(keys["pubSeed"]?.stringValue)
        let askJ = try #require(Hex.decode(askJHex)), pubSeed = try #require(Hex.decode(pubSeedHex))
        #expect(Hex.encode(XMSSAuthTree.pubSeed(askJ: askJ)) == pubSeedHex)
        let askBase = try #require(account["askBase"]?.stringValue.flatMap(Hex.decode))
        #expect(Hex.encode(XMSSAuthTree.deriveAsk(askBase: askBase, j: 0)) == askJHex)
        for index in [0, 1, 2, 4097, 65535] {
            let expected = try await bridge.call("tzelAuthLeaf", [askJHex, pubSeedHex, index]).stringValue
            #expect(Hex.encode(XMSSAuthTree.leaf(askJ: askJ, pubSeed: pubSeed, keyIdx: index)) == expected, "leaf \(index)")
        }
    }

    /// The whole tree against the shared vectors: the first address's root and a WOTS+ leaf.
    @Test func fullTreeMatchesTheVectors() throws {
        guard let vectors = TzELVectors.load() else { return }
        let hierarchy = try #require(vectors["key_hierarchy"] as? [String: Any])
        let addresses = try #require(vectors["addresses"] as? [[String: Any]])
        let first = try #require(addresses.first { ($0["j"] as? Int) == 0 })
        let askBase = try #require(Hex.decode(hierarchy["ask_base"] as? String ?? ""))
        let askJ = XMSSAuthTree.deriveAsk(askBase: askBase, j: 0)
        let pubSeed = XMSSAuthTree.pubSeed(askJ: askJ)
        #expect(Hex.encode(pubSeed) == first["auth_pub_seed"] as? String)
        let started = Date()
        let leaves = XMSSAuthTree.buildLeaves(askJ: askJ, pubSeed: pubSeed)
        let levels = XMSSAuthTree.levels(pubSeed: pubSeed, leaves: leaves)
        print("native auth tree built in \(String(format: "%.1f", Date().timeIntervalSince(started))) s")
        #expect(Hex.encode(XMSSAuthTree.root(levels: levels)) == first["auth_root"] as? String)
        #expect(XMSSAuthTree.path(levels: levels, index: 3).count == 16)
        #expect(XMSSAuthTree.path(levels: levels, index: 3)[0] == Array(leaves[(2 * 32)..<(3 * 32)]), "the first sibling of leaf 3 is leaf 2")
        for w in try #require(vectors["wots"] as? [[String: Any]]) {
            let ask = try #require(Hex.decode(w["ask_j"] as? String ?? "")), seed = try #require(Hex.decode(w["auth_pub_seed"] as? String ?? ""))
            let index = try #require(w["key_idx"] as? Int)
            #expect(Hex.encode(XMSSAuthTree.leaf(askJ: ask, pubSeed: seed, keyIdx: index)) == w["leaf"] as? String)
        }
    }

    /// A real proof is a few hundred KB of hex; the encoder must come back through the bridge as one string.
    @Test func aLargeProofEncodesThroughTheBridge() async throws {
        let zeroNote = String(repeating: "00", count: 1088) + "0000" + String(repeating: "00", count: 1088 + 12 + 1080 + 185)
        let message: [String: Any] = [
            "pubkeyHash": String(repeating: "ab", count: 32), "fee": "100000", "v": "1", "producerFee": "100000",
            "proofBytes": String(repeating: "cd", count: 300_000), "outputPreimage": Array(repeating: String(repeating: "ef", count: 32), count: 9),
            "clientCm": String(repeating: "11", count: 32), "clientEnc": zeroNote, "producerCm": String(repeating: "22", count: 32), "producerEnc": zeroNote,
        ]
        let result = try await TaquitoBridge.shared.call("tzelEncodeShieldMessage", [String(decoding: try JSONSerialization.data(withJSONObject: message), as: UTF8.self)])
        let payload = try #require(result.stringValue, "got \(String(describing: result).prefix(120))")
        let header = 3 + 32 + 24 + 4
        let proof = 4 + 300_000 + 4 + 9 * 32
        let notes = 32 + 3455 + 32 + 3455
        let expectedBytes = header + proof + notes
        #expect(payload.count == 2 * expectedBytes)
        #expect(payload.hasPrefix("110002" + String(repeating: "ab", count: 32)))
    }

    @Test func feltHelpersMatchTheSpec() {
        #expect(Hex.encode(XMSSAuthTree.feltTag("xmss-tr")) == "72742d73736d7800000000000000000000000000000000000000000000000000")
        #expect(Hex.encode(XMSSAuthTree.feltOfInt(0x0102)) == "0201000000000000000000000000000000000000000000000000000000000000")
        #expect(Hex.decode("zz") == nil && Hex.decode("abc") == nil && Hex.decode("ABcd") == [0xab, 0xcd] && Hex.encode([0xab, 0xcd]) == "abcd")
    }
}

// MARK: - Store

struct ShieldedWalletStoreTests {
    @Test func fileStoreRoundTripsPrivatelyAndIsBackedUp() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("signet-shielded-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = FileShieldedWalletStore(directory: directory, chain: "shadownet")
        #expect(try store.load() == nil && (try store.loadLeaves(addressIndex: 0)) == nil)
        var wallet = ShieldedWallet.make(chain: "shadownet")
        #expect(Hex.decode(wallet.masterSk)?.count == 32 && (Hex.decode(wallet.masterSk)?[31] ?? 0xff) & 0xf8 == 0, "a 251-bit master key")
        #expect(ShieldedWallet.make(chain: "shadownet").masterSk != wallet.masterSk)
        wallet.addresses.append(ShieldedAddress(index: 0, dJ: "aa", authRoot: "bb", pubSeed: "cc", nkTag: "dd", ekV: "ee", ekD: "ff", nextKeyIndex: 3))
        wallet.pools.append(DepositPool(pubkeyHash: "11", blind: "22", addressIndex: 0, authDomain: "33", depositedMutez: "1000000", operationHash: "ooX", shieldedCm: nil, created: Date(timeIntervalSince1970: 1_000_000)))
        wallet.notes.append(ShieldedNote(index: 7, cm: "44", rseed: "55", nullifier: "66", valueMutez: "1800000", addressIndex: 0))
        wallet.notes.append(ShieldedNote(index: 8, cm: "47", rseed: "58", nullifier: "69", valueMutez: "100", addressIndex: 0, spent: true))
        wallet.operatorToken = "secret"
        wallet.scanned = 9
        try store.save(wallet)
        #expect(try store.load() == wallet)
        #expect(wallet.balanceMutez == 1_800_000 && wallet.balance == Decimal(string: "1.8"))
        let attributes = try FileManager.default.attributesOfItem(atPath: directory.appendingPathComponent("tzel-shadownet.json").path)
        #expect((attributes[.posixPermissions] as? Int) == 0o600)
        let leaves = (0..<XMSSAuthTree.leavesBytes).map { UInt8($0 & 0xff) }
        try store.saveLeaves(leaves, addressIndex: 0)
        #expect(try store.loadLeaves(addressIndex: 0) == leaves)
        #expect(WalletBackup.files.contains("tzel-shadownet.json") && WalletBackup.valuableFiles.contains("tzel-shadownet.json"))
        #expect(!WalletBackup.files.contains("tzel-shadownet-auth0.bin"))
    }

    @Test func theFeeRuleAndStateKeysFollowTheKernel() {
        #expect(RollupState.requiredTxFee(privateTxsInLevel: 0) == 100_000 && RollupState.requiredTxFee(privateTxsInLevel: 1) == 100_000)
        #expect(RollupState.requiredTxFee(privateTxsInLevel: 2) == 200_000 && RollupState.requiredTxFee(privateTxsInLevel: 7) == 6_400_000 && RollupState.requiredTxFee(privateTxsInLevel: 70) == 6_400_000)
        #expect(RollupState.indexed(RollupState.notePrefix, 26) == "/tzel/v1/state/notes/000000000000001a")
        #expect(RollupState.depositBalance("ab") == "/tzel/v1/state/deposits/balance/ab")
        #expect(Network.shadownet.shielded?.ticketer.value == "KT1RCZzNe8G4VQ94YWqb6Xz4q9WGWVdMWSB4" && Network.quantumnet.shielded == nil && Network.mainnet.shielded == nil)
        #expect(!Network.shadownet.canShield && Network.shadownet.usingShielded(enabled: true).canShield && !Network.quantumnet.usingShielded(enabled: true).canShield)
        #expect((try? ShieldedConfig.shadownet.producerAddressJSON())?["ek_v"]?.count == 2368)
    }
}

// MARK: - The flow, against a rollup in memory

/// The rollup node, proving service and operator as one in-memory state.
final class MockShieldedRollup: ShieldedRollup, @unchecked Sendable {
    private let lock = NSLock()
    var address = "sr1Psv7PdY533c4njAW4qg2acbMhi8goqxcK"
    var authDomain = String(repeating: "07", count: 32)
    var ticketer = "KT1RCZzNe8G4VQ94YWqb6Xz4q9WGWVdMWSB4"
    var verifierInstalled = true
    var level = 100
    var privateTxsInLevel: UInt64 = 0
    var pools: [String: UInt64] = [:]
    var notes: [[UInt8]] = []
    var nullifiers: [String] = []
    var submitted: [(kind: String, payload: String, token: String)] = []
    var proofRequests: [[String]] = []
    var failProving: String?

    func head() async throws -> RollupHead { lock.withLock { RollupHead(hash: "BLmock\(level)", level: level) } }
    func smartRollupAddress() async throws -> String { lock.withLock { address } }

    private func value(_ key: String) -> [UInt8]? {
        func le(_ n: UInt64, _ count: Int) -> [UInt8] { (0..<count).map { UInt8(truncatingIfNeeded: n >> (8 * UInt64($0))) } }
        switch key {
        case RollupState.authDomain: return Hex.decode(authDomain)
        case RollupState.verifierConfig: return verifierInstalled ? [1, 2, 3] : nil
        case RollupState.bridgeTicketer: return Array(ticketer.utf8)
        case RollupState.treeSize: return le(UInt64(notes.count), 8)
        case RollupState.nullifierCount: return le(UInt64(nullifiers.count), 8)
        case RollupState.lastInputLevel, RollupState.privateTxFeeLevel: return privateTxsInLevel > 0 ? le(UInt64(level + 1), 4) : nil
        case RollupState.privateTxCountInLevel: return le(privateTxsInLevel, 8)
        default:
            if key.hasPrefix(RollupState.depositBalancePrefix) { return pools[String(key.dropFirst(RollupState.depositBalancePrefix.count))].map { le($0, 8) } }
            if key.hasPrefix(RollupState.nullifierIndexPrefix), let i = Int(String(key.dropFirst(RollupState.nullifierIndexPrefix.count)), radix: 16), i < nullifiers.count { return Hex.decode(nullifiers[i]) }
            if key.hasPrefix(RollupState.notePrefix) {
                let rest = String(key.dropFirst(RollupState.notePrefix.count))
                let parts = rest.split(separator: "/").map(String.init)
                guard let i = Int(parts[0], radix: 16), i < notes.count else { return nil }
                if parts.count == 1 { return nil }   // served chunked, as Shadownet does
                if parts[1] == "len" { return le(UInt64(notes[i].count), 8) }
                if parts[1] == "chunk", let c = Int(parts[2], radix: 16) {
                    let start = c * RollupState.noteChunkBytes
                    guard start < notes[i].count else { return nil }
                    return Array(notes[i][start..<min(start + RollupState.noteChunkBytes, notes[i].count)])
                }
            }
            return nil
        }
    }

    func durableLength(block: String, key: String) async throws -> Int? { lock.withLock { value(key)?.count } }
    func durableValue(block: String, key: String) async throws -> [UInt8]? { lock.withLock { value(key) } }
    func programHash(named program: String) async throws -> String { String(repeating: "ab", count: 32) }

    func startProof(programHash: String, arguments: [String]) async throws -> String {
        lock.withLock { proofRequests.append(arguments); return "job-\(proofRequests.count)" }
    }

    /// "Proves" by echoing the witness's nine public outputs behind the bootloader header, as the service does.
    func proofJob(id: String, lastStatus: String?) async throws -> ProofJob {
        let (request, failure): ([String]?, String?) = lock.withLock { (proofRequests.last, failProving) }
        if let failure { return .failed(failure) }
        guard let request, request.count == 171 else { return .failed("bad witness") }
        let outputs = request[1...9].map { arg -> String in
            var hex = String(arg.dropFirst(2))
            hex = String(repeating: "0", count: 64 - hex.count) + hex
            return Hex.encode(Hex.decode(hex)!.reversed())
        }
        let header = [1, 12].map { Hex.encode(XMSSAuthTree.feltOfInt($0)) } + [String(repeating: "ab", count: 32), Hex.encode(XMSSAuthTree.feltOfInt(9))]
        return lastStatus == nil ? .running : .done(ProofBundle(proofBytes: "aabbcc", outputPreimage: header + outputs))
    }

    func submit(kind: String, payloadHex: String, rollupAddress: String, token: String) async throws -> OperatorSubmission {
        guard token == "operator-secret" else { throw ShieldedError.operatorRefused("missing Authorization header") }
        lock.withLock { submitted.append((kind, payloadHex, token)) }
        return OperatorSubmission(id: "sub-\(submitted.count)", status: "commitment_included", transport: "dal", operationHash: nil, detail: nil)
    }

    func submission(id: String, token: String) async throws -> OperatorSubmission {
        OperatorSubmission(id: id, status: "submitted_to_l1", transport: "dal", operationHash: "ooShieldPointer", detail: nil)
    }

    /// Puts the client note of the last submitted shield into the tree, as the kernel would.
    func applyLastShield() -> String {
        lock.withLock {
            let bytes = Hex.decode(submitted.last!.payload)!
            let proofLength = Int(bytes[59]) << 24 | Int(bytes[60]) << 16 | Int(bytes[61]) << 8 | Int(bytes[62])
            let start = 63 + proofLength
            let note = Array(bytes[start..<(start + RollupState.publishedNoteBytes)])
            notes.append(note)
            let pool = Hex.encode(Array(bytes[3..<35]))
            pools[pool] = nil
            return Hex.encode(Array(note[0..<32]))
        }
    }
}

@MainActor
struct ShieldFlowTests {
    private func makeModel(store: InMemoryShieldedWalletStore, rollup: MockShieldedRollup, wallets: [Wallet] = WalletViewModel.sampleWallets) throws -> WalletViewModel {
        let keys = InMemoryWalletStore()
        try keys.add(wallets[0], secretKey: "edskSAMPLE")
        if wallets.count > 1 { try keys.add(wallets[1], secretKey: "edeskSAMPLE") }
        let model = WalletViewModel(wallets: wallets, chain: MockChainService(), walletStore: keys, shieldedStoreFactory: { _, _ in store }, shieldedRollupFactory: { _ in rollup })
        model.setShieldedEnabled(true, for: .shadownet)
        model.switchNetwork(to: .shadownet)
        model.shieldedCreditPolls = 2
        model.shieldedPollInterval = .milliseconds(10)
        return model
    }

    @Test func shieldsThroughDepositProofAndOperatorWithEveryStatePersistedFirst() async throws {
        let store = InMemoryShieldedWalletStore()
        let rollup = MockShieldedRollup()
        let model = try makeModel(store: store, rollup: rollup)
        #expect(model.canShield && model.network.canShield)
        // Nothing is on file yet and the token is not set: the Shield sheet can prepare, but not shield.
        let pool = try await model.prepareShield()
        var wallet = try #require(try store.load())
        #expect(wallet.addresses.count == 1 && wallet.addresses[0].nextKeyIndex == 0 && wallet.pools == [pool] && wallet.depositNonce == 1)
        #expect(try store.loadLeaves(addressIndex: 0)?.count == XMSSAuthTree.leavesBytes)
        #expect(pool.operationHash == nil && pool.authDomain == rollup.authDomain && pool.addressIndex == 0)
        // Preparing again reuses the unfunded pool rather than minting ids.
        #expect(try await model.prepareShield() == pool)
        let estimate = try await model.estimateShield(amount: 2, pool: pool)
        #expect(estimate.rollupFeeMutez == 100_000 && estimate.producerFeeMutez == 100_000 && estimate.shieldedAmount == Decimal(string: "1.8") && estimate.estimate.limits != nil)
        await #expect(throws: ShieldedError.operatorTokenMissing) { _ = try await model.shieldTez(approved: estimate, passphrase: nil) }
        #expect(try store.load()?.pools.first?.operationHash == nil, "nothing was sent without the token")

        try model.setShieldedOperatorToken("operator-secret", for: .shadownet)
        #expect(model.shieldedOperatorTokenIsSet(for: .shadownet) && !model.shieldedOperatorTokenIsSet(for: .mainnet))
        // The rollup credits the pool when the (mock) deposit lands.
        rollup.pools[pool.pubkeyHash] = 2_000_000
        let receipt = try await model.shieldTez(approved: estimate, passphrase: nil)
        #expect(receipt.depositHash == "ooMockShieldDeposit" && receipt.shieldedMutez == 1_800_000 && receipt.rollupFeeMutez == 100_000 && receipt.operationHash == "ooShieldPointer")
        wallet = try #require(try store.load())
        #expect(wallet.pools.first?.operationHash == "ooMockShieldDeposit" && wallet.pools.first?.depositedMutez == "2000000" && wallet.pools.first?.shieldedCm == receipt.cm)
        #expect(wallet.addresses[0].nextKeyIndex == 1)
        // The key index was on file before the witness existed, and the deposit before the block was waited for.
        let saves = store.history
        let indexSpent = try #require(saves.firstIndex { $0.addresses.first?.nextKeyIndex == 1 })
        let shieldRecorded = try #require(saves.firstIndex { $0.pools.first?.shieldedCm != nil })
        let depositRecorded = try #require(saves.firstIndex { $0.pools.first?.operationHash != nil })
        #expect(depositRecorded < indexSpent && indexSpent < shieldRecorded)
        // What went to the operator: a version 17 shield message for this pool, built from the proof.
        let sent = try #require(rollup.submitted.last)
        #expect(sent.kind == "shield" && sent.payload.hasPrefix("110002" + pool.pubkeyHash) && !sent.payload.contains("operator-secret"))
        #expect(rollup.proofRequests.last?.count == 171 && rollup.proofRequests.last?[0] == "0xaa")

        // The kernel applies it: the note is ours, the pool is gone, the row shows 1.8 tz.
        let cm = rollup.applyLastShield()
        #expect(cm == receipt.cm)
        await model.refresh()
        let shielded = try #require(model.shieldedWallet)
        #expect(shielded.notes.count == 1 && shielded.notes[0].cm == cm && shielded.notes[0].valueMutez == "1800000" && shielded.notes[0].index == 0 && shielded.scanned == 1)
        #expect(shielded.pools.isEmpty && model.shieldedPools.isEmpty)
        let row = try #require(model.assets.first { $0.kind == .shielded })
        #expect(row.amount == Decimal(string: "1.8") && row.unavailable == nil && row.details.isEmpty)
        // Spent on the rollup: the nullifier appears and the balance drops.
        rollup.nullifiers = [shielded.notes[0].nullifier]
        await model.refresh()
        #expect(model.shieldedWallet?.notes[0].spent == true && model.shieldedWallet?.balanceMutez == 0 && model.shieldedWallet?.nullifiersSeen == 1)
        #expect(model.assets.first { $0.kind == .shielded }?.amount == 0)
    }

    @Test func refusesAStaleContextARollupForAnotherDeploymentAndAnUncreditedPool() async throws {
        let store = InMemoryShieldedWalletStore()
        let rollup = MockShieldedRollup()
        let model = try makeModel(store: store, rollup: rollup)
        try model.setShieldedOperatorToken("operator-secret", for: .shadownet)
        rollup.address = "sr1Ghq66tYK9y3r8CC1Tf8i8m5nxh8nTvZEf"
        await #expect(throws: ShieldedError.rollupMismatch(served: "sr1Ghq66tYK9y3r8CC1Tf8i8m5nxh8nTvZEf", expected: "sr1Psv7PdY533c4njAW4qg2acbMhi8goqxcK")) { _ = try await model.prepareShield() }
        rollup.address = "sr1Psv7PdY533c4njAW4qg2acbMhi8goqxcK"
        rollup.ticketer = "KT1Mkqf6TnMVmhAAuBJCizkzAu4Nhg6DTPmM"
        await #expect(throws: ShieldedError.ticketerMismatch(configured: "KT1Mkqf6TnMVmhAAuBJCizkzAu4Nhg6DTPmM", expected: "KT1RCZzNe8G4VQ94YWqb6Xz4q9WGWVdMWSB4")) { _ = try await model.prepareShield() }
        rollup.ticketer = "KT1RCZzNe8G4VQ94YWqb6Xz4q9WGWVdMWSB4"
        #expect(try store.load()?.pools.isEmpty == true, "no pool before the rollup passed its checks")
        let pool = try await model.prepareShield()
        let estimate = try await model.estimateShield(amount: 1, pool: pool)
        // Another account was selected after the estimate: nothing is sent.
        model.select(WalletViewModel.sampleWallets[1])
        await #expect(throws: WalletViewModel.WalletError.contextChanged) { _ = try await model.shieldTez(approved: estimate, passphrase: nil) }
        model.select(WalletViewModel.sampleWallets[0])
        let again = try await model.estimateShield(amount: 1, pool: pool)   // the context moved, so a fresh estimate
        // A pool the rollup never credited: the deposit is on file, the shield gives up and the pool stays to retry.
        rollup.pools = [:]
        await #expect(throws: ShieldedError.poolNotCredited(pool.pubkeyHash)) { _ = try await model.shieldTez(approved: again, passphrase: nil) }
        let wallet = try #require(try store.load())
        #expect(wallet.pools.first?.operationHash == "ooMockShieldDeposit" && wallet.pools.first?.shieldedCm == nil && wallet.addresses[0].nextKeyIndex == 0)
        await model.refresh()
        #expect(model.shieldedPools.first?.balanceMutez == nil && model.shieldedPools.count == 1)
        // Credited later and too small for the fees, then enough: `shieldPool` picks it up.
        rollup.pools[pool.pubkeyHash] = 150_000
        await #expect(throws: ShieldedError.poolTooSmall(balance: 150_000, fees: 200_000)) { _ = try await model.shieldPool(pool.pubkeyHash) }
        rollup.pools[pool.pubkeyHash] = 1_000_000
        rollup.privateTxsInLevel = 3   // the dynamic fee: 0.1 tez doubled twice
        let receipt = try await model.shieldPool(pool.pubkeyHash)
        #expect(receipt.rollupFeeMutez == 400_000 && receipt.shieldedMutez == 500_000 && receipt.depositHash == nil)
        await #expect(throws: ShieldedError.poolUnknown("ff")) { _ = try await model.shieldPool("ff") }
    }

    @Test func theDashboardRowReportsAnUnreachableRollupWithoutLosingTheWallet() async throws {
        struct Down: ShieldedRollup {
            func head() async throws -> RollupHead { throw URLError(.cannotConnectToHost) }
            func smartRollupAddress() async throws -> String { throw URLError(.cannotConnectToHost) }
            func durableLength(block: String, key: String) async throws -> Int? { nil }
            func durableValue(block: String, key: String) async throws -> [UInt8]? { nil }
            func programHash(named program: String) async throws -> String { throw URLError(.cannotConnectToHost) }
            func startProof(programHash: String, arguments: [String]) async throws -> String { throw URLError(.cannotConnectToHost) }
            func proofJob(id: String, lastStatus: String?) async throws -> ProofJob { throw URLError(.cannotConnectToHost) }
            func submit(kind: String, payloadHex: String, rollupAddress: String, token: String) async throws -> OperatorSubmission { throw URLError(.cannotConnectToHost) }
            func submission(id: String, token: String) async throws -> OperatorSubmission { throw URLError(.cannotConnectToHost) }
        }
        var wallet = ShieldedWallet.make(chain: "shadownet")
        wallet.notes.append(ShieldedNote(index: 0, cm: "11", rseed: "22", nullifier: "33", valueMutez: "2500000", addressIndex: 0))
        wallet.pools.append(DepositPool(pubkeyHash: "44", blind: "55", addressIndex: 0, authDomain: "66", depositedMutez: "1", operationHash: "ooX", shieldedCm: nil, created: Date()))
        let store = InMemoryShieldedWalletStore(wallet: wallet)
        let keys = InMemoryWalletStore()
        try keys.add(WalletViewModel.sampleWallets[0], secretKey: "edskSAMPLE")
        let model = WalletViewModel(wallets: WalletViewModel.sampleWallets, chain: MockChainService(), walletStore: keys, shieldedStoreFactory: { _, _ in store }, shieldedRollupFactory: { _ in Down() })
        await model.refresh()
        #expect(model.assets.map(\.id) == ["tez"], "off by default")
        model.setShieldedEnabled(true, for: .shadownet)
        model.switchNetwork(to: .shadownet)
        await model.refresh()
        let row = try #require(model.assets.first { $0.kind == .shielded })
        #expect(row.amount == Decimal(string: "2.5") && row.unavailable?.contains("Shielded balance unavailable") == true)
        #expect(model.shieldedWallet == wallet && model.shieldedPools.count == 1 && model.shieldedPools[0].balanceMutez == nil)
        #expect(store.history.isEmpty, "nothing is written when the rollup cannot be read")
        // Quantumnet has shielded transactions but no services Signet knows: the placeholder row.
        model.setShieldedEnabled(true, for: .quantumnet)
        model.switchNetwork(to: .quantumnet)
        await model.refresh()
        #expect(model.assets.first { $0.kind == .shielded } == .shieldedPlaceholder && !model.canShield)
    }
}

// MARK: - Live

/// Shadownet, end to end: a faucet-funded account deposits into a fresh pool through the real
/// ticketer, the rollup credits it, the witness is proved by the proving service, and the shield
/// goes to the operator. Without `SIGNET_TZEL_OPERATOR_TOKEN` the operator's refusal is the
/// expected end (the pool stays funded for a later shield); with it the note is seen in the scan.
struct ShadownetShieldTests {
    @Test(.tags(.network), .liveNetwork, .timeLimit(.minutes(20)))
    @MainActor func depositsProvesAndShieldsOnShadownet() async throws {
        let token = ProcessInfo.processInfo.environment["SIGNET_TZEL_OPERATOR_TOKEN"]
        let material = try await KeyGenerator().generate(scheme: .tz1)
        let wallet = Wallet(alias: "shield-test", address: Address(material.address), scheme: .tz1, publicKey: material.publicKey, keyKind: .unencrypted)
        let keys = InMemoryWalletStore()
        try keys.add(wallet, secretKey: material.secretKey)
        let store = InMemoryShieldedWalletStore()
        let model = WalletViewModel(wallets: [wallet], chainFactory: { TaquitoChainService(network: $0) }, walletStore: keys, shieldedStoreFactory: { _, _ in store })
        model.setShieldedEnabled(true, for: .shadownet)
        model.switchNetwork(to: .shadownet)
        try model.setShieldedOperatorToken(token ?? "not-the-token", for: .shadownet)

        let faucet = try #require(FaucetService(network: .shadownet))
        _ = try await faucet.requestTez(to: wallet.address, amount: 5)
        let layer1 = TaquitoChainService(network: .shadownet)
        var funded = false
        for _ in 0..<40 { try await Task.sleep(for: .seconds(4)); if let b = try? await layer1.tezBalance(for: wallet.address), b.spendable >= 5 { funded = true; break } }
        #expect(funded)
        await model.refresh()

        let pool = try await model.prepareShield()
        print("shield pool \(pool.pubkeyHash)")
        let estimate = try await model.estimateShield(amount: 1, pool: pool)
        #expect(estimate.estimate.fee > 0 && estimate.rollupFeeMutez >= 100_000)
        do {
            let receipt = try await model.shieldTez(approved: estimate, passphrase: nil)
            #expect(token != nil, "the operator accepted a shield without the token?")
            print("shielded \(receipt.shieldedMutez) mutez, submission \(receipt.submissionID), op \(receipt.operationHash ?? "-")")
            var seen = false
            for _ in 0..<30 { try await Task.sleep(for: .seconds(6)); await model.refresh(); if model.shieldedWallet?.notes.contains(where: { $0.cm == receipt.cm }) == true { seen = true; break } }
            #expect(seen && model.shieldedWallet?.balanceMutez == receipt.shieldedMutez)
        } catch ShieldedError.operatorRefused(let detail) {
            #expect(token == nil, "the operator refused the token: \(detail)")
            print("operator refused as expected without a token: \(detail)")
        }
        let saved = try #require(try store.load())
        #expect(saved.pools.first?.operationHash != nil && saved.addresses[0].nextKeyIndex == 1, "the deposit landed and the shield was signed once")
        let rollup = RollupNodeService(config: .shadownet)
        let liveHead = try await rollup.head()
        let poolBalance = try await rollup.poolBalance(at: liveHead.hash, pubkeyHash: pool.pubkeyHash)
        #expect(poolBalance != nil || token != nil)
    }

    @Test(.tags(.network), .liveNetwork, .timeLimit(.minutes(2)))
    func readsTheRollupAndTheProvingServiceRegistry() async throws {
        let rollup = RollupNodeService(config: .shadownet)
        #expect(try await rollup.smartRollupAddress() == ShieldedConfig.shadownet.rollupAddress)
        let head = try await rollup.head()
        #expect(head.level > 0)
        #expect(try await rollup.authDomain(at: head.hash) == "f1e4e757b5cc5af59690170d4507c78621e520048955613170e0bb5c52dcbe07")
        #expect(try await rollup.verifierConfigured(at: head.hash))
        #expect(try await rollup.bridgeTicketer(at: head.hash) == ShieldedConfig.shadownet.ticketer.value)
        #expect(try await rollup.requiredTxFee(at: head) >= 100_000)
        #expect(try await rollup.treeSize(at: head.hash) >= 26)
        #expect(try await rollup.publishedNote(at: head.hash, index: 0)?.count == RollupState.publishedNoteBytes)
        #expect(try await rollup.nullifierCount(at: head.hash) >= 9)
        #expect(try await rollup.nullifier(at: head.hash, index: 0).count == 64)
        #expect(try await rollup.poolBalance(at: head.hash, pubkeyHash: String(repeating: "00", count: 32)) == nil)
        #expect(try await rollup.programHash(named: "run_shield").count == 64)
        await #expect(throws: ShieldedError.self) { _ = try await rollup.submit(kind: "shield", payloadHex: "00", rollupAddress: ShieldedConfig.shadownet.rollupAddress, token: "not-the-token") }
    }
}
