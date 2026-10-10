import CryptoKit
import Foundation

/// Backup preferences. Like the wallet directory pointer these live in the app's preferences.
struct BackupSettings: @unchecked Sendable {
    static let directoryKey = "backupDirectory"
    static let generationsKey = "backupGenerations"
    static let defaultGenerations = 10
    static let generationRange = 1...100

    let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var defaultDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".signet_backups", isDirectory: true)
    }

    var directory: URL {
        guard let path = defaults.string(forKey: Self.directoryKey), !path.isEmpty else { return defaultDirectory }
        return URL(fileURLWithPath: (path as NSString).expandingTildeInPath, isDirectory: true)
    }

    var generations: Int {
        let value = defaults.integer(forKey: Self.generationsKey)
        return Self.generationRange.contains(value) ? value : Self.defaultGenerations
    }

    func setDirectory(_ url: URL) {
        if url.standardizedFileURL == defaultDirectory.standardizedFileURL {
            defaults.removeObject(forKey: Self.directoryKey)
        } else {
            defaults.set(url.standardizedFileURL.path, forKey: Self.directoryKey)
        }
    }

    func setGenerations(_ count: Int) {
        let clamped = min(max(count, Self.generationRange.lowerBound), Self.generationRange.upperBound)
        if clamped == Self.defaultGenerations {
            defaults.removeObject(forKey: Self.generationsKey)
        } else {
            defaults.set(clamped, forKey: Self.generationsKey)
        }
    }
}

/// Copies the wallet files into a timestamped generation folder and prunes old generations.
///
/// Only generations Signet made are ever deleted: each carries a `.signet-backup` manifest, and
/// pruning skips anything else in the folder (another wallet's backups, a user's documents, a
/// symlink). Generations without a valid ownership manifest are preserved.
struct WalletBackup: Sendable {
    enum Outcome: Equatable, Sendable {
        /// A new generation was written here.
        case created(URL)
        /// The latest generation already matches the wallet files byte for byte.
        case unchanged(latest: URL)
        /// The wallet directory has no wallet files yet.
        case nothingToBackUp
    }

    enum BackupError: LocalizedError, Equatable {
        /// The backup folder is the wallet directory, inside it, or contains it.
        case overlapsWallet(backup: URL, wallet: URL)

        var errorDescription: String? {
            switch self {
            case .overlapsWallet(let backup, let wallet):
                "The backup folder \(backup.path) overlaps the wallet directory \(wallet.path). Choose a separate folder for backups."
            }
        }
    }

    /// Generation folders are named so lexical order is chronological order.
    static let stampFormat: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(secondsFromGMT: 0)
        f.dateFormat = "yyyy-MM-dd'T'HHmmss'Z'"
        return f
    }()

    /// What a generation folder is named: the stamp, optionally `-2`, `-3`… when one second holds several.
    static var stampPattern: Regex<(Substring, Substring?)> { /[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{6}Z(-[0-9]+)?/ }

    /// Written into every generation; its presence is what marks the folder as ours to prune.
    static let manifestFile = ".signet-backup"

    struct Manifest: Codable, Equatable, Sendable {
        static let currentVersion = 1
        var version = Manifest.currentVersion
        var created: Date
        /// The wallet directory the generation was taken from.
        var source: String
        var files: [String]
    }

    let walletDirectory: URL
    let backupDirectory: URL
    let generations: Int

    /// Files worth saving: the three octez-client wallet files, named contracts, Signet's state
    /// and multisig proposals in flight.
    static let files = TezosClientStore.walletFiles + [TezosClientStore.contractsFile, "state", FileMultisigProposalStore.fileName]

    /// Any of these present means there is something to back up (`state` alone is not worth a generation).
    static let valuableFiles = TezosClientStore.walletFiles + [TezosClientStore.contractsFile, FileMultisigProposalStore.fileName]

    /// - Parameter force: write a generation even if the latest one already matches (explicit user action).
    func run(now: Date = Date(), force: Bool = false) throws -> Outcome {
        let present = Self.files.filter { FileManager.default.fileExists(atPath: walletDirectory.appendingPathComponent($0).path) }
        guard present.contains(where: Self.valuableFiles.contains) else { return .nothingToBackUp }
        try Self.checkSeparate(backup: backupDirectory, wallet: walletDirectory)

        let fm = FileManager.default
        try fm.createDirectory(at: backupDirectory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])

        let existing = try Self.generations(in: backupDirectory, source: walletDirectory)
        if !force, let latest = existing.last, try Self.fingerprint(of: walletDirectory) == Self.fingerprint(of: latest) {
            try prune(existing)
            return .unchanged(latest: latest)
        }

        var stamp = Self.stampFormat.string(from: now)
        var target = backupDirectory.appendingPathComponent(stamp, isDirectory: true)
        var suffix = 1
        while fm.fileExists(atPath: target.path) {
            suffix += 1
            stamp = Self.stampFormat.string(from: now) + "-\(suffix)"
            target = backupDirectory.appendingPathComponent(stamp, isDirectory: true)
        }

        // Build in a temporary folder and rename into place so a half-written generation never counts.
        let staging = backupDirectory.appendingPathComponent(".\(stamp).partial", isDirectory: true)
        try? fm.removeItem(at: staging)
        try fm.createDirectory(at: staging, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        for file in present {
            let destination = staging.appendingPathComponent(file)
            try fm.copyItem(at: walletDirectory.appendingPathComponent(file), to: destination)
            try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: destination.path)
        }
        let manifest = Manifest(created: now, source: Self.normalized(walletDirectory).path, files: present)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let manifestURL = staging.appendingPathComponent(Self.manifestFile)
        try encoder.encode(manifest).write(to: manifestURL, options: .atomic)
        try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: manifestURL.path)
        try fm.moveItem(at: staging, to: target)

        let created = Self.normalized(target)
        try prune(existing + [created])
        return .created(created)
    }

    /// The backup folder must be neither the wallet directory, nor inside it, nor around it:
    /// a generation inside the wallet would be backed up into itself, and pruning around the
    /// wallet could never be made safe.
    static func checkSeparate(backup: URL, wallet: URL) throws {
        let b = normalized(backup).standardizedFileURL.path
        let w = normalized(wallet).standardizedFileURL.path
        if b == w || b.hasPrefix(w + "/") || w.hasPrefix(b + "/") { throw BackupError.overlapsWallet(backup: backup, wallet: wallet) }
    }

    /// Generation folders Signet owns, oldest first. Anything else in the folder is left alone.
    static func generations(in directory: URL, source: URL? = nil) throws -> [URL] {
        guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey], options: [.skipsHiddenFiles])
            .filter { url in
                let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
                return values?.isDirectory == true && values?.isSymbolicLink != true && isGeneration(url, source: source)
            }
            .map(normalized)
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    /// Recognize only complete, supported manifests. Legacy folders have no provable owner.
    static func isGeneration(_ url: URL, source: URL? = nil) -> Bool {
        guard url.lastPathComponent.wholeMatch(of: stampPattern) != nil,
              let manifest = manifest(of: url), manifest.version == Manifest.currentVersion,
              manifest.source.hasPrefix("/"), !manifest.files.isEmpty,
              Set(manifest.files).count == manifest.files.count,
              manifest.files.allSatisfy({ files.contains($0) }),
              manifest.files.contains(where: valuableFiles.contains) else { return false }
        if let source, manifest.source != normalized(source).path { return false }
        guard let contents = try? FileManager.default.contentsOfDirectory(atPath: url.path),
              Set(contents) == Set(manifest.files + [manifestFile]) else { return false }
        return contents.allSatisfy { name in
            let values = try? url.appendingPathComponent(name).resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            return values?.isRegularFile == true && values?.isSymbolicLink != true
        }
    }

    static func manifest(of generation: URL) -> Manifest? {
        guard let data = try? Data(contentsOf: generation.appendingPathComponent(manifestFile)) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(Manifest.self, from: data)
    }

    /// Directory listings can come back as `/private/var/...` while callers built `/var/...`;
    /// resolve symlinks so generation URLs compare equal.
    static func normalized(_ url: URL) -> URL {
        URL(fileURLWithPath: url.resolvingSymlinksInPath().path, isDirectory: true)
    }

    private func prune(_ generations: [URL]) throws {
        let sorted = generations.sorted { $0.lastPathComponent < $1.lastPathComponent }
        guard sorted.count > self.generations else { return }
        let root = Self.normalized(backupDirectory).standardizedFileURL.path
        for old in sorted.prefix(sorted.count - self.generations) {
            // Re-check right before deleting: still directly under our folder, still a generation of ours.
            let path = old.standardizedFileURL.path
            guard path.hasPrefix(root + "/"), old.deletingLastPathComponent().standardizedFileURL.path == root,
                  (try? old.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) != true,
                  Self.isGeneration(old, source: walletDirectory) else { continue }
            try FileManager.default.removeItem(at: old)
        }
    }

    /// SHA-256 over each saved file's name and contents, so identical wallets compare equal.
    static func fingerprint(of directory: URL) throws -> Data {
        var hasher = SHA256()
        for file in files {
            let url = directory.appendingPathComponent(file)
            guard FileManager.default.fileExists(atPath: url.path) else { continue }
            hasher.update(data: Data(file.utf8))
            hasher.update(data: try Data(contentsOf: url))
        }
        return Data(hasher.finalize())
    }
}
