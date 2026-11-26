import Foundation
import Testing
@testable import Signet

/// Fungible token transfers: exact smallest-unit amounts, FA1.2 beside FA2 in one request with
/// the bridge's call order, the raw balance kept from TzKT, the model's rule for the menu,
/// and Move assets taking tokens along.
struct TokenTransferTests {
    static let fa2 = "KT1FfjhvJZppBFQuUzNAdFPR1Z2jpD4XiXrF"
    static let fa12 = "KT1BPGyFqmGQqsU4oEL8NUXQpHQGwuFdyjd1"
    static let them = Address("tz1dCaMnnMJk76UodjewCK67ABiXWjcKj73N")

    @Test func amountsAreExactSmallestUnits() {
        #expect(TokenTransfer.rawAmount(from: "1.5", decimals: 6) == "1500000")
        #expect(TokenTransfer.rawAmount(from: "0,000001", decimals: 6) == "1")
        #expect(TokenTransfer.rawAmount(from: ".5", decimals: 1) == "5")
        #expect(TokenTransfer.rawAmount(from: "12", decimals: 0) == "12")
        #expect(TokenTransfer.rawAmount(from: "1.047540545999871429", decimals: 18) == "1047540545999871429")
        for bad in ["", "0", "0.0", "1.2345678", "-1", "1e3", "1.2.3", "abc", " . "] {
            #expect(TokenTransfer.rawAmount(from: bad, decimals: 6) == nil, Comment(rawValue: bad))
        }
        #expect(TokenTransfer.nat("999", isAtMost: "1000") && TokenTransfer.nat("1000", isAtMost: "1000") && !TokenTransfer.nat("1001", isAtMost: "1000"))
        #expect(AssetBalance.plainAmount(raw: "1500000", decimals: 6) == "1.5")
        #expect(AssetBalance.plainAmount(raw: "1", decimals: 6) == "0.000001")
        #expect(AssetBalance.plainAmount(raw: "30000000000", decimals: 6) == "30000")
        #expect(AssetBalance.plainAmount(raw: "42", decimals: 0) == "42")
    }

    @Test func fa12TransfersAreCallsOfTheirOwn() throws {
        let request = TokenTransferRequest(to: Self.them, transfers: [
            TokenTransfer(contract: Self.fa2, tokenId: "0", amount: "5"),
            TokenTransfer(contract: Self.fa12, tokenId: "0", amount: "10", standard: "fa1.2"),
            TokenTransfer(contract: Self.fa2, tokenId: "1", amount: "1"),
        ], tezMutez: "7")
        #expect(request.isValid && request.contracts == [Self.fa2, Self.fa12] && request.operationCount == 3)
        let rows = try #require(try JSONSerialization.jsonObject(with: Data(request.transfersJSON.utf8)) as? [[String: String]])
        #expect(rows[1]["standard"] == "fa1.2" && rows[0]["standard"] == nil)
        // An FA1.2 token has no id; one contract cannot be both standards.
        #expect(!TokenTransfer(contract: Self.fa12, tokenId: "1", amount: "1", standard: "fa1.2").isValid)
        #expect(!TokenTransferRequest(to: Self.them, transfers: [TokenTransfer(contract: Self.fa12, tokenId: "0", amount: "1", standard: "fa1.2"),
                                                                 TokenTransfer(contract: Self.fa12, tokenId: "0", amount: "1")]).isValid)
    }

    @Test func theIndexersExactBalanceIsKept() throws {
        let rows = try TzKTService.decode(Data(FungibleTokenTests.fixture.utf8))
        let tokens = TzKTService.fungibleTokens(from: rows)
        let rice = try #require(tokens.first { $0.symbol == "RICE" })
        #expect(rice.rawAmount == "10" && rice.decimals == 1 && rice.isFA12)
        let key = try #require(tokens.first { $0.symbol == "TKEY" })
        #expect(key.rawAmount == "1047540545999871429" && key.decimals == 18)
        let raw = try #require(key.rawAmount)
        let all = try #require(TokenTransfer(token: key, rawAmount: raw))
        #expect(all == TokenTransfer(contract: "KT1VaEsVNiBoA56eToEK6n6BcPgh1tdx9eXi", tokenId: "0", amount: "1047540545999871429"))
        #expect(TokenTransfer(token: rice, rawAmount: "10")?.standard == "fa1.2")
    }

    @Test @MainActor func onlyTokensWithAnExactBalanceOnASigningAccountOfferTransfer() throws {
        let store = InMemoryWalletStore()
        try store.add(WalletViewModel.sampleWallets[0], secretKey: "edskX")
        let model = WalletViewModel(wallets: [WalletViewModel.sampleWallets[0]], chain: MockChainService(), walletStore: store)
        var token = AssetBalance(id: "\(Self.fa2):0", kind: .token(contract: Self.fa2, tokenId: "0"), name: "GINE", symbol: "GINE", amount: 1, standard: "fa2")
        #expect(!model.canTransferToken(token))
        token.rawAmount = "1000000"; token.decimals = 6
        #expect(model.canTransferToken(token))
        #expect(!model.canTransferToken(token.onLayer2()))       // Layer 2 is off
        token.rawAmount = "0"
        #expect(!model.canTransferToken(token))
    }
}

extension MoveAssetsTests {
    @Test func tokensMoveWithTheNFTsAndTheTezIsSweptLast() async throws {
        let chain = Chain()
        chain.nftList = [Self.nft(1)]
        var gine = AssetBalance(id: "\(TokenTransferTests.fa2):0", kind: .token(contract: TokenTransferTests.fa2, tokenId: "0"), name: "Aubergine", symbol: "GINE", amount: 30_000, standard: "fa2")
        gine.rawAmount = "30000000000"; gine.decimals = 6
        var rice = AssetBalance(id: "\(TokenTransferTests.fa12):0", kind: .token(contract: TokenTransferTests.fa12, tokenId: "0"), name: "RICE", symbol: "RICE", amount: 1, standard: "fa1.2")
        rice.rawAmount = "10"; rice.decimals = 1
        let unknown = AssetBalance(id: "KT1MZg99PxMDEENwB4Fi64xkqAVh5d1rv8Z9:0", kind: .token(contract: "KT1MZg99PxMDEENwB4Fi64xkqAVh5d1rv8Z9", tokenId: "0"), name: "PEPE", symbol: "PEPE", amount: 5, standard: "fa2")
        chain.tokenList = [gine, rice, unknown]
        let model = try makeModel(chain)
        let plan = try await model.planMoveAssets(from: Self.main, to: Self.book)
        let layer = try #require(plan.layers.first)
        #expect(layer.tokens.map(\.symbol) == ["GINE", "RICE"] && layer.tokensLeftBehind.map(\.symbol) == ["PEPE"])
        let request = try #require(layer.batches.last?.request)
        #expect(request.transfers.map(\.amount) == ["30000000000", "10", "1"])
        #expect(request.transfers[1].isFA12 && request.tezMutez != nil)
        #expect(request.contracts == [TokenTransferTests.fa2, TokenTransferTests.fa12, Self.contract])
    }
}
