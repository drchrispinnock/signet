import SwiftUI

/// Transfers or burns the NFTs chosen in the grid (0.9.13): the tokens with how many editions
/// of each, the recipient (an address, a `.tez` name or one of our accounts; the burn address
/// for a burn), the fee and storage burn from the estimate, then the result. One FA2
/// `transfer` call per contract goes out in one operation group with the approved limits
/// (S14), bound to the account, network and directory the estimate was made in (S31).
struct TransferNFTSheet: View {
    @Bindable var model: WalletViewModel
    let operation: NFTOperation
    @Environment(\.dismiss) private var dismiss

    enum Step: Hashable { case compose, working, done(hash: String, level: Int) }

    /// Resolves the recipient as the Send sheet does (names, suggestions, Etherlink's tz1–tz3 rule).
    @State private var recipient: SendViewModel
    /// Editions of each token to move; a token held once has no choice.
    @State private var counts: [NFT.ID: Int]
    @State private var estimate: WalletViewModel.TokenTransferApproval?
    @State private var estimateError: String?
    @State private var passphrase = ""
    @State private var understoodBurn = false
    @State private var errorMessage: String?
    @State private var step: Step = .compose
    @State private var submitted: WalletViewModel.TokenTransferApproval?
    @FocusState private var recipientFocused: Bool

    init(model: WalletViewModel, operation: NFTOperation) {
        self.model = model
        self.operation = operation
        let sender = model.selectedWallet ?? Wallet(alias: "", address: Address(""), keyKind: .none)
        let chain = operation.layer == 2 ? (model.layer2Chain ?? model.chainService) : model.chainService
        _recipient = State(initialValue: SendViewModel(sender: sender, wallets: model.wallets, chain: chain, spendable: nil,
                                                       implicitAccountsOnly: operation.layer == 2, signerProvider: { _, _ in nil }))
        _counts = State(initialValue: Dictionary(uniqueKeysWithValues: operation.nfts.map { ($0.id, 1) }))
    }

    private var isBurn: Bool { operation.kind == .burn }
    private var wallet: Wallet? { submitted?.context.wallet ?? model.selectedWallet }
    private var network: Network { model.tokenNetwork(on: operation.layer) }
    private var needsPassphrase: Bool { wallet?.keyKind == .encrypted }
    private var signsOnLedger: Bool { wallet?.keyKind == .ledger }
    private var title: String {
        let what = operation.nfts.count == 1 ? "NFT" : "\(operation.nfts.count) NFTs"
        return (isBurn ? "Burn " : "Transfer ") + what + (operation.layer == 2 ? " on Etherlink" : "")
    }

    /// The request as composed, once it is complete and sound.
    private var request: TokenTransferRequest? {
        if let submitted { return submitted.request }
        guard let to = isBurn ? TokenTransferRequest.burnAddress : recipient.recipient?.address else { return nil }
        let transfers = operation.nfts.map { TokenTransfer(nft: $0, amount: counts[$0.id] ?? 1) }
        guard operation.nfts.allSatisfy({ (counts[$0.id] ?? 1) >= 1 && Decimal(counts[$0.id] ?? 1) <= $0.balance }) else { return nil }
        let request = TokenTransferRequest(to: to, transfers: transfers)
        return request.isValid ? request : nil
    }
    private var editions: Int { operation.nfts.reduce(0) { $0 + (counts[$1.id] ?? 1) } }
    private var canConfirm: Bool {
        guard let request, let estimate, estimate.request == request, estimate.context == model.bridgeContext else { return false }
        return step == .compose && model.canTransferTokens(on: operation.layer) && !(needsPassphrase && passphrase.isEmpty) && (!isBurn || understoodBurn)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            tokens
            switch step {
            case .compose:
                form
            case .working:
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(isBurn ? "Burning…" : "Transferring…").font(.callout).foregroundStyle(.secondary)
                }
                if signsOnLedger { LedgerPromptLabel(text: "Confirm the \(isBurn ? "burn" : "transfer") on your Ledger…") }
            case .done(let hash, let level):
                doneView(hash: hash, level: level)
            }
            if let errorMessage { Text(errorMessage).font(.callout).foregroundStyle(.red) }
            buttons
        }
        .padding(20)
        .frame(width: 560)
        .task(id: EstimateKey(request: request, context: model.bridgeContext, step: step)) { await refreshEstimate() }
    }

    // MARK: Pieces

    private var header: some View {
        HStack(spacing: 12) {
            if let wallet { AccountAvatarView(address: wallet.address, size: 40) }
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.title2.weight(.semibold))
                if let wallet { Text("From \(wallet.alias)  \(wallet.address.shortened())").font(.callout).foregroundStyle(.secondary) }
            }
        }
    }

    /// The tokens going, with a count for those held in several editions.
    private var tokens: some View {
        ScrollView(.vertical) {
            VStack(spacing: 0) {
                ForEach(operation.nfts) { nft in
                    HStack(spacing: 10) {
                        NFTTileView(nft: nft).frame(width: 44).labelsHidden()
                        VStack(alignment: .leading, spacing: 2) {
                            Text(nft.name).lineLimit(1).truncationMode(.tail)
                            Text("\(Address(nft.contract).shortened()) #\(nft.tokenId)").font(.caption.monospaced()).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if nft.balance > 1 {
                            let held = NSDecimalNumber(decimal: nft.balance).intValue
                            Stepper(value: Binding(get: { counts[nft.id] ?? 1 }, set: { counts[nft.id] = min(max(1, $0), held) }), in: 1...max(1, held)) {
                                Text("\(counts[nft.id] ?? 1) of \(held)").font(.callout.monospacedDigit())
                            }
                            .disabled(step != .compose)
                            .help("How many of the \(held) editions held to \(isBurn ? "burn" : "transfer")")
                        }
                    }
                    .padding(.vertical, 6)
                    if nft.id != operation.nfts.last?.id { Divider() }
                }
            }
            .padding(.horizontal, 4)
        }
        .frame(maxHeight: CGFloat(min(operation.nfts.count, 4)) * 60)
        .background(RoundedRectangle(cornerRadius: 8).fill(.quaternary.opacity(0.4)))
    }

    private var form: some View {
        Form {
            if isBurn {
                VStack(alignment: .leading, spacing: 6) {
                    Label("Burning is permanent.", systemImage: "flame.fill").foregroundStyle(.orange).font(.headline)
                    Text("The tokens go to \(TokenTransferRequest.burnAddress.shortened()), an address nobody holds the key to, and can never be recovered or sold.")
                        .font(.callout).foregroundStyle(.secondary)
                    Toggle("I understand that \(editions == 1 ? "this token" : "these \(editions) tokens") will be gone for good", isOn: $understoodBurn)
                }
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    TextField("To", text: $recipient.recipientText, prompt: Text(recipient.implicitAccountsOnly ? "tz1, tz2 or tz3 address, name.tez, or an account from your list" : "Address, name.tez, or an account from your list"))
                        .font(.body.monospaced())
                        .focused($recipientFocused)
                        .autocorrectionDisabled()
                    recipientStatus
                    if recipient.recipient == nil, !recipient.suggestions.isEmpty { suggestionList }
                }
            }
            if let estimate = estimate?.estimate {
                LabeledContent("Fee", value: AssetBalance.format(estimate.fee, symbol: "tz"))
                if estimate.burn > 0 {
                    LabeledContent("Storage", value: AssetBalance.format(estimate.burn, symbol: "tz"))
                        .help("The contract's ledger grows for a recipient that has not held the token before; the chain charges for the space.")
                }
                LabeledContent("Total", value: AssetBalance.format(estimate.total, symbol: "tz"))
            } else if request != nil {
                LabeledContent("Fee") {
                    if let estimateError { Text(estimateError).font(.callout).foregroundStyle(.orange).multilineTextAlignment(.trailing) }
                    else { ProgressView().controlSize(.small) }
                }
            }
            if needsPassphrase, let wallet { SecureField("Password for “\(wallet.alias)”", text: $passphrase) }
            if !model.canTransferTokens(on: operation.layer) {
                Text(operation.layer == 2 ? "Transfers on Etherlink need Layer 2 on and a tz1, tz2 or tz3 account Signet can sign for." : "Signet cannot sign for this account.")
                    .font(.callout).foregroundStyle(.orange)
            }
        }
        .formStyle(.grouped)
        .scrollDisabled(true)
        .onAppear { recipientFocused = !isBurn }
    }

    @ViewBuilder
    private var recipientStatus: some View {
        if let resolved = recipient.recipient {
            HStack(spacing: 8) {
                AccountAvatarView(address: resolved.address, size: 20)
                Text(resolved.displayName).font(.callout)
                verificationTag(resolved)
                if resolved.wallet == nil, let domain = resolved.domains.first, domain != resolved.displayName {
                    Text(domain).font(.callout).foregroundStyle(.secondary)
                }
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
                        Text(candidate.keyKind == KeyKind.none ? "Address book" : "My account").font(.caption).foregroundStyle(.tertiary)
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
            let what = editions == 1 ? "1 token" : "\(editions) tokens"
            Label(isBurn ? "Burnt \(what)" : "Transferred \(what) to \(submitted.map { $0.request.to.shortened() } ?? "the recipient")", systemImage: "checkmark.seal.fill").foregroundStyle(.green)
            Text("Included in block \(level.formatted()). The NFTs tab updates on the next refresh.").font(.callout).foregroundStyle(.secondary)
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
                Button(isBurn ? "Burn" : "Transfer") { Task { await send() } }
                    .keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent).tint(isBurn ? .orange : nil).disabled(!canConfirm)
            case .working:
                Button("Cancel", role: .cancel) { dismiss() }.disabled(true)
            case .done:
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent)
            }
        }
    }

    // MARK: Actions

    /// Everything the estimate depends on: the request itself, and a change of account, network,
    /// node or wallet directory drops the old estimate and asks again (S31).
    private struct EstimateKey: Hashable {
        let request: TokenTransferRequest?
        let context: WalletViewModel.BridgeContext?
        let step: Step
    }

    private func refreshEstimate() async {
        estimate = nil
        estimateError = nil
        guard step == .compose, let request, model.canTransferTokens(on: operation.layer) else { return }
        try? await Task.sleep(for: .milliseconds(300))
        guard !Task.isCancelled else { return }
        do {
            let result = try await model.estimateTokenTransfer(request, on: operation.layer)
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
            let (hash, level) = try await model.transferTokens(request, on: operation.layer, approved: approved, passphrase: needsPassphrase ? passphrase : nil)
            step = .done(hash: hash, level: level)
        } catch {
            errorMessage = error.localizedDescription
            submitted = nil
            step = .compose
        }
    }
}

#Preview {
    TransferNFTSheet(model: .preview(), operation: NFTOperation(kind: .transfer, nfts: [NFT(id: "k:1", contract: "KT1RJ6PbjHpwc3M5rw5s2Nbmefwbuwbdxton", tokenId: "1", name: "Preview", balance: 3, thumbnailURL: nil)]))
}
