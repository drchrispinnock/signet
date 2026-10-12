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
