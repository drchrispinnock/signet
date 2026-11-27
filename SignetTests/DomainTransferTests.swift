import Foundation
import Testing
@testable import Signet

/// Tezos Domains transfers: what hands a name over (its FA2 token, with `update_record` first to
/// point it at the recipient; a subdomain's record alone), the record data kept, the API's
/// token id and data read, the request the bridge is given, and Move assets taking names along.
struct DomainTransferTests {
    static let me = Address("tz1VSUr8wwNhLAzempoch5d6hLRiTh8Cjcjb")
    static let them = Address("tz1dCaMnnMJk76UodjewCK67ABiXWjcKj73N")
    static let other = Address("tz3WXYtyDUNL91qfiCJtVUX746QpNv5i5ve5")
    static let later = Date().addingTimeInterval(365 * 86_400)

    static func name(_ name: String, owner: Address = me, address: Address? = me, tokenId: Int? = 143032, expires: Date? = later) -> TezosDomain {
        var domain = TezosDomain(name: name, address: address, owner: owner, expires: expires, isReverseRecord: false)
        domain.tokenId = tokenId
        domain.data = ["openid:website": "2268"]
        return domain
    }

    @Test func aSecondLevelNameMovesAsItsTokenAndIsPointedAtTheRecipientFirst() throws {
        let parts = try #require(Self.name("captstake.tez").transferParts(from: Self.me, to: Self.them, pointAtRecipient: true))
        #expect(parts.transfers == [TokenTransfer(contract: TezosDomain.registry, tokenId: "143032", amount: "1")])
        #expect(parts.records == [DomainRecordUpdate(proxy: TezosDomain.updateRecordProxy, name: "captstake.tez", address: Self.them.value, owner: Self.me.value, data: ["openid:website": "2268"])])
        let request = TokenTransferRequest(to: Self.them, transfers: parts.transfers, records: parts.records)
        #expect(request.isValid && request.operationCount == 2 && request.extraBridgeArguments.count == 2 && request.extraBridgeArguments[0] == "")
        // Left pointing where it was: the token alone.
        let plain = try #require(Self.name("captstake.tez").transferParts(from: Self.me, to: Self.them, pointAtRecipient: false))
        #expect(plain.records.isEmpty && plain.transfers.count == 1)
    }

    @Test func aSubdomainIsHandedOverByItsRecord() throws {
        let sub = Self.name("shop.captstake.tez", address: Self.other, tokenId: nil, expires: nil)
        let pointed = try #require(sub.transferParts(from: Self.me, to: Self.them, pointAtRecipient: true))
        #expect(pointed.transfers.isEmpty && pointed.records.first?.owner == Self.them.value && pointed.records.first?.address == Self.them.value)
        let kept = try #require(sub.transferParts(from: Self.me, to: Self.them, pointAtRecipient: false))
        #expect(kept.records.first?.address == Self.other.value && kept.records.first?.data == ["openid:website": "2268"])
        #expect(TokenTransferRequest(to: Self.them, transfers: [], records: kept.records).isValid)
    }

    @Test func onlyALiveNameTheAccountOwnsCanBeHandedOver() {
        #expect(Self.name("x.tez", owner: Self.other).transferParts(from: Self.me, to: Self.them, pointAtRecipient: true) == nil)
        #expect(Self.name("x.tez", expires: Date().addingTimeInterval(-60)).transferParts(from: Self.me, to: Self.them, pointAtRecipient: true) == nil)
        #expect(Self.name("x.tez").transferParts(from: Self.me, to: Self.me, pointAtRecipient: true) == nil)
        // Records the bridge would refuse are refused here too.
        #expect(!DomainRecordUpdate(proxy: Self.me.value, name: "x.tez", address: nil, owner: Self.me.value).isValid)
        #expect(!DomainRecordUpdate(proxy: TezosDomain.updateRecordProxy, name: "X.tez", address: nil, owner: Self.me.value).isValid)
        #expect(!DomainRecordUpdate(proxy: TezosDomain.updateRecordProxy, name: "x.tez", address: nil, owner: Self.me.value, data: ["k": "zz"]).isValid)
    }

    @Test func theAPIsTokenIdAndDataAreRead() throws {
        let reply = """
        {"data":{"owned":{"items":[{"name":"captstake.tez","address":"\(Self.me.value)","owner":"\(Self.me.value)","expiresAtUtc":"2029-06-22T19:27:05Z","tokenId":143032,
          "data":[{"key":"openid:website","rawValue":"2268"}]},
          {"name":"shop.captstake.tez","address":null,"owner":"\(Self.me.value)","expiresAtUtc":null,"tokenId":null,"data":[]}],
          "pageInfo":{"hasNextPage":false,"endCursor":null}},
          "pointing":{"items":[],"pageInfo":{"hasNextPage":false,"endCursor":null}},"reverseRecord":null}}
        """
        let names = try TezosDomainsService.parseDomains(Data(reply.utf8))
        let main = try #require(names.first { $0.name == "captstake.tez" })
        #expect(main.tokenId == 143032 && main.data == ["openid:website": "2268"])
        #expect(names.first { $0.name == "shop.captstake.tez" }?.tokenId == nil)
    }

    @Test @MainActor func theMenuIsOfferedForOwnedLiveNamesOnly() throws {
        let store = InMemoryWalletStore()
        let wallet = Wallet(alias: "Main", address: Self.me, keyKind: .unencrypted)
        try store.add(wallet, secretKey: "edskX")
        let model = WalletViewModel(chain: MockChainService(), walletStore: store, stateStore: InMemoryAppStateStore())
        model.switchNetwork(to: .mainnet)
        #expect(model.canTransferDomain(Self.name("captstake.tez")))
        #expect(!model.canTransferDomain(Self.name("captstake.tez", owner: Self.other)))
        #expect(!model.canTransferDomain(Self.name("old.tez", expires: Date().addingTimeInterval(-60))))
        model.switchNetwork(to: .shadownet)
        #expect(!model.canTransferDomain(Self.name("captstake.tez")))   // no Tezos Domains there
    }
}

extension MoveAssetsTests {
    @Test func ownedNamesMoveInTheFirstGroupPointedAtTheDestination() async throws {
        let chain = Chain()
        chain.domainList = [DomainTransferTests.name("main.tez", owner: Self.main.address, address: Self.main.address),
                            DomainTransferTests.name("theirs.tez", owner: Self.book.address, address: Self.main.address),
                            DomainTransferTests.name("old.tez", owner: Self.main.address, expires: Date().addingTimeInterval(-60))]
        chain.nftList = (1...150).map { Self.nft($0) }
        let model = try makeModel(chain)
        model.switchNetwork(to: .mainnet)
        let plan = try await model.planMoveAssets(from: Self.main, to: Self.book)
        let layer = try #require(plan.layers.first)
        #expect(layer.domains.map(\.name) == ["main.tez"] && Set(layer.domainsLeftBehind.map(\.name)) == ["theirs.tez", "old.tez"])
        #expect(layer.batches.count == 2)
        #expect(layer.batches[0].request.records.map(\.address) == [Self.book.address.value])
        #expect(layer.batches[0].request.transfers.first?.contract == TezosDomain.registry)
        #expect(layer.batches[1].request.records.isEmpty && layer.batches[1].request.tezMutez != nil)
        try await model.moveAssets(plan, passphrase: nil) { _ in }
        #expect(chain.sent.first?.records.count == 1)
    }

    @Test func anUnreadableNameListStopsTheMoveOnMainnet() async throws {
        let chain = Chain()
        chain.domainsFail = true
        let model = try makeModel(chain)
        model.switchNetwork(to: .mainnet)
        await #expect(throws: WalletViewModel.MoveAssetsError.self) { _ = try await model.planMoveAssets(from: Self.main, to: Self.book) }
        #expect(chain.sent.isEmpty)
    }
}

/// A refresh reads the Domains tab's list again once it has been read, so a transfer shows up
/// when the indexer has caught up; a list never read is left to the tab.
@MainActor
struct DomainListRefreshTests {
    final class Names: TestChainService, @unchecked Sendable {
        var names: [TezosDomain] = []
        func tezBalance(for address: Address) async throws -> TezBalance { TezBalance(spendable: 1) }
        func tezosDomains(for address: Address) async throws -> [TezosDomain]? { names }
    }

    @Test func aRefreshPicksUpAChangedList() async throws {
        let chain = Names()
        chain.names = [DomainTransferTests.name("mytestdomain.tez", owner: WalletViewModel.sampleWallets[0].address)]
        let model = WalletViewModel(wallets: WalletViewModel.sampleWallets, chain: chain)
        await model.refreshDomainList()
        #expect(model.currentDomainList == nil)                           // never read: nothing done
        await model.loadDomainList()
        guard case .loaded(let before)? = model.currentDomainList else { Issue.record("not loaded"); return }
        #expect(before.count == 1)
        chain.names = []                                                    // the name has gone
        await model.refreshDomainList()
        guard case .loaded(let after)? = model.currentDomainList else { Issue.record("not loaded"); return }
        #expect(after.isEmpty)
    }
}
