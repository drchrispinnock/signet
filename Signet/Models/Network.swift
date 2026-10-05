import Foundation

/// A Tezos network the wallet can talk to. RPC URLs come from https://teztnets.com/teztnets.json;
/// Ghostnet was retired, so Shadownet is the long-running public testnet.
struct Network: Hashable, Sendable {
    let name: String
    let rpcURL: URL

    static let mainnet = Network(name: "Mainnet", rpcURL: URL(string: "https://rpc.tzbeta.net")!)
    static let shadownet = Network(name: "Shadownet", rpcURL: URL(string: "https://rpc.shadownet.teztnets.com")!)
}
