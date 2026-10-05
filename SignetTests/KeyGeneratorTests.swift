import Foundation
import Testing
@testable import Signet

struct Base58Tests {
    @Test(arguments: [
        ([UInt8](), ""),
        ([0x61], "2g"),
        ([0x62, 0x62, 0x62], "a3gV"),
        ([0x00, 0x00, 0x00, 0x28, 0x7f, 0xb4, 0xcd], "111233QC4"),
    ])
    func encodesKnownVectors(bytes: [UInt8], expected: String) {
        #expect(Base58.encode(bytes) == expected)
    }
}

struct KeyGeneratorTests {
    /// Every supported scheme must produce a key that Taquito's own signer decodes to the same
    /// public key and address we recorded. For tz1/tz3 this proves the Swift base58 encoding.
    @Test(arguments: [AddressScheme.tz1, .tz2, .tz3, .tz4])
    func generatesKeysTaquitoAgreesWith(scheme: AddressScheme) async throws {
        let material = try await KeyGenerator().generate(scheme: scheme)

        #expect(material.scheme == scheme)
        #expect(material.address.hasPrefix(scheme.rawValue))
        #expect(try await TaquitoBridge.shared.call("isValidAddress", [material.address]) == .bool(true))

        let info = try await TaquitoBridge.shared.call("keyInfoFromSecretKey", [material.secretKey])
        #expect(info["publicKey"] == .string(material.publicKey))
        #expect(info["address"] == .string(material.address))
    }

    @Test func secretKeysUseTheExpectedPrefixes() async throws {
        let expected: [AddressScheme: (secret: String, public: String)] = [
            .tz1: ("edsk", "edpk"), .tz2: ("spsk", "sppk"), .tz3: ("p2sk", "p2pk"), .tz4: ("BLsk", "BLpk"),
        ]
        for (scheme, prefixes) in expected {
            let material = try await KeyGenerator().generate(scheme: scheme)
            #expect(material.secretKey.hasPrefix(prefixes.secret), "\(scheme)")
            #expect(material.publicKey.hasPrefix(prefixes.public), "\(scheme)")
        }
    }

    @Test func twoKeysAreNeverTheSame() async throws {
        let a = try await KeyGenerator().generate(scheme: .tz1)
        let b = try await KeyGenerator().generate(scheme: .tz1)
        #expect(a.address != b.address)
    }

    @Test(arguments: [AddressScheme.tz5, .tz6])
    func refusesPostQuantumSchemes(scheme: AddressScheme) async {
        await #expect(throws: KeyGenerator.KeyError.self) {
            _ = try await KeyGenerator().generate(scheme: scheme)
        }
    }
}

@MainActor
struct WalletCreationTests {
    @Test func createWalletStoresKeyAndSelectsIt() async throws {
        let secrets = InMemorySecretKeyStore()
        let store = InMemoryWalletStore()
        let model = WalletViewModel(chain: MockChainService(), secretKeys: secrets, walletStore: store)
        #expect(model.wallets.isEmpty)
        #expect(model.selectedWallet == nil)

        try await model.createWallet(alias: "  Savings ", scheme: .tz3)

        let wallet = try #require(model.selectedWallet)
        #expect(wallet.alias == "Savings")
        #expect(wallet.scheme == .tz3)
        #expect(wallet.address.value.hasPrefix("tz3"))
        #expect(wallet.publicKey?.hasPrefix("p2pk") == true)
        #expect(try secrets.secretKey(for: wallet.address)?.hasPrefix("p2sk") == true)
        #expect(try store.load() == [wallet])
    }

    @Test func rejectsEmptyAliasAndUnsupportedSchemes() async {
        let model = WalletViewModel(chain: MockChainService())
        await #expect(throws: WalletViewModel.WalletError.self) {
            try await model.createWallet(alias: "   ", scheme: .tz1)
        }
        await #expect(throws: WalletViewModel.WalletError.self) {
            try await model.createWallet(alias: "Quantum", scheme: .tz5)
        }
        #expect(model.wallets.isEmpty)
    }
}
