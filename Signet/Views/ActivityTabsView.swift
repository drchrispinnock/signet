import AppKit
import SwiftUI

/// Bottom section of the dashboard: recent transactions or NFTs, chosen with a segmented control.
struct ActivityTabsView: View {
    @Bindable var model: WalletViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Picker("Activity", selection: $model.activityTab) {
                    ForEach(WalletViewModel.ActivityTab.allCases) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: 400)
                Spacer(minLength: 0)
                if model.filtersLayers {
                    LayerToggles(shown: $model.shownLayers)
                }
            }

            switch model.activityTab {
            case .transactions:
                TransactionListView(model: model)
            case .assets:
                TokenListView(tokens: model.visibleTokens, isLoading: model.isLoading, state: model.portfolioState, network: model.network,
                              layerEmptyText: model.layerEmptyText(for: "tokens"))
            case .nfts:
                NFTGridView(nfts: model.visibleNFTs, isLoading: model.isLoading, state: model.portfolioState,
                            layerEmptyText: model.layerEmptyText(for: "NFTs"))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

/// Two logo buttons, Tezos and Etherlink, each lit while that layer's holdings and operations
/// are shown. Beside the activity picker while Layer 2 is on, so every tab can be cut to one chain.
struct LayerToggles: View {
    @Binding var shown: Set<Int>

    var body: some View {
        HStack(spacing: 4) {
            toggle(layer: 1, logo: "TezosToken", name: "Tezos")
            toggle(layer: 2, logo: "EtherlinkLogo", name: "Etherlink")
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Chains shown")
    }

    private func toggle(layer: Int, logo: String, name: String) -> some View {
        Toggle(isOn: Binding(
            get: { shown.contains(layer) },
            set: { on in if on { shown.insert(layer) } else { shown.remove(layer) } }
        )) {
            Image(nsImage: ChainSidePicker.smallLogo(logo, points: 16))
                .opacity(shown.contains(layer) ? 1 : 0.45)
        }
        .toggleStyle(.button)
        .controlSize(.small)
        .help(shown.contains(layer) ? "Showing \(name). Click to hide its transactions, tokens and NFTs." : "Show \(name)")
        .accessibilityLabel(name)
    }
}

/// A small Etherlink logo beside a layer 2 row's figure or on its tile: the same mark as the
/// dashboard's Etherlink balance row, so a list reads "on Etherlink".
struct EtherlinkMark: View {
    var size: CGFloat = 14

    var body: some View {
        Image("EtherlinkLogo")
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .help("On Etherlink")
            .accessibilityHidden(true)
    }
}

/// The last few operations, each with the counterparty's avatar and best-known name.
struct TransactionListView: View {
    @Bindable var model: WalletViewModel

    private var emptyText: String {
        if model.isLoading { return "Loading…" }
        return model.layerEmptyText(for: "transactions") ?? "No transactions yet."
    }

    var body: some View {
        if model.visibleTransactions.isEmpty {
            Text(emptyText)
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .padding(.top, 24)
        } else {
            ScrollView(.vertical) {
                LazyVStack(spacing: 0) {
                    ForEach(model.visibleTransactions) { tx in
                        TransactionRowView(model: model, transaction: tx)
                        Divider().padding(.leading, 56)
                    }
                }
            }
        }
    }
}

struct TransactionRowView: View {
    @Bindable var model: WalletViewModel
    let transaction: TezosTransaction
    @State private var isHovering = false

    /// The network the row's explorer link belongs to: Etherlink's for a layer 2 row (none if
    /// Layer 2 has since been turned off), else the one in use.
    private var network: Network? { transaction.isLayer2 ? model.network.layer2 : model.network }

    private var party: (name: String, isOurs: Bool) {
        guard let address = transaction.counterparty else { return ("Unknown", false) }
        return model.displayName(for: address, indexerAlias: transaction.counterpartyAlias)
    }

    var body: some View {
        HStack(spacing: 12) {
            ZStack(alignment: .bottomTrailing) {
                if let address = transaction.counterparty {
                    AccountAvatarView(address: address, size: 40)
                } else {
                    Circle().fill(.quaternary).frame(width: 40, height: 40)
                }
                directionBadge
                    .offset(x: 4, y: 4)
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(headline)
                        .font(.body.weight(.medium))
                        .lineLimit(1)
                    if party.isOurs {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.caption)
                            .foregroundStyle(.green)
                            .help("One of your accounts or address-book entries")
                    }
                    if !transaction.isApplied {
                        Text("Failed")
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(Capsule().fill(.red.opacity(0.15)))
                            .foregroundStyle(.red)
                    }
                }
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                HStack(spacing: 5) {
                    if transaction.isLayer2 { etherlinkMark }
                    figure
                }
                if showsDelegatedBalance {
                    Text("delegated balance").font(.caption2).foregroundStyle(.tertiary)
                }
                if transaction.direction != .incoming, transaction.fee > 0 {
                    Text("fee \(AssetBalance.format(transaction.fee, symbol: "tz"))")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 4)
        .background(RoundedRectangle(cornerRadius: 8).fill(isHovering ? Color.secondary.opacity(0.08) : .clear))
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .onTapGesture { openExplorer() }
        .help(helpText)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(headline), \(subtitle), \(transaction.amount > 0 ? signedAmount : "")\(transaction.isLayer2 ? ", on Etherlink" : "")")
    }

    // MARK: Pieces

    private var showsDelegatedBalance: Bool {
        transaction.amount == 0 && transaction.kind == .delegation && (transaction.delegatedBalance ?? 0) > 0
    }

    /// The amount, the delegator's balance, or the kind of call.
    @ViewBuilder private var figure: some View {
        if transaction.amount > 0 {
            Text(signedAmount)
                .font(.body.monospacedDigit().weight(.medium))
                .foregroundStyle(transaction.direction == .incoming ? .green : .primary)
        } else if showsDelegatedBalance, let balance = transaction.delegatedBalance {
            Text(AssetBalance.format(balance, symbol: "tz"))
                .font(.body.monospacedDigit())
                .foregroundStyle(.secondary)
        } else {
            Text(transaction.kind == .delegation ? "Delegation" : "Call")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private var etherlinkMark: some View { EtherlinkMark() }

    private var role: TezosTransaction.DelegationRole? {
        model.selectedWallet.flatMap { transaction.delegationRole(for: $0.address) }
    }

    private var directionBadge: some View {
        let (symbol, color): (String, Color) = switch (role, transaction.direction) {
        case (.delegatorJoined, _): ("person.fill.badge.plus", .green)
        case (.delegatorLeft, _), (.delegatorMoved, _): ("person.fill.badge.minus", .orange)
        case (.weDelegated, _), (.weUndelegated, _): ("person.fill", .blue)
        case (_, .incoming): ("arrow.down", .green)
        case (_, .outgoing): ("arrow.up", .blue)
        case (_, .selfTransfer): ("arrow.triangle.2.circlepath", .gray)
        }
        return Image(systemName: symbol)
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 16, height: 16)
            .background(Circle().fill(color))
            .overlay(Circle().strokeBorder(Color(nsColor: .windowBackgroundColor), lineWidth: 1.5))
    }

    private var headline: String {
        if let role {
            switch role {
            case .weDelegated: return "Delegated to \(party.name)"
            case .weUndelegated: return "Undelegated"
            case .delegatorJoined: return "\(party.name) delegated to you"
            case .delegatorLeft: return "\(party.name) undelegated"
            case .delegatorMoved: return "\(party.name) moved their delegation"
            }
        }
        return switch (transaction.kind, transaction.direction) {
        case (.origination, _): "Originated \(party.name)"
        case (_, .incoming): "From \(party.name)"
        case (_, .selfTransfer): "To yourself"
        case (_, .outgoing): "To \(party.name)"
        }
    }

    private var subtitle: String {
        var parts = [Self.relative.localizedString(for: transaction.timestamp, relativeTo: Date())]
        if let entrypoint = transaction.entrypoint { parts.append("entrypoint \(entrypoint)") }
        else if transaction.isContractCall { parts.append("contract") }
        if let via = transaction.via { parts.append("via \(model.displayName(for: via, indexerAlias: nil).name)") }
        if !party.isOurs, transaction.counterpartyAlias != nil { parts.append("name from TzKT") }
        return parts.joined(separator: " · ")
    }

    private var signedAmount: String {
        let sign = transaction.direction == .incoming ? "+" : (transaction.direction == .outgoing ? "−" : "")
        return sign + AssetBalance.format(transaction.amount, symbol: "tz")
    }

    private var helpText: String {
        var lines = [transaction.hash, "Block \(transaction.level.formatted())", transaction.timestamp.formatted(date: .abbreviated, time: .shortened)]
        if transaction.isLayer2 { lines.insert("On Etherlink", at: 0) }
        if let address = transaction.counterparty { lines.append(address.value) }
        if network?.explorerURL(operation: transaction.hash) != nil { lines.append("Click to view in the explorer") }
        return lines.joined(separator: "\n")
    }

    private func openExplorer() {
        guard let url = network?.explorerURL(operation: transaction.hash) else { return }
        NSWorkspace.shared.open(url)
    }

    private static let relative: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f
    }()
}

#Preview {
    ActivityTabsView(model: {
        let m = WalletViewModel.preview()
        Task { await m.refresh() }
        return m
    }())
    .padding()
    .frame(height: 360)
}
