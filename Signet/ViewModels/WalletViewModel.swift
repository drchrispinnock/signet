import Foundation
import Observation

/// Drives the default screen. Owns the list of wallets, the selected one and everything loaded for it.
@MainActor
@Observable
final class WalletViewModel {
    enum WalletError: LocalizedError, Equatable {
        case emptyAlias
        case aliasExists(String)
        case addressExists(String)
        case invalidAddress
        case unsupportedScheme(AddressScheme)
        case passphraseTooShort
        case directoryChanged
        case notEstimated
        case contextChanged
        case outcomeUnknown(String)

        var errorDescription: String? {
            switch self {
            case .emptyAlias: "Give the account a name."
            case .aliasExists(let alias): "An account named “\(alias)” already exists."
            case .addressExists(let alias): "That address is already in the list as “\(alias)”."
            case .invalidAddress: "That is not a valid Tezos address."
            case .passphraseTooShort: "Use a password of at least \(WalletViewModel.minimumPassphraseLength) characters."
            case .unsupportedScheme(let scheme): scheme.unavailableReason ?? "\(scheme.rawValue) is not supported yet."
            case .directoryChanged: "The wallet directory changed while this was being confirmed. Nothing was done; please try again."
            case .notEstimated: "The fee has not been estimated yet; wait for the estimate and try again."
            case .contextChanged: "The account, network or node changed since the fee was estimated. Nothing was sent; the estimate will be made again."
            case .outcomeUnknown(let hash): "The node did not confirm receiving operation \(hash.prefix(12))… and it has not appeared in a block yet. Check the explorer before trying again; do not repeat it blindly."
            }
        }
    }

    /// The Etherlink row of the dashboard: only on networks with Etherlink on and for keys the
    /// rollup accepts. An unreachable Etherlink node blanks this row alone, never the dashboard.
    private nonisolated static func etherlinkRow(for address: Address, on network: Network, chain: any ChainService) async -> AssetBalance? {
        guard network.hasL2, address.isUsableOnEtherlink else { return nil }
        do {
            return AssetBalance(id: "etherlink", kind: .etherlink, name: "Etherlink", symbol: "tz", amount: try await chain.etherlinkBalance(for: address))
        } catch {
            return AssetBalance(id: "etherlink", kind: .etherlink, name: "Etherlink", symbol: "tz", amount: 0, unavailable: "Etherlink balance unavailable: \(error.localizedDescription)")
        }
    }

    /// The Shielded row of the dashboard, under Etherlink (or tez), while the network has
    /// shielded transactions on: the wallet's unspent notes, found by scanning the rollup's
    /// commitment tree with its viewing keys (`WalletViewModel+Shielded.swift`). A network
    /// whose TzEL services Signet does not know shows the 0 placeholder.
    private nonisolated static func shieldedSnapshot(for address: Address, on network: Network, store: (any ShieldedWalletStore)?, rollup: (any ShieldedRollup)?, bridge: TaquitoBridge) async -> ShieldedSnapshot? {
        guard network.shieldedEnabled else { return nil }
        guard let store, let rollup, network.shielded != nil else { return ShieldedSnapshot(wallet: nil, pools: [], row: .shieldedPlaceholder) }
        return await scanShielded(store: store, account: address, rollup: rollup, bridge: bridge)
    }

    /// Every account: those from the wallet directory (accounts, address book, contracts), then
    /// the keys held for this session only. Assigning replaces the stored part.
    private(set) var wallets: [Wallet] {
        get { storedWallets + sessionWallets }
        set { storedWallets = newValue.filter { !$0.isSessionOnly } }
    }
    private var storedWallets: [Wallet]
    /// Paper keys imported for this run only: in memory, never in the directory or a backup.
    private(set) var sessionWallets: [Wallet] = []
    private let sessionKeys = SessionKeyStore()
    /// Named contracts (octez-client `contracts` aliases): the KT1 entries of the address book,
    /// which is where created and added multisigs go.
    var multisigContracts: [MultisigContract] {
        wallets.filter { $0.address.isContract }.map { MultisigContract(alias: $0.alias, address: $0.address) }
    }
    /// Multisig actions proposed here, with the signatures gathered so far (all networks).
    private(set) var multisigProposals: [MultisigProposal] = []
    var selectedWalletID: Wallet.ID?
    var isPresentingCreateWallet = false
    var isPresentingRenameWallet = false
    var isPresentingReceive = false
    var isPresentingAddAddress = false
    var isPresentingSend = false
    var isPresentingConnectDApp = false
    var isPresentingFaucet = false
    var isPresentingStaking = false
    var isPresentingBaking = false
    var isPresentingConnectLedger = false
    var isPresentingImportAccount = false
    var isPresentingExportKey = false
    var isPresentingForget = false
    var isPresentingRememberKey = false
    var isPresentingCreateMultisig = false
    var isPresentingAddMultisig = false
    var isPresentingSignMultisig = false
    /// What the Sign multisig sheet opens on when something else (the delegate row) asks for it.
    var signMultisigPreset: MultisigSheetPreset?
    var isPresentingSubmitMultisig = false
    /// A pairing code that arrived by URL, waiting for the Connect dApp sheet to pick it up.
    var pendingPairingCode: String?

    /// Handles a `signet://` link. Only TZIP-10 pairing links are understood; the code is handed
    /// to the Connect dApp sheet, which pairs and reports as if it had been pasted.
    func handleIncomingURL(_ url: URL) {
        guard let code = DAppPairingLink.code(from: url) else {
            errorMessage = "Signet does not understand that link."
            return
        }
        pendingPairingCode = code
        isPresentingConnectDApp = true
    }

    /// Export shows keys Signet holds on disk; Ledger and watch-only entries have nothing to show.
    var canExportSelectedKey: Bool { [.unencrypted, .encrypted].contains(selectedWallet?.keyKind) }
    var isPresentingGovernance = false
    var isPresentingBridge = false
    var isPresentingShield = false
    var isPresentingUnshield = false
    var isPresentingSendShielded = false
    var isPresentingShieldedAddress = false

    // Shielded tez (TzEL): `WalletViewModel+Shielded.swift` owns the flow; the state is here
    // because `@Observable` storage cannot live in an extension.
    /// The shielded wallet of the selected network, from its store, as of the last refresh.
    var shieldedWallet: ShieldedWallet?
    /// Its deposit pools with what the rollup holds for each.
    var shieldedPools: [ShieldedPoolStatus] = []
    /// Its unshields, with where each stands between the operator and layer 1.
    var shieldedWithdrawals: [ShieldedWithdrawalStatus] = []
    /// Its shielded transfers, until the rollup has applied them (then a week for the record).
    var shieldedTransfers: [ShieldedTransfer] = []
    /// What a shield in progress is doing, for the Shield sheet.
    var shieldProgress: ShieldProgress?
    /// Stores by directory and chain, so one wallet file is read and written through one store.
    var shieldedStores: [String: any ShieldedWalletStore] = [:]
    let shieldedStoreFactory: @Sendable (URL?, String) -> any ShieldedWalletStore
    let shieldedRollupFactory: @Sendable (ShieldedConfig) -> any ShieldedRollup
    /// The bridge the protocol primitives run in (`src/tzel.js`, `src/shield.js`).
    let shieldedBridge: TaquitoBridge
    /// How long a shield waits for the rollup to credit a deposit: this many polls, this far apart.
    var shieldedCreditPolls = 36
    var shieldedPollInterval: Duration = .seconds(5)
    var isPresentingNetworks = false
    var isPresentingBuy = false

    /// Governance is for bakers whose key we can sign with.
    var canGovern: Bool { selectedWallet?.keyKind.canSign == true && delegateInfo?.isBaker == true }

    /// dApp connections over Octez Connect (TZIP-10).
    private(set) var dapps: DAppConnectionManager!

    private(set) var domains: [String] = []
    private(set) var assets: [AssetBalance] = []
    /// Fungible (DeFi) tokens, shown on the Assets tab rather than in the balance list.
    private(set) var tokens: [AssetBalance] = []
    private(set) var tezBalance: TezBalance?
    private(set) var nfts: [NFT] = []
    /// Whether `tokens` and `nfts` are the whole story (S26).
    private(set) var portfolioState: Portfolio.State = .complete
    private(set) var transactions: [TezosTransaction] = []
    private(set) var delegateInfo: DelegateInfo?
    static let recentTransactionLimit = 25

    enum ActivityTab: String, CaseIterable, Identifiable {
        case transactions = "Recent transactions"
        case assets = "Assets"
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
    /// The faucet request in flight, so switching accounts (or the user) can cancel the proof of work.
    private var faucetTask: Task<Void, Never>?
    static let faucetAmountTez: Double = 100
    private(set) var isCreatingWallet = false
    private(set) var errorMessage: String?

    /// Watches the configured node for the status bar.
    let nodeMonitor: NodeMonitor
    /// Watches the Layer 2 Michelson node while the network has Layer 2 on; grey and idle otherwise.
    let l2Monitor: NodeMonitor

    /// The network and node the app talks to. Changing either swaps the chain service and
    /// reloads the dashboard. Assign a `Network` straight from `Network.all` to use its default
    /// node; `switchNetwork(to:)` applies the custom node saved for it, if any.
    var network: Network {
        didSet {
            guard network != oldValue else { return }
            nodeMonitor.network = network
            l2Monitor.network = network
            chain = chainFactory(network)
            state.networkName = network.name
            state.remember(network)
            persistState()
            clearChainData()
            Task { await refresh() }
        }
    }

    /// Everything on the dashboard that came from the chain for the previous context (S16).
    private func clearChainData() {
        operationGeneration = UUID()
        refreshGeneration += 1
        isLoading = false
        assets = []
        tokens = []
        domains = []
        nfts = []
        transactions = []
        delegateInfo = nil
        tezBalance = nil
        accountNotOnChain = false
        portfolioState = .complete
        faucetStatus = .idle
        shieldedWallet = nil
        shieldedPools = []
        shieldedWithdrawals = []
        shieldedTransfers = []
    }

    /// Which load is current. Every refresh captures the generation, the account, the network and
    /// the directory it started under and publishes nothing unless all four still hold (S16).
    private var operationGeneration = UUID()
    private var refreshGeneration = 0
    private struct RefreshContext: Equatable {
        let generation: Int
        let address: Address
        let network: Network
        let revision: UUID
    }
    private var currentContext: RefreshContext? {
        selectedWallet.map { RefreshContext(generation: refreshGeneration, address: $0.address, network: network, revision: walletDirectoryRevision) }
    }

    /// `base` with the node, Layer 2 settings and links the user saved for it (`AppState.resolved`).
    func resolved(_ base: Network) -> Network {
        state.resolved(base)
    }

    /// The link in use (saved or default) for `service` on `base`, without switching to it.
    func serviceURL(for service: Network.Service, in base: Network) -> URL? {
        resolved(Network.named(base.name) ?? base).url(for: service)
    }

    /// Points `service` on `base` at what the user typed, or turns it off for empty text.
    /// False (and no change) when the text is not a URL, or for a faucet on mainnet.
    @discardableResult
    func setServiceURL(_ text: String, for service: Network.Service, in base: Network) -> Bool {
        guard base.offers(service) else { return false }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        var url: URL?
        if !trimmed.isEmpty {
            guard let parsed = Network.nodeURL(from: trimmed) else { return false }
            url = parsed
        }
        change(base) { $0.using(url, for: service) }
        return true
    }

    /// Goes back to the link we ship for `service` on `base`.
    func useDefaultServiceURL(for service: Network.Service, in base: Network) {
        change(base) { $0.using($0.defaultURL(for: service), for: service) }
    }

    /// Whether the Etherlink balance is shown for `base` (saved or default), without switching.
    func isL2Enabled(for base: Network) -> Bool { resolved(Network.named(base.name) ?? base).l2Enabled }

    /// The Etherlink node in use for `base`, if it has one.
    func l2NodeURL(for base: Network) -> URL? { resolved(Network.named(base.name) ?? base).l2RPCURL }

    func setL2Enabled(_ enabled: Bool, for base: Network) {
        changeL2(of: base) { $0.usingL2(enabled: enabled, node: $0.l2RPCURL) }
    }

    /// Points `base`'s Etherlink at the node typed in Networks; false when it is not a URL.
    @discardableResult
    func setL2Node(_ text: String, for base: Network) -> Bool {
        guard let url = Network.nodeURL(from: text) else { return false }
        changeL2(of: base) { $0.usingL2(enabled: $0.l2Enabled, node: url) }
        return true
    }

    func useDefaultL2Node(for base: Network) {
        changeL2(of: base) { $0.usingL2(enabled: $0.l2Enabled, node: $0.l2DefaultRPCURL) }
    }

    private func changeL2(of base: Network, _ change: (Network) -> Network) { self.change(base, change) }

    /// Whether shielded transactions are on for `base` (saved or default), without switching.
    func isShieldedEnabled(for base: Network) -> Bool { resolved(Network.named(base.name) ?? base).shieldedEnabled }

    /// Turns shielded transactions on or off for `base`. Only the choice is kept for now.
    func setShieldedEnabled(_ enabled: Bool, for base: Network) {
        change(base) { $0.usingShielded(enabled: enabled) }
    }

    /// Applies a per-network change: through `network` (which persists and reloads) when
    /// `base` is in use, else straight into the saved state.
    private func change(_ base: Network, _ change: (Network) -> Network) {
        if base.name == network.name {
            network = change(network)
        } else {
            let changed = change(resolved(Network.named(base.name) ?? base))
            state.rememberL2(of: changed)
            state.rememberShielded(of: changed)
            state.rememberServices(of: changed)
            persistState()
        }
    }

    /// Switches to another network, talking to whatever node was last set for it.
    func switchNetwork(to base: Network) {
        network = resolved(base)
    }

    /// Points the current network at the node typed in Networks. False (and no change) when
    /// the text is not a host or http(s) URL.
    @discardableResult
    func setNode(_ text: String) -> Bool {
        setNode(text, for: network)
    }

    /// Goes back to the node we ship for the current network.
    func useDefaultNode() {
        useDefaultNode(for: network)
    }

    /// How the node monitors and `checkNode` reach a node; injectable for tests.
    private let nodeProbe: NodeMonitor.Probe

    /// Asks the node typed in Networks which chain it serves before it is adopted, so a node for
    /// the wrong network is warned about as it is entered, not only by the red status bar
    /// afterwards. Networks that pin no chain id (Weeklynet, Quantumnet, Custom) are `.unpinned`;
    /// `layer: .two` compares with the Etherlink chain. Nothing is changed by asking.
    func checkNode(_ text: String, for base: Network, layer: NodeMonitor.Layer = .one) async -> NodeIdentity {
        guard let url = Network.nodeURL(from: text) else { return .unchecked(reason: Network.nodeURLProblem(text)) }
        let template = Network.named(base.name) ?? base
        let expected = switch layer {
        case .one: template.expectedChainID
        case .two: template.expectedL2ChainID
        }
        return await NodeMonitor.identity(of: url, expectedChainID: expected, probe: nodeProbe)
    }

    /// The node in use (saved or default) for any network, without switching to it.
    func nodeURL(for base: Network) -> URL {
        resolved(Network.named(base.name) ?? base).rpcURL
    }

    /// Saves the node for `base`. Applies immediately if `base` is the network in use.
    @discardableResult
    func setNode(_ text: String, for base: Network) -> Bool {
        guard let url = Network.nodeURL(from: text) else { return false }
        if base.name == network.name {
            network = network.usingNode(url)
        } else {
            let template = Network.named(base.name) ?? base
            state.rememberNode(of: template.usingNode(url))
            persistState()
        }
        return true
    }

    /// Goes back to the shipped node for `base`.
    func useDefaultNode(for base: Network) {
        let template = Network.named(base.name) ?? base
        if base.name == network.name {
            network = network.usingNode(template.defaultRPCURL)
        } else {
            state.rememberNode(of: template)
            persistState()
        }
    }

    private var chain: any ChainService
    /// The chain service in use, for the flows kept in their own files (`WalletViewModel+Shielded.swift`).
    var currentChain: any ChainService { chain }
    private let chainFactory: @Sendable (Network) -> any ChainService

    /// The directory the wallet files live in, when the stores are file-backed.
    private(set) var walletDirectory: URL?
    private var walletDirectoryRevision = UUID()
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
    /// Builds the Octez Connect storage for a wallet directory: each directory is its own dApp
    /// session, with its own peers and grants (S08).
    private let dappStorageFactory: (@Sendable (URL) -> any BridgeStorage)?
    private let dappDiagnostics: Bool
    private let startsDApps: Bool
    private let keyGenerator: KeyGenerator
    /// Ledger discovery and key derivation.
    let ledger: any LedgerService
    /// Pasted secret keys and recovery phrases.
    let keyImporter: any KeyImporter
    private let multisigService: any MultisigService
    var multisig: any MultisigService { multisigService.forNetwork(network) }
    private var proposalStore: any MultisigProposalStore
    private(set) var isConnectingLedger = false
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
        ledger: any LedgerService = MockLedgerService(),
        keyImporter: any KeyImporter = MockKeyImporter(),
        multisig: any MultisigService = MockMultisigService(),
        proposalStore: (any MultisigProposalStore)? = nil,
        walletStore: any WalletStore = InMemoryWalletStore(),
        importSource: URL? = nil,
        stateStore: any AppStateStore = InMemoryAppStateStore(),
        directorySettings: WalletDirectorySettings? = nil,
        storeFactory: (@Sendable (URL) -> (wallets: any WalletStore, state: any AppStateStore))? = nil,
        backupSettings: BackupSettings? = nil,
        nodeProbe: NodeMonitor.Probe? = nil,
        dappStorage: (any BridgeStorage)? = nil,
        dappStorageFactory: (@Sendable (URL) -> any BridgeStorage)? = nil,
        dappDiagnostics: Bool = false,
        startDApps: Bool = false,
        shieldedStoreFactory: (@Sendable (URL?, String) -> any ShieldedWalletStore)? = nil,
        shieldedRollupFactory: (@Sendable (ShieldedConfig) -> any ShieldedRollup)? = nil,
        shieldedBridge: TaquitoBridge = .shared
    ) {
        self.backupSettings = backupSettings
        self.shieldedStoreFactory = shieldedStoreFactory ?? { _, _ in InMemoryShieldedWalletStore() }
        self.shieldedRollupFactory = shieldedRollupFactory ?? { config in RollupNodeService(config: config) }
        self.shieldedBridge = shieldedBridge
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
        let network = state.resolved(Network.named(state.networkName) ?? .mainnet)
        self.network = network
        self.nodeMonitor = NodeMonitor(network: network, probe: nodeProbe)
        self.l2Monitor = NodeMonitor(network: network, layer: .two, probe: nodeProbe)
        self.nodeProbe = nodeProbe ?? NodeMonitor.urlSessionProbe
        self.chainFactory = factory
        self.chain = factory(network)
        self.keyGenerator = keyGenerator
        self.ledger = ledger
        self.keyImporter = keyImporter
        self.multisigService = multisig
        let proposalStore = proposalStore ?? directory.map { FileMultisigProposalStore(directory: $0) } ?? InMemoryMultisigProposalStore()
        self.proposalStore = proposalStore
        self.walletStore = walletStore
        self.importSource = importSource
        self.multisigProposals = proposalStore.load()

        var loadError: String?
        let loaded: [Wallet]
        if let wallets {
            loaded = wallets
        } else {
            do {
                loaded = try walletStore.load()
            } catch {
                loaded = []
                loadError = "Could not load accounts: \(error.localizedDescription)"
            }
        }
        self.storedWallets = loaded
        // Restore the wallet that was showing last time, if it still exists.
        let remembered = state.selectedWalletAlias
        self.selectedWalletID = loaded.first { $0.alias == remembered }?.id ?? loaded.first?.id
        self.errorMessage = loadError
        self.importableWalletCount = Self.countImportable(at: importSource, excluding: loaded)

        self.dappStorageFactory = dappStorageFactory
        self.dappDiagnostics = dappDiagnostics
        self.startsDApps = startDApps

        // Startup backup of the key files.
        Task { await backUp() }

        self.dapps = makeDApps(storage: dappStorage ?? directory.flatMap { dappStorageFactory?($0) } ?? InMemoryBridgeStorage())
        if startDApps, !self.wallets.isEmpty {
            Task { await dapps.start() }
        }

        // A new head means balances or history may have moved; refresh (not while one is running).
        nodeMonitor.onNewHead = { [weak self] _ in
            guard let self, !self.isLoading, self.selectedWallet != nil else { return }
            Task { await self.refresh() }
        }
    }

    private func makeDApps(storage: any BridgeStorage) -> DAppConnectionManager {
        let bridge = TaquitoBridge(requirePublicEndpoints: true)
        bridge.operationJournal = TaquitoBridge.shared.operationJournal
        bridge.configureLog(at: TaquitoBridge.shared.configuredLogURL)
        return DAppConnectionManager(
            bridge: bridge, storage: storage,
            diagnostics: dappDiagnostics,
            wallets: { [unowned self] in self.wallets },
            signer: { [unowned self] wallet, passphrase in try self.signingKey(for: wallet, passphrase: passphrase) }
        )
    }

    /// A directory change ends the dApp session: the old client is stopped (its waiting requests
    /// aborted) and a new manager is built on the new directory's storage, so sessions paired
    /// under one wallet can never ask about another's accounts (S08).
    private func replaceDApps(for directory: URL) {
        let old: DAppConnectionManager = dapps
        old.invalidate()
        let fresh = makeDApps(storage: dappStorageFactory?(directory) ?? InMemoryBridgeStorage())
        dapps = fresh
        let start = startsDApps && !wallets.isEmpty
        Task {
            await old.stop()
            if start, self.dapps === fresh { await fresh.start() }
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
        walletDirectoryRevision = UUID()
        directorySettings.set(directory)
        let stores = storeFactory(directory)
        walletStore = stores.wallets
        stateStore = stores.state
        walletDirectory = directory
        state = stateStore.load()
        proposalStore = FileMultisigProposalStore(directory: directory)
        multisigProposals = proposalStore.load()

        do {
            wallets = try walletStore.load()
            errorMessage = nil
        } catch {
            wallets = []
            errorMessage = "Could not load accounts: \(error.localizedDescription)"
        }
        selectedWalletID = wallets.first { $0.alias == state.selectedWalletAlias }?.id ?? wallets.first?.id
        if let remembered = Network.named(state.networkName) { switchNetwork(to: remembered) }
        importableWalletCount = Self.countImportable(at: importSource, excluding: wallets)
        replaceDApps(for: directory)
        clearChainData()
        Task { await refresh() }
        Task { await backUp() }
    }

    var isUsingDefaultWalletDirectory: Bool {
        guard let directorySettings, let walletDirectory else { return true }
        return walletDirectory.standardizedFileURL == directorySettings.defaultDirectory.standardizedFileURL
    }

    var defaultWalletDirectory: URL? { directorySettings?.defaultDirectory }

    /// Loads the dashboard for the selected account. Everything is fetched into a local snapshot
    /// through the chain service captured at the start, and published in one step only if the
    /// account, network, directory and refresh generation are still the ones it was started for;
    /// a slow reply from a previous context can never land on the screen (S16). Two refreshes of
    /// the same context may both publish: both describe the same account on the same chain.
    func refresh() async {
        guard let mine = currentContext else {
            clearChainData()
            return
        }
        let chain = self.chain
        let address = mine.address
        let network = self.network
        if network.canShield { await adoptLegacyShieldedWallet() }
        guard currentContext == mine else { return }
        let shieldedStore = network.canShield ? shieldedStore(for: network.chain) : nil
        let shieldedRollup = network.shielded.map(shieldedRollupFactory)
        let shieldedBridge = self.shieldedBridge
        isLoading = true
        errorMessage = nil

        struct Snapshot {
            var tezBalance: TezBalance?
            var shielded: ShieldedSnapshot?
            var assets: [AssetBalance] = []
            var portfolio = Portfolio.empty
            var domains: [String] = []
            var transactions: [TezosTransaction] = []
            var delegateInfo: DelegateInfo?
            var notOnChain = false
            var error: String?
        }
        var snapshot = Snapshot()
        do {
            async let tez = chain.tezBalance(for: address)
            async let holdings = chain.portfolio(for: address)
            async let names = chain.domains(for: address)
            async let history = chain.recentTransactions(for: address, limit: Self.recentTransactionLimit)
            async let delegation = chain.delegateInfo(for: address)
            async let etherlink = Self.etherlinkRow(for: address, on: network, chain: chain)
            async let shielded = Self.shieldedSnapshot(for: address, on: network, store: shieldedStore, rollup: shieldedRollup, bridge: shieldedBridge)

            let tezBalance = try await tez
            var list = [AssetBalance(id: "tez", kind: .tez, name: "Tezos", symbol: "tz", amount: tezBalance.total, details: tezBalance.breakdown)]
            if let row = await etherlink { list.append(row) }
            if let shielded = await shielded { list.append(shielded.row); snapshot.shielded = shielded }
            snapshot.tezBalance = tezBalance
            snapshot.assets = list
            snapshot.portfolio = (try? await holdings) ?? Portfolio(tokens: [], nfts: [], state: .unavailable("Could not read the account's tokens."))
            snapshot.domains = try await names
            snapshot.transactions = try await history
            snapshot.delegateInfo = (try? await delegation) ?? nil
        } catch ChainError.accountNotOnChain {
            // Not on layer 1: no balance rows at all, the Etherlink one included.
            snapshot.notOnChain = true
            snapshot.portfolio = (try? await chain.portfolio(for: address)) ?? .empty
            snapshot.domains = (try? await chain.domains(for: address)) ?? []
        } catch {
            snapshot.error = error.localizedDescription
        }

        // Publish only into the context the load was started for.
        guard currentContext == mine else { return }
        isLoading = false
        if let error = snapshot.error {
            errorMessage = error
            return
        }
        tezBalance = snapshot.tezBalance
        assets = snapshot.assets
        if let shielded = snapshot.shielded {
            shieldedWallet = shielded.wallet
            shieldedPools = shielded.pools
            shieldedWithdrawals = shielded.withdrawals
            shieldedTransfers = shielded.transfers
        }
        portfolioState = snapshot.portfolio.state
        // An unavailable indexer keeps the last known lists (they are from this same context).
        if case .unavailable = snapshot.portfolio.state {} else {
            tokens = snapshot.portfolio.tokens
            nfts = snapshot.portfolio.nfts
        }
        domains = snapshot.domains
        transactions = snapshot.transactions
        delegateInfo = snapshot.delegateInfo
        accountNotOnChain = snapshot.notOnChain
    }

    func select(_ wallet: Wallet) {
        guard wallet.id != selectedWalletID else { return }
        selectedWalletID = wallet.id
        rememberSelection()
        cancelFaucetRequest()
        clearChainData()
        Task { await refresh() }
    }

    nonisolated static let minimumPassphraseLength = 8

    /// A default alias that is not already taken: "My Account", then "My Account 2", "My Account 3", …
    func suggestedAlias(base: String = "My Account") -> String {
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

    /// Removes the selected account from the key store (secret key included). Encrypted keys must
    /// be unlocked with `passphrase` first, so a key cannot be thrown away by someone who does not
    /// know its password. Earlier backups keep their copies.
    func forgetSelectedWallet(passphrase: String?) async throws {
        guard let wallet = selectedWallet else { throw WalletError.emptyAlias }
        if wallet.isSessionOnly {
            try await forgetSessionWallet(wallet, passphrase: passphrase)
            return
        }
        let revision = walletDirectoryRevision
        let store = walletStore
        let snapshot = try store.removalSnapshot(for: wallet)
        if wallet.keyKind == .encrypted {
            guard let passphrase, !passphrase.isEmpty else { throw SendViewModel.SendError.passphraseRequired }
            guard let stored = snapshot.secretKey else { throw SendViewModel.SendError.noSecretKey }
            _ = try await keyImporter.decrypt(secretKey: stored, passphrase: passphrase)
        }
        // Even switching away and back invalidates approval. The captured store checks all account
        // entries against the password-verified snapshot under the same lock as deletion.
        guard walletDirectoryRevision == revision else { throw WalletError.directoryChanged }
        try store.remove(wallet, matching: snapshot)
        wallets = (try? store.load()) ?? wallets.filter { $0.id != wallet.id }
        selectAfterRemoval()
        await backUp()
    }

    /// Drops a session-only key: wiped from memory now (it was never on disk). An encrypted one
    /// is opened first, as for a stored key, so the password proves the owner is asking. The
    /// entry is pinned before the password check and only that exact entry is removed after it
    /// (S07): a rename, replacement or re-import under the same alias in the meantime means
    /// nothing is removed.
    private func forgetSessionWallet(_ wallet: Wallet, passphrase: String?) async throws {
        guard let snapshot = try sessionKeys.removalSnapshot(for: wallet) else { throw SendViewModel.SendError.noSecretKey }
        if wallet.keyKind == .encrypted {
            guard let passphrase, !passphrase.isEmpty else { throw SendViewModel.SendError.passphraseRequired }
            _ = try await keyImporter.decrypt(secretKey: snapshot.secretKey, passphrase: passphrase)
        }
        try sessionKeys.remove(matching: snapshot)
        sessionWallets = sessionKeys.wallets
        selectAfterRemoval()
    }

    private func selectAfterRemoval() {
        if let next = wallets.first {
            select(next)
        } else {
            selectedWalletID = nil
            rememberSelection()
            domains = []; assets = []; tokens = []; nfts = []; transactions = []; delegateInfo = nil; tezBalance = nil
        }
    }

    /// What Export puts on screen: the clear key, and the encrypted form when that is how it is stored.
    struct ExportedKey: Equatable, Sendable {
        let clear: String
        let encrypted: String?
    }

    /// The selected account's secret key. Encrypted keys are opened with `passphrase`; a wrong one
    /// surfaces as `ChainError.wrongPassphrase`.
    func exportSecretKey(passphrase: String?) async throws -> ExportedKey {
        guard let wallet = selectedWallet else { throw WalletError.emptyAlias }
        guard let stored = try softwareSecret(for: wallet) else { throw SendViewModel.SendError.noSecretKey }
        switch wallet.keyKind {
        case .unencrypted:
            return ExportedKey(clear: stored, encrypted: nil)
        case .encrypted:
            guard let passphrase, !passphrase.isEmpty else { throw SendViewModel.SendError.passphraseRequired }
            return ExportedKey(clear: try await keyImporter.decrypt(secretKey: stored, passphrase: passphrase), encrypted: stored)
        default:
            throw SendViewModel.SendError.noSecretKey
        }
    }

    /// Adds an account from key material obtained elsewhere (a pasted key or a recovery phrase).
    /// Stores it clear, or encrypted with `storePassphrase`; an already-encrypted key is kept as is.
    /// With `keepForSession` the key is a paper key for this run only: held in memory (encrypted
    /// there too when a password is given), never written to the directory or a backup, and gone
    /// when Signet quits.
    func importAccount(alias: String, material: KeyMaterial, alreadyEncrypted: Bool = false, storePassphrase: String? = nil, keepForSession: Bool = false) async throws {
        let name = alias.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw WalletError.emptyAlias }
        try requireFree(alias: name, address: material.address)

        var secretKey = material.secretKey
        var kind: KeyKind = alreadyEncrypted ? .encrypted : .unencrypted
        if !alreadyEncrypted, let storePassphrase {
            guard storePassphrase.count >= Self.minimumPassphraseLength else { throw WalletError.passphraseTooShort }
            secretKey = try await keyGenerator.encrypt(secretKey: material.secretKey, passphrase: storePassphrase)
            kind = .encrypted
        }
        // Another import or a rename may have taken the name or address during the encryption.
        try requireFree(alias: name, address: material.address)
        var wallet = Wallet(alias: name, address: Address(material.address), scheme: material.scheme, publicKey: material.publicKey, keyKind: kind)
        if keepForSession {
            wallet.isSessionOnly = true
            try sessionKeys.add(wallet, secretKey: secretKey)
            sessionWallets = sessionKeys.wallets
            select(wallet)
            return
        }
        try walletStore.add(wallet, secretKey: secretKey)
        wallets = (try? walletStore.load()) ?? wallets + [wallet]
        select(wallet)
        await backUp()
    }

    /// Remember key is for the selected account only while its key would be forgotten at quit.
    var canRememberSelectedKey: Bool { selectedWallet?.isSessionOnly == true }

    /// Moves the selected session-only key into the wallet directory, so it is kept like any
    /// other account (and backed up). An encrypted key is written as it is held; a clear one
    /// can be encrypted with `storePassphrase` on the way. The entry is pinned first and
    /// removed from memory only if it is unchanged after the encryption wait (S07); if the
    /// directory then refuses it, the key goes back into memory and nothing is lost.
    func rememberSelectedWallet(storePassphrase: String? = nil) async throws {
        guard let wallet = selectedWallet, wallet.isSessionOnly else { throw WalletError.emptyAlias }
        guard let snapshot = try sessionKeys.removalSnapshot(for: wallet) else { throw SendViewModel.SendError.noSecretKey }
        let revision = walletDirectoryRevision
        var secretKey = snapshot.secretKey
        var stored = snapshot.wallet
        stored.isSessionOnly = false
        if stored.keyKind == .unencrypted, let storePassphrase, !storePassphrase.isEmpty {
            guard storePassphrase.count >= Self.minimumPassphraseLength else { throw WalletError.passphraseTooShort }
            secretKey = try await keyGenerator.encrypt(secretKey: secretKey, passphrase: storePassphrase)
            stored.keyKind = .encrypted
        }
        guard walletDirectoryRevision == revision else { throw WalletError.directoryChanged }
        // Against the directory as it is now, not the list loaded earlier: another program may
        // have written to it since.
        let onDisk = try walletStore.load()
        if onDisk.contains(where: { $0.alias == stored.alias }) { throw WalletError.aliasExists(stored.alias) }
        if let taken = onDisk.first(where: { $0.address == stored.address }) { throw WalletError.addressExists(taken.alias) }
        try sessionKeys.remove(matching: snapshot)
        do {
            try walletStore.add(stored, secretKey: secretKey)
        } catch {
            try? sessionKeys.add(snapshot.wallet, secretKey: snapshot.secretKey)
            sessionWallets = sessionKeys.wallets
            throw error
        }
        sessionWallets = sessionKeys.wallets
        wallets = (try? walletStore.load()) ?? wallets + [stored]
        select(wallets.first { $0.alias == stored.alias } ?? stored)
        await backUp()
    }

    /// Aliases and addresses are unique across stored, session-only and watch-only accounts.
    private func requireFree(alias: String, address: String) throws {
        guard !wallets.contains(where: { $0.alias == alias }) else { throw WalletError.aliasExists(alias) }
        if let existing = wallets.first(where: { $0.address.value == address }) { throw WalletError.addressExists(existing.alias) }
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
    /// account appears on chain. The work runs in a cancellable task (S21): selecting another
    /// account or calling `cancelFaucetRequest` stops the proof of work.
    func requestTestTez(amount: Double = WalletViewModel.faucetAmountTez) async {
        guard let wallet = selectedWallet, let service = FaucetService(network: network) else { return }
        faucetTask?.cancel()
        let address = wallet.address
        faucetStatus = .solving(done: 0, total: 1)
        let task = Task {
            do {
                // Solving runs off the main actor; cancelling this task cancels the worker too.
                let worker = Task.detached(priority: .userInitiated) {
                    try await service.requestTez(to: address, amount: amount) { done, total in
                        Task { @MainActor in
                            guard case .solving = self.faucetStatus else { return }
                            self.faucetStatus = .solving(done: done, total: total)
                        }
                    }
                }
                let hash = try await withTaskCancellationHandler { try await worker.value } onCancel: { worker.cancel() }
                guard !Task.isCancelled else { return }
                faucetStatus = .sent(hash: hash)
                // The faucet's transfer needs a block; refresh until the balance moves (or give up quietly).
                let before = tezBalance?.spendable ?? 0
                for _ in 0..<12 where selectedWallet?.address == address && !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(5))
                    await refresh()
                    if !accountNotOnChain, (tezBalance?.spendable ?? 0) > before { faucetStatus = .received(hash: hash); break }
                }
            } catch {
                guard !Task.isCancelled else { return }
                faucetStatus = .failed(error.localizedDescription)
            }
        }
        faucetTask = task
        await task.value
        if faucetTask == task { faucetTask = nil }
    }

    /// Stops a faucet request in flight and clears its status.
    func cancelFaucetRequest() {
        faucetTask?.cancel()
        faucetTask = nil
        faucetStatus = .idle
    }

    /// Runs a staking-family operation for the selected wallet with the limits of the estimate
    /// the user approved (S14) and waits one block on the chain service the operation went
    /// through (S16). Returns the operation hash and the block it landed in, then refreshes.
    func performStaking(_ operation: StakingOperation, limits: OperationLimits?, passphrase: String?) async throws -> (hash: String, level: Int) {
        guard let wallet = selectedWallet else { throw WalletError.emptyAlias }
        guard let limits else { throw WalletError.notEstimated }
        guard let signer = try signingKey(for: wallet, passphrase: passphrase) else { throw SendViewModel.SendError.noSecretKey }
        let chain = self.chain
        let sent = try await chain.performStaking(operation, from: wallet, signer: signer, limits: limits)
        let level: Int
        do {
            level = try await chain.waitForConfirmation(of: sent.hash)
        } catch where !sent.injected {
            throw WalletError.outcomeUnknown(sent.hash)
        }
        await refreshAfterOperation()
        return (sent.hash, level)
    }

    /// Refreshes now and again a little later: the node confirms a block before the indexer has it,
    /// so history fetched immediately after an operation often misses it.
    func refreshAfterOperation() async {
        await refresh()
        Task { [weak self] in
            for delay in [6, 15] {
                try? await Task.sleep(for: .seconds(delay))
                await self?.refresh()
            }
        }
    }

    /// Fee estimate for a staking-family operation from the selected wallet.
    // MARK: Etherlink bridge (0.9.1)

    /// The Bridge item: Layer 2 on with a known bridge, and a tz1 to tz3 account we can sign for.
    var canBridge: Bool {
        guard network.canDepositToL2, let wallet = selectedWallet else { return false }
        return wallet.address.isUsableOnEtherlink && wallet.keyKind.canSign
    }

    /// What a deposit estimate was made for (S31): the account, the whole network (node and
    /// Layer 2 settings included) and the directory the key comes from. The estimate is only
    /// good for carrying out a deposit in exactly this context.
    struct BridgeContext: Hashable, Sendable {
        let wallet: Wallet
        let network: Network
        let directoryRevision: UUID
        let generation: UUID
    }

    /// The context a deposit would run in right now; `nil` when nothing is selected.
    var bridgeContext: BridgeContext? {
        selectedWallet.map { BridgeContext(wallet: $0, network: network, directoryRevision: walletDirectoryRevision, generation: operationGeneration) }
    }

    /// A deposit estimate together with the context it is valid for.
    struct BridgeEstimate: Sendable {
        let estimate: TransferEstimate
        let context: BridgeContext
        let amount: Decimal
    }

    func estimateBridgeDeposit(amount: Decimal) async throws -> BridgeEstimate {
        guard let wallet = selectedWallet, let context = bridgeContext else { throw WalletError.emptyAlias }
        guard amount > 0, Mutez.isValid(Mutez.fromTez(amount)) else { throw SendViewModel.SendError.invalidAmount }
        let chain = self.chain
        let estimate = try await chain.estimateEtherlinkDeposit(from: wallet, amount: amount)
        // The account, network, node or directory may have changed while the node was asked.
        guard bridgeContext == context else { throw WalletError.contextChanged }
        return BridgeEstimate(estimate: estimate, context: context, amount: amount)
    }

    /// Moves `amount` tez from the selected account on layer 1 to the same account on Etherlink,
    /// with the approved limits (S14), and waits for the layer 1 block. The rollup credits the
    /// account on its own shortly after. The estimate must have been made in the context the
    /// deposit runs in now (S31): a different account, network, node or directory refuses it.
    func bridgeToEtherlink(amount: Decimal, approved: BridgeEstimate?, passphrase: String?) async throws -> (hash: String, level: Int) {
        guard let wallet = selectedWallet else { throw WalletError.emptyAlias }
        guard let approved, let limits = approved.estimate.limits else { throw WalletError.notEstimated }
        guard approved.context == bridgeContext else { throw WalletError.contextChanged }
        guard canBridge else { throw ChainError.noEtherlinkBridge }
        guard amount > 0, Mutez.isValid(Mutez.fromTez(amount)) else { throw SendViewModel.SendError.invalidAmount }
        guard amount == approved.amount else { throw WalletError.contextChanged }
        guard let signer = try signingKey(for: wallet, passphrase: passphrase) else { throw SendViewModel.SendError.noSecretKey }
        let chain = self.chain
        let sent = try await chain.sendEtherlinkDeposit(from: wallet, signer: signer, amount: amount, limits: limits)
        let level: Int
        do {
            level = try await chain.waitForConfirmation(of: sent.hash)
        } catch where !sent.injected {
            throw WalletError.outcomeUnknown(sent.hash)
        }
        await refreshAfterOperation()
        return (sent.hash, level)
    }

    // MARK: Etherlink alias (0.9.3)

    /// Whether the selected account's EVM-side address exists on Etherlink yet, asked of the
    /// Layer 2 node; `nil` when Layer 2 is off or the key is not usable on the rollup.
    func etherlinkAliasStatus() async throws -> EtherlinkAliasStatus? {
        guard let wallet = selectedWallet, wallet.address.isUsableOnEtherlink, let chain = layer2Chain else { return nil }
        return try await chain.etherlinkAliasStatus(for: wallet.address)
    }

    /// The fee for linking the selected account to its EVM alias (a no-op gateway call on the
    /// Michelson interface, S14: the estimate's limits are what the link is sent with).
    func estimateEtherlinkLink() async throws -> TransferEstimate {
        guard let wallet = selectedWallet, let chain = layer2Chain else { throw ChainError.noEtherlinkNode }
        guard wallet.address.isUsableOnEtherlink, wallet.keyKind.canSign else { throw SendViewModel.SendError.noSecretKey }
        return try await chain.estimateEtherlinkLink(from: wallet)
    }

    /// Links the selected account to its EVM alias: sends the gateway no-op from the account on
    /// the Layer 2 node with the approved `limits` and waits for the rollup block, after which
    /// `etherlinkAliasStatus` reports it linked. The account pays the fee on Etherlink, so it
    /// needs a little tez there first (the Bridge sheet moves some).
    func linkToEtherlink(limits: OperationLimits?, passphrase: String?) async throws -> (hash: String, level: Int) {
        guard let wallet = selectedWallet, let chain = layer2Chain else { throw ChainError.noEtherlinkNode }
        guard let limits else { throw WalletError.notEstimated }
        guard wallet.address.isUsableOnEtherlink else { throw SendViewModel.SendError.noSecretKey }
        guard let signer = try signingKey(for: wallet, passphrase: passphrase) else { throw SendViewModel.SendError.noSecretKey }
        let sent = try await chain.sendEtherlinkLink(from: wallet, signer: signer, limits: limits)
        let level: Int
        do {
            level = try await chain.waitForConfirmation(of: sent.hash)
        } catch where !sent.injected {
            throw WalletError.outcomeUnknown(sent.hash)
        }
        await refreshAfterOperation()
        return (sent.hash, level)
    }

    func estimateStaking(_ operation: StakingOperation) async throws -> TransferEstimate {
        guard let wallet = selectedWallet else { throw WalletError.emptyAlias }
        return try await chain.estimateStaking(operation, from: wallet)
    }

    /// The buy widget for the selected account at `provider`. With a key we can sign for, the
    /// address is pre-validated (a signed per-provider message) so the user has nothing to prove in
    /// the widget; otherwise the address is only pre-filled.
    func buyURL(provider: BuyProvider = .current, fiat: String, passphrase: String?, embedded: Bool = true, dark: Bool = false) async throws -> URL {
        guard let wallet = selectedWallet else { throw WalletError.emptyAlias }
        let code = MtPelerin.randomCode()
        var proof: SignedPayload?
        if let payload = provider.ownershipPayload(code: code), let signer = try signingKey(for: wallet, passphrase: passphrase) {
            proof = try await chain.signPayload(signer: signer, payloadHex: payload)
        }
        return provider.buyURL(address: wallet.address, fiat: fiat, code: code, proof: proof, embedded: embedded, dark: dark)
    }

    func governanceInfo() async throws -> GovernanceInfo {
        guard let wallet = selectedWallet else { throw WalletError.emptyAlias }
        return try await chain.governanceInfo(for: wallet.address)
    }

    /// Upvotes or casts a ballot for the selected baker and waits one block.
    func performGovernance(_ operation: GovernanceOperation, passphrase: String?) async throws -> (hash: String, level: Int) {
        guard let wallet = selectedWallet else { throw WalletError.emptyAlias }
        guard let signer = try signingKey(for: wallet, passphrase: passphrase) else { throw SendViewModel.SendError.noSecretKey }
        let chain = self.chain
        let hash = try await chain.performGovernance(operation, from: wallet, signer: signer)
        let level = try await chain.waitForConfirmation(of: hash)
        await refreshAfterOperation()
        return (hash, level)
    }

    func bakers() async -> [BakerCandidate] {
        (try? await chain.bakers(limit: 60)) ?? []
    }

    /// Proof of possession for one of our tz4 wallets (needed to make it a consensus or companion key).
    func proofOfPossession(for wallet: Wallet, passphrase: String?) async throws -> String {
        guard let signer = try signingKey(for: wallet, passphrase: passphrase) else { throw SendViewModel.SendError.noSecretKey }
        return try await chain.proofOfPossession(signer: signer)
    }

    /// The live chain service, for flows that run their own lookups (Send).
    var chainService: any ChainService { chain }

    /// A chain service for Etherlink's Michelson interface (`Network.layer2`), for operations
    /// between tz accounts on the rollup; `nil` unless Layer 2 is on with a node.
    var layer2Chain: (any ChainService)? { network.layer2.map(chainFactory) }

    /// The selected account's tez on Etherlink as last loaded, or `nil` when unknown.
    var etherlinkSpendable: Decimal? {
        assets.first { $0.kind == .etherlink && $0.unavailable == nil }?.amount
    }

    /// What signs for one of our wallets: its secret key from the store (with `passphrase` if
    /// encrypted) or its Ledger key. `nil` for watch-only and remote-signer aliases.
    /// A software key's secret (clear or octez-encrypted) from the directory, or from memory for
    /// a session-only key; both check the alias still maps to the wallet's address.
    private func softwareSecret(for wallet: Wallet) throws -> String? {
        wallet.isSessionOnly ? try sessionKeys.secretKey(for: wallet) : try walletStore.secretKey(for: wallet)
    }

    func signingKey(for wallet: Wallet, passphrase: String?) throws -> SigningKey? {
        switch wallet.keyKind {
        case .unencrypted, .encrypted:
            guard let secretKey = try softwareSecret(for: wallet) else { return nil }
            return .secret(secretKey, passphrase: wallet.keyKind == .encrypted ? passphrase : nil, address: wallet.address)
        case .ledger:
            guard let key = wallet.ledgerKey else { return nil }
            return .ledger(key, address: wallet.address)
        case .remote, .unknown, .none:
            return nil
        }
    }

    /// Adds a key that lives on a Ledger. The device shows the address and the user approves it
    /// there before anything is written; the entry is an octez-client `ledger://` alias, so
    /// octez-client can use the same key.
    func connectLedger(alias: String, deviceID: String, curve: LedgerCurve, account: Int) async throws {
        let name = alias.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw WalletError.emptyAlias }
        guard !wallets.contains(where: { $0.alias == name }) else { throw WalletError.aliasExists(name) }
        isConnectingLedger = true
        defer { isConnectingLedger = false }

        var key = LedgerKey(rootID: "", curve: curve, account: account)
        let derived = try await ledger.address(deviceID: deviceID, key: key, prompt: true)
        if let existing = wallets.first(where: { $0.address == derived.address }) { throw WalletError.addressExists(existing.alias) }
        // octez names the device by its root key; fall back to the key's own address if the app refuses that path.
        key.rootID = ((try? await ledger.rootAddress(deviceID: deviceID)) ?? derived.address).value

        let wallet = Wallet(alias: name, address: derived.address, scheme: curve.scheme, publicKey: derived.publicKey, keyKind: .ledger, ledgerKey: key)
        try walletStore.add(wallet, locator: key.locator)
        wallets = (try? walletStore.load()) ?? wallets + [wallet]
        select(wallet)
        await backUp()
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

        if wallet.isSessionOnly {
            try sessionKeys.rename(alias: wallet.alias, to: name)
            sessionWallets = sessionKeys.wallets
        } else {
            try walletStore.rename(alias: wallet.alias, to: name)
            wallets = try walletStore.load()
        }
        selectedWalletID = name
        rememberSelection()
        if !wallet.isSessionOnly { Task { await backUp() } }
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
        Wallet(alias: "My Account", address: Address("tz1VSUr8wwNhLAzempoch5d6hLRiTh8Cjcjb"), keyKind: .unencrypted),
        Wallet(alias: "Savings", address: Address("tz2BFTyPeYRzxd5aiBchbXN3WCZhx7BqbMBq"), keyKind: .encrypted),
    ]

    static func preview() -> WalletViewModel {
        WalletViewModel(wallets: sampleWallets, chain: MockChainService())
    }
}

// MARK: - Multisig

extension WalletViewModel {
    /// Where the Sign multisig sheet should start.
    struct MultisigSheetPreset: Hashable, Sendable {
        var contract: MultisigContract
        var delegating = false
    }

    enum MultisigError: LocalizedError {
        case invalidAddress
        case notAMultisig(String)
        case notAMember
        case invalidKey(String)
        case thresholdOutOfRange(Int, Int)
        case cannotSign(String)
        case alreadySigned(String)
        case stale
        case notRevealed(Address)
        case notASignerCandidate(String)
        case keyAddressMismatch(Address, Address)
        case wrongNetwork(String)
        case tampered
        case contextChanged(Address)
        case awaitingConfirmation(String, Address)
        case invalidAmount

        var errorDescription: String? {
            switch self {
            case .invalidAddress: "That is not a contract address (KT1…)."
            case .notAMultisig(let hash): "That contract is not an octez-client multisig (its script hash is \(hash.prefix(16))…), so Signet cannot sign for it."
            case .notAMember: "None of your accounts is a signer of that multisig."
            case .invalidKey(let key): "“\(key.prefix(16))…” is not a public key (edpk, sppk, p2pk, BLpk or mdpk)."
            case .thresholdOutOfRange(let threshold, let keys): "The threshold must be between 1 and the number of keys (\(keys)), not \(threshold)."
            case .cannotSign(let alias): "Signet cannot sign with “\(alias)”."
            case .alreadySigned(let alias): "“\(alias)” has already signed this proposal."
            case .stale: "The multisig has moved on since this was proposed; the signatures no longer apply."
            case .notRevealed(let address): "\(address.shortened()) has not revealed its public key on this network yet (it has never sent an operation). Ask its owner for the public key instead."
            case .notASignerCandidate(let text): "“\(text.prefix(20))…” is neither a public key nor a tz address."
            case .keyAddressMismatch(let wanted, let got): "The node answered with a key for \(got.shortened()), not \(wanted.shortened()). Nothing was added; check the node or paste the public key."
            case .wrongNetwork(let name): "This proposal was made on \(name); switch to that network to sign it."
            case .tampered: "This proposal does not match what the multisig would sign for it now. Nothing was signed; discard it and propose it again."
            case .awaitingConfirmation(let hash, let address): "Operation \(hash) has not been confirmed. Its contract address is \(address.value). Open Send from the paying account to recover this operation; do not create another contract."
            case .invalidAmount: "The initial balance must be a number of tez, zero or more."
            case .contextChanged(let address): "The wallet directory or network changed while the multisig \(address.shortened()) was being set up. It exists on chain but was not recorded here; add it with Add multisig… where it belongs."
            }
        }
    }

    /// Proposals for the network in use, newest first.
    var currentMultisigProposals: [MultisigProposal] {
        multisigProposals.filter { $0.networkName == network.name }.sorted { $0.created > $1.created }
    }

    /// Accounts whose public key we know, so they can be put on a multisig.
    var multisigKeyCandidates: [Wallet] { wallets.filter { $0.publicKey != nil } }

    nonisolated static func isPublicKey(_ key: String) -> Bool {
        // The node checks the key properly at origination; this only keeps obvious garbage out of the list.
        ["edpk", "sppk", "p2pk", "BLpk", "mdpk"].contains { key.hasPrefix($0) } && key.count > 6 && key.allSatisfy { $0.isLetter || $0.isNumber }
    }

    /// A signer for a new multisig from what the user gave: a public key as is, or a tz address
    /// (pasted, from the address book or one of ours) resolved to the key it has revealed on chain.
    func multisigSignerKey(from text: String) async throws -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if Self.isPublicKey(trimmed) { return trimmed }
        let address = Address(trimmed)
        guard address.isValidAccount, !address.isContract else { throw MultisigError.notASignerCandidate(trimmed) }
        if let mine = wallets.first(where: { $0.address == address }), let key = mine.publicKey { return key }
        guard let key = try await multisig.revealedPublicKey(rpcURL: network.rpcURL, address: address) else { throw MultisigError.notRevealed(address) }
        // The node is not trusted to say whose key that is: it must hash to the address asked for.
        guard Self.isPublicKey(key) else { throw MultisigError.invalidKey(key) }
        let derived = try await multisig.address(forPublicKey: key)
        guard derived == address else { throw MultisigError.keyAddressMismatch(address, derived) }
        return key
    }

    func multisigInfo(_ contract: MultisigContract) async throws -> MultisigInfo {
        try await multisig.info(rpcURL: network.rpcURL, address: contract.address)
    }

    /// Fee and burn for deploying the multisig, with `amount` tez moved into it on creation.
    func estimateCreateMultisig(threshold: Int, keys: [String], amount: Decimal = 0) async throws -> MultisigEstimate {
        guard let wallet = selectedWallet else { throw WalletError.emptyAlias }
        try Self.checkMultisig(threshold: threshold, keys: keys, amount: amount)
        return try await multisig.estimateOriginate(rpcURL: network.rpcURL, from: wallet, threshold: threshold, keys: keys, amount: amount)
    }

    private static func checkMultisig(threshold: Int, keys: [String], amount: Decimal) throws {
        if let bad = keys.first(where: { !isPublicKey($0) }) { throw MultisigError.invalidKey(bad) }
        guard threshold >= 1, threshold <= keys.count else { throw MultisigError.thresholdOutOfRange(threshold, keys.count) }
        guard amount >= 0, amount.isFinite, Mutez.isValid(Mutez.fromTez(amount)) else { throw MultisigError.invalidAmount }
    }

    /// Deploys a multisig from the selected account with the approved estimate's limits (S14),
    /// waits for its block and records it under `alias`.
    func createMultisig(alias: String, threshold: Int, keys: [String], amount: Decimal = 0, limits: OperationLimits?, passphrase: String?) async throws -> MultisigContract {
        guard let limits else { throw WalletError.notEstimated }
        guard let wallet = selectedWallet else { throw WalletError.emptyAlias }
        let name = alias.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw WalletError.emptyAlias }
        guard !wallets.contains(where: { $0.alias == name }) else { throw WalletError.aliasExists(name) }
        try Self.checkMultisig(threshold: threshold, keys: keys, amount: amount)
        guard let signer = try signingKey(for: wallet, passphrase: passphrase) else { throw MultisigError.cannotSign(wallet.alias) }
        let chain = self.chain
        let context = (revision: walletDirectoryRevision, network: network, generation: operationGeneration)
        let (hash, address) = try await multisig.originate(rpcURL: network.rpcURL, signer: signer, threshold: threshold, keys: keys, amount: amount, limits: limits)
        do { _ = try await chain.waitForConfirmation(of: hash) }
        catch { throw MultisigError.awaitingConfirmation(hash, address) }
        return try await recordContract(MultisigContract(alias: name, address: address), startedIn: context)
    }

    /// Writes the contract alias, puts it in the address book and shows it. The alias goes to the
    /// directory the operation started in: after a directory or network switch it is refused,
    /// and the address is reported so the user can add it where it belongs (S16).
    private func recordContract(_ contract: MultisigContract, startedIn context: (revision: UUID, network: Network, generation: UUID)) async throws -> MultisigContract {
        guard walletDirectoryRevision == context.revision, network == context.network, operationGeneration == context.generation else {
            throw MultisigError.contextChanged(contract.address)
        }
        try walletStore.addContract(contract)
        let entry = Wallet(alias: contract.alias, address: contract.address, keyKind: .none)
        wallets = (try? walletStore.load()) ?? wallets + [entry]
        select(wallets.first { $0.alias == contract.alias } ?? entry)
        await backUp()
        return contract
    }

    /// Records an existing multisig under `alias`, after checking it is the generic multisig and
    /// one of our accounts is among its keys.
    func addMultisig(alias: String, address rawAddress: String) async throws -> MultisigContract {
        let name = alias.trimmingCharacters(in: .whitespacesAndNewlines)
        let address = Address(rawAddress.trimmingCharacters(in: .whitespacesAndNewlines))
        guard !name.isEmpty else { throw WalletError.emptyAlias }
        guard address.isContract, address.isValidAccount else { throw MultisigError.invalidAddress }
        guard !wallets.contains(where: { $0.alias == name }) else { throw WalletError.aliasExists(name) }
        if let existing = wallets.first(where: { $0.address == address }) { throw WalletError.addressExists(existing.alias) }
        let context = (revision: walletDirectoryRevision, network: network, generation: operationGeneration)
        let info = try await multisig.info(rpcURL: network.rpcURL, address: address)
        guard info.isGenericMultisig else { throw MultisigError.notAMultisig(info.scriptHash) }
        guard !info.members(among: wallets).isEmpty else { throw MultisigError.notAMember }
        return try await recordContract(MultisigContract(alias: name, address: address), startedIn: context)
    }

    /// Fetches the contract's state and makes an unsigned proposal for this transfer at its current counter.
    func proposeMultisigTransfer(from contract: MultisigContract, amount: Decimal, to destination: Address) async throws -> MultisigProposal {
        try await proposeMultisig(.transfer(amountMutez: Mutez.fromTez(amount), destination: destination.value), from: contract)
    }

    /// Fetches the contract's state and makes an unsigned proposal for this action at its current counter.
    func proposeMultisig(_ action: MultisigAction, from contract: MultisigContract) async throws -> MultisigProposal {
        let context = (revision: walletDirectoryRevision, network: network, generation: operationGeneration)
        let (info, chainID, bytes) = try await multisig.prepare(rpcURL: network.rpcURL, contract: contract.address, action: action)
        guard walletDirectoryRevision == context.revision, network == context.network, operationGeneration == context.generation else { throw WalletError.directoryChanged }
        guard info.isGenericMultisig else { throw MultisigError.notAMultisig(info.scriptHash) }
        // The same action proposed twice is the same proposal: reuse it so signatures accumulate.
        if let existing = multisigProposals.first(where: { $0.contractAddress == contract.address.value && $0.networkName == network.name && $0.bytes == bytes }) {
            return existing
        }
        let proposal = MultisigProposal(contractAlias: contract.alias, contractAddress: contract.address.value, networkName: network.name, chainID: chainID,
                                        counter: info.counter, threshold: info.threshold, keys: info.keys, action: action, bytes: bytes)
        let same = { (p: MultisigProposal) in p.contractAddress == proposal.contractAddress && p.networkName == proposal.networkName && p.bytes == proposal.bytes }
        multisigProposals = try proposalStore.update { stored in
            if !stored.contains(where: same) { stored.append(proposal) }
        }
        return multisigProposals.first(where: same) ?? proposal
    }

    /// Signs a proposal with one of our accounts (a key of the multisig) and keeps the signature with it.
    ///
    /// The proposal file is not trusted. What gets signed is rebuilt by the bridge from the
    /// proposal's chain, contract, counter and action (the fields the sheet displays), never its
    /// stored bytes, and the chain must agree: the contract is the generic multisig, at that
    /// counter, with those keys, and packs those same bytes. Any difference means nothing is signed.
    @discardableResult
    func signMultisigProposal(_ proposal: MultisigProposal, with wallet: Wallet, passphrase: String?) async throws -> MultisigSignature {
        guard let publicKey = wallet.publicKey, proposal.keys.contains(publicKey) else { throw MultisigError.notAMember }
        guard !proposal.hasSignature(from: publicKey) else { throw MultisigError.alreadySigned(wallet.alias) }
        guard proposal.networkName == network.name else { throw MultisigError.wrongNetwork(proposal.networkName) }
        let revision = walletDirectoryRevision
        let rpcURL = network.rpcURL
        let generation = operationGeneration
        let service = multisig

        let live = try await service.prepare(rpcURL: rpcURL, contract: proposal.contract.address, action: proposal.action)
        guard live.info.isGenericMultisig else { throw MultisigError.notAMultisig(live.info.scriptHash) }
        guard live.chainID == proposal.chainID, live.info.counter == proposal.counter else { throw MultisigError.stale }
        guard live.info.keys == proposal.keys, live.info.threshold == proposal.threshold, live.info.keys.contains(publicKey) else { throw MultisigError.stale }
        guard live.bytes == proposal.bytes else { throw MultisigError.tampered }

        guard walletDirectoryRevision == revision, operationGeneration == generation else { throw WalletError.directoryChanged }
        guard let signer = try signingKey(for: wallet, passphrase: passphrase) else { throw MultisigError.cannotSign(wallet.alias) }
        let signed = try await service.sign(signer: signer, proposal: proposal)
        guard signed.bytes == proposal.bytes else { throw MultisigError.tampered }
        guard walletDirectoryRevision == revision, operationGeneration == generation, network.rpcURL == rpcURL else { throw WalletError.directoryChanged }

        let signature = MultisigSignature(publicKey: publicKey, signature: signed.signature)
        try updateProposal(proposal.id) { $0.signatures.append(signature) }
        return signature
    }

    /// Keeps a signature another signer sent us (verified against the keys when submitting).
    func addMultisigSignature(_ signature: String, to proposal: MultisigProposal) throws {
        let trimmed = signature.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        try updateProposal(proposal.id) { stored in
            // Check against what is stored, not the caller's copy, so repeated pastes do not pile up.
            guard !stored.signatures.contains(where: { $0.signature == trimmed }) else { return }
            stored.signatures.append(MultisigSignature(publicKey: nil, signature: trimmed))
        }
    }

    func removeMultisigProposal(_ proposal: MultisigProposal) throws {
        multisigProposals = try proposalStore.update { $0.removeAll { $0.id == proposal.id } }
    }

    /// Changes one stored proposal; the change is applied to the copy on disk, not the one in memory.
    private func updateProposal(_ id: MultisigProposal.ID, _ change: (inout MultisigProposal) -> Void) throws {
        multisigProposals = try proposalStore.update { stored in
            guard let index = stored.firstIndex(where: { $0.id == id }) else { return }
            change(&stored[index])
        }
    }

    func estimateSubmitMultisig(_ proposal: MultisigProposal, from wallet: Wallet) async throws -> MultisigEstimate {
        try await multisig.estimateSubmit(rpcURL: network.rpcURL, from: wallet, proposal: proposal, signatures: proposal.signatures.map(\.signature))
    }

    /// Submits the proposal with its signatures from `wallet` (which pays the fee), waits one block
    /// and forgets the proposal. Returns the operation hash.
    func submitMultisig(_ proposal: MultisigProposal, from wallet: Wallet, limits: OperationLimits?, passphrase: String?) async throws -> String {
        guard let limits else { throw WalletError.notEstimated }
        guard let signer = try signingKey(for: wallet, passphrase: passphrase) else { throw MultisigError.cannotSign(wallet.alias) }
        let chain = self.chain
        let revision = walletDirectoryRevision
        let generation = operationGeneration
        let hash = try await multisig.submit(rpcURL: network.rpcURL, signer: signer, proposal: proposal, signatures: proposal.signatures.map(\.signature), limits: limits)
        _ = try await chain.waitForConfirmation(of: hash)
        // The proposal file belongs to the directory the submission started in.
        if walletDirectoryRevision == revision, operationGeneration == generation { try removeMultisigProposal(proposal) }
        await refreshAfterOperation()
        return hash
    }
}
