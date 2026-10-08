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
    func sendTransfer(from wallet: Wallet, secretKey: String, passphrase: String?, to destination: Address, amount: Decimal) async throws -> String
    /// Waits for the operation to be included. Returns the block level.
    func waitForConfirmation(of operationHash: String) async throws -> Int

    // Delegation, staking and baking.
    func delegateInfo(for address: Address) async throws -> DelegateInfo
    /// Bakers to offer in the picker, most popular first.
    func bakers(limit: Int) async throws -> [BakerCandidate]
    func estimateStaking(_ operation: StakingOperation, from wallet: Wallet) async throws -> TransferEstimate
    func performStaking(_ operation: StakingOperation, from wallet: Wallet, secretKey: String, passphrase: String?) async throws -> String
    /// BLS proof of possession for one of our tz4 keys.
    func proofOfPossession(secretKey: String, passphrase: String?) async throws -> String
}

/// Errors the UI distinguishes from generic failures.
enum ChainError: LocalizedError, Equatable {
    /// The node has no record of this account: it has never received tez on this network.
    case accountNotOnChain(Address)
    /// The password did not decrypt the wallet's key.
    case wrongPassphrase

    var errorDescription: String? {
        switch self {
        case .accountNotOnChain: "Key not found on chain"
        case .wrongPassphrase: "Incorrect password for this wallet."
        }
    }
}
