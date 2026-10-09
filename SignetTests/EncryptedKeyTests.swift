import Foundation
import Testing
@testable import Signet

struct EncryptedKeyTests {
    @Test(arguments: [AddressScheme.tz1, .tz2, .tz3, .tz4, .tz5])
    func encryptsInOctezFormatAndDecryptsWithThePassphrase(scheme: AddressScheme) async throws {
        let generator = KeyGenerator()
        let material = try await generator.generate(scheme: scheme)
        let encrypted = try await generator.encrypt(secretKey: material.secretKey, passphrase: "correct horse battery staple")

        let expectedPrefix = ["tz1": "edesk", "tz2": "spesk", "tz3": "p2esk", "tz4": "BLesk", "tz5": "mdesk"][scheme.rawValue]!
        #expect(encrypted.hasPrefix(expectedPrefix))
        #expect(KeyKind.locator(forSecretKey: encrypted).hasPrefix("encrypted:"))
        #expect(KeyKind.locator(forSecretKey: material.secretKey).hasPrefix("unencrypted:"))

        // Taquito's own signer must open it and land on the same key.
        let info = try await TaquitoBridge.shared.call("keyInfoFromSecretKey", [encrypted, "correct horse battery staple"])
        #expect(info["address"] == .string(material.address))
        #expect(info["publicKey"] == .string(material.publicKey))

        await #expect(throws: TaquitoBridge.BridgeError.self) {
            _ = try await TaquitoBridge.shared.call("keyInfoFromSecretKey", [encrypted, "wrong"])
        }
    }

    @Test func storeKeepsEncryptedLocatorAndKind() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("signet-enc-\(UUID().uuidString)", isDirectory: true)
        let store = TezosClientStore(directory: dir)
        let wallet = Wallet(alias: "vault", address: Address("tz1VSUr8wwNhLAzempoch5d6hLRiTh8Cjcjb"), publicKey: "edpkV", keyKind: .encrypted)
        try store.add(wallet, secretKey: "edeskFAKEENCRYPTED")

        let loaded = try #require(try store.load().first)
        #expect(loaded.keyKind == .encrypted)
        #expect(try store.secretKey(for: loaded) == "edeskFAKEENCRYPTED")
        let raw = try String(contentsOf: dir.appendingPathComponent("secret_keys"), encoding: .utf8)
        #expect(raw.contains("\"encrypted:edeskFAKEENCRYPTED\""))
    }
}

@MainActor
struct EncryptedWalletFlowTests {
    @Test func createWalletWithPassphraseStoresAnEncryptedKey() async throws {
        let store = InMemoryWalletStore()
        let model = WalletViewModel(chain: MockChainService(), walletStore: store)
        try await model.createWallet(alias: "Vault", scheme: .tz1, passphrase: "correct horse battery staple")
        let wallet = try #require(model.selectedWallet)
        #expect(wallet.keyKind == .encrypted)
        #expect(try store.secretKey(for: wallet)?.hasPrefix("edesk") == true)

        await #expect(throws: WalletViewModel.WalletError.self) {
            try await model.createWallet(alias: "Short", scheme: .tz1, passphrase: "short")
        }
    }

    @Test func sendingFromAnEncryptedWalletNeedsTheRightPassword() async {
        let vault = Wallet(alias: "Vault", address: Address("tz1VSUr8wwNhLAzempoch5d6hLRiTh8Cjcjb"), publicKey: "edpkV", keyKind: .encrypted)
        let alice = Wallet(alias: "Alice", address: Address("tz3WXYtyDUNL91qfiCJtVUX746QpNv5i5ve5"))
        let send = SendViewModel(sender: vault, wallets: [vault, alice], chain: MockChainService(), spendable: 100,
                                 signerProvider: { w, p in .secret("edeskFAKE", passphrase: p, address: w.address) })
        #expect(send.needsPassphrase)
        send.choose(alice)
        try? await Task.sleep(for: .milliseconds(400))
        send.amountText = "1"
        await send.proceedToConfirm()
        #expect(send.step == .confirm)

        await send.send()
        #expect(send.step == .confirm)
        #expect(send.errorMessage == SendViewModel.SendError.passphraseRequired.localizedDescription)

        send.passphrase = "nope"
        await send.send()
        #expect(send.step == .confirm)
        #expect(send.errorMessage == ChainError.wrongPassphrase.localizedDescription)

        send.passphrase = "correct horse"
        await send.send()
        guard case .confirmed = send.step else { Issue.record("expected confirmed, got \(send.step)"); return }
    }
}
