import Foundation

/// Where an account's delegation stands, plus its baker record if it is one.
struct DelegateInfo: Hashable, Sendable {
    struct Baker: Hashable, Sendable {
        let deactivated: Bool
        let gracePeriod: Int?
        let consensusKey: Address?
        let pendingConsensusKeys: [Address]
        let companionKey: Address?
        let pendingCompanionKeys: [Address]
        var stakingParameters: StakingParameters? = nil
        var pendingStakingParameters: [StakingParameters] = []
    }

    let delegate: Address?
    let baker: Baker?
    /// Whether the current delegate accepts staked tez (limit of staking over baking > 0). nil if unknown.
    let delegateAcceptsStaking: Bool?

    var isBaker: Bool { baker != nil }
    var isSelfDelegated: Bool { baker != nil }
}

/// A baker's staking parameters, as the protocol stores them.
struct StakingParameters: Hashable, Sendable {
    /// Max staked tez accepted from others, as a multiple of the baker's own stake, in millionths (9_000_000 = 9×).
    let limitMillionth: Int
    /// Share of stakers' rewards kept by the baker, in billionths (1_000_000_000 = 100 %).
    let edgeBillionth: Int
    /// Cycle a pending change takes effect; nil for the active set.
    var cycle: Int? = nil

    var limitMultiplier: Decimal { Decimal(limitMillionth) / 1_000_000 }
    var edgePercent: Decimal { Decimal(edgeBillionth) / 10_000_000 }

    init(limitMillionth: Int, edgeBillionth: Int, cycle: Int? = nil) {
        self.limitMillionth = limitMillionth
        self.edgeBillionth = edgeBillionth
        self.cycle = cycle
    }

    /// From user-facing numbers: a multiple (0–9) and a percentage (0–100).
    init?(limitMultiplier: Decimal, edgePercent: Decimal) {
        guard limitMultiplier >= 0, limitMultiplier <= 9, edgePercent >= 0, edgePercent <= 100 else { return nil }
        self.init(limitMillionth: NSDecimalNumber(decimal: limitMultiplier * 1_000_000).intValue,
                  edgeBillionth: NSDecimalNumber(decimal: edgePercent * 10_000_000).intValue)
    }
}

/// A baker offered in the delegate picker.
struct BakerCandidate: Identifiable, Hashable, Sendable {
    let address: Address
    let alias: String?
    let stakingBalance: Decimal
    let delegators: Int
    let stakers: Int
    /// nil when the indexer does not say.
    let acceptsStaking: Bool?

    var id: String { address.value }
}

/// Operations in the staking and baking family.
enum StakingOperation: Hashable, Sendable {
    case delegate(to: Address?)                  // nil = remove delegation
    case registerAsBaker
    case stake(Decimal)
    case unstake(Decimal)
    case finalizeUnstake
    /// `proof` is required for tz4 (BLS) keys.
    case updateConsensusKey(publicKey: String, proof: String?)
    case updateCompanionKey(publicKey: String, proof: String?)
    /// Needs the baker's own address because it is a transaction to self.
    case setStakingParameters(StakingParameters, source: Address)

    var bridgeKind: String {
        switch self {
        case .delegate: "setDelegate"
        case .registerAsBaker: "registerDelegate"
        case .stake: "stake"
        case .unstake: "unstake"
        case .finalizeUnstake: "finalizeUnstake"
        case .updateConsensusKey: "updateConsensusKey"
        case .updateCompanionKey: "updateCompanionKey"
        case .setStakingParameters: "setDelegateParameters"
        }
    }

    var bridgeArgument: [String: Any] {
        switch self {
        case .delegate(let to): ["delegate": to?.value ?? ""]
        case .registerAsBaker, .finalizeUnstake: [:]
        case .stake(let amount), .unstake(let amount): ["amountMutez": Mutez.fromTez(amount)]
        case .updateConsensusKey(let pk, let proof), .updateCompanionKey(let pk, let proof):
            ["pk": pk, "proof": proof ?? ""].filter { !$0.value.isEmpty }
        case .setStakingParameters(let p, let source):
            ["limitMillionth": p.limitMillionth, "edgeBillionth": p.edgeBillionth, "source": source.value]
        }
    }

    var title: String {
        switch self {
        case .delegate(let to): to == nil ? "Remove delegation" : "Delegate"
        case .registerAsBaker: "Register as a baker"
        case .stake: "Stake"
        case .unstake: "Unstake"
        case .finalizeUnstake: "Finalize unstaked tez"
        case .updateConsensusKey: "Set consensus key"
        case .updateCompanionKey: "Set companion key"
        case .setStakingParameters: "Set staking parameters"
        }
    }
}
