import SwiftUI

@main
struct SignetApp: App {
    @State private var model = WalletViewModel(
        chainFactory: { network in TaquitoChainService(network: network) },
        keyGenerator: KeyGenerator(),
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

    var body: some Scene {
        WindowGroup("Signet") {
            WalletHomeView(model: model)
        }
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Create wallet…") { model.isPresentingCreateWallet = true }
                    .keyboardShortcut("n", modifiers: .command)
            }
        }

        Settings {
            SettingsView(model: model)
        }
    }
}
