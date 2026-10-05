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

    @Test func secretKeyOnlyForUnencryptedEntries() throws {
        let dir = try makeDirectory()
        try writeFixture(in: dir)
        let store = TezosClientStore(directory: dir)
        let wallets = try store.load()
        #expect(try store.secretKey(for: wallets[0]) == "edskALICE")
        #expect(try store.secretKey(for: wallets[1]) == nil)
        #expect(try store.secretKey(for: wallets[3]) == nil)
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
