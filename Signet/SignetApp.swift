import SwiftUI

@main
struct SignetApp: App {
    /// True when this process is the host for `SignetTests`.
    static var isTestHost: Bool { ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil }

    init() {
        // Session-only keys live in memory (`SessionKeyStore`); a core dump would write that
        // memory to disk. macOS crash reports carry no heap, and this makes sure no core file is
        // ever produced either.
        var none = rlimit(rlim_cur: 0, rlim_max: 0)
        setrlimit(RLIMIT_CORE, &none)
    }

    /// The app's model. Under the test host it is built on in-memory stores only (S24): no wallet
    /// directory is read, no backup is scheduled, no dApp storage or client is touched, so tests
    /// never see or change the developer's real wallet state. Tests construct their own models.
    @MainActor
    static func makeModel(isTestHost: Bool = isTestHost) -> WalletViewModel {
        if isTestHost {
            return WalletViewModel(wallets: [], chain: MockChainService(), multisig: MockMultisigService(), walletStore: InMemoryWalletStore(), nodeProbe: { _ in throw URLError(.notConnectedToInternet) })
        }
        TaquitoBridge.shared.configureLog(at: TaquitoBridge.logFileURL)
        TaquitoBridge.shared.operationJournal = OperationJournal(directory: TezosClientStore.defaultDirectory)
        return WalletViewModel(
            chainFactory: { network in TaquitoChainService(network: network) },
            keyGenerator: KeyGenerator(),
            ledger: BridgeLedgerService(),
            keyImporter: BridgeKeyImporter(),
            multisig: BridgeMultisigService(),
            importSource: TezosClientStore.octezClientDirectory,
            directorySettings: WalletDirectorySettings(),
            storeFactory: { directory in
                (wallets: TezosClientStore(directory: directory), state: FileAppStateStore(directory: directory))
            },
            backupSettings: BackupSettings(),
            dappStorageFactory: { directory in OctezConnectStorage(directory: directory) },
            dappDiagnostics: DeveloperSettings.dappDiagnostics,
            startDApps: true
        )
    }

    @State private var model = SignetApp.makeModel()
    // Sparkle: checks the GitHub release appcast daily and on "Check for Updates…". Not started
    // under the test host, which would otherwise reach the network and may put up a dialog.
    @State private var updater = UpdaterService(starting: !SignetApp.isTestHost)

    var body: some Scene {
        // A single window: a WindowGroup would open a second one when a signet:// link arrives.
        Window("Signet", id: "main") {
            WalletHomeView(model: model)
                // signet://?type=tzip10&data=<pairing code>: what a dApp's wallet list opens for desktop wallets.
                .onOpenURL { url in model.handleIncomingURL(url) }
        }
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Check for Updates…") { updater.checkForUpdates() }
                    .disabled(!updater.canCheckForUpdates)
            }
            CommandGroup(replacing: .newItem) {
                Button("Create Backup") { Task { await model.backUp(force: true) } }
                    .disabled(model.backupDirectory == nil)
            }
            // The same actions as the burger menu, in the menu bar.
            CommandMenu("Operations") {
                Button("Create account…") { model.isPresentingCreateWallet = true }
                    .keyboardShortcut("n", modifiers: .command)
                Button("Import account…") { model.isPresentingImportAccount = true }
                    .keyboardShortcut("i", modifiers: [.command, .shift])
                Button("Connect Ledger…") { model.isPresentingConnectLedger = true }
                    .keyboardShortcut("l", modifiers: [.command, .shift])
                Button("Rename account…") { model.isPresentingRenameWallet = true }
                    .disabled(model.selectedWallet == nil)
                Button("Export secret key…") { model.isPresentingExportKey = true }
                    .disabled(!model.canExportSelectedKey)
                Divider()
                Button("Add address…") { model.isPresentingAddAddress = true }
                    .keyboardShortcut("n", modifiers: [.command, .shift])
                Button("Forget account…") { model.isPresentingForget = true }
                    .disabled(model.selectedWallet == nil)
                Divider()
                Button("dApps…") { model.isPresentingConnectDApp = true }
                    .keyboardShortcut("d", modifiers: [.command, .shift])
                if model.canBridge {
                    Button("Bridge…") { model.isPresentingBridge = true }
                }
                Divider()
                Button("Create multisig…") { model.isPresentingCreateMultisig = true }
                Button("Add multisig…") { model.isPresentingAddMultisig = true }
                Button("Sign multisig transaction…") { model.isPresentingSignMultisig = true }
                Button("Submit multisig transaction…") { model.isPresentingSubmitMultisig = true }
                Divider()
                Button("Baking…") { model.isPresentingBaking = true }
                    .disabled(model.selectedWallet == nil)
                if model.canGovern {
                    Button("Governance…") { model.isPresentingGovernance = true }
                }
                Divider()
                Button("Networks…") { model.isPresentingNetworks = true }
                SettingsLink { Text("Settings…") }
                Button("Refresh") { Task { await model.refresh() } }
                    .keyboardShortcut("r", modifiers: .command)
                    .disabled(model.selectedWallet == nil)
            }
        }

        Settings {
            SettingsView(model: model, updater: updater)
        }
    }
}
