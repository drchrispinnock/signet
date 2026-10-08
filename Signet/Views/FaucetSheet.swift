import AppKit
import SwiftUI

/// Asks the current testnet's faucet to send tez to the selected wallet.
struct FaucetSheet: View {
    @Bindable var model: WalletViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var amountText = "\(Int(WalletViewModel.faucetAmountTez))"
    @State private var limits: (min: Double, max: Double)?

    private var wallet: Wallet? { model.selectedWallet }
    private var amount: Double? {
        guard let value = Double(amountText.trimmingCharacters(in: .whitespaces)), value > 0 else { return nil }
        if let limits, value < limits.min || value > limits.max { return nil }
        return value
    }
    private var isBusy: Bool {
        switch model.faucetStatus {
        case .solving, .sent: true
        default: false
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Get test tez")
                .font(.title2.weight(.semibold))

            Form {
                if let wallet {
                    LabeledContent("To") {
                        HStack(spacing: 8) {
                            AccountAvatarView(address: wallet.address, size: 24)
                            Text(wallet.alias)
                            Text(wallet.address.shortened()).font(.callout.monospaced()).foregroundStyle(.secondary)
                        }
                    }
                }
                LabeledContent("Faucet", value: model.network.faucetURL?.host() ?? "")
                HStack {
                    TextField("Amount", text: $amountText)
                        .font(.body.monospacedDigit())
                        .onSubmit { if amount != nil, !isBusy { request() } }
                    Text("tz").foregroundStyle(.secondary)
                    if let limits {
                        Text("\(Int(limits.min)) to \(Int(limits.max))").font(.callout).foregroundStyle(.secondary)
                    }
                }
                Text(model.network.faucetKind == .teztnets
                     ? "The faucet asks for a small proof of work before it pays out; Signet solves it for you. Test tez have no value."
                     : "The faucet pays out on request. Test tez have no value.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            .formStyle(.grouped)
            .scrollDisabled(true)

            status

            HStack {
                Spacer()
                Button(isBusy ? "Close" : "Done") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Request", action: request)
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(amount == nil || isBusy || wallet == nil)
            }
        }
        .padding(20)
        .frame(width: 460)
        .task {
            if let service = FaucetService(network: model.network), let info = try? await service.info() {
                limits = (info.minTez, info.maxTez)
                if WalletViewModel.faucetAmountTez > info.maxTez { amountText = "\(Int(info.maxTez))" }
            }
        }
    }

    @ViewBuilder
    private var status: some View {
        switch model.faucetStatus {
        case .idle:
            EmptyView()
        case .solving(let done, let total):
            HStack(spacing: 8) {
                ProgressView(value: Double(done), total: Double(max(total, 1))).frame(width: 160)
                Text("Solving faucet challenge \(min(done + 1, total)) of \(total)…").font(.callout).foregroundStyle(.secondary)
            }
        case .sent(let hash):
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Sent, waiting for the next block…").font(.callout).foregroundStyle(.secondary)
                Text(hash).font(.caption.monospaced()).lineLimit(1).truncationMode(.middle).textSelection(.enabled)
            }
        case .received(let hash):
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                Text("Received. Balance updated.").font(.callout)
                Text(hash).font(.caption.monospaced()).lineLimit(1).truncationMode(.middle).textSelection(.enabled)
            }
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle").font(.callout).foregroundStyle(.red)
        }
    }

    private func request() {
        guard let amount else { return }
        Task { await model.requestTestTez(amount: amount) }
    }
}

#Preview {
    FaucetSheet(model: .preview())
}
