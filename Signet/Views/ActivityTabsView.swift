import AppKit
import SwiftUI

/// Bottom section of the dashboard: recent transactions or NFTs, chosen with a segmented control.
struct ActivityTabsView: View {
    @Bindable var model: WalletViewModel
    var hidesBalances = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 24) {
                ForEach(WalletViewModel.ActivityTab.allCases) { tab in
                    Button {
                        model.activityTab = tab
                    } label: {
                        VStack(spacing: 12) {
                            Text(tab == .transactions ? "Activity" : tab.rawValue)
                                .font(.body.weight(.semibold))
                                .foregroundStyle(model.activityTab == tab ? Color.primary : Color.secondary)
                            Capsule()
                                .fill(model.activityTab == tab ? Theme.violet : .clear)
                                .frame(height: 2)
                        }
                        .fixedSize(horizontal: true, vertical: false)
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(model.activityTab == tab ? .isSelected : [])
                }
                Spacer()
            }
            .padding(.top, 4)

            switch model.activityTab {
            case .transactions:
                TransactionListView(model: model, hidesBalances: hidesBalances)
            case .assets:
                TokenListView(tokens: model.tokens, isLoading: model.isLoading, network: model.network, hidesBalances: hidesBalances)
            case .nfts:
                NFTGridView(nfts: model.nfts, isLoading: model.isLoading)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

/// The last few operations, each with the counterparty's avatar and best-known name.
struct TransactionListView: View {
    @Bindable var model: WalletViewModel
    var hidesBalances = false

    var body: some View {
        if model.transactions.isEmpty {
            Text(model.isLoading ? "Loading…" : "No transactions yet.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .padding(.top, 24)
        } else {
            ScrollView(.vertical) {
                LazyVStack(spacing: 0) {
                    ForEach(model.transactions) { tx in
                        TransactionRowView(model: model, transaction: tx, hidesBalances: hidesBalances)
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
    var hidesBalances = false
    @State private var isHovering = false

    private var network: Network { model.network }

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
                if transaction.amount > 0 {
                    Text(hidesBalances ? "••••" : signedAmount)
                        .font(.body.monospacedDigit().weight(.medium))
                        .foregroundStyle(transaction.direction == .incoming ? .green : .primary)
                } else if transaction.kind == .delegation, let balance = transaction.delegatedBalance, balance > 0 {
                    Text(hidesBalances ? "••••" : AssetBalance.format(balance, symbol: "tz"))
                        .font(.body.monospacedDigit())
                        .foregroundStyle(.secondary)
                    Text("delegated balance").font(.caption2).foregroundStyle(.tertiary)
                } else {
                    Text(transaction.kind == .delegation ? "Delegation" : "Call")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Text("Fee \(hidesBalances ? "••••" : AssetBalance.format(transaction.fee, symbol: "tz"))")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .help("Network fee paid by the operation sender")
            }
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 4)
        .background(RoundedRectangle(cornerRadius: 8).fill(isHovering ? Color.secondary.opacity(0.08) : .clear))
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .onTapGesture { openExplorer() }
        .help(helpText)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(headline), \(subtitle), \(hidesBalances ? "Amount and fee hidden" : (transaction.amount > 0 ? signedAmount : "") + ", fee " + AssetBalance.format(transaction.fee, symbol: "tz"))")
    }

    // MARK: Pieces

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
        return parts.joined(separator: " · ")
    }

    private var signedAmount: String {
        let sign = transaction.direction == .incoming ? "+" : (transaction.direction == .outgoing ? "−" : "")
        return sign + AssetBalance.format(transaction.amount, symbol: "tz")
    }

    private var helpText: String {
        var lines = [transaction.hash, "Block \(transaction.level.formatted())", transaction.timestamp.formatted(date: .abbreviated, time: .shortened)]
        if let address = transaction.counterparty { lines.append(address.value) }
        if network.explorerURL(operation: transaction.hash) != nil { lines.append("Click to view in the explorer") }
        return lines.joined(separator: "\n")
    }

    private func openExplorer() {
        guard let url = network.explorerURL(operation: transaction.hash) else { return }
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
