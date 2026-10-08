import Foundation

/// Everything the UI needs from the chain and indexers, behind one protocol so views can be
/// driven by mock data until the Taquito bridge is in place.
protocol ChainService: Sendable {
    func tezBalance(for address: Address) async throws -> TezBalance
    func etherlinkBalance(for address: Address) async throws -> Decimal
    func tokenBalances(for address: Address) async throws -> [AssetBalance]
    func domains(for address: Address) async throws -> [String]
    func nfts(for address: Address) async throws -> [NFT]
    /// Most recent operations touching the address, newest first.
    func recentTransactions(for address: Address, limit: Int) async throws -> [TezosTransaction]

    /// Forward Tezos Domains lookup: `name.tez` → address, or `nil` if unregistered.
    func resolveDomain(_ name: String) async throws -> Address?
    /// Indexer-known identity for an address (TzProfiles via TzKT), or `nil`.
    func accountProfile(for address: Address) async throws -> AccountProfile?

    /// Cost of a transfer, computed without any secret key.
    func estimateTransfer(from wallet: Wallet, to destination: Address, amount: Decimal) async throws -> TransferEstimate
    /// Signs and injects a transfer. Returns the operation hash.
    func sendTransfer(from wallet: Wallet, signer: SigningKey, to destination: Address, amount: Decimal) async throws -> String
    /// Waits for the operation to be included. Returns the block level.
    func waitForConfirmation(of operationHash: String) async throws -> Int

    // Delegation, staking and baking.
    func delegateInfo(for address: Address) async throws -> DelegateInfo
    /// Bakers to offer in the picker, most popular first.
    func bakers(limit: Int) async throws -> [BakerCandidate]
    func estimateStaking(_ operation: StakingOperation, from wallet: Wallet) async throws -> TransferEstimate
    func performStaking(_ operation: StakingOperation, from wallet: Wallet, signer: SigningKey) async throws -> String
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

    var errorDescription: String? {
        switch self {
        case .accountNotOnChain: "Key not found on chain"
        case .wrongPassphrase: "Incorrect password for this account."
        case .ledgerDeclined: "Declined on the Ledger."
        case .ledgerAppNotOpen: "Open the Tezos app on your Ledger and try again."
        case .ledgerLocked: "Unlock your Ledger and try again."
        case .ledgerNotConnected: "No Ledger is connected. Plug it in, unlock it and open the Tezos app."
        case .ledgerWrongDevice(let detail): detail
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
        return nil
    }
}
