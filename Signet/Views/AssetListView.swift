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

struct AssetRowView: View {
    let asset: AssetBalance

    var body: some View {
        HStack(spacing: 16) {
            icon
                .frame(width: 44, height: 44)
            Text(asset.formattedAmount)
                .font(.title3.monospacedDigit())
            Spacer()
        }
        .accessibilityElement(children: .combine)
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
        AssetBalance(id: "tez", kind: .tez, name: "Tezos", symbol: "tz", amount: 4361.43),
        AssetBalance(id: "etherlink", kind: .etherlink, name: "Etherlink", symbol: "tz", amount: 5432.1),
    ])
    .padding()
}
