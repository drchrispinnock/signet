import Foundation

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

        var errorDescription: String? {
            switch self {
            case .aliasExists(let alias): "An alias named “\(alias)” already exists in the tezos-client directory."
            case .unknownAlias(let alias): "No alias named “\(alias)” exists in the tezos-client directory."
            case .missingPublicKey(let alias): "Wallet “\(alias)” has no public key to write."
            case .malformed(let file, let detail): "\(file) in the tezos-client directory is malformed: \(detail)"
            }
        }
    }

    static let publicKeyHashesFile = "public_key_hashs"
    static let publicKeysFile = "public_keys"
    static let secretKeysFile = "secret_keys"
    static let lockFile = "wallet_lock"

    /// Signet's own wallet directory.
    static var defaultDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".signet", isDirectory: true)
    }

    /// Where octez-client keeps its wallet.
    static var octezClientDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".tezos-client", isDirectory: true)
    }

    static let walletFiles = [publicKeyHashesFile, publicKeysFile, secretKeysFile]

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
        let hashes = try readEntries(Self.publicKeyHashesFile)
        let publicKeys = try index(readEntries(Self.publicKeysFile))
        let secretKeys = try index(readEntries(Self.secretKeysFile))

        return hashes.compactMap { entry in
            guard let address = entry.value as? String else { return nil }
            return Wallet(
                alias: entry.name,
                address: Address(address),
                publicKey: Self.publicKey(from: publicKeys[entry.name]),
                keyKind: KeyKind(locator: secretKeys[entry.name] as? String)
            )
        }
    }

    func add(_ wallet: Wallet, secretKey: String) throws {
        guard let publicKey = wallet.publicKey else { throw StoreError.missingPublicKey(wallet.alias) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        try withWalletLock {
            var hashes = try readRaw(Self.publicKeyHashesFile)
            var publicKeys = try readRaw(Self.publicKeysFile)
            var secretKeys = try readRaw(Self.secretKeysFile)

            for list in [hashes, publicKeys, secretKeys] where list.contains(where: { ($0["name"] as? String) == wallet.alias }) {
                throw StoreError.aliasExists(wallet.alias)
            }

            hashes.append(["name": wallet.alias, "value": wallet.address.value])
            publicKeys.append(["name": wallet.alias, "value": ["locator": "unencrypted:\(publicKey)", "key": publicKey]])
            secretKeys.append(["name": wallet.alias, "value": KeyKind.locator(forSecretKey: secretKey)])

            try write(hashes, to: Self.publicKeyHashesFile)
            try write(publicKeys, to: Self.publicKeysFile)
            try write(secretKeys, to: Self.secretKeysFile)
        }
    }

    func addWatchOnly(_ wallet: Wallet) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        try withWalletLock {
            var hashes = try readRaw(Self.publicKeyHashesFile)
            let taken = try [hashes, readRaw(Self.publicKeysFile), readRaw(Self.secretKeysFile)]
                .contains { $0.contains { ($0["name"] as? String) == wallet.alias } }
            guard !taken else { throw StoreError.aliasExists(wallet.alias) }
            hashes.append(["name": wallet.alias, "value": wallet.address.value])
            try write(hashes, to: Self.publicKeyHashesFile)
        }
    }

    func rename(alias: String, to newAlias: String) throws {
        try withWalletLock {
            var files = try [Self.publicKeyHashesFile, Self.publicKeysFile, Self.secretKeysFile].map { ($0, try readRaw($0)) }
            let names = { (list: [[String: Any]]) in list.compactMap { $0["name"] as? String } }
            guard !files.contains(where: { names($0.1).contains(newAlias) }) else { throw StoreError.aliasExists(newAlias) }
            guard let hashes = files.first(where: { $0.0 == Self.publicKeyHashesFile }), names(hashes.1).contains(alias) else {
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
            for (file, entries) in files { try write(entries, to: file) }
        }
    }

    func importWallets(from directory: URL) throws -> Int {
        let source = TezosClientStore(directory: directory)
        guard source.hasWallets else { return 0 }
        try FileManager.default.createDirectory(at: self.directory, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        return try withWalletLock {
            let existing = Set(try readEntries(Self.publicKeyHashesFile).map(\.name))
            let incoming = try source.readEntries(Self.publicKeyHashesFile).map(\.name).filter { !existing.contains($0) }
            let accepted = Set(incoming)
            for file in Self.walletFiles {
                let sourceURL = directory.appendingPathComponent(file)
                guard FileManager.default.fileExists(atPath: sourceURL.path) else { continue }
                let target = self.directory.appendingPathComponent(file)
                if !FileManager.default.fileExists(atPath: target.path) {
                    // Cold start: take an exact copy of the file.
                    try FileManager.default.copyItem(at: sourceURL, to: target)
                    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: target.path)
                } else {
                    // Merge: append only aliases we do not already have.
                    var entries = try readRaw(file)
                    let additions = try source.readRaw(file).filter { ($0["name"] as? String).map(accepted.contains) ?? false }
                    guard !additions.isEmpty else { continue }
                    entries.append(contentsOf: additions)
                    try write(entries, to: file)
                }
            }
            return incoming.count
        }
    }

    /// The base58 secret key for `unencrypted:` and `encrypted:` entries (the caller supplies the
    /// password for the latter); `nil` for ledger, remote and watch-only aliases.
    func secretKey(for wallet: Wallet) throws -> String? {
        let secretKeys = try index(readEntries(Self.secretKeysFile))
        guard let locator = secretKeys[wallet.alias] as? String else { return nil }
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
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        let data = try Data(contentsOf: url)
        guard !data.isEmpty else { return [] }
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

    private func write(_ entries: [[String: Any]], to file: String) throws {
        let data = try JSONSerialization.data(withJSONObject: entries, options: [.prettyPrinted, .withoutEscapingSlashes])
        let target = directory.appendingPathComponent(file)
        let temporary = directory.appendingPathComponent(".\(file).\(UUID().uuidString).tmp")
        try data.write(to: temporary, options: [.atomic])
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: temporary.path)
        _ = try FileManager.default.replaceItemAt(target, withItemAt: temporary)
        // replaceItemAt keeps the original file's metadata, so re-apply the private mode.
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: target.path)
    }

    /// Holds the same advisory lock octez-client takes while it edits the wallet files.
    private func withWalletLock<T>(_ body: () throws -> T) throws -> T {
        let path = directory.appendingPathComponent(Self.lockFile).path
        let fd = open(path, O_RDWR | O_CREAT, 0o644)
        guard fd >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        defer { close(fd) }
        guard lockf(fd, F_LOCK, 0) == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        defer { _ = lockf(fd, F_ULOCK, 0) }
        return try body()
    }
}
