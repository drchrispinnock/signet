import SwiftUI

/// A balance-first dashboard retaining the account and activity flows from spec/EXAMPLE.png.
/// With no wallets yet it shows a prompt to create the first address instead.
struct WalletHomeView: View {
    @Bindable var model: WalletViewModel
    @State var hidesBalances = false
    @State var showsBalanceDetails = false
    @State var navigationPanel: WalletNavigationPage?
    @State private var pendingNavigationAction: WalletNavigationAction?

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                content
                    .padding(24)
                    .frame(maxWidth: 760)
                    .frame(maxWidth: .infinity, alignment: .top)
            }
            .background(Theme.canvas)
        }
        .frame(minWidth: 520, minHeight: 760)
        .tint(Theme.violet)
        .appliesStoredAppearance()
        .showsLaunchDisclaimer()
        .task {
            model.nodeMonitor.start()
            await model.refresh()
        }
        .sheet(item: $navigationPanel, onDismiss: finishNavigation) { page in
            WalletNavigationSheet(model: model, page: page) { action in
                pendingNavigationAction = action
                navigationPanel = nil
            }
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
        .sheet(isPresented: $model.isPresentingSwap) {
            ConnectDAppSheet(model: model, isSwapFlow: true)
        }
        .sheet(isPresented: $model.isPresentingBuy) {
            if AppRuntime.isDemo {
                DemoNoticeSheet(title: "Buy tez", message: "Purchases are unavailable in this frontend demo.")
            } else {
                BuySheet(model: model)
            }
        }
        .sheet(isPresented: $model.isPresentingFaucet) {
            if AppRuntime.isDemo {
                DemoNoticeSheet(title: "Get test tez", message: "Faucet requests are unavailable in this frontend demo.")
            } else {
                FaucetSheet(model: model)
            }
        }
        .sheet(isPresented: $model.isPresentingConnectDApp) {
            if AppRuntime.isDemo {
                DemoNoticeSheet(title: "Connect to a dApp", message: "Live dApp pairing is unavailable in this frontend demo.")
            } else {
                ConnectDAppSheet(model: model)
            }
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
        VStack(alignment: .leading, spacing: 28) {
            if let wallet = model.selectedWallet {
                HStack(alignment: .center, spacing: 16) {
                    WalletIdentityView(model: model, wallet: wallet) { navigationPanel = .accounts }
                        .tint(.primary)
                    Spacer(minLength: 0)
                    HStack(spacing: 6) {
                        Button {
                            hidesBalances.toggle()
                            if hidesBalances { showsBalanceDetails = false }
                        } label: {
                            Image(systemName: hidesBalances ? "eye.slash" : "eye")
                                .font(.system(size: 18))
                                .frame(width: 36, height: 36)
                                .contentShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .help(hidesBalances ? "Show balances" : "Hide balances")
                        .accessibilityLabel(hidesBalances ? "Show balances" : "Hide balances")
                        AppMenuButton { navigationPanel = .actions }
                    }
                    .padding(6)
                    .background(Color.primary.opacity(0.035), in: Capsule())

                }

                VStack(spacing: 24) {
                    balanceSummary
                    ActionButtonsView(model: model)
                }
                .padding(24)
                .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 24))

                if model.accountNotOnChain {
                    AccountNotOnChainView(model: model, wallet: wallet)
                }
                ActivityTabsView(model: model, hidesBalances: hidesBalances)
                    .frame(height: 360)
            } else {
                HStack {
                    Text("Signet")
                        .font(.title3.weight(.semibold))
                    Spacer()
                    AppMenuButton { navigationPanel = .actions }
                }
                NoWalletsView(model: model)
                    .frame(minHeight: 620)
            }
        }
    }

    private func finishNavigation() {
        guard let action = pendingNavigationAction else { return }
        pendingNavigationAction = nil
        switch action {
        case .create: model.isPresentingCreateWallet = true
        case .importAccount: model.isPresentingImportAccount = true
        case .ledger: model.isPresentingConnectLedger = true
        case .rename: model.isPresentingRenameWallet = true
        case .exportKey: model.isPresentingExportKey = true
        case .addAddress: model.isPresentingAddAddress = true
        case .forget: model.isPresentingForget = true
        case .connectDApp: model.isPresentingConnectDApp = true
        case .baking: model.isPresentingBaking = true
        case .governance: model.isPresentingGovernance = true
        case .swap: model.isPresentingSwap = true
        case .refresh: Task { await model.refresh() }
        }
    }

    private var balanceSummary: some View {
        VStack(spacing: 18) {
            if hidesBalances {
                Text("•••• tz")
                    .font(.system(size: 48, weight: .medium, design: .rounded))
                    .accessibilityLabel("Balance hidden")
            } else if model.accountNotOnChain {
                Text("Not funded yet")
                    .font(.system(size: 32, weight: .semibold, design: .rounded))
            } else if let tez = model.assets.first(where: { $0.kind == .tez }) {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { showsBalanceDetails.toggle() }
                } label: {
                    Text(tez.formattedAmount)
                        .font(.system(size: 48, weight: .medium, design: .rounded))
                        .monospacedDigit()
                        .minimumScaleFactor(0.45)
                        .lineLimit(1)
                        .contentTransition(.numericText())
                }
                .buttonStyle(.plain)
                .help(showsBalanceDetails ? "Hide balance breakdown" : "Show balance breakdown")
                .accessibilityLabel("\(tez.formattedAmount). \(showsBalanceDetails ? "Hide" : "Show") balance breakdown")
                .accessibilityValue(showsBalanceDetails ? "Expanded" : "Collapsed")

                if showsBalanceDetails {
                    VStack(spacing: 10) {
                        ForEach(tez.details) { detail in
                            HStack {
                                Text(detail.label).foregroundStyle(.secondary)
                                Spacer()
                                Text(AssetBalance.format(detail.amount, symbol: tez.symbol))
                                    .monospacedDigit()
                            }
                            .font(.callout)
                        }
                        let otherAssets = model.assets.filter { $0.kind != .tez }
                        if !otherAssets.isEmpty { AssetListView(assets: otherAssets) }
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            } else {
                Text(model.isLoading ? "Loading balance…" : "Balance unavailable")
                    .font(.title2.weight(.medium))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .onChange(of: model.selectedWallet?.id) { showsBalanceDetails = false }
        .onChange(of: model.network) { showsBalanceDetails = false }
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
            Image(systemName: "seal")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(Theme.violet)
                .padding(.bottom, 8)
            Text("Welcome to Signet")
                .font(.system(size: 32, weight: .semibold, design: .rounded))
                .multilineTextAlignment(.center)
            Text("Your Tezos, on your Mac.")
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
                    detail: "Generate a fresh key on this Mac and choose how to protect it.",
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
                    Text(detail)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 16).fill(prominent ? Theme.violet.opacity(0.10) : Theme.surface))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(prominent ? Theme.violet.opacity(0.6) : Color.secondary.opacity(0.15), lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: 16))
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

private struct DemoNoticeSheet: View {
    let title: String
    let message: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 20) {
            Text(title).font(.title2.weight(.semibold))
            Text(message).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
        }
        .padding(32)
        .frame(width: 420)
    }
}
