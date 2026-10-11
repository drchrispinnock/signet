import Foundation

/// Everything the UI needs from the chain and indexers, behind one protocol so views can be
/// driven by mock data until the Taquito bridge is in place.
protocol ChainService: Sendable {
    func tezBalance(for address: Address) async throws -> TezBalance
    func etherlinkBalance(for address: Address) async throws -> Decimal
    func tokenBalances(for address: Address) async throws -> [AssetBalance]
    func domains(for address: Address) async throws -> [String]
    func nfts(for address: Address) async throws -> [NFT]
    /// Tokens and NFTs from one indexer snapshot, with whether it is complete (S26).
    func portfolio(for address: Address) async throws -> Portfolio
    /// Most recent operations touching the address, newest first.
    func recentTransactions(for address: Address, limit: Int) async throws -> [TezosTransaction]

    /// Forward Tezos Domains lookup: `name.tez` → address, or `nil` if unregistered.
    func resolveDomain(_ name: String) async throws -> Address?
    /// Indexer-known identity for an address (TzProfiles via TzKT), or `nil`.
    func accountProfile(for address: Address) async throws -> AccountProfile?

    /// Cost of a transfer, computed without any secret key, with the limits to send it under.
    func estimateTransfer(from wallet: Wallet, to destination: Address, amount: Decimal) async throws -> TransferEstimate
    /// Signs and injects a transfer with exactly the approved `limits` (S14).
    func sendTransfer(from wallet: Wallet, signer: SigningKey, to destination: Address, amount: Decimal, limits: OperationLimits) async throws -> SentOperation
    /// Sends the same signed bytes again after an unknown outcome; the hash cannot change (S15).
    func rebroadcast(_ sent: SentOperation) async throws -> SentOperation
    /// Waits for the operation to be included. Returns the block level.
    func waitForConfirmation(of operationHash: String) async throws -> Int

    // Delegation, staking and baking.
    func delegateInfo(for address: Address) async throws -> DelegateInfo
    /// Bakers to offer in the picker, most popular first.
    func bakers(limit: Int) async throws -> [BakerCandidate]
    func estimateStaking(_ operation: StakingOperation, from wallet: Wallet) async throws -> TransferEstimate
    /// Signs and injects a staking-family operation with exactly the approved `limits` (S14).
    func performStaking(_ operation: StakingOperation, from wallet: Wallet, signer: SigningKey, limits: OperationLimits) async throws -> SentOperation
    /// BLS proof of possession for one of our tz4 keys.
    func proofOfPossession(signer: SigningKey) async throws -> String

    /// Signs raw bytes (hex) with no watermark, e.g. a packed "Tezos Signed Message". Returns the
    /// signer's public key and the prefixed signature (edsig/spsig/p2sig…).
    func signPayload(signer: SigningKey, payloadHex: String) async throws -> SignedPayload

    // Governance.
    func governanceInfo(for address: Address) async throws -> GovernanceInfo
    /// Injects an upvote or ballot. Returns the operation hash.
    func performGovernance(_ operation: GovernanceOperation, from wallet: Wallet, signer: SigningKey) async throws -> String
}

/// Everything the indexer knows the account holds, and how much of it was fetched (S26): a
/// partial page or an unavailable indexer is said so, never shown as "no tokens".
struct Portfolio: Equatable, Sendable {
    enum State: Equatable, Sendable {
        case complete
        /// The indexer has more than was fetched; older holdings may be missing.
        case partial(fetched: Int)
        case unavailable(String)
    }
    var tokens: [AssetBalance]
    var nfts: [NFT]
    var state: State

    static let empty = Portfolio(tokens: [], nfts: [], state: .complete)
}

extension ChainService {
    func portfolio(for address: Address) async throws -> Portfolio {
        async let tokens = tokenBalances(for: address)
        async let nfts = nfts(for: address)
        return Portfolio(tokens: try await tokens, nfts: try await nfts, state: .complete)
    }
}

struct SignedPayload: Equatable, Sendable {
    let publicKey: String
    let signature: String
}

/// Errors the UI distinguishes from generic failures.
enum ChainError: LocalizedError, Equatable {
    /// The node has no record of this account: it has never received tez on this network.
    case accountNotOnChain(Address)
    /// The password did not decrypt the wallet's key.
    case wrongPassphrase
    /// The user declined on the Ledger.
    case ledgerDeclined
    /// The Ledger is showing the dashboard or another app.
    case ledgerAppNotOpen
    /// The Ledger is locked (PIN screen).
    case ledgerLocked
    /// No Ledger on USB.
    case ledgerNotConnected
    /// The connected Ledger derives a different key at this path (wrong device or seed).
    case ledgerWrongDevice(String)
    /// The secret key on disk does not derive the account's address (edited or swapped directory).
    case keyAddressMismatch(String)

    var errorDescription: String? {
        switch self {
        case .accountNotOnChain: "Key not found on chain"
        case .wrongPassphrase: "Incorrect password for this account."
        case .ledgerDeclined: "Declined on the Ledger."
        case .ledgerAppNotOpen: "Open the Tezos app on your Ledger and try again."
        case .ledgerLocked: "Unlock your Ledger and try again."
        case .ledgerNotConnected: "No Ledger is connected. Plug it in, unlock it and open the Tezos app."
        case .ledgerWrongDevice(let detail): detail
        case .keyAddressMismatch(let detail): detail
        }
    }

    /// Recognises the bridge's error text for the cases above, so every signing path maps them the same way.
    static func fromBridgeMessage(_ message: String) -> ChainError? {
        let lower = message.lowercased()
        if lower.contains("decrypt") || lower.contains("passphrase") { return .wrongPassphrase }
        if lower.contains("0x6985") || lower.contains("denied by the user") || lower.contains("conditions_of_use_not_satisfied") { return .ledgerDeclined }
        if lower.contains("0x5515") || lower.contains("locked_device") || lower.contains("locked device") { return .ledgerLocked }
        if lower.contains("0x6e00") || lower.contains("0x6d00") || lower.contains("0x6511") || lower.contains("0x6e01") || lower.contains("0x6d02")
            || lower.contains("cla_not_supported") || lower.contains("ins_not_supported") { return .ledgerAppNotOpen }
        if lower.contains("no ledger is connected") || lower.contains("was unplugged") { return .ledgerNotConnected }
        if lower.contains("does not hold this key") { return .ledgerWrongDevice(message) }
        if lower.contains("does not derive the account's address") { return .keyAddressMismatch(message) }
        return nil
    }
}
