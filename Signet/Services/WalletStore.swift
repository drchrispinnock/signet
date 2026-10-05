import Foundation

/// Persists the list of wallets (aliases, addresses, public keys). Secret keys are never here.
protocol WalletStore: Sendable {
    func load() throws -> [Wallet]
    func save(_ wallets: [Wallet]) throws
}

/// JSON file in the app's Application Support directory.
struct FileWalletStore: WalletStore {
    let url: URL

    init(url: URL? = nil) {
        if let url {
            self.url = url
        } else {
            let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            self.url = support.appendingPathComponent("Signet", isDirectory: true).appendingPathComponent("wallets.json")
        }
    }

    func load() throws -> [Wallet] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode([Wallet].self, from: data)
    }

    func save(_ wallets: [Wallet]) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(wallets).write(to: url, options: .atomic)
    }
}

/// For previews and tests.
final class InMemoryWalletStore: WalletStore, @unchecked Sendable {
    private let lock = NSLock()
    private var wallets: [Wallet]

    init(wallets: [Wallet] = []) {
        self.wallets = wallets
    }

    func load() throws -> [Wallet] { lock.withLock { wallets } }
    func save(_ wallets: [Wallet]) throws { lock.withLock { self.wallets = wallets } }
}
