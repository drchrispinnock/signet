import Foundation

/// A Tezos network the wallet can talk to. RPC URLs come from https://teztnets.com/teztnets.json;
/// Ghostnet was retired, so Shadownet is the long-running public testnet.
struct Network: Hashable, Identifiable, Sendable {
    var id: String { name }

    let name: String
    let rpcURL: URL
    /// Tezos Domains GraphQL endpoint, or `nil` where the service does not run.
    let tezosDomainsURL: URL?
    /// TzKT indexer base URL (tokens, NFTs), or `nil` where none is available.
    let tzktURL: URL?

    static let mainnet = Network(
        name: "Mainnet",
        rpcURL: URL(string: "https://rpc.tzbeta.net")!,
        tezosDomainsURL: URL(string: "https://api.tezos.domains/graphql")!,
        tzktURL: URL(string: "https://api.tzkt.io")!
    )
    static let shadownet = Network(
        name: "Shadownet",
        rpcURL: URL(string: "https://rpc.shadownet.teztnets.com")!,
        tezosDomainsURL: nil,
        tzktURL: URL(string: "https://api.shadownet.tzkt.io")!
    )

    /// Networks offered in Settings, in display order.
    static let all: [Network] = [.mainnet, .shadownet]

    static func named(_ name: String?) -> Network? {
        all.first { $0.name == name }
    }
}
