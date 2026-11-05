import Foundation
import Testing
@testable import Signet

/// The 5 November 2026 audit's fixes (`audit/AUDIT_20261105.md`): the console boundary
/// (K01), the shielded wallet file's cross-process lock and size bounds (G01, G05), untrusted
/// rollup numbers (G08), records that survive an unknown operator outcome (T01), and the
/// plain-HTTP note (G04).
struct AuditFixTests {
    // MARK: K01: the console boundary

    @Test func redactionCoversUUIDSeedsAndByteDumps() {
        let seed = "1786ff8a-2dd8-4554-8f99-6735d76e2170"
        #expect(TaquitoBridge.redactedLine("Generating new ID: \(seed)") == "Generating new ID: <uuid 1786ff8a…>")
        let object = "{" + (0..<32).map { "\"\($0)\":\($0 * 7 % 256)" }.joined(separator: ",") + "}"
        #expect(TaquitoBridge.redactedLine("key \(object) end") == "key <32 bytes> end")
        let array = "[" + (0..<32).map { String($0 * 5 % 256) }.joined(separator: ", ") + "]"
        #expect(TaquitoBridge.redactedLine("sk \(array)") == "sk <32 bytes>")
        // Short runs and ordinary numbers are left alone.
        #expect(TaquitoBridge.redactedLine("[1, 2, 3] {\"0\":1,\"1\":2}") == "[1, 2, 3] {\"0\":1,\"1\":2}")
        #expect(TaquitoBridge.redactedLine("fetch #3 ← 200 1234 bytes") == "fetch #3 ← 200 1234 bytes")
    }

    @Test func consoleObjectsAreScrubbedBeforeSerialisation() async throws {
        let bridge = TaquitoBridge()
        let bytes = (0..<32).map { $0 * 3 % 256 }
        let object: [String: Any] = [
            "ok": 1, "name": "transport",
            "client": ["keyPair": ["publicKey": bytes, "secretKey": bytes], "seed": "1786ff8a-2dd8-4554-8f99-6735d76e2170"],
            "privateKey": "plain", "bytes": bytes, "asObject": Dictionary(uniqueKeysWithValues: bytes.enumerated().map { (String($0.offset), $0.element) }),
        ]
        let json = String(decoding: try JSONSerialization.data(withJSONObject: object), as: UTF8.self)
        _ = try await bridge.call("bridgeEchoObject", [json])
        let line = try #require(bridge.consoleLines.last { $0.hasPrefix("[log] echo-object:") })
        #expect(line.contains("\"ok\":1") && line.contains("\"name\":\"transport\""))
        #expect(line.contains("\"keyPair\":\"<redacted>\"") && line.contains("\"seed\":\"<redacted>\"") && line.contains("\"privateKey\":\"<redacted>\""))
        #expect(line.contains("\"bytes\":\"<32 bytes>\"") && line.contains("\"typed\":\"<32 bytes>\"") && line.contains("\"asObject\":\"<32 bytes>\""))
        #expect(!line.contains("93") && !line.contains("1786ff8a-2dd8"))
    }

    // MARK: G01, G05: the shielded wallet file

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("signet-audit-\(UUID().uuidString)", isDirectory: true)
    }

    @Test func shieldedWalletFileIsNeverWrittenLargerThanItIsRead() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let account = Address("tz1VSUr8wwNhLAzempoch5d6hLRiTh8Cjcjb")
        let store = FileShieldedWalletStore(directory: directory, chain: "test", maxBytes: 4096)
        var wallet = ShieldedWallet.make(chain: "test")
        try store.save(wallet, account: account)
        let before = try #require(try PrivateFile.read(directory.appendingPathComponent(FileShieldedWalletStore.walletFile(chain: "test"))))
        wallet.leafCms = (0..<200).map { _ in String(repeating: "ab", count: 32) }
        #expect(throws: ShieldedError.self) { try store.save(wallet, account: account) }
        let after = try #require(try PrivateFile.read(directory.appendingPathComponent(FileShieldedWalletStore.walletFile(chain: "test"))))
        #expect(before == after)
        #expect(try store.load(account: account)?.leafCms.isEmpty == true)
        // A file beyond the bound on disk is refused on reading rather than parsed.
        try PrivateFile.write(Data(repeating: 0x20, count: 5000), to: directory.appendingPathComponent(FileShieldedWalletStore.walletFile(chain: "test")))
        #expect(throws: (any Error).self) { try store.load(account: account) }
    }

    @Test func shieldedWalletFileIsLockedAgainstOtherProcesses() async throws {
        let python = URL(fileURLWithPath: "/usr/bin/python3")
        guard FileManager.default.isExecutableFile(atPath: python.path) else { return }
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let account = Address("tz1VSUr8wwNhLAzempoch5d6hLRiTh8Cjcjb")
        let store = FileShieldedWalletStore(directory: directory, chain: "test", lockTimeout: 0.3)
        try store.save(ShieldedWallet.make(chain: "test"), account: account)
        let lockPath = directory.appendingPathComponent(FileShieldedWalletStore.lockFile(chain: "test")).path
        #expect(FileManager.default.fileExists(atPath: lockPath))
        // Another process takes the same lock for a while.
        let holder = Process()
        holder.executableURL = python
        holder.arguments = ["-I", "-c", "import fcntl, os, sys, time\nfd = os.open(sys.argv[1], os.O_RDWR)\nfcntl.lockf(fd, fcntl.LOCK_EX)\nprint('held', flush=True)\ntime.sleep(2)\n", lockPath]
        let output = Pipe()
        holder.standardOutput = output
        try holder.run()
        defer { if holder.isRunning { holder.terminate() }; holder.waitUntilExit() }
        let line = output.fileHandleForReading.readLine()
        #expect(line == "held")
        #expect(throws: ShieldedError.self) { _ = try store.update(account: account, initial: nil) { $0.depositNonce += 1 } }
        holder.waitUntilExit()
        let updated = try #require(try store.update(account: account, initial: nil) { $0.depositNonce += 1 })
        #expect(updated.depositNonce == 1)
    }

    @Test func shieldedWalletFileLockIsSharedAcrossPathAliases() throws {
        // A real parent directory and a symlink to it both lead to the same wallet file; two
        // stores, one through each, must take the same lock (lockf alone is per process).
        let parent = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: parent) }
        let real = parent.appendingPathComponent("real", isDirectory: true)
        try FileManager.default.createDirectory(at: real.appendingPathComponent("wallet"), withIntermediateDirectories: true)
        let alias = parent.appendingPathComponent("alias")
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: real)
        let account = Address("tz1VSUr8wwNhLAzempoch5d6hLRiTh8Cjcjb")
        let a = FileShieldedWalletStore(directory: real.appendingPathComponent("wallet"), chain: "test")
        let b = FileShieldedWalletStore(directory: alias.appendingPathComponent("wallet"), chain: "test")
        try a.save(ShieldedWallet.make(chain: "test"), account: account)
        let group = DispatchGroup()
        for store in [a, b] {
            group.enter()
            DispatchQueue.global().async {
                for _ in 0..<40 { _ = try? store.update(account: account, initial: nil) { $0.depositNonce += 1 } }
                group.leave()
            }
        }
        group.wait()
        #expect(try a.load(account: account)?.depositNonce == 80 && b.load(account: account)?.depositNonce == 80)
    }

    @Test func backupsReadEveryWalletFileTheStoreAccepts() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let wallet = root.appendingPathComponent("wallet", isDirectory: true), backups = root.appendingPathComponent("backups", isDirectory: true)
        try FileManager.default.createDirectory(at: wallet, withIntermediateDirectories: true)
        try PrivateFile.write(Data("[]".utf8), to: wallet.appendingPathComponent("public_key_hashs"))
        // A shielded wallet file larger than the ordinary 32 MB bound, as a long scan leaves it.
        let name = FileShieldedWalletStore.walletFile(chain: Network.shadownet.chain)
        var big = Data("{\"version\":2,\"chain\":\"x\",\"pad\":\"".utf8)
        big.append(Data(repeating: 0x61, count: 40 << 20))
        big.append(Data("\"}".utf8))
        try PrivateFile.write(big, to: wallet.appendingPathComponent(name))
        #expect(PrivateFile.readLimit(for: name) == PrivateFile.largeStateBytes && PrivateFile.readLimit(for: "secret_keys") == PrivateFile.maxBytes)
        #expect(throws: (any Error).self) { try PrivateFile.read(wallet.appendingPathComponent(name)) }
        let outcome = try WalletBackup(walletDirectory: wallet, backupDirectory: backups, generations: 2).run()
        guard case .created(let generation) = outcome else { Issue.record("expected a generation, got \(outcome)"); return }
        let saved = try #require(try PrivateFile.read(generation.appendingPathComponent(name), limit: PrivateFile.largeStateBytes))
        #expect(saved == big)
        #expect(try WalletBackup.fingerprint(of: wallet) == WalletBackup.fingerprint(of: generation))
    }

    // MARK: G08: untrusted rollup numbers

    @Test func rollupLevelsOutOfRangeAreErrorsNotTraps() async throws {
        #expect(RollupState.level(-1) == nil && RollupState.level(Int(Int32.max) + 1) == nil && RollupState.level(5) == 5)
        let rollup = MockShieldedRollup()
        for level in [Int.max, Int.max - 1, Int(Int32.max), -1] {
            await #expect(throws: ShieldedError.self) { _ = try await rollup.requiredTxFee(at: RollupHead(hash: "x", level: level)) }
        }
        rollup.level = 100
        #expect(try await rollup.requiredTxFee(at: rollup.head()) == RollupState.requiredTxFee(privateTxsInLevel: 0))
    }

    // MARK: T01: shielded records before and after the operator

    @Test func olderRecordsReadAsAcknowledgedAndNewOnesKeepTheirPayload() throws {
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        let old = """
        {"submissionID":"sub-1","recipient":"tz1a","amountMutez":"10","rollupFeeMutez":"1","producerFeeMutez":"1","nullifiers":["n1"],"changeCm":null,"submittedLevel":7,"created":"2026-11-01T00:00:00Z","operationHash":null,"applied":false,"outboxLevel":null,"messageIndex":null,"executedHash":null}
        """
        let withdrawal = try decoder.decode(ShieldedWithdrawal.self, from: Data(old.utf8))
        #expect(withdrawal.submitted && withdrawal.payloadHex == nil && withdrawal.id == "sub-1")
        let oldTransfer = """
        {"submissionID":"sub-2","recipientFingerprint":"fp","recipientName":null,"amountMutez":"10","rollupFeeMutez":"1","producerFeeMutez":"1","memo":"","nullifiers":["n2"],"recipientCm":"c1","changeCm":"c2","created":"2026-11-01T00:00:00Z","operationHash":null,"applied":false}
        """
        let transfer = try decoder.decode(ShieldedTransfer.self, from: Data(oldTransfer.utf8))
        #expect(transfer.submitted && transfer.payloadHex == nil)
        var fresh = ShieldedWithdrawal(submissionID: ShieldedWithdrawal.localID(), recipient: "tz1a", amountMutez: "10", rollupFeeMutez: "1", producerFeeMutez: "1", nullifiers: ["n1"], changeCm: nil, submittedLevel: 7, created: Date(), payloadHex: "0102", submitted: false)
        #expect(fresh.id.hasPrefix("local:"))
        let round = try decoder.decode(ShieldedWithdrawal.self, from: try encoder.encode(fresh))
        #expect(round.payloadHex == "0102" && !round.submitted && round.id == fresh.id)
        fresh.submissionID = "sub-3"; fresh.submitted = true
        #expect(fresh.id == "sub-3")
        // An unacknowledged withdrawal reserves its notes and says so.
        var wallet = ShieldedWallet.make(chain: "test")
        wallet.notes = [ShieldedNote(index: 0, cm: "c", rseed: "r", nullifier: "n1", valueMutez: "10", addressIndex: 0)]
        wallet.withdrawals = [round]
        #expect(wallet.availableNotes.isEmpty && wallet.reservedMutez == 10)
        #expect(ShieldedWithdrawalStatus(withdrawal: round, cementedLevel: nil).state == .unconfirmed)
    }

    @Test func submittingKeepsTheRecordUnlessTheOperatorRefusedIt() async throws {
        final class Dropped: @unchecked Sendable { var count = 0 }
        let dropped = Dropped()
        let submission = OperatorSubmission(id: "s1", status: "queued", transport: nil, operationHash: nil, detail: nil)
        let ok = try await WalletViewModel.submitShielded(record: "local:abc", drop: { dropped.count += 1 }) { submission }
        #expect(ok.id == "s1" && dropped.count == 0)
        // Refusals the operator made itself: the record goes.
        for refusal in [ShieldedError.operatorRefused("token"), ShieldedError.rejected(status: 400, "bad payload")] {
            await #expect(throws: ShieldedError.self) { _ = try await WalletViewModel.submitShielded(record: "local:abc", drop: { dropped.count += 1 }) { throw refusal } }
        }
        #expect(dropped.count == 2)
        // A lost reply, a timeout or a bad answer: the record stays and the error says so.
        for unknown in [URLError(.timedOut) as any Error, ShieldedError.badReply("HTTP 502"), CancellationError()] {
            do {
                _ = try await WalletViewModel.submitShielded(record: "local:abcdef0123", drop: { dropped.count += 1 }) { throw unknown }
                Issue.record("should have thrown")
            } catch ShieldedError.submissionPending(let detail) {
                #expect(detail.contains("abcdef01…") && detail.contains("reserved"))
            }
        }
        #expect(dropped.count == 2)
    }

    @MainActor @Test func unacknowledgedRecordsCanBeHandedToTheOperatorAgain() async throws {
        let store = InMemoryShieldedWalletStore()
        let rollup = MockShieldedRollup()
        let keys = InMemoryWalletStore()
        try keys.add(WalletViewModel.sampleWallets[0], secretKey: "edskSAMPLE")
        let model = WalletViewModel(wallets: WalletViewModel.sampleWallets, chain: MockChainService(), walletStore: keys, shieldedStoreFactory: { _, _ in store }, shieldedRollupFactory: { _ in rollup })
        model.setShieldedEnabled(true, for: .shadownet)
        model.switchNetwork(to: .shadownet)
        try model.setShieldedOperatorToken("operator-secret", for: .shadownet)
        let me = WalletViewModel.sampleWallets[0].address
        var wallet = ShieldedWallet.make(chain: Network.shadownet.chain)
        wallet.notes = [ShieldedNote(index: 0, cm: "c", rseed: "r", nullifier: "n1", valueMutez: "10", addressIndex: 0), ShieldedNote(index: 1, cm: "d", rseed: "r", nullifier: "n2", valueMutez: "10", addressIndex: 0)]
        let withdrawalID = ShieldedWithdrawal.localID(), transferID = ShieldedWithdrawal.localID()
        wallet.withdrawals = [ShieldedWithdrawal(submissionID: withdrawalID, recipient: me.value, amountMutez: "5", rollupFeeMutez: "1", producerFeeMutez: "1", nullifiers: ["n1"], changeCm: nil, submittedLevel: 7, created: Date(), payloadHex: "aa01", submitted: false)]
        wallet.transfers = [ShieldedTransfer(submissionID: transferID, recipientFingerprint: "fp", recipientName: nil, amountMutez: "5", rollupFeeMutez: "1", producerFeeMutez: "1", memo: "", nullifiers: ["n2"], recipientCm: "c1", changeCm: "c2", created: Date(), payloadHex: "bb02", submitted: false)]
        try store.save(wallet, account: me)
        #expect(try store.load(account: me)?.availableNotes.isEmpty == true)
        // The kept payloads go out as they were; the records take the operator's ids.
        try await model.resubmitWithdrawal(withdrawalID)
        try await model.resubmitTransfer(transferID)
        let after = try #require(try store.load(account: me))
        #expect(rollup.submitted.map { ($0.kind, $0.payload) }.elementsEqual([("unshield", "aa01"), ("transfer", "bb02")], by: ==))
        #expect(after.withdrawals.map(\.id) == ["sub-1"] && after.withdrawals[0].submitted && after.transfers.map(\.id) == ["sub-2"] && after.transfers[0].submitted)
        #expect(after.availableNotes.isEmpty, "still reserved until the rollup applies them")
        // Acknowledged records are not sent twice.
        await #expect(throws: ShieldedError.self) { try await model.resubmitWithdrawal("sub-1") }
    }

    @MainActor @Test func refusedRetriesPreserveEarlierUncertainSubmissions() async throws {
        let store = InMemoryShieldedWalletStore()
        let rollup = MockShieldedRollup()
        let keys = InMemoryWalletStore()
        try keys.add(WalletViewModel.sampleWallets[0], secretKey: "edskSAMPLE")
        let model = WalletViewModel(wallets: WalletViewModel.sampleWallets, chain: MockChainService(), walletStore: keys, shieldedStoreFactory: { _, _ in store }, shieldedRollupFactory: { _ in rollup })
        model.setShieldedEnabled(true, for: .shadownet)
        model.switchNetwork(to: .shadownet)
        try model.setShieldedOperatorToken("operator-secret", for: .shadownet)
        let me = WalletViewModel.sampleWallets[0].address
        var wallet = ShieldedWallet.make(chain: Network.shadownet.chain)
        wallet.notes = [ShieldedNote(index: 0, cm: "c", rseed: "r", nullifier: "n1", valueMutez: "10", addressIndex: 0), ShieldedNote(index: 1, cm: "d", rseed: "r", nullifier: "n2", valueMutez: "10", addressIndex: 0)]
        let withdrawalID = ShieldedWithdrawal.localID(), transferID = ShieldedWithdrawal.localID()
        wallet.withdrawals = [ShieldedWithdrawal(submissionID: withdrawalID, recipient: me.value, amountMutez: "5", rollupFeeMutez: "1", producerFeeMutez: "1", nullifiers: ["n1"], changeCm: nil, submittedLevel: 7, created: Date(), payloadHex: "aa01", submitted: false)]
        wallet.transfers = [ShieldedTransfer(submissionID: transferID, recipientFingerprint: "fp", recipientName: nil, amountMutez: "5", rollupFeeMutez: "1", producerFeeMutez: "1", memo: "", nullifiers: ["n2"], recipientCm: "c1", changeCm: "c2", created: Date(), payloadHex: "bb02", submitted: false)]
        try store.save(wallet, account: me)

        // Both first attempts are accepted by the operator, but their replies are lost.
        for (kind, payload, id) in [("unshield", "aa01", withdrawalID), ("transfer", "bb02", transferID)] {
            do {
                _ = try await WalletViewModel.submitShielded(record: id, drop: {
                    _ = try store.update(account: me, initial: nil) {
                        $0.withdrawals.removeAll { $0.id == id }
                        $0.transfers.removeAll { $0.id == id }
                    }
                }) {
                    _ = try await rollup.submit(kind: kind, payloadHex: payload, rollupAddress: "synthetic-rollup", token: "operator-secret")
                    throw URLError(.timedOut)
                }
                Issue.record("expected an uncertain submission")
            } catch ShieldedError.submissionPending { }
        }
        #expect(rollup.submitted.count == 2)

        // A new authentication failure cannot resolve either earlier attempt.
        try model.setShieldedOperatorToken("wrong", for: .shadownet)
        for id in [withdrawalID, transferID] {
            do {
                if id == withdrawalID { try await model.resubmitWithdrawal(id) }
                else { try await model.resubmitTransfer(id) }
                Issue.record("expected a refused retry")
            } catch ShieldedError.submissionPending(let detail) {
                #expect(detail.contains("reserved"))
            }
        }
        let pending = try #require(try store.load(account: me))
        #expect(pending.withdrawals.map(\.id) == [withdrawalID] && pending.withdrawals[0].payloadHex == "aa01" && !pending.withdrawals[0].submitted)
        #expect(pending.transfers.map(\.id) == [transferID] && pending.transfers[0].payloadHex == "bb02" && !pending.transfers[0].submitted)
        #expect(pending.reservedNullifiers == Set(["n1", "n2"]) && pending.availableNotes.isEmpty && pending.reservedMutez == 20)
        #expect(rollup.submitted.count == 2)

        // Correcting the token still permits replay of the same payloads, keeping reservations.
        try model.setShieldedOperatorToken("operator-secret", for: .shadownet)
        try await model.resubmitWithdrawal(withdrawalID)
        try await model.resubmitTransfer(transferID)
        let acknowledged = try #require(try store.load(account: me))
        #expect(acknowledged.withdrawals.map(\.id) == ["sub-3"] && acknowledged.withdrawals[0].submitted)
        #expect(acknowledged.transfers.map(\.id) == ["sub-4"] && acknowledged.transfers[0].submitted)
        #expect(acknowledged.availableNotes.isEmpty)
        #expect(rollup.submitted.map { ($0.kind, $0.payload) }.elementsEqual([("unshield", "aa01"), ("transfer", "bb02"), ("unshield", "aa01"), ("transfer", "bb02")], by: ==))
    }

    @Test func retryRefusalsRemainUncertain() async throws {
        for refusal in [ShieldedError.operatorRefused("expired token"), ShieldedError.rejected(status: 400, "bad request"), ShieldedError.rejected(status: 403, "forbidden"), ShieldedError.rejected(status: 422, "invalid payload")] {
            do {
                _ = try await WalletViewModel.submitShielded(record: "local:abcdef0123") { throw refusal }
                Issue.record("expected an uncertain submission")
            } catch ShieldedError.submissionPending(let detail) {
                #expect(detail.contains("abcdef01…") && detail.contains("reserved"))
            }
        }
    }

    @Test func onlyDefiniteClientErrorsCountAsRejections() {
        for status in [400, 401, 403, 404, 413, 422] { #expect(RollupNodeService.isRejection(status), Comment(rawValue: "\(status)")) }
        for status in [408, 409, 425, 429, 500, 502, 503, 504, 200] { #expect(!RollupNodeService.isRejection(status), Comment(rawValue: "\(status)")) }
    }

    // MARK: G04

    @Test func plainHTTPServicesAreNamed() {
        #expect(ShieldSettingsSheet.plainHTTP("https://operator.example", "https://rollup.example") == nil)
        #expect(ShieldSettingsSheet.plainHTTP("http://operator.example:8787", "https://rollup.example")?.hasPrefix("The operator is reached over plain HTTP") == true)
        #expect(ShieldSettingsSheet.plainHTTP("HTTP://operator.example", "http://rollup.example")?.hasPrefix("The operator and rollup node are reached") == true)
        #expect(ShieldSettingsSheet.plainHTTP("", "") == nil)
    }
}

private extension FileHandle {
    /// One line of text, without its newline, read byte by byte so the pipe is not drained.
    func readLine() -> String {
        var bytes: [UInt8] = []
        while let data = try? read(upToCount: 1), let byte = data.first, byte != UInt8(ascii: "\n") { bytes.append(byte) }
        return String(decoding: bytes, as: UTF8.self)
    }
}
