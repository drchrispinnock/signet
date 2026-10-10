import SwiftUI

/// Send, Receive, Buy (Get on testnets), Stake. Selling is out of scope: it would mean handling bank
/// accounts. Buttons whose flow does not exist yet are disabled.
struct ActionButtonsView: View {
    @Bindable var model: WalletViewModel

    private struct Action: Identifiable {
        let title: String
        let symbol: String
        let enabled: Bool
        let perform: () -> Void
        var id: String { title }
    }

    /// Address-book entries have no key, so none of the actions apply to them.
    private var isWatchOnly: Bool { model.selectedWallet?.keyKind == KeyKind.none }
    /// Faucets only fund implicit accounts; a contract (KT1) is funded by sending to it.
    private var isContract: Bool { model.selectedWallet?.address.isContract == true }
    /// Keys on disk (clear or encrypted) and on a Ledger can sign; remote signers cannot yet.
    private var canSign: Bool { model.selectedWallet?.keyKind.canSign == true }

    private var actions: [Action] {
        [
            Action(title: "Send", symbol: "arrow.up", enabled: canSign && !model.accountNotOnChain) { model.isPresentingSend = true },
            Action(title: "Receive", symbol: "arrow.down", enabled: model.selectedWallet != nil && !isWatchOnly) { model.isPresentingReceive = true },
            model.network.faucetURL != nil
                ? Action(title: "Get", symbol: "drop.fill", enabled: model.selectedWallet != nil && !isContract) { model.isPresentingFaucet = true }
                : Action(title: "Buy", symbol: "plus", enabled: model.selectedWallet != nil && model.network.isMainnet) { model.isPresentingBuy = true },
            Action(title: "Stake", symbol: "chart.line.uptrend.xyaxis", enabled: canSign && !model.accountNotOnChain) { model.isPresentingStaking = true },
        ]
    }

    private func helpText(for action: Action) -> String {
        if action.enabled { return action.title == "Buy" ? "Buy tez through \(BuyProvider.current.title)" : action.title }
        if action.title == "Buy", !model.network.isMainnet { return "Buying is only possible on Mainnet" }
        if action.title == "Get", isContract { return "The faucet cannot fund a contract; send it tez from an account" }
        if isWatchOnly { return "Not available for a watch-only address" }
        if action.title == "Send" {
            if model.accountNotOnChain { return "This address has no tez on this network" }
            if let kind = model.selectedWallet?.keyKind, !kind.canSign { return "Sending with \(kind.rawValue) keys is not supported yet" }
        }
        return "\(action.title) is coming soon"
    }

    /// Why Send is off, spelled out under the row so it is not just a tooltip.
    private var sendUnavailableReason: String? {
        guard let wallet = model.selectedWallet, !(canSign && !model.accountNotOnChain) else { return nil }
        if isWatchOnly { return "This is an address-book entry; Signet holds no key for it, so it cannot send." }
        if model.accountNotOnChain { return "This address has no tez on \(model.network.name), so there is nothing to send." }
        switch wallet.keyKind {
        case .remote: return "This account signs through a remote signer, which Signet does not support yet."
        default: return "Signet cannot sign for this account yet."
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            actionRow
            if let reason = sendUnavailableReason {
                Label(reason, systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var actionRow: some View {
        HStack(spacing: 12) {
            ForEach(actions) { action in
                Button(action: action.perform) {
                    VStack(spacing: 6) {
                        Image(systemName: action.symbol)
                            .font(.title3)
                            .frame(height: 22) // symbols differ in height (e.g. minus), keep tiles equal
                        Text(action.title)
                            .font(.callout)
                    }
                }
                .buttonStyle(ActionButtonStyle())
                .disabled(!action.enabled)
                .help(helpText(for: action))
            }
        }
    }
}

/// A tile that always fills its share of the row, so all four buttons are the same size
/// regardless of label length (the system bordered style sizes its chrome to the text).
struct ActionButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(configuration.isPressed ? Color.secondary.opacity(0.25) : Color.secondary.opacity(0.12))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Color.secondary.opacity(0.35), lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 8))
            .foregroundStyle(isEnabled ? AnyShapeStyle(.primary) : AnyShapeStyle(.tertiary))
    }
}

#Preview {
    ActionButtonsView(model: .preview()).padding()
}
