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
        let me = Address("tz1VSUr8wwNhLAzempoch5d6hLRiTh8Cjcjb"), other = Address("tz2BFTyPeYRzxd5aiBchbXN3WCZhx7BqbMBq")
        #expect(try store.load(account: me) == nil && (try store.loadLeaves(account: me, addressIndex: 0)) == nil && (try store.operatorToken()) == nil)
        var wallet = ShieldedWallet.make(chain: "shadownet")
        #expect(Hex.decode(wallet.masterSk)?.count == 32 && (Hex.decode(wallet.masterSk)?[31] ?? 0xff) & 0xf8 == 0, "a 251-bit master key")
        #expect(ShieldedWallet.make(chain: "shadownet").masterSk != wallet.masterSk)
        wallet.addresses.append(ShieldedAddress(index: 0, dJ: "aa", authRoot: "bb", pubSeed: "cc", nkTag: "dd", ekV: "ee", ekD: "ff", nextKeyIndex: 3))
        wallet.pools.append(DepositPool(pubkeyHash: "11", blind: "22", addressIndex: 0, authDomain: "33", depositedMutez: "1000000", operationHash: "ooX", shieldedCm: nil, created: Date(timeIntervalSince1970: 1_000_000)))
        wallet.notes.append(ShieldedNote(index: 7, cm: "44", rseed: "55", nullifier: "66", valueMutez: "1800000", addressIndex: 0))
        wallet.notes.append(ShieldedNote(index: 8, cm: "47", rseed: "58", nullifier: "69", valueMutez: "100", addressIndex: 0, spent: true))
        wallet.scanned = 9
        try store.save(wallet, account: me)
        try store.setOperatorToken("secret")
        #expect(try store.load(account: me) == wallet && (try store.load(account: other)) == nil && (try store.operatorToken()) == "secret")
        // Another account's wallet in the same file, and the token survives both.
        let second = ShieldedWallet.make(chain: "shadownet")
        try store.save(second, account: other)
        #expect(try store.load(account: me) == wallet && (try store.load(account: other)) == second && (try store.operatorToken()) == "secret")
        try store.setOperatorToken(nil)
        #expect(try store.operatorToken() == nil && (try store.load(account: me)) == wallet)
        #expect(wallet.balanceMutez == 1_800_000 && wallet.balance == Decimal(string: "1.8"))
        let attributes = try FileManager.default.attributesOfItem(atPath: directory.appendingPathComponent("tzel-shadownet.json").path)
        #expect((attributes[.posixPermissions] as? Int) == 0o600)
        let leaves = (0..<XMSSAuthTree.leavesBytes).map { UInt8($0 & 0xff) }
        try store.saveLeaves(leaves, account: me, addressIndex: 0)
        #expect(try store.loadLeaves(account: me, addressIndex: 0) == leaves && (try store.loadLeaves(account: other, addressIndex: 0)) == nil)
        #expect(WalletBackup.files.contains("tzel-shadownet.json") && WalletBackup.valuableFiles.contains("tzel-shadownet.json"))
        #expect(!WalletBackup.files.contains("tzel-shadownet-auth0.bin"))
    }

    /// A version 1 file (one wallet for the network, token inside) is read and handed to the
    /// account that adopts it, leaves file included; nothing shielded is lost.
    @Test func aVersionOneFileIsAdoptedByAnAccount() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("signet-shielded-v1-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try PrivateFile.hardenDirectory(directory)
        let me = Address("tz1VSUr8wwNhLAzempoch5d6hLRiTh8Cjcjb")
        let v1 = """
        {"version":1,"chain":"shadownet","masterSk":"\(String(repeating: "07", count: 32))","depositNonce":1,"scanned":28,"nullifiersSeen":9,"operatorToken":"tok",
         "addresses":[{"index":0,"dJ":"aa","authRoot":"bb","pubSeed":"cc","nkTag":"dd","ekV":"ee","ekD":"ff","nextKeyIndex":1}],
         "pools":[{"pubkeyHash":"11","blind":"22","addressIndex":0,"authDomain":"33","depositedMutez":"10000000","operationHash":"ooDeposit","shieldedCm":"44","created":"2026-10-19T20:00:00Z"}],
         "notes":[{"index":26,"cm":"44","rseed":"55","nullifier":"66","valueMutez":"9800000","addressIndex":0,"spent":false}]}
        """
        try PrivateFile.write(Data(v1.utf8), to: directory.appendingPathComponent("tzel-shadownet.json"))
        let leaves = [UInt8](repeating: 9, count: XMSSAuthTree.leavesBytes)
        try PrivateFile.write(Data(leaves), to: directory.appendingPathComponent("tzel-shadownet-auth0.bin"))
        let store = FileShieldedWalletStore(directory: directory, chain: "shadownet")
        #expect(try store.load(account: me) == nil && (try store.operatorToken()) == "tok")
        let legacy = try #require(try store.legacyWallet())
        #expect(legacy.balanceMutez == 9_800_000 && legacy.addresses[0].nextKeyIndex == 1 && legacy.pools[0].operationHash == "ooDeposit" && legacy.scanned == 28)
        try store.adoptLegacyWallet(for: me)
        #expect(try store.legacyWallet() == nil && (try store.load(account: me)) == legacy && (try store.operatorToken()) == "tok")
        #expect(try store.loadLeaves(account: me, addressIndex: 0) == leaves)
        try store.adoptLegacyWallet(for: me)   // a second time changes nothing
        #expect(try store.load(account: me) == legacy)
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
    /// What `/tzel/v1/state/tree/root` serves; tests set it from the bridge's `tzelMerkleRoot`.
    var treeRoot: String?
    var cemented = 0
    var outbox: [OutboxEntry] = []
    var submitted: [(kind: String, payload: String, token: String)] = []
    var proofRequests: [[String]] = []
    var failProving: String?
    var failDelivery = false

    func head() async throws -> RollupHead { lock.withLock { RollupHead(hash: "BLmock\(level)", level: level) } }
    func smartRollupAddress() async throws -> String { lock.withLock { address } }

    private func value(_ key: String) -> [UInt8]? {
        func le(_ n: UInt64, _ count: Int) -> [UInt8] { (0..<count).map { UInt8(truncatingIfNeeded: n >> (8 * UInt64($0))) } }
        switch key {
        case RollupState.authDomain: return Hex.decode(authDomain)
        case RollupState.verifierConfig: return verifierInstalled ? [1, 2, 3] : nil
        case RollupState.bridgeTicketer: return Array(ticketer.utf8)
        case RollupState.treeSize: return le(UInt64(notes.count), 8)
        case RollupState.treeRoot: return treeRoot.flatMap(Hex.decode)
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

    /// A witness word (`0x…`, big-endian) as a felt, hex.
    static func felt(_ arg: String) -> String {
        var hex = String(arg.dropFirst(2))
        hex = String(repeating: "0", count: 64 - hex.count) + hex
        return Hex.encode(Hex.decode(hex)!.reversed())
    }

    /// "Proves" by echoing the witness's public outputs behind the bootloader header, as the
    /// service does: the shield's nine, or the unshield's `2 + n + 7` (the two commitments the
    /// circuit would compute are computed with the bridge).
    func proofJob(id: String, lastStatus: String?) async throws -> ProofJob {
        let (request, failure): ([String]?, String?) = lock.withLock { (proofRequests.last, failProving) }
        if let failure { return .failed(failure) }
        guard let request else { return .failed("no witness") }
        var outputs: [String]
        if request.count == 171 {
            outputs = request[1...9].map(Self.felt)
        } else if let n = Int(request[1].dropFirst(2), radix: 16), request.count == 1 + 4 + n * 206 + 24 {
            // A transfer: the three output commitments and memo hashes are in the witness.
            let w = request, tail = 5 + 206 * n
            outputs = [w[2], w[3]].map(Self.felt) + (0..<n).map { Self.felt(w[5 + 9 * $0]) } + [Self.felt(w[4])]
                + [w[tail], w[tail + 8], w[tail + 16]].map(Self.felt) + [w[tail + 7], w[tail + 15], w[tail + 23]].map(Self.felt)
        } else {
            guard let n = Int(request[1].dropFirst(2), radix: 16), request.count == 1 + 6 + n * 206 + 15 else { return .failed("bad witness") }
            let w = request
            func commitment(_ at: Int) async throws -> String {
                let v = String(UInt64(w[at + 1].dropFirst(2), radix: 16) ?? 0)
                return try await TaquitoBridge.shared.call("tzelNoteCommitment", [Self.felt(w[at]), v, Self.felt(w[at + 2]), Self.felt(w[at + 3]), Self.felt(w[at + 4]), Self.felt(w[at + 5])]).stringValue ?? ""
            }
            let flag = 7 + 206 * n
            let hasChange = w[flag] != "0x0"
            let changeCm = hasChange ? try await commitment(flag + 1) : Hex.encode(XMSSAuthTree.feltOfInt(0))
            let feeCm = try await commitment(flag + 8)
            outputs = [w[2], w[3]].map(Self.felt) + (0..<n).map { Self.felt(w[7 + 9 * $0]) } + [w[4], w[5], w[6]].map(Self.felt)
                + [changeCm, Self.felt(w[flag + 7]), feeCm, Self.felt(w[flag + 14])]
        }
        let header = [1, outputs.count + 3].map { Hex.encode(XMSSAuthTree.feltOfInt(UInt64($0))) } + [String(repeating: "ab", count: 32), Hex.encode(XMSSAuthTree.feltOfInt(UInt64(outputs.count)))]
        return lastStatus == nil ? .running : .done(ProofBundle(proofBytes: "aabbcc", outputPreimage: header + outputs))
    }

    func submit(kind: String, payloadHex: String, rollupAddress: String, token: String) async throws -> OperatorSubmission {
        guard token == "operator-secret" else { throw ShieldedError.operatorRefused("missing Authorization header") }
        lock.withLock { submitted.append((kind, payloadHex, token)) }
        return OperatorSubmission(id: "sub-\(submitted.count)", status: "commitment_included", transport: "dal", operationHash: nil, detail: nil)
    }

    func submission(id: String, token: String) async throws -> OperatorSubmission {
        if lock.withLock({ failDelivery }) { return OperatorSubmission(id: id, status: "failed", transport: "dal", operationHash: nil, detail: "slot not attested") }
        return OperatorSubmission(id: id, status: "submitted_to_l1", transport: "dal", operationHash: "ooShieldPointer", detail: nil)
    }

    func cementedLevel() async throws -> Int { lock.withLock { cemented } }
    func pendingOutbox() async throws -> [OutboxEntry] { lock.withLock { outbox } }
    func outboxProof(outboxLevel: Int, messageIndex: Int) async throws -> OutboxProof {
        guard lock.withLock({ cemented >= outboxLevel && outbox.contains { $0.outboxLevel == outboxLevel && $0.messageIndex == messageIndex } }) else {
            throw ShieldedError.withdrawalNotReady("outbox level \(outboxLevel) is not cemented")
        }
        return OutboxProof(commitment: "src13Ycd5ZPbQGiLiVuWqAMUhNuaWafb5T7KoqHsMGEAStvScGDFgx", proof: "aabb")
    }

    /// Applies the last submitted transfer as the kernel would: the nullifiers are spent and
    /// the three notes join the tree. Returns their commitments.
    func applyLastTransfer() -> [String] {
        lock.withLock {
            let b = Hex.decode(submitted.last!.payload)!
            var o = 7
            func u32() -> Int { let v = Int(b[o]) << 24 | Int(b[o + 1]) << 16 | Int(b[o + 2]) << 8 | Int(b[o + 3]); o += 4; return v }
            func take(_ n: Int) -> [UInt8] { let s = Array(b[o..<(o + n)]); o += n; return s }
            _ = take(32)
            let end = o + u32()
            var spent: [String] = []
            while o < end { let l = u32(); spent.append(Hex.encode(take(l))) }
            _ = take(8)
            let cms = (0..<3).map { _ in take(32) }
            _ = take(u32())
            for cm in cms { notes.append(cm + take(u32())) }
            nullifiers += spent
            return cms.map(Hex.encode)
        }
    }

    /// Applies the last submitted unshield as the kernel would: the nullifiers are spent, the
    /// change note (if any) and the producer note join the tree, and the ticketer's `burn` for
    /// the recipient is queued in the outbox at the current level.
    func applyLastUnshield() -> (changeCm: String?, nullifiers: [String]) {
        lock.withLock {
            let b = Hex.decode(submitted.last!.payload)!
            var o = 7
            func u32() -> Int { let v = Int(b[o]) << 24 | Int(b[o + 1]) << 16 | Int(b[o + 2]) << 8 | Int(b[o + 3]); o += 4; return v }
            func take(_ n: Int) -> [UInt8] { let s = Array(b[o..<(o + n)]); o += n; return s }
            _ = take(32)
            let end = o + u32()
            var spent: [String] = []
            while o < end { let l = u32(); spent.append(Hex.encode(take(l))) }
            let vPub = take(8).enumerated().reduce(UInt64(0)) { $0 | UInt64($1.element) << (8 * UInt64($1.offset)) }
            _ = take(8)
            let recipient = String(decoding: take(u32()), as: UTF8.self)
            let cmChange = take(32)
            _ = take(u32())
            var changeCm: String?
            if take(1)[0] == 0xff { notes.append(cmChange + take(u32())); changeCm = Hex.encode(cmChange) }
            let cmFee = take(32)
            notes.append(cmFee + take(u32()))
            nullifiers += spent
            outbox.append(OutboxEntry(outboxLevel: level, messageIndex: outbox.count, destination: ticketer, entrypoint: "burn", receiver: Address(recipient).forgedContract ?? "", amountMutez: vPub))
            return (changeCm, spent)
        }
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
        let me = WalletViewModel.sampleWallets[0].address
        let pool = try await model.prepareShield()
        var wallet = try #require(try store.load(account: me))
        #expect(wallet.addresses.count == 1 && wallet.addresses[0].nextKeyIndex == 0 && wallet.pools == [pool] && wallet.depositNonce == 1)
        #expect(try store.loadLeaves(account: me, addressIndex: 0)?.count == XMSSAuthTree.leavesBytes)
        #expect(pool.operationHash == nil && pool.authDomain == rollup.authDomain && pool.addressIndex == 0)
        // Preparing again reuses the unfunded pool rather than minting ids.
        #expect(try await model.prepareShield() == pool)
        let estimate = try await model.estimateShield(amount: 2, pool: pool)
        #expect(estimate.rollupFeeMutez == 100_000 && estimate.producerFeeMutez == 100_000 && estimate.shieldedAmount == Decimal(string: "1.8") && estimate.estimate.limits != nil)
        await #expect(throws: ShieldedError.operatorTokenMissing) { _ = try await model.shieldTez(approved: estimate, passphrase: nil) }
        #expect(try store.load(account: me)?.pools.first?.operationHash == nil, "nothing was sent without the token")

        try model.setShieldedOperatorToken("operator-secret", for: .shadownet)
        #expect(model.shieldedOperatorTokenIsSet(for: .shadownet) && !model.shieldedOperatorTokenIsSet(for: .mainnet))
        // The rollup credits the pool when the (mock) deposit lands.
        rollup.pools[pool.pubkeyHash] = 2_000_000
        let receipt = try await model.shieldTez(approved: estimate, passphrase: nil)
        #expect(receipt.depositHash == "ooMockShieldDeposit" && receipt.shieldedMutez == 1_800_000 && receipt.rollupFeeMutez == 100_000 && receipt.operationHash == "ooShieldPointer")
        wallet = try #require(try store.load(account: me))
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
        // Another account in the same directory has a shielded wallet of its own: nothing to show yet.
        rollup.nullifiers = []
        model.select(WalletViewModel.sampleWallets[1])
        await model.refresh()
        #expect(model.shieldedWallet == nil && model.assets.first { $0.kind == .shielded }?.amount == 0 && model.shieldedPools.isEmpty)
        model.select(WalletViewModel.sampleWallets[0])
        await model.refresh()
        #expect(model.shieldedWallet?.notes.count == 1)
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
        #expect(try store.load(account: WalletViewModel.sampleWallets[0].address) == nil, "no wallet before the rollup passed its checks")
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
        let wallet = try #require(try store.load(account: WalletViewModel.sampleWallets[0].address))
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

    @Test func aLegacyWalletGoesToTheAccountThatFundedIt() async throws {
        struct Funder: TestChainService {
            func tezBalance(for address: Address) async throws -> TezBalance { TezBalance(spendable: 1) }
        }
        var legacy = ShieldedWallet.make(chain: "shadownet")
        legacy.notes.append(ShieldedNote(index: 26, cm: "11", rseed: "22", nullifier: "33", valueMutez: "9800000", addressIndex: 0))
        legacy.pools.append(DepositPool(pubkeyHash: "44", blind: "55", addressIndex: 0, authDomain: "66", depositedMutez: "10000000", operationHash: nil, shieldedCm: "11", created: Date()))
        let store = InMemoryShieldedWalletStore(legacy: legacy)
        let keys = InMemoryWalletStore()
        try keys.add(WalletViewModel.sampleWallets[0], secretKey: "edskSAMPLE")
        let model = WalletViewModel(wallets: WalletViewModel.sampleWallets, chain: Funder(), walletStore: keys, shieldedStoreFactory: { _, _ in store }, shieldedRollupFactory: { _ in MockShieldedRollup() })
        model.setShieldedEnabled(true, for: .shadownet)
        model.switchNetwork(to: .shadownet)
        await model.refresh()
        // No operation hash to ask TzKT about: the selected account adopts it.
        #expect(try store.legacyWallet() == nil && (try store.load(account: WalletViewModel.sampleWallets[0].address))?.notes.count == 1)
        #expect(model.shieldedWallet?.balanceMutez == 9_800_000 && model.assets.first { $0.kind == .shielded }?.amount == Decimal(string: "9.8"))
        model.select(WalletViewModel.sampleWallets[1])
        await model.refresh()
        #expect(model.shieldedWallet == nil && model.assets.first { $0.kind == .shielded }?.amount == 0)
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
            func cementedLevel() async throws -> Int { throw URLError(.cannotConnectToHost) }
            func pendingOutbox() async throws -> [OutboxEntry] { throw URLError(.cannotConnectToHost) }
            func outboxProof(outboxLevel: Int, messageIndex: Int) async throws -> OutboxProof { throw URLError(.cannotConnectToHost) }
        }
        var wallet = ShieldedWallet.make(chain: "shadownet")
        wallet.notes.append(ShieldedNote(index: 0, cm: "11", rseed: "22", nullifier: "33", valueMutez: "2500000", addressIndex: 0))
        wallet.pools.append(DepositPool(pubkeyHash: "44", blind: "55", addressIndex: 0, authDomain: "66", depositedMutez: "1", operationHash: "ooX", shieldedCm: nil, created: Date()))
        let store = InMemoryShieldedWalletStore(wallets: [WalletViewModel.sampleWallets[0].address.value: wallet])
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

@MainActor
struct UnshieldFlowTests {
    private func shieldedModel() async throws -> (WalletViewModel, InMemoryShieldedWalletStore, MockShieldedRollup, ShieldedNote) {
        let store = InMemoryShieldedWalletStore()
        let rollup = MockShieldedRollup()
        let keys = InMemoryWalletStore()
        try keys.add(WalletViewModel.sampleWallets[0], secretKey: "edskSAMPLE")
        let model = WalletViewModel(wallets: WalletViewModel.sampleWallets, chain: MockChainService(), walletStore: keys, shieldedStoreFactory: { _, _ in store }, shieldedRollupFactory: { _ in rollup })
        model.setShieldedEnabled(true, for: .shadownet)
        model.switchNetwork(to: .shadownet)
        model.shieldedCreditPolls = 2
        model.shieldedPollInterval = .milliseconds(10)
        try model.setShieldedOperatorToken("operator-secret", for: .shadownet)
        // A 1.8 tz note at tree position 0, from a 2 tz deposit.
        let pool = try await model.prepareShield()
        rollup.pools[pool.pubkeyHash] = 2_000_000
        _ = try await model.shieldTez(approved: try await model.estimateShield(amount: 2, pool: pool), passphrase: nil)
        let cm = rollup.applyLastShield()
        rollup.treeRoot = try await TaquitoBridge.shared.call("tzelMerkleRoot", [try WalletViewModel.json(.array([.string(cm)]))]).stringValue
        await model.refresh()
        let note = try #require(model.shieldedWallet?.notes.first)
        #expect(model.shieldedWallet?.leafCms == [cm] && note.valueMutez == "1800000" && !note.spent)
        return (model, store, rollup, note)
    }

    @Test func unshieldsANoteWithChangeAndFollowsTheWithdrawalToTezos() async throws {
        let (model, store, rollup, note) = try await shieldedModel()
        let me = WalletViewModel.sampleWallets[0].address
        // A bad recipient, or more than the notes hold, is refused at the estimate.
        await #expect(throws: ShieldedError.badRecipient("bob")) { _ = try await model.estimateUnshield(amount: 1, recipient: "bob") }
        await #expect(throws: ShieldedError.insufficientShielded(available: 1_800_000, needed: 2_200_000)) { _ = try await model.estimateUnshield(amount: 2, recipient: me.value) }
        let estimate = try await model.estimateUnshield(amount: 1, recipient: " \(me.value) ")
        #expect(estimate.inputs == [note] && estimate.rollupFeeMutez == 100_000 && estimate.producerFeeMutez == 100_000 && estimate.changeMutez == 600_000 && estimate.recipient == me.value)
        // The rollup's fee moved since the estimate: refused before anything is proved or any key spent.
        rollup.privateTxsInLevel = 3
        await #expect(throws: ShieldedError.feeChanged(from: 100_000, to: 400_000)) { _ = try await model.unshieldTez(approved: estimate) }
        rollup.privateTxsInLevel = 0
        #expect(try store.load(account: me)?.addresses[0].nextKeyIndex == 1 && rollup.proofRequests.count == 1)

        let receipt = try await model.unshieldTez(approved: estimate)
        #expect(receipt.amount == 1 && receipt.changeMutez == 600_000 && receipt.withdrawal.recipient == me.value && receipt.withdrawal.nullifiers == [note.nullifier])
        #expect(receipt.withdrawal.operationHash == "ooShieldPointer" && receipt.withdrawal.submittedLevel == rollup.level && receipt.withdrawal.changeCm != nil)
        var wallet = try #require(try store.load(account: me))
        #expect(wallet.addresses.count == 2 && wallet.addresses[0].nextKeyIndex == 2 && wallet.addresses[1].nextKeyIndex == 0, "one key spent, a change address made")
        #expect(try store.loadLeaves(account: me, addressIndex: 1)?.count == XMSSAuthTree.leavesBytes, "the change address's signing tree is kept")
        #expect(wallet.withdrawals.count == 1 && !wallet.withdrawals[0].applied && wallet.availableMutez == 0 && wallet.balanceMutez == 1_800_000 && wallet.reservedMutez == 1_800_000)
        #expect(model.assets.first { $0.kind == .shielded }?.details.map(\.id) == ["unshielding"])
        // The witness: one input, 227 felts after the length word; the message: tag 4, then the root.
        let witness = try #require(rollup.proofRequests.last)
        #expect(witness.count == 1 + 6 + 206 + 15 && witness[0] == "0xe3" && witness[1] == "0x1")
        let sent = try #require(rollup.submitted.last)
        #expect(sent.kind == "unshield" && sent.payload.hasPrefix("110004") && String(sent.payload.dropFirst(14).prefix(64)) == rollup.treeRoot)
        // The key index was on file before the proof was asked for, the withdrawal before the operator was polled.
        let saves = store.history
        let indexSpent = try #require(saves.firstIndex { $0.addresses.first?.nextKeyIndex == 2 })
        let recorded = try #require(saves.firstIndex { !$0.withdrawals.isEmpty })
        #expect(indexSpent < recorded)
        // A reserved note is not offered to another unshield.
        await #expect(throws: ShieldedError.insufficientShielded(available: 0, needed: 300_000)) { _ = try await model.estimateUnshield(amount: 0.1, recipient: me.value) }

        // The kernel applies it: the note is spent, the change note is ours, the withdrawal is in the outbox and waiting.
        let applied = rollup.applyLastUnshield()
        #expect(applied.changeCm == receipt.withdrawal.changeCm && applied.nullifiers == [note.nullifier])
        await model.refresh()
        wallet = try #require(model.shieldedWallet)
        #expect(wallet.notes.count == 2 && wallet.notes[0].spent && wallet.notes[1].valueMutez == "600000" && wallet.notes[1].addressIndex == 1 && wallet.notes[1].index == 1)
        #expect(wallet.leafCms.count == 3 && wallet.balanceMutez == 600_000 && wallet.availableMutez == 600_000)
        let status = try #require(model.shieldedWithdrawals.first)
        #expect(status.withdrawal.applied && status.withdrawal.outboxLevel == rollup.level && status.withdrawal.messageIndex == 0)
        #expect(status.state == .waiting(blocksLeft: rollup.level))
        await #expect(throws: ShieldedError.withdrawalNotReady("the rollup commitment covering it is not cemented yet (about 14 days after the unshield)")) { _ = try await model.estimateWithdrawalExecution(status.id) }
        // Cemented: the account executes it through the approved-limits path.
        rollup.cemented = rollup.level
        await model.refresh()
        #expect(model.shieldedWithdrawals.first?.state == .ready)
        let execution = try await model.estimateWithdrawalExecution(status.id)
        #expect(execution.execution.cementedCommitment.hasPrefix("src1") && execution.execution.rollup == ShieldedConfig.shadownet.rollupAddress && execution.estimate.limits != nil)
        let hash = try await model.executeWithdrawal(approved: execution, passphrase: nil)
        #expect(hash == "ooMockOutbox" && model.shieldedWallet?.withdrawals.first?.executedHash == "ooMockOutbox")
        #expect(model.shieldedWithdrawals.first?.state == .executed("ooMockOutbox"))
        await #expect(throws: ShieldedError.withdrawalNotReady("it has been executed already")) { _ = try await model.estimateWithdrawalExecution(status.id) }
    }

    @Test func anUndeliveredUnshieldFreesItsNotesAndAnExactOneMakesNoChange() async throws {
        let (model, store, rollup, note) = try await shieldedModel()
        let me = WalletViewModel.sampleWallets[0].address
        // The operator gives up on it: no withdrawal stays, the notes are available again, the key index stays spent.
        rollup.failDelivery = true
        let estimate = try await model.estimateUnshield(amount: 1, recipient: me.value)
        await #expect(throws: ShieldedError.submissionFailed("slot not attested")) { _ = try await model.unshieldTez(approved: estimate) }
        var wallet = try #require(try store.load(account: me))
        #expect(wallet.withdrawals.isEmpty && wallet.availableMutez == 1_800_000 && wallet.addresses[0].nextKeyIndex == 2 && wallet.addresses.count == 2)
        rollup.failDelivery = false
        // Unshielding exactly what is left after the fees: no change note, the flag and its fields are zero.
        let exact = try await model.estimateUnshield(amount: 1.6, recipient: "KT1RCZzNe8G4VQ94YWqb6Xz4q9WGWVdMWSB4")
        #expect(exact.changeMutez == 0 && exact.inputs == [note])
        let receipt = try await model.unshieldTez(approved: exact)
        #expect(receipt.changeMutez == 0 && receipt.withdrawal.changeCm == nil)
        wallet = try #require(try store.load(account: me))
        #expect(wallet.addresses.count == 2 && wallet.addresses[0].nextKeyIndex == 3, "no further change address")
        let witness = try #require(rollup.proofRequests.last)
        #expect(Array(witness[(7 + 206)..<(7 + 206 + 8)]) == Array(repeating: "0x0", count: 8))
        // Forgetting one the operator has not delivered frees the notes; when it lands after all, the scan still spends them.
        try model.forgetWithdrawal(receipt.withdrawal.id)
        #expect(try store.load(account: me)?.availableMutez == 1_800_000 && model.shieldedWithdrawals.isEmpty)
        let applied = rollup.applyLastUnshield()
        #expect(applied.changeCm == nil)
        await model.refresh()
        #expect(model.shieldedWallet?.balanceMutez == 0 && model.shieldedWallet?.notes.count == 1 && model.shieldedWallet?.leafCms.count == 2)
    }

    @Test func selectsTheLargestNotesFirstAndRefusesMoreThanSevenInputs() throws {
        func note(_ i: Int, _ v: UInt64) -> ShieldedNote { ShieldedNote(index: i, cm: "cm\(i)", rseed: "", nullifier: "nf\(i)", valueMutez: String(v), addressIndex: 0) }
        let notes = (0..<10).map { note($0, UInt64($0 + 1) * 100_000) }
        #expect(try WalletViewModel.selectNotes(notes, covering: 1_000_000).map(\.index) == [9])
        #expect(try WalletViewModel.selectNotes(notes, covering: 1_000_001).map(\.index) == [9, 8])
        #expect(try WalletViewModel.selectNotes(notes, covering: 4_900_000).map(\.index) == [9, 8, 7, 6, 5, 4, 3])
        #expect(throws: ShieldedError.tooManyInputs(8)) { try WalletViewModel.selectNotes(notes, covering: 4_900_001) }
        #expect(throws: ShieldedError.insufficientShielded(available: 5_500_000, needed: 5_500_001)) { try WalletViewModel.selectNotes(notes, covering: 5_500_001) }
        #expect(try WalletViewModel.selectNotes([], covering: 0).isEmpty)
    }

    /// Alice (sample account 0) sends to Bob (sample account 1), both in the same directory:
    /// Bob's shielded address comes from his Shielded address sheet, goes into Alice's address
    /// book, and the note reaches him with the memo while Alice gets her change.
    @Test func sendsAShieldedTransferToAnotherAccountsAddress() async throws {
        let (model, store, rollup, note) = try await shieldedModel()
        let alice = WalletViewModel.sampleWallets[0], bob = WalletViewModel.sampleWallets[1]
        // Bob hands out his address: the JSON other wallets take, with its fingerprint; a new one is a fresh address of his.
        model.select(bob)
        let handed = try await model.shieldedReceiveAddress()
        #expect(handed.index == 0 && handed.json.contains("\"ek_v\"") && handed.fingerprint.count == 64)
        let fresh = try await model.makeShieldedAddress()
        let bobWallet = try store.load(account: bob.address)
        #expect(fresh.index == 1 && fresh.fingerprint != handed.fingerprint && bobWallet?.addresses.count == 2)
        let again = try await model.shieldedReceiveAddress()
        #expect(again == fresh, "the newest address is the one handed out")
        // Alice pastes it, saves it, and sends 1 tz with a memo.
        model.select(alice)
        await model.refresh()
        let pasted = try await model.shieldedRecipient(from: fresh.json)
        #expect(pasted.fingerprint == fresh.fingerprint && pasted.name.isEmpty)
        await #expect(throws: ShieldedError.self) { _ = try await model.shieldedRecipient(from: "{\"d_j\": \"zz\"}") }
        try model.addShieldedContact(pasted, name: "Bob")
        #expect(throws: ShieldedError.contactExists("Bob")) { try model.addShieldedContact(pasted, name: "Robert") }
        let contact = try #require(try model.shieldedContacts().first)
        #expect(contact.name == "Bob" && contact.fingerprint == fresh.fingerprint)
        let known = try await model.shieldedRecipient(from: fresh.json)
        #expect(known.name == "Bob", "a known address comes back with its name")
        let estimate = try await model.estimateSendShielded(amount: 1, recipient: contact, memo: "for lunch")
        #expect(estimate.inputs == [note] && estimate.changeMutez == 600_000 && estimate.fees == Decimal(string: "0.2"))
        await #expect(throws: ShieldedError.memoTooLong) { _ = try await model.estimateSendShielded(amount: 1, recipient: contact, memo: String(repeating: "x", count: 1025)) }
        let receipt = try await model.sendShielded(approved: estimate)
        #expect(receipt.amount == 1 && receipt.transfer.recipientName == "Bob" && receipt.transfer.memo == "for lunch" && receipt.transfer.nullifiers == [note.nullifier] && !receipt.transfer.applied)
        let witness = try #require(rollup.proofRequests.last)
        #expect(witness.count == 1 + 4 + 206 + 24 && witness[0] == "0xea" && witness[1] == "0x1")
        let sent = try #require(rollup.submitted.last)
        #expect(sent.kind == "transfer" && sent.payload.hasPrefix("110003"))
        var wallet = try #require(try store.load(account: alice.address))
        #expect(wallet.transfers.count == 1 && wallet.availableMutez == 0 && wallet.addresses.count == 2 && wallet.addresses[0].nextKeyIndex == 2)
        // The kernel applies it: Alice's note is spent and her change is back; Bob has 1 tz with the memo.
        let cms = rollup.applyLastTransfer()
        #expect(cms[0] == receipt.transfer.recipientCm && cms[1] == receipt.transfer.changeCm)
        await model.refresh()
        wallet = try #require(model.shieldedWallet)
        #expect(wallet.notes.count == 2 && wallet.notes[0].spent && wallet.notes[1].valueMutez == "600000" && wallet.notes[1].addressIndex == 1 && wallet.transfers[0].applied)
        #expect(model.shieldedTransfers.first?.applied == true && wallet.availableMutez == 600_000)
        model.select(bob)
        await model.refresh()
        let received = try #require(model.shieldedWallet?.notes.first)
        #expect(received.cm == cms[0] && received.valueMutez == "1000000" && received.addressIndex == 1 && received.memo == "for lunch" && model.shieldedWallet?.balanceMutez == 1_000_000)
        #expect(model.shieldedWallet?.notes.count == 1, "the change and the producer note are not Bob's")
        try model.removeShieldedContact(contact.fingerprint)
        let left = try model.shieldedContacts()
        #expect(left.isEmpty)
    }

    @Test func forgesRecipientsAsOutboxMessagesNameThem() {
        #expect(Address("tz1VSUr8wwNhLAzempoch5d6hLRiTh8Cjcjb").forgedContract == "00006b82198cb179e8306c1bedd08f12dc863f328886")
        #expect(Address("KT1RCZzNe8G4VQ94YWqb6Xz4q9WGWVdMWSB4").forgedContract?.hasPrefix("01") == true && Address("KT1RCZzNe8G4VQ94YWqb6Xz4q9WGWVdMWSB4").forgedContract?.count == 44)
        #expect(Address("tz3Rb5RVucLc6ani23jVdZM4Qm6c4oQ74zhh").forgedContract?.hasPrefix("0002") == true)
        #expect(Address("bob").forgedContract == nil)
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
            // Then part of it back to the account: proved by the real `run_unshield`, applied by
            // the kernel (the nullifier appears, the change note is ours) and queued in the
            // outbox. Executing it on layer 1 is 14 days away, so the test stops at "waiting".
            let unshield = try await model.estimateUnshield(amount: 0.3, recipient: wallet.address.value)
            #expect(unshield.inputs.map(\.cm) == [receipt.cm] && unshield.changeMutez == receipt.shieldedMutez - 300_000 - unshield.rollupFeeMutez - 100_000)
            let withdrawal = try await model.unshieldTez(approved: unshield)
            print("unshield submission \(withdrawal.withdrawal.submissionID), op \(withdrawal.withdrawal.operationHash ?? "-"), change \(withdrawal.changeMutez)")
            var applied = false
            for _ in 0..<30 { try await Task.sleep(for: .seconds(6)); await model.refresh(); if model.shieldedWithdrawals.first?.withdrawal.applied == true { applied = true; break } }
            #expect(applied, "the rollup applied the unshield")
            let after = try #require(model.shieldedWallet)
            #expect(after.notes.first { $0.cm == receipt.cm }?.spent == true && after.notes.contains { $0.cm == withdrawal.withdrawal.changeCm } && after.balanceMutez == withdrawal.changeMutez)
            if case .waiting(let blocks) = try #require(model.shieldedWithdrawals.first).state { print("outbox message at level \(model.shieldedWithdrawals.first?.withdrawal.outboxLevel ?? 0), \(blocks) blocks to cementation") } else { Issue.record("expected the withdrawal to be waiting for cementation: \(String(describing: model.shieldedWithdrawals.first?.state))") }
        } catch ShieldedError.operatorRefused(let detail) {
            #expect(token == nil, "the operator refused the token: \(detail)")
            print("operator refused as expected without a token: \(detail)")
        }
        let saved = try #require(try store.load(account: wallet.address))
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
        #expect(try await rollup.programHash(named: "run_unshield").count == 64)
        #expect(try await rollup.treeRoot(at: head.hash).count == 64)
        #expect(try await rollup.cementedLevel() < head.level)
        let pending = try await rollup.pendingOutbox()
        #expect(pending.allSatisfy { $0.entrypoint == "burn" && $0.destination == ShieldedConfig.shadownet.ticketer.value && $0.receiver.count == 44 })
        if let first = pending.first { await #expect(throws: ShieldedError.self) { _ = try await rollup.outboxProof(outboxLevel: first.outboxLevel, messageIndex: first.messageIndex) } }
        await #expect(throws: ShieldedError.self) { _ = try await rollup.submit(kind: "shield", payloadHex: "00", rollupAddress: ShieldedConfig.shadownet.rollupAddress, token: "not-the-token") }
    }
}
