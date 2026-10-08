import SwiftUI

/// The network pill in the header: green on mainnet, orange on a testnet. Click it to switch.
struct NetworkBadgeMenu: View {
    @Bindable var model: WalletViewModel
    @State private var isHovering = false

    private var tint: Color { model.network.isMainnet ? .green : .orange }

    var body: some View {
        Menu {
            ForEach(Network.all) { base in
                let network = model.resolved(base)
                Button {
                    model.switchNetwork(to: base)
                } label: {
                    if network.name == model.network.name {
                        Label("\(network.name)  \(network.rpcURL.host() ?? "")", systemImage: "checkmark")
                    } else {
                        Text("\(network.name)  \(network.rpcURL.host() ?? "")")
                    }
                }
            }
        } label: {
            // The lozenge, with a small chevron and a hover highlight so it reads as clickable.
            HStack(spacing: 3) {
                Text(model.network.name)
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .bold))
                    .opacity(0.8)
            }
            .font(.caption.weight(.semibold))
            .padding(.leading, 8)
            .padding(.trailing, 6)
            .padding(.vertical, 3)
            .background(Capsule().fill(tint.opacity(isHovering ? 0.35 : 0.2)))
            .overlay(Capsule().strokeBorder(tint.opacity(isHovering ? 0.6 : 0), lineWidth: 1))
            .foregroundStyle(tint)
            .animation(.easeInOut(duration: 0.12), value: isHovering)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .onHover { isHovering = $0 }
        .help("Connected to \(model.network.rpcURL.absoluteString). Click to switch network.")
        .accessibilityLabel("Network \(model.network.name). Switch network")
    }
}

#Preview {
    NetworkBadgeMenu(model: .preview()).padding()
}
