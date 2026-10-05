import SwiftUI

@main
struct SignetApp: App {
    @State private var model = WalletViewModel(
        chainFactory: { network in TaquitoChainService(network: network) },
        keyGenerator: KeyGenerator(),
        walletStore: TezosClientStore(),
        importSource: TezosClientStore.octezClientDirectory,
        stateStore: FileAppStateStore()
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
