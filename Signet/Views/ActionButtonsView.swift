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

    private var actions: [Action] {
        [
            Action(title: "Send", symbol: "arrow.up", enabled: false) {},
            Action(title: "Receive", symbol: "arrow.down", enabled: model.selectedWallet != nil) { model.isPresentingReceive = true },
            Action(title: "Buy", symbol: "plus", enabled: false) {},
            Action(title: "Sell", symbol: "minus", enabled: false) {},
        ]
    }

    var body: some View {
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
                .help(action.enabled ? action.title : "\(action.title) is coming soon")
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
