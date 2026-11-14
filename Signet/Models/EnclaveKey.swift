import Foundation

/// A P-256 key that lives in this Mac's Secure Enclave. What we hold is the Enclave's own
/// wrapped form of it: an opaque blob only this machine's Enclave can use, and only to sign
/// after the user has authenticated. The secret itself never exists outside the Enclave, so
/// the key cannot be exported, backed up or moved to another machine.
///
/// The `secret_keys` locator is `signet-enclave:<base64 blob>`, so the wallet directory stays
/// self-contained; a copy of it elsewhere (a backup, another Mac) holds nothing usable.
struct EnclaveKey: Hashable, Codable, Sendable {
    static let scheme = "signet-enclave"

    let blob: Data

    init(blob: Data) {
        self.blob = blob
    }

    init?(base64: String) {
        guard let blob = Data(base64Encoded: base64), !blob.isEmpty, blob.count <= 4096 else { return nil }
        self.blob = blob
    }

    init?(locator: String) {
        let prefix = Self.scheme + ":"
        guard locator.lowercased().hasPrefix(prefix) else { return nil }
        self.init(base64: String(locator.dropFirst(prefix.count)))
    }

    var base64: String { blob.base64EncodedString() }
    var locator: String { Self.scheme + ":" + base64 }
}
