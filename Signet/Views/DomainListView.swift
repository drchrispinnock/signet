import AppKit
import SwiftUI

/// The Domains tab: the account's Tezos Domains names, the one it publishes as its own first,
/// each with where it points, who owns it and when it expires.
struct DomainListView: View {
    @Bindable var model: WalletViewModel

    var body: some View {
        Group {
            switch model.currentDomainList {
            case nil, .loading?:
                message("Loading…")
            case .unavailable?:
                message("Tezos Domains names exist on Mainnet only.")
            case .failed(let reason)?:
                VStack(spacing: 8) {
                    message("Tezos Domains could not be read: \(reason)")
                    Button("Try Again") { Task { await model.reloadDomainList() } }
                }
            case .loaded(let domains)?:
                if domains.isEmpty {
                    message("No .tez names belong to or point at this account.")
                } else if let account = model.selectedWallet?.address {
                    ScrollView(.vertical) {
                        LazyVStack(spacing: 0) {
                            ForEach(domains) { domain in
                                DomainRowView(domain: domain, account: account, model: model)
                                Divider().padding(.leading, 56)
                            }
                        }
                    }
                }
            }
        }
        .task(id: model.domainListKey) { await model.loadDomainList() }
    }

    private func message(_ text: String) -> some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, alignment: .top)
            .padding(.top, 24)
    }
}

struct DomainRowView: View {
    let domain: TezosDomain
    let account: Address
    let model: WalletViewModel

    private var owned: Bool { domain.isOwned(by: account) }
    private var pointsHere: Bool { domain.pointsAt(account) }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: domain.isReverseRecord ? "person.text.rectangle" : "globe")
                .font(.title3)
                .foregroundStyle(.tint)
                .frame(width: 40, height: 40)
                .background(Circle().fill(Color.accentColor.opacity(0.12)))
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(domain.name).font(.body.weight(.medium)).lineLimit(1).textSelection(.enabled)
                    if domain.isReverseRecord { tag("Primary name", help: "The account's reverse record: the name wallets and explorers show for this address.") }
                }
                Text(detail).font(.callout).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 8)
            expiry
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .contextMenu {
            if model.canTransferDomain(domain) {
                Button("Transfer…") { model.domainOperation = domain }
                Divider()
            }
            Button("Copy Name") { copy(domain.name) }
            if let address = domain.address { Button("Copy Address It Points To") { copy(address.value) } }
            if let url = domain.appURL { Button("Open on Tezos Domains") { NSWorkspace.shared.open(url) } }
        }
    }

    /// Who owns it and where it points, in words.
    private var detail: String {
        let target = domain.address.map { pointsHere ? "this account" : model.displayName(for: $0, indexerAlias: nil).name }
        let points = target.map { "Points to \($0)" } ?? "Points nowhere"
        if owned { return "Owned by this account · \(points)" }
        let owner = domain.owner.map { model.displayName(for: $0, indexerAlias: nil).name } ?? "someone else"
        return "\(points) · owned by \(owner)"
    }

    @ViewBuilder private var expiry: some View {
        if let expires = domain.expires {
            let days = Calendar.current.dateComponents([.day], from: Date(), to: expires).day ?? 0
            VStack(alignment: .trailing, spacing: 2) {
                Text(days < 0 ? "Expired" : "Expires").font(.caption).foregroundStyle(.secondary)
                Text(expires.formatted(date: .abbreviated, time: .omitted))
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(days < 0 ? .red : days < 30 ? .orange : .primary)
            }
            .help(days < 0 ? "This name has expired; anyone may register it." : days < 30 ? "Renew it on Tezos Domains before it expires." : "")
        } else {
            Text("Subdomain").font(.caption).foregroundStyle(.secondary)
                .help("A subdomain lasts as long as its parent name.")
        }
    }

    private func tag(_ text: String, help: String) -> some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(.quaternary))
            .foregroundStyle(.secondary)
            .help(help)
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

#Preview {
    DomainListView(model: .preview())
        .frame(width: 600, height: 300)
}
