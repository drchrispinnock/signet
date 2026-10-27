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
        TransferEstimate(fee: 0.001, burn: 0, total: amount + 0.001, gasLimit: 0, storageLimit: 0, limits: OperationLimits(feeMutez: "1000", gasLimit: 0, storageLimit: 0))
    }
    func sendTransfer(from wallet: Wallet, signer: SigningKey, to destination: Address, amount: Decimal, limits: OperationLimits) async throws -> SentOperation { SentOperation(hash: "ooTest") }
    func rebroadcast(_ sent: SentOperation) async throws -> SentOperation { sent }
    func waitForConfirmation(of operationHash: String) async throws -> Int { 1 }
    func delegateInfo(for address: Address) async throws -> DelegateInfo { DelegateInfo(delegate: nil, baker: nil, delegateAcceptsStaking: nil) }
    func bakers(limit: Int) async throws -> [BakerCandidate] { [] }
    func estimateStaking(_ operation: StakingOperation, from wallet: Wallet) async throws -> TransferEstimate { TransferEstimate(fee: 0.001, burn: 0, total: 0.001, gasLimit: 0, storageLimit: 0, limits: OperationLimits(feeMutez: "1000", gasLimit: 0, storageLimit: 0)) }
    func performStaking(_ operation: StakingOperation, from wallet: Wallet, signer: SigningKey, limits: OperationLimits) async throws -> SentOperation { SentOperation(hash: "ooTest") }
    func proofOfPossession(signer: SigningKey) async throws -> String { "BLsigTest" }
    func estimateEtherlinkDeposit(from wallet: Wallet, amount: Decimal) async throws -> TransferEstimate { TransferEstimate(fee: 0.001, burn: 0, total: amount + 0.001, gasLimit: 0, storageLimit: 0, limits: OperationLimits(feeMutez: "1000", gasLimit: 0, storageLimit: 0)) }
    func sendEtherlinkDeposit(from wallet: Wallet, signer: SigningKey, amount: Decimal, limits: OperationLimits) async throws -> SentOperation { SentOperation(hash: "ooTest") }
    func estimateShieldDeposit(from wallet: Wallet, deposit: ShieldDeposit) async throws -> TransferEstimate { TransferEstimate(fee: 0.001, burn: 0, total: deposit.amount + 0.001, gasLimit: 0, storageLimit: 0, limits: OperationLimits(feeMutez: "1000", gasLimit: 0, storageLimit: 0)) }
    func sendShieldDeposit(from wallet: Wallet, signer: SigningKey, deposit: ShieldDeposit, limits: OperationLimits) async throws -> SentOperation { SentOperation(hash: "ooTest") }
    func estimateOutboxExecution(from wallet: Wallet, execution: OutboxExecution) async throws -> TransferEstimate { TransferEstimate(fee: 0.001, burn: 0, total: 0.001, gasLimit: 0, storageLimit: 0, limits: OperationLimits(feeMutez: "1000", gasLimit: 0, storageLimit: 0)) }
    func sendOutboxExecution(from wallet: Wallet, signer: SigningKey, execution: OutboxExecution, limits: OperationLimits) async throws -> SentOperation { SentOperation(hash: "ooTest") }
    func etherlinkAliasStatus(for address: Address) async throws -> EtherlinkAliasStatus { .unlinked(evmAddress: EtherlinkAlias.address(for: address)) }
    func estimateEtherlinkLink(from wallet: Wallet) async throws -> TransferEstimate { TransferEstimate(fee: 0.001, burn: 0, total: 0.001, gasLimit: 0, storageLimit: 0, limits: OperationLimits(feeMutez: "1000", gasLimit: 0, storageLimit: 0)) }
    func sendEtherlinkLink(from wallet: Wallet, signer: SigningKey, limits: OperationLimits) async throws -> SentOperation { SentOperation(hash: "ooTest") }
    func signPayload(signer: SigningKey, payloadHex: String) async throws -> SignedPayload { SignedPayload(publicKey: "edpkTest", signature: "edsigTest") }
    func governanceInfo(for address: Address) async throws -> GovernanceInfo { GovernanceInfo() }
    func performGovernance(_ operation: GovernanceOperation, from wallet: Wallet, signer: SigningKey) async throws -> String { "ooTest" }
    func etherlinkVotingRights(for address: Address, contract: Address) async throws -> [Address] { [] }
    func etherlinkGovernanceState(contract: Address, for address: Address) async throws -> EtherlinkGovernance.State { EtherlinkGovernance.State(contract: contract) }
    func estimateEtherlinkGovernance(_ operation: EtherlinkGovernance.Operation, contract: Address, from wallet: Wallet) async throws -> TransferEstimate { TransferEstimate(fee: 0.001, burn: 0, total: 0.001, gasLimit: 0, storageLimit: 0, limits: OperationLimits(feeMutez: "1000", gasLimit: 0, storageLimit: 0)) }
    func sendEtherlinkGovernance(_ operation: EtherlinkGovernance.Operation, contract: Address, from wallet: Wallet, signer: SigningKey, limits: OperationLimits) async throws -> SentOperation { SentOperation(hash: "ooTest") }
}
