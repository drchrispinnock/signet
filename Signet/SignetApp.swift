import SwiftUI

@main
struct SignetApp: App {
    @State private var model = WalletViewModel(
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
        dappStorage: OctezConnectStorage(directory: WalletDirectorySettings().current),
        // Never run the dApp client inside a test host: tests drive the bridge themselves and the
        // app's client would share (and could clobber) real state.
        startDApps: ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil
    )
    // Sparkle: checks the GitHub release appcast daily and on "Check for Updates…". Not started
    // under the test host, which would otherwise reach the network and may put up a dialog.
    @State private var updater = UpdaterService(
        starting: ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil
    )

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
                Button("Connect to dApp…") { model.isPresentingConnectDApp = true }
                    .keyboardShortcut("d", modifiers: [.command, .shift])
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
