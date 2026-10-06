import Foundation

/// Static data matching the sketch in spec/EXAMPLE.png. Used for previews and tests.
struct MockChainService: ChainService {
    static let captainStake = Address("tz1dCaMnnMJk76UodjewCK67ABiXWjcKj73N")

    func tezBalance(for address: Address) async throws -> TezBalance {
        TezBalance(spendable: Decimal(string: "1361.43")!, staked: 3000)
    }

    func etherlinkBalance(for address: Address) async throws -> Decimal {
        Decimal(string: "5432.1")!
    }

    func tokenBalances(for address: Address) async throws -> [AssetBalance] {
        []
    }

    func domains(for address: Address) async throws -> [String] {
        address == Self.captainStake ? ["captstake.tez"] : ["mytez.tez"]
    }

    func nfts(for address: Address) async throws -> [NFT] {
        (1...6).map { NFT(id: "mock:\($0)", contract: "KT1mock", tokenId: "\($0)", name: "NFT \($0)", balance: 1, thumbnailURL: nil) }
    }

    func resolveDomain(_ name: String) async throws -> Address? {
        name.lowercased() == "captstake.tez" ? Self.captainStake : nil
    }

    func accountProfile(for address: Address) async throws -> AccountProfile? {
        address == Self.captainStake ? AccountProfile(name: "Captain Stake", twitter: "captstake", description: "Truth, Justice, Staking.") : nil
    }

    func estimateTransfer(from wallet: Wallet, to destination: Address, amount: Decimal) async throws -> TransferEstimate {
        let burn: Decimal = destination == Self.captainStake ? 0 : Decimal(string: "0.06425")!
        return TransferEstimate(fee: Decimal(string: "0.000521")!, burn: burn, total: amount + Decimal(string: "0.000521")! + burn, gasLimit: 169, storageLimit: burn > 0 ? 257 : 0)
    }

    func sendTransfer(from wallet: Wallet, secretKey: String, passphrase: String?, to destination: Address, amount: Decimal) async throws -> String {
        if wallet.keyKind == .encrypted, passphrase != "correct horse" { throw ChainError.wrongPassphrase }
        return "ooMockOperationHash1111111111111111111111111111111111"
    }

    func waitForConfirmation(of operationHash: String) async throws -> Int {
        9_000_000
    }
}
