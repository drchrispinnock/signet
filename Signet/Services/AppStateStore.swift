import Foundation

/// UI state remembered between launches: which wallet was showing, which network was chosen
/// and any custom nodes.
struct AppState: Codable, Equatable, Sendable {
    var selectedWalletAlias: String?
    var networkName: String?
    /// Custom RPC nodes by network name, for networks where the user replaced the default.
    var nodeURLs: [String: String]?
    /// Etherlink on or off by network name, only where the user changed it from the default
    /// (on where we ship an Etherlink endpoint, off elsewhere).
    var l2Enabled: [String: Bool]?
    /// Etherlink RPC nodes by network name, where the user replaced (or supplied) one.
    var l2NodeURLs: [String: String]?
    /// Shielded transactions on by network name, only where the user turned them on.
    var shieldedEnabled: [String: Bool]?
    /// TzEL services by network name, then by `ShieldedConfig.Setting` raw value, only where
    /// the user replaced what we ship.
    var shieldedSettings: [String: [String: String]]?
    /// TzKT API, explorer and faucet links by network name, then by `Network.Service` raw
    /// value, only where the user replaced the default; an empty string means the link is off.
    var serviceURLs: [String: [String: String]]?
}

extension AppState {
    /// `base` with everything saved for it applied: its node, its Layer 2 switch and node, and
    /// its links. Saved text that is not a URL is ignored; Layer 2 is off unless saved on.
    func resolved(_ base: Network) -> Network {
        var network = base
        if let saved = nodeURLs?[base.name], let url = Network.nodeURL(from: saved) { network = network.usingNode(url) }
        let l2Node = l2NodeURLs?[base.name].flatMap(Network.nodeURL(from:)) ?? base.l2DefaultRPCURL
        network = network.usingL2(enabled: l2Enabled?[base.name] ?? false, node: l2Node)
        network = network.usingShielded(enabled: shieldedEnabled?[base.name] ?? false)
        for setting in ShieldedConfig.Setting.allCases {
            // Saved text that is not valid for the item is ignored.
            guard let saved = shieldedSettings?[base.name]?[setting.rawValue], let config = network.shielded?.using(saved, for: setting) else { continue }
            network = network.usingShielded(config: config)
        }
        for service in Network.Service.allCases {
            guard let saved = serviceURLs?[base.name]?[service.rawValue] else { continue }
            // "" is a link the user turned off; anything that is not a URL is ignored.
            if saved.isEmpty {
                network = network.using(nil, for: service)
            } else if let url = Network.nodeURL(from: saved) {
                network = network.using(url, for: service)
            }
        }
        return network
    }

    /// Records `net`'s node, Layer 2 choices and links, each only where it differs from the
    /// defaults, so the maps stay sparse and `nil` when nothing is custom.
    mutating func remember(_ net: Network) {
        rememberNode(of: net)
        rememberL2(of: net)
        rememberShielded(of: net)
        rememberServices(of: net)
    }

    mutating func rememberNode(of net: Network) {
        var nodes = nodeURLs ?? [:]
        nodes[net.name] = net.isUsingDefaultNode ? nil : net.rpcURL.absoluteString
        nodeURLs = nodes.isEmpty ? nil : nodes
    }

    /// Etherlink is off by default everywhere, with our endpoint where we ship one.
    mutating func rememberL2(of net: Network) {
        var nodes = l2NodeURLs ?? [:]
        nodes[net.name] = net.isUsingDefaultL2Node ? nil : net.l2RPCURL?.absoluteString
        l2NodeURLs = nodes.isEmpty ? nil : nodes
        var flags = l2Enabled ?? [:]
        flags[net.name] = net.l2Enabled ? true : nil
        l2Enabled = flags.isEmpty ? nil : flags
    }

    /// Shielded transactions are off by default everywhere; only "on" is saved, and of the
    /// TzEL services only those replaced.
    mutating func rememberShielded(of net: Network) {
        var flags = shieldedEnabled ?? [:]
        flags[net.name] = net.shieldedEnabled ? true : nil
        shieldedEnabled = flags.isEmpty ? nil : flags
        var all = shieldedSettings ?? [:]
        var settings = all[net.name] ?? [:]
        for setting in ShieldedConfig.Setting.allCases {
            settings[setting.rawValue] = net.isUsingDefault(setting) ? nil : net.shielded?.text(for: setting)
        }
        all[net.name] = settings.isEmpty ? nil : settings
        shieldedSettings = all.isEmpty ? nil : all
    }

    /// TzKT, explorer and faucet links ("" for a link turned off).
    mutating func rememberServices(of net: Network) {
        var all = serviceURLs ?? [:]
        var links = all[net.name] ?? [:]
        for service in Network.Service.allCases {
            links[service.rawValue] = net.isUsingDefault(service) ? nil : (net.url(for: service)?.absoluteString ?? "")
        }
        all[net.name] = links.isEmpty ? nil : links
        serviceURLs = all.isEmpty ? nil : all
    }
}

protocol AppStateStore: Sendable {
    func load() -> AppState
    func save(_ state: AppState) throws
}

/// `~/.signet/state`, a small JSON file next to the wallet files.
struct FileAppStateStore: AppStateStore {
    let url: URL

    init(directory: URL = TezosClientStore.defaultDirectory) {
        url = directory.appendingPathComponent("state")
    }

    func load() -> AppState {
        guard let data = try? Data(contentsOf: url),
              let state = try? JSONDecoder().decode(AppState.self, from: data)
        else { return AppState() }
        return state
    }

    func save(_ state: AppState) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try PrivateFile.write(try encoder.encode(state), to: url)
    }
}

/// For previews and tests. Share one instance between two models to simulate a relaunch.
final class InMemoryAppStateStore: AppStateStore, @unchecked Sendable {
    private let lock = NSLock()
    private var state: AppState

    init(_ state: AppState = AppState()) {
        self.state = state
    }

    func load() -> AppState { lock.withLock { state } }
    func save(_ state: AppState) throws { lock.withLock { self.state = state } }
}
