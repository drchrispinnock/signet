import SwiftUI

/// The default screen from spec/EXAMPLE.png: header, action row, asset list, NFT grid.
/// With no wallets yet it shows a prompt to create the first address instead.
struct WalletHomeView: View {
    @Bindable var model: WalletViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            if let wallet = model.selectedWallet {
                HStack(alignment: .top) {
                    WalletIdentityView(model: model, wallet: wallet)
                    Spacer()
                    if model.network != .mainnet {
                        Text(model.network.name)
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(.orange.opacity(0.2)))
                            .foregroundStyle(.orange)
                            .help("Connected to \(model.network.rpcURL.absoluteString)")
                    }
                    AppMenuButton(model: model)
                }
                ActionButtonsView()
                AssetListView(assets: model.assets)
                Divider()
                NFTGridView(nfts: model.nfts, isLoading: model.isLoading)
            } else {
                NoWalletsView(model: model)
            }
        }
        .padding(24)
        .frame(minWidth: 480, minHeight: 720)
        .task { await model.refresh() }
        .sheet(isPresented: $model.isPresentingCreateWallet) {
            CreateWalletSheet(model: model)
        }
        .sheet(isPresented: $model.isPresentingRenameWallet) {
            RenameWalletSheet(model: model)
        }
        .overlay(alignment: .bottom) {
            if let message = model.errorMessage {
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .padding(8)
            }
        }
    }
}

/// Shown when there is nothing to display yet.
struct NoWalletsView: View {
    @Bindable var model: WalletViewModel
    @State private var importError: String?

    private func importWallets() {
        importError = nil
        do {
            try model.importFromOctezClient()
        } catch {
            importError = error.localizedDescription
        }
    }

    var body: some View {
        VStack(spacing: 16) {
            Spacer()
            Image("TezosToken")
                .resizable()
                .scaledToFit()
                .frame(width: 72, height: 72)
            Text("Welcome to Signet, a Tezos Wallet for the Mac.")
                .font(.title3.weight(.semibold))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
            if model.importableWalletCount > 0 {
                Text("Found an octez-client wallet with \(model.importableWalletCount) \(model.importableWalletCount == 1 ? "key" : "keys") in ~/.tezos-client. Import it into Signet?")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 360)
                Button("Import wallets") { importWallets() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                Button("Create a new wallet instead…") { model.isPresentingCreateWallet = true }
                    .buttonStyle(.link)
                    .keyboardShortcut("n", modifiers: .command)
            } else {
                Button("Create wallet…") { model.isPresentingCreateWallet = true }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut("n", modifiers: .command)
            }
            if let importError {
                Text(importError)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}

#Preview("With wallets") {
    WalletHomeView(model: .preview())
}

#Preview("Empty") {
    WalletHomeView(model: WalletViewModel(wallets: [], chain: MockChainService()))
}
