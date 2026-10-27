import Foundation

/// Static data matching the sketch in spec/EXAMPLE.png. Used for previews and tests.
struct MockChainService: ChainService {
    static let captainStake = Address("tz1dCaMnnMJk76UodjewCK67ABiXWjcKj73N")

    func tezBalance(for address: Address) async throws -> TezBalance {
        TezBalance(spendable: Decimal(string: "1361.43")!, staked: 3000)
    }

    func etherlinkBalance(for address: Address) async throws -> Decimal {
        Decimal(string: "5432.1")!
    }

    func tokenBalances(for address: Address) async throws -> [AssetBalance] {
        guard address == Self.captainStake else { return [] }
        return [
            AssetBalance(id: "KT1FfjhvJZppBFQuUzNAdFPR1Z2jpD4XiXrF:0", kind: .token(contract: "KT1FfjhvJZppBFQuUzNAdFPR1Z2jpD4XiXrF", tokenId: "0"), name: "Aubergine", symbol: "GINE", amount: 30_000, standard: "fa2"),
            AssetBalance(id: "KT1MZg99PxMDEENwB4Fi64xkqAVh5d1rv8Z9:0", kind: .token(contract: "KT1MZg99PxMDEENwB4Fi64xkqAVh5d1rv8Z9", tokenId: "0"), name: "Tezos Pepe", symbol: "PEPE", amount: 5_000, standard: "fa2"),
            AssetBalance(id: "KT1VaEsVNiBoA56eToEK6n6BcPgh1tdx9eXi:0", kind: .token(contract: "KT1VaEsVNiBoA56eToEK6n6BcPgh1tdx9eXi", tokenId: "0"), name: "Temple Key", symbol: "TKEY", amount: Decimal(string: "1.047540545999871429")!, standard: "fa2"),
        ]
    }

    func domains(for address: Address) async throws -> [String] {
        address == Self.captainStake ? ["captstake.tez"] : ["mytez.tez"]
    }

    func nfts(for address: Address) async throws -> [NFT] {
        (1...6).map { NFT(id: "mock:\($0)", contract: "KT1mock", tokenId: "\($0)", name: "NFT \($0)", balance: 1, thumbnailURL: nil) }
    }

    func recentTransactions(for address: Address, limit: Int) async throws -> [TezosTransaction] {
        let now = Date()
        return [
            TezosTransaction(id: "1", hash: "ooAAA111", level: 9_000_010, timestamp: now.addingTimeInterval(-3_600), kind: .transaction, direction: .incoming,
                             counterparty: Self.captainStake, counterpartyAlias: "Captain Stake", amount: 12.5, fee: 0, entrypoint: nil, isApplied: true),
            TezosTransaction(id: "2", hash: "ooBBB222", level: 9_000_000, timestamp: now.addingTimeInterval(-86_400), kind: .transaction, direction: .outgoing,
                             counterparty: Address("KT1RJ6PbjHpwc3M5rw5s2Nbmefwbuwbdxton"), counterpartyAlias: "objkt.com Marketplace", amount: 0, fee: 0.000521, entrypoint: "collect", isApplied: true),
            TezosTransaction(id: "3", hash: "ooCCC333", level: 8_999_000, timestamp: now.addingTimeInterval(-3 * 86_400), kind: .delegation, direction: .outgoing,
                             counterparty: Self.captainStake, counterpartyAlias: "Captain Stake", amount: 0, fee: 0.0003, entrypoint: nil, isApplied: true),
            TezosTransaction(id: "4", hash: "ooDDD444", level: 8_990_000, timestamp: now.addingTimeInterval(-9 * 86_400), kind: .transaction, direction: .outgoing,
                             counterparty: Address("tz2BFTyPeYRzxd5aiBchbXN3WCZhx7BqbMBq"), counterpartyAlias: nil, amount: 3, fee: 0.0004, entrypoint: nil, isApplied: false),
        ]
    }

    func resolveDomain(_ name: String) async throws -> Address? {
        name.lowercased() == "captstake.tez" ? Self.captainStake : nil
    }

    func accountProfile(for address: Address) async throws -> AccountProfile? {
        address == Self.captainStake ? AccountProfile(name: "Captain Stake", twitter: "captstake", description: "Truth, Justice, Staking.") : nil
    }

    func estimateTransfer(from wallet: Wallet, to destination: Address, amount: Decimal) async throws -> TransferEstimate {
        let burn: Decimal = destination == Self.captainStake ? 0 : Decimal(string: "0.06425")!
        return TransferEstimate(fee: Decimal(string: "0.000521")!, burn: burn, total: amount + Decimal(string: "0.000521")! + burn, gasLimit: 169, storageLimit: burn > 0 ? 257 : 0,
                                limits: OperationLimits(feeMutez: "521", gasLimit: 169, storageLimit: burn > 0 ? 257 : 0))
    }

    func sendTransfer(from wallet: Wallet, signer: SigningKey, to destination: Address, amount: Decimal, limits: OperationLimits) async throws -> SentOperation {
        if wallet.keyKind == .encrypted, case .secret(_, let passphrase, _) = signer, passphrase != "correct horse" { throw ChainError.wrongPassphrase }
        return SentOperation(hash: "ooMockOperationHash1111111111111111111111111111111111", signedBytes: "ab")
    }

    func rebroadcast(_ sent: SentOperation) async throws -> SentOperation { SentOperation(hash: sent.hash, signedBytes: sent.signedBytes) }

    func waitForConfirmation(of operationHash: String) async throws -> Int {
        9_000_000
    }

    func delegateInfo(for address: Address) async throws -> DelegateInfo {
        if address == Self.captainStake {
            return DelegateInfo(delegate: address, baker: .init(deactivated: false, gracePeriod: 1379, consensusKey: Address("tz4E128TU3t1TdLCJEY4oHg8gZzZNoNBknwh"), pendingConsensusKeys: [], companionKey: nil, pendingCompanionKeys: [], stakingParameters: StakingParameters(limitMillionth: 9_000_000, edgeBillionth: 10_000_000), pendingStakingParameters: []), delegateAcceptsStaking: true)
        }
        return DelegateInfo(delegate: Self.captainStake, baker: nil, delegateAcceptsStaking: true)
    }

    func bakers(limit: Int) async throws -> [BakerCandidate] {
        [BakerCandidate(address: Self.captainStake, alias: "Captain Stake", stakingBalance: 136_876, delegators: 38, stakers: 15, acceptsStaking: true),
         BakerCandidate(address: Address("tz3cqThj23Feu55KDynm7Vg81mCMpWDgzQZq"), alias: "Tezos Foundation Baker 1", stakingBalance: 24_666_552, delegators: 18, stakers: 4, acceptsStaking: true)]
    }

    func estimateStaking(_ operation: StakingOperation, from wallet: Wallet) async throws -> TransferEstimate {
        TransferEstimate(fee: Decimal(string: "0.000421")!, burn: 0, total: Decimal(string: "0.000421")!, gasLimit: 200, storageLimit: 0,
                         limits: OperationLimits(feeMutez: "421", gasLimit: 200, storageLimit: 0))
    }

    func estimateEtherlinkDeposit(from wallet: Wallet, amount: Decimal) async throws -> TransferEstimate {
        TransferEstimate(fee: Decimal(string: "0.001234")!, burn: 0, total: amount + Decimal(string: "0.001234")!, gasLimit: 3000, storageLimit: 0,
                         limits: OperationLimits(feeMutez: "1234", gasLimit: 3000, storageLimit: 0))
    }

    func sendEtherlinkDeposit(from wallet: Wallet, signer: SigningKey, amount: Decimal, limits: OperationLimits) async throws -> SentOperation {
        if wallet.keyKind == .encrypted, case .secret(_, let passphrase, _) = signer, passphrase != "correct horse" { throw ChainError.wrongPassphrase }
        return SentOperation(hash: "ooMockDeposit")
    }

    func estimateShieldDeposit(from wallet: Wallet, deposit: ShieldDeposit) async throws -> TransferEstimate {
        TransferEstimate(fee: 0.000654, burn: 0, total: deposit.amount + 0.000654, gasLimit: 3000, storageLimit: 0, limits: OperationLimits(feeMutez: "654", gasLimit: 3000, storageLimit: 0))
    }

    func sendShieldDeposit(from wallet: Wallet, signer: SigningKey, deposit: ShieldDeposit, limits: OperationLimits) async throws -> SentOperation {
        if wallet.keyKind == .encrypted, case .secret(_, let passphrase, _) = signer, passphrase != "correct horse" { throw ChainError.wrongPassphrase }
        return SentOperation(hash: "ooMockShieldDeposit")
    }

    func estimateOutboxExecution(from wallet: Wallet, execution: OutboxExecution) async throws -> TransferEstimate {
        TransferEstimate(fee: 0.001234, burn: 0, total: 0.001234, gasLimit: 6000, storageLimit: 0, limits: OperationLimits(feeMutez: "1234", gasLimit: 6000, storageLimit: 0))
    }

    func sendOutboxExecution(from wallet: Wallet, signer: SigningKey, execution: OutboxExecution, limits: OperationLimits) async throws -> SentOperation {
        if wallet.keyKind == .encrypted, case .secret(_, let passphrase, _) = signer, passphrase != "correct horse" { throw ChainError.wrongPassphrase }
        return SentOperation(hash: "ooMockOutbox")
    }

    /// Accounts linked so far in this process; a link call adds the sender.
    nonisolated(unsafe) static var linkedAliases: Set<Address> = []

    func etherlinkAliasStatus(for address: Address) async throws -> EtherlinkAliasStatus {
        let alias = EtherlinkAlias.address(for: address)
        return Self.linkedAliases.contains(address) ? .linked(evmAddress: alias) : .unlinked(evmAddress: alias)
    }

    func estimateEtherlinkLink(from wallet: Wallet) async throws -> TransferEstimate {
        TransferEstimate(fee: Decimal(string: "0.001291")!, burn: 0, total: Decimal(string: "0.001291")!, gasLimit: 2000, storageLimit: 0,
                         limits: OperationLimits(feeMutez: "1291", gasLimit: 2000, storageLimit: 0))
    }

    func sendEtherlinkLink(from wallet: Wallet, signer: SigningKey, limits: OperationLimits) async throws -> SentOperation {
        if wallet.keyKind == .encrypted, case .secret(_, let passphrase, _) = signer, passphrase != "correct horse" { throw ChainError.wrongPassphrase }
        Self.linkedAliases.insert(wallet.address)
        return SentOperation(hash: "ooMockLink")
    }

    func performStaking(_ operation: StakingOperation, from wallet: Wallet, signer: SigningKey, limits: OperationLimits) async throws -> SentOperation {
        if wallet.keyKind == .encrypted, case .secret(_, let passphrase, _) = signer, passphrase != "correct horse" { throw ChainError.wrongPassphrase }
        return SentOperation(hash: "ooMockStaking\(operation.bridgeKind)")
    }

    func proofOfPossession(signer: SigningKey) async throws -> String { "BLsigMockProof" }

    func signPayload(signer: SigningKey, payloadHex: String) async throws -> SignedPayload {
        if case .secret(_, let passphrase, _) = signer, passphrase == "wrong" { throw ChainError.wrongPassphrase }
        return SignedPayload(publicKey: "edpkMock", signature: "edsigMock\(payloadHex.suffix(8))")
    }

    func governanceInfo(for address: Address) async throws -> GovernanceInfo {
        var info = GovernanceInfo(kind: .proposal, index: 184, position: 16754, remaining: 184845)
        info.proposals = [GovernanceInfo.Proposal(hash: "PtSeouLouXkxhg39oWzjxDWaCydNfR3RxCUrNe4Q9Ro8BTehcbh", votingPower: 123_456_789_000)]
        info.votingPower = address == Self.captainStake ? 1_234_567_000 : nil
        info.totalVotingPower = 600_000_000_000_000
        info.quorumPerTenThousand = 5500
        return info
    }

    func performGovernance(_ operation: GovernanceOperation, from wallet: Wallet, signer: SigningKey) async throws -> String {
        if wallet.keyKind == .encrypted, case .secret(_, let passphrase, _) = signer, passphrase != "correct horse" { throw ChainError.wrongPassphrase }
        return "ooMockGovernance\(operation.bridgeKind)"
    }

    /// The sample account votes for Captain Stake on Etherlink; nobody else is a voting key.
    static let etherlinkVotingKey = Address("tz1VSUr8wwNhLAzempoch5d6hLRiTh8Cjcjb")
    static let mockKernelHash = "0x009e07373751a43acbf0cd747b404f45130e0ad561c4b7da937e02eb812bd0f7e8"

    func etherlinkVotingRights(for address: Address, contract: Address) async throws -> [Address] {
        address == Self.etherlinkVotingKey ? [Self.captainStake] : []
    }

    func etherlinkGovernanceState(contract: Address, for address: Address) async throws -> EtherlinkGovernance.State {
        var state = EtherlinkGovernance.State(contract: contract)
        state.periodIndex = 816
        state.remainingBlocks = 3780
        state.config = EtherlinkGovernance.Config(periodLength: 4800, upvotingLimit: 20, scale: 100, proposalQuorum: 5, promotionQuorum: 15, promotionSupermajority: 80)
        state.totalVotingPower = 654_433_650_040_589
        state.proposals = [EtherlinkGovernance.Proposal(hash: Self.mockKernelHash, proposers: [Self.captainStake], upvotes: 215_727_025_713_721)]
        state.votesFor = try await etherlinkVotingRights(for: address, contract: contract)
        state.votingPower = address == Self.captainStake || !state.votesFor.isEmpty ? 1_234_567_000 : 0
        return state
    }

    func estimateEtherlinkGovernance(_ operation: EtherlinkGovernance.Operation, contract: Address, from wallet: Wallet) async throws -> TransferEstimate {
        TransferEstimate(fee: Decimal(string: "0.001845")!, burn: 0, total: Decimal(string: "0.001845")!, gasLimit: 4200, storageLimit: 0,
                         limits: OperationLimits(feeMutez: "1845", gasLimit: 4200, storageLimit: 0))
    }

    func sendEtherlinkGovernance(_ operation: EtherlinkGovernance.Operation, contract: Address, from wallet: Wallet, signer: SigningKey, limits: OperationLimits) async throws -> SentOperation {
        if wallet.keyKind == .encrypted, case .secret(_, let passphrase, _) = signer, passphrase != "correct horse" { throw ChainError.wrongPassphrase }
        return SentOperation(hash: "ooMockEtherlink\(operation.entrypoint)")
    }
}
