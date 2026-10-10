import Foundation
import Testing
@testable import Signet

struct WalletBackupTests {
    private func tempDir(_ label: String) -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("signet-\(label)-\(UUID().uuidString)", isDirectory: true)
    }

    private func seedWallet(in dir: URL, alias: String) throws {
        try TezosClientStore(directory: dir).add(
            Wallet(alias: alias, address: Address("tz1VSUr8wwNhLAzempoch5d6hLRiTh8Cjcjb"), publicKey: "edpk\(alias)", keyKind: .unencrypted),
            secretKey: "edsk\(alias)")
    }

    @Test func createsAGenerationWithTheWalletFiles() throws {
        let wallet = tempDir("wallet"), backups = tempDir("backups")
        try seedWallet(in: wallet, alias: "a")
        try FileAppStateStore(directory: wallet).save(AppState(selectedWalletAlias: "a"))

        let outcome = try WalletBackup(walletDirectory: wallet, backupDirectory: backups, generations: 10).run()
        guard case .created(let generation) = outcome else { Issue.record("expected .created, got \(outcome)"); return }

        for file in ["public_key_hashs", "public_keys", "secret_keys", "state"] {
            let copy = generation.appendingPathComponent(file)
            #expect(FileManager.default.fileExists(atPath: copy.path), Comment(rawValue: file))
            let original = try Data(contentsOf: wallet.appendingPathComponent(file))
            #expect(try Data(contentsOf: copy) == original, Comment(rawValue: file))
            let attrs = try FileManager.default.attributesOfItem(atPath: copy.path)
            #expect((attrs[.posixPermissions] as? Int) == 0o600, Comment(rawValue: file))
        }
        #expect(try TezosClientStore(directory: generation).load().map(\.alias) == ["a"])
    }

    @Test func skipsWhenNothingChangedAndPrunesToTheLimit() throws {
        let wallet = tempDir("wallet"), backups = tempDir("backups")
        try seedWallet(in: wallet, alias: "a")
        let job = WalletBackup(walletDirectory: wallet, backupDirectory: backups, generations: 3)
        let base = Date(timeIntervalSince1970: 1_800_000_000)

        guard case .created(let first) = try job.run(now: base) else { Issue.record("first run should create"); return }
        #expect(try job.run(now: base.addingTimeInterval(60)) == .unchanged(latest: first))
        #expect(try WalletBackup.generations(in: backups).count == 1)

        // Each change produces a generation; only the newest three survive.
        for (i, alias) in ["b", "c", "d", "e"].enumerated() {
            try seedWallet(in: wallet, alias: alias)
            guard case .created = try job.run(now: base.addingTimeInterval(Double(120 * (i + 1)))) else { Issue.record("expected a new generation for \(alias)"); return }
        }
        let remaining = try WalletBackup.generations(in: backups)
        #expect(remaining.count == 3)
        #expect(!remaining.contains(first))
        // The newest generation holds everything.
        #expect(try TezosClientStore(directory: remaining.last!).load().map(\.alias) == ["a", "b", "c", "d", "e"])
    }

    /// S05: only generations Signet made are pruned. Anything else in the backup folder, a
    /// user's documents, a symlink, a stamp-named folder holding other things, is never touched.
    @Test func pruningLeavesWhatItDoesNotOwnAlone() throws {
        let wallet = tempDir("wallet"), backups = tempDir("backups"), elsewhere = tempDir("elsewhere")
        try seedWallet(in: wallet, alias: "a")
        let fm = FileManager.default
        try fm.createDirectory(at: backups, withIntermediateDirectories: true)
        let documents = backups.appendingPathComponent("000-unrelated-documents", isDirectory: true)
        try fm.createDirectory(at: documents, withIntermediateDirectories: true)
        try Data("thesis".utf8).write(to: documents.appendingPathComponent("thesis.txt"))
        let lookalike = backups.appendingPathComponent("1999-01-01T000000Z", isDirectory: true)   // stamp name, foreign contents
        try fm.createDirectory(at: lookalike, withIntermediateDirectories: true)
        try Data("photo".utf8).write(to: lookalike.appendingPathComponent("holiday.jpg"))
        try fm.createDirectory(at: elsewhere, withIntermediateDirectories: true)
        try Data("precious".utf8).write(to: elsewhere.appendingPathComponent("keep.txt"))
        try fm.createSymbolicLink(at: backups.appendingPathComponent("1999-01-02T000000Z"), withDestinationURL: elsewhere)
        let legacy = backups.appendingPathComponent("2000-01-01T000000Z", isDirectory: true)      // no manifest: owner unknown
        try fm.createDirectory(at: legacy, withIntermediateDirectories: true)
        try Data("[]".utf8).write(to: legacy.appendingPathComponent("public_key_hashs"))

        let job = WalletBackup(walletDirectory: wallet, backupDirectory: backups, generations: 1)
        #expect(try WalletBackup.generations(in: backups).isEmpty)
        let base = Date(timeIntervalSince1970: 1_800_000_000)
        guard case .created(let first) = try job.run(now: base) else { Issue.record("expected .created"); return }
        try seedWallet(in: wallet, alias: "b")
        guard case .created(let second) = try job.run(now: base.addingTimeInterval(60)) else { Issue.record("expected .created"); return }

        // Our old generations went; everything foreign is still there, symlink target included.
        #expect(try WalletBackup.generations(in: backups) == [second])
        #expect(fm.fileExists(atPath: legacy.path) && !fm.fileExists(atPath: first.path))
        #expect(try String(contentsOf: documents.appendingPathComponent("thesis.txt"), encoding: .utf8) == "thesis")
        #expect(try String(contentsOf: lookalike.appendingPathComponent("holiday.jpg"), encoding: .utf8) == "photo")
        #expect(try String(contentsOf: elsewhere.appendingPathComponent("keep.txt"), encoding: .utf8) == "precious")
        #expect(fm.fileExists(atPath: backups.appendingPathComponent("1999-01-02T000000Z").path))
        let manifest = try #require(WalletBackup.manifest(of: second))
        #expect(manifest.source == WalletBackup.normalized(wallet).path)
        #expect(manifest.files.contains("public_key_hashs"))
    }

    @Test func sharedBackupFolderKeepsEachWalletsGenerations() throws {
        let a = tempDir("wallet-a"), b = tempDir("wallet-b"), backups = tempDir("backups")
        try seedWallet(in: a, alias: "same")
        try seedWallet(in: b, alias: "same")
        let base = Date(timeIntervalSince1970: 1_800_000_000)
        let first = try WalletBackup(walletDirectory: a, backupDirectory: backups, generations: 1).run(now: base)
        guard case .created(let savedA) = first else { Issue.record("expected A backup"); return }
        // Identical data from another wallet must neither deduplicate against nor prune A.
        let second = try WalletBackup(walletDirectory: b, backupDirectory: backups, generations: 1).run(now: base.addingTimeInterval(60))
        guard case .created(let savedB) = second else { Issue.record("expected B backup"); return }
        #expect(FileManager.default.fileExists(atPath: savedA.path))
        _ = try WalletBackup(walletDirectory: b, backupDirectory: backups, generations: 1).run(now: base.addingTimeInterval(120), force: true)
        #expect(FileManager.default.fileExists(atPath: savedA.path))
        #expect(!FileManager.default.fileExists(atPath: savedB.path))
        #expect(try WalletBackup.generations(in: backups, source: a) == [savedA])
        #expect(try WalletBackup.generations(in: backups, source: b).count == 1)
    }

    @Test func unknownManifestVersionsAndExtraDocumentsArePreserved() throws {
        let wallet = tempDir("wallet"), backups = tempDir("backups")
        try seedWallet(in: wallet, alias: "a")
        let job = WalletBackup(walletDirectory: wallet, backupDirectory: backups, generations: 1)
        let base = Date(timeIntervalSince1970: 1_800_000_000)
        guard case .created(let old) = try job.run(now: base) else { Issue.record("expected backup"); return }
        var manifest = try #require(WalletBackup.manifest(of: old))
        manifest.version += 1
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(manifest).write(to: old.appendingPathComponent(WalletBackup.manifestFile))
        guard case .created(let documents) = try job.run(now: base.addingTimeInterval(60), force: true) else { Issue.record("expected backup"); return }
        try Data("precious".utf8).write(to: documents.appendingPathComponent("notes.txt"))
        _ = try job.run(now: base.addingTimeInterval(120), force: true)
        #expect(FileManager.default.fileExists(atPath: old.path))
        #expect(try String(contentsOf: documents.appendingPathComponent("notes.txt"), encoding: .utf8) == "precious")
    }

    @Test func backupFolderMustNotOverlapTheWallet() throws {
        let wallet = tempDir("wallet")
        try seedWallet(in: wallet, alias: "a")
        for bad in [wallet, wallet.appendingPathComponent("backups"), wallet.deletingLastPathComponent()] {
            #expect(throws: WalletBackup.BackupError.self) { try WalletBackup(walletDirectory: wallet, backupDirectory: bad, generations: 3).run() }
        }
        #expect(try WalletBackup.generations(in: wallet).isEmpty)
    }

    /// S28: a directory holding only named contracts or proposals is worth a generation too.
    @Test func contractsOnlyDirectoryIsBackedUp() throws {
        let wallet = tempDir("wallet"), backups = tempDir("backups")
        try TezosClientStore(directory: wallet).addContract(MultisigContract(alias: "treasury", address: Address("KT1BEqzn5Wx8uJrZNvuS9DVHmLvG9td3fDLi")))
        guard case .created(let generation) = try WalletBackup(walletDirectory: wallet, backupDirectory: backups, generations: 3).run() else { Issue.record("expected .created"); return }
        #expect(try TezosClientStore(directory: generation).loadContracts().map(\.alias) == ["treasury"])
        // State alone is not.
        let empty = tempDir("wallet")
        try FileAppStateStore(directory: empty).save(AppState(selectedWalletAlias: nil))
        #expect(try WalletBackup(walletDirectory: empty, backupDirectory: backups, generations: 3).run() == .nothingToBackUp)
    }

    @Test func nothingToBackUpWithoutWalletFiles() throws {
        let wallet = tempDir("wallet"), backups = tempDir("backups")
        #expect(try WalletBackup(walletDirectory: wallet, backupDirectory: backups, generations: 10).run() == .nothingToBackUp)
        let generations = try WalletBackup.generations(in: backups)
        #expect(generations.isEmpty)
    }

    @Test func settingsDefaultAndClamp() {
        let suite = "signet-backup-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let settings = BackupSettings(defaults: defaults)
        #expect(settings.generations == 10)
        #expect(settings.directory.lastPathComponent == ".signet_backups")

        settings.setGenerations(500)
        #expect(settings.generations == 100)
        settings.setGenerations(0)
        #expect(settings.generations == 1)
        settings.setGenerations(10)
        #expect(defaults.object(forKey: BackupSettings.generationsKey) == nil)

        settings.setDirectory(URL(fileURLWithPath: "/tmp/bk", isDirectory: true))
        #expect(settings.directory.path == "/tmp/bk")
        settings.setDirectory(settings.defaultDirectory)
        #expect(defaults.string(forKey: BackupSettings.directoryKey) == nil)
    }
}

@MainActor
struct BackupViewModelTests {
    @Test func backsUpOnLaunchAndAfterCreatingAKey() async throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("signet-vmbk-\(UUID().uuidString)", isDirectory: true)
        let wallet = base.appendingPathComponent("wallet"), backups = base.appendingPathComponent("backups")
        try TezosClientStore(directory: wallet).add(
            Wallet(alias: "seed", address: Address("tz1VSUr8wwNhLAzempoch5d6hLRiTh8Cjcjb"), publicKey: "edpkS", keyKind: .unencrypted), secretKey: "edskS")

        let suite = "signet-vmbk-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        defaults.set(wallet.path, forKey: WalletDirectorySettings.key)
        defaults.set(backups.path, forKey: BackupSettings.directoryKey)

        let model = WalletViewModel(chain: MockChainService(),
                                    directorySettings: WalletDirectorySettings(defaults: defaults),
                                    storeFactory: { (wallets: TezosClientStore(directory: $0), state: FileAppStateStore(directory: $0)) },
                                    backupSettings: BackupSettings(defaults: defaults))
        // The launch backup is asynchronous; wait for it.
        for _ in 0..<50 where model.lastBackup == nil { try await Task.sleep(for: .milliseconds(50)) }
        guard case .created = model.lastBackup?.outcome else { Issue.record("launch backup missing: \(String(describing: model.lastBackup))"); return }
        #expect(try WalletBackup.generations(in: backups).count == 1)

        try await model.createWallet(alias: "fresh", scheme: .tz1)
        #expect(try WalletBackup.generations(in: backups).count == 2)
        #expect(try TezosClientStore(directory: WalletBackup.generations(in: backups).last!).load().map(\.alias) == ["seed", "fresh"])
    }
}

struct ForcedBackupTests {
    @Test func forceWritesAGenerationEvenWhenUnchanged() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("signet-force-\(UUID().uuidString)", isDirectory: true)
        let wallet = base.appendingPathComponent("wallet"), backups = base.appendingPathComponent("backups")
        try TezosClientStore(directory: wallet).add(
            Wallet(alias: "a", address: Address("tz1VSUr8wwNhLAzempoch5d6hLRiTh8Cjcjb"), publicKey: "edpkA", keyKind: .unencrypted), secretKey: "edskA")
        let job = WalletBackup(walletDirectory: wallet, backupDirectory: backups, generations: 10)
        let t0 = Date(timeIntervalSince1970: 1_800_000_000)

        guard case .created = try job.run(now: t0) else { Issue.record("first run should create"); return }
        guard case .unchanged = try job.run(now: t0.addingTimeInterval(60)) else { Issue.record("second run should skip"); return }
        guard case .created = try job.run(now: t0.addingTimeInterval(120), force: true) else { Issue.record("forced run should create"); return }
        #expect(try WalletBackup.generations(in: backups).count == 2)
    }
}
