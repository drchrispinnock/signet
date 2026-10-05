import Foundation

/// Live chain access through the Taquito bridge. Anything the bridge does not provide yet is
/// delegated to `fallback` so the UI stays complete while features land one at a time.
struct TaquitoChainService: ChainService {
    let network: Network
    let bridge: TaquitoBridge
    let fallback: any ChainService
    let session: URLSession

    init(network: Network = .mainnet, bridge: TaquitoBridge = .shared, fallback: any ChainService = MockChainService(), session: URLSession = .shared) {
        self.network = network
        self.bridge = bridge
        self.fallback = fallback
        self.session = session
    }

    func tezBalance(for address: Address) async throws -> TezBalance {
        // Taquito rejects tz5/tz6 addresses, so ask the node directly for those.
        if let scheme = address.scheme, !scheme.isSupported {
            return try await directTezBalance(for: address)
        }
        let result = try await bridge.call("getTezBalances", [network.rpcURL.absoluteString, address.value])
        guard let balance = TezBalance(
            mutezSpendable: result["spendable"]?.stringValue,
            staked: result["staked"]?.stringValue,
            unstakedFrozen: result["unstakedFrozen"]?.stringValue,
            unstakedFinalizable: result["unstakedFinalizable"]?.stringValue
        ) else {
            throw TaquitoBridge.BridgeError.javaScript("unexpected balance payload: \(String(describing: result))")
        }
        return balance
    }

    /// The same breakdown straight from the node: `/context/contracts/<pkh>/{spendable,staked_balance,...}`.
    func directTezBalance(for address: Address) async throws -> TezBalance {
        async let spendable = rpcMutez("spendable", for: address)
        async let staked = rpcMutez("staked_balance", for: address)
        async let frozen = rpcMutez("unstaked_frozen_balance", for: address)
        async let finalizable = rpcMutez("unstaked_finalizable_balance", for: address)
        guard let balance = TezBalance(mutezSpendable: try await spendable, staked: try await staked,
                                       unstakedFrozen: try await frozen, unstakedFinalizable: try await finalizable)
        else { throw URLError(.cannotParseResponse) }
        return balance
    }

    /// `GET /chains/main/blocks/head/context/contracts/<pkh>/<field>` → `"<mutez>"`.
    private func rpcMutez(_ field: String, for address: Address) async throws -> String {
        let url = network.rpcURL.appendingPathComponent("chains/main/blocks/head/context/contracts/\(address.value)/\(field)")
        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse, userInfo: [NSLocalizedDescriptionKey: "RPC error for \(address.shortened()) \(field): \(String(data: data, encoding: .utf8) ?? "")"])
        }
        guard let text = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) as? String else {
            throw URLError(.cannotParseResponse)
        }
        return text
    }

    func etherlinkBalance(for address: Address) async throws -> Decimal {
        try await fallback.etherlinkBalance(for: address)
    }

    func tokenBalances(for address: Address) async throws -> [AssetBalance] {
        try await fallback.tokenBalances(for: address)
    }

    /// The address's published Tezos Domains name, if any. A lookup failure is logged and
    /// treated as "no name" so a flaky domains API never hides the balances.
    func domains(for address: Address) async throws -> [String] {
        guard let endpoint = network.tezosDomainsURL else { return [] }
        do {
            let name = try await TezosDomainsService(endpoint: endpoint, session: session).reverseName(for: address)
            return name.map { [$0] } ?? []
        } catch {
            NSLog("Tezos Domains lookup failed for % %@", address.value, error.localizedDescription)
            return []
        }
    }

    /// NFTs from the TzKT indexer. Indexer trouble is logged and shown as an empty grid rather
    /// than failing the whole refresh.
    func nfts(for address: Address) async throws -> [NFT] {
        guard let tzkt = network.tzktURL else { return [] }
        do {
            return try await TzKTService(baseURL: tzkt, session: session).nfts(for: address)
        } catch {
            NSLog("TzKT NFT lookup failed for % %@", address.value, error.localizedDescription)
            return []
        }
    }
}
