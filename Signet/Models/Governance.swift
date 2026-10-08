import Foundation

/// The five phases of a Tezos voting cycle, in order.
enum VotingPeriodKind: String, Codable, Sendable, CaseIterable {
    case proposal, exploration, cooldown, promotion, adoption

    var title: String {
        switch self {
        case .proposal: "Proposal period"
        case .exploration: "Exploration vote"
        case .cooldown: "Cooldown period"
        case .promotion: "Promotion vote"
        case .adoption: "Adoption period"
        }
    }

    /// Bakers can act: upvote in the proposal period, cast a ballot in the two votes.
    var acceptsUpvotes: Bool { self == .proposal }
    var acceptsBallots: Bool { self == .exploration || self == .promotion }
}

enum BallotVote: String, Codable, Sendable, CaseIterable, Identifiable {
    case yay, nay, pass
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

/// What the chain says about the current voting period and this baker's standing in it.
struct GovernanceInfo: Equatable, Sendable {
    struct Proposal: Equatable, Sendable, Identifiable {
        let hash: String
        /// Voting power behind the proposal so far.
        let votingPower: Decimal
        var id: String { hash }
    }

    struct Ballots: Equatable, Sendable {
        var yay: Decimal = 0
        var nay: Decimal = 0
        var pass: Decimal = 0
        var total: Decimal { yay + nay + pass }
    }

    var kind: VotingPeriodKind?
    var index: Int?
    /// Blocks into the period, and blocks left.
    var position: Int?
    var remaining: Int?
    var proposals: [Proposal] = []
    var currentProposal: String?
    /// Our voting power if we are in the listings, else `nil` (no vote this period).
    var votingPower: Decimal?
    var totalVotingPower: Decimal = 0
    var quorumPerTenThousand: Int?
    var ballots = Ballots()
    /// How we voted already in this period, if we have.
    var myBallot: BallotVote?
    /// Proposals we have upvoted so far in this period (the protocol allows 20).
    var proposalCount = 0

    static let maximumUpvotesPerPeriod = 20

    var canVote: Bool { votingPower != nil }
    /// Fraction of total voting power behind `power`.
    func share(of power: Decimal) -> Double {
        guard totalVotingPower > 0 else { return 0 }
        return (power / totalVotingPower as NSDecimalNumber).doubleValue
    }
}

/// A voting operation. Neither kind carries a fee.
enum GovernanceOperation: Equatable, Sendable {
    /// Upvote proposals in the proposal period (one `proposals` operation, up to 20 hashes).
    case upvote([String])
    /// Cast a ballot in an exploration or promotion vote.
    case ballot(proposal: String, vote: BallotVote)

    var title: String {
        switch self {
        case .upvote(let hashes): hashes.count == 1 ? "Upvote proposal" : "Upvote \(hashes.count) proposals"
        case .ballot(_, let vote): "Vote \(vote.title)"
        }
    }

    var bridgeKind: String {
        switch self {
        case .upvote: "proposals"
        case .ballot: "ballot"
        }
    }

    var bridgeArgument: [String: Any] {
        switch self {
        case .upvote(let hashes): ["proposals": hashes]
        case .ballot(let proposal, let vote): ["proposal": proposal, "ballot": vote.rawValue]
        }
    }

    /// Protocol hashes are base58check `P…` of 51 characters: 2-byte prefix plus a 32-byte hash.
    static func isProposalHash(_ text: String) -> Bool {
        guard text.count == 51, text.hasPrefix("P"), let body = Base58.checkDecode(text) else { return false }
        return body.count == 2 + 32
    }
}
