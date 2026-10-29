import Foundation

/// Etherlink's on-chain governance: bakers propose and upvote kernel upgrades in a Proposal
/// period and vote Yea / Nay / Pass on the winner in the Promotion period that follows, in
/// layer 1 contracts (one for slow upgrades, one for fast ones) written by Baking Bad
/// (github.com/baking-bad/etherlink-governance). Calls carry an ordinary fee, unlike layer 1
/// ballots. A baker may name another account as its voting key through the delegation
/// contract named in each governance contract's storage; the governance contract then counts
/// that baker's power for the voting key (`list_voters`).
enum EtherlinkGovernance {
    /// The two kernel upgrade tracks, each with its own contract and period length.
    enum Process: String, CaseIterable, Identifiable, Sendable, Codable {
        case slow, fast
        var id: String { rawValue }

        var title: String {
            switch self {
            case .slow: "Slow kernel upgrades"
            case .fast: "Fast kernel upgrades"
            }
        }

        /// The field's label in the Networks sheet.
        var settingTitle: String {
            switch self {
            case .slow: "Slow governance"
            case .fast: "Fast governance"
            }
        }
    }

    /// A promotion ballot, as the contract's `vote` entrypoint spells it.
    enum Vote: String, CaseIterable, Identifiable, Sendable {
        case yea, nay, pass
        var id: String { rawValue }
        var title: String { rawValue.capitalized }
    }

    enum PeriodKind: String, Sendable {
        case proposal, promotion

        var title: String {
            switch self {
            case .proposal: "Proposal period"
            case .promotion: "Promotion period"
            }
        }
    }

    /// A kernel proposed in the current proposal period.
    struct Proposal: Identifiable, Equatable, Sendable {
        /// The kernel root hash, `0x` and 66 hex digits.
        let hash: String
        let proposers: [Address]
        /// Voting power behind it so far.
        let upvotes: Decimal
        /// Whether the selected account upvoted it already.
        var upvoted = false
        var id: String { hash }
    }

    /// The contract's thresholds, each a share of `scale` (100 for percent).
    struct Config: Equatable, Sendable {
        var periodLength = 0
        var upvotingLimit = 20
        var scale = 100
        var proposalQuorum = 0
        var promotionQuorum = 0
        var promotionSupermajority = 0

        func fraction(_ value: Int) -> Double { scale > 0 ? Double(value) / Double(scale) : 0 }
    }

    struct Tallies: Equatable, Sendable {
        var yea: Decimal = 0
        var nay: Decimal = 0
        var pass: Decimal = 0
        var total: Decimal { yea + nay + pass }
    }

    /// The current period of one governance contract and where the selected account stands in it.
    struct State: Equatable, Sendable {
        var contract: Address
        var periodIndex = 0
        var periodKind: PeriodKind = .proposal
        /// Layer 1 blocks until the period ends.
        var remainingBlocks = 0
        var config = Config()
        /// All bakers' voting power as the contract counted it when the period opened.
        var totalVotingPower: Decimal = 0
        /// Proposal period: the kernels proposed so far, most upvoted first.
        var proposals: [Proposal] = []
        /// False when the proposal list could not be read (no indexer), so only a typed hash can be upvoted.
        var proposalsKnown = true
        /// Promotion period: the kernel being voted on.
        var candidate: String?
        var tallies = Tallies()
        /// The account's own voting power plus that of the bakers it votes for; 0 when it cannot vote.
        var votingPower: Decimal = 0
        /// Bakers whose voting key the account is, on this contract.
        var votesFor: [Address] = []
        /// Proposals the account has submitted or upvoted in this period, of `config.upvotingLimit`.
        var upvotesUsed = 0
        var myVote: Vote?

        var canVote: Bool { votingPower > 0 }

        /// Fraction of total voting power behind `power`.
        func share(of power: Decimal) -> Double {
            guard totalVotingPower > 0 else { return 0 }
            return (power / totalVotingPower as NSDecimalNumber).doubleValue
        }
    }

    /// One call to a governance contract.
    enum Operation: Equatable, Sendable {
        case newProposal(hash: String)
        case upvote(hash: String)
        case vote(Vote)

        var title: String {
            switch self {
            case .newProposal: "Propose kernel"
            case .upvote: "Upvote proposal"
            case .vote(let vote): "Vote \(vote.title)"
            }
        }

        var entrypoint: String {
            switch self {
            case .newProposal: "new_proposal"
            case .upvote: "upvote_proposal"
            case .vote: "vote"
            }
        }

        /// The entrypoint's argument as the bridge takes it: the hash's hex (no `0x`) or the vote word.
        var payload: String {
            switch self {
            case .newProposal(let hash), .upvote(let hash): String(hash.dropFirst(2))
            case .vote(let vote): vote.rawValue
            }
        }

        var kernelHash: String? {
            switch self {
            case .newProposal(let hash), .upvote(let hash): hash
            case .vote: nil
            }
        }
    }

    /// A kernel root hash is 33 bytes: `0x` and 66 hex digits (the contract checks the length).
    static let kernelHashBytes = 33

    /// `text` as a kernel hash the contract accepts (lowercase, with `0x`), or `nil`.
    static func kernelHash(from text: String) -> String? {
        var hex = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if hex.hasPrefix("0x") { hex.removeFirst(2) }
        guard hex.count == kernelHashBytes * 2, hex.allSatisfy(\.isHexDigit) else { return nil }
        return "0x" + hex
    }

    static func isKernelHash(_ text: String) -> Bool { kernelHash(from: text) != nil }

    /// Governance contract addresses are KT1s.
    static func contractAddress(from text: String) -> Address? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let address = Address(trimmed)
        return address.isContract && address.isValidAccount ? address : nil
    }

    /// Where proposals are described and discussed.
    static let siteURL = URL(string: "https://governance.etherlink.com")!
}
