import SwiftUI

/// Send tez: compose (recipient + amount), confirm (you → them), then the result.
struct SendSheet: View {
    @Bindable var model: WalletViewModel
    @State private var send: SendViewModel
    @Environment(\.dismiss) private var dismiss

    init(model: WalletViewModel, sender: Wallet) {
        self.model = model
        _send = State(initialValue: SendViewModel(
            sender: sender,
            wallets: model.wallets,
            chain: model.chainService,
            spendable: model.tezBalance?.spendable,
            secretKeyProvider: { [model] wallet in try model.secretKey(for: wallet) }
        ))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            switch send.step {
            case .compose:
                ComposeTransferView(send: send, network: model.network, onCancel: { dismiss() })
            case .confirm, .sending:
                ConfirmTransferView(send: send, network: model.network)
            case .sent, .confirmed:
                TransferResultView(send: send, network: model.network, onDone: {
                    dismiss()
                    Task { await model.refresh() }
                })
            }
        }
        .padding(20)
        .frame(width: 520)
        .animation(.easeInOut(duration: 0.15), value: send.step)
    }
}

// MARK: - Step 1

private struct ComposeTransferView: View {
    @Bindable var send: SendViewModel
    let network: Network
    let onCancel: () -> Void
    @FocusState private var focus: Field?
    private enum Field { case recipient, amount }

    var body: some View {
        Text("Send tez")
            .font(.title2.weight(.semibold))

        Form {
            LabeledContent("From") {
                HStack(spacing: 8) {
                    AccountAvatarView(address: send.sender.address, network: network, size: 24)
                    Text(send.sender.alias)
                    Text(send.sender.address.shortened()).font(.callout.monospaced()).foregroundStyle(.secondary)
                    Spacer()
                    if let spendable = send.spendable {
                        Text("\(AssetBalance.format(spendable, symbol: "tz")) spendable")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                TextField("To", text: $send.recipientText, prompt: Text("Address, name.tez, or a wallet from your list"))
                    .font(.body.monospaced())
                    .focused($focus, equals: .recipient)
                    .autocorrectionDisabled()
                recipientStatus
                if send.recipient == nil, !send.suggestions.isEmpty {
                    suggestionList
                }
            }

            HStack {
                TextField("Amount", text: $send.amountText, prompt: Text("0.0"))
                    .font(.body.monospacedDigit())
                    .focused($focus, equals: .amount)
                    .onSubmit { if send.canProceed { Task { await send.proceedToConfirm() } } }
                Text("tz").foregroundStyle(.secondary)
                Button("Max") { send.useMaximum() }
                    .disabled(send.spendable == nil)
                    .help("Everything except a small reserve for the fee")
            }
        }
        .formStyle(.grouped)
        .scrollDisabled(true)

        if let error = send.errorMessage {
            Text(error).font(.callout).foregroundStyle(.red)
        }

        HStack {
            Spacer()
            Button("Cancel", role: .cancel, action: onCancel)
                .keyboardShortcut(.cancelAction)
            Button("Continue") { Task { await send.proceedToConfirm() } }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(!send.canProceed)
        }
        .onAppear { focus = .recipient }
    }

    @ViewBuilder
    private var recipientStatus: some View {
        if let recipient = send.recipient {
            HStack(spacing: 8) {
                AccountAvatarView(address: recipient.address, network: network, size: 20)
                Text(recipient.displayName).font(.callout)
                verificationTag(recipient)
                if recipient.wallet == nil, let domain = recipient.domains.first, domain != recipient.displayName {
                    Text(domain).font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
            }
        } else if send.isResolving {
            HStack(spacing: 6) { ProgressView().controlSize(.mini); Text("Looking up name…").font(.callout).foregroundStyle(.secondary) }
        } else if !send.recipientText.isEmpty, send.suggestions.isEmpty {
            Label("Not a valid address or .tez name", systemImage: "exclamationmark.triangle")
                .font(.callout).foregroundStyle(.secondary)
        }
    }

    private var suggestionList: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(send.suggestions.prefix(6)) { wallet in
                Button { send.choose(wallet) } label: {
                    HStack(spacing: 8) {
                        AccountAvatarView(address: wallet.address, network: network, size: 20)
                        Text(wallet.alias)
                        Text(wallet.address.shortened()).font(.callout.monospaced()).foregroundStyle(.secondary)
                        Spacer()
                        Text(wallet.keyKind == KeyKind.none ? "Address book" : "My wallet")
                            .font(.caption).foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, 4)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }
}

/// "Verified" when the recipient is one of ours; otherwise the name is hearsay from an indexer.
@ViewBuilder
func verificationTag(_ recipient: SendViewModel.Recipient) -> some View {
    if recipient.isVerified {
        Label(recipient.wallet?.keyKind == KeyKind.none ? "Address book" : "My wallet", systemImage: "checkmark.seal.fill")
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(Capsule().fill(.green.opacity(0.15)))
            .foregroundStyle(.green)
    } else {
        Label("Not verified", systemImage: "questionmark.circle")
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(Capsule().fill(.orange.opacity(0.15)))
            .foregroundStyle(.orange)
            .help("This name comes from the recipient's public profile (TzProfiles via TzKT), not from your own records. Check the address.")
    }
}

// MARK: - Step 2

struct ConfirmTransferView: View {
    @Bindable var send: SendViewModel
    let network: Network

    var body: some View {
        Text("Confirm")
            .font(.title2.weight(.semibold))

        if let recipient = send.recipient, let amount = send.amount {
            HStack(alignment: .top, spacing: 0) {
                party(address: send.sender.address, name: send.sender.alias, subtitle: send.sender.address.shortened(), tag: nil)
                VStack(spacing: 4) {
                    Image(systemName: "arrow.right")
                        .font(.title.weight(.semibold))
                        .foregroundStyle(Theme.tezosBlue)
                    Text(AssetBalance.format(amount, symbol: "tz"))
                        .font(.headline.monospacedDigit())
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 28)
                party(address: recipient.address, name: recipient.displayName,
                      subtitle: recipient.domains.first.flatMap { $0 == recipient.displayName ? nil : $0 } ?? recipient.address.shortened(),
                      tag: AnyView(verificationTag(recipient)))
            }
            .padding(.vertical, 8)

            Form {
                LabeledContent("To", value: recipient.address.value)
                    .font(.callout.monospaced())
                if let estimate = send.estimate {
                    LabeledContent("Amount", value: AssetBalance.format(amount, symbol: "tz"))
                    LabeledContent("Fee", value: AssetBalance.format(estimate.fee, symbol: "tz"))
                    if estimate.burn > 0 {
                        LabeledContent("Allocation") {
                            VStack(alignment: .trailing) {
                                Text(AssetBalance.format(estimate.burn, symbol: "tz"))
                                Text("The recipient has never held tez; the chain charges once to create the account.")
                                    .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.trailing)
                            }
                        }
                    }
                    LabeledContent("Total", value: AssetBalance.format(estimate.total, symbol: "tz"))
                        .fontWeight(.semibold)
                }
            }
            .formStyle(.grouped)
            .scrollDisabled(true)
        }

        if let error = send.errorMessage {
            Text(error).font(.callout).foregroundStyle(.red)
        }

        HStack {
            if send.step == .sending {
                ProgressView().controlSize(.small)
                Text("Signing and sending…").font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Back") { send.backToCompose() }
                .disabled(send.step == .sending)
            Button("Confirm and Send") { Task { await send.send() } }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(send.step == .sending || send.isBusy)
        }
    }

    private func party(address: Address, name: String, subtitle: String, tag: AnyView?) -> some View {
        VStack(spacing: 6) {
            AccountAvatarView(address: address, network: network, size: 72)
            Text(name).font(.headline).lineLimit(1)
            Text(subtitle).font(.callout.monospaced()).foregroundStyle(.secondary).lineLimit(1)
            if let tag { tag }
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Step 3

private struct TransferResultView: View {
    let send: SendViewModel
    let network: Network
    let onDone: () -> Void

    var body: some View {
        switch send.step {
        case .sent(let hash):
            resultHeader(systemImage: "paperplane.fill", title: "Sent", subtitle: "Waiting for the next block…", spinning: true)
            operationLink(hash)
        case .confirmed(let hash, let level):
            resultHeader(systemImage: "checkmark.circle.fill", title: "Confirmed", subtitle: "Included in block \(level.formatted())", spinning: false)
            operationLink(hash)
        default:
            EmptyView()
        }
        if let error = send.errorMessage {
            Text(error).font(.callout).foregroundStyle(.red)
        }
        HStack {
            Spacer()
            Button("Done", action: onDone).keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent)
        }
    }

    private func resultHeader(systemImage: String, title: String, subtitle: String, spinning: Bool) -> some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage).font(.largeTitle).foregroundStyle(spinning ? Theme.tezosBlue : .green)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.title2.weight(.semibold))
                HStack(spacing: 6) {
                    if spinning { ProgressView().controlSize(.mini) }
                    Text(subtitle).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func operationLink(_ hash: String) -> some View {
        HStack(spacing: 8) {
            Text(hash).font(.callout.monospaced()).textSelection(.enabled).lineLimit(1).truncationMode(.middle)
            if network.isMainnet, let url = URL(string: "https://tzkt.io/\(hash)") {
                Link("View on TzKT", destination: url).font(.callout)
            }
        }
    }
}
