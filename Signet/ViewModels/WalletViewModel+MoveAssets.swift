import Foundation

/// Move assets: everything one of our accounts holds goes to another account in the list, tez,
/// fungible tokens, NFTs and (on mainnet) the Tezos Domains names it owns, pointed at the new
/// account, on Tezos and (with Layer 2 on) on Etherlink.
/// Each layer is one operation group, the token and NFT transfers first and the tez sweep last
/// (`TokenTransferRequest.tezMutez`), under one signature, with the approved limits (S14) and
/// bound to the context it was planned in (S31). A layer holding more than
/// `TokenTransferRequest.maxTokens` NFTs takes several groups, the sweep riding on the last.
/// An account with staked or unstaking tez, or a registered baker, is refused: those tez
/// cannot be moved by a transfer, and a baker's account cannot be emptied.
extension WalletViewModel {
    enum MoveAssetsError: LocalizedError, Equatable {
        case sameAccount
        case sourceCannotSign
        case notInList
        case contract
        case staked(alias: String, staked: Decimal, unstaking: Decimal)
        case baker(alias: String)
        case nftsUnknown(layer: String, reason: String)
        case domainsUnknown(reason: String)
        case cannotPayFees(layer: String)
        case nothingToMove

        var errorDescription: String? {
            switch self {
            case .sameAccount: "Choose two different accounts."
            case .sourceCannotSign: "Signet cannot sign for the account the assets would leave."
            case .notInList: "Both accounts must be in your list of accounts and address book."
            case .contract: "Assets can only move between accounts, not into or out of a contract."
            case .staked(let alias, let staked, let unstaking):
                "“\(alias)” has " + [staked > 0 ? "\(AssetBalance.format(staked, symbol: "tz")) staked" : nil, unstaking > 0 ? "\(AssetBalance.format(unstaking, symbol: "tz")) unstaking" : nil].compactMap { $0 }.joined(separator: " and ")
                    + ". Staked tez cannot be moved by a transfer: unstake, wait for the tez to be finalizable, finalize them in Stake, then move the assets. Nothing was moved."
            case .baker(let alias): "“\(alias)” is a registered baker, and a baker's account cannot be emptied. Nothing was moved."
            case .nftsUnknown(let layer, let reason): "Signet could not list every NFT on \(layer) (\(reason)), so it will not empty the account and leave them without tez for fees. Nothing was moved."
            case .domainsUnknown(let reason): "Signet could not list the account's Tezos Domains names (\(reason)), so it will not empty the account and leave them with no tez to move them later. Nothing was moved."
            case .cannotPayFees(let layer): "There is not enough tez on \(layer) to pay for moving its NFTs. Nothing was moved."
            case .nothingToMove: "There is nothing to move: no tez, tokens or NFTs that can be transferred."
            }
        }
    }

    /// What will move, layer by layer, and the context it was planned in.
    struct MoveAssetsPlan: Sendable {
        struct Batch: Sendable, Hashable {
            let request: TokenTransferRequest
            let estimate: TokenTransferEstimate
        }
        struct Layer: Sendable {
            let layer: Int
            let name: String
            let network: Network
            let chain: any ChainService
            /// Spendable tez on this layer when planned.
            let balance: Decimal
            /// Tez that arrives at the destination.
            let tez: Decimal
            let nfts: [NFT]
            /// NFTs whose metadata says they cannot be transferred; they stay behind.
            let leftBehind: [NFT]
            /// Fungible tokens moved, all of each.
            var tokens: [AssetBalance] = []
            /// Tokens whose exact balance the indexer did not give; they stay behind.
            var tokensLeftBehind: [AssetBalance] = []
            /// Tezos Domains names moved, each pointed at the destination.
            var domains: [TezosDomain] = []
            /// Names the account owns that have expired, and names that only point at it.
            var domainsLeftBehind: [TezosDomain] = []
            let batches: [Batch]
            /// Fees and storage burn of every group on this layer.
            var cost: Decimal { batches.reduce(0) { $0 + $1.estimate.total } }
            var editions: Int { nfts.reduce(0) { $0 + NSDecimalNumber(decimal: $1.balance).intValue } }
        }
        let source: Wallet
        let destination: Wallet
        let context: BridgeContext
        let layers: [Layer]
        /// Things the plan leaves out, worded for the review (a layer the destination cannot use…).
        let notes: [String]
        var batchCount: Int { layers.reduce(0) { $0 + $1.batches.count } }
    }

    /// One operation group carried out.
    struct MoveAssetsStep: Sendable, Hashable, Identifiable {
        let layer: Int
        let index: Int
        let hash: String
        let level: Int
        let explorerURL: URL?
        var id: String { "\(layer):\(index)" }
    }

    /// Accounts the assets can leave: implicit accounts Signet can sign for.
    var moveSources: [Wallet] { wallets.filter { $0.keyKind.canSign && !$0.address.isContract } }

    /// Accounts the assets can go to: any other implicit account in the list or address book.
    func moveDestinations(from source: Wallet?) -> [Wallet] {
        wallets.filter { !$0.address.isContract && $0.address != source?.address }
    }

    /// The Move assets item: there is an account to move from and another to move to.
    var canMoveAssets: Bool { moveSources.contains { !moveDestinations(from: $0).isEmpty } }

    /// Whether the destination is one Signet signs for, so the move can be undone from here.
    static func holdsKey(of wallet: Wallet) -> Bool { wallet.keyKind.canSign }

    /// Reads both layers, refuses what cannot be moved and estimates every group. Nothing is signed.
    func planMoveAssets(from source: Wallet, to destination: Wallet) async throws -> MoveAssetsPlan {
        guard source.address != destination.address else { throw MoveAssetsError.sameAccount }
        guard source.keyKind.canSign else { throw MoveAssetsError.sourceCannotSign }
        guard !source.address.isContract, !destination.address.isContract else { throw MoveAssetsError.contract }
        guard isListed(source), isListed(destination) else { throw MoveAssetsError.notInList }
        let context = operationContext(for: source)
        let network = self.network
        let chain = chainService

        // Layer 1: stop on staked or unstaking tez, and on a baker.
        var spendable: Decimal = 0
        do {
            let balance = try await chain.tezBalance(for: source.address)
            let unstaking = balance.unstakedFrozen + balance.unstakedFinalizable
            if balance.staked > 0 || unstaking > 0 { throw MoveAssetsError.staked(alias: source.alias, staked: balance.staked, unstaking: unstaking) }
            spendable = balance.spendable
        } catch ChainError.accountNotOnChain {
            spendable = 0
        }
        if spendable > 0, try await chain.delegateInfo(for: source.address).baker != nil { throw MoveAssetsError.baker(alias: source.alias) }
        let l1Holdings = try await Self.holdings(chain.portfolio(for: source.address), layer: network.name)
        var names: [TezosDomain] = []
        if network.tezosDomainsURL != nil {
            do { names = try await chain.tezosDomains(for: source.address) ?? [] } catch { throw MoveAssetsError.domainsUnknown(reason: error.localizedDescription) }
        }

        var layers: [MoveAssetsPlan.Layer] = []
        var notes: [String] = []
        if let layer = try await planLayer(1, name: network.name, network: network, chain: chain, source: source, to: destination.address, spendable: spendable,
                                           nfts: l1Holdings.nfts, tokens: l1Holdings.tokens, domains: names) {
            layers.append(layer)
        }

        // Layer 2, while it is on and the source can use it.
        if network.hasL2, source.address.isUsableOnEtherlink, let l2Network = network.layer2, let l2Chain = layer2Chain {
            let name = network.l2Name
            let l2Spendable = try await chain.etherlinkBalance(for: source.address)
            let portfolio = try await l2Chain.portfolio(for: source.address)
            let l2 = try Self.holdings(portfolio.onLayer2(), layer: name)
            if l2Spendable > 0 || !l2.nfts.isEmpty || !l2.tokens.isEmpty {
                if destination.address.isUsableOnEtherlink {
                    if let layer = try await planLayer(2, name: name, network: l2Network, chain: l2Chain, source: source, to: destination.address, spendable: l2Spendable, nfts: l2.nfts, tokens: l2.tokens) {
                        layers.append(layer)
                    }
                } else {
                    notes.append("Holdings on \(name) stay where they are: \(name) accepts only tz1, tz2 and tz3 accounts, and “\(destination.alias)” is a \(destination.address.value.prefix(3)).")
                }
            }
        }
        guard !layers.isEmpty else { throw MoveAssetsError.nothingToMove }
        // The account, network, node or directory may have changed while the nodes were asked.
        guard operationContext(for: source) == context else { throw WalletError.contextChanged }
        return MoveAssetsPlan(source: source, destination: destination, context: context, layers: layers, notes: notes)
    }

    /// Carries the plan out group by group, waiting for each block before the next (a pending
    /// operation blocks the account's next signing, S15). `progress` hears of each one done. A
    /// failure part way leaves what was done done; the error says nothing about the rest.
    func moveAssets(_ plan: MoveAssetsPlan, passphrase: String?, progress: @MainActor (MoveAssetsStep) -> Void) async throws {
        for layer in plan.layers {
            for (index, batch) in layer.batches.enumerated() {
                guard operationContext(for: plan.source) == plan.context, isListed(plan.source), isListed(plan.destination) else { throw WalletError.contextChanged }
                guard batch.request.isValid, batch.request.to == plan.destination.address,
                      batch.estimate.limits.operations.count == batch.request.operationCount else { throw ChainError.invalidTokenTransfer }
                guard let signer = try signingKey(for: plan.source, passphrase: passphrase) else { throw SendViewModel.SendError.noSecretKey }
                let sent = try await layer.chain.sendTokenTransfer(batch.request, from: plan.source, signer: signer, limits: batch.estimate.limits)
                let level: Int
                do {
                    level = try await layer.chain.waitForConfirmation(of: sent.hash)
                } catch where !sent.injected {
                    throw WalletError.outcomeUnknown(sent.hash)
                }
                progress(MoveAssetsStep(layer: layer.layer, index: index, hash: sent.hash, level: level, explorerURL: layer.network.explorerURL(operation: sent.hash)))
            }
        }
        await refreshAfterOperation()
    }

    // MARK: Planning

    private func isListed(_ wallet: Wallet) -> Bool {
        wallets.contains { $0.id == wallet.id && $0.address == wallet.address }
    }

    /// Every NFT and fungible token of a complete listing; an indexer that is off, unreachable
    /// or cut short is an error, since emptying the account would strand whatever was not listed.
    private static func holdings(_ portfolio: Portfolio, layer: String) throws -> (nfts: [NFT], tokens: [AssetBalance]) {
        switch portfolio.state {
        case .complete: return (portfolio.nfts, portfolio.tokens)
        case .partial(let fetched): throw MoveAssetsError.nftsUnknown(layer: layer, reason: "the indexer holds more than the \(fetched) read")
        case .unavailable(let reason): throw MoveAssetsError.nftsUnknown(layer: layer, reason: reason)
        }
    }

    /// One layer's groups: NFTs in groups of at most `maxTokens`, the tez sweep on the last.
    /// The sweep is priced with a 1 mutez placeholder (gas and storage do not depend on the
    /// amount), then the amount is the spendable tez less every group's fee and storage burn.
    /// `nil` when the layer holds nothing to move.
    private func planLayer(_ layer: Int, name: String, network: Network, chain: any ChainService, source: Wallet, to destination: Address, spendable: Decimal,
                           nfts: [NFT], tokens: [AssetBalance] = [], domains: [TezosDomain] = []) async throws -> MoveAssetsPlan.Layer? {
        let movable = nfts.filter { $0.isTransferable && $0.balance >= 1 }
        let leftBehind = nfts.filter { !$0.isTransferable }
        let tokenTransfers = tokens.compactMap { token -> (AssetBalance, TokenTransfer)? in
            guard let raw = token.rawAmount, raw != "0", let transfer = TokenTransfer(token: token, rawAmount: raw), transfer.isValid else { return nil }
            return (token, transfer)
        }
        let movedTokens = tokenTransfers.map(\.0)
        let tokensLeft = tokens.filter { token in token.rawAmount != "0" && !movedTokens.contains(token) }
        // Names the account owns, each handed over and pointed at the destination: the record
        // updates must run while the account still owns them, so they all go in the first group.
        let domainParts = domains.compactMap { domain in domain.transferParts(from: source.address, to: destination, pointAtRecipient: true).map { (domain, $0) } }
        let movedDomains = domainParts.map(\.0)
        let domainsLeft = domains.filter { !movedDomains.contains($0) }
        let records = domainParts.flatMap(\.1.records)
        let transfers = tokenTransfers.map(\.1) + domainParts.flatMap(\.1.transfers) + movable.map { TokenTransfer(nft: $0, amount: NSDecimalNumber(decimal: $0.balance).intValue) }
        var chunks = stride(from: 0, to: transfers.count, by: TokenTransferRequest.maxTokens).map { Array(transfers[$0..<min($0 + TokenTransferRequest.maxTokens, transfers.count)]) }
        if chunks.isEmpty { chunks = [[]] }
        let spendableMutez = Int64(Mutez.fromTez(spendable)) ?? 0
        guard spendableMutez > 0 || !transfers.isEmpty || !records.isEmpty else { return nil }
        func request(_ index: Int, tez: String? = nil) -> TokenTransferRequest {
            TokenTransferRequest(to: destination, transfers: chunks[index], tezMutez: tez, records: index == 0 ? records : [])
        }

        var batches: [MoveAssetsPlan.Batch] = []
        for index in chunks.indices.dropLast() {
            let request = request(index)
            batches.append(.init(request: request, estimate: try await chain.estimateTokenTransfer(request, from: source)))
        }
        let lastIndex = chunks.count - 1
        var tez: Decimal = 0
        if spendableMutez > 0 {
            let priced = try await chain.estimateTokenTransfer(request(lastIndex, tez: "1"), from: source)
            let cost = batches.reduce(Decimal(0)) { $0 + $1.estimate.total } + priced.total
            let amount = spendableMutez - (Int64(Mutez.fromTez(cost)) ?? .max)
            if amount > 0 {
                batches.append(.init(request: request(lastIndex, tez: String(amount)), estimate: priced))
                tez = Decimal(amount) / Mutez.perTez
            }
        }
        if tez == 0, !chunks[lastIndex].isEmpty || (lastIndex == 0 && !records.isEmpty) {
            let request = request(lastIndex)
            batches.append(.init(request: request, estimate: try await chain.estimateTokenTransfer(request, from: source)))
        }
        guard !batches.isEmpty else { return nil }
        let plan = MoveAssetsPlan.Layer(layer: layer, name: name, network: network, chain: chain, balance: spendable, tez: tez, nfts: movable, leftBehind: leftBehind,
                                        tokens: movedTokens, tokensLeftBehind: tokensLeft, domains: movedDomains, domainsLeftBehind: domainsLeft, batches: batches)
        guard plan.cost + tez <= spendable else { throw MoveAssetsError.cannotPayFees(layer: name) }
        return plan
    }
}
