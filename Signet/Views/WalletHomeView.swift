import SwiftUI

/// The default screen from spec/EXAMPLE.png: header, action row, asset list, NFT grid.
/// With no wallets yet it shows a prompt to create the first address instead.
struct WalletHomeView: View {
    @Bindable var model: WalletViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack(alignment: .top) {
                if let wallet = model.selectedWallet {
                    WalletIdentityView(model: model, wallet: wallet)
                } else {
                    Text("Signet")
                        .font(.title2.weight(.semibold))
                }
                Spacer()
                AppMenuButton(model: model)
            }

            if model.selectedWallet != nil {
                ActionButtonsView()
                AssetListView(assets: model.assets)
                Spacer(minLength: 0)
                Divider()
                NFTGridView(nfts: model.nfts)
            } else {
                NoWalletsView(model: model)
            }
        }
        .padding(24)
        .frame(minWidth: 480, minHeight: 640)
        .task { await model.refresh() }
        .sheet(isPresented: $model.isPresentingCreateWallet) {
            CreateWalletSheet(model: model)
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

    var body: some View {
        VStack(spacing: 16) {
            Spacer()
            Image("TezosToken")
                .resizable()
                .scaledToFit()
                .frame(width: 72, height: 72)
            Text("No addresses yet")
                .font(.title3.weight(.semibold))
            Text("Create your first Tezos address to see balances, domains and NFTs here.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
            Button("Create address…") { model.isPresentingCreateWallet = true }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut("n", modifiers: .command)
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
