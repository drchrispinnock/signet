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
struct WalletBackup: Sendable {
    enum Outcome: Equatable, Sendable {
        /// A new generation was written here.
        case created(URL)
        /// The latest generation already matches the wallet files byte for byte.
        case unchanged(latest: URL)
        /// The wallet directory has no wallet files yet.
        case nothingToBackUp
    }

    /// Generation folders are named so lexical order is chronological order.
    static let stampFormat: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(secondsFromGMT: 0)
        f.dateFormat = "yyyy-MM-dd'T'HHmmss'Z'"
        return f
    }()

    let walletDirectory: URL
    let backupDirectory: URL
    let generations: Int

    /// Files worth saving: the three octez-client wallet files plus Signet's state.
    static let files = TezosClientStore.walletFiles + ["state"]

    /// - Parameter force: write a generation even if the latest one already matches (explicit user action).
    func run(now: Date = Date(), force: Bool = false) throws -> Outcome {
        let present = Self.files.filter { FileManager.default.fileExists(atPath: walletDirectory.appendingPathComponent($0).path) }
        guard present.contains(TezosClientStore.publicKeyHashesFile) else { return .nothingToBackUp }

        let fm = FileManager.default
        try fm.createDirectory(at: backupDirectory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])

        let existing = try Self.generations(in: backupDirectory)
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
        try fm.moveItem(at: staging, to: target)

        let created = Self.normalized(target)
        try prune(existing + [created])
        return .created(created)
    }

    /// Generation folders, oldest first.
    static func generations(in directory: URL) throws -> [URL] {
        guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
            .map(normalized)
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    /// Directory listings can come back as `/private/var/...` while callers built `/var/...`;
    /// resolve symlinks so generation URLs compare equal.
    static func normalized(_ url: URL) -> URL {
        URL(fileURLWithPath: url.resolvingSymlinksInPath().path, isDirectory: true)
    }

    private func prune(_ generations: [URL]) throws {
        let sorted = generations.sorted { $0.lastPathComponent < $1.lastPathComponent }
        guard sorted.count > self.generations else { return }
        for old in sorted.prefix(sorted.count - self.generations) {
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
