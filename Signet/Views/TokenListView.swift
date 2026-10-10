import SwiftUI

/// The Assets tab: fungible (DeFi) token balances with their logos.
struct TokenListView: View {
    let tokens: [AssetBalance]
    let isLoading: Bool
    let network: Network
    var hidesBalances = false

    var body: some View {
        if tokens.isEmpty {
            Text(isLoading ? "Loading…" : "No tokens in this account.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .padding(.top, 24)
        } else {
            ScrollView(.vertical) {
                LazyVStack(spacing: 0) {
                    ForEach(tokens) { token in
                        TokenRowView(token: token, network: network, hidesBalances: hidesBalances)
                        Divider().padding(.leading, 56)
                    }
                }
            }
        }
    }
}

struct TokenRowView: View {
    let token: AssetBalance
    let network: Network
    var hidesBalances = false

    private var contract: String? {
        if case .token(let contract, _) = token.kind { return contract }
        return nil
    }

    var body: some View {
        HStack(spacing: 12) {
            logo
                .frame(width: 40, height: 40)
                .clipShape(Circle())
                .overlay(Circle().strokeBorder(.secondary.opacity(0.25)))
            VStack(alignment: .leading, spacing: 2) {
                Text(token.name).font(.body.weight(.medium)).lineLimit(1)
                HStack(spacing: 6) {
                    if let contract {
                        Text(Address(contract).shortened()).font(.callout.monospaced()).foregroundStyle(.secondary)
                    }
                    if let standard = token.standard {
                        Text(standard.uppercased())
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(.quaternary))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Spacer()
            Text(hidesBalances ? "••••" : token.formattedAmount)
                .font(.body.monospacedDigit())
                .lineLimit(1)
        }
        .padding(.vertical, 8)
        .help(contract.map { "\(token.name)\n\($0)" } ?? token.name)
        .contextMenu {
            if let contract {
                Button("Copy contract address") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(contract, forType: .string)
                }
                if let url = network.explorerURL(contract: contract) {
                    Link("View in explorer", destination: url)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(token.name) \(hidesBalances ? "Balance hidden" : token.formattedAmount)")
    }

    @ViewBuilder
    private var logo: some View {
        if token.iconURLs.isEmpty {
            placeholder
        } else {
            RemoteImage(urls: token.iconURLs) { image in
                Image(nsImage: image).resizable().scaledToFill()
            } placeholder: { _ in
                placeholder
            }
        }
    }

    private var placeholder: some View {
        ZStack {
            Circle().fill(.quaternary)
            Text(String(token.symbol.prefix(3)))
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
        }
    }
}

#Preview {
    TokenListView(tokens: [
        AssetBalance(id: "a", kind: .token(contract: "KT1MZg99PxMDEENwB4Fi64xkqAVh5d1rv8Z9", tokenId: "0"), name: "Tezos Pepe", symbol: "PEPE", amount: 5000, standard: "fa2"),
        AssetBalance(id: "b", kind: .token(contract: "KT1BPGyFqmGQqsU4oEL8NUXQpHQGwuFdyjd1", tokenId: "0"), name: "FabRicE", symbol: "RICE", amount: 1, standard: "fa1.2"),
    ], isLoading: false, network: .mainnet)
    .padding()
}
