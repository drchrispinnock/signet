import Foundation

/// The Domains tab: the Tezos Domains names the selected account owns or that point at it.
/// Read when the tab is shown rather than on every refresh, since only mainnet has them.
extension WalletViewModel {
    /// The tabs the dashboard offers: Domains only where Tezos Domains exists (Mainnet).
    var activityTabs: [ActivityTab] {
        network.tezosDomainsURL == nil ? ActivityTab.allCases.filter { $0 != .domains } : ActivityTab.allCases
    }

    /// The tab to show: the chosen one, or Activity when the network does not offer it.
    var shownActivityTab: ActivityTab { activityTabs.contains(activityTab) ? activityTab : .transactions }

    /// Which account on which network a list belongs to, so one never shows for another.
    var domainListKey: String? { selectedWallet.map { "\(network.name)|\($0.address.value)" } }

    /// The list for the selected account, if it was read for it.
    var currentDomainList: DomainListState? {
        guard let key = domainListKey, let list = domainList, list.key == key else { return nil }
        return list.state
    }

    func loadDomainList() async {
        guard let wallet = selectedWallet, let key = domainListKey else { return }
        if case .loaded = currentDomainList { return }
        domainList = (key, .loading)
        let state: DomainListState
        do {
            if let names = try await chainService.tezosDomains(for: wallet.address) { state = .loaded(names) } else { state = .unavailable }
        } catch {
            state = .failed(error.localizedDescription)
        }
        // The account or network may have changed while Tezos Domains answered.
        guard domainListKey == key else { return }
        domainList = (key, state)
    }

    /// Whether the selected account can hand `domain` to someone: Tezos Domains on this network,
    /// a key Signet signs with, and a name the account owns that has not expired.
    func canTransferDomain(_ domain: TezosDomain) -> Bool {
        guard network.tezosDomainsURL != nil, let wallet = selectedWallet, wallet.keyKind.canSign, !wallet.address.isContract else { return false }
        return domain.isOwned(by: wallet.address) && !domain.isExpired()
    }

    /// Reads the list again, quietly (the tab keeps showing the old one until the new one is
    /// in), when it was already read for the selected account: every refresh does this, so a
    /// transfer shows up once the Tezos Domains indexer has the block (`refreshAfterOperation`
    /// refreshes again after 6 and 15 seconds). A failed read keeps the list as it was.
    func refreshDomainList() async {
        guard let wallet = selectedWallet, let key = domainListKey, domainList?.key == key, case .loaded = currentDomainList else { return }
        guard let names = try? await chainService.tezosDomains(for: wallet.address), domainListKey == key else { return }
        domainList = (key, .loaded(names))
    }

    func reloadDomainList() async {
        domainList = nil
        await loadDomainList()
    }
}
