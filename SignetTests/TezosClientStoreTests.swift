import Foundation
import Testing
@testable import Signet

struct TezosClientStoreTests {
    private func makeDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("signet-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func writeFixture(in directory: URL) throws {
        let hashes = """
        [ { "name": "alice", "value": "tz1VSUr8wwNhLAzempoch5d6hLRiTh8Cjcjb" },
          { "name": "bob",   "value": "tz2BFTyPeYRzxd5aiBchbXN3WCZhx7BqbMBq" },
          { "name": "pq",    "value": "tz5c9dMrWKhwBbSUPhxQRdwUnMMYHfqnpQRD" },
          { "name": "watch", "value": "tz3WXYtyDUNL91qfiCJtVUX746QpNv5i5ve5" } ]
        """
        // Mixed public_keys formats: current object form, legacy string form, and one missing.
        let publicKeys = """
        [ { "name": "bob",   "value": "unencrypted:sppkBOB" },
          { "name": "alice", "value": { "locator": "unencrypted:edpkALICE", "key": "edpkALICE" } },
          { "name": "pq",    "value": { "locator": "unencrypted:mdpkPQ", "key": "mdpkPQ" } } ]
        """
        let secretKeys = """
        [ { "name": "alice", "value": "unencrypted:edskALICE" },
          { "name": "bob",   "value": "encrypted:edeskBOB" },
          { "name": "pq",    "value": "ledger://thing/ed25519/0h/0h" } ]
        """
        try hashes.write(to: directory.appendingPathComponent("public_key_hashs"), atomically: true, encoding: .utf8)
        try publicKeys.write(to: directory.appendingPathComponent("public_keys"), atomically: true, encoding: .utf8)
        try secretKeys.write(to: directory.appendingPathComponent("secret_keys"), atomically: true, encoding: .utf8)
    }

    @Test func loadsAliasesJoinedByName() throws {
        let dir = try makeDirectory()
        try writeFixture(in: dir)
        let store = TezosClientStore(directory: dir)
        #expect(store.hasWallets)

        let wallets = try store.load()
        #expect(wallets.map(\.alias) == ["alice", "bob", "pq", "watch"])

        let alice = wallets[0]
        #expect(alice.scheme == .tz1)
        #expect(alice.publicKey == "edpkALICE")
        #expect(alice.keyKind == .unencrypted)

        let bob = wallets[1]
        #expect(bob.scheme == .tz2)
        #expect(bob.publicKey == "sppkBOB")   // legacy string form
        #expect(bob.keyKind == .encrypted)

        let pq = wallets[2]
        #expect(pq.scheme == .tz5)
        #expect(pq.keyKind == .ledger)

        let watch = wallets[3]
        #expect(watch.publicKey == nil)
        #expect(watch.keyKind == KeyKind.none)
    }

    @Test func secretKeyForClearAndEncryptedEntriesOnly() throws {
        let dir = try makeDirectory()
        try writeFixture(in: dir)
        let store = TezosClientStore(directory: dir)
        let wallets = try store.load()
        #expect(try store.secretKey(for: wallets[0]) == "edskALICE")
        // Encrypted keys come back too (the caller supplies the password); ledger and watch-only do not.
        #expect(try store.secretKey(for: wallets[1]) == "edeskBOB")
        #expect(try store.secretKey(for: wallets[2]) == nil)
        #expect(try store.secretKey(for: wallets[3]) == nil)
    }

    /// S06/S07: a `Wallet` held by a sheet may be stale. The alias alone must never pick a key or
    /// choose what to delete; the address on disk has to agree.
    @Test func secretKeyAndRemoveRefuseAnAliasWhoseAddressChanged() throws {
        let dir = try makeDirectory()
        try writeFixture(in: dir)
        let store = TezosClientStore(directory: dir)
        let alice = try store.load()[0]
        let impostor = Wallet(alias: "alice", address: Address("tz1KqTpEZ7Yob7QbPE4Hy4Wo8fHG8LhKxZSx"), keyKind: .unencrypted)

        #expect(throws: TezosClientStore.StoreError.self) { try store.secretKey(for: impostor) }
        #expect(throws: TezosClientStore.StoreError.self) { try store.remove(impostor) }
        #expect(try store.load().map(\.alias) == ["alice", "bob", "pq", "watch"])
        #expect(try store.secretKey(for: alice) == "edskALICE")

        try store.remove(alice)
        #expect(try store.load().map(\.alias) == ["bob", "pq", "watch"])
        #expect(try store.secretKey(for: alice) == nil)
    }

    @Test(arguments: ["public_key_hashs", "public_keys", "secret_keys"])
    func removalRejectsChangedAccountEntriesWithoutWriting(file: String) throws {
        let dir = try makeDirectory()
        try writeFixture(in: dir)
        let store = TezosClientStore(directory: dir)
        let alice = try store.load()[0]
        let snapshot = try store.removalSnapshot(for: alice)
        let url = dir.appendingPathComponent(file)
        var rows = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [[String: Any]])
        let index = try #require(rows.firstIndex { $0["name"] as? String == "alice" })
        switch file {
        case "public_key_hashs": rows[index]["value"] = "tz1REPLACEMENT"
        case "public_keys": rows[index]["value"] = ["locator": "unencrypted:CHANGED", "key": "edpkALICE"]
        default: rows[index]["value"] = "unencrypted:edskREPLACEMENT"
        }
        try JSONSerialization.data(withJSONObject: rows).write(to: url)
        let before = try TezosClientStore.walletFiles.map { try Data(contentsOf: dir.appendingPathComponent($0)) }
        #expect(throws: TezosClientStore.StoreError.self) { try store.remove(alice, matching: snapshot) }
        let after = try TezosClientStore.walletFiles.map { try Data(contentsOf: dir.appendingPathComponent($0)) }
        #expect(before == after)
    }

    @Test func removalRejectsReplacementDirectoryAtTheSamePath() throws {
        let dir = try makeDirectory()
        try writeFixture(in: dir)
        let store = TezosClientStore(directory: dir)
        let alice = try store.load()[0]
        let snapshot = try store.removalSnapshot(for: alice)
        let moved = dir.appendingPathExtension("original")
        try FileManager.default.moveItem(at: dir, to: moved)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try writeFixture(in: dir)
        #expect(throws: TezosClientStore.StoreError.self) { try store.remove(alice, matching: snapshot) }
        #expect(try store.load().count == 4)
        #expect(try TezosClientStore(directory: moved).load().count == 4)
    }

    @Test func removalSnapshotAllowsUnchangedAccountAndUnrelatedEdits() throws {
        let dir = try makeDirectory()
        try writeFixture(in: dir)
        let store = TezosClientStore(directory: dir)
        let alice = try store.load()[0]
        let snapshot = try store.removalSnapshot(for: alice)
        #expect(snapshot.secretKey == "edskALICE")
        try store.rename(alias: "bob", to: "renamed-bob")
        try store.remove(alice, matching: snapshot)
        #expect(try store.load().map(\.alias) == ["renamed-bob", "pq", "watch"])
    }

    @Test func removalRejectsNewSecretForPreviouslyWatchOnlyAccount() throws {
        let dir = try makeDirectory()
        try writeFixture(in: dir)
        let store = TezosClientStore(directory: dir)
        let watch = try #require(store.load().first { $0.alias == "watch" })
        let snapshot = try store.removalSnapshot(for: watch)
        #expect(snapshot.secretKey == nil)
        let url = dir.appendingPathComponent("secret_keys")
        var rows = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [[String: Any]])
        rows.append(["name": "watch", "value": "encrypted:edeskNEW"])
        try JSONSerialization.data(withJSONObject: rows).write(to: url)
        #expect(throws: TezosClientStore.StoreError.self) { try store.remove(watch, matching: snapshot) }
        #expect(try store.load().count == 4)
    }

    @Test func inMemoryRemovalRejectsChangedKeyAndAnotherStore() throws {
        let wallet = Wallet(alias: "shared", address: Address("tz1SYNTHETIC"), publicKey: "edpkSYNTHETIC", keyKind: .encrypted)
        let store = InMemoryWalletStore()
        try store.add(wallet, locator: "encrypted:edeskOLD")
        let snapshot = try store.removalSnapshot(for: wallet)
        try store.remove(wallet)
        try store.add(wallet, locator: "encrypted:edeskNEW")
        #expect(throws: InMemoryWalletStore.StoreError.self) { try store.remove(wallet, matching: snapshot) }
        let other = InMemoryWalletStore()
        try other.add(wallet, locator: "encrypted:edeskOLD")
        #expect(throws: InMemoryWalletStore.StoreError.self) { try other.remove(wallet, matching: snapshot) }
        #expect(try store.load().count == 1)
        #expect(try other.load().count == 1)
    }

    @Test func addAppendsInOctezFormatAndKeepsExistingEntries() throws {
        let dir = try makeDirectory()
        try writeFixture(in: dir)
        let store = TezosClientStore(directory: dir)

        let wallet = Wallet(alias: "new one", address: Address("tz3WXYtyDUNL91qfiCJtVUX746QpNv5i5ve5"),
                            scheme: .tz3, publicKey: "p2pkNEW", keyKind: .unencrypted)
        try store.add(wallet, secretKey: "p2skNEW")

        let reloaded = try store.load()
        #expect(reloaded.map(\.alias) == ["alice", "bob", "pq", "watch", "new one"])
        #expect(reloaded.last?.publicKey == "p2pkNEW")
        #expect(reloaded.last?.keyKind == .unencrypted)
        #expect(try store.secretKey(for: wallet) == "p2skNEW")
        // Existing entries survive untouched.
        #expect(try store.secretKey(for: reloaded[0]) == "edskALICE")

        // The public_keys entry uses the current {locator, key} object form.
        let data = try Data(contentsOf: dir.appendingPathComponent("public_keys"))
        let entries = try #require(try JSONSerialization.jsonObject(with: data) as? [[String: Any]])
        let value = try #require(entries.last?["value"] as? [String: Any])
        #expect(value["locator"] as? String == "unencrypted:p2pkNEW")
        #expect(value["key"] as? String == "p2pkNEW")

        // Secret file is private.
        let attrs = try FileManager.default.attributesOfItem(atPath: dir.appendingPathComponent("secret_keys").path)
        #expect((attrs[.posixPermissions] as? Int) == 0o600)
    }

    @Test func addRefusesDuplicateAlias() throws {
        let dir = try makeDirectory()
        try writeFixture(in: dir)
        let store = TezosClientStore(directory: dir)
        let dup = Wallet(alias: "alice", address: Address("tz1VSUr8wwNhLAzempoch5d6hLRiTh8Cjcjb"), publicKey: "edpkX")
        #expect(throws: TezosClientStore.StoreError.self) {
            try store.add(dup, secretKey: "edskX")
        }
    }

    @Test func createsDirectoryAndFilesWhenMissing() throws {
        let dir = try makeDirectory().appendingPathComponent("fresh", isDirectory: true)
        let store = TezosClientStore(directory: dir)
        #expect(!store.hasWallets)
        #expect(try store.load().isEmpty)

        let wallet = Wallet(alias: "My Wallet", address: Address("tz1VSUr8wwNhLAzempoch5d6hLRiTh8Cjcjb"), publicKey: "edpkX", keyKind: .unencrypted)
        try store.add(wallet, secretKey: "edskX")
        #expect(store.hasWallets)
        #expect(try store.load() == [wallet])
    }
}

struct TezosClientStoreRenameTests {
    private func makeStore() throws -> TezosClientStore {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("signet-rename-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try """
        [ { "name": "alice", "value": "tz1VSUr8wwNhLAzempoch5d6hLRiTh8Cjcjb" },
          { "name": "watch", "value": "tz3WXYtyDUNL91qfiCJtVUX746QpNv5i5ve5" } ]
        """.write(to: dir.appendingPathComponent("public_key_hashs"), atomically: true, encoding: .utf8)
        try """
        [ { "name": "alice", "value": { "locator": "unencrypted:edpkALICE", "key": "edpkALICE" } } ]
        """.write(to: dir.appendingPathComponent("public_keys"), atomically: true, encoding: .utf8)
        try """
        [ { "name": "alice", "value": "unencrypted:edskALICE" } ]
        """.write(to: dir.appendingPathComponent("secret_keys"), atomically: true, encoding: .utf8)
        return TezosClientStore(directory: dir)
    }

    @Test func renamesAliasInAllThreeFiles() throws {
        let store = try makeStore()
        try store.rename(alias: "alice", to: "alice-main")

        let wallets = try store.load()
        #expect(wallets.map(\.alias) == ["alice-main", "watch"])
        let renamed = wallets[0]
        #expect(renamed.publicKey == "edpkALICE")
        #expect(renamed.keyKind == .unencrypted)
        #expect(try store.secretKey(for: renamed) == "edskALICE")
        #expect(try store.secretKey(for: Wallet(alias: "alice", address: renamed.address)) == nil)
    }

    @Test func renamesWatchOnlyAliasPresentInOneFile() throws {
        let store = try makeStore()
        try store.rename(alias: "watch", to: "observer")
        #expect(try store.load().map(\.alias) == ["alice", "observer"])
    }

    @Test func refusesTakenOrUnknownAliases() throws {
        let store = try makeStore()
        #expect(throws: TezosClientStore.StoreError.self) { try store.rename(alias: "alice", to: "watch") }
        #expect(throws: TezosClientStore.StoreError.self) { try store.rename(alias: "nobody", to: "x") }
        #expect(try store.load().map(\.alias) == ["alice", "watch"])
    }
}

struct TezosClientStoreImportTests {
    private func tempDir(_ label: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("signet-\(label)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func writeOctez(in dir: URL) throws {
        try """
        [ { "name": "alice", "value": "tz1VSUr8wwNhLAzempoch5d6hLRiTh8Cjcjb" },
          { "name": "bob",   "value": "tz2BFTyPeYRzxd5aiBchbXN3WCZhx7BqbMBq" } ]
        """.write(to: dir.appendingPathComponent("public_key_hashs"), atomically: true, encoding: .utf8)
        try """
        [ { "name": "alice", "value": { "locator": "unencrypted:edpkALICE", "key": "edpkALICE" } } ]
        """.write(to: dir.appendingPathComponent("public_keys"), atomically: true, encoding: .utf8)
        try """
        [ { "name": "alice", "value": "unencrypted:edskALICE" } ]
        """.write(to: dir.appendingPathComponent("secret_keys"), atomically: true, encoding: .utf8)
    }

    @Test func coldStartImportCopiesFilesExactly() throws {
        let octez = try tempDir("octez")
        try writeOctez(in: octez)
        let signet = try tempDir("signet").appendingPathComponent("fresh", isDirectory: true)
        let store = TezosClientStore(directory: signet)

        let added = try store.importWallets(from: octez)

        #expect(added == 2)
        #expect(try store.load().map(\.alias) == ["alice", "bob"])
        for file in TezosClientStore.walletFiles {
            let a = try Data(contentsOf: octez.appendingPathComponent(file))
            let b = try Data(contentsOf: signet.appendingPathComponent(file))
            #expect(a == b, "\(file) should be a byte-for-byte copy")
            let attrs = try FileManager.default.attributesOfItem(atPath: signet.appendingPathComponent(file).path)
            #expect((attrs[.posixPermissions] as? Int) == 0o600)
        }
        // The source is untouched.
        #expect(try TezosClientStore(directory: octez).load().count == 2)
    }

    @Test func laterImportMergesOnlyNewAliases() throws {
        let octez = try tempDir("octez")
        try writeOctez(in: octez)
        let signet = try tempDir("signet")
        let store = TezosClientStore(directory: signet)
        let mine = Wallet(alias: "alice", address: Address("tz3WXYtyDUNL91qfiCJtVUX746QpNv5i5ve5"), publicKey: "p2pkMINE", keyKind: .unencrypted)
        try store.add(mine, secretKey: "p2skMINE")

        let added = try store.importWallets(from: octez)

        #expect(added == 1)
        let wallets = try store.load()
        #expect(wallets.map(\.alias) == ["alice", "bob"])
        // My own "alice" wins; octez's "alice" was skipped.
        #expect(wallets[0].publicKey == "p2pkMINE")
        #expect(try store.secretKey(for: wallets[0]) == "p2skMINE")
        #expect(wallets[1].scheme == .tz2)
    }

    @Test func importWithNoSourceIsANoOp() throws {
        let signet = try tempDir("signet")
        let store = TezosClientStore(directory: signet)
        #expect(try store.importWallets(from: signet.appendingPathComponent("missing")) == 0)
        #expect(!store.hasWallets)
    }
}

@MainActor
struct ImportViewModelTests {
    @Test func offersImportOnColdStartAndClearsItAfterwards() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("signet-vm-\(UUID().uuidString)", isDirectory: true)
        let octez = base.appendingPathComponent("tezos-client", isDirectory: true)
        try FileManager.default.createDirectory(at: octez, withIntermediateDirectories: true)
        try """
        [ { "name": "alice", "value": "tz1VSUr8wwNhLAzempoch5d6hLRiTh8Cjcjb" } ]
        """.write(to: octez.appendingPathComponent("public_key_hashs"), atomically: true, encoding: .utf8)

        let model = WalletViewModel(chain: MockChainService(),
                                    walletStore: TezosClientStore(directory: base.appendingPathComponent("signet")),
                                    importSource: octez)
        #expect(model.wallets.isEmpty)
        #expect(model.importableWalletCount == 1)

        #expect(try model.importFromOctezClient() == 1)
        #expect(model.selectedWallet?.alias == "alice")
        #expect(model.importableWalletCount == 0)
    }

    @Test func noOfferWithoutASource() {
        let model = WalletViewModel(chain: MockChainService())
        #expect(model.importableWalletCount == 0)
    }
}

struct FileAppStateStoreTests {
    @Test func roundTripsThroughTheStateFile() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("signet-state-\(UUID().uuidString)", isDirectory: true)
        let store = FileAppStateStore(directory: dir)
        #expect(store.load() == AppState())

        try store.save(AppState(selectedWalletAlias: "pq", networkName: "Shadownet"))
        #expect(FileAppStateStore(directory: dir).load() == AppState(selectedWalletAlias: "pq", networkName: "Shadownet"))

        let attrs = try FileManager.default.attributesOfItem(atPath: dir.appendingPathComponent("state").path)
        #expect((attrs[.posixPermissions] as? Int) == 0o600)
    }

    @MainActor
    @Test func modelRestoresSelectionFromTheStateFile() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("signet-state-\(UUID().uuidString)", isDirectory: true)
        let wallets = TezosClientStore(directory: dir)
        try wallets.add(Wallet(alias: "first", address: Address("tz1VSUr8wwNhLAzempoch5d6hLRiTh8Cjcjb"), publicKey: "edpkA", keyKind: .unencrypted), secretKey: "edskA")
        try wallets.add(Wallet(alias: "pq", address: Address("tz5c9dMrWKhwBbSUPhxQRdwUnMMYHfqnpQRD"), publicKey: "mdpkB", keyKind: .unencrypted), secretKey: "mdskB")
        try FileAppStateStore(directory: dir).save(AppState(selectedWalletAlias: "pq"))

        let model = WalletViewModel(chain: MockChainService(), walletStore: wallets, stateStore: FileAppStateStore(directory: dir))
        #expect(model.selectedWallet?.alias == "pq")
    }
}

/// S09 and S10: wallet changes are one unit, files are private from creation, reads are locked.
struct TezosClientStoreIntegrityTests {
    private func makeDirectory(mode: Int = 0o700) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("signet-integrity-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true, attributes: [.posixPermissions: mode])
        return url
    }

    private func mode(_ url: URL) throws -> Int {
        try #require(FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? Int) & 0o777
    }

    @Test func filesAreCreatedPrivateAndTheDirectoryIsHardened() throws {
        let dir = try makeDirectory(mode: 0o755)
        let store = TezosClientStore(directory: dir)
        try store.add(Wallet(alias: "a", address: Address("tz1VSUr8wwNhLAzempoch5d6hLRiTh8Cjcjb"), publicKey: "edpkA", keyKind: .unencrypted), secretKey: "edskA")
        #expect(try mode(dir) == 0o700)
        for file in TezosClientStore.walletFiles { #expect(try mode(dir.appendingPathComponent(file)) == 0o600) }
        // No temporary or journal is left behind.
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: dir.path).filter { $0.hasSuffix(".tmp") || $0 == TezosClientStore.journalFile }
        #expect(leftovers.isEmpty)
        // A directory someone else owns (simulated by a symlink) is refused.
        let link = FileManager.default.temporaryDirectory.appendingPathComponent("signet-link-\(UUID().uuidString)")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: dir)
        #expect(throws: PrivateFile.FileError.self) { try PrivateFile.hardenDirectory(link) }
    }

    @Test func anUnfinishedChangeIsRolledBackBeforeTheNextRead() throws {
        let dir = try makeDirectory()
        let store = TezosClientStore(directory: dir)
        try store.add(Wallet(alias: "a", address: Address("tz1VSUr8wwNhLAzempoch5d6hLRiTh8Cjcjb"), publicKey: "edpkA", keyKind: .unencrypted), secretKey: "edskA")
        let before = try TezosClientStore.walletFiles.map { try Data(contentsOf: dir.appendingPathComponent($0)) }
        // Simulate a crash after the first of three files was replaced: the journal still names
        // all three with their previous contents, and public_key_hashs already has the new alias.
        var files: [String: Any] = [:]
        for (file, data) in zip(TezosClientStore.walletFiles, before) { files[file] = data.base64EncodedString() }
        files[TezosClientStore.contractsFile] = NSNull()
        try JSONSerialization.data(withJSONObject: ["version": 1, "files": files]).write(to: dir.appendingPathComponent(TezosClientStore.journalFile))
        try #"[{"name":"a","value":"tz1VSUr8wwNhLAzempoch5d6hLRiTh8Cjcjb"},{"name":"b","value":"tz2BFTyPeYRzxd5aiBchbXN3WCZhx7BqbMBq"}]"#.write(to: dir.appendingPathComponent("public_key_hashs"), atomically: true, encoding: .utf8)
        try #"[{"name":"orphan","value":"KT1BEqzn5Wx8uJrZNvuS9DVHmLvG9td3fDLi"}]"#.write(to: dir.appendingPathComponent("contracts"), atomically: true, encoding: .utf8)
        try "junk".write(to: dir.appendingPathComponent(".secret_keys.deadbeef.tmp"), atomically: true, encoding: .utf8)

        let wallets = try store.load()
        #expect(wallets.map(\.alias) == ["a"])
        #expect(try TezosClientStore.walletFiles.map { try Data(contentsOf: dir.appendingPathComponent($0)) } == before)
        #expect(!FileManager.default.fileExists(atPath: dir.appendingPathComponent("contracts").path))
        #expect(!FileManager.default.fileExists(atPath: dir.appendingPathComponent(TezosClientStore.journalFile).path))
        #expect(!FileManager.default.fileExists(atPath: dir.appendingPathComponent(".secret_keys.deadbeef.tmp").path))
        // A journal that cannot be read is an error, never silently ignored.
        try "{".write(to: dir.appendingPathComponent(TezosClientStore.journalFile), atomically: true, encoding: .utf8)
        #expect(throws: TezosClientStore.StoreError.self) { try store.load() }
    }

    @Test func renameAndRemoveAreJournaledAsOneUnit() throws {
        let dir = try makeDirectory()
        let store = TezosClientStore(directory: dir)
        let wallet = Wallet(alias: "a", address: Address("tz1VSUr8wwNhLAzempoch5d6hLRiTh8Cjcjb"), publicKey: "edpkA", keyKind: .unencrypted)
        try store.add(wallet, secretKey: "edskA")
        try store.rename(alias: "a", to: "b")
        let renamed = try #require(try store.load().first)
        #expect(renamed.alias == "b" && renamed.publicKey == "edpkA" && renamed.keyKind == .unencrypted)
        let snapshot = try store.removalSnapshot(for: renamed)
        try store.remove(renamed, matching: snapshot)
        #expect(try store.load().isEmpty)
        for file in TezosClientStore.walletFiles {
            #expect((try JSONSerialization.jsonObject(with: Data(contentsOf: dir.appendingPathComponent(file))) as? [[String: Any]])?.isEmpty == true)
        }
        #expect(!FileManager.default.fileExists(atPath: dir.appendingPathComponent(TezosClientStore.journalFile).path))
    }

    @Test func proposalUpdatesMergeWhatIsOnDisk() throws {
        let dir = try makeDirectory()
        let one = FileMultisigProposalStore(directory: dir), two = FileMultisigProposalStore(directory: dir)
        func proposal(_ n: Int) -> MultisigProposal {
            MultisigProposal(contractAlias: "m", contractAddress: "KT1BEqzn5Wx8uJrZNvuS9DVHmLvG9td3fDLi", networkName: "Shadownet", chainID: "NetX", counter: n, threshold: 2,
                             keys: ["edpk1", "edpk2"], action: .setDelegate(delegate: nil), bytes: "05\(n)")
        }
        // Each instance holds a stale in-memory view; neither write may drop the other's proposal.
        let first = proposal(1), second = proposal(2)
        try one.update { $0.append(first) }
        try two.update { $0.append(second) }
        #expect(one.load().map(\.counter).sorted() == [1, 2])
        try one.update { stored in stored[stored.firstIndex { $0.id == first.id }!].signatures.append(MultisigSignature(publicKey: "edpk1", signature: "edsig1")) }
        try two.update { stored in stored[stored.firstIndex { $0.id == second.id }!].signatures.append(MultisigSignature(publicKey: "edpk2", signature: "edsig2")) }
        let stored = two.load()
        #expect(stored.first { $0.id == first.id }?.signatures.count == 1 && stored.first { $0.id == second.id }?.signatures.count == 1)
        #expect(try mode(dir.appendingPathComponent(FileMultisigProposalStore.fileName)) == 0o600)
        // Oversized entries another program wrote are left out (S19).
        var huge = proposal(3); huge.bytes = String(repeating: "0", count: FileMultisigProposalStore.maxBytesHex + 2)
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        try encoder.encode([first, huge]).write(to: dir.appendingPathComponent(FileMultisigProposalStore.fileName))
        #expect(one.load().map(\.counter) == [1])
    }

    @Test func aHeldLockMakesCallersWaitThenFail() throws {
        let dir = try makeDirectory()
        // The lock is advisory per process; hold it from a child process with a short timeout.
        let script = "import fcntl,time,sys\nf=open(sys.argv[1],'a+')\nfcntl.lockf(f,fcntl.LOCK_EX)\nprint('locked',flush=True)\ntime.sleep(2.5)\n"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        process.arguments = ["-c", script, dir.appendingPathComponent(TezosClientStore.lockFile).path]
        let pipe = Pipe()
        process.standardOutput = pipe
        try process.run()
        // Wait until the child reports that it holds the lock.
        #expect(String(data: pipe.fileHandleForReading.readData(ofLength: 6), encoding: .utf8) == "locked")
        let started = Date()
        // Taking the lock waits for the child (well under the 5 s timeout) rather than failing at once.
        try TezosClientStore.withWalletLock(in: dir) { }
        #expect(Date().timeIntervalSince(started) > 1)
        process.waitUntilExit()
        #expect(process.terminationStatus == 0)
    }
}
