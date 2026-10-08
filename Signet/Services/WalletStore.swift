import Foundation

/// Where wallets and their secret keys live.
protocol WalletStore: Sendable {
    func load() throws -> [Wallet]
    /// Adds a wallet whose `secret_keys` entry is `locator` (`unencrypted:…`, `encrypted:…`,
    /// `ledger://…`). Fails if the alias is already taken.
    func add(_ wallet: Wallet, locator: String) throws
    /// Adds an address we hold no key for (address book). Fails if the alias is already taken.
    func addWatchOnly(_ wallet: Wallet) throws
    /// The base58 secret key for clear-text and encrypted entries (encrypted ones need the password), else `nil`.
    func secretKey(for wallet: Wallet) throws -> String?
    /// Changes an alias everywhere it appears. Fails if the new alias is already taken.
    func rename(alias: String, to newAlias: String) throws
    /// Removes an alias from every file, secret key included (octez-client's `forget address … --force`).
    func remove(alias: String) throws
    /// Brings in wallets from an octez-client style directory, skipping aliases already present.
    /// Returns how many were added.
    func importWallets(from directory: URL) throws -> Int
}

extension WalletStore {
    /// Adds a wallet and its base58 secret key (clear or octez-encrypted).
    func add(_ wallet: Wallet, secretKey: String) throws {
        try add(wallet, locator: KeyKind.locator(forSecretKey: secretKey))
    }
}

/// For previews and tests. Nothing is persisted.
final class InMemoryWalletStore: WalletStore, @unchecked Sendable {
    enum StoreError: Error { case aliasExists(String), unknownAlias(String) }

    private let lock = NSLock()
    private var wallets: [Wallet]
    private var secrets: [String: String] = [:]

    init(wallets: [Wallet] = []) {
        self.wallets = wallets
    }

    func load() throws -> [Wallet] { lock.withLock { wallets } }

    func add(_ wallet: Wallet, locator: String) throws {
        try lock.withLock {
            guard !wallets.contains(where: { $0.alias == wallet.alias }) else { throw StoreError.aliasExists(wallet.alias) }
            wallets.append(wallet)
            secrets[wallet.alias] = locator
        }
    }

    func addWatchOnly(_ wallet: Wallet) throws {
        try lock.withLock {
            guard !wallets.contains(where: { $0.alias == wallet.alias }) else { throw StoreError.aliasExists(wallet.alias) }
            var entry = wallet
            entry.keyKind = .none
            entry.publicKey = nil
            wallets.append(entry)
        }
    }

    func secretKey(for wallet: Wallet) throws -> String? {
        lock.withLock {
            guard let locator = secrets[wallet.alias] else { return nil }
            for prefix in ["unencrypted:", "encrypted:"] where locator.hasPrefix(prefix) { return String(locator.dropFirst(prefix.count)) }
            return nil
        }
    }

    func importWallets(from directory: URL) throws -> Int {
        let incoming = try TezosClientStore(directory: directory).load()
        return lock.withLock {
            let existing = Set(wallets.map(\.alias))
            let additions = incoming.filter { !existing.contains($0.alias) }
            wallets.append(contentsOf: additions)
            return additions.count
        }
    }

    func remove(alias: String) throws {
        try lock.withLock {
            guard wallets.contains(where: { $0.alias == alias }) else { throw StoreError.unknownAlias(alias) }
            wallets.removeAll { $0.alias == alias }
            secrets[alias] = nil
        }
    }

    func rename(alias: String, to newAlias: String) throws {
        try lock.withLock {
            guard !wallets.contains(where: { $0.alias == newAlias }) else { throw StoreError.aliasExists(newAlias) }
            guard let index = wallets.firstIndex(where: { $0.alias == alias }) else { throw StoreError.unknownAlias(alias) }
            wallets[index].alias = newAlias
            if let secret = secrets.removeValue(forKey: alias) { secrets[newAlias] = secret }
        }
    }
}
