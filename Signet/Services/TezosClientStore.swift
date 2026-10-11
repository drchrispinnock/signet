import Foundation
import CryptoKit

/// Reads and writes a wallet directory in octez-client's format. Signet's own directory is
/// `~/.signet`; `~/.tezos-client` is read only when the user imports from it.
///
/// Three JSON files hold arrays of `{ "name": alias, "value": ... }`:
/// - `public_key_hashs`: value is the address (`tz1...`).
/// - `public_keys`: value is `{ "locator": "unencrypted:edpk...", "key": "edpk..." }`
///   (older clients wrote a bare `"unencrypted:edpk..."` string; both are read).
/// - `secret_keys`: value is a locator such as `unencrypted:edsk...`, `encrypted:edesk...`,
///   `ledger://...` or a remote signer URI.
///
/// Entries are joined by alias. Writes take `wallet_lock` like octez-client, append only, and
/// replace each file atomically so existing entries are never rewritten by hand.
struct TezosClientStore: WalletStore {
    enum StoreError: LocalizedError {
        case aliasExists(String)
        case unknownAlias(String)
        case missingPublicKey(String)
        case malformed(String, String)
        /// The alias now names a different address than the `Wallet` the caller holds.
        case addressMismatch(alias: String, expected: Address, found: Address?)
        case walletChanged(String)
        /// Another program (octez-client, another Signet) held the wallet lock for too long.
        case locked

        var errorDescription: String? {
            switch self {
            case .aliasExists(let alias): "An alias named “\(alias)” already exists in the tezos-client directory."
            case .unknownAlias(let alias): "No alias named “\(alias)” exists in the tezos-client directory."
            case .missingPublicKey(let alias): "Account “\(alias)” has no public key to write."
            case .malformed(let file, let detail): "\(file) in the tezos-client directory is malformed: \(detail)"
            case .addressMismatch(let alias, let expected, let found):
                "Account “\(alias)” is \(found?.shortened() ?? "missing") in the wallet directory, not \(expected.shortened()) as expected. The directory may have changed; please try again."
            case .walletChanged(let alias):
                "Account “\(alias)” or its key entries changed while removal was being confirmed. Nothing was removed; please try again."
            case .locked:
                "The wallet directory is locked by another program (octez-client?). Please try again in a moment."
            }
        }
    }

    static let publicKeyHashesFile = "public_key_hashs"
    static let publicKeysFile = "public_keys"
    static let secretKeysFile = "secret_keys"
    static let lockFile = "wallet_lock"
    /// Written before a change touches several files, removed after the last one (S09). If it is
    /// still there, the change did not finish and every file it names is put back as it was.
    static let journalFile = "wallet_journal"
    /// octez-client's named contracts (`[{name, value: "KT1…"}]`); multisigs live here.
    static let contractsFile = "contracts"

    /// Signet's own wallet directory.
    static var defaultDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".signet", isDirectory: true)
    }

    /// Where octez-client keeps its wallet.
    static var octezClientDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".tezos-client", isDirectory: true)
    }

    static let walletFiles = [publicKeyHashesFile, publicKeysFile, secretKeysFile]
    /// Every file an alias can appear in; aliases are unique across all of them, as in octez-client.
    static let aliasFiles = walletFiles + [contractsFile]

    let directory: URL

    init(directory: URL = TezosClientStore.defaultDirectory) {
        self.directory = directory
    }

    /// True when the directory already holds a `public_key_hashs` file.
    var hasWallets: Bool {
        FileManager.default.fileExists(atPath: directory.appendingPathComponent(Self.publicKeyHashesFile).path)
    }

    // MARK: WalletStore

    func load() throws -> [Wallet] {
        // A read takes the same lock octez-client writes under, so it never sees a half-done
        // change, and an unfinished change of ours is rolled back first (S09).
        let (hashes, publicKeys, secretKeys, contractRows) = try withWalletLock {
            try recoverIfNeeded()
            PrivateFile.removeStaleTemporaries(in: directory, for: Self.aliasFiles + [Self.journalFile])
            return (try readEntries(Self.publicKeyHashesFile), try index(readEntries(Self.publicKeysFile)), try index(readEntries(Self.secretKeysFile)), try readEntries(Self.contractsFile))
        }

        let accounts: [Wallet] = hashes.compactMap { entry in
            guard let address = entry.value as? String else { return nil }
            let locator = secretKeys[entry.name] as? String
            return Wallet(
                alias: entry.name,
                address: Address(address),
                publicKey: Self.publicKey(from: publicKeys[entry.name]),
                keyKind: KeyKind(locator: locator),
                ledgerKey: locator.flatMap(LedgerKey.init(locator:))
            )
        }
        // Named contracts (`contracts`) are part of the address book: watch-only entries whose
        // address is a KT1. octez-client keeps them apart because `public_key_hashs` may only
        // hold tz addresses (it refuses to read the file otherwise), so Signet keeps them apart
        // on disk too and joins them here.
        let taken = Set(accounts.map(\.alias))
        let contracts = Self.contracts(from: contractRows).filter { !taken.contains($0.alias) }.map { Wallet(alias: $0.alias, address: $0.address, keyKind: .none) }
        return accounts + contracts
    }

    func add(_ wallet: Wallet, locator: String) throws {
        guard let publicKey = wallet.publicKey else { throw StoreError.missingPublicKey(wallet.alias) }
        // octez-client points the public key at the same place as the secret: the file for
        // in-memory keys, the device for Ledger keys.
        let publicKeyLocator = locator.lowercased().hasPrefix("ledger://") ? locator : "unencrypted:\(publicKey)"
        try PrivateFile.hardenDirectory(directory)
        try withWalletLock {
            try recoverIfNeeded()
            var hashes = try readRaw(Self.publicKeyHashesFile)
            var publicKeys = try readRaw(Self.publicKeysFile)
            var secretKeys = try readRaw(Self.secretKeysFile)

            for list in [hashes, publicKeys, secretKeys, try readRaw(Self.contractsFile)] where list.contains(where: { ($0["name"] as? String) == wallet.alias }) {
                throw StoreError.aliasExists(wallet.alias)
            }

            hashes.append(["name": wallet.alias, "value": wallet.address.value])
            publicKeys.append(["name": wallet.alias, "value": ["locator": publicKeyLocator, "key": publicKey]])
            secretKeys.append(["name": wallet.alias, "value": locator])

            try commit([(Self.publicKeyHashesFile, hashes), (Self.publicKeysFile, publicKeys), (Self.secretKeysFile, secretKeys)])
        }
    }

    func loadContracts() throws -> [MultisigContract] {
        Self.contracts(from: try withWalletLock { try recoverIfNeeded(); return try readEntries(Self.contractsFile) })
    }

    private static func contracts(from entries: [Entry]) -> [MultisigContract] {
        entries.compactMap { entry in
            guard let address = entry.value as? String else { return nil }
            return MultisigContract(alias: entry.name, address: Address(address))
        }
    }

    func addContract(_ contract: MultisigContract) throws {
        try PrivateFile.hardenDirectory(directory)
        try withWalletLock {
            try recoverIfNeeded()
            var contracts = try readRaw(Self.contractsFile)
            let taken = try [contracts, readRaw(Self.publicKeyHashesFile), readRaw(Self.publicKeysFile), readRaw(Self.secretKeysFile)]
                .contains { $0.contains { ($0["name"] as? String) == contract.alias } }
            guard !taken else { throw StoreError.aliasExists(contract.alias) }
            contracts.append(["name": contract.alias, "value": contract.address.value])
            try commit([(Self.contractsFile, contracts)])
        }
    }

    func addWatchOnly(_ wallet: Wallet) throws {
        // A KT1 belongs in `contracts`: octez-client refuses to read `public_key_hashs` if one is in there.
        if wallet.address.isContract {
            try addContract(MultisigContract(alias: wallet.alias, address: wallet.address))
            return
        }
        try PrivateFile.hardenDirectory(directory)
        try withWalletLock {
            try recoverIfNeeded()
            var hashes = try readRaw(Self.publicKeyHashesFile)
            let taken = try [hashes, readRaw(Self.publicKeysFile), readRaw(Self.secretKeysFile), readRaw(Self.contractsFile)]
                .contains { $0.contains { ($0["name"] as? String) == wallet.alias } }
            guard !taken else { throw StoreError.aliasExists(wallet.alias) }
            hashes.append(["name": wallet.alias, "value": wallet.address.value])
            try commit([(Self.publicKeyHashesFile, hashes)])
        }
    }

    func rename(alias: String, to newAlias: String) throws {
        try withWalletLock {
            try recoverIfNeeded()
            var files = try Self.aliasFiles.map { ($0, try readRaw($0)) }
            let names = { (list: [[String: Any]]) in list.compactMap { $0["name"] as? String } }
            guard !files.contains(where: { names($0.1).contains(newAlias) }) else { throw StoreError.aliasExists(newAlias) }
            // An alias is an account (in public_key_hashs) or a named contract (in contracts).
            guard files.contains(where: { ($0.0 == Self.publicKeyHashesFile || $0.0 == Self.contractsFile) && names($0.1).contains(alias) }) else {
                throw StoreError.unknownAlias(alias)
            }
            for i in files.indices {
                files[i].1 = files[i].1.map { entry in
                    guard (entry["name"] as? String) == alias else { return entry }
                    var renamed = entry
                    renamed["name"] = newAlias
                    return renamed
                }
            }
            try commit(files.filter { FileManager.default.fileExists(atPath: directory.appendingPathComponent($0.0).path) })
        }
    }

    func removalSnapshot(for wallet: Wallet) throws -> WalletRemovalSnapshot {
        try withWalletLock {
            try recoverIfNeeded()
            return try snapshot(for: wallet, files: Self.aliasFiles.map { ($0, try readRaw($0)) })
        }
    }

    private func snapshot(for wallet: Wallet, files: [(String, [[String: Any]])]) throws -> WalletRemovalSnapshot {
        func value(in file: String) -> Any? {
            files.first(where: { $0.0 == file })?.1.first(where: { ($0["name"] as? String) == wallet.alias })?["value"]
        }
        // Accounts live in public_key_hashs, named contracts in contracts; never both.
        let address = ((value(in: Self.publicKeyHashesFile) ?? value(in: Self.contractsFile)) as? String).map(Address.init)
        guard address == wallet.address else {
            throw StoreError.addressMismatch(alias: wallet.alias, expected: wallet.address, found: address)
        }
        let locator = value(in: Self.secretKeysFile) as? String
        guard Self.publicKey(from: value(in: Self.publicKeysFile)) == wallet.publicKey,
              KeyKind(locator: locator) == wallet.keyKind,
              locator.flatMap(LedgerKey.init(locator:)) == wallet.ledgerKey else { throw StoreError.walletChanged(wallet.alias) }
        let entries = Dictionary(uniqueKeysWithValues: files.map { file, rows in
            (file, rows.filter { ($0["name"] as? String) == wallet.alias })
        })
        let data = try JSONSerialization.data(withJSONObject: entries, options: [.sortedKeys])
        // Bind the snapshot to the actual directory, including replacement at the same path.
        let resolved = directory.resolvingSymlinksInPath().standardizedFileURL
        let attributes = try FileManager.default.attributesOfItem(atPath: resolved.path)
        guard let device = attributes[.systemNumber] as? NSNumber,
              let inode = attributes[.systemFileNumber] as? NSNumber else { throw StoreError.walletChanged(wallet.alias) }
        let storageID = "\(resolved.path):\(device):\(inode)"
        let secret = locator.flatMap { locator in
            ["unencrypted:", "encrypted:"].first(where: locator.hasPrefix).map { String(locator.dropFirst($0.count)) }
        }
        return WalletRemovalSnapshot(wallet: wallet, storageID: storageID, fingerprint: Data(SHA256.hash(data: data)), secretKey: secret)
    }

    func remove(_ wallet: Wallet, matching expected: WalletRemovalSnapshot) throws {
        let alias = wallet.alias
        try withWalletLock {
            try recoverIfNeeded()
            let files = try Self.aliasFiles.map { ($0, try readRaw($0)) }
            guard files.contains(where: { $0.1.contains { ($0["name"] as? String) == alias } }) else { throw StoreError.unknownAlias(alias) }
            let current = try snapshot(for: wallet, files: files)
            guard expected.wallet == wallet, expected.storageID == current.storageID,
                  expected.fingerprint == current.fingerprint else { throw StoreError.walletChanged(alias) }
            var updates: [(String, [[String: Any]])] = []
            for (file, entries) in files {
                let kept = entries.filter { ($0["name"] as? String) != alias }
                if kept.count != entries.count { updates.append((file, kept)) }
            }
            try commit(updates)
        }
    }

    func importWallets(from directory: URL) throws -> Int {
        let source = TezosClientStore(directory: directory)
        guard source.hasWallets else { return 0 }
        try PrivateFile.hardenDirectory(self.directory)
        return try withWalletLock {
            try recoverIfNeeded()
            let existing = Set(try readEntries(Self.publicKeyHashesFile).map(\.name))
            let incoming = try source.readEntries(Self.publicKeyHashesFile).map(\.name).filter { !existing.contains($0) }
            let accepted = Set(incoming)
            var copies: [(String, Data)] = []
            var merges: [(String, [[String: Any]])] = []
            for file in Self.walletFiles {
                let sourceURL = directory.appendingPathComponent(file)
                guard let data = try PrivateFile.read(sourceURL) else { continue }
                let target = self.directory.appendingPathComponent(file)
                if !FileManager.default.fileExists(atPath: target.path) {
                    // Cold start: take an exact copy of the file.
                    copies.append((file, data))
                } else {
                    // Merge: append only aliases we do not already have.
                    var entries = try readRaw(file)
                    let additions = try source.readRaw(file).filter { ($0["name"] as? String).map(accepted.contains) ?? false }
                    guard !additions.isEmpty else { continue }
                    entries.append(contentsOf: additions)
                    merges.append((file, entries))
                }
            }
            try commit(merges, raw: copies)
            return incoming.count
        }
    }

    /// The base58 secret key for `unencrypted:` and `encrypted:` entries (the caller supplies the
    /// password for the latter); `nil` for ledger, remote and watch-only aliases.
    func secretKey(for wallet: Wallet) throws -> String? {
        let (secretKeys, hashes) = try withWalletLock {
            try recoverIfNeeded()
            return (try index(readEntries(Self.secretKeysFile)), try index(readEntries(Self.publicKeyHashesFile)))
        }
        guard let locator = secretKeys[wallet.alias] as? String else { return nil }
        let found = (hashes[wallet.alias] as? String).map(Address.init)
        guard found == wallet.address else {
            throw StoreError.addressMismatch(alias: wallet.alias, expected: wallet.address, found: found)
        }
        for prefix in ["unencrypted:", "encrypted:"] where locator.hasPrefix(prefix) {
            return String(locator.dropFirst(prefix.count))
        }
        return nil
    }

    // MARK: - Parsing

    private struct Entry {
        let name: String
        let value: Any
    }

    private func readRaw(_ file: String) throws -> [[String: Any]] {
        let url = directory.appendingPathComponent(file)
        guard let data = try PrivateFile.read(url), !data.isEmpty else { return [] }
        guard let array = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw StoreError.malformed(file, "expected a JSON array of objects")
        }
        return array
    }

    private func readEntries(_ file: String) throws -> [Entry] {
        try readRaw(file).compactMap { object in
            guard let name = object["name"] as? String, let value = object["value"] else { return nil }
            return Entry(name: name, value: value)
        }
    }

    private func index(_ entries: [Entry]) -> [String: Any] {
        Dictionary(entries.map { ($0.name, $0.value) }, uniquingKeysWith: { first, _ in first })
    }

    private static func publicKey(from value: Any?) -> String? {
        if let object = value as? [String: Any], let key = object["key"] as? String {
            return key
        }
        if let locator = value as? String {
            // Older format: "unencrypted:edpk..." or a bare key.
            if let colon = locator.firstIndex(of: ":") { return String(locator[locator.index(after: colon)...]) }
            return locator
        }
        return nil
    }

    // MARK: - Writing

    /// A change to several files as one unit (S09). Before the first file is replaced, a journal
    /// records what every named file held (or that it did not exist); the journal is removed
    /// after the last replacement. Found at the start of any later read or write, it means the
    /// change was cut short, and the files are put back exactly as they were, so the three key
    /// files (and `contracts`) always agree with each other. Must be called under the lock.
    private func commit(_ updates: [(String, [[String: Any]])], raw: [(String, Data)] = []) throws {
        let payloads = try updates.map { ($0.0, try JSONSerialization.data(withJSONObject: $0.1, options: [.prettyPrinted, .withoutEscapingSlashes])) } + raw
        guard !payloads.isEmpty else { return }
        let names = payloads.map(\.0)
        guard Set(names).count == names.count, names.allSatisfy(Self.aliasFiles.contains) else { throw StoreError.malformed(Self.journalFile, "unexpected files in a transaction") }
        if payloads.count > 1 {
            var before: [String: Any] = [:]
            for name in names {
                before[name] = try PrivateFile.read(directory.appendingPathComponent(name)).map { $0.base64EncodedString() } ?? NSNull()
            }
            let journal = try JSONSerialization.data(withJSONObject: ["version": 1, "files": before])
            try PrivateFile.write(journal, to: directory.appendingPathComponent(Self.journalFile))
        }
        for (name, data) in payloads {
            try PrivateFile.write(data, to: directory.appendingPathComponent(name))
        }
        if payloads.count > 1 {
            try FileManager.default.removeItem(at: directory.appendingPathComponent(Self.journalFile))
            PrivateFile.syncDirectory(directory)
        }
    }

    /// Rolls back a change the journal says never finished. Must be called under the lock.
    private func recoverIfNeeded() throws {
        let url = directory.appendingPathComponent(Self.journalFile)
        guard let data = try PrivateFile.read(url) else { return }
        guard let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              object["version"] as? Int == 1, let files = object["files"] as? [String: Any] else {
            throw StoreError.malformed(Self.journalFile, "unreadable; an earlier change did not finish. Restore from a backup or remove the file by hand.")
        }
        for (name, previous) in files where Self.aliasFiles.contains(name) {
            let target = directory.appendingPathComponent(name)
            if let encoded = previous as? String, let bytes = Data(base64Encoded: encoded) {
                try PrivateFile.write(bytes, to: target)
            } else {
                try? FileManager.default.removeItem(at: target)
            }
        }
        try FileManager.default.removeItem(at: url)
        PrivateFile.syncDirectory(directory)
    }

    /// Holds the same advisory lock octez-client takes while it edits the wallet files.
    private func withWalletLock<T>(_ body: () throws -> T) throws -> T {
        try Self.withWalletLock(in: directory, body)
    }

    /// How long a caller waits for the lock before giving up; octez-client holds it for milliseconds.
    static let lockTimeout: TimeInterval = 5

    /// The wallet lock, tried rather than waited for, so the main actor is never blocked for
    /// good on a program that keeps it (S09). Readers and backups take it too.
    static func withWalletLock<T>(in directory: URL, _ body: () throws -> T) throws -> T {
        // No directory yet means no files and nobody else to lock out.
        guard FileManager.default.fileExists(atPath: directory.path) else { return try body() }
        let path = directory.appendingPathComponent(lockFile).path
        let fd = open(path, O_RDWR | O_CREAT | O_NOFOLLOW | O_CLOEXEC, 0o644)
        guard fd >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        defer { close(fd) }
        let deadline = Date().addingTimeInterval(lockTimeout)
        while lockf(fd, F_TLOCK, 0) != 0 {
            let busy = errno == EAGAIN || errno == EACCES
            guard busy, Date() < deadline else {
                throw busy ? StoreError.locked : POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            }
            usleep(50_000)
        }
        defer { _ = lockf(fd, F_ULOCK, 0) }
        return try body()
    }
}
