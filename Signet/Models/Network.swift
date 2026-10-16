import Foundation

/// A chain the wallet can talk to and the node it uses for it. RPC URLs come from
/// https://teztnets.com/teztnets.json; Ghostnet was retired, so Shadownet is the long-running
/// public testnet. `rpcURL` is the node in use; `defaultRPCURL` is the one we ship, which the
/// user can override per network in the Networks sheet.
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
    /// TzKT indexer base URL (tokens, NFTs, history), or `nil` where none is available.
    /// `tzktURL` is the one in use, `defaultTzKTURL` the one we ship (the Networks sheet lets
    /// the user replace or clear each of the TzKT, explorer and faucet links per network).
    var tzktURL: URL?
    let defaultTzKTURL: URL?
    /// Testnet faucet, or `nil` on mainnet (from teztnets.json). Mainnet never has one.
    var faucetURL: URL? = nil
    let defaultFaucetURL: URL?
    /// Which faucet protocol `faucetURL` speaks.
    var faucetKind: FaucetKind = .teztnets
    /// Block explorer for this network, used to link operations; `nil` when there is none.
    var explorerURL: URL? = nil
    let defaultExplorerURL: URL?
    /// The chain id a node for this network must report (`/chains/main/chain_id`), when the
    /// network is long-lived enough to pin one (S12). The node monitor shows a node serving
    /// another chain in red, and nothing is estimated or signed through it.
    var expectedChainID: String? = nil
    /// Etherlink, the layer 2 rollup, through its Tezos-style ("michelson") RPC, where tz1 to
    /// tz3 keys are used directly. `l2DefaultRPCURL` is the endpoint we ship (mainnet and
    /// Shadownet), `l2RPCURL` the one in use, and `l2Enabled` whether Layer 2 features (the
    /// Etherlink balance, Bridge, Receive and Send on Etherlink) are on at all; off by default.
    var l2DefaultRPCURL: URL? = nil
    var l2RPCURL: URL? = nil
    var l2Enabled = false
    /// The chain id the Etherlink RPC must report (`/chains/main/chain_id`), when pinned (S12).
    var expectedL2ChainID: String? = nil
    /// Etherlink's bridge helper contract on layer 1 (`deposit %evm_address %l2_address`) and the
    /// Smart Rollup it feeds, for depositing tez to a Michelson-interface account. Shipped for
    /// mainnet and Shadownet; a user-supplied Layer 2 node does not come with a bridge.
    var l2BridgeHelper: Address? = nil
    var l2Rollup: String? = nil
    /// TzKT for the Michelson interface and its explorer, where TzKT indexes it.
    var l2TzKTURL: URL? = nil
    var l2ExplorerURL: URL? = nil

    enum FaucetKind: Sendable {
        /// tacoinfra/tezos-faucet: `/info`, `/challenge` (proof of work), `/verify`.
        case teztnets
        /// Nomadic Labs' PQPark faucet: `/info`, then `POST /send {to, amount}`.
        case pqpark
    }

    init(name: String, chain: String, rpcURL: URL, tezosDomainsURL: URL?, tzktURL: URL?, faucetURL: URL? = nil,
         faucetKind: FaucetKind = .teztnets, explorerURL: URL? = nil, expectedChainID: String? = nil,
         l2RPCURL: URL? = nil, expectedL2ChainID: String? = nil, l2BridgeHelper: String? = nil, l2Rollup: String? = nil,
         l2TzKTURL: URL? = nil, l2ExplorerURL: URL? = nil) {
        self.name = name
        self.chain = chain
        self.rpcURL = rpcURL
        self.defaultRPCURL = rpcURL
        self.tezosDomainsURL = tezosDomainsURL
        self.tzktURL = tzktURL
        self.defaultTzKTURL = tzktURL
        self.faucetURL = chain == "mainnet" ? nil : faucetURL
        self.defaultFaucetURL = self.faucetURL
        self.faucetKind = faucetKind
        self.explorerURL = explorerURL
        self.defaultExplorerURL = explorerURL
        self.expectedChainID = expectedChainID
        self.l2DefaultRPCURL = l2RPCURL
        self.l2RPCURL = l2RPCURL
        self.l2Enabled = false   // off until the user turns Layer 2 on in the Networks sheet
        self.expectedL2ChainID = expectedL2ChainID
        self.l2BridgeHelper = l2BridgeHelper.map(Address.init)
        self.l2Rollup = l2Rollup
        self.l2TzKTURL = l2TzKTURL
        self.l2ExplorerURL = l2ExplorerURL
    }

    /// Etherlink's Michelson interface as a network of its own, for operations between tz
    /// accounts on the rollup: the Layer 2 node is its node, its chain id is pinned, and its
    /// TzKT and explorer are Etherlink's. `nil` unless Layer 2 is on with a node.
    var layer2: Network? {
        guard hasL2, let node = l2RPCURL else { return nil }
        var copy = Network(name: "\(name) · Etherlink", chain: "etherlink-\(chain)", rpcURL: node, tezosDomainsURL: nil,
                           tzktURL: l2TzKTURL, explorerURL: l2ExplorerURL, expectedChainID: expectedL2ChainID)
        copy.layerNumber = 2
        return copy
    }

    /// 1 for a Tezos network, 2 for its `layer2` counterpart.
    var layerNumber = 1

    /// Etherlink is on and has a node to ask.
    var hasL2: Bool { l2Enabled && l2RPCURL != nil }
    /// Tez can be moved from layer 1 to Etherlink here: Layer 2 is on and the bridge is known.
    var canDepositToL2: Bool { hasL2 && l2BridgeHelper != nil && l2Rollup != nil }

    /// Etherlink's Michelson gateway (the same address on every Etherlink network): the
    /// contract a tz account calls to reach the EVM runtime, and whose `resolveAddress` view
    /// says whether the account's EVM alias exists yet.
    static let etherlinkGateway = Address("KT18oDJJKXMKhfE1bSuAPGp92pYcwVDiqsPw")
    var isUsingDefaultL2Node: Bool { l2RPCURL == l2DefaultRPCURL }

    /// The same network with Etherlink switched on or off and pointed at `node`.
    func usingL2(enabled: Bool, node: URL?) -> Network {
        var copy = self
        copy.l2Enabled = enabled
        copy.l2RPCURL = node
        return copy
    }

    /// The links a network uses besides its node: the TzKT API, the block explorer and the
    /// faucet. Each can be replaced or cleared per network in the Networks sheet.
    enum Service: String, CaseIterable, Sendable {
        case tzkt, explorer, faucet

        var title: String {
            switch self {
            case .tzkt: "TzKT API"
            case .explorer: "Block explorer"
            case .faucet: "Faucet"
            }
        }
    }

    /// Whether `service` can be set on this network at all: mainnet has no faucet.
    func offers(_ service: Service) -> Bool { service != .faucet || !isMainnet }

    func url(for service: Service) -> URL? {
        switch service {
        case .tzkt: tzktURL
        case .explorer: explorerURL
        case .faucet: faucetURL
        }
    }

    func defaultURL(for service: Service) -> URL? {
        switch service {
        case .tzkt: defaultTzKTURL
        case .explorer: defaultExplorerURL
        case .faucet: defaultFaucetURL
        }
    }

    func isUsingDefault(_ service: Service) -> Bool { url(for: service) == defaultURL(for: service) }

    /// The same network with `service` pointed at `url` (`nil` turns it off). A faucet on
    /// mainnet is ignored.
    func using(_ url: URL?, for service: Service) -> Network {
        var copy = self
        switch service {
        case .tzkt: copy.tzktURL = url
        case .explorer: copy.explorerURL = url
        case .faucet: copy.faucetURL = offers(.faucet) ? url : nil
        }
        return copy
    }

    /// Where to look an operation up, if this network has an explorer.
    func explorerURL(operation hash: String) -> URL? {
        guard let explorerURL else { return nil }
        // tzkt.io front ends (mainnet and the testnets) take the hash as a path; self-hosted
        // TzKT front ends use the hash route.
        return Self.isTzKTFrontEnd(explorerURL) ? explorerURL.appendingPathComponent(hash) : URL(string: "\(explorerURL.absoluteString)/#op/\(hash)")
    }

    /// Where to look a contract up, if this network has an explorer.
    func explorerURL(contract address: String) -> URL? {
        guard let explorerURL else { return nil }
        return Self.isTzKTFrontEnd(explorerURL) ? explorerURL.appendingPathComponent(address) : URL(string: "\(explorerURL.absoluteString)/#contract/\(address)")
    }

    private static func isTzKTFrontEnd(_ url: URL) -> Bool {
        let host = url.host()?.lowercased() ?? ""
        return host == "tzkt.io" || host.hasSuffix(".tzkt.io")
    }

    var isMainnet: Bool { chain == "mainnet" }
    var isUsingDefaultNode: Bool { rpcURL == defaultRPCURL }

    /// The same network talking to `url` instead of its current node.
    func usingNode(_ url: URL) -> Network {
        var copy = self
        copy.rpcURL = url
        return copy
    }

    /// Parses what the user typed for a node: an absolute URL with a host, trailing slashes dropped
    /// so paths append cleanly, or `nil` when it is not one. A bare host such as `rpc.tzbeta.net`
    /// (optionally with a port or path) is taken as HTTPS. Plain `http://` is accepted only for
    /// this machine and the local network, where there is nothing to intercept (a node you run
    /// yourself); anything further away must be HTTPS. Credentials in the URL are refused (S12).
    static func nodeURL(from text: String) -> URL? {
        var trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        while trimmed.hasSuffix("/") { trimmed.removeLast() }
        guard !trimmed.isEmpty, !trimmed.contains(" ") else { return nil }
        if !trimmed.lowercased().hasPrefix("http://"), !trimmed.lowercased().hasPrefix("https://") {
            guard !trimmed.contains("://") else { return nil }   // some other scheme
            trimmed = "https://" + trimmed
        }
        guard let url = URL(string: trimmed), let host = url.host(percentEncoded: false), !host.isEmpty, url.user == nil, url.password == nil else { return nil }
        let local = EndpointPolicy.isLocalOrPrivateHost(host)
        guard local || host.contains(".") else { return nil }
        if url.scheme?.lowercased() == "http", !local { return nil }
        return url
    }

    /// Why `nodeURL(from:)` refused `text`, for the Networks sheet.
    static func nodeURLProblem(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if trimmed.hasPrefix("http://") { return "Plain http is only allowed for a node on this machine or your local network; use https for anything else." }
        if trimmed.contains("@") { return "Leave credentials out of the node URL." }
        return "Enter a host name such as rpc.tzbeta.net."
    }

    /// The node as shown to the user: the full URL.
    var nodeDisplayText: String { rpcURL.nodeDisplayTextStandalone }

    static let mainnet = Network(
        name: "Mainnet",
        chain: "mainnet",
        rpcURL: URL(string: "https://rpc.tzbeta.net")!,
        tezosDomainsURL: URL(string: "https://api.tezos.domains/graphql")!,
        tzktURL: URL(string: "https://api.tzkt.io")!,
        explorerURL: URL(string: "https://tzkt.io")!,
        expectedChainID: "NetXdQprcVkpaWU",
        l2RPCURL: URL(string: "https://michelson.etherlink.mainnet.octez.io")!,
        expectedL2ChainID: "NetXohUVN5QWR4f",
        l2BridgeHelper: "KT1Wj8SUGmnEPFqyahHAcjcNQwe6YGhEXJb5",
        l2Rollup: "sr1Ghq66tYK9y3r8CC1Tf8i8m5nxh8nTvZEf",
        l2TzKTURL: URL(string: "https://api.etherlink.tzkt.io")!,
        l2ExplorerURL: URL(string: "https://etherlink.tzkt.io")!
    )
    static let shadownet = Network(
        name: "Shadownet",
        chain: "shadownet",
        rpcURL: URL(string: "https://rpc.shadownet.teztnets.com")!,
        tezosDomainsURL: nil,
        tzktURL: URL(string: "https://api.shadownet.tzkt.io")!,
        faucetURL: URL(string: "https://faucet.shadownet.teztnets.com")!,
        explorerURL: URL(string: "https://shadownet.tzkt.io")!,
        expectedChainID: "NetXsqzbfFenSTS",
        l2RPCURL: URL(string: "https://michelson.etherlink.shadownet.octez.io")!,
        expectedL2ChainID: "NetXtLrzvQDobza",
        l2BridgeHelper: "KT19aBsSWvWtvEkbiqReJnD8UzQMWcD8SHUD",
        l2Rollup: "sr19fMYrr5C4qqvQqQrDSjtP31GcrWjodzvg",
        l2TzKTURL: URL(string: "https://api.shadownet.etherlink.tzkt.io")!,
        l2ExplorerURL: URL(string: "https://shadownet.etherlink.tzkt.io")!
    )
    static let bakingnet = Network(
        name: "Bakingnet",
        chain: "bakingnet",
        rpcURL: URL(string: "https://rpc.bakingnet.teztnets.com")!,
        tezosDomainsURL: nil,
        tzktURL: URL(string: "https://api.bakingnet.tzkt.io")!,
        faucetURL: URL(string: "https://faucet.bakingnet.teztnets.com")!,
        explorerURL: URL(string: "https://bakingnet.tzkt.io")!,
        expectedChainID: "NetXvNVUNbWHxGt"
    )
    /// The protocol-proposal testnet of the day (Ushuaia, October 2026). teztnets.com also
    /// aliases it as "currentnet", but TzKT names its instance after the protocol, so the entry
    /// is the protocol's own: when the next proposal's network appears, replace this one.
    static let ushuaianet = Network(
        name: "Ushuaianet",
        chain: "ushuaianet",
        rpcURL: URL(string: "https://rpc.ushuaianet.teztnets.com")!,
        tezosDomainsURL: nil,
        tzktURL: URL(string: "https://api.ushuaianet.tzkt.io")!,
        faucetURL: URL(string: "https://faucet.ushuaianet.teztnets.com")!,
        explorerURL: URL(string: "https://ushuaianet.tzkt.io")!,
        expectedChainID: "NetXpX8WSZkAZZA"
    )

    /// Weeklynet restarts every Wednesday from tezos/tezos master and its hosts carry the launch
    /// date (`rpc.weeklynet-YYYY-MM-DD.teztnets.com`); there is no dated-free alias, so the URL
    /// is built from the most recent Wednesday (UTC). Set a node in Networks to pin another.
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

    /// Networks offered in the Networks sheet and the badge, in display order, each with its default node.
    static var all: [Network] { [.mainnet, .shadownet, .bakingnet, .ushuaianet, .weeklynet, .quantumnet, .custom] }

    static func named(_ name: String?) -> Network? {
        all.first { $0.name == name }
    }
}


extension URL {
    /// The node as shown in the Networks sheet: the full URL, e.g. `https://rpc.tzbeta.net`.
    var nodeDisplayTextStandalone: String { absoluteString }
}
