import Foundation

/// Key/value store the Octez Connect SDK persists its peers, permissions and seed in.
/// Synchronous because the bridge calls it from JavaScript on the bridge queue.
protocol BridgeStorage: Sendable {
    func get(_ key: String) -> String?
    func set(_ key: String, _ value: String)
    func delete(_ key: String)
}

/// A single JSON object in `<wallet directory>/octez-connect.json`, owner-readable only
/// (it contains the SDK's secret seed).
final class OctezConnectStorage: BridgeStorage, @unchecked Sendable {
    let url: URL
    private let lock = NSLock()
    private var values: [String: String]

    init(directory: URL = TezosClientStore.defaultDirectory) {
        url = directory.appendingPathComponent("octez-connect.json")
        if let data = try? Data(contentsOf: url), let stored = try? JSONDecoder().decode([String: String].self, from: data) {
            values = stored
        } else {
            values = [:]
        }
    }

    func get(_ key: String) -> String? { lock.withLock { values[key] } }

    func set(_ key: String, _ value: String) {
        lock.withLock {
            values[key] = value
            persist()
        }
    }

    func delete(_ key: String) {
        lock.withLock {
            values.removeValue(forKey: key)
            persist()
        }
    }

    private func persist() {
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true,
                                                    attributes: [.posixPermissions: 0o700])
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            try encoder.encode(values).write(to: url, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        } catch {
            NSLog("Signet: could not save Octez Connect state: %@", error.localizedDescription)
        }
    }
}

/// For tests and previews.
final class InMemoryBridgeStorage: BridgeStorage, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: String] = [:]
    func get(_ key: String) -> String? { lock.withLock { values[key] } }
    func set(_ key: String, _ value: String) { lock.withLock { values[key] = value } }
    func delete(_ key: String) { _ = lock.withLock { values.removeValue(forKey: key) } }
}
