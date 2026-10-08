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
      {"balance":"1","token":{"contract":{"address":"KT1NFT"},"tokenId":"7","standard":"fa2","metadata":{"name":"Picture","decimals":"0","displayUri":"ipfs://QmPic"}}}
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

    @Test(.tags(.network), .timeLimit(.minutes(1)))
    func liveMainnetTokens() async throws {
        let tokens = try await TzKTService(baseURL: Network.mainnet.tzktURL!).fungibleTokens(for: MockChainService.captainStake)
        let symbols = Set(tokens.map(\.symbol))
        #expect(symbols.isSuperset(of: ["PEPE", "TKEY", "GINE"]), Comment(rawValue: "got \(symbols)"))
    }
}
