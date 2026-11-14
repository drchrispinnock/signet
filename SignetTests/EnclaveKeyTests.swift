import CryptoKit
import Foundation
import Testing
@testable import Signet

/// tz3 keys made inside the Secure Enclave: the locator, the store, creation and forgetting in
/// the model, and signing through the bridge, where JavaScript computes the digest and Swift
/// signs it. `SoftwareEnclaveKeys` stands in for the hardware except where a test says otherwise.
struct EnclaveKeyTests {
    @Test func locatorParsesAndRoundTrips() throws {
        let key = EnclaveKey(blob: Data([1, 2, 3, 250, 251, 252]))
        #expect(key.locator.hasPrefix("signet-enclave:"))
        #expect(EnclaveKey(locator: key.locator) == key)
        #expect(KeyKind(locator: key.locator) == .enclave)
        #expect(KeyKind.enclave.canSign)
        #expect(EnclaveKey(locator: "unencrypted:p2sk3zen") == nil)
        #expect(EnclaveKey(locator: "signet-enclave:") == nil)
        #expect(EnclaveKey(locator: "signet-enclave:not base64!") == nil)
    }

    @Test func signaturesAreLowSAndVerify() async throws {
        let enclave = SoftwareEnclaveKeys()
        let pair = try enclave.create()
        let publicKey = try P256.Signing.PublicKey(compressedRepresentation: pair.publicKey)
        for round in 0..<32 {
            let digest = Data((0..<32).map { UInt8(truncatingIfNeeded: $0 &* 13 &+ round) })
            let raw = try await enclave.sign(digest: digest, with: pair.key, reason: "test")
            #expect(raw.count == 64)
            #expect(P256Signature.isLowS(raw))
            #expect(publicKey.isValidSignature(try P256.Signing.ECDSASignature(rawRepresentation: raw), for: RawDigest(digest)))
        }
    }

    @Test func highSIsFlippedToItsLowTwin() {
        // s = n - 1 becomes 1; r is untouched.
        var high = Data(repeating: 0x11, count: 32)
        high += Data([0xff, 0xff, 0xff, 0xff, 0x00, 0x00, 0x00, 0x00, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff,
                      0xbc, 0xe6, 0xfa, 0xad, 0xa7, 0x17, 0x9e, 0x84, 0xf3, 0xb9, 0xca, 0xc2, 0xfc, 0x63, 0x25, 0x50])
        let low = P256Signature.lowS(high)
        #expect(low.prefix(32) == high.prefix(32))
        #expect(low.suffix(32) == Data(repeating: 0, count: 31) + Data([1]))
        #expect(P256Signature.lowS(low) == low)
    }

    @Test func storeKeepsTheLocatorAndNoSecret() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("signet-enclave-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = TezosClientStore(directory: directory)
        let key = EnclaveKey(blob: Data((0..<284).map { UInt8(truncatingIfNeeded: $0) }))
        let wallet = Wallet(alias: "enclave", address: Address("tz3himcMhi5Eaz8XsnoWAL1sYxNsUBtXZFZx"), scheme: .tz3,
                            publicKey: "p2pk66tTYL5EvahKAXncbtbRPBkAnxo3CszzUho5wPCgWauBMyvybuB", keyKind: .enclave, enclaveKey: key)
        try store.add(wallet, locator: key.locator)

        let loaded = try #require(try store.load().first)
        #expect(loaded.keyKind == .enclave)
        #expect(loaded.enclaveKey == key)
        #expect(loaded.address == wallet.address)
        // There is no base58 secret to hand out, and none on disk.
        #expect(try store.secretKey(for: loaded) == nil)
        let secrets = try String(contentsOf: directory.appendingPathComponent("secret_keys"), encoding: .utf8)
        #expect(secrets.contains("signet-enclave:"))
        for prefix in ["p2sk", "edsk", "spsk", "BLsk", "unencrypted:", "encrypted:"] { #expect(!secrets.contains(prefix)) }

        try store.rename(alias: "enclave", to: "spending")
        #expect(try store.load().first?.enclaveKey == key)
    }

    @MainActor @Test func modelCreatesSignsForAndForgetsAnEnclaveAccount() async throws {
        let model = WalletViewModel(wallets: [], chain: MockChainService(), enclave: SoftwareEnclaveKeys(), walletStore: InMemoryWalletStore())
        #expect(model.canCreateEnclaveKey)
        try await model.createEnclaveWallet(alias: "Spending")

        let wallet = try #require(model.selectedWallet)
        #expect(wallet.alias == "Spending")
        #expect(wallet.scheme == .tz3)
        #expect(wallet.address.value.hasPrefix("tz3"))
        #expect(wallet.keyKind == .enclave)
        #expect(model.isEnclaveKeyPresent(wallet))
        #expect(!model.canExportSelectedKey)
        #expect(!model.canProveSelectedKey)

        guard case .enclave(let key, let publicKey, let address)? = try model.signingKey(for: wallet, passphrase: nil) else {
            Issue.record("an Enclave account signs with an Enclave key")
            return
        }
        #expect(key == wallet.enclaveKey)
        #expect(publicKey == wallet.publicKey)
        #expect(address == wallet.address)

        await #expect(throws: (any Error).self) { try await model.createEnclaveWallet(alias: "Spending") }

        try await model.forgetSelectedWallet(passphrase: nil)
        #expect(!model.wallets.contains { $0.alias == "Spending" })
    }

    @MainActor @Test func aKeyFromAnotherMacIsShownButCannotSign() async throws {
        let foreign = EnclaveKey(blob: Data(repeating: 7, count: 5))
        let wallet = Wallet(alias: "elsewhere", address: Address("tz3himcMhi5Eaz8XsnoWAL1sYxNsUBtXZFZx"), scheme: .tz3,
                            publicKey: "p2pk66tTYL5EvahKAXncbtbRPBkAnxo3CszzUho5wPCgWauBMyvybuB", keyKind: .enclave, enclaveKey: foreign)
        let enclave = SoftwareEnclaveKeys()
        let model = WalletViewModel(wallets: [wallet], chain: MockChainService(), enclave: enclave, walletStore: InMemoryWalletStore(wallets: [wallet]))
        #expect(!model.isEnclaveKeyPresent(wallet))
        await #expect(throws: EnclaveError.notOnThisMac) {
            _ = try await enclave.sign(digest: Data(count: 32), with: foreign, reason: "test")
        }
        // It can still be forgotten: there is nothing here to authenticate against.
        model.select(wallet)
        try await model.forgetSelectedWallet(passphrase: nil)
        #expect(model.wallets.isEmpty)
    }

    @MainActor @Test func withoutAnEnclaveNothingIsOffered() async throws {
        let model = WalletViewModel(wallets: [], chain: MockChainService(), walletStore: InMemoryWalletStore())
        #expect(!model.canCreateEnclaveKey)
        await #expect(throws: EnclaveError.unavailable) { try await model.createEnclaveWallet(alias: "Spending") }
        #expect(model.wallets.isEmpty)
    }

    @Test func bridgeSignsThroughTheNativeEnclave() async throws {
        let enclave = SoftwareEnclaveKeys()
        let bridge = TaquitoBridge(systemLog: { _ in })
        bridge.enclave = enclave
        let pair = try enclave.create()
        let publicKey = Base58.checkEncode(prefix: TezosPrefix.p2pk, payload: Array(pair.publicKey))
        let address = try #require(try await bridge.call("addressFromPublicKey", [publicKey]).stringValue)
        #expect(address.hasPrefix("tz3"))

        let payload = "05010000000b68656c6c6f20776f726c64"
        let spec = SigningKey.enclave(pair.key, publicKey: publicKey, address: Address(address)).bridgeSpec
        let signed = try await bridge.sign("signPayload", [spec, payload])
        let signature = try #require(signed["signature"]?.stringValue)
        #expect(signature.hasPrefix("p2sig"))
        #expect(signed["publicKey"]?.stringValue == publicKey)
        #expect(signed["address"]?.stringValue == address)
        #expect(try await bridge.call("verifySignature", [payload, publicKey, signature]).boolValue == true)

        // Another key's blob under this account's name: the signature does not verify, nothing is returned.
        let other = try enclave.create()
        let swapped = SigningKey.enclave(other.key, publicKey: publicKey, address: Address(address)).bridgeSpec
        await #expect(throws: (any Error).self) { _ = try await bridge.sign("signPayload", [swapped, payload]) }

        // A public key that is not the account's is refused before anything is signed.
        let otherPublic = Base58.checkEncode(prefix: TezosPrefix.p2pk, payload: Array(other.publicKey))
        let mismatched = SigningKey.enclave(pair.key, publicKey: otherPublic, address: Address(address)).bridgeSpec
        do {
            _ = try await bridge.sign("signPayload", [mismatched, payload])
            Issue.record("a key for another address must not sign")
        } catch let error as TaquitoBridge.BridgeError {
            guard case .keyAddressMismatch = error.asChainError as? ChainError else {
                Issue.record("expected keyAddressMismatch, got \(error)")
                return
            }
        }
    }

    @Test func enclaveFailuresAreTyped() {
        #expect(ChainError.fromBridgeMessage(EnclaveError.cancelled.localizedDescription) == .enclaveCancelled)
        #expect(ChainError.fromBridgeMessage(EnclaveError.notOnThisMac.localizedDescription) == .enclaveKeyMissing)
    }

    /// The hardware itself, with a key that needs no presence so nobody has to answer a prompt.
    @Test(.enabled(if: SecureEnclave.isAvailable, "This machine has no Secure Enclave"))
    func theRealEnclaveSignsADigestAsItIs() async throws {
        let enclave = SecureEnclaveKeys(requiresUserPresence: false)
        let pair = try enclave.create()
        #expect(enclave.isUsable(pair.key))
        #expect(!enclave.isUsable(EnclaveKey(blob: Data(repeating: 7, count: 284))))
        // Making the guarded kind (Touch ID or password per signature) asks nothing; using it would.
        let guarded = try SecureEnclaveKeys().create()
        #expect(SecureEnclaveKeys().isUsable(guarded.key))
        #expect(guarded.publicKey.count == 33)
        let publicKey = try P256.Signing.PublicKey(compressedRepresentation: pair.publicKey)
        let digest = Data((0..<32).map { UInt8($0 &* 7 &+ 3) })
        for _ in 0..<8 {
            let raw = try await enclave.sign(digest: digest, with: pair.key, reason: "test")
            #expect(P256Signature.isLowS(raw))
            #expect(publicKey.isValidSignature(try P256.Signing.ECDSASignature(rawRepresentation: raw), for: RawDigest(digest)))
        }
    }
}

/// The whole path against a real node: a tz3 account whose key the bridge never sees reveals
/// itself and sends tez on Shadownet, signed by the Enclave (the hardware where there is one,
/// with a key that asks for no presence).
struct EnclaveSendTests {
    @Test(.tags(.network), .liveNetwork, .timeLimit(.minutes(5)))
    func enclaveAccountCanReceiveAndSendOnShadownet() async throws {
        let enclave: any EnclaveKeyService = SecureEnclave.isAvailable ? SecureEnclaveKeys(requiresUserPresence: false) : SoftwareEnclaveKeys()
        let bridge = TaquitoBridge(systemLog: { _ in })
        bridge.enclave = enclave
        let pair = try enclave.create()
        let publicKey = Base58.checkEncode(prefix: TezosPrefix.p2pk, payload: Array(pair.publicKey))
        let address = Address(try #require(try await bridge.call("addressFromPublicKey", [publicKey]).stringValue))
        let wallet = Wallet(alias: "enclave-test", address: address, scheme: .tz3, publicKey: publicKey, keyKind: .enclave, enclaveKey: pair.key)

        let faucet = FaucetService(baseURL: Network.shadownet.faucetURL!)
        #expect(try await faucet.requestTez(to: address, amount: 2).hasPrefix("o"))
        let chain = TaquitoChainService(network: .shadownet, bridge: bridge)
        var funded = false
        for _ in 0..<24 {
            try await Task.sleep(for: .seconds(5))
            if let b = try? await chain.tezBalance(for: address), b.spendable > 0 { funded = true; break }
        }
        try #require(funded, "faucet transfer to the Enclave address never showed up")

        let destination = Address("tz1VSUr8wwNhLAzempoch5d6hLRiTh8Cjcjb")
        let signer = SigningKey.enclave(pair.key, publicKey: publicKey, address: address)
        // Twice: the first carries the reveal, and two signatures make a high-S slip less likely to hide.
        for round in 1...2 {
            let estimate = try await chain.estimateTransfer(from: wallet, to: destination, amount: Decimal(string: "0.3")!)
            let hash = try await chain.sendTransfer(from: wallet, signer: signer, to: destination, amount: Decimal(string: "0.3")!, limits: try #require(estimate.limits)).hash
            #expect(hash.hasPrefix("o"))
            let level = try await chain.waitForConfirmation(of: hash)
            #expect(level > 0)
            print("Enclave send \(round) on Shadownet confirmed in block \(level): \(hash)")
        }
    }
}
