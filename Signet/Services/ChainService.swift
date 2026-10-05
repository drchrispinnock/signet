import Foundation

/// Everything the UI needs from the chain and indexers, behind one protocol so views can be
/// driven by mock data until the Taquito bridge is in place.
protocol ChainService: Sendable {
    func tezBalance(for address: Address) async throws -> TezBalance
    func etherlinkBalance(for address: Address) async throws -> Decimal
    func tokenBalances(for address: Address) async throws -> [AssetBalance]
    func domains(for address: Address) async throws -> [String]
    func nfts(for address: Address) async throws -> [NFT]

    /// Forward Tezos Domains lookup: `name.tez` → address, or `nil` if unregistered.
    func resolveDomain(_ name: String) async throws -> Address?
    /// Indexer-known identity for an address (TzProfiles via TzKT), or `nil`.
    func accountProfile(for address: Address) async throws -> AccountProfile?

    /// Cost of a transfer, computed without any secret key.
    func estimateTransfer(from wallet: Wallet, to destination: Address, amount: Decimal) async throws -> TransferEstimate
    /// Signs and injects a transfer. Returns the operation hash.
    func sendTransfer(from wallet: Wallet, secretKey: String, to destination: Address, amount: Decimal) async throws -> String
    /// Waits for the operation to be included. Returns the block level.
    func waitForConfirmation(of operationHash: String) async throws -> Int
}

/// Errors the UI distinguishes from generic failures.
enum ChainError: LocalizedError, Equatable {
    /// The node has no record of this account: it has never received tez on this network.
    case accountNotOnChain(Address)

    var errorDescription: String? {
        switch self {
        case .accountNotOnChain: "Key not found on chain"
        }
    }
}
