import Foundation

/// UI state remembered between launches: which wallet was showing and which node was chosen.
struct AppState: Codable, Equatable, Sendable {
    var selectedWalletAlias: String?
    var networkName: String?
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
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(state).write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
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
