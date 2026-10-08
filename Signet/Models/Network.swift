import Foundation

/// A chain the wallet can talk to and the node it uses for it. RPC URLs come from
/// https://teztnets.com/teztnets.json; Ghostnet was retired, so Shadownet is the long-running
/// public testnet. `rpcURL` is the node in use; `defaultRPCURL` is the one we ship, which the
/// user can override per network in Settings.
struct Network: Hashable, Identifiable, Sendable {
    var id: String { name }

    let name: String
    /// Which chain this node serves, e.g. "mainnet" or "shadownet".
    let chain: String
    /// The node in use. Defaults to `defaultRPCURL`.
    var rpcURL: URL
    /// The node we ship for this network.
    let defaultRPCURL: URL
    /// Tezos Domains GraphQL endpoint, or `nil` where the service does not run.
    let tezosDomainsURL: URL?
    /// TzKT indexer base URL (tokens, NFTs), or `nil` where none is available.
    let tzktURL: URL?
    /// Testnet faucet, or `nil` on mainnet (from teztnets.json).
    var faucetURL: URL? = nil
    /// Which faucet protocol `faucetURL` speaks.
    var faucetKind: FaucetKind = .teztnets
    /// Block explorer for this network, used to link operations; `nil` when there is none.
    var explorerURL: URL? = nil

    enum FaucetKind: Sendable {
        /// tacoinfra/tezos-faucet: `/info`, `/challenge` (proof of work), `/verify`.
        case teztnets
        /// Nomadic Labs' PQPark faucet: `/info`, then `POST /send {to, amount}`.
        case pqpark
    }

    init(name: String, chain: String, rpcURL: URL, tezosDomainsURL: URL?, tzktURL: URL?, faucetURL: URL? = nil,
         faucetKind: FaucetKind = .teztnets, explorerURL: URL? = nil) {
        self.name = name
        self.chain = chain
        self.rpcURL = rpcURL
        self.defaultRPCURL = rpcURL
        self.tezosDomainsURL = tezosDomainsURL
        self.tzktURL = tzktURL
        self.faucetURL = faucetURL
        self.faucetKind = faucetKind
        self.explorerURL = explorerURL
    }

    /// Where to look an operation up, if this network has an explorer.
    func explorerURL(operation hash: String) -> URL? {
        guard let explorerURL else { return nil }
        // tzkt.io takes the hash as a path; self-hosted TzKT front ends use the hash route.
        return explorerURL.host() == "tzkt.io" ? explorerURL.appendingPathComponent(hash) : URL(string: "\(explorerURL.absoluteString)/#op/\(hash)")
    }

    var isMainnet: Bool { chain == "mainnet" }
    var isUsingDefaultNode: Bool { rpcURL == defaultRPCURL }

    /// The same network talking to `url` instead of its current node.
    func usingNode(_ url: URL) -> Network {
        var copy = self
        copy.rpcURL = url
        return copy
    }

    /// Parses what the user typed into the node field: an absolute http(s) URL with a host,
    /// trailing slashes dropped so paths append cleanly. `nil` when it is not one.
    /// Parses what the user typed for a node. A bare host such as `rpc.tzbeta.net` (optionally with
    /// a port or path) is taken as HTTPS; an explicit `http://` or `https://` is kept.
    static func nodeURL(from text: String) -> URL? {
        var trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        while trimmed.hasSuffix("/") { trimmed.removeLast() }
        guard !trimmed.isEmpty, !trimmed.contains(" ") else { return nil }
        if !trimmed.lowercased().hasPrefix("http://"), !trimmed.lowercased().hasPrefix("https://") {
            trimmed = "https://" + trimmed
        }
        guard let url = URL(string: trimmed), let host = url.host(), !host.isEmpty, host.contains(".") || host == "localhost" else { return nil }
        return url
    }

    /// The node as shown to the user: the full URL.
    var nodeDisplayText: String { rpcURL.nodeDisplayTextStandalone }

    static let mainnet = Network(
        name: "Mainnet",
        chain: "mainnet",
        rpcURL: URL(string: "https://rpc.tzbeta.net")!,
        tezosDomainsURL: URL(string: "https://api.tezos.domains/graphql")!,
        tzktURL: URL(string: "https://api.tzkt.io")!,
        explorerURL: URL(string: "https://tzkt.io")!
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

    /// Weeklynet restarts every Wednesday from tezos/tezos master and its hosts carry the launch
    /// date (`rpc.weeklynet-YYYY-MM-DD.teztnets.com`); there is no dated-free alias, so the URL
    /// is built from the most recent Wednesday (UTC). Set a node in Settings to pin another.
    static var weeklynet: Network { weeklynet(on: Date()) }

    static func weeklynet(on date: Date) -> Network {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let weekday = calendar.component(.weekday, from: date)  // 1 = Sunday … 4 = Wednesday
        let daysSinceWednesday = (weekday - 4 + 7) % 7
        let wednesday = calendar.date(byAdding: .day, value: -daysSinceWednesday, to: calendar.startOfDay(for: date))!
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        let stamp = formatter.string(from: wednesday)
        return Network(
            name: "Weeklynet",
            chain: "weeklynet",
            rpcURL: URL(string: "https://rpc.weeklynet-\(stamp).teztnets.com")!,
            tezosDomainsURL: nil,
            tzktURL: nil,
            faucetURL: URL(string: "https://faucet.weeklynet-\(stamp).teztnets.com")!
        )
    }

    /// Nomadic Labs' post-quantum testnet (tz5 enabled, 6 s blocks). Not on teztnets.com: its node,
    /// TzKT and faucet live under pqpark.dal.nomadic-labs.com, and the faucet is PQPark's own.
    static let quantumnet = Network(
        name: "Quantumnet",
        chain: "quantumnet",
        rpcURL: URL(string: "https://quantumnet.pqpark.dal.nomadic-labs.com/rpc")!,
        tezosDomainsURL: nil,
        tzktURL: URL(string: "https://quantumnet-tzkt.pqpark.dal.nomadic-labs.com")!,
        faucetURL: URL(string: "https://quantumnet-faucet.pqpark.dal.nomadic-labs.com/api")!,
        faucetKind: .pqpark,
        explorerURL: URL(string: "https://quantumnet-tzkt.pqpark.dal.nomadic-labs.com")!
    )

    /// A network of the user's own: any node they point it at. Defaults to a local node.
    static let custom = Network(
        name: "Custom",
        chain: "custom",
        rpcURL: URL(string: "http://localhost:8732")!,
        tezosDomainsURL: nil,
        tzktURL: nil
    )

    /// Networks offered in Settings, in display order, each with its default node.
    static var all: [Network] { [.mainnet, .shadownet, .bakingnet, .currentnet, .weeklynet, .quantumnet, .custom] }

    static func named(_ name: String?) -> Network? {
        all.first { $0.name == name }
    }
}


extension URL {
    /// The node as shown in Settings: the full URL, e.g. `https://rpc.tzbeta.net`.
    var nodeDisplayTextStandalone: String { absoluteString }
}
