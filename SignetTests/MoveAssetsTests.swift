import Foundation
import Testing
@testable import Signet

/// Move assets: which accounts are offered, the refusals (staked, baker, an incomplete NFT
/// listing), the plan's groups with the tez sweep last, and the run bound to its context.
@MainActor
struct MoveAssetsTests {
    static let contract = "KT1RJ6PbjHpwc3M5rw5s2Nbmefwbuwbdxton"
    static let main = Wallet(alias: "Main", address: Address("tz1VSUr8wwNhLAzempoch5d6hLRiTh8Cjcjb"), keyKind: .unencrypted)
    static let book = Wallet(alias: "Friend", address: Address("tz1dCaMnnMJk76UodjewCK67ABiXWjcKj73N"), keyKind: .none)

    /// A chain whose balance, NFTs and baker state the test sets; sends are recorded.
    final class Chain: TestChainService, @unchecked Sendable {
        private let lock = NSLock()
        var balance = TezBalance(spendable: 10)
        var nftList: [NFT] = []
        var tokenList: [AssetBalance] = []
        var state: Portfolio.State = .complete
        var isBaker = false
        private var _sent: [TokenTransferRequest] = []
        var sent: [TokenTransferRequest] { lock.withLock { _sent } }

        func tezBalance(for address: Address) async throws -> TezBalance { balance }
        func portfolio(for address: Address) async throws -> Portfolio { Portfolio(tokens: tokenList, nfts: nftList, state: state) }
        func delegateInfo(for address: Address) async throws -> DelegateInfo {
            isBaker ? DelegateInfo(delegate: address, baker: .init(deactivated: false, gracePeriod: nil, consensusKey: nil, pendingConsensusKeys: [], companionKey: nil, pendingCompanionKeys: []), delegateAcceptsStaking: nil)
                    : DelegateInfo(delegate: nil, baker: nil, delegateAcceptsStaking: nil)
        }
        func sendTokenTransfer(_ request: TokenTransferRequest, from wallet: Wallet, signer: SigningKey, limits: BatchLimits) async throws -> SentOperation {
            lock.withLock { _sent.append(request) }
            return SentOperation(hash: "ooMove\(sent.count)")
        }
    }

    static func nft(_ id: Int, editions: Decimal = 1, transferable: Bool = true) -> NFT {
        var nft = NFT(id: "\(contract):\(id)", contract: contract, tokenId: "\(id)", name: "NFT \(id)", balance: editions, thumbnailURL: nil)
        nft.isTransferable = transferable
        return nft
    }

    func makeModel(_ chain: Chain) throws -> WalletViewModel {
        let store = InMemoryWalletStore()
        try store.add(Self.main, secretKey: "edskX")
        try store.addWatchOnly(Self.book)
        try store.addContract(MultisigContract(alias: "Vault", address: Address(Self.contract)))
        return WalletViewModel(chain: chain, walletStore: store, stateStore: InMemoryAppStateStore())
    }

    @Test func theSweepIsPartOfTheTokenRequest() {
        let to = Self.book.address
        #expect(TokenTransferRequest(to: to, transfers: [], tezMutez: "5").isValid)
        #expect(TokenTransferRequest(to: to, transfers: [], tezMutez: "5").operationCount == 1)
        #expect(TokenTransferRequest(to: to, transfers: [TokenTransfer(contract: Self.contract, tokenId: "1", amount: "1")], tezMutez: "5").operationCount == 2)
        for bad in ["0", "05", "-1", "1.5", "", "9007199254740993"] {
            #expect(!TokenTransferRequest(to: to, transfers: [], tezMutez: bad).isValid, Comment(rawValue: bad))
        }
        #expect(!TokenTransferRequest(to: TokenTransferRequest.burnAddress, transfers: [], tezMutez: "5").isValid)
        #expect(!TokenTransferRequest(to: to, transfers: []).isValid)
    }

    @Test func accountsOnOfferAreOursToMoveFromAndAnyAccountToMoveTo() throws {
        let model = try makeModel(Chain())
        #expect(model.moveSources.map(\.alias) == ["Main"])
        #expect(model.moveDestinations(from: Self.main).map(\.alias) == ["Friend"])
        #expect(model.canMoveAssets)
        #expect(WalletViewModel.holdsKey(of: Self.main) && !WalletViewModel.holdsKey(of: Self.book))
    }

    @Test func stakedTezABakerOrAnIncompleteListingStopTheMove() async throws {
        let chain = Chain()
        let model = try makeModel(chain)
        chain.balance = TezBalance(spendable: 10, staked: 5)
        await #expect(throws: WalletViewModel.MoveAssetsError.staked(alias: "Main", staked: 5, unstaking: 0)) { _ = try await model.planMoveAssets(from: Self.main, to: Self.book) }
        chain.balance = TezBalance(spendable: 10, unstakedFinalizable: 2)
        await #expect(throws: WalletViewModel.MoveAssetsError.staked(alias: "Main", staked: 0, unstaking: 2)) { _ = try await model.planMoveAssets(from: Self.main, to: Self.book) }
        chain.balance = TezBalance(spendable: 10)
        chain.isBaker = true
        await #expect(throws: WalletViewModel.MoveAssetsError.baker(alias: "Main")) { _ = try await model.planMoveAssets(from: Self.main, to: Self.book) }
        chain.isBaker = false
        chain.state = .partial(fetched: 500)
        await #expect(throws: WalletViewModel.MoveAssetsError.self) { _ = try await model.planMoveAssets(from: Self.main, to: Self.book) }
        chain.state = .complete
        // Wrong way round, or into a contract: refused before the chain is asked.
        await #expect(throws: WalletViewModel.MoveAssetsError.sourceCannotSign) { _ = try await model.planMoveAssets(from: Self.book, to: Self.main) }
        await #expect(throws: WalletViewModel.MoveAssetsError.sameAccount) { _ = try await model.planMoveAssets(from: Self.main, to: Self.main) }
        chain.balance = TezBalance(spendable: 0)
        await #expect(throws: WalletViewModel.MoveAssetsError.nothingToMove) { _ = try await model.planMoveAssets(from: Self.main, to: Self.book) }
        #expect(chain.sent.isEmpty)
    }

    @Test func thePlanSweepsTheTezLastAndLeavesSoulboundTokens() async throws {
        let chain = Chain()
        chain.nftList = [Self.nft(1), Self.nft(2, editions: 3), Self.nft(3, transferable: false)]
        let model = try makeModel(chain)
        let plan = try await model.planMoveAssets(from: Self.main, to: Self.book)
        let layer = try #require(plan.layers.first)
        #expect(plan.layers.count == 1 && layer.batches.count == 1)
        #expect(layer.nfts.count == 2 && layer.editions == 4 && layer.leftBehind.map(\.tokenId) == ["3"])
        let request = layer.batches[0].request
        #expect(request.transfers == [TokenTransfer(contract: Self.contract, tokenId: "1", amount: "1"), TokenTransfer(contract: Self.contract, tokenId: "2", amount: "3")])
        // 10 tez less the estimate's 0.001 tez.
        #expect(request.tezMutez == "9999000" && layer.tez == Decimal(string: "9.999")!)
        #expect(layer.batches[0].estimate.limits.operations.count == request.operationCount)
    }

    @Test func manyNFTsTakeSeveralGroupsWithTheSweepOnTheLast() async throws {
        let chain = Chain()
        chain.nftList = (1...150).map { Self.nft($0) }
        let model = try makeModel(chain)
        let plan = try await model.planMoveAssets(from: Self.main, to: Self.book)
        let batches = try #require(plan.layers.first).batches
        #expect(batches.map(\.request.count) == [100, 50])
        #expect(batches[0].request.tezMutez == nil && batches[1].request.tezMutez == "9998000")
        try await model.moveAssets(plan, passphrase: nil) { _ in }
        #expect(chain.sent == batches.map(\.request))
    }

    @Test func theMoveRunsInItsOwnContextOnly() async throws {
        let chain = Chain()
        chain.nftList = [Self.nft(1)]
        let model = try makeModel(chain)
        let plan = try await model.planMoveAssets(from: Self.main, to: Self.book)
        var steps: [WalletViewModel.MoveAssetsStep] = []
        try await model.moveAssets(plan, passphrase: nil) { steps.append($0) }
        #expect(steps.map(\.hash) == ["ooMove1"] && chain.sent.count == 1)
        // Another network since planning: nothing more is sent.
        let again = try await model.planMoveAssets(from: Self.main, to: Self.book)
        model.switchNetwork(to: model.network == .shadownet ? .mainnet : .shadownet)
        await #expect(throws: WalletViewModel.WalletError.contextChanged) { try await model.moveAssets(again, passphrase: nil) { _ in } }
        #expect(chain.sent.count == 1)
    }
}
