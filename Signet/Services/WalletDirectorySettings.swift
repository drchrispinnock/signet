import Foundation

/// Where the wallet directory is. This pointer cannot live inside the directory it points to,
/// so it is the one thing kept in the app's preferences rather than in `~/.signet/state`.
// UserDefaults is thread-safe but not annotated Sendable; this wrapper only ever reads and writes one key.
struct WalletDirectorySettings: @unchecked Sendable {
    static let key = "walletDirectory"

    let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var defaultDirectory: URL { TezosClientStore.defaultDirectory }

    var current: URL {
        guard let path = defaults.string(forKey: Self.key), !path.isEmpty else { return defaultDirectory }
        return URL(fileURLWithPath: (path as NSString).expandingTildeInPath, isDirectory: true)
    }

    /// Stores `url`, or clears the override when it is the default directory.
    func set(_ url: URL) {
        if url.standardizedFileURL == defaultDirectory.standardizedFileURL {
            defaults.removeObject(forKey: Self.key)
        } else {
            defaults.set(url.standardizedFileURL.path, forKey: Self.key)
        }
    }
}
