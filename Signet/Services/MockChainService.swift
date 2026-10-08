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
        return TransferEstimate(fee: Decimal(string: "0.000521")!, burn: burn, total: amount + Decimal(string: "0.000521")! + burn, gasLimit: 169, storageLimit: burn > 0 ? 257 : 0)
    }

    func sendTransfer(from wallet: Wallet, signer: SigningKey, to destination: Address, amount: Decimal) async throws -> String {
        if wallet.keyKind == .encrypted, case .secret(_, let passphrase) = signer, passphrase != "correct horse" { throw ChainError.wrongPassphrase }
        return "ooMockOperationHash1111111111111111111111111111111111"
    }

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
        TransferEstimate(fee: Decimal(string: "0.000421")!, burn: 0, total: Decimal(string: "0.000421")!, gasLimit: 200, storageLimit: 0)
    }

    func performStaking(_ operation: StakingOperation, from wallet: Wallet, signer: SigningKey) async throws -> String {
        if wallet.keyKind == .encrypted, case .secret(_, let passphrase) = signer, passphrase != "correct horse" { throw ChainError.wrongPassphrase }
        return "ooMockStaking\(operation.bridgeKind)"
    }

    func proofOfPossession(signer: SigningKey) async throws -> String { "BLsigMockProof" }

    func signPayload(signer: SigningKey, payloadHex: String) async throws -> SignedPayload {
        if case .secret(_, let passphrase) = signer, passphrase == "wrong" { throw ChainError.wrongPassphrase }
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
        if wallet.keyKind == .encrypted, case .secret(_, let passphrase) = signer, passphrase != "correct horse" { throw ChainError.wrongPassphrase }
        return "ooMockGovernance\(operation.bridgeKind)"
    }
}
