#if canImport(CryptoKit)
import CryptoKit
#else
import Crypto
#endif
import Foundation

/// Settings > Passwords: how many minutes (0 to 60) a wallet password, once typed and found to
/// open the key, is remembered. 0 (the default) remembers nothing, as before. In UserDefaults;
/// the test host shares the app's defaults, so under it the stored value is ignored.
enum PasswordCacheSettings {
    static let key = "passwordCacheMinutes"
    static let range = 0...60

    static func minutes(_ defaults: UserDefaults = .standard) -> Int {
        if defaults == .standard, SignetApp.isTestHost { return 0 }
        return min(max(defaults.integer(forKey: key), range.lowerBound), range.upperBound)
    }
}

/// Wallet passwords remembered for a few minutes so they need not be typed for every
/// operation. Memory only: each password sits in locked memory (`SessionSecret`) that is wiped
/// when it expires, is forgotten, or the cache goes away; nothing is written anywhere. An entry
/// belongs to one account and to the exact encrypted key it opened (a SHA-256 of it), so a key
/// changed on disk is never handed a password that was right for the old one. The time is fixed
/// from when the password was typed: using it does not extend it.
@MainActor
final class PassphraseCache {
    private struct Entry {
        let secret: SessionSecret
        let keyDigest: String
        let expires: Date
    }

    private var entries: [String: Entry] = [:]
    /// Called whenever an entry appears or goes, so views can redraw their password fields.
    var onChange: (() -> Void)?

    static func digest(of encryptedKey: String) -> String {
        SHA256.hash(data: Data(encryptedKey.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    /// When the account's remembered password expires, or `nil` when there is none.
    func expiry(for address: Address, now: Date = Date()) -> Date? {
        guard let entry = entries[address.value] else { return nil }
        guard entry.expires > now else { forget(address); return nil }
        return entry.expires
    }

    /// The remembered password, only for the encrypted key it was found to open. A different
    /// key drops the entry and answers `nil`.
    func passphrase(for address: Address, encryptedKey: String, now: Date = Date()) -> String? {
        guard let entry = entries[address.value] else { return nil }
        guard entry.expires > now, entry.keyDigest == Self.digest(of: encryptedKey) else { forget(address); return nil }
        return entry.secret.value
    }

    /// Remembers `passphrase` for `minutes` from now (nothing for 0) and wipes it when they are up.
    func store(_ passphrase: String, for address: Address, encryptedKey: String, minutes: Int, now: Date = Date()) {
        guard minutes > 0, !passphrase.isEmpty else { return }
        entries[address.value]?.secret.wipe()
        let expires = now.addingTimeInterval(TimeInterval(minutes) * 60)
        entries[address.value] = Entry(secret: SessionSecret(passphrase), keyDigest: Self.digest(of: encryptedKey), expires: expires)
        onChange?()
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(max(0, expires.timeIntervalSinceNow) + 0.5))
            self?.purgeExpired()
        }
    }

    func forget(_ address: Address) {
        guard let entry = entries.removeValue(forKey: address.value) else { return }
        entry.secret.wipe()
        onChange?()
    }

    func forgetAll() {
        guard !entries.isEmpty else { return }
        for entry in entries.values { entry.secret.wipe() }
        entries = [:]
        onChange?()
    }

    func purgeExpired(now: Date = Date()) {
        for (address, entry) in entries where entry.expires <= now { forget(Address(address)) }
    }

    var isEmpty: Bool { entries.isEmpty }
}
