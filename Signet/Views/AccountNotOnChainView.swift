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
                if network.faucetURL != nil {
                    Button("Get test tez…") { model.isPresentingFaucet = true }
                        .buttonStyle(.borderedProminent)
                    Button(copied ? "Address copied" : "Copy address", systemImage: copied ? "checkmark" : "doc.on.doc", action: copyAddress)
                } else {
                    Button("Show address to receive tez…") { model.isPresentingReceive = true }
                        .buttonStyle(.borderedProminent)
                    Button("Buy tez…") { model.isPresentingBuy = true }
                        .help("Buy tez through \(BuyProvider.current.title), delivered to this address")
                }
            }
            .padding(.leading, 60)

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
