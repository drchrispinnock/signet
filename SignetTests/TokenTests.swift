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
