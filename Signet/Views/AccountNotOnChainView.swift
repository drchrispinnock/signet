import AppKit
import SwiftUI

/// Shown where the balance would be when the node has never seen the address, with the way to
/// fix it: buy tez on mainnet, or use the faucet on a testnet.
struct AccountNotOnChainView: View {
    @Bindable var model: WalletViewModel
    let wallet: Wallet
    @State private var copied = false

    private var network: Network { model.network }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 16) {
                ZStack {
                    Circle().fill(.orange.opacity(0.15))
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
                .frame(width: 44, height: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Key not found on chain")
                        .font(.title3.weight(.medium))
                    Text(explanation)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            HStack(spacing: 8) {
                if let faucet = network.faucetURL {
                    switch model.faucetStatus {
                    case .idle, .failed:
                        Button("Get \(Int(WalletViewModel.faucetAmountTez)) test tez") { Task { await model.requestTestTez() } }
                            .buttonStyle(.borderedProminent)
                    case .solving(let done, let total):
                        ProgressView(value: Double(done), total: Double(max(total, 1)))
                            .frame(width: 140)
                        Text("Solving faucet challenge \(min(done + 1, total)) of \(total)…")
                            .font(.callout).foregroundStyle(.secondary)
                    case .sent:
                        ProgressView().controlSize(.small)
                        Text("Tez sent, waiting for the next block…")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                    Button("Open faucet site…") { NSWorkspace.shared.open(faucet) }
                        .buttonStyle(.link)
                    Button(copied ? "Address copied" : "Copy address", systemImage: copied ? "checkmark" : "doc.on.doc", action: copyAddress)
                } else {
                    Button("Show address to receive tez…") { model.isPresentingReceive = true }
                        .buttonStyle(.borderedProminent)
                    Button("Buy tez") {}
                        .disabled(true)
                        .help("Buying tez in Signet is coming soon")
                }
            }
            .padding(.leading, 60)

            if case .failed(let message) = model.faucetStatus {
                Text(message).font(.callout).foregroundStyle(.red).padding(.leading, 60)
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var explanation: String {
        if network.faucetURL != nil {
            return "This address has never received tez on \(network.name). Signet can ask the \(network.name) faucet for free test tez."
        }
        return "This address has never received tez on \(network.name). Buy some tez on an exchange and send it here, or have someone send you some."
    }

    private func copyAddress() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(wallet.address.value, forType: .string)
        copied = true
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            copied = false
        }
    }
}

#Preview("Testnet") {
    AccountNotOnChainView(model: .preview(), wallet: WalletViewModel.sampleWallets[0]).padding()
}
