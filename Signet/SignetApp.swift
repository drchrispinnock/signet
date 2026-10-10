import SwiftUI

@main
struct SignetApp: App {
    @State private var model = makeModel()

    @MainActor private static func makeModel() -> WalletViewModel {
        if AppRuntime.isDemo { return WalletViewModel.demo() }
        return WalletViewModel(
            chainFactory: { network in TaquitoChainService(network: network) },
            keyGenerator: KeyGenerator(),
            ledger: BridgeLedgerService(),
            keyImporter: BridgeKeyImporter(),
            importSource: TezosClientStore.octezClientDirectory,
            directorySettings: WalletDirectorySettings(),
            storeFactory: { directory in
                (wallets: TezosClientStore(directory: directory), state: FileAppStateStore(directory: directory))
            },
            backupSettings: BackupSettings(),
            dappStorage: OctezConnectStorage(directory: WalletDirectorySettings().current),
            // Test hosts drive the bridge themselves, without starting the app's dApp client.
            startDApps: ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil
        )
    }

    // Sparkle: checks the GitHub release appcast daily and on "Check for Updates…". Not started
    // under the test host, which would otherwise reach the network and may put up a dialog.
    @State private var updater = UpdaterService(
        starting: !AppRuntime.isDemo && ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil
    )

    var body: some Scene {
        // A single window: a WindowGroup would open a second one when a signet:// link arrives.
        Window(AppRuntime.isDemo ? "Signet — Demo" : "Signet", id: "main") {
            WalletHomeView(model: model)
                // signet://?type=tzip10&data=<pairing code>: what a dApp's wallet list opens for desktop wallets.
                .onOpenURL { url in
                    guard !AppRuntime.isDemo else { return }
                    model.handleIncomingURL(url)
                }
                .overlay(alignment: .bottom) {
                    if AppRuntime.isDemo {
                        Text("Demo · sample accounts · no real payments")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(8)
                    }
                }
        }
        .defaultSize(width: 620, height: 760)
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
                Button("Swap with 3Route…") { model.isPresentingSwap = true }
                    .disabled(model.selectedWallet == nil || !model.network.isMainnet)
                Divider()
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
