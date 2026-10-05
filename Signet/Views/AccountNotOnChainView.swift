import SwiftUI

/// Shown where the balance would be when the node has never seen the address.
struct AccountNotOnChainView: View {
    let network: Network

    var body: some View {
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
                Text("This address has never received tez on \(network.name), so the node has no record of it yet.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    AccountNotOnChainView(network: .mainnet).padding()
}
