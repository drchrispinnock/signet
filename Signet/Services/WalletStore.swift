import Foundation
import CryptoKit

/// Captures the exact account entries whose removal is being approved. Kept only for the flow;
/// the secret (encrypted when applicable) is needed to verify that same entry's password.
struct WalletRemovalSnapshot: Sendable {
    let wallet: Wallet
    let storageID: String
    let fingerprint: Data
    let secretKey: String?
}

/// Where wallets and their secret keys live.
protocol WalletStore: Sendable {
    func load() throws -> [Wallet]
    /// Adds a wallet whose `secret_keys` entry is `locator` (`unencrypted:…`, `encrypted:…`,
    /// `ledger://…`). Fails if the alias is already taken.
    func add(_ wallet: Wallet, locator: String) throws
    /// Adds an address we hold no key for (address book). Fails if the alias is already taken.
    func addWatchOnly(_ wallet: Wallet) throws
    /// The base58 secret key for clear-text and encrypted entries (encrypted ones need the password), else `nil`.
    /// The alias on disk must still map to `wallet.address`: a `Wallet` captured by a sheet may
    /// outlive a directory switch or an external edit, and the alias alone must never pick a key.
    func secretKey(for wallet: Wallet) throws -> String?
    /// Changes an alias everywhere it appears. Fails if the new alias is already taken.
    func rename(alias: String, to newAlias: String) throws
    /// Captures the account entries and storage identity before password verification.
    /// Fails if the stored account no longer matches the wallet being approved.
    func removalSnapshot(for wallet: Wallet) throws -> WalletRemovalSnapshot
    /// Compares the snapshot and removes the alias from every file, secret key included,
    /// while holding the same storage lock (octez-client's `forget address … --force`).
    func remove(_ wallet: Wallet, matching snapshot: WalletRemovalSnapshot) throws
    /// Brings in wallets from an octez-client style directory, skipping aliases already present.
    /// Returns how many were added.
    func importWallets(from directory: URL) throws -> Int
    /// Named contracts (octez-client's `contracts` file): the multisigs the user has created or added.
    func loadContracts() throws -> [MultisigContract]
    /// Records a contract alias. Fails if the alias is already taken.
    func addContract(_ contract: MultisigContract) throws
}

extension WalletStore {
    func remove(_ wallet: Wallet) throws {
        try remove(wallet, matching: removalSnapshot(for: wallet))
    }

    /// Adds a wallet and its base58 secret key (clear or octez-encrypted).
    func add(_ wallet: Wallet, secretKey: String) throws {
        try add(wallet, locator: KeyKind.locator(forSecretKey: secretKey))
    }
}

/// For previews and tests. Nothing is persisted.
final class InMemoryWalletStore: WalletStore, @unchecked Sendable {
    enum StoreError: Error { case aliasExists(String), unknownAlias(String), addressMismatch(String), walletChanged(String) }

    private let lock = NSLock()
    private let storageID = UUID().uuidString
    private var wallets: [Wallet]
    private var secrets: [String: String] = [:]
    private var contracts: [MultisigContract] = []

    init(wallets: [Wallet] = []) {
        self.wallets = wallets
    }

    /// Accounts first, then named contracts as watch-only entries, like `TezosClientStore.load()`.
    private func allWallets() -> [Wallet] {
        wallets + contracts.map { Wallet(alias: $0.alias, address: $0.address, keyKind: .none) }
    }

    private func aliasTaken(_ alias: String) -> Bool {
        wallets.contains { $0.alias == alias } || contracts.contains { $0.alias == alias }
    }

    func load() throws -> [Wallet] { lock.withLock { allWallets() } }

    func add(_ wallet: Wallet, locator: String) throws {
        try lock.withLock {
            guard !aliasTaken(wallet.alias) else { throw StoreError.aliasExists(wallet.alias) }
            wallets.append(wallet)
            secrets[wallet.alias] = locator
        }
    }

    func addWatchOnly(_ wallet: Wallet) throws {
        if wallet.address.isContract {
            try addContract(MultisigContract(alias: wallet.alias, address: wallet.address))
            return
        }
        try lock.withLock {
            guard !aliasTaken(wallet.alias) else { throw StoreError.aliasExists(wallet.alias) }
            var entry = wallet
            entry.keyKind = .none
            entry.publicKey = nil
            wallets.append(entry)
        }
    }

    func secretKey(for wallet: Wallet) throws -> String? {
        try lock.withLock {
            guard let locator = secrets[wallet.alias] else { return nil }
            guard wallets.first(where: { $0.alias == wallet.alias })?.address == wallet.address else { throw StoreError.addressMismatch(wallet.alias) }
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

    func removalSnapshot(for wallet: Wallet) throws -> WalletRemovalSnapshot {
        try lock.withLock { try snapshot(for: wallet) }
    }

    private func snapshot(for wallet: Wallet) throws -> WalletRemovalSnapshot {
        guard let stored = allWallets().first(where: { $0.alias == wallet.alias }) else { throw StoreError.unknownAlias(wallet.alias) }
        guard stored.address == wallet.address else { throw StoreError.addressMismatch(wallet.alias) }
        guard stored == wallet else { throw StoreError.walletChanged(wallet.alias) }
        struct Entries: Encodable { let wallet: Wallet; let locator: String? }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let locator = secrets[wallet.alias]
        let data = try encoder.encode(Entries(wallet: stored, locator: locator))
        let secret = locator.flatMap { locator in
            ["unencrypted:", "encrypted:"].first(where: locator.hasPrefix).map { String(locator.dropFirst($0.count)) }
        }
        return WalletRemovalSnapshot(wallet: wallet, storageID: storageID, fingerprint: Data(SHA256.hash(data: data)), secretKey: secret)
    }

    func remove(_ wallet: Wallet, matching expected: WalletRemovalSnapshot) throws {
        try lock.withLock {
            let current = try snapshot(for: wallet)
            guard expected.wallet == wallet, expected.storageID == current.storageID,
                  expected.fingerprint == current.fingerprint else { throw StoreError.walletChanged(wallet.alias) }
            wallets.removeAll { $0.alias == wallet.alias }
            contracts.removeAll { $0.alias == wallet.alias }
            secrets[wallet.alias] = nil
        }
    }

    func loadContracts() throws -> [MultisigContract] { lock.withLock { contracts } }

    func addContract(_ contract: MultisigContract) throws {
        try lock.withLock {
            guard !aliasTaken(contract.alias) else { throw StoreError.aliasExists(contract.alias) }
            contracts.append(contract)
        }
    }

    func rename(alias: String, to newAlias: String) throws {
        try lock.withLock {
            guard !aliasTaken(newAlias) else { throw StoreError.aliasExists(newAlias) }
            if let index = wallets.firstIndex(where: { $0.alias == alias }) {
                wallets[index].alias = newAlias
                if let secret = secrets.removeValue(forKey: alias) { secrets[newAlias] = secret }
            } else if let index = contracts.firstIndex(where: { $0.alias == alias }) {
                contracts[index].alias = newAlias
            } else {
                throw StoreError.unknownAlias(alias)
            }
        }
    }
}
