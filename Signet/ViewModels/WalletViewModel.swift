import Foundation
import Observation

/// Drives the default screen. Owns the list of wallets, the selected one and everything loaded for it.
@MainActor
@Observable
final class WalletViewModel {
    enum WalletError: LocalizedError {
        case emptyAlias
        case aliasExists(String)
        case unsupportedScheme(AddressScheme)

        var errorDescription: String? {
            switch self {
            case .emptyAlias: "Give the wallet a name."
            case .aliasExists(let alias): "A wallet named “\(alias)” already exists."
            case .unsupportedScheme(let scheme): scheme.unavailableReason ?? "\(scheme.rawValue) is not supported yet."
            }
        }
    }

    /// Etherlink is not relevant yet; flip this to bring the row (icon, balance fetch) back.
    static let showsEtherlinkBalance = false

    private(set) var wallets: [Wallet]
    var selectedWalletID: Wallet.ID?
    var isPresentingCreateWallet = false
    var isPresentingRenameWallet = false

    private(set) var domains: [String] = []
    private(set) var assets: [AssetBalance] = []
    private(set) var nfts: [NFT] = []
    private(set) var isLoading = false
    private(set) var isCreatingWallet = false
    private(set) var errorMessage: String?

    /// The node the app talks to. Changing it swaps the chain service and reloads the dashboard.
    var network: Network {
        didSet {
            guard network != oldValue else { return }
            chain = chainFactory(network)
            state.networkName = network.name
            persistState()
            assets = []
            domains = []
            nfts = []
            Task { await refresh() }
        }
    }

    private var chain: any ChainService
    private let chainFactory: @Sendable (Network) -> any ChainService
    private let keyGenerator: KeyGenerator
    private let walletStore: any WalletStore
    private let stateStore: any AppStateStore
    private var state: AppState
    /// An octez-client directory to offer for import, or `nil` to never offer.
    private let importSource: URL?

    /// Number of octez-client aliases available to import, or 0 when there is nothing to offer.
    private(set) var importableWalletCount = 0

    /// - Parameters:
    ///   - chain: a fixed chain service (tests and previews). Ignored when `chainFactory` is given.
    ///   - chainFactory: builds the chain service for a network; the app passes `TaquitoChainService.init`.
    init(
        wallets: [Wallet]? = nil,
        chain: (any ChainService)? = nil,
        chainFactory: (@Sendable (Network) -> any ChainService)? = nil,
        keyGenerator: KeyGenerator = KeyGenerator(),
        walletStore: any WalletStore = InMemoryWalletStore(),
        importSource: URL? = nil,
        stateStore: any AppStateStore = InMemoryAppStateStore()
    ) {
        let factory: @Sendable (Network) -> any ChainService = chainFactory ?? { _ in chain ?? MockChainService() }
        let state = stateStore.load()
        self.stateStore = stateStore
        self.state = state
        let network = Network.named(state.networkName) ?? .mainnet
        self.network = network
        self.chainFactory = factory
        self.chain = factory(network)
        self.keyGenerator = keyGenerator
        self.walletStore = walletStore
        self.importSource = importSource

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
        // Restore the wallet that was showing last time, if it still exists.
        let remembered = state.selectedWalletAlias
        self.selectedWalletID = loaded.first { $0.alias == remembered }?.id ?? loaded.first?.id
        self.errorMessage = loadError
        self.importableWalletCount = Self.countImportable(at: importSource, excluding: loaded)
    }

    var selectedWallet: Wallet? {
        wallets.first { $0.id == selectedWalletID } ?? wallets.first
    }

    /// Re-reads the store, e.g. after octez-client added a key.
    func reloadWallets() {
        do {
            wallets = try walletStore.load()
            if selectedWallet == nil { selectedWalletID = wallets.first?.id }
            Task { await refresh() }
        } catch {
            errorMessage = "Could not load wallets: \(error.localizedDescription)"
        }
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
            async let tokens = chain.tokenBalances(for: address)
            async let names = chain.domains(for: address)
            async let collectibles = chain.nfts(for: address)

            let tezBalance = try await tez
            var list = [AssetBalance(id: "tez", kind: .tez, name: "Tezos", symbol: "tz", amount: tezBalance.total, details: tezBalance.breakdown)]
            if Self.showsEtherlinkBalance {
                let etherlink = try await chain.etherlinkBalance(for: address)
                list.append(AssetBalance(id: "etherlink", kind: .etherlink, name: "Etherlink", symbol: "tz", amount: etherlink))
            }
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
        rememberSelection()
        domains = []
        assets = []
        nfts = []
        Task { await refresh() }
    }

    /// Generates a key for `scheme`, writes it to the store, and adds and selects the new wallet.
    func createWallet(alias: String, scheme: AddressScheme) async throws {
        let name = alias.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw WalletError.emptyAlias }
        guard !wallets.contains(where: { $0.alias == name }) else { throw WalletError.aliasExists(name) }
        guard scheme.isSupported else { throw WalletError.unsupportedScheme(scheme) }

        isCreatingWallet = true
        defer { isCreatingWallet = false }

        let material = try await keyGenerator.generate(scheme: scheme)
        let wallet = Wallet(alias: name, address: Address(material.address), scheme: scheme,
                            publicKey: material.publicKey, keyKind: .unencrypted)
        try walletStore.add(wallet, secretKey: material.secretKey)
        wallets = (try? walletStore.load()) ?? wallets + [wallet]
        select(wallet)
    }

    /// Copies wallets from the octez-client directory into Signet's own. Returns how many were added.
    @discardableResult
    func importFromOctezClient() throws -> Int {
        guard let importSource else { return 0 }
        let added = try walletStore.importWallets(from: importSource)
        wallets = try walletStore.load()
        if selectedWallet == nil { selectedWalletID = wallets.first?.id }
        importableWalletCount = Self.countImportable(at: importSource, excluding: wallets)
        Task { await refresh() }
        return added
    }

    /// Aliases in `source` that are not already in `existing`.
    private static func countImportable(at source: URL?, excluding existing: [Wallet]) -> Int {
        guard let source else { return 0 }
        let store = TezosClientStore(directory: source)
        guard store.hasWallets, let candidates = try? store.load() else { return 0 }
        let known = Set(existing.map(\.alias))
        return candidates.filter { !known.contains($0.alias) }.count
    }

    /// Renames the selected wallet's alias in the store and keeps it selected.
    func renameSelectedWallet(to newAlias: String) throws {
        guard let wallet = selectedWallet else { return }
        let name = newAlias.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw WalletError.emptyAlias }
        guard name != wallet.alias else { return }
        guard !wallets.contains(where: { $0.alias == name }) else { throw WalletError.aliasExists(name) }

        try walletStore.rename(alias: wallet.alias, to: name)
        wallets = try walletStore.load()
        selectedWalletID = name
        rememberSelection()
    }

    private func rememberSelection() {
        state.selectedWalletAlias = selectedWalletID
        persistState()
    }

    private func persistState() {
        do {
            try stateStore.save(state)
        } catch {
            NSLog("Signet: could not save state: %@", error.localizedDescription)
        }
    }

    static let sampleWallets = [
        Wallet(alias: "MyWallet", address: Address("tz1VSUr8wwNhLAzempoch5d6hLRiTh8Cjcjb"), keyKind: .unencrypted),
        Wallet(alias: "Savings", address: Address("tz2BFTyPeYRzxd5aiBchbXN3WCZhx7BqbMBq"), keyKind: .encrypted),
    ]

    static func preview() -> WalletViewModel {
        WalletViewModel(wallets: sampleWallets, chain: MockChainService())
    }
}
