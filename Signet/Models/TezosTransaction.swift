import Foundation

/// One line of account history, as the indexer reports it.
struct TezosTransaction: Identifiable, Hashable, Sendable {
    enum Kind: String, Sendable { case transaction, delegation, origination, other }
    enum Direction: Sendable { case incoming, outgoing, selfTransfer }

    let id: String
    let hash: String
    let level: Int
    let timestamp: Date
    let kind: Kind
    let direction: Direction
    /// The other party: recipient for outgoing, sender for incoming, new baker for delegations.
    let counterparty: Address?
    /// Name the indexer knows for the counterparty (TzProfiles / known accounts), if any.
    let counterpartyAlias: String?
    /// Whole tez moved by this operation (0 for contract calls without a transfer).
    let amount: Decimal
    /// Baker fee paid, in tez; only meaningful for outgoing operations.
    let fee: Decimal
    /// Entrypoint for contract calls.
    let entrypoint: String?
    let isApplied: Bool
    /// Delegations only: where the delegator was pointing before.
    var previousDelegate: Address? = nil
    /// Delegations only: the delegator's balance at the time (what moved in or out of our stake).
    var delegatedBalance: Decimal? = nil

    /// What a delegation row means from our point of view.
    enum DelegationRole: Sendable { case weDelegated, weUndelegated, delegatorJoined, delegatorLeft, delegatorMoved }

    func delegationRole(for us: Address) -> DelegationRole? {
        guard kind == .delegation else { return nil }
        if direction != .incoming { return counterparty == nil ? .weUndelegated : .weDelegated }
        if newDelegateIsUs { return .delegatorJoined }
        return previousDelegate == us && newDelegate != nil ? .delegatorMoved : .delegatorLeft
    }

    /// Delegations only: the baker the delegator now points at (nil when they undelegated).
    var newDelegate: Address? = nil
    private var newDelegateIsUs: Bool { newDelegate != nil && newDelegate == delegationTarget }
    /// Our own address, recorded at parse time so roles can be derived without more context.
    var delegationTarget: Address? = nil

    var isContractCall: Bool { counterparty?.isContract == true }
}
