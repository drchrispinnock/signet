import Foundation
@testable import Signet

/// Default implementations so small test doubles only override what they care about.
protocol TestChainService: ChainService {}
extension TestChainService {
    func etherlinkBalance(for address: Address) async throws -> Decimal { 0 }
    func tokenBalances(for address: Address) async throws -> [AssetBalance] { [] }
    func domains(for address: Address) async throws -> [String] { [] }
    func nfts(for address: Address) async throws -> [NFT] { [] }
    func recentTransactions(for address: Address, limit: Int) async throws -> [TezosTransaction] { [] }
    func resolveDomain(_ name: String) async throws -> Address? { nil }
    func accountProfile(for address: Address) async throws -> AccountProfile? { nil }
    func estimateTransfer(from wallet: Wallet, to destination: Address, amount: Decimal) async throws -> TransferEstimate {
        TransferEstimate(fee: 0.001, burn: 0, total: amount + 0.001, gasLimit: 0, storageLimit: 0)
    }
    func sendTransfer(from wallet: Wallet, secretKey: String, passphrase: String?, to destination: Address, amount: Decimal) async throws -> String { "ooTest" }
    func waitForConfirmation(of operationHash: String) async throws -> Int { 1 }
    func delegateInfo(for address: Address) async throws -> DelegateInfo { DelegateInfo(delegate: nil, baker: nil, delegateAcceptsStaking: nil) }
    func bakers(limit: Int) async throws -> [BakerCandidate] { [] }
    func estimateStaking(_ operation: StakingOperation, from wallet: Wallet) async throws -> TransferEstimate { TransferEstimate(fee: 0.001, burn: 0, total: 0.001, gasLimit: 0, storageLimit: 0) }
    func performStaking(_ operation: StakingOperation, from wallet: Wallet, secretKey: String, passphrase: String?) async throws -> String { "ooTest" }
    func proofOfPossession(secretKey: String, passphrase: String?) async throws -> String { "BLsigTest" }
}
