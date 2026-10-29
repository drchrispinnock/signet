import SwiftUI

/// The Assets tab: fungible (DeFi) token balances with their logos.
struct TokenListView: View {
    let tokens: [AssetBalance]
    let isLoading: Bool
    var state: Portfolio.State = .complete
    let network: Network
    /// What to say instead of "No tokens" when the layer toggles leave the tab empty.
    var layerEmptyText: String? = nil

    var body: some View {
        VStack(spacing: 0) {
            if tokens.isEmpty {
                Text(isLoading ? "Loading…" : (state.isUnavailable ? "Token data is unavailable." : layerEmptyText ?? "No tokens in this account."))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .padding(.top, 24)
            } else {
                ScrollView(.vertical) {
                    LazyVStack(spacing: 0) {
                        ForEach(tokens) { token in
                            TokenRowView(token: token, network: network)
                            Divider().padding(.leading, 56)
                        }
                    }
                }
            }
            PortfolioStateNote(state: state)
        }
    }
}

/// A line under the Assets and NFTs tabs when the list is not the whole story (S26).
struct PortfolioStateNote: View {
    let state: Portfolio.State

    var body: some View {
        switch state {
        case .complete:
            EmptyView()
        case .partial(let fetched):
            Label("Showing the \(fetched) most recently changed tokens; older holdings may be missing.", systemImage: "exclamationmark.triangle")
                .font(.caption).foregroundStyle(.orange).padding(.vertical, 6)
        case .unavailable(let reason):
            Label("The indexer could not be read (\(reason)). Showing the last known list.", systemImage: "exclamationmark.triangle")
                .font(.caption).foregroundStyle(.orange).padding(.vertical, 6).lineLimit(2)
        }
    }
}

extension Portfolio.State {
    var isUnavailable: Bool { if case .unavailable = self { return true } else { return false } }
}

struct TokenRowView: View {
    let token: AssetBalance
    let network: Network

    private var contract: String? {
        if case .token(let contract, _) = token.kind { return contract }
        return nil
    }

    /// The explorer the token's contract is on: Etherlink's for a layer 2 token.
    private var explorer: Network? { token.isLayer2 ? network.layer2 : network }

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
            HStack(spacing: 5) {
                if token.isLayer2 { EtherlinkMark() }
                Text(token.formattedAmount)
                    .font(.body.monospacedDigit())
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 8)
        .help((token.isLayer2 ? "On Etherlink\n" : "") + (contract.map { "\(token.name)\n\($0)" } ?? token.name))
        .contextMenu {
            if let contract {
                Button("Copy contract address") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(contract, forType: .string)
                }
                if let url = explorer?.explorerURL(contract: contract) {
                    Link("View in explorer", destination: url)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(token.name) \(token.formattedAmount)\(token.isLayer2 ? ", on Etherlink" : "")")
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
