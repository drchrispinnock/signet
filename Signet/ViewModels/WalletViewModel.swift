import Foundation
import Observation

/// Drives the default screen. Owns the list of wallets, the selected one and everything loaded for it.
@MainActor
@Observable
final class WalletViewModel {
    enum WalletError: LocalizedError {
        case emptyAlias
        case unsupportedScheme(AddressScheme)

        var errorDescription: String? {
            switch self {
            case .emptyAlias: "Give the address a name."
            case .unsupportedScheme(let scheme): scheme.unavailableReason ?? "\(scheme.rawValue) is not supported yet."
            }
        }
    }

    private(set) var wallets: [Wallet]
    var selectedWalletID: Wallet.ID?
    var isPresentingCreateWallet = false

    private(set) var domains: [String] = []
    private(set) var assets: [AssetBalance] = []
    private(set) var nfts: [NFT] = []
    private(set) var isLoading = false
    private(set) var isCreatingWallet = false
    private(set) var errorMessage: String?

    private let chain: any ChainService
    private let keyGenerator: KeyGenerator
    private let secretKeys: any SecretKeyStore
    private let walletStore: any WalletStore

    init(
        wallets: [Wallet]? = nil,
        chain: any ChainService,
        keyGenerator: KeyGenerator = KeyGenerator(),
        secretKeys: any SecretKeyStore = InMemorySecretKeyStore(),
        walletStore: any WalletStore = InMemoryWalletStore()
    ) {
        self.chain = chain
        self.keyGenerator = keyGenerator
        self.secretKeys = secretKeys
        self.walletStore = walletStore

        var loadError: String?
        let loaded: [Wallet]
        if let wallets {
            loaded = wallets
        } else {
            do {
                loaded = try walletStore.load()
            } catch {
                loaded = []
                loadError = "Could not load wallets: \(error.localizedDescription)"
            }
        }
        self.wallets = loaded
        self.selectedWalletID = loaded.first?.id
        self.errorMessage = loadError
    }

    var selectedWallet: Wallet? {
        wallets.first { $0.id == selectedWalletID } ?? wallets.first
    }

    func refresh() async {
        guard let wallet = selectedWallet else {
            assets = []
            domains = []
            nfts = []
            return
        }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        let address = wallet.address
        do {
            async let tez = chain.tezBalance(for: address)
            async let etherlink = chain.etherlinkBalance(for: address)
            async let tokens = chain.tokenBalances(for: address)
            async let names = chain.domains(for: address)
            async let collectibles = chain.nfts(for: address)

            var list: [AssetBalance] = [
                AssetBalance(id: "tez", kind: .tez, name: "Tezos", symbol: "tz", amount: try await tez),
                AssetBalance(id: "etherlink", kind: .etherlink, name: "Etherlink", symbol: "tz", amount: try await etherlink),
            ]
            list.append(contentsOf: try await tokens)

            // Drop the results if the user switched wallets while we were loading.
            guard address == selectedWallet?.address else { return }
            assets = list
            domains = try await names
            nfts = try await collectibles
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func select(_ wallet: Wallet) {
        guard wallet.id != selectedWalletID else { return }
        selectedWalletID = wallet.id
        domains = []
        assets = []
        nfts = []
        Task { await refresh() }
    }

    /// Generates a key for `scheme`, stores the secret, and adds and selects the new wallet.
    func createWallet(alias: String, scheme: AddressScheme) async throws {
        let name = alias.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw WalletError.emptyAlias }
        guard scheme.isSupported else { throw WalletError.unsupportedScheme(scheme) }

        isCreatingWallet = true
        defer { isCreatingWallet = false }

        let material = try await keyGenerator.generate(scheme: scheme)
        let address = Address(material.address)
        try secretKeys.store(material.secretKey, for: address)

        let wallet = Wallet(alias: name, address: address, scheme: scheme, publicKey: material.publicKey)
        var updated = wallets
        updated.append(wallet)
        do {
            try walletStore.save(updated)
        } catch {
            // Keep the key store consistent with the wallet list.
            try? secretKeys.delete(for: address)
            throw error
        }
        wallets = updated
        select(wallet)
    }

    static let sampleWallets = [
        Wallet(alias: "MyWallet", address: Address("tz1VSUr8wwNhLAzempoch5d6hLRiTh8Cjcjb")),
        Wallet(alias: "Savings", address: Address("tz2BFTyPeYRzxd5aiBchbXN3WCZhx7BqbMBq")),
    ]

    static func preview() -> WalletViewModel {
        WalletViewModel(wallets: sampleWallets, chain: MockChainService())
    }
}
