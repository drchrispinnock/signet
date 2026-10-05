import Foundation

/// Static data matching the sketch in spec/EXAMPLE.png. Used for previews and until live
/// chain access lands.
struct MockChainService: ChainService {
    func tezBalance(for address: Address) async throws -> Decimal {
        Decimal(string: "4361.43")!
    }

    func etherlinkBalance(for address: Address) async throws -> Decimal {
        Decimal(string: "5432.1")!
    }

    func tokenBalances(for address: Address) async throws -> [AssetBalance] {
        []
    }

    func domains(for address: Address) async throws -> [String] {
        ["mytez.tez"]
    }

    func nfts(for address: Address) async throws -> [NFT] {
        (1...6).map { NFT(id: "mock-\($0)", name: "NFT \($0)", thumbnailURL: nil) }
    }
}
