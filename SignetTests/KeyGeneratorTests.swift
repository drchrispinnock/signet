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
    @Test(arguments: [AddressScheme.tz1, .tz2, .tz3, .tz4, .tz5])
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
            .tz1: ("edsk", "edpk"), .tz2: ("spsk", "sppk"), .tz3: ("p2sk", "p2pk"), .tz4: ("BLsk", "BLpk"), .tz5: ("mdsk", "mdpk"),
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

    @Test(arguments: [AddressScheme.tz6])
    func refusesPostQuantumSchemes(scheme: AddressScheme) async {
        await #expect(throws: KeyGenerator.KeyError.self) {
            _ = try await KeyGenerator().generate(scheme: scheme)
        }
    }
}

@MainActor
struct WalletCreationTests {
    @Test func createWalletStoresKeyAndSelectsIt() async throws {
        let store = InMemoryWalletStore()
        let model = WalletViewModel(chain: MockChainService(), walletStore: store)
        #expect(model.wallets.isEmpty)
        #expect(model.selectedWallet == nil)

        try await model.createWallet(alias: "  Savings ", scheme: .tz3)

        let wallet = try #require(model.selectedWallet)
        #expect(wallet.alias == "Savings")
        #expect(wallet.scheme == .tz3)
        #expect(wallet.keyKind == .unencrypted)
        #expect(wallet.address.value.hasPrefix("tz3"))
        #expect(wallet.publicKey?.hasPrefix("p2pk") == true)
        #expect(try store.secretKey(for: wallet)?.hasPrefix("p2sk") == true)
        #expect(try store.load() == [wallet])
    }

    @Test func rejectsEmptyAliasDuplicatesAndUnsupportedSchemes() async throws {
        let model = WalletViewModel(chain: MockChainService())
        await #expect(throws: WalletViewModel.WalletError.self) {
            try await model.createWallet(alias: "   ", scheme: .tz1)
        }
        await #expect(throws: WalletViewModel.WalletError.self) {
            try await model.createWallet(alias: "Quantum", scheme: .tz6)
        }
        try await model.createWallet(alias: "Main", scheme: .tz1)
        await #expect(throws: WalletViewModel.WalletError.self) {
            try await model.createWallet(alias: "Main", scheme: .tz1)
        }
        #expect(model.wallets.count == 1)
    }
}

@MainActor
struct WalletRenameTests {
    @Test func renameUpdatesStoreAndKeepsSelection() async throws {
        let store = InMemoryWalletStore()
        let model = WalletViewModel(chain: MockChainService(), walletStore: store)
        try await model.createWallet(alias: "Main", scheme: .tz1)
        try await model.createWallet(alias: "Savings", scheme: .tz1)
        let savings = try #require(model.selectedWallet)
        #expect(savings.alias == "Savings")

        try model.renameSelectedWallet(to: " Rainy Day ")

        #expect(model.selectedWallet?.alias == "Rainy Day")
        #expect(model.selectedWallet?.address == savings.address)
        #expect(try store.load().map(\.alias) == ["Main", "Rainy Day"])
        #expect(try store.secretKey(for: model.selectedWallet!) != nil)

        #expect(throws: WalletViewModel.WalletError.self) { try model.renameSelectedWallet(to: "Main") }
        #expect(throws: WalletViewModel.WalletError.self) { try model.renameSelectedWallet(to: "  ") }
    }
}

@MainActor
struct SelectionPersistenceTests {
    @Test func restoresLastSelectedWalletAcrossLaunches() async throws {
        let defaults = InMemoryAppStateStore()
        let store = InMemoryWalletStore()
        let first = WalletViewModel(chain: MockChainService(), walletStore: store, stateStore: defaults)
        try await first.createWallet(alias: "Main", scheme: .tz1)
        try await first.createWallet(alias: "Savings", scheme: .tz1)
        let main = try #require(first.wallets.first { $0.alias == "Main" })
        first.select(main)
        #expect(first.selectedWallet?.alias == "Main")

        // "Relaunch": a new model over the same store and defaults.
        let second = WalletViewModel(chain: MockChainService(), walletStore: store, stateStore: defaults)
        #expect(second.selectedWallet?.alias == "Main")
    }

    @Test func followsRenamesAndFallsBackWhenAliasIsGone() async throws {
        let defaults = InMemoryAppStateStore()
        let store = InMemoryWalletStore()
        let first = WalletViewModel(chain: MockChainService(), walletStore: store, stateStore: defaults)
        try await first.createWallet(alias: "Main", scheme: .tz1)
        try await first.createWallet(alias: "Savings", scheme: .tz1)
        try first.renameSelectedWallet(to: "Rainy Day")

        let second = WalletViewModel(chain: MockChainService(), walletStore: store, stateStore: defaults)
        #expect(second.selectedWallet?.alias == "Rainy Day")

        // A remembered alias that no longer exists falls back to the first wallet.
        try defaults.save(AppState(selectedWalletAlias: "Vanished"))
        let third = WalletViewModel(chain: MockChainService(), walletStore: store, stateStore: defaults)
        #expect(third.selectedWallet?.alias == "Main")
    }
}

@MainActor
struct NetworkSettingsTests {
    /// A chain service that reports which network it was built for.
    struct Probe: TestChainService {
        let network: Network
        func tezBalance(for address: Address) async throws -> TezBalance { TezBalance(spendable: network == .mainnet ? 1 : 2) }
    }

    @Test func defaultsToMainnetAndSwitchingRebuildsTheChainService() async throws {
        let defaults = InMemoryAppStateStore()
        let model = WalletViewModel(wallets: WalletViewModel.sampleWallets,
                                    chainFactory: { Probe(network: $0) }, stateStore: defaults)
        #expect(model.network == .mainnet)
        await model.refresh()
        #expect(model.assets.first?.amount == 1)

        model.network = .shadownet
        await model.refresh()
        #expect(model.assets.first?.amount == 2)
        #expect(defaults.load().networkName == "Shadownet")
    }

    @Test func restoresTheChosenNetworkOnLaunch() {
        let defaults = InMemoryAppStateStore(AppState(networkName: "Shadownet"))
        let model = WalletViewModel(chain: MockChainService(), stateStore: defaults)
        #expect(model.network == .shadownet)

        try? defaults.save(AppState(networkName: "Nonsense"))
        #expect(WalletViewModel(chain: MockChainService(), stateStore: defaults).network == .mainnet)
    }
}
