import Foundation
import Testing
@testable import Signet

struct ImportTests {
    /// Live: the Mt Pelerin docs' test phrase derives their documented address at 44'/1729'/0'/0'.
    @Test func derivesTheDocumentedAddressFromAPhrase() async throws {
        let importer = BridgeKeyImporter()
        let phrase = "bamboo feed assist glove soda merry medal vanish almost solid bean loop"
        let check = try await importer.check(mnemonic: phrase)
        #expect(check.isValid && check.wordCount == 12 && check.unknownWords.isEmpty)
        let key = try await importer.key(fromMnemonic: phrase, passphrase: nil, derivationPath: BridgeKeyImporter.defaultDerivationPath, curve: .ed25519)
        #expect(key.address == "tz1dnCbNYHDoxmHss9kEQVjWQj6GvYX4gYp5")
        #expect(key.publicKey == "edpkus9ckWtwxNi7NqZqGT2bo1VGxyRkCvaV5zkms7rkeWUV532PhU")
        #expect(key.secretKey.hasPrefix("edsk") && key.secretKey.count == 54)
        // Other curves and accounts give other addresses.
        let tz2 = try await importer.key(fromMnemonic: phrase, passphrase: nil, derivationPath: BridgeKeyImporter.defaultDerivationPath, curve: .secp256k1)
        #expect(tz2.address.hasPrefix("tz2") && tz2.scheme == .tz2)
        let second = try await importer.key(fromMnemonic: phrase, passphrase: nil, derivationPath: "44'/1729'/1'/0'", curve: .ed25519)
        #expect(second.address != key.address)
        // A 24-word phrase and a bad checksum.
        let bad = try await importer.check(mnemonic: "bamboo feed assist glove soda merry medal vanish almost solid bean bean")
        #expect(!bad.isValid && bad.wordCount == 12)
        let typo = try await importer.check(mnemonic: "bamboo feed assist glove soda merry medal vanish almost solid bean looop")
        #expect(typo.unknownWords == ["looop"])
    }

    /// Live: a pasted key round-trips, a 64-byte edsk is reduced to its seed, encrypted keys need their password.
    @Test func inspectsPastedKeys() async throws {
        let importer = BridgeKeyImporter()
        let generated = try await KeyGenerator().generate(scheme: .tz1)
        let clear = try await importer.inspect(secretKey: generated.secretKey, passphrase: nil)
        #expect(clear.address?.value == generated.address && clear.secretKey == generated.secretKey && !clear.isEncrypted)

        let encrypted = try await KeyGenerator().encrypt(secretKey: generated.secretKey, passphrase: "correct horse battery staple")
        let locked = try await importer.inspect(secretKey: encrypted, passphrase: nil)
        #expect(locked.needsPassphrase && locked.isEncrypted)
        let opened = try await importer.inspect(secretKey: encrypted, passphrase: "correct horse battery staple")
        #expect(opened.address?.value == generated.address && opened.secretKey == encrypted)
        await #expect(throws: ChainError.wrongPassphrase) { _ = try await importer.inspect(secretKey: encrypted, passphrase: "nope") }

        let tz2 = try await KeyGenerator().generate(scheme: .tz2)
        #expect(try await importer.inspect(secretKey: tz2.secretKey, passphrase: nil).address?.value == tz2.address)
        await #expect(throws: Error.self) { _ = try await importer.inspect(secretKey: "edskNotAKey", passphrase: nil) }
    }

    @Test @MainActor func importStoresAndSelects() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("signet-import-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = TezosClientStore(directory: dir)
        let model = WalletViewModel(chain: MockChainService(), walletStore: store)
        let material = KeyMaterial(scheme: .tz1, publicKey: "edpkX", address: "tz1VSUr8wwNhLAzempoch5d6hLRiTh8Cjcjb", secretKey: "edskX")
        try await model.importAccount(alias: "Imported", material: material)
        #expect(model.selectedWallet?.alias == "Imported")
        #expect(model.selectedWallet?.keyKind == .unencrypted)
        #expect(try store.secretKey(for: model.selectedWallet!) == "edskX")

        await #expect(throws: WalletViewModel.WalletError.self) { try await model.importAccount(alias: "Again", material: material) }

        let enc = KeyMaterial(scheme: .tz1, publicKey: "edpkY", address: "tz1dnCbNYHDoxmHss9kEQVjWQj6GvYX4gYp5", secretKey: "edeskALREADY")
        try await model.importAccount(alias: "Vault", material: enc, alreadyEncrypted: true)
        #expect(model.selectedWallet?.keyKind == .encrypted)
        #expect(try store.secretKey(for: model.selectedWallet!) == "edeskALREADY")
    }

    /// Live: an encrypted key decrypts back to the seed it was made from.
    @Test func decryptsForExport() async throws {
        let generated = try await KeyGenerator().generate(scheme: .tz1)
        let encrypted = try await KeyGenerator().encrypt(secretKey: generated.secretKey, passphrase: "correct horse battery staple")
        #expect(try await BridgeKeyImporter().decrypt(secretKey: encrypted, passphrase: "correct horse battery staple") == generated.secretKey)
        await #expect(throws: ChainError.wrongPassphrase) { _ = try await BridgeKeyImporter().decrypt(secretKey: encrypted, passphrase: "nope") }
    }

    @Test @MainActor func exportNeedsThePasswordForEncryptedKeys() async throws {
        let store = InMemoryWalletStore()
        try store.add(Wallet(alias: "clear", address: Address("tz1VSUr8wwNhLAzempoch5d6hLRiTh8Cjcjb"), publicKey: "edpkX", keyKind: .unencrypted), secretKey: "edskCLEAR")
        try store.add(Wallet(alias: "vault", address: Address("tz1dnCbNYHDoxmHss9kEQVjWQj6GvYX4gYp5"), publicKey: "edpkY", keyKind: .encrypted), secretKey: "edeskLOCKED")
        let model = WalletViewModel(chain: MockChainService(), walletStore: store)
        model.select(try #require(model.wallets.first { $0.alias == "clear" }))
        #expect(model.canExportSelectedKey)
        #expect(try await model.exportSecretKey(passphrase: nil) == .init(clear: "edskCLEAR", encrypted: nil))

        model.select(try #require(model.wallets.first { $0.alias == "vault" }))
        await #expect(throws: SendViewModel.SendError.passphraseRequired) { _ = try await model.exportSecretKey(passphrase: nil) }
        await #expect(throws: ChainError.wrongPassphrase) { _ = try await model.exportSecretKey(passphrase: "wrong") }
        #expect(try await model.exportSecretKey(passphrase: "correct horse") == .init(clear: "edskDECRYPTED", encrypted: "edeskLOCKED"))

        let watch = WalletViewModel(wallets: [Wallet(alias: "w", address: Address("tz1VSUr8wwNhLAzempoch5d6hLRiTh8Cjcjb"), keyKind: .none)], chain: MockChainService())
        #expect(!watch.canExportSelectedKey)
    }

    @Test @MainActor func forgetRemovesTheAliasFromEveryFile() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("signet-forget-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = TezosClientStore(directory: dir)
        try store.add(Wallet(alias: "clear", address: Address("tz1VSUr8wwNhLAzempoch5d6hLRiTh8Cjcjb"), publicKey: "edpkX", keyKind: .unencrypted), secretKey: "edskCLEAR")
        try store.add(Wallet(alias: "vault", address: Address("tz1dnCbNYHDoxmHss9kEQVjWQj6GvYX4gYp5"), publicKey: "edpkY", keyKind: .encrypted), secretKey: "edeskLOCKED")
        try store.addWatchOnly(Wallet(alias: "book", address: Address("tz2BFTyPeYRzxd5aiBchbXN3WCZhx7BqbMBq"), keyKind: .none))
        let model = WalletViewModel(chain: MockChainService(), walletStore: store)

        model.select(try #require(model.wallets.first { $0.alias == "vault" }))
        await #expect(throws: SendViewModel.SendError.passphraseRequired) { try await model.forgetSelectedWallet(passphrase: nil) }
        await #expect(throws: ChainError.wrongPassphrase) { try await model.forgetSelectedWallet(passphrase: "wrong") }
        #expect(model.wallets.count == 3)
        try await model.forgetSelectedWallet(passphrase: "correct horse")
        #expect(model.wallets.map(\.alias) == ["clear", "book"])
        #expect(model.selectedWallet?.alias == "clear")
        for file in TezosClientStore.walletFiles {
            let text = (try? String(contentsOf: dir.appendingPathComponent(file), encoding: .utf8)) ?? ""
            #expect(!text.contains("vault") && !text.contains("edeskLOCKED"))
        }

        model.select(try #require(model.wallets.first { $0.alias == "book" }))
        try await model.forgetSelectedWallet(passphrase: nil)
        try await model.forgetSelectedWallet(passphrase: nil)
        #expect(model.wallets.isEmpty && model.selectedWallet == nil)
        #expect(try store.load().isEmpty)
    }
}
