import SwiftUI

/// Send, Receive, Buy, Sell. Buttons whose flow does not exist yet are disabled.
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
    /// Only clear-text keys can sign today; encrypted, ledger and remote keys come later.
    private var canSign: Bool { model.selectedWallet?.keyKind.canSign == true }

    private var actions: [Action] {
        [
            Action(title: "Send", symbol: "arrow.up", enabled: canSign && !model.accountNotOnChain) { model.isPresentingSend = true },
            Action(title: "Receive", symbol: "arrow.down", enabled: model.selectedWallet != nil && !isWatchOnly) { model.isPresentingReceive = true },
            Action(title: "Buy", symbol: "plus", enabled: false) {},
            Action(title: "Sell", symbol: "minus", enabled: false) {},
        ]
    }

    private func helpText(for action: Action) -> String {
        if action.enabled { return action.title }
        if isWatchOnly { return "Not available for a watch-only address" }
        if action.title == "Send" {
            if model.accountNotOnChain { return "This address has no tez on this network" }
            if let kind = model.selectedWallet?.keyKind, kind != .unencrypted { return "Sending with \(kind.rawValue) keys is not supported yet" }
        }
        return "\(action.title) is coming soon"
    }

    /// Why Send is off, spelled out under the row so it is not just a tooltip.
    private var sendUnavailableReason: String? {
        guard let wallet = model.selectedWallet, !(canSign && !model.accountNotOnChain) else { return nil }
        if isWatchOnly { return "This is an address-book entry; Signet holds no key for it, so it cannot send." }
        if model.accountNotOnChain { return "This address has no tez on \(model.network.name), so there is nothing to send." }
        switch wallet.keyKind {
        case .ledger: return "This wallet's key is on a Ledger. Signing with Ledger is not supported yet; pick a wallet whose key Signet holds."
        case .encrypted: return "This wallet's key is passphrase-encrypted. Encrypted keys are not supported yet; pick a wallet with a clear-text key."
        case .remote: return "This wallet signs through a remote signer, which Signet does not support yet."
        default: return "Signet cannot sign for this wallet yet."
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
