import Foundation
import Observation

/// Drives the default screen. Owns the list of wallets, the selected one and everything loaded for it.
@MainActor
@Observable
final class WalletViewModel {
    enum WalletError: LocalizedError {
        case emptyAlias
        case aliasExists(String)
        case addressExists(String)
        case invalidAddress
        case unsupportedScheme(AddressScheme)
        case passphraseTooShort

        var errorDescription: String? {
            switch self {
            case .emptyAlias: "Give the wallet a name."
            case .aliasExists(let alias): "A wallet named “\(alias)” already exists."
            case .addressExists(let alias): "That address is already in the list as “\(alias)”."
            case .invalidAddress: "That is not a valid Tezos address."
            case .passphraseTooShort: "Use a password of at least \(WalletViewModel.minimumPassphraseLength) characters."
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
    var isPresentingReceive = false
    var isPresentingAddAddress = false
    var isPresentingSend = false
    var isPresentingConnectDApp = false
    var isPresentingFaucet = false

    /// dApp connections over Octez Connect (TZIP-10).
    private(set) var dapps: DAppConnectionManager!

    private(set) var domains: [String] = []
    private(set) var assets: [AssetBalance] = []
    private(set) var tezBalance: TezBalance?
    private(set) var nfts: [NFT] = []
    private(set) var transactions: [TezosTransaction] = []
    static let recentTransactionLimit = 25

    enum ActivityTab: String, CaseIterable, Identifiable {
        case transactions = "Recent transactions"
        case nfts = "NFTs"
        var id: String { rawValue }
    }
    var activityTab: ActivityTab = .transactions
    private(set) var isLoading = false
    /// True when the node has no record of the selected address (never funded on this network).
    private(set) var accountNotOnChain = false

    enum FaucetStatus: Equatable {
        case idle
        case solving(done: Int, total: Int)
        case sent(hash: String)
        case received(hash: String)
        case failed(String)
    }
    private(set) var faucetStatus: FaucetStatus = .idle
    static let faucetAmountTez: Double = 100
    private(set) var isCreatingWallet = false
    private(set) var errorMessage: String?

    /// Watches the configured node for the status bar.
    let nodeMonitor: NodeMonitor

    /// The network and node the app talks to. Changing either swaps the chain service and
    /// reloads the dashboard. Assign a `Network` straight from `Network.all` to use its default
    /// node; `switchNetwork(to:)` applies the custom node saved for it, if any.
    var network: Network {
        didSet {
            guard network != oldValue else { return }
            nodeMonitor.network = network
            chain = chainFactory(network)
            state.networkName = network.name
            var nodeURLs = state.nodeURLs ?? [:]
            nodeURLs[network.name] = network.isUsingDefaultNode ? nil : network.rpcURL.absoluteString
            state.nodeURLs = nodeURLs.isEmpty ? nil : nodeURLs
            persistState()
            assets = []
            domains = []
            nfts = []
            Task { await refresh() }
        }
    }

    /// `base` with the custom node the user saved for it, or `base` itself.
    func resolved(_ base: Network) -> Network {
        Self.resolve(base, in: state)
    }

    private static func resolve(_ base: Network, in state: AppState) -> Network {
        guard let saved = state.nodeURLs?[base.name], let url = Network.nodeURL(from: saved) else { return base }
        return base.usingNode(url)
    }

    /// Switches to another network, talking to whatever node was last set for it.
    func switchNetwork(to base: Network) {
        network = resolved(base)
    }

    /// Points the current network at the node typed in Settings. False (and no change) when
    /// the text is not a host or http(s) URL.
    @discardableResult
    func setNode(_ text: String) -> Bool {
        setNode(text, for: network)
    }

    /// Goes back to the node we ship for the current network.
    func useDefaultNode() {
        useDefaultNode(for: network)
    }

    /// The node in use (saved or default) for any network, without switching to it.
    func nodeURL(for base: Network) -> URL {
        resolved(Network.named(base.name) ?? base).rpcURL
    }

    /// Saves the node for `base`. Applies immediately if `base` is the network in use.
    @discardableResult
    func setNode(_ text: String, for base: Network) -> Bool {
        guard let url = Network.nodeURL(from: text) else { return false }
        let template = Network.named(base.name) ?? base
        if base.name == network.name {
            network = template.usingNode(url)      // didSet persists it
        } else {
            var nodeURLs = state.nodeURLs ?? [:]
            nodeURLs[base.name] = url == template.defaultRPCURL ? nil : url.absoluteString
            state.nodeURLs = nodeURLs.isEmpty ? nil : nodeURLs
            persistState()
        }
        return true
    }

    /// Goes back to the shipped node for `base`.
    func useDefaultNode(for base: Network) {
        let template = Network.named(base.name) ?? base
        if base.name == network.name {
            network = template.usingNode(template.defaultRPCURL)
        } else {
            var nodeURLs = state.nodeURLs ?? [:]
            nodeURLs[base.name] = nil
            state.nodeURLs = nodeURLs.isEmpty ? nil : nodeURLs
            persistState()
        }
    }

    private var chain: any ChainService
    private let chainFactory: @Sendable (Network) -> any ChainService

    /// The directory the wallet files live in, when the stores are file-backed.
    private(set) var walletDirectory: URL?
    private let directorySettings: WalletDirectorySettings?
    private let backupSettings: BackupSettings?

    /// Result of the most recent backup attempt, for Settings.
    private(set) var lastBackup: (date: Date, outcome: WalletBackup.Outcome)?
    private(set) var lastBackupError: String?
    var backupDirectory: URL? { backupSettings?.directory }
    var backupGenerations: Int { backupSettings?.generations ?? BackupSettings.defaultGenerations }
    var isUsingDefaultBackupDirectory: Bool {
        guard let backupSettings else { return true }
        return backupSettings.directory.standardizedFileURL == backupSettings.defaultDirectory.standardizedFileURL
    }
    var defaultBackupDirectory: URL? { backupSettings?.defaultDirectory }
    private let storeFactory: (@Sendable (URL) -> (wallets: any WalletStore, state: any AppStateStore))?
    private let keyGenerator: KeyGenerator
    private var walletStore: any WalletStore
    private var stateStore: any AppStateStore
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
        stateStore: any AppStateStore = InMemoryAppStateStore(),
        directorySettings: WalletDirectorySettings? = nil,
        storeFactory: (@Sendable (URL) -> (wallets: any WalletStore, state: any AppStateStore))? = nil,
        backupSettings: BackupSettings? = nil,
        nodeProbe: NodeMonitor.Probe? = nil,
        dappStorage: (any BridgeStorage)? = nil,
        startDApps: Bool = false
    ) {
        self.backupSettings = backupSettings
        let factory: @Sendable (Network) -> any ChainService = chainFactory ?? { _ in chain ?? MockChainService() }
        // File-backed mode: build both stores for the configured directory.
        var walletStore = walletStore
        var stateStore = stateStore
        var directory: URL?
        if let directorySettings, let storeFactory {
            directory = directorySettings.current
            let stores = storeFactory(directory!)
            walletStore = stores.wallets
            stateStore = stores.state
        }
        self.walletDirectory = directory
        self.directorySettings = directorySettings
        self.storeFactory = storeFactory
        let state = stateStore.load()
        self.stateStore = stateStore
        self.state = state
        let network = Self.resolve(Network.named(state.networkName) ?? .mainnet, in: state)
        self.network = network
        self.nodeMonitor = NodeMonitor(network: network, probe: nodeProbe)
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

        // Startup backup of the key files.
        Task { await backUp() }

        self.dapps = DAppConnectionManager(
            storage: dappStorage ?? InMemoryBridgeStorage(),
            wallets: { [unowned self] in self.wallets },
            secretKey: { [unowned self] wallet in try self.walletStore.secretKey(for: wallet) }
        )
        if startDApps, !self.wallets.isEmpty {
            Task { await dapps.start() }
        }
    }

    /// Copies the wallet files to the backup directory, keeping the configured number of generations.
    /// Runs off the main actor; results land in `lastBackup` / `lastBackupError`.
    func backUp(force: Bool = false) async {
        guard let backupSettings, let walletDirectory else { return }
        let job = WalletBackup(walletDirectory: walletDirectory, backupDirectory: backupSettings.directory, generations: backupSettings.generations)
        do {
            let outcome = try await Task.detached(priority: .utility) { try job.run(force: force) }.value
            lastBackup = (Date(), outcome)
            lastBackupError = nil
        } catch {
            lastBackupError = error.localizedDescription
            NSLog("Signet: backup failed: %@", error.localizedDescription)
        }
    }

    func setBackupDirectory(_ url: URL) {
        backupSettings?.setDirectory(url)
        Task { await backUp() }
    }

    func setBackupGenerations(_ count: Int) {
        backupSettings?.setGenerations(count)
        Task { await backUp() }
    }

    var selectedWallet: Wallet? {
        wallets.first { $0.id == selectedWalletID } ?? wallets.first
    }

    /// Points the app at a different wallet directory: rebuilds the stores, reloads the wallets and
    /// restores whatever that directory remembers. The choice is kept in preferences.
    func changeWalletDirectory(to url: URL) {
        guard let storeFactory, let directorySettings else { return }
        let directory = url.standardizedFileURL
        guard directory != walletDirectory?.standardizedFileURL else { return }
        directorySettings.set(directory)
        let stores = storeFactory(directory)
        walletStore = stores.wallets
        stateStore = stores.state
        walletDirectory = directory
        state = stateStore.load()

        do {
            wallets = try walletStore.load()
            errorMessage = nil
        } catch {
            wallets = []
            errorMessage = "Could not load wallets: \(error.localizedDescription)"
        }
        selectedWalletID = wallets.first { $0.alias == state.selectedWalletAlias }?.id ?? wallets.first?.id
        if let remembered = Network.named(state.networkName) { switchNetwork(to: remembered) }
        importableWalletCount = Self.countImportable(at: importSource, excluding: wallets)
        assets = []
        domains = []
        nfts = []
        Task { await refresh() }
        Task { await backUp() }
    }

    var isUsingDefaultWalletDirectory: Bool {
        guard let directorySettings, let walletDirectory else { return true }
        return walletDirectory.standardizedFileURL == directorySettings.defaultDirectory.standardizedFileURL
    }

    var defaultWalletDirectory: URL? { directorySettings?.defaultDirectory }

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
        accountNotOnChain = false
        defer { isLoading = false }

        let address = wallet.address
        do {
            async let tez = chain.tezBalance(for: address)
            async let tokens = chain.tokenBalances(for: address)
            async let names = chain.domains(for: address)
            async let collectibles = chain.nfts(for: address)
            async let history = chain.recentTransactions(for: address, limit: Self.recentTransactionLimit)

            let tezBalance = try await tez
            var list = [AssetBalance(id: "tez", kind: .tez, name: "Tezos", symbol: "tz", amount: tezBalance.total, details: tezBalance.breakdown)]
            self.tezBalance = tezBalance
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
            transactions = try await history
        } catch ChainError.accountNotOnChain {
            guard address == selectedWallet?.address else { return }
            accountNotOnChain = true
            assets = []
            domains = (try? await chain.domains(for: address)) ?? []
            nfts = (try? await chain.nfts(for: address)) ?? []
            transactions = []
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
        transactions = []
        tezBalance = nil
        accountNotOnChain = false
        faucetStatus = .idle
        Task { await refresh() }
    }

    nonisolated static let minimumPassphraseLength = 8

    /// A default alias that is not already taken: "My Wallet", then "My Wallet 2", "My Wallet 3", …
    func suggestedAlias(base: String = "My Wallet") -> String {
        let taken = Set(wallets.map { $0.alias.lowercased() })
        if !taken.contains(base.lowercased()) { return base }
        var n = 2
        while taken.contains("\(base) \(n)".lowercased()) { n += 1 }
        return "\(base) \(n)"
    }

    /// Generates a key for `scheme`, writes it to the store (encrypted with `passphrase` when given),
    /// and adds and selects the new wallet.
    func createWallet(alias: String, scheme: AddressScheme, passphrase: String? = nil) async throws {
        let name = alias.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw WalletError.emptyAlias }
        guard !wallets.contains(where: { $0.alias == name }) else { throw WalletError.aliasExists(name) }
        guard scheme.isSupported else { throw WalletError.unsupportedScheme(scheme) }

        isCreatingWallet = true
        defer { isCreatingWallet = false }

        if let passphrase, passphrase.count < Self.minimumPassphraseLength { throw WalletError.passphraseTooShort }
        let material = try await keyGenerator.generate(scheme: scheme)
        var secretKey = material.secretKey
        var kind = KeyKind.unencrypted
        if let passphrase {
            secretKey = try await keyGenerator.encrypt(secretKey: material.secretKey, passphrase: passphrase)
            kind = .encrypted
        }
        let wallet = Wallet(alias: name, address: Address(material.address), scheme: scheme,
                            publicKey: material.publicKey, keyKind: kind)
        try walletStore.add(wallet, secretKey: secretKey)
        wallets = (try? walletStore.load()) ?? wallets + [wallet]
        select(wallet)
        await backUp()
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

    /// Adds an address book entry: an alias for an address we hold no key for.
    func addWatchOnlyWallet(alias: String, address rawAddress: String) async throws {
        let name = alias.trimmingCharacters(in: .whitespacesAndNewlines)
        let address = Address(rawAddress.trimmingCharacters(in: .whitespacesAndNewlines))
        guard !name.isEmpty else { throw WalletError.emptyAlias }
        guard address.isValidAccount else { throw WalletError.invalidAddress }
        guard !wallets.contains(where: { $0.alias == name }) else { throw WalletError.aliasExists(name) }
        if let existing = wallets.first(where: { $0.address == address }) { throw WalletError.addressExists(existing.alias) }

        let wallet = Wallet(alias: name, address: address, keyKind: .none)
        try walletStore.addWatchOnly(wallet)
        wallets = (try? walletStore.load()) ?? wallets + [wallet]
        select(wallet)
        await backUp()
    }

    /// Asks the current testnet's faucet to fund the selected address, then polls until the
    /// account appears on chain.
    func requestTestTez(amount: Double = WalletViewModel.faucetAmountTez) async {
        guard let wallet = selectedWallet, let service = FaucetService(network: network) else { return }
        let address = wallet.address
        faucetStatus = .solving(done: 0, total: 1)
        do {
            let hash = try await Task.detached(priority: .userInitiated) {
                try await service.requestTez(to: address, amount: amount) { done, total in
                    Task { @MainActor in
                        if case .solving = self.faucetStatus { self.faucetStatus = .solving(done: done, total: total) }
                    }
                }
            }.value
            faucetStatus = .sent(hash: hash)
            // The faucet's transfer needs a block; refresh until the balance moves (or give up quietly).
            let before = tezBalance?.spendable ?? 0
            for _ in 0..<12 where selectedWallet?.address == address {
                try? await Task.sleep(for: .seconds(5))
                await refresh()
                if !accountNotOnChain, (tezBalance?.spendable ?? 0) > before { faucetStatus = .received(hash: hash); break }
            }
        } catch {
            faucetStatus = .failed(error.localizedDescription)
        }
    }

    /// The live chain service, for flows that run their own lookups (Send).
    var chainService: any ChainService { chain }

    /// The clear-text secret key for one of our wallets, read from the store on demand.
    func secretKey(for wallet: Wallet) throws -> String? {
        try walletStore.secretKey(for: wallet)
    }

    /// How to label an address in lists: our own alias (verified), else the indexer's name, else the
    /// shortened address. The flag says whether the name came from our records.
    func displayName(for address: Address, indexerAlias: String?) -> (name: String, isOurs: Bool) {
        if let mine = wallets.first(where: { $0.address == address }) { return (mine.alias, true) }
        if let alias = indexerAlias, !alias.isEmpty { return (alias, false) }
        return (address.shortened(), false)
    }

    /// The TzProfiles name (via TzKT, always mainnet) for any address, or `nil` if it has none.
    func profileName(for address: Address) async -> String? {
        let name = (try? await chain.accountProfile(for: address))??.name?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (name?.isEmpty ?? true) ? nil : name
    }

    /// Tezos Domains names for any address, for previews while typing.
    func domainNames(for address: Address) async -> [String] {
        (try? await chain.domains(for: address)) ?? []
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
        Task { await backUp() }
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
