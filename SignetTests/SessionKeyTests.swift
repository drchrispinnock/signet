import Foundation
import Testing
@testable import Signet

/// Paper keys: imported for this run only, usable like any software key, never written anywhere.
@MainActor
struct SessionKeyTests {
    static let paper = KeyMaterial(scheme: .tz1, publicKey: "edpkuPAPER", address: "tz1VSUr8wwNhLAzempoch5d6hLRiTh8Cjcjb", secretKey: "edskPAPERSECRET")
    static let other = KeyMaterial(scheme: .tz1, publicKey: "edpkuOTHER", address: "tz1dCaMnnMJk76UodjewCK67ABiXWjcKj73N", secretKey: "edskOTHER")

    @Test func aSessionKeySignsAndExportsButIsNeverStored() async throws {
        let store = InMemoryWalletStore()
        let model = WalletViewModel(chain: MockChainService(), walletStore: store)
        try await model.importAccount(alias: "Paper", material: Self.paper, keepForSession: true)
        let wallet = try #require(model.selectedWallet)
        #expect(wallet.alias == "Paper" && wallet.isSessionOnly && wallet.keyKind == .unencrypted)
        #expect(model.wallets.map(\.alias) == ["Paper"])
        #expect(try store.load().isEmpty)

        guard case .secret(let secret, let passphrase, let address)? = try model.signingKey(for: wallet, passphrase: nil) else {
            Issue.record("no signing key for the session account"); return
        }
        #expect(secret == Self.paper.secretKey && passphrase == nil && address == wallet.address)
        #expect(try await model.exportSecretKey(passphrase: nil) == WalletViewModel.ExportedKey(clear: Self.paper.secretKey, encrypted: nil))

        // Aliases are shared with the directory; stored accounts come first; a fresh load never sees the paper key.
        await #expect(throws: WalletViewModel.WalletError.self) { try await model.importAccount(alias: "Paper", material: Self.other) }
        try await model.importAccount(alias: "Stored", material: Self.other)
        #expect(model.wallets.map(\.alias) == ["Stored", "Paper"])
        #expect(try store.load().map(\.alias) == ["Stored"])
        #expect(WalletViewModel(chain: MockChainService(), walletStore: store).wallets.map(\.alias) == ["Stored"])
    }

    @Test func renameAndForgetStayInMemory() async throws {
        let store = InMemoryWalletStore()
        let model = WalletViewModel(chain: MockChainService(), walletStore: store)
        try await model.importAccount(alias: "Paper", material: Self.paper, keepForSession: true)
        try model.renameSelectedWallet(to: "Cold")
        #expect(model.selectedWallet?.alias == "Cold" && model.wallets.map(\.alias) == ["Cold"])
        let renamed = try #require(model.selectedWallet)
        #expect(try model.signingKey(for: renamed, passphrase: nil) != nil)
        // A wallet value from before the rename no longer names the key.
        var stale = Wallet(alias: "Paper", address: renamed.address, scheme: .tz1, publicKey: renamed.publicKey, keyKind: .unencrypted)
        stale.isSessionOnly = true
        #expect(try model.signingKey(for: stale, passphrase: nil) == nil)
        #expect(try store.load().isEmpty)

        try await model.forgetSelectedWallet(passphrase: nil)
        #expect(model.wallets.isEmpty && model.selectedWallet == nil)
        #expect(try store.load().isEmpty)
    }

    @Test func encryptedSessionKeysKeepTheirPassword() async throws {
        let material = try await KeyGenerator().generate(scheme: .tz1)
        let model = WalletViewModel(chain: MockChainService(), walletStore: InMemoryWalletStore())
        try await model.importAccount(alias: "Vault", material: material, storePassphrase: "correct horse battery staple", keepForSession: true)
        let wallet = try #require(model.selectedWallet)
        #expect(wallet.isSessionOnly && wallet.keyKind == .encrypted)
        guard case .secret(let secret, let passphrase, _)? = try model.signingKey(for: wallet, passphrase: "correct horse battery staple") else {
            Issue.record("no signing key for the encrypted session account"); return
        }
        #expect(secret.hasPrefix("edesk") && passphrase == "correct horse battery staple")
        // Forgetting an encrypted key needs its password, like a stored one.
        await #expect(throws: (any Error).self) { try await model.forgetSelectedWallet(passphrase: nil) }
        #expect(model.wallets.count == 1)
    }

    @Test func secretsAreWipedWhenForgotten() {
        let secret = SessionSecret("edskSECRET")
        #expect(secret.value == "edskSECRET")
        secret.wipe()
        #expect(secret.value.utf8.count == 10 && secret.value.utf8.allSatisfy { $0 == 0 })
    }

    @Test func walletsRecordedBeforeTheFlagStillDecode() throws {
        let encoded = try JSONEncoder().encode(Wallet(alias: "b", address: Address("tz1VSUr8wwNhLAzempoch5d6hLRiTh8Cjcjb")))
        var object = try #require(try JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        #expect(object["isSessionOnly"] as? Bool == false)
        object.removeValue(forKey: "isSessionOnly")
        let decoded = try JSONDecoder().decode(Wallet.self, from: try JSONSerialization.data(withJSONObject: object))
        #expect(decoded.alias == "b" && !decoded.isSessionOnly)
    }
}
