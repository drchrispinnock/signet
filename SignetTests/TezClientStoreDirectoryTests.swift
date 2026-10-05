import Foundation
import Testing
@testable import Signet

@MainActor
struct WalletDirectoryTests {
    private func tempDir(_ label: String) -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("signet-\(label)-\(UUID().uuidString)", isDirectory: true)
    }

    private func seed(_ dir: URL, alias: String, address: String, remembered: String? = nil) throws {
        let store = TezosClientStore(directory: dir)
        try store.add(Wallet(alias: alias, address: Address(address), publicKey: "edpk\(alias)", keyKind: .unencrypted), secretKey: "edsk\(alias)")
        try store.add(Wallet(alias: "\(alias)-2", address: Address(address), publicKey: "edpk\(alias)2", keyKind: .unencrypted), secretKey: "edsk\(alias)2")
        if let remembered { try FileAppStateStore(directory: dir).save(AppState(selectedWalletAlias: remembered)) }
    }

    @Test func switchingDirectoriesSwapsWalletsAndRestoresThatDirectorysSelection() throws {
        let a = tempDir("a"), b = tempDir("b")
        try seed(a, alias: "alpha", address: "tz1VSUr8wwNhLAzempoch5d6hLRiTh8Cjcjb")
        try seed(b, alias: "beta", address: "tz2BFTyPeYRzxd5aiBchbXN3WCZhx7BqbMBq", remembered: "beta-2")

        let suite = "signet-dir-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        defaults.set(a.path, forKey: WalletDirectorySettings.key)

        let factory: @Sendable (URL) -> (wallets: any WalletStore, state: any AppStateStore) = {
            (wallets: TezosClientStore(directory: $0), state: FileAppStateStore(directory: $0))
        }
        let model = WalletViewModel(chain: MockChainService(),
                                    directorySettings: WalletDirectorySettings(defaults: defaults), storeFactory: factory)
        #expect(model.walletDirectory?.standardizedFileURL == a.standardizedFileURL)
        #expect(model.wallets.map(\.alias) == ["alpha", "alpha-2"])
        #expect(!model.isUsingDefaultWalletDirectory)

        model.changeWalletDirectory(to: b)

        #expect(model.wallets.map(\.alias) == ["beta", "beta-2"])
        #expect(model.selectedWallet?.alias == "beta-2")
        #expect(defaults.string(forKey: WalletDirectorySettings.key) == b.standardizedFileURL.path)

        // A relaunch over the same preferences lands in b.
        let again = WalletViewModel(chain: MockChainService(),
                                    directorySettings: WalletDirectorySettings(defaults: defaults), storeFactory: factory)
        #expect(again.wallets.map(\.alias) == ["beta", "beta-2"])
    }

    @Test func defaultDirectoryClearsTheOverride() {
        let suite = "signet-dir-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let settings = WalletDirectorySettings(defaults: defaults)
        #expect(settings.current == settings.defaultDirectory)

        settings.set(URL(fileURLWithPath: "/tmp/elsewhere", isDirectory: true))
        #expect(settings.current.path == "/tmp/elsewhere")
        settings.set(settings.defaultDirectory)
        #expect(defaults.string(forKey: WalletDirectorySettings.key) == nil)
        #expect(settings.current == settings.defaultDirectory)
    }
}
