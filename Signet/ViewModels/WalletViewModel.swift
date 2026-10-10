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
        case directoryChanged

        var errorDescription: String? {
            switch self {
            case .emptyAlias: "Give the account a name."
            case .aliasExists(let alias): "An account named “\(alias)” already exists."
            case .addressExists(let alias): "That address is already in the list as “\(alias)”."
            case .invalidAddress: "That is not a valid Tezos address."
            case .passphraseTooShort: "Use a password of at least \(WalletViewModel.minimumPassphraseLength) characters."
            case .unsupportedScheme(let scheme): scheme.unavailableReason ?? "\(scheme.rawValue) is not supported yet."
            case .directoryChanged: "The wallet directory changed while this was being confirmed. Nothing was done; please try again."
            }
        }
    }

    /// Etherlink is not relevant yet; flip this to bring the row (icon, balance fetch) back.
    static let showsEtherlinkBalance = false

    private(set) var wallets: [Wallet]
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
    private let keyGenerator: KeyGenerator
    /// Ledger discovery and key derivation.
    let ledger: any LedgerService
    /// Pasted secret keys and recovery phrases.
    let keyImporter: any KeyImporter
    let multisig: any MultisigService
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
        self.ledger = ledger
        self.keyImporter = keyImporter
        self.multisig = multisig
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
            signer: { [unowned self] wallet, passphrase in try self.signingKey(for: wallet, passphrase: passphrase) }
        )
        if startDApps, !self.wallets.isEmpty {
            Task { await dapps.start() }
        }

        // A new head means balances or history may have moved; refresh (not while one is running).
        nodeMonitor.onNewHead = { [weak self] _ in
            guard let self, !self.isLoading, self.selectedWallet != nil else { return }
            Task { await self.refresh() }
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
            errorMessage = "Could not load accounts: \(error.localizedDescription)"
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
            async let delegation = chain.delegateInfo(for: address)

            let tezBalance = try await tez
            var list = [AssetBalance(id: "tez", kind: .tez, name: "Tezos", symbol: "tz", amount: tezBalance.total, details: tezBalance.breakdown)]
            self.tezBalance = tezBalance
            if Self.showsEtherlinkBalance {
                let etherlink = try await chain.etherlinkBalance(for: address)
                list.append(AssetBalance(id: "etherlink", kind: .etherlink, name: "Etherlink", symbol: "tz", amount: etherlink))
            }
            let tokenList = try await tokens

            // Drop the results if the user switched wallets while we were loading.
            guard address == selectedWallet?.address else { return }
            assets = list
            self.tokens = tokenList
            domains = try await names
            nfts = try await collectibles
            transactions = try await history
            delegateInfo = (try? await delegation) ?? nil
        } catch ChainError.accountNotOnChain {
            guard address == selectedWallet?.address else { return }
            accountNotOnChain = true
            assets = []
            tokens = (try? await chain.tokenBalances(for: address)) ?? []
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
        tokens = []
        nfts = []
        transactions = []
        delegateInfo = nil
        tezBalance = nil
        accountNotOnChain = false
        faucetStatus = .idle
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
        if let next = wallets.first {
            select(next)
        } else {
            selectedWalletID = nil
            rememberSelection()
            domains = []; assets = []; tokens = []; nfts = []; transactions = []; delegateInfo = nil; tezBalance = nil
        }
        await backUp()
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
        guard let stored = try walletStore.secretKey(for: wallet) else { throw SendViewModel.SendError.noSecretKey }
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
    func importAccount(alias: String, material: KeyMaterial, alreadyEncrypted: Bool = false, storePassphrase: String? = nil) async throws {
        let name = alias.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw WalletError.emptyAlias }
        guard !wallets.contains(where: { $0.alias == name }) else { throw WalletError.aliasExists(name) }
        if let existing = wallets.first(where: { $0.address.value == material.address }) { throw WalletError.addressExists(existing.alias) }

        var secretKey = material.secretKey
        var kind: KeyKind = alreadyEncrypted ? .encrypted : .unencrypted
        if !alreadyEncrypted, let storePassphrase {
            guard storePassphrase.count >= Self.minimumPassphraseLength else { throw WalletError.passphraseTooShort }
            secretKey = try await keyGenerator.encrypt(secretKey: material.secretKey, passphrase: storePassphrase)
            kind = .encrypted
        }
        let wallet = Wallet(alias: name, address: Address(material.address), scheme: material.scheme, publicKey: material.publicKey, keyKind: kind)
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

    /// Runs a staking-family operation for the selected wallet and waits one block.
    /// Returns the operation hash and the block it landed in, then refreshes.
    func performStaking(_ operation: StakingOperation, passphrase: String?) async throws -> (hash: String, level: Int) {
        guard let wallet = selectedWallet else { throw WalletError.emptyAlias }
        guard let signer = try signingKey(for: wallet, passphrase: passphrase) else { throw SendViewModel.SendError.noSecretKey }
        let hash = try await chain.performStaking(operation, from: wallet, signer: signer)
        let level = try await chain.waitForConfirmation(of: hash)
        await refreshAfterOperation()
        return (hash, level)
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

    /// What signs for one of our wallets: its secret key from the store (with `passphrase` if
    /// encrypted) or its Ledger key. `nil` for watch-only and remote-signer aliases.
    func signingKey(for wallet: Wallet, passphrase: String?) throws -> SigningKey? {
        switch wallet.keyKind {
        case .unencrypted, .encrypted:
            guard let secretKey = try walletStore.secretKey(for: wallet) else { return nil }
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

    func estimateCreateMultisig(threshold: Int, keys: [String]) async throws -> MultisigEstimate {
        guard let wallet = selectedWallet else { throw WalletError.emptyAlias }
        try Self.checkMultisig(threshold: threshold, keys: keys)
        return try await multisig.estimateOriginate(rpcURL: network.rpcURL, from: wallet, threshold: threshold, keys: keys)
    }

    private static func checkMultisig(threshold: Int, keys: [String]) throws {
        if let bad = keys.first(where: { !isPublicKey($0) }) { throw MultisigError.invalidKey(bad) }
        guard threshold >= 1, threshold <= keys.count else { throw MultisigError.thresholdOutOfRange(threshold, keys.count) }
    }

    /// Deploys a multisig from the selected account and records it under `alias`.
    func createMultisig(alias: String, threshold: Int, keys: [String], passphrase: String?) async throws -> MultisigContract {
        guard let wallet = selectedWallet else { throw WalletError.emptyAlias }
        let name = alias.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw WalletError.emptyAlias }
        guard !wallets.contains(where: { $0.alias == name }) else { throw WalletError.aliasExists(name) }
        try Self.checkMultisig(threshold: threshold, keys: keys)
        guard let signer = try signingKey(for: wallet, passphrase: passphrase) else { throw MultisigError.cannotSign(wallet.alias) }
        let (_, address) = try await multisig.originate(rpcURL: network.rpcURL, signer: signer, threshold: threshold, keys: keys)
        return try await recordContract(MultisigContract(alias: name, address: address))
    }

    /// Writes the contract alias, puts it in the address book and shows it.
    private func recordContract(_ contract: MultisigContract) async throws -> MultisigContract {
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
        let info = try await multisig.info(rpcURL: network.rpcURL, address: address)
        guard info.isGenericMultisig else { throw MultisigError.notAMultisig(info.scriptHash) }
        guard !info.members(among: wallets).isEmpty else { throw MultisigError.notAMember }
        return try await recordContract(MultisigContract(alias: name, address: address))
    }

    /// Fetches the contract's state and makes an unsigned proposal for this transfer at its current counter.
    func proposeMultisigTransfer(from contract: MultisigContract, amount: Decimal, to destination: Address) async throws -> MultisigProposal {
        try await proposeMultisig(.transfer(amountMutez: Mutez.fromTez(amount), destination: destination.value), from: contract)
    }

    /// Fetches the contract's state and makes an unsigned proposal for this action at its current counter.
    func proposeMultisig(_ action: MultisigAction, from contract: MultisigContract) async throws -> MultisigProposal {
        let (info, chainID, bytes) = try await multisig.prepare(rpcURL: network.rpcURL, contract: contract.address, action: action)
        guard info.isGenericMultisig else { throw MultisigError.notAMultisig(info.scriptHash) }
        // The same action proposed twice is the same proposal: reuse it so signatures accumulate.
        if let existing = multisigProposals.first(where: { $0.contractAddress == contract.address.value && $0.networkName == network.name && $0.bytes == bytes }) {
            return existing
        }
        let proposal = MultisigProposal(contractAlias: contract.alias, contractAddress: contract.address.value, networkName: network.name, chainID: chainID,
                                        counter: info.counter, threshold: info.threshold, keys: info.keys, action: action, bytes: bytes)
        multisigProposals.append(proposal)
        try proposalStore.save(multisigProposals)
        return proposal
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

        let live = try await multisig.prepare(rpcURL: rpcURL, contract: proposal.contract.address, action: proposal.action)
        guard live.info.isGenericMultisig else { throw MultisigError.notAMultisig(live.info.scriptHash) }
        guard live.chainID == proposal.chainID, live.info.counter == proposal.counter else { throw MultisigError.stale }
        guard live.info.keys == proposal.keys, live.info.threshold == proposal.threshold, live.info.keys.contains(publicKey) else { throw MultisigError.stale }
        guard live.bytes == proposal.bytes else { throw MultisigError.tampered }

        guard let signer = try signingKey(for: wallet, passphrase: passphrase) else { throw MultisigError.cannotSign(wallet.alias) }
        let signed = try await multisig.sign(signer: signer, proposal: proposal)
        guard signed.bytes == proposal.bytes else { throw MultisigError.tampered }
        guard walletDirectoryRevision == revision, network.rpcURL == rpcURL else { throw WalletError.directoryChanged }

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
        multisigProposals.removeAll { $0.id == proposal.id }
        try proposalStore.save(multisigProposals)
    }

    private func updateProposal(_ id: MultisigProposal.ID, _ change: (inout MultisigProposal) -> Void) throws {
        guard let index = multisigProposals.firstIndex(where: { $0.id == id }) else { return }
        change(&multisigProposals[index])
        try proposalStore.save(multisigProposals)
    }

    func estimateSubmitMultisig(_ proposal: MultisigProposal, from wallet: Wallet) async throws -> MultisigEstimate {
        try await multisig.estimateSubmit(rpcURL: network.rpcURL, from: wallet, proposal: proposal, signatures: proposal.signatures.map(\.signature))
    }

    /// Submits the proposal with its signatures from `wallet` (which pays the fee), waits one block
    /// and forgets the proposal. Returns the operation hash.
    func submitMultisig(_ proposal: MultisigProposal, from wallet: Wallet, passphrase: String?) async throws -> String {
        guard let signer = try signingKey(for: wallet, passphrase: passphrase) else { throw MultisigError.cannotSign(wallet.alias) }
        let hash = try await multisig.submit(rpcURL: network.rpcURL, signer: signer, proposal: proposal, signatures: proposal.signatures.map(\.signature))
        try removeMultisigProposal(proposal)
        await refreshAfterOperation()
        return hash
    }
}
