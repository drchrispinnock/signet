import Foundation

/// Live chain access through the Taquito bridge. Anything the bridge does not provide yet is
/// delegated to `fallback` so the UI stays complete while features land one at a time.
struct TaquitoChainService: ChainService {
    let network: Network
    let bridge: TaquitoBridge
    let fallback: any ChainService

    init(network: Network = .mainnet, bridge: TaquitoBridge = .shared, fallback: any ChainService = MockChainService()) {
        self.network = network
        self.bridge = bridge
        self.fallback = fallback
    }

    func tezBalance(for address: Address) async throws -> Decimal {
        let result = try await bridge.call("getBalanceMutez", [network.rpcURL.absoluteString, address.value])
        guard let mutez = result.stringValue.flatMap({ Decimal(string: $0) }) else {
            throw TaquitoBridge.BridgeError.javaScript("unexpected balance payload: \(String(describing: result))")
        }
        return mutez / 1_000_000
    }

    func etherlinkBalance(for address: Address) async throws -> Decimal {
        try await fallback.etherlinkBalance(for: address)
    }

    func tokenBalances(for address: Address) async throws -> [AssetBalance] {
        try await fallback.tokenBalances(for: address)
    }

    func domains(for address: Address) async throws -> [String] {
        try await fallback.domains(for: address)
    }

    func nfts(for address: Address) async throws -> [NFT] {
        try await fallback.nfts(for: address)
    }
}
