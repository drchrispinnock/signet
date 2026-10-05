import SwiftUI

@main
struct SignetApp: App {
    @State private var model = WalletViewModel(
        chain: TaquitoChainService(),
        keyGenerator: KeyGenerator(),
        secretKeys: KeychainSecretKeyStore(),
        walletStore: FileWalletStore()
    )

    var body: some Scene {
        WindowGroup("Signet") {
            WalletHomeView(model: model)
        }
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Create address…") { model.isPresentingCreateWallet = true }
                    .keyboardShortcut("n", modifiers: .command)
            }
        }
    }
}
