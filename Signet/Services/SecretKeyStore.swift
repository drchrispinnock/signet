import Foundation
import Security

/// Where secret keys live. Keyed by address so a wallet can always find its key.
protocol SecretKeyStore: Sendable {
    func store(_ secretKey: String, for address: Address) throws
    func secretKey(for address: Address) throws -> String?
    func delete(for address: Address) throws
}

/// Secret keys in the user's login keychain, one generic-password item per address.
struct KeychainSecretKeyStore: SecretKeyStore {
    struct KeychainError: LocalizedError {
        let status: OSStatus
        var errorDescription: String? {
            let message = SecCopyErrorMessageString(status, nil) as String? ?? "unknown error"
            return "Keychain error \(status): \(message)"
        }
    }

    let service: String

    init(service: String = "org.tezos.signet.secret-keys") {
        self.service = service
    }

    func store(_ secretKey: String, for address: Address) throws {
        let data = Data(secretKey.utf8)
        let query = baseQuery(for: address)
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrLabel as String: "Signet key \(address.value)",
        ]
        var status = SecItemAdd(query.merging(attributes) { $1 } as CFDictionary, nil)
        if status == errSecDuplicateItem {
            status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        }
        guard status == errSecSuccess else { throw KeychainError(status: status) }
    }

    func secretKey(for address: Address) throws -> String? {
        var query = baseQuery(for: address)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        switch status {
        case errSecSuccess:
            guard let data = item as? Data else { return nil }
            return String(data: data, encoding: .utf8)
        case errSecItemNotFound:
            return nil
        default:
            throw KeychainError(status: status)
        }
    }

    func delete(for address: Address) throws {
        let status = SecItemDelete(baseQuery(for: address) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw KeychainError(status: status) }
    }

    private func baseQuery(for address: Address) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: address.value,
        ]
    }
}

/// For previews and tests. Nothing is persisted.
final class InMemorySecretKeyStore: SecretKeyStore, @unchecked Sendable {
    private let lock = NSLock()
    private var keys: [Address: String] = [:]

    init() {}

    func store(_ secretKey: String, for address: Address) throws {
        lock.withLock { keys[address] = secretKey }
    }

    func secretKey(for address: Address) throws -> String? {
        lock.withLock { keys[address] }
    }

    func delete(for address: Address) throws {
        _ = lock.withLock { keys.removeValue(forKey: address) }
    }
}
