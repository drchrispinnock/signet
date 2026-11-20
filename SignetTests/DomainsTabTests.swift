import Foundation
import Testing
@testable import Signet

/// The Domains tab and the renamed Activity tab.
struct DomainsTabTests {
    static let captain = Address("tz1dCaMnnMJk76UodjewCK67ABiXWjcKj73N")

    @Test func namesTheTabs() {
        #expect(WalletViewModel.ActivityTab.allCases.map(\.rawValue) == ["Activity", "Assets", "NFTs", "Domains"])
    }

    /// The reply api.tezos.domains gave for captstake.tez, which the account owns, points at and publishes.
    @Test func readsTheApisReply() throws {
        let reply = #"{"data":{"owned":{"items":[{"name":"captstake.tez","address":"tz1dCaMnnMJk76UodjewCK67ABiXWjcKj73N","owner":"tz1dCaMnnMJk76UodjewCK67ABiXWjcKj73N","expiresAtUtc":"2029-06-22T19:27:05Z"}]},"pointing":{"items":[{"name":"captstake.tez","address":"tz1dCaMnnMJk76UodjewCK67ABiXWjcKj73N","owner":"tz1dCaMnnMJk76UodjewCK67ABiXWjcKj73N","expiresAtUtc":"2029-06-22T19:27:05Z"}]},"reverseRecord":{"domain":{"name":"captstake.tez"}}}}"#
        let domains = try TezosDomainsService.parseDomains(Data(reply.utf8))
        #expect(domains.count == 1)
        let name = try #require(domains.first)
        #expect(name.name == "captstake.tez" && name.isReverseRecord)
        #expect(name.isOwned(by: Self.captain) && name.pointsAt(Self.captain))
        #expect(name.expires == ISO8601DateFormatter().date(from: "2029-06-22T19:27:05Z"))
        #expect(name.appURL?.absoluteString == "https://app.tezos.domains/domain/captstake.tez")
    }

    @Test func putsThePublishedNameFirstThenTheRestByName() throws {
        let other = "tz1VSUr8wwNhLAzempoch5d6hLRiTh8Cjcjb"
        let reply = """
        {"data":{"owned":{"items":[{"name":"zeta.tez","address":"\(other)","owner":"\(Self.captain.value)","expiresAtUtc":null},{"name":"me.tez","address":"\(Self.captain.value)","owner":"\(Self.captain.value)","expiresAtUtc":"2030-01-01T00:00:00Z"}]},
         "pointing":{"items":[{"name":"alpha.tez","address":"\(Self.captain.value)","owner":"\(other)","expiresAtUtc":"2027-01-01T00:00:00Z"},{"name":"me.tez","address":"\(Self.captain.value)","owner":"\(Self.captain.value)","expiresAtUtc":"2030-01-01T00:00:00Z"}]},
         "reverseRecord":{"domain":{"name":"me.tez"}}}}
        """
        let domains = try TezosDomainsService.parseDomains(Data(reply.utf8))
        #expect(domains.map(\.name) == ["me.tez", "alpha.tez", "zeta.tez"])
        #expect(!domains[1].isOwned(by: Self.captain) && domains[1].pointsAt(Self.captain))
        #expect(domains[2].isOwned(by: Self.captain) && !domains[2].pointsAt(Self.captain) && domains[2].expires == nil)
        #expect(try TezosDomainsService.parseDomains(Data(#"{"data":{"owned":{"items":[]},"pointing":{"items":[]},"reverseRecord":null}}"#.utf8)).isEmpty)
        #expect(throws: TezosDomainsService.DomainsError.self) { try TezosDomainsService.parseDomains(Data(#"{"errors":[{"message":"bad"}]}"#.utf8)) }
    }

    @Test @MainActor func loadsTheListForTheSelectedAccountOnly() async throws {
        let model = WalletViewModel(wallets: WalletViewModel.sampleWallets, chain: MockChainService())
        #expect(model.selectedWallet != nil)
        #expect(model.currentDomainList == nil)
        await model.loadDomainList()
        guard case .loaded(let names)? = model.currentDomainList else { Issue.record("not loaded"); return }
        #expect(names.first?.isReverseRecord == true)
        // Another account's list is never shown for this one.
        let first = try #require(model.selectedWallet)
        if let second = model.wallets.first(where: { $0.address != first.address }) {
            model.select(second)
            #expect(model.currentDomainList == nil)
        }
    }

    @Test @MainActor func offersTheDomainsTabOnMainnetOnly() {
        let model = WalletViewModel(wallets: WalletViewModel.sampleWallets, chain: MockChainService())
        model.network = .mainnet
        #expect(model.activityTabs.contains(.domains))
        model.activityTab = .domains
        #expect(model.shownActivityTab == .domains)
        model.network = .shadownet
        #expect(model.activityTabs.map(\.rawValue) == ["Activity", "Assets", "NFTs"])
        #expect(model.shownActivityTab == .transactions)
    }

    @Test func followsThePagesOfTheApi() throws {
        let first = #"{"data":{"owned":{"items":[{"name":"a.tez","address":null,"owner":"tz1dCaMnnMJk76UodjewCK67ABiXWjcKj73N","expiresAtUtc":null}],"pageInfo":{"hasNextPage":true,"endCursor":"C1"}},"pointing":{"items":[],"pageInfo":{"hasNextPage":false,"endCursor":null}},"reverseRecord":null}}"#
        let page = try TezosDomainsService.parsePage(Data(first.utf8))
        #expect(page.ownedNext == "C1" && page.pointingNext == nil && page.items.count == 1 && page.reverse == nil)
        #expect(TezosDomainsService.pageSize <= 50)
    }

    @Test func onlyMainnetHasDomains() async throws {
        // Answered before any request: Shadownet has no Tezos Domains endpoint.
        #expect(try await TaquitoChainService(network: .shadownet).tezosDomains(for: Self.captain) == nil)
        #expect(Network.mainnet.tezosDomainsURL != nil)
    }
}
