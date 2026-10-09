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

    /// A key importer whose decrypt runs a hook first, so a test can switch directories while
    /// Forget is waiting on the password check (S07).
    private struct HookedImporter: KeyImporter {
        let onDecrypt: @Sendable () async -> Void
        func inspect(secretKey: String, passphrase: String?) async throws -> InspectedSecretKey { try await MockKeyImporter().inspect(secretKey: secretKey, passphrase: passphrase) }
        func check(mnemonic: String) async throws -> MnemonicCheck { try await MockKeyImporter().check(mnemonic: mnemonic) }
        func key(fromMnemonic mnemonic: String, passphrase: String?, derivationPath: String, curve: MnemonicCurve) async throws -> KeyMaterial {
            try await MockKeyImporter().key(fromMnemonic: mnemonic, passphrase: passphrase, derivationPath: derivationPath, curve: curve)
        }
        func key(fromFundraiserEmail email: String, password: String, mnemonic: String) async throws -> KeyMaterial {
            try await MockKeyImporter().key(fromFundraiserEmail: email, password: password, mnemonic: mnemonic)
        }
        func decrypt(secretKey: String, passphrase: String) async throws -> String {
            await onDecrypt()
            return "edskDECRYPTED"
        }
    }

    private func makeModel(at a: URL, importer: any KeyImporter = MockKeyImporter()) -> WalletViewModel {
        let suite = "signet-dir-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        defaults.set(a.path, forKey: WalletDirectorySettings.key)
        return WalletViewModel(chain: MockChainService(), keyImporter: importer,
                               directorySettings: WalletDirectorySettings(defaults: defaults),
                               storeFactory: { (wallets: TezosClientStore(directory: $0), state: FileAppStateStore(directory: $0)) })
    }

    /// S07: directories a and b both have an encrypted "shared" alias with different keys.
    /// Switching to b while Forget awaits the password check must delete nothing anywhere.
    @Test func forgetRefusesWhenTheDirectoryChangesDuringThePasswordCheck() async throws {
        let a = tempDir("a"), b = tempDir("b")
        try TezosClientStore(directory: a).add(Wallet(alias: "shared", address: Address("tz1VSUr8wwNhLAzempoch5d6hLRiTh8Cjcjb"), publicKey: "edpkA", keyKind: .encrypted), secretKey: "edeskA")
        try TezosClientStore(directory: b).add(Wallet(alias: "shared", address: Address("tz2BFTyPeYRzxd5aiBchbXN3WCZhx7BqbMBq"), publicKey: "sppkB", keyKind: .encrypted), secretKey: "edeskB")

        let box = ModelBox()
        let model = makeModel(at: a, importer: HookedImporter { await box.model?.changeWalletDirectory(to: b) })
        box.model = model
        #expect(model.selectedWallet?.alias == "shared")

        await #expect(throws: (any Error).self) { try await model.forgetSelectedWallet(passphrase: "pw") }

        #expect(try TezosClientStore(directory: a).load().map(\.alias) == ["shared"])
        #expect(try TezosClientStore(directory: b).load().map(\.alias) == ["shared"])
        #expect(model.wallets.map(\.alias) == ["shared"])
    }

    /// S06: a Send sheet holds the wallet it opened with. After a directory switch, the same alias
    /// in the new directory must not be handed out as that wallet's key.
    @Test func signingKeyRefusesAStaleWalletAfterADirectorySwitch() throws {
        let a = tempDir("a"), b = tempDir("b")
        try TezosClientStore(directory: a).add(Wallet(alias: "shared", address: Address("tz1VSUr8wwNhLAzempoch5d6hLRiTh8Cjcjb"), publicKey: "edpkA", keyKind: .unencrypted), secretKey: "edskA")
        try TezosClientStore(directory: b).add(Wallet(alias: "shared", address: Address("tz2BFTyPeYRzxd5aiBchbXN3WCZhx7BqbMBq"), publicKey: "sppkB", keyKind: .unencrypted), secretKey: "edskB")

        let model = makeModel(at: a)
        let stale = try #require(model.selectedWallet)
        #expect(try model.signingKey(for: stale, passphrase: nil) == .secret("edskA", passphrase: nil, address: stale.address))

        model.changeWalletDirectory(to: b)
        #expect(throws: TezosClientStore.StoreError.self) { try model.signingKey(for: stale, passphrase: nil) }
        // The new directory's own wallet still signs with its own key.
        let fresh = try #require(model.selectedWallet)
        #expect(try model.signingKey(for: fresh, passphrase: nil) == .secret("edskB", passphrase: nil, address: fresh.address))
    }

    @Test func forgetRefusesAReplacementKeyAfterThePasswordCheck() async throws {
        let directory = tempDir("replacement")
        let store = TezosClientStore(directory: directory)
        try store.add(Wallet(alias: "shared", address: Address("tz1VSUr8wwNhLAzempoch5d6hLRiTh8Cjcjb"), publicKey: "edpkA", keyKind: .encrypted), secretKey: "edeskOLD")
        let model = makeModel(at: directory, importer: HookedImporter {
            do {
                let entries = [["name": "shared", "value": "encrypted:edeskREPLACEMENT"]]
                try JSONSerialization.data(withJSONObject: entries).write(to: directory.appendingPathComponent("secret_keys"), options: .atomic)
            } catch { Issue.record("could not replace synthetic key fixture") }
        })
        await #expect(throws: TezosClientStore.StoreError.self) { try await model.forgetSelectedWallet(passphrase: "old-password") }
        let wallet = try #require(store.load().first)
        #expect(try store.secretKey(for: wallet) == "edeskREPLACEMENT")
        #expect(model.wallets.count == 1)
    }

    @Test func forgetRefusesSwitchingAwayAndBackDuringThePasswordCheck() async throws {
        let a = tempDir("return-a"), b = tempDir("return-b")
        let wallet = Wallet(alias: "shared", address: Address("tz1VSUr8wwNhLAzempoch5d6hLRiTh8Cjcjb"), publicKey: "edpkA", keyKind: .encrypted)
        try TezosClientStore(directory: a).add(wallet, secretKey: "edeskA")
        try TezosClientStore(directory: b).add(wallet, secretKey: "edeskB")
        let box = ModelBox()
        let model = makeModel(at: a, importer: HookedImporter {
            await box.model?.changeWalletDirectory(to: b)
            await box.model?.changeWalletDirectory(to: a)
        })
        box.model = model
        await #expect(throws: WalletViewModel.WalletError.self) { try await model.forgetSelectedWallet(passphrase: "pw") }
        #expect(try TezosClientStore(directory: a).load().count == 1)
        #expect(try TezosClientStore(directory: b).load().count == 1)
    }

    @Test func forgetRemovesAnUnchangedPasswordVerifiedAccount() async throws {
        let directory = tempDir("unchanged")
        let store = TezosClientStore(directory: directory)
        try store.add(Wallet(alias: "shared", address: Address("tz1VSUr8wwNhLAzempoch5d6hLRiTh8Cjcjb"), publicKey: "edpkA", keyKind: .encrypted), secretKey: "edeskA")
        let model = makeModel(at: directory, importer: HookedImporter {})
        try await model.forgetSelectedWallet(passphrase: "pw")
        #expect(try store.load().isEmpty)
        #expect(model.wallets.isEmpty)
    }

    /// The bridge is the last line: a secret spec whose key derives another address is refused.
    @Test(arguments: ["{}", #"{"address":null}"#, #"{"address":""}"#,
                      #"{"address":"   "}"#, #"{"address":false}"#, #"{"address":123}"#])
    func bridgeRequiresAnExpectedAccountAddress(fields: String) async throws {
        var spec = try #require(try JSONSerialization.jsonObject(with: Data(fields.utf8)) as? [String: Any])
        spec["kind"] = "secret"
        // Address validation must happen before key loading, even with an unusable key.
        spec["secretKey"] = "invalid-synthetic-key"
        let json = String(decoding: try JSONSerialization.data(withJSONObject: spec), as: UTF8.self)
        do {
            _ = try await TaquitoBridge.shared.call("signPayload", [json, "0501000000026869"])
            Issue.record("Signing accepted a missing or invalid expected address")
        } catch {
            #expect(error.localizedDescription.contains("missing expected account address"))
        }
    }

    @Test func bridgeRefusesASecretKeyThatDerivesAnotherAddress() async throws {
        let mine = try await KeyGenerator().generate(scheme: .tz1)
        let other = try await KeyGenerator().generate(scheme: .tz1)
        let wrong = SigningKey.secret(mine.secretKey, passphrase: nil, address: Address(other.address)).bridgeSpec
        await #expect(throws: (any Error).self) { try await TaquitoBridge.shared.call("signPayload", [wrong, "0501000000026869"]) }
        do {
            _ = try await TaquitoBridge.shared.call("signPayload", [wrong, "0501000000026869"])
        } catch {
            #expect(ChainError.fromBridgeMessage(error.localizedDescription) == .keyAddressMismatch(error.localizedDescription))
        }
        let right = SigningKey.secret(mine.secretKey, passphrase: nil, address: Address(mine.address)).bridgeSpec
        let signed = try await TaquitoBridge.shared.call("signPayload", [right, "0501000000026869"])
        #expect(signed["signature"]?.stringValue?.hasPrefix("edsig") == true)
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

/// Lets a hook reach the model that owns it.
@MainActor private final class ModelBox {
    var model: WalletViewModel?
}
