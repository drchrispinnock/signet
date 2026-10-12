import Foundation

/// A secret held only for this run of the app: a paper key imported for one session. The bytes
/// live in memory that is locked against being swapped out, are wiped when the key is forgotten
/// or the object goes away, and never touch the wallet directory or a backup.
///
/// What this cannot do: the key still has to be handed to the bridge as a string for the one
/// operation it signs, exactly like a key read from disk, and those copies are the runtime's.
/// Core dumps are switched off at launch (`SignetApp.init`); macOS crash reports contain no heap.
final class SessionSecret: @unchecked Sendable {
    private let buffer: UnsafeMutableRawBufferPointer
    private let count: Int
    private let locked: Bool

    init(_ secret: String) {
        let bytes = Array(secret.utf8)
        count = bytes.count
        buffer = .allocate(byteCount: max(count, 1), alignment: 1)
        buffer.copyBytes(from: bytes)
        locked = mlock(buffer.baseAddress, buffer.count) == 0
    }

    var value: String { String(decoding: UnsafeRawBufferPointer(rebasing: buffer[..<count]), as: UTF8.self) }

    /// Overwrites the secret with zeros; `value` is empty of meaning afterwards.
    func wipe() {
        _ = memset_s(buffer.baseAddress, buffer.count, 0, buffer.count)
    }

    deinit {
        wipe()
        if locked { munlock(buffer.baseAddress, buffer.count) }
        buffer.deallocate()
    }
}

/// The session-only accounts and their secrets: the in-memory counterpart of `WalletStore` for
/// paper keys. Aliases are unique here as in the directory; the model keeps the two sets apart.
@MainActor
final class SessionKeyStore {
    enum StoreError: LocalizedError {
        case addressMismatch(String)
        var errorDescription: String? {
            switch self {
            case .addressMismatch(let alias): "“\(alias)” no longer names the account it did."
            }
        }
    }

    private(set) var wallets: [Wallet] = []
    private var secrets: [String: SessionSecret] = [:]

    var isEmpty: Bool { wallets.isEmpty }

    /// Holds `secretKey` (clear or octez-encrypted base58) for `wallet`, marked session-only.
    func add(_ wallet: Wallet, secretKey: String) {
        var entry = wallet
        entry.isSessionOnly = true
        wallets.removeAll { $0.alias == entry.alias }
        wallets.append(entry)
        secrets[entry.alias]?.wipe()
        secrets[entry.alias] = SessionSecret(secretKey)
    }

    /// The secret for `wallet`, as long as its alias still maps to its address (a sheet's
    /// `Wallet` can outlive a rename), else `nil` when it is not a session key.
    func secretKey(for wallet: Wallet) throws -> String? {
        guard let stored = wallets.first(where: { $0.alias == wallet.alias }) else { return nil }
        guard stored.address == wallet.address else { throw StoreError.addressMismatch(wallet.alias) }
        return secrets[wallet.alias]?.value
    }

    func rename(alias: String, to newAlias: String) {
        guard let index = wallets.firstIndex(where: { $0.alias == alias }), let secret = secrets.removeValue(forKey: alias) else { return }
        wallets[index].alias = newAlias
        secrets[newAlias] = secret
    }

    /// Wipes the secret and drops the account.
    func remove(_ wallet: Wallet) {
        secrets.removeValue(forKey: wallet.alias)?.wipe()
        wallets.removeAll { $0.alias == wallet.alias }
    }

    func removeAll() {
        for secret in secrets.values { secret.wipe() }
        secrets = [:]
        wallets = []
    }
}
