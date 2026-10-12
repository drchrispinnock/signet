import Foundation

/// Signed operations are persisted before injection. This contains no secret keys, but retains
/// spendable signed bytes, so it uses the same private-file and wallet-lock policy as key state.
final class OperationJournal: @unchecked Sendable {
    private let directory: URL?
    private let lock = NSLock()
    private var memory: [String: String] = [:]
    init(directory: URL? = nil) { self.directory = directory }

    func read() throws -> String {
        try transaction { records in
            let data = try JSONSerialization.data(withJSONObject: records.values.map { try JSONSerialization.jsonObject(with: Data($0.utf8)) })
            return String(decoding: data, as: UTF8.self)
        }
    }

    func save(_ json: String) throws {
        guard json.utf8.count <= 1 << 20,
              let object = try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any],
              let hash = object["hash"] as? String, let bytes = object["signedBytes"] as? String,
              !hash.isEmpty, bytes.count <= 1 << 20, object["rpcURL"] is String else { throw CocoaError(.fileWriteUnknown) }
        try transaction { records in
            guard records[hash] != nil || records.count < 128 else { throw CocoaError(.fileWriteOutOfSpace) }
            for (otherHash, otherJSON) in records where otherHash != hash {
                let other = try JSONSerialization.jsonObject(with: Data(otherJSON.utf8)) as? [String: Any]
                if let source = object["source"] as? String, other?["source"] as? String == source,
                   (other?["chainID"] == nil || object["chainID"] == nil || other?["chainID"] as? String == object["chainID"] as? String) {
                    throw CocoaError(.fileWriteFileExists)
                }
            }
            records[hash] = json
        }
    }

    func remove(_ hash: String) throws { try transaction { $0.removeValue(forKey: hash); return () } }

    private func transaction<T>(_ body: (inout [String: String]) throws -> T) throws -> T {
        try lock.withLock {
            guard let directory else { return try body(&memory) }
            try PrivateFile.hardenDirectory(directory)
            return try TezosClientStore.withWalletLock(in: directory) {
                let url = directory.appendingPathComponent("pending_operations.json")
                let data = try PrivateFile.read(url)
                guard (data?.count ?? 0) <= 16 << 20 else { throw CocoaError(.fileReadTooLarge) }
                var records = try data.map { try JSONDecoder().decode([String: String].self, from: $0) } ?? [:]
                let result = try body(&records)
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.sortedKeys]
                try PrivateFile.write(try encoder.encode(records), to: url)
                return result
            }
        }
    }
}
