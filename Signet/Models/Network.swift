import Foundation

/// A node the wallet can talk to. Several entries may point at the same chain with different
/// RPC endpoints. RPC URLs come from https://teztnets.com/teztnets.json; Ghostnet was retired,
/// so Shadownet is the long-running public testnet.
struct Network: Hashable, Identifiable, Sendable {
    var id: String { name }

    let name: String
    /// Which chain this node serves, e.g. "mainnet" or "shadownet".
    let chain: String
    let rpcURL: URL
    /// Tezos Domains GraphQL endpoint, or `nil` where the service does not run.
    let tezosDomainsURL: URL?
    /// TzKT indexer base URL (tokens, NFTs), or `nil` where none is available.
    let tzktURL: URL?
    /// Testnet faucet, or `nil` on mainnet (from teztnets.json).
    var faucetURL: URL? = nil

    var isMainnet: Bool { chain == "mainnet" }

    static let mainnet = Network(
        name: "Mainnet",
        chain: "mainnet",
        rpcURL: URL(string: "https://rpc.tzbeta.net")!,
        tezosDomainsURL: URL(string: "https://api.tezos.domains/graphql")!,
        tzktURL: URL(string: "https://api.tzkt.io")!
    )
    static let shadownet = Network(
        name: "Shadownet",
        chain: "shadownet",
        rpcURL: URL(string: "https://rpc.shadownet.teztnets.com")!,
        tezosDomainsURL: nil,
        tzktURL: URL(string: "https://api.shadownet.tzkt.io")!,
        faucetURL: URL(string: "https://faucet.shadownet.teztnets.com")!
    )


    static let bakingnet = Network(
        name: "Bakingnet",
        chain: "bakingnet",
        rpcURL: URL(string: "https://rpc.bakingnet.teztnets.com")!,
        tezosDomainsURL: nil,
        tzktURL: URL(string: "https://api.bakingnet.tzkt.io")!,
        faucetURL: URL(string: "https://faucet.bakingnet.teztnets.com")!
    )
    /// The current protocol-proposal testnet (Ushuaianet at the time of writing).
    static let currentnet = Network(
        name: "Currentnet",
        chain: "currentnet",
        rpcURL: URL(string: "https://rpc.currentnet.teztnets.com")!,
        tezosDomainsURL: nil,
        tzktURL: nil,
        faucetURL: URL(string: "https://faucet.currentnet.teztnets.com")!
    )

    /// Networks offered in Settings, in display order.
    static let all: [Network] = [.mainnet, .shadownet, .bakingnet, .currentnet]

    static func named(_ name: String?) -> Network? {
        all.first { $0.name == name }
    }
}
