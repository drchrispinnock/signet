import SwiftUI

/// Hands a Tezos Domains name to another account (Domains tab, right-click). A second-level
/// name moves as its FA2 token, which changes the owner but not where the name points, so
/// "Point it at the new account" (on by default) first sets the record's address to the
/// recipient with `update_record`; both go in one operation group. A subdomain has no token and
/// changes owner through `update_record` alone. The record's data is kept. Goes through the
/// same approved-limits path as tokens (`TezosDomain.transferParts`, S14, S31).
struct TransferDomainSheet: View {
    @Bindable var model: WalletViewModel
    let domain: TezosDomain
    @Environment(\.dismiss) private var dismiss

    enum Step: Hashable { case compose, working, done(hash: String, level: Int) }

    @State private var recipient: SendViewModel
    @State private var pointAtRecipient = true
    @State private var estimate: WalletViewModel.TokenTransferApproval?
    @State private var estimateError: String?
    @State private var passphrase = ""
    @State private var errorMessage: String?
    @State private var step: Step = .compose
    @State private var submitted: WalletViewModel.TokenTransferApproval?

    init(model: WalletViewModel, domain: TezosDomain) {
        self.model = model
        self.domain = domain
        let sender = model.selectedWallet ?? Wallet(alias: "", address: Address(""), keyKind: .none)
        _recipient = State(initialValue: SendViewModel(sender: sender, wallets: model.wallets, chain: model.chainService, spendable: nil,
                                                       implicitAccountsOnly: false, signerProvider: { _, _ in nil }))
    }

    private var wallet: Wallet? { submitted?.context.wallet ?? model.selectedWallet }
    private var needsPassphrase: Bool { wallet?.keyKind == .encrypted }
    private var signsOnLedger: Bool { wallet?.keyKind == .ledger }
    private var isSubdomain: Bool { domain.tokenId == nil }

    private var request: TokenTransferRequest? {
        if let submitted { return submitted.request }
        guard let owner = model.selectedWallet?.address, let to = recipient.recipient?.address,
              let parts = domain.transferParts(from: owner, to: to, pointAtRecipient: pointAtRecipient) else { return nil }
        let request = TokenTransferRequest(to: to, transfers: parts.transfers, records: parts.records)
        return request.isValid ? request : nil
    }
    private var canConfirm: Bool {
        guard let request, let estimate, estimate.request == request, estimate.context == model.bridgeContext else { return false }
        return step == .compose && model.canTransferDomain(domain) && !(needsPassphrase && passphrase.isEmpty)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Transfer \(domain.name)").font(.title2.weight(.semibold))
                if let wallet { Text("From \(wallet.alias)  \(wallet.address.shortened())").font(.callout).foregroundStyle(.secondary) }
            }
            switch step {
            case .compose:
                form
            case .working:
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Transferring \(domain.name)…").font(.callout).foregroundStyle(.secondary)
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
    }

    private var form: some View {
        Form {
            VStack(alignment: .leading, spacing: 6) {
                TextField("To", text: $recipient.recipientText, prompt: Text("Address, name.tez, or an account from your list"))
                    .font(.body.monospaced())
                    .autocorrectionDisabled()
                recipientStatus
                if recipient.recipient == nil, !recipient.suggestions.isEmpty { suggestionList }
            }
            Toggle("Point it at the new account", isOn: $pointAtRecipient)
            Text(pointAtRecipient
                 ? "\(domain.name) will resolve to the new account, so tez sent to the name go there."
                 : "\(domain.name) keeps pointing \(domain.address.map { $0 == model.selectedWallet?.address ? "at this account" : "where it does now" } ?? "nowhere") until its new owner changes it.")
                .font(.callout).foregroundStyle(.secondary)
            if isSubdomain {
                Text("A subdomain has no token of its own: its record is given to the new owner directly. Its parent's owner can still change it.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            if domain.isReverseRecord, pointAtRecipient {
                Text("It is this account's primary name; that stops when it points elsewhere.").font(.callout).foregroundStyle(.secondary)
            }
            if let estimate = estimate?.estimate {
                LabeledContent("Fee", value: AssetBalance.format(estimate.fee, symbol: "tz"))
                if estimate.burn > 0 { LabeledContent("Storage", value: AssetBalance.format(estimate.burn, symbol: "tz")) }
            } else if request != nil {
                LabeledContent("Fee") {
                    if let estimateError { Text(estimateError).font(.callout).foregroundStyle(.orange).multilineTextAlignment(.trailing) }
                    else { ProgressView().controlSize(.small) }
                }
            }
            if needsPassphrase, let wallet { SecureField("Password for “\(wallet.alias)”", text: $passphrase) }
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
            Label("Transferred \(domain.name) to \(submitted.map { $0.request.to.shortened() } ?? "the new owner")", systemImage: "checkmark.seal.fill").foregroundStyle(.green)
            Text("Included in block \(level.formatted()). Tezos Domains shows the change within a minute or so.").font(.callout).foregroundStyle(.secondary)
            HStack(spacing: 8) {
                Text(hash).font(.callout.monospaced()).textSelection(.enabled).lineLimit(1).truncationMode(.middle)
                if let url = model.network.explorerURL(operation: hash) { Link("View in explorer", destination: url) }
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
        guard step == .compose, let request, model.canTransferDomain(domain) else { return }
        try? await Task.sleep(for: .milliseconds(300))
        guard !Task.isCancelled else { return }
        do {
            let result = try await model.estimateTokenTransfer(request, on: 1)
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
            let (hash, level) = try await model.transferTokens(request, on: 1, approved: approved, passphrase: needsPassphrase ? passphrase : nil)
            step = .done(hash: hash, level: level)
            await model.reloadDomainList()
        } catch {
            errorMessage = error.localizedDescription
            submitted = nil
            step = .compose
        }
    }
}
