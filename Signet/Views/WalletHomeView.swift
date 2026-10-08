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
        .showsLaunchDisclaimer()
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
        .sheet(isPresented: $model.isPresentingConnectLedger) {
            ConnectLedgerSheet(model: model)
        }
        .sheet(isPresented: $model.isPresentingImportAccount) {
            ImportAccountSheet(model: model)
        }
        .sheet(isPresented: $model.isPresentingExportKey) {
            ExportKeySheet(model: model)
        }
        .sheet(isPresented: $model.isPresentingForget) {
            ForgetAccountSheet(model: model)
        }
        .sheet(isPresented: $model.isPresentingStaking) {
            StakingSheet(model: model)
        }
        .sheet(isPresented: $model.isPresentingBaking) {
            BakingSheet(model: model)
        }
        .sheet(isPresented: $model.isPresentingGovernance) {
            GovernanceSheet(model: model)
        }
        .sheet(isPresented: $model.isPresentingBuy) {
            BuySheet(model: model)
        }
        .sheet(isPresented: $model.isPresentingFaucet) {
            FaucetSheet(model: model)
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
                    NetworkBadgeMenu(model: model)
                    AppMenuButton(model: model)
                }
                ActionButtonsView(model: model)
                if model.accountNotOnChain {
                    AccountNotOnChainView(model: model, wallet: wallet)
                } else {
                    AssetListView(assets: model.assets)
                    DelegateRowView(model: model)
                }
                Divider()
                ActivityTabsView(model: model)
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

    private var hasOctezWallet: Bool { model.importableWalletCount > 0 }

    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .scaledToFit()
                .frame(width: 96, height: 96)
            Text("Welcome to Signet, a Tezos Wallet for the Mac.")
                .font(.title3.weight(.semibold))
                .multilineTextAlignment(.center)
            Text("How would you like to start?")
                .font(.callout)
                .foregroundStyle(.secondary)

            VStack(spacing: 10) {
                if hasOctezWallet {
                    StartOption(
                        title: "Import your octez-client wallet",
                        detail: "Found \(model.importableWalletCount) \(model.importableWalletCount == 1 ? "account" : "accounts") in ~/.tezos-client. Copies the files into ~/.signet; octez-client keeps working.",
                        symbol: "square.and.arrow.down.on.square",
                        prominent: true,
                        action: importWallets
                    )
                    .keyboardShortcut(.defaultAction)
                }
                StartOption(
                    title: "Create a new account",
                    detail: "Generate a fresh key on this Mac, protected with a password.",
                    symbol: "plus.circle",
                    prominent: !hasOctezWallet
                ) { model.isPresentingCreateWallet = true }
                    .keyboardShortcut("n", modifiers: .command)
                StartOption(
                    title: "Import an existing account",
                    detail: "From a secret key or a recovery phrase of 12 to 24 words.",
                    symbol: "key.horizontal"
                ) { model.isPresentingImportAccount = true }
                    .keyboardShortcut("i", modifiers: [.command, .shift])
                StartOption(
                    title: "Connect a Ledger",
                    detail: "Use a key that stays on your hardware wallet.",
                    symbol: "lock.rectangle.stack"
                ) { model.isPresentingConnectLedger = true }
                    .keyboardShortcut("l", modifiers: [.command, .shift])
            }
            .frame(maxWidth: 440)

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

/// One of the ways to start on a cold boot: an icon, a title, a line of detail and a chevron.
private struct StartOption: View {
    let title: String
    let detail: String
    let symbol: String
    var prominent = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: symbol)
                    .font(.title2)
                    .frame(width: 32)
                    .foregroundStyle(prominent ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.secondary))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.body.weight(.semibold))
                    Text(detail).font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.secondary.opacity(prominent ? 0.14 : 0.08)))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(prominent ? Color.accentColor.opacity(0.6) : Color.secondary.opacity(0.3), lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title). \(detail)")
    }
}

#Preview("With wallets") {
    WalletHomeView(model: .preview())
}

#Preview("Empty") {
    WalletHomeView(model: WalletViewModel(wallets: [], chain: MockChainService()))
}
