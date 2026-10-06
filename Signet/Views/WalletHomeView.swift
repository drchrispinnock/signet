import SwiftUI

/// The default screen from spec/EXAMPLE.png: header, action row, asset list, NFT grid.
/// With no wallets yet it shows a prompt to create the first address instead.
struct WalletHomeView: View {
    @Bindable var model: WalletViewModel

    var body: some View {
        VStack(spacing: 0) {
            content
                .padding(24)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            Divider()
            NodeStatusBar(monitor: model.nodeMonitor)
        }
        .frame(minWidth: 480, minHeight: 720)
        .appliesStoredAppearance()
        .task {
            model.nodeMonitor.start()
            await model.refresh()
        }
        .sheet(isPresented: $model.isPresentingCreateWallet) {
            CreateWalletSheet(model: model)
        }
        .sheet(isPresented: $model.isPresentingRenameWallet) {
            RenameWalletSheet(model: model)
        }
        .sheet(isPresented: $model.isPresentingAddAddress) {
            AddAddressSheet(model: model)
        }
        .sheet(isPresented: $model.isPresentingConnectDApp) {
            ConnectDAppSheet(model: model)
        }
        .sheet(item: Binding(get: { model.dapps.current }, set: { _ in })) { request in
            DAppRequestSheet(model: model, request: request)
                .interactiveDismissDisabled()
        }
        .sheet(isPresented: $model.isPresentingSend) {
            if let wallet = model.selectedWallet {
                SendSheet(model: model, sender: wallet)
            }
        }
        .sheet(isPresented: $model.isPresentingReceive) {
            if let wallet = model.selectedWallet {
                ReceiveSheet(wallet: wallet, domains: model.domains)
            }
        }
        .overlay(alignment: .bottom) {
            if let message = model.errorMessage {
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .padding(8)
                    .padding(.bottom, 28)
            }
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 24) {
            if let wallet = model.selectedWallet {
                HStack(alignment: .top) {
                    WalletIdentityView(model: model, wallet: wallet)
                    Spacer()
                    if !model.network.isMainnet {
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
                ActionButtonsView(model: model)
                if model.accountNotOnChain {
                    AccountNotOnChainView(model: model, wallet: wallet)
                } else {
                    AssetListView(assets: model.assets)
                }
                Divider()
                NFTGridView(nfts: model.nfts, isLoading: model.isLoading)
            } else {
                NoWalletsView(model: model)
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
