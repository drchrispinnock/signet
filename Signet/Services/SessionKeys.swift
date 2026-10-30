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
        #if canImport(Darwin)
        _ = memset_s(buffer.baseAddress, buffer.count, 0, buffer.count)
        #else
        explicit_bzero(buffer.baseAddress!, buffer.count)   // glibc and the BSDs; never optimised away
        #endif
    }

    deinit {
        wipe()
        if locked { munlock(buffer.baseAddress, buffer.count) }
        buffer.deallocate()
    }
}

/// The session-only accounts and their secrets: the in-memory counterpart of `WalletStore` for
/// paper keys. Aliases and addresses are unique here as in the directory; the model keeps the
/// two sets apart. Every entry has an identity of its own and a generation that each change
/// bumps, so a removal decided after an await (the password check) can be matched against the
/// exact entry it verified (S07): a renamed, replaced or re-imported account is never the one
/// that gets wiped.
@MainActor
final class SessionKeyStore {
    enum StoreError: LocalizedError {
        case aliasExists(String)
        case addressExists(String)
        case addressMismatch(String)
        case walletChanged(String)
        var errorDescription: String? {
            switch self {
            case .aliasExists(let alias): "An account named “\(alias)” already exists for this session."
            case .addressExists(let alias): "“\(alias)” already holds that address for this session."
            case .addressMismatch(let alias): "“\(alias)” no longer names the account it did."
            case .walletChanged(let alias):
                "Account “\(alias)” changed while removal was being confirmed. Nothing was removed; please try again."
            }
        }
    }

    /// What a removal was decided on: the entry's identity, its state at that moment and the
    /// secret the password was checked against. `remove(matching:)` takes only this.
    struct RemovalSnapshot: Sendable {
        fileprivate let id: UUID
        fileprivate let generation: Int
        let wallet: Wallet
        let secretKey: String
    }

    private struct Entry {
        let id = UUID()
        var wallet: Wallet
        var generation = 0
        let secret: SessionSecret
    }

    private var entries: [Entry] = []

    var wallets: [Wallet] { entries.map(\.wallet) }
    var isEmpty: Bool { entries.isEmpty }

    /// Holds `secretKey` (clear or octez-encrypted base58) for `wallet`, marked session-only.
    /// Never replaces an entry: a taken alias or address is refused.
    func add(_ wallet: Wallet, secretKey: String) throws {
        var entry = wallet
        entry.isSessionOnly = true
        if entries.contains(where: { $0.wallet.alias == entry.alias }) { throw StoreError.aliasExists(entry.alias) }
        if let taken = entries.first(where: { $0.wallet.address == entry.address }) { throw StoreError.addressExists(taken.wallet.alias) }
        entries.append(Entry(wallet: entry, secret: SessionSecret(secretKey)))
    }

    private func entry(for wallet: Wallet) throws -> Entry? {
        guard let stored = entries.first(where: { $0.wallet.alias == wallet.alias }) else { return nil }
        guard stored.wallet.address == wallet.address else { throw StoreError.addressMismatch(wallet.alias) }
        return stored
    }

    /// The secret for `wallet`, as long as its alias still maps to its address (a sheet's
    /// `Wallet` can outlive a rename), else `nil` when it is not a session key.
    func secretKey(for wallet: Wallet) throws -> String? {
        try entry(for: wallet)?.secret.value
    }

    /// The entry `wallet` names right now, pinned for a later `remove(matching:)`; `nil` when it
    /// is not a session key.
    func removalSnapshot(for wallet: Wallet) throws -> RemovalSnapshot? {
        guard let stored = try entry(for: wallet) else { return nil }
        return RemovalSnapshot(id: stored.id, generation: stored.generation, wallet: stored.wallet, secretKey: stored.secret.value)
    }

    func rename(alias: String, to newAlias: String) throws {
        guard let index = entries.firstIndex(where: { $0.wallet.alias == alias }) else { return }
        guard !entries.contains(where: { $0.wallet.alias == newAlias }) else { throw StoreError.aliasExists(newAlias) }
        entries[index].wallet.alias = newAlias
        entries[index].generation += 1
    }

    /// Wipes the secret and drops the account, but only the very entry the snapshot was taken
    /// of, unchanged since: same identity, generation, account and secret.
    func remove(matching snapshot: RemovalSnapshot) throws {
        guard let index = entries.firstIndex(where: { $0.id == snapshot.id }),
              entries[index].generation == snapshot.generation,
              entries[index].wallet == snapshot.wallet,
              entries[index].secret.value == snapshot.secretKey
        else { throw StoreError.walletChanged(snapshot.wallet.alias) }
        entries[index].secret.wipe()
        entries.remove(at: index)
    }

    func removeAll() {
        for entry in entries { entry.secret.wipe() }
        entries = []
    }
}
