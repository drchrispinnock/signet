import SwiftUI

/// Transfers a fungible token from the Assets tab: an amount in the token's own units (or Max,
/// the exact balance), the recipient (an address, a `.tez` name or one of our accounts, as in
/// Send), the fee and storage burn from the estimate, then the result. FA2 and FA1.2 tokens go
/// through the same approved-limits path as NFTs (`TokenTransferRequest`, S14), bound to the
/// account, network and directory the estimate was made in (S31).
struct TransferTokenSheet: View {
    @Bindable var model: WalletViewModel
    let token: AssetBalance
    @Environment(\.dismiss) private var dismiss

    enum Step: Hashable { case compose, working, done(hash: String, level: Int) }

    @State private var recipient: SendViewModel
    @State private var amountText = ""
    @State private var estimate: WalletViewModel.TokenTransferApproval?
    @State private var estimateError: String?
    @State private var passphrase = ""
    @State private var errorMessage: String?
    @State private var step: Step = .compose
    @State private var submitted: WalletViewModel.TokenTransferApproval?
    @FocusState private var amountFocused: Bool

    init(model: WalletViewModel, token: AssetBalance) {
        self.model = model
        self.token = token
        let sender = model.selectedWallet ?? Wallet(alias: "", address: Address(""), keyKind: .none)
        let chain = token.layer == 2 ? (model.layer2Chain ?? model.chainService) : model.chainService
        _recipient = State(initialValue: SendViewModel(sender: sender, wallets: model.wallets, chain: chain, spendable: nil,
                                                       implicitAccountsOnly: token.layer == 2, signerProvider: { _, _ in nil }))
    }

    private var wallet: Wallet? { submitted?.context.wallet ?? model.selectedWallet }
    private var network: Network { model.tokenNetwork(on: token.layer) }
    private var needsPassphrase: Bool { wallet?.keyKind == .encrypted }
    private var signsOnLedger: Bool { wallet?.keyKind == .ledger }
    private var symbol: String { token.symbol.isEmpty ? token.name : token.symbol }

    /// The amount typed, in the token's smallest unit, when it is sound and within the balance.
    private var rawAmount: String? {
        guard let raw = TokenTransfer.rawAmount(from: amountText, decimals: token.decimals), let balance = token.rawAmount,
              TokenTransfer.nat(raw, isAtMost: balance) else { return nil }
        return raw
    }
    private var exceedsBalance: Bool {
        guard let raw = TokenTransfer.rawAmount(from: amountText, decimals: token.decimals), let balance = token.rawAmount else { return false }
        return !TokenTransfer.nat(raw, isAtMost: balance)
    }
    private var request: TokenTransferRequest? {
        if let submitted { return submitted.request }
        guard let to = recipient.recipient?.address, let rawAmount, let transfer = TokenTransfer(token: token, rawAmount: rawAmount) else { return nil }
        let request = TokenTransferRequest(to: to, transfers: [transfer])
        return request.isValid ? request : nil
    }
    private var canConfirm: Bool {
        guard let request, let estimate, estimate.request == request, estimate.context == model.bridgeContext else { return false }
        return step == .compose && model.canTransferToken(token) && !(needsPassphrase && passphrase.isEmpty)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            switch step {
            case .compose:
                form
            case .working:
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Transferring \(amountText) \(symbol)…").font(.callout).foregroundStyle(.secondary)
                }
                if signsOnLedger { LedgerPromptLabel(text: "Confirm the transfer on your Ledger…") }
            case .done(let hash, let level):
                doneView(hash: hash, level: level)
            }
            if let errorMessage { Text(errorMessage).font(.callout).foregroundStyle(.red) }
            buttons
        }
        .padding(20)
        .frame(width: 520)
        .task(id: EstimateKey(request: request, context: model.bridgeContext, step: step)) { await refreshEstimate() }
        .onAppear { amountFocused = true }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Transfer \(symbol)\(token.isLayer2 ? " on \(Brand.l2)" : "")").font(.title2.weight(.semibold))
            if let wallet { Text("From \(wallet.alias)  \(wallet.address.shortened())").font(.callout).foregroundStyle(.secondary) }
            Text("Balance \(token.formattedAmount)").font(.callout.monospacedDigit()).foregroundStyle(.secondary)
        }
    }

    private var form: some View {
        Form {
            LabeledContent("Amount") {
                HStack(spacing: 6) {
                    TextField("", text: $amountText, prompt: Text("0"))
                        .multilineTextAlignment(.trailing).frame(width: 160)
                        .focused($amountFocused)
                    Text(symbol).foregroundStyle(.secondary)
                    Button("Max") { amountText = AssetBalance.plainAmount(raw: token.rawAmount ?? "0", decimals: token.decimals) }
                        .controlSize(.small)
                }
            }
            if exceedsBalance {
                Text("More than the balance.").font(.caption).foregroundStyle(.orange)
            } else if !amountText.isEmpty, TokenTransfer.rawAmount(from: amountText, decimals: token.decimals) == nil {
                Text(token.decimals == 0 ? "A whole number." : "A number with at most \(token.decimals) decimal places.").font(.caption).foregroundStyle(.orange)
            }
            VStack(alignment: .leading, spacing: 6) {
                TextField("To", text: $recipient.recipientText, prompt: Text(recipient.implicitAccountsOnly ? "tz1, tz2 or tz3 address, name.tez, or an account from your list" : "Address, name.tez, or an account from your list"))
                    .font(.body.monospaced())
                    .autocorrectionDisabled()
                recipientStatus
                if recipient.recipient == nil, !recipient.suggestions.isEmpty { suggestionList }
            }
            if let estimate = estimate?.estimate {
                LabeledContent("Fee", value: AssetBalance.format(estimate.fee, symbol: "tz"))
                if estimate.burn > 0 {
                    LabeledContent("Storage", value: AssetBalance.format(estimate.burn, symbol: "tz"))
                        .help("The token's ledger grows for a recipient that has not held it before; the chain charges for the space.")
                }
            } else if request != nil {
                LabeledContent("Fee") {
                    if let estimateError { Text(estimateError).font(.callout).foregroundStyle(.orange).multilineTextAlignment(.trailing) }
                    else { ProgressView().controlSize(.small) }
                }
            }
            if needsPassphrase, let wallet { SecureField("Password for “\(wallet.alias)”", text: $passphrase) }
            if !model.canTransferToken(token) {
                Text(token.layer == 2 ? "Transfers on \(Brand.l2) need Layer 2 on and a tz1, tz2 or tz3 account Signet can sign for." : "Signet cannot sign for this account.")
                    .font(.callout).foregroundStyle(.orange)
            }
        }
        .formStyle(.grouped)
        .scrollDisabled(true)
    }

    @ViewBuilder
    private var recipientStatus: some View {
        if let resolved = recipient.recipient {
            HStack(spacing: 8) {
                AccountAvatarView(address: resolved.address, size: 20)
                Text(resolved.displayName).font(.callout)
                Spacer()
            }
        } else if recipient.isResolving {
            HStack(spacing: 6) { ProgressView().controlSize(.mini); Text("Looking up name…").font(.callout).foregroundStyle(.secondary) }
        } else if let error = recipient.errorMessage {
            Text(error).font(.callout).foregroundStyle(.red)
        } else if !recipient.recipientText.isEmpty, recipient.suggestions.isEmpty {
            Label("Not a valid address or .tez name", systemImage: "exclamationmark.triangle").font(.callout).foregroundStyle(.secondary)
        }
    }

    private var suggestionList: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(recipient.suggestions.prefix(6)) { candidate in
                Button { recipient.choose(candidate) } label: {
                    HStack(spacing: 8) {
                        AccountAvatarView(address: candidate.address, size: 20)
                        Text(candidate.alias)
                        Text(candidate.address.shortened()).font(.callout.monospaced()).foregroundStyle(.secondary)
                        Spacer()
                    }
                    .padding(.vertical, 4)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func doneView(hash: String, level: Int) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Transferred \(amountText) \(symbol) to \(submitted.map { $0.request.to.shortened() } ?? "the recipient")", systemImage: "checkmark.seal.fill").foregroundStyle(.green)
            Text("Included in block \(level.formatted()). The Assets tab updates on the next refresh.").font(.callout).foregroundStyle(.secondary)
            HStack(spacing: 8) {
                Text(hash).font(.callout.monospaced()).textSelection(.enabled).lineLimit(1).truncationMode(.middle)
                if let url = network.explorerURL(operation: hash) { Link("View in explorer", destination: url) }
            }
        }
    }

    private var buttons: some View {
        HStack {
            Spacer()
            switch step {
            case .compose:
                Button("Cancel", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Transfer") { Task { await send() } }
                    .keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent).disabled(!canConfirm)
            case .working:
                Button("Cancel", role: .cancel) { dismiss() }.disabled(true)
            case .done:
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent)
            }
        }
    }

    private struct EstimateKey: Hashable {
        let request: TokenTransferRequest?
        let context: WalletViewModel.BridgeContext?
        let step: Step
    }

    private func refreshEstimate() async {
        estimate = nil
        estimateError = nil
        guard step == .compose, let request, model.canTransferToken(token) else { return }
        try? await Task.sleep(for: .milliseconds(300))
        guard !Task.isCancelled else { return }
        do {
            let result = try await model.estimateTokenTransfer(request, on: token.layer)
            if !Task.isCancelled { estimate = result }
        } catch {
            if !Task.isCancelled { estimateError = error.localizedDescription }
        }
    }

    private func send() async {
        guard let request, let approved = estimate else { return }
        errorMessage = nil
        submitted = approved
        step = .working
        do {
            let (hash, level) = try await model.transferTokens(request, on: token.layer, approved: approved, passphrase: needsPassphrase ? passphrase : nil)
            step = .done(hash: hash, level: level)
        } catch {
            errorMessage = error.localizedDescription
            submitted = nil
            step = .compose
        }
    }
}
