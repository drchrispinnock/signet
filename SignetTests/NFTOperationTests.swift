import Foundation
import Testing
@testable import Signet

/// NFT Transfer and Burn (0.9.13): the request the bridge is given, the batch limits it must
/// send with, the metadata that turns the menu off, and the model's bound estimate and send.
struct NFTOperationTests {
    static let a = "KT1RJ6PbjHpwc3M5rw5s2Nbmefwbuwbdxton"
    static let b = "KT1KEa8z6vWXDJrVqtMrAeDVzsvxat3kHaCE"
    static let them = Address("tz1dCaMnnMJk76UodjewCK67ABiXWjcKj73N")

    @Test func requestGroupsByContractAndIsCheckedBeforeTheBridge() throws {
        let request = TokenTransferRequest(to: Self.them, transfers: [
            TokenTransfer(contract: Self.a, tokenId: "7", amount: "1"), TokenTransfer(contract: Self.b, tokenId: "12", amount: "3"), TokenTransfer(contract: Self.a, tokenId: "9", amount: "1"),
        ])
        #expect(request.isValid && !request.isBurn && request.count == 3 && request.contracts == [Self.a, Self.b])
        let rows = try #require(try JSONSerialization.jsonObject(with: Data(request.transfersJSON.utf8)) as? [[String: String]])
        #expect(rows == [["contract": Self.a, "tokenId": "7", "amount": "1"], ["contract": Self.b, "tokenId": "12", "amount": "3"], ["contract": Self.a, "tokenId": "9", "amount": "1"]])
        #expect(TokenTransferRequest(to: TokenTransferRequest.burnAddress, transfers: request.transfers).isBurn)
        #expect(TokenTransferRequest.burnAddress.isValidAccount)
        // Nothing, too much, a bad recipient, contract, id or amount, or a zero amount: not sent.
        #expect(!TokenTransferRequest(to: Self.them, transfers: []).isValid)
        #expect(!TokenTransferRequest(to: Self.them, transfers: Array(repeating: request.transfers[0], count: TokenTransferRequest.maxTokens + 1)).isValid)
        #expect(!TokenTransferRequest(to: Address("tz1nope"), transfers: request.transfers).isValid)
        for bad in [TokenTransfer(contract: Self.them.value, tokenId: "1", amount: "1"), TokenTransfer(contract: Self.a, tokenId: "01", amount: "1"),
                    TokenTransfer(contract: Self.a, tokenId: "-1", amount: "1"), TokenTransfer(contract: Self.a, tokenId: "1", amount: "0"),
                    TokenTransfer(contract: Self.a, tokenId: "1", amount: "1.5"), TokenTransfer(contract: Self.a, tokenId: "", amount: "1")] {
            #expect(!bad.isValid, Comment(rawValue: "\(bad)"))
        }
        let nft = NFT(id: "\(Self.a):5", contract: Self.a, tokenId: "5", name: "x", balance: 4, thumbnailURL: nil)
        #expect(TokenTransfer(nft: nft, amount: 2) == TokenTransfer(contract: Self.a, tokenId: "5", amount: "2"))
    }

    @Test func batchLimitsRoundTripThroughTheBridgeShape() throws {
        let json = """
        {"operations":[{"feeMutez":"500","gasLimit":1500,"storageLimit":0},{"feeMutez":"700","gasLimit":2500,"storageLimit":100}],"revealFeeMutez":"374","revealGasLimit":200,"revealStorageLimit":0}
        """
        let limits = try #require(BatchLimits(JSONValue(bridged: try JSONSerialization.jsonObject(with: Data(json.utf8)))))
        #expect(limits.operations.count == 2 && limits.operations[1] == BatchLimits.Operation(feeMutez: "700", gasLimit: 2500, storageLimit: 100))
        #expect(limits.revealFeeMutez == "374" && limits.revealGasLimit == 200)
        let back = try JSONDecoder().decode(BatchLimits.self, from: Data(limits.json.utf8))
        #expect(back == limits)
        // Missing or malformed figures are refused, never defaulted (S20).
        for broken in ["{\"operations\":[]}", "{\"operations\":[{\"feeMutez\":\"5e2\",\"gasLimit\":1,\"storageLimit\":0}]}",
                       "{\"operations\":[{\"feeMutez\":\"500\",\"gasLimit\":1.5,\"storageLimit\":0}]}", "{\"operations\":[{\"feeMutez\":\"500\",\"gasLimit\":1}]}",
                       "{\"operations\":[{\"feeMutez\":\"500\",\"gasLimit\":1,\"storageLimit\":0}],\"revealFeeMutez\":\"x\"}"] {
            #expect(BatchLimits(JSONValue(bridged: try JSONSerialization.jsonObject(with: Data(broken.utf8)))) == nil, Comment(rawValue: broken))
        }
    }

    @Test func soulboundTokensAndArtifactsAreReadFromTheMetadata() throws {
        let fixture = """
        [
          { "balance": "1", "token": { "contract": { "address": "\(Self.a)" }, "tokenId": "1", "standard": "fa2",
            "metadata": { "name": "Badge", "decimals": "0", "isTransferable": false, "displayUri": "ipfs://QmXxvrULyrWH18e6kUinPNXt5PAwv6h7MPcmWbSw4DwDuP" } } },
          { "balance": "1", "token": { "contract": { "address": "\(Self.a)" }, "tokenId": "2", "standard": "fa2",
            "metadata": { "name": "Worded", "decimals": "0", "isTransferable": "False", "displayUri": "ipfs://QmXxvrULyrWH18e6kUinPNXt5PAwv6h7MPcmWbSw4DwDuP" } } },
          { "balance": "1", "token": { "contract": { "address": "\(Self.a)" }, "tokenId": "3", "standard": "fa2",
            "metadata": { "name": "Art", "decimals": "0", "isTransferable": "maybe", "displayUri": "ipfs://QmXxvrULyrWH18e6kUinPNXt5PAwv6h7MPcmWbSw4DwDuP",
                          "artifactUri": "ipfs://Qmaf8m2vtegsvoWybB2AL1wJ4Q79SwornWx8T7DbkYRhv9", "formats": [ { "uri": "ipfs://Qmaf8m2vtegsvoWybB2AL1wJ4Q79SwornWx8T7DbkYRhv9", "mimeType": "video/mp4" } ] } } }
        ]
        """.data(using: .utf8)!
        let nfts = TzKTService.nfts(from: try TzKTService.decode(fixture))
        #expect(nfts.map(\.isTransferable) == [false, false, true])
        #expect(nfts[0].artifactURLs.isEmpty)
        #expect(nfts[2].artifactURLs == IPFS.candidateURLs(for: "ipfs://Qmaf8m2vtegsvoWybB2AL1wJ4Q79SwornWx8T7DbkYRhv9") && nfts[2].isMoving)
        let ops = NFTOperation(kind: .burn, nfts: Array(nfts.prefix(2)))
        #expect(ops.layer == 1 && ops.id == "burn:\(Self.a):1,\(Self.a):2")
        #expect(NFTOperation(kind: .transfer, nfts: [nfts[2].onLayer2()]).layer == 2)
    }

    @Test func tokenLinksFollowTheNetwork() {
        #expect(Network.mainnet.explorerURL(token: Self.a, id: "7")?.absoluteString == "https://tzkt.io/\(Self.a)/tokens/7")
        #expect(Network.mainnet.objktURL(token: Self.a, id: "7")?.absoluteString == "https://objkt.com/tokens/\(Self.a)/7")
        #expect(Network.shadownet.objktURL(token: Self.a, id: "7") == nil)
        #expect(Network.mainnet.l2On.layer2?.objktURL(token: Self.a, id: "7") == nil)
        #expect(Network.mainnet.l2On.layer2?.explorerURL(token: Self.a, id: "7")?.host()?.contains("etherlink") == true)
    }

    @Test @MainActor func theModelEstimatesAndSendsOnlyInTheSameContext() async throws {
        let store = InMemoryWalletStore()
        let wallet = Wallet(alias: "Main", address: Address("tz1VSUr8wwNhLAzempoch5d6hLRiTh8Cjcjb"), keyKind: .unencrypted)
        try store.add(wallet, secretKey: "edskX")
        let model = WalletViewModel(chain: MockChainService(), walletStore: store, stateStore: InMemoryAppStateStore())
        #expect(model.selectedWallet?.address == wallet.address)
        #expect(model.canTransferTokens(on: 1) && !model.canTransferTokens(on: 2))   // Layer 2 is off by default
        let request = TokenTransferRequest(to: Self.them, transfers: [TokenTransfer(contract: Self.a, tokenId: "7", amount: "1"), TokenTransfer(contract: Self.b, tokenId: "1", amount: "2")])
        let approved = try await model.estimateTokenTransfer(request, on: 1)
        #expect(approved.estimate.limits.operations.count == 2 && approved.estimate.total == approved.estimate.fee + approved.estimate.burn)
        // Not estimated, another request, or another layer: refused before any key is touched.
        await #expect(throws: WalletViewModel.WalletError.notEstimated) { try await model.transferTokens(request, on: 1, approved: nil, passphrase: nil) }
        let other = TokenTransferRequest(to: TokenTransferRequest.burnAddress, transfers: request.transfers)
        await #expect(throws: WalletViewModel.WalletError.contextChanged) { try await model.transferTokens(other, on: 1, approved: approved, passphrase: nil) }
        await #expect(throws: WalletViewModel.WalletError.contextChanged) { try await model.transferTokens(request, on: 2, approved: approved, passphrase: nil) }
        let (hash, level) = try await model.transferTokens(request, on: 1, approved: approved, passphrase: nil)
        #expect(hash == "ooMockTokens2" && level >= 1)
        // A bad request never reaches the chain service.
        await #expect(throws: ChainError.invalidTokenTransfer) { _ = try await model.estimateTokenTransfer(TokenTransferRequest(to: Self.them, transfers: []), on: 1) }
    }
}
