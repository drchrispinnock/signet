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
    /// TzKT avatar service (TzProfiles logos, known-account logos, identicon fallback), or `nil`.
    let avatarURL: URL?

    var isMainnet: Bool { chain == "mainnet" }

    static let mainnet = Network(
        name: "Mainnet",
        chain: "mainnet",
        rpcURL: URL(string: "https://rpc.tzbeta.net")!,
        tezosDomainsURL: URL(string: "https://api.tezos.domains/graphql")!,
        tzktURL: URL(string: "https://api.tzkt.io")!,
        avatarURL: URL(string: "https://services.tzkt.io/v1/avatars/")!
    )
    static let shadownet = Network(
        name: "Shadownet",
        chain: "shadownet",
        rpcURL: URL(string: "https://rpc.shadownet.teztnets.com")!,
        tezosDomainsURL: nil,
        tzktURL: URL(string: "https://api.shadownet.tzkt.io")!,
        avatarURL: nil
    )

    /// The avatar image for `address` on this network, as TzKT shows it, or `nil` without a service.
    func avatarURL(for address: Address) -> URL? {
        avatarURL.flatMap { URL(string: address.value, relativeTo: $0)?.absoluteURL }
    }

    /// Networks offered in Settings, in display order.
    static let all: [Network] = [.mainnet, .shadownet]

    static func named(_ name: String?) -> Network? {
        all.first { $0.name == name }
    }
}
