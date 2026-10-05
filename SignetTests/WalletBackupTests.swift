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
