import Foundation
import Testing
@testable import Signet

struct FungibleTokenTests {
    static let fixture = """
    [
      {"balance":"1","token":{"contract":{"address":"KT1GBZmSxmnKJXGMdMLbugPfLyUPmuLSMwKS"},"tokenId":"143032","standard":"fa2","metadata":{"name":"captstake.tez","symbol":"TD","decimals":"0"}}},
      {"balance":"30000000000","token":{"contract":{"address":"KT1FfjhvJZppBFQuUzNAdFPR1Z2jpD4XiXrF"},"tokenId":"0","standard":"fa2","metadata":{"name":"Aubergine","symbol":"GINE","decimals":"6","thumbnailUri":"https://gateway.pinata.cloud/ipfs/Qmaf8m2vtegsvoWybB2AL1wJ4Q79SwornWx8T7DbkYRhv9"}}},
      {"balance":"10","token":{"contract":{"address":"KT1BPGyFqmGQqsU4oEL8NUXQpHQGwuFdyjd1"},"tokenId":"0","standard":"fa1.2","metadata":{"name":"FabRicE","symbol":"RICE","decimals":"1","icon":"https://example.com/rice.jpg"}}},
      {"balance":"1047540545999871429","token":{"contract":{"address":"KT1VaEsVNiBoA56eToEK6n6BcPgh1tdx9eXi"},"tokenId":"0","standard":"fa2","metadata":{"name":"Temple Key","symbol":"TKEY","decimals":"18","thumbnailUri":"ipfs://Qmb9QUXYn1PW8e7E2CwpBMgEur7gFAPPpq2Zh7H2D7eQcT"}}},
      {"balance":"500000","token":{"contract":{"address":"KT1MZg99PxMDEENwB4Fi64xkqAVh5d1rv8Z9"},"tokenId":"0","standard":"fa2","metadata":{"name":"Tezos Pepe","symbol":"PEPE","decimals":"2"}}},
      {"balance":"1","token":{"contract":{"address":"KT1NFT"},"tokenId":"7","standard":"fa2","metadata":{"name":"Picture","decimals":"0","displayUri":"ipfs://QmNrhZHUaEqxhyLfqoq1mtHSipkWHeT31LNHb1QEbDHgnc"}}}
    ]
    """

    @Test func picksFungibleTokensAndScalesByDecimals() throws {
        let rows = try TzKTService.decode(Data(Self.fixture.utf8))
        let tokens = TzKTService.fungibleTokens(from: rows)
        #expect(tokens.map(\.symbol) == ["GINE", "PEPE", "TKEY", "RICE"])   // largest balance first
        #expect(tokens.first { $0.symbol == "GINE" }?.amount == 30_000)
        #expect(tokens.first { $0.symbol == "PEPE" }?.amount == 5_000)
        #expect(tokens.first { $0.symbol == "RICE" }?.amount == 1)
        #expect(tokens.first { $0.symbol == "TKEY" }?.amount == Decimal(string: "1.047540545999871429"))
        #expect(tokens.first { $0.symbol == "RICE" }?.standard == "fa1.2")
        #expect(tokens.first { $0.symbol == "RICE" }?.iconURLs.first?.absoluteString == "https://example.com/rice.jpg")
        #expect(tokens.first { $0.symbol == "TKEY" }?.iconURLs.count == IPFS.gateways.count)
        #expect(tokens.first { $0.symbol == "GINE" }?.kind == .token(contract: "KT1FfjhvJZppBFQuUzNAdFPR1Z2jpD4XiXrF", tokenId: "0"))
        // The domain token and the picture are not assets: zero decimals, and the picture is an NFT.
        #expect(!tokens.contains { $0.name == "captstake.tez" || $0.name == "Picture" })
        #expect(TzKTService.nfts(from: rows).map(\.name) == ["Picture"])
    }

    @Test(.tags(.network), .liveNetwork, .timeLimit(.minutes(1)))
    func liveMainnetTokens() async throws {
        let tokens = try await TzKTService(baseURL: Network.mainnet.tzktURL!).fungibleTokens(for: MockChainService.captainStake)
        let symbols = Set(tokens.map(\.symbol))
        #expect(symbols.isSuperset(of: ["PEPE", "TKEY", "GINE"]), Comment(rawValue: "got \(symbols)"))
    }
}

/// S26: a portfolio says when it is incomplete or unavailable, and token metadata cannot lie about scaling.
struct PortfolioStateTests {
    @Test func unreadableDecimalsAreNotGuessed() throws {
        let rows = try TzKTService.decode(Data("""
        [
          {"balance":"100","token":{"contract":{"address":"KT1A"},"tokenId":"0","standard":"fa2","metadata":{"name":"Huge","symbol":"HUGE","decimals":"400"}}},
          {"balance":"100","token":{"contract":{"address":"KT1B"},"tokenId":"0","standard":"fa2","metadata":{"name":"Neg","symbol":"NEG","decimals":"-3"}}},
          {"balance":"100","token":{"contract":{"address":"KT1C"},"tokenId":"0","standard":"fa2","metadata":{"name":"Text","symbol":"TXT","decimals":"lots"}}},
          {"balance":"100","token":{"contract":{"address":"KT1D"},"tokenId":"0","standard":"fa1.2","metadata":{"name":"Old","symbol":"OLD","decimals":"1e2"}}},
          {"balance":"-5","token":{"contract":{"address":"KT1E"},"tokenId":"0","standard":"fa2","metadata":{"name":"Neg balance","symbol":"NB","decimals":"2"}}},
          {"balance":"250","token":{"contract":{"address":"KT1F"},"tokenId":"0","standard":"fa2","metadata":{"name":"Fine","symbol":"OK","decimals":"2"}}}
        ]
        """.utf8))
        let tokens = TzKTService.fungibleTokens(from: rows)
        #expect(tokens.map(\.symbol) == ["OLD", "OK"])
        #expect(tokens.first { $0.symbol == "OLD" }?.amount == 100)   // FA1.2 with unreadable decimals: shown unscaled
        #expect(tokens.first { $0.symbol == "OK" }?.amount == Decimal(string: "2.5"))
        #expect(TzKTService.nfts(from: rows).isEmpty)
    }

    @MainActor
    @Test func anUnavailableIndexerKeepsTheLastKnownListAndSaysSo() async throws {
        final class Flaky: TestChainService, @unchecked Sendable {
            var fail = false
            func tezBalance(for address: Address) async throws -> TezBalance { TezBalance(spendable: 1, staked: 0) }
            func portfolio(for address: Address) async throws -> Portfolio {
                fail ? Portfolio(tokens: [], nfts: [], state: .unavailable("HTTP 503"))
                     : Portfolio(tokens: [AssetBalance(id: "t", kind: .token(contract: "KT1x", tokenId: "0"), name: "Tok", symbol: "TOK", amount: 1)], nfts: [], state: .partial(fetched: 1000))
            }
        }
        let chain = Flaky()
        let model = WalletViewModel(wallets: [Wallet(alias: "A", address: Address("tz1VSUr8wwNhLAzempoch5d6hLRiTh8Cjcjb"), keyKind: .unencrypted)], chain: chain)
        await model.refresh()
        #expect(model.tokens.map(\.symbol) == ["TOK"])
        #expect(model.portfolioState == .partial(fetched: 1000))
        chain.fail = true
        await model.refresh()
        #expect(model.tokens.map(\.symbol) == ["TOK"], "last known holdings stay on screen")
        #expect(model.portfolioState == .unavailable("HTTP 503"))
    }
}

/// Metadata Signet reads for itself when the indexer has none: the `token_metadata` big map
/// entry and the TZIP-21 document it names (seen live: Etherlink Shadownet's TzKT resolved
/// nothing for a fresh FA2, so its NFT was neither an asset nor an NFT).
struct TokenMetadataFallbackTests {
    typealias Metadata = TzKTService.TokenBalance.Token.Metadata
    static let contract = "KT1MJPVfyTqycX13mGq8Adpays8yxJrNPjXp"
    static let uri = "ipfs://bafkreib5alq3q4zsqokoohi6nrp23uzqnolto67aomapucnr5yk3tj3olu"
    static let image = "ipfs://bafybeigqpjyhcy2kkb4f5rpdgs7al6pgaqcpfum2344ttekzxbm7i4qxku"
    static let document = Data("""
    {"name":"Layer 2 Elvis","description":"My dog has always wanted to visit Etherlink","decimals":0,"isBooleanAmount":true,"symbol":"NFT",
     "artifactUri":"\(image)","displayUri":"\(image)","thumbnailUri":"\(image)","creators":["tz3Rb5RVucLc6ani23jVdZM4Qm6c4oQ74zhh"],
     "formats":[{"uri":"\(image)","mimeType":"image/jpeg"}],"tags":[]}
    """.utf8)
    /// TzKT's reply for `/v1/contracts/<KT1>/bigmaps/token_metadata/keys/0`, the URI as hex bytes.
    static let keyReply = Data("""
    {"id":81,"active":true,"key":"0","value":{"token_id":"0","token_info":{"":"\(uri.utf8.map { String(format: "%02x", $0) }.joined())","symbol":"4e4654","odd":"zz"}}}
    """.utf8)

    @Test func theBigMapEntryIsHexDecoded() throws {
        let info = try #require(TzKTService.parseTokenInfo(Self.keyReply))
        #expect(info[""] == Self.uri && info["symbol"] == "NFT" && info["odd"] == nil)
        #expect(TzKTService.parseTokenInfo(Data("[]".utf8)) == nil)
    }

    @Test func aDocumentWithNumericDecimalsReadsAsTheIndexerWouldReportIt() throws {
        let metadata = try #require(TokenMetadataResolver.decodeDocument(Self.document))
        #expect(metadata.name == "Layer 2 Elvis" && metadata.decimals == "0" && metadata.decimalPlaces == 0 && metadata.symbol == "NFT")
        #expect(metadata.displayUri == Self.image && metadata.formats?.first?.mimeType == "image/jpeg")
        // Odd types are missing fields, not a failure; a non-object is nothing.
        let odd = try #require(TokenMetadataResolver.decodeDocument(Data(#"{"name":7,"decimals":"6","symbol":"X","formats":"no"}"#.utf8)))
        #expect(odd.name == nil && odd.decimals == "6" && odd.symbol == "X" && odd.formats == nil)
        #expect(TokenMetadataResolver.decodeDocument(Data("[1,2]".utf8)) == nil)
        #expect(TokenMetadataResolver.decodeDocument(Data("{}".utf8))?.isEmpty == true)
    }

    @Test func directEntriesOverrideTheDocumentAndNothingUsableIsNil() {
        let merged = TokenMetadataResolver.metadata(from: ["": Self.uri, "name": "Elvis on chain", "decimals": "0"], document: Self.document)
        #expect(merged?.name == "Elvis on chain" && merged?.symbol == "NFT" && merged?.displayUri == Self.image)
        // No document: the direct entries alone still describe a token.
        let direct = TokenMetadataResolver.metadata(from: ["name": "Plain", "symbol": "PLN", "decimals": "6"], document: nil)
        #expect(direct?.name == "Plain" && direct?.decimalPlaces == 6)
        #expect(TokenMetadataResolver.metadata(from: ["": "tezos-storage:content"], document: nil) == nil)
        #expect(TokenMetadataResolver.metadata(from: [:], document: Data("{}".utf8)) == nil)
    }

    @Test func documentsAreFetchedOnlyFromGatewaysOrPublicHTTPS() {
        #expect(TokenMetadataResolver.documentURLs(for: Self.uri).count == IPFS.gateways.count)
        #expect(TokenMetadataResolver.documentURLs(for: "https://example.com/meta/0.json").map(\.absoluteString) == ["https://example.com/meta/0.json"])
        #expect(TokenMetadataResolver.documentURLs(for: "http://example.com/meta.json").isEmpty)
        #expect(TokenMetadataResolver.documentURLs(for: "https://localhost/meta.json").isEmpty)
        #expect(TokenMetadataResolver.documentURLs(for: "tezos-storage:content").isEmpty)
        #expect(TokenMetadataResolver.documentURLs(for: "ipfs://not a cid").isEmpty)
    }

    @Test func rowsWithoutMetadataAreFilledAndThenClassified() async throws {
        let rows = try TzKTService.decode(Data("""
        [
          {"balance":"1","token":{"contract":{"address":"\(Self.contract)"},"tokenId":"0","standard":"fa2","metadata":null}},
          {"balance":"1","token":{"contract":{"address":"KT1BPGyFqmGQqsU4oEL8NUXQpHQGwuFdyjd1"},"tokenId":"0","standard":"fa2","metadata":{"name":"Known","decimals":"0","displayUri":"\(Self.image)"}}},
          {"balance":"5","token":{"contract":{"address":"KT1VaEsVNiBoA56eToEK6n6BcPgh1tdx9eXi"},"tokenId":"3","standard":"fa2","metadata":null}}
        ]
        """.utf8))
        actor Log { var asked: [String] = []; func add(_ s: String) { asked.append(s) } }
        let log = Log()
        let resolver = TokenMetadataResolver(scope: UUID().uuidString, tokenInfo: { contract, tokenId in
            await log.add("info \(contract):\(tokenId)")
            return contract == Self.contract ? TzKTService.parseTokenInfo(Self.keyReply) : nil
        }, document: { url in
            await log.add("doc \(url.host() ?? "")")
            return url.absoluteString.contains("bafkreib5alq3q4z") ? Self.document : nil
        })
        let filled = await resolver.fill(rows)
        #expect(filled[0].token.metadata?.name == "Layer 2 Elvis" && filled[1].token.metadata?.name == "Known" && filled[2].token.metadata == nil)
        #expect(TzKTService.nfts(from: filled).map(\.name) == ["Layer 2 Elvis", "Known"])
        #expect(TzKTService.fungibleTokens(from: filled).isEmpty)
        var asked = await log.asked
        #expect(asked == ["info \(Self.contract):0", "doc ipfs.filebase.io", "info KT1VaEsVNiBoA56eToEK6n6BcPgh1tdx9eXi:3"])

        // The next load answers both from the cache, the hit and the miss alike.
        let again = await resolver.fill(rows)
        #expect(again[0].token.metadata?.name == "Layer 2 Elvis" && again[2].token.metadata == nil)
        asked = await log.asked
        #expect(asked.count == 3)
    }

    @Test(.tags(.network), .liveNetwork, .timeLimit(.minutes(1)))
    func liveEtherlinkShadownetTokenMetadata() async throws {
        let tzkt = TzKTService(baseURL: try #require(Network.shadownet.l2TzKTURL))
        let info = try #require(try await tzkt.tokenInfo(contract: Self.contract, tokenId: "0"))
        #expect(info[""] == Self.uri)
        let metadata = await TokenMetadataResolver.live(tzkt: tzkt).resolve(contract: Self.contract, tokenId: "0")
        #expect(metadata?.name == "Layer 2 Elvis" && metadata?.decimalPlaces == 0)
    }
}
