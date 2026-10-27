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
    func pendingOperation(for address: Address) async throws -> SentOperation?
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

    // Etherlink bridge (0.9.1): a layer 1 deposit to the wallet's own account on the rollup.
    func estimateEtherlinkDeposit(from wallet: Wallet, amount: Decimal) async throws -> TransferEstimate
    /// Signs and injects the deposit with exactly the approved `limits` (S14).
    func sendEtherlinkDeposit(from wallet: Wallet, signer: SigningKey, amount: Decimal, limits: OperationLimits) async throws -> SentOperation

    // Shielded tez (TzEL): the layer 1 deposit into a deposit pool through the bridge ticketer's
    // `mint`; the rollup credits `deposit:<pubkeyHash>` and the wallet shields it from there.
    func estimateShieldDeposit(from wallet: Wallet, deposit: ShieldDeposit) async throws -> TransferEstimate
    /// Signs and injects the deposit with exactly the approved `limits` (S14).
    func sendShieldDeposit(from wallet: Wallet, signer: SigningKey, deposit: ShieldDeposit, limits: OperationLimits) async throws -> SentOperation
    /// Executing an unshield's outbox message on layer 1 (the ticketer's `burn` paying the
    /// recipient), once the rollup commitment covering it is cemented.
    func estimateOutboxExecution(from wallet: Wallet, execution: OutboxExecution) async throws -> TransferEstimate
    /// Signs and injects the execution with exactly the approved `limits` (S14).
    func sendOutboxExecution(from wallet: Wallet, signer: SigningKey, execution: OutboxExecution, limits: OperationLimits) async throws -> SentOperation

    // Etherlink alias (0.9.3), on a Layer 2 (Michelson interface) service only: whether the
    // account's EVM-side address exists on chain yet, and the gateway call that creates it.
    func etherlinkAliasStatus(for address: Address) async throws -> EtherlinkAliasStatus
    func estimateEtherlinkLink(from wallet: Wallet) async throws -> TransferEstimate
    /// Signs and injects the link call with exactly the approved `limits` (S14).
    func sendEtherlinkLink(from wallet: Wallet, signer: SigningKey, limits: OperationLimits) async throws -> SentOperation

    /// Signs raw bytes (hex) with no watermark, e.g. a packed "Tezos Signed Message". Returns the
    /// signer's public key and the prefixed signature (edsig/spsig/p2sig…).
    func signPayload(signer: SigningKey, payloadHex: String) async throws -> SignedPayload

    // Governance.
    func governanceInfo(for address: Address) async throws -> GovernanceInfo
    /// Injects an upvote or ballot. Returns the operation hash.
    func performGovernance(_ operation: GovernanceOperation, from wallet: Wallet, signer: SigningKey) async throws -> String

    // Etherlink governance: layer 1 contracts, called with an ordinary fee.
    /// The bakers `address` is the Etherlink voting key of on `contract` (the delegation contract's `list_voters`).
    func etherlinkVotingRights(for address: Address, contract: Address) async throws -> [Address]
    func etherlinkGovernanceState(contract: Address, for address: Address) async throws -> EtherlinkGovernance.State
    func estimateEtherlinkGovernance(_ operation: EtherlinkGovernance.Operation, contract: Address, from wallet: Wallet) async throws -> TransferEstimate
    /// Signs and injects the call with exactly the approved `limits` (S14).
    func sendEtherlinkGovernance(_ operation: EtherlinkGovernance.Operation, contract: Address, from wallet: Wallet, signer: SigningKey, limits: OperationLimits) async throws -> SentOperation
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
    func pendingOperation(for address: Address) async throws -> SentOperation? { nil }
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
    /// The network has Etherlink off or no Etherlink node to ask.
    case noEtherlinkNode
    /// The network has no known bridge contract for depositing to Etherlink.
    case noEtherlinkBridge
    /// Asked of a layer 1 service: alias status and linking live on the Layer 2 node.
    case notALayer2Service
    /// A node answered with another chain's id than the one pinned for it (S12).
    case wrongChain(expected: String, found: String)
    /// Estimating an unrevealed tz4 account's operation: the reveal needs the key's BLS proof of
    /// possession, which only the secret key can make (`ChainService.proofOfPossession`).
    case proofOfPossessionRequired
    /// The node refused to simulate because the source cannot pay: it holds no tez on this
    /// network (`empty_implicit_contract`) or too little for the fee (`balance_too_low`).
    case cannotPayFee

    var errorDescription: String? {
        switch self {
        case .accountNotOnChain: "Key not found on chain"
        case .noEtherlinkNode: "Etherlink is not enabled for this network."
        case .noEtherlinkBridge: "Signet knows no Etherlink bridge for this network."
        case .notALayer2Service: "This needs the Layer 2 node."
        case .wrongChain(let expected, let found): "The node serves chain \(found), not \(expected)."
        case .proofOfPossessionRequired: "This account's first operation reveals its key with a proof of possession, which needs the secret key."
        case .cannotPayFee: "This account holds no tez on this network, or too little to pay the fee."
        case .wrongPassphrase: "Incorrect password for this account."
        case .ledgerDeclined: "Declined on the Ledger."
        case .ledgerAppNotOpen: "Open the Tezos app on your Ledger and try again."
        case .ledgerLocked: "Unlock your Ledger and try again."
        case .ledgerNotConnected: "No Ledger is connected. Plug it in, unlock it and open the Tezos app."
        case .ledgerWrongDevice(let detail): detail
        case .keyAddressMismatch(let detail): detail
        }
    }

    /// Recognises the bridge's error text for the cases above, so every signing path maps them
    /// the same way (`TaquitoBridge.BridgeError.typed` is the one place that applies it).
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
        if lower.contains("proof of possession required") { return .proofOfPossessionRequired }
        if lower.contains("empty_implicit_contract") || lower.contains("empty implicit contract")
            || lower.contains("balance_too_low") || lower.contains("subtraction_underflow") { return .cannotPayFee }
        return nil
    }
}

extension TaquitoBridge.BridgeError {
    /// The `ChainError` this failure stands for when the bridge's text is one every signing path
    /// words the same way (wrong password, Ledger trouble, a key for another address); otherwise
    /// the bridge error itself, untouched.
    var asChainError: any Error {
        if case .javaScript(let message) = self, let known = ChainError.fromBridgeMessage(message) { return known }
        return self
    }

    /// Runs a bridge call and rethrows a bridge failure through `asChainError`. Any other error
    /// passes through unchanged, so a typed catch keeps exactly its scope.
    static func typed<T>(_ body: () async throws -> T) async throws -> T {
        do {
            return try await body()
        } catch let error as TaquitoBridge.BridgeError {
            throw error.asChainError
        }
    }
}

/// Whether a tz account's address on Etherlink's EVM side exists on chain. The address itself
/// is a pure function of the tz address (`EtherlinkAlias`), but the rollup only creates the
/// account behind it, with the forwarder that passes tez on to the tz account, when the
/// account makes its first cross-interface call. Before that, the gateway's `resolveAddress`
/// view reports the address as derived (1) rather than recorded (0), and tez sent to it sit at
/// an address nobody controls.
enum EtherlinkAliasStatus: Equatable, Sendable {
    /// Recorded on chain: tez sent to the alias reach the account.
    case linked(evmAddress: String)
    /// Only derived so far: the account must link itself first.
    case unlinked(evmAddress: String)

    var isLinked: Bool { if case .linked = self { true } else { false } }
    var evmAddress: String {
        switch self {
        case .linked(let address), .unlinked(let address): address
        }
    }
}

/// A layer 1 deposit into a TzEL deposit pool: the ticketer to call, the rollup it feeds, the
/// pool (`pubkey_hash`, hex) and the tez to attach.
struct ShieldDeposit: Hashable, Sendable {
    let ticketer: Address
    let rollup: String
    let pubkeyHash: String
    let amount: Decimal
}

/// A rollup outbox message to execute on layer 1: the rollup, the cemented commitment the
/// rollup node proved it against and that proof (hex).
struct OutboxExecution: Hashable, Sendable {
    let rollup: String
    let cementedCommitment: String
    let outputProof: String
}
