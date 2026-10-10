import SwiftUI

/// Key balances: tez first, Etherlink second, then any other tokens.
struct AssetListView: View {
    let assets: [AssetBalance]

    var body: some View {
        VStack(spacing: 12) {
            ForEach(assets) { asset in
                AssetRowView(asset: asset)
            }
        }
    }
}

/// One balance. Rows with a breakdown get a chevron that expands the detail lines beneath.
struct AssetRowView: View {
    let asset: AssetBalance
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 16) {
                icon
                    .frame(width: 44, height: 44)
                VStack(alignment: .leading, spacing: 3) {
                    Text(asset.name).font(.body.weight(.semibold))
                    Text(asset.kind == .tez ? "Native asset" : asset.symbol)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(asset.formattedAmount)
                    .font(.title3.monospacedDigit())
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
                if !asset.details.isEmpty {
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) { isExpanded.toggle() }
                    } label: {
                        Image(systemName: "chevron.down")
                            .rotationEffect(.degrees(isExpanded ? 180 : 0))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.borderless)
                    .help(isExpanded ? "Hide breakdown" : "Show breakdown")
                    .accessibilityLabel(isExpanded ? "Hide breakdown" : "Show breakdown")
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                guard !asset.details.isEmpty else { return }
                withAnimation(.easeInOut(duration: 0.15)) { isExpanded.toggle() }
            }

            if isExpanded {
                VStack(spacing: 6) {
                    ForEach(asset.details) { line in
                        HStack {
                            Text(line.label)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(AssetBalance.format(line.amount, symbol: asset.symbol))
                                .font(.body.monospacedDigit())
                        }
                    }
                }
                .font(.callout)
                .padding(.leading, 60)
                .padding(.trailing, 24)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(asset.name) balance \(asset.formattedAmount)")
    }

    @ViewBuilder
    private var icon: some View {
        switch asset.kind {
        case .tez:
            Image("TezosToken")
                .resizable()
                .scaledToFit()
        case .etherlink:
            Image("EtherlinkLogo")
                .resizable()
                .scaledToFit()
        case .token:
            badge(String(asset.symbol.prefix(4)))
        }
    }

    private func badge(_ text: String) -> some View {
        ZStack {
            Circle().strokeBorder(.secondary, lineWidth: 1.5)
            Text(text)
                .font(.caption.weight(.semibold))
        }
    }
}

#Preview {
    AssetListView(assets: [
        AssetBalance(id: "tez", kind: .tez, name: "Tezos", symbol: "tz", amount: 22702.455018,
                     details: TezBalance(spendable: 1386.761464, staked: 21315.693554).breakdown),
        AssetBalance(id: "etherlink", kind: .etherlink, name: "Etherlink", symbol: "tz", amount: 5432.1),
    ])
    .padding()
}
