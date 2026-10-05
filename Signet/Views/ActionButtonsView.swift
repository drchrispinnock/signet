import SwiftUI

/// Send, Receive, Buy, Sell. Actions are placeholders until the flows exist.
struct ActionButtonsView: View {
    private let actions: [(title: String, symbol: String)] = [
        ("Send", "arrow.up"),
        ("Receive", "arrow.down"),
        ("Buy", "plus"),
        ("Sell", "minus"),
    ]

    var body: some View {
        HStack(spacing: 12) {
            ForEach(actions, id: \.title) { action in
                Button {
                    // Flows land in later steps.
                } label: {
                    VStack(spacing: 6) {
                        Image(systemName: action.symbol)
                            .font(.title3)
                            .frame(height: 22) // symbols differ in height (e.g. minus), keep tiles equal
                        Text(action.title)
                            .font(.callout)
                    }
                }
                .buttonStyle(ActionButtonStyle())
            }
        }
    }
}

/// A tile that always fills its share of the row, so all four buttons are the same size
/// regardless of label length (the system bordered style sizes its chrome to the text).
struct ActionButtonStyle: ButtonStyle {
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
            .foregroundStyle(.primary)
    }
}

#Preview {
    ActionButtonsView().padding()
}
