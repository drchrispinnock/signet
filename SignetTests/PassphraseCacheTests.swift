import Foundation
import Testing
@testable import Signet

/// Remembered wallet passwords (Settings > Passwords): only a password found to open the key is
/// kept, only for that key and only until its time is up; an operation then signs without one
/// being typed; zero minutes, Forget and a wrong password leave nothing behind.
@MainActor
struct PassphraseCacheTests {
    static let address = Address("tz1VSUr8wwNhLAzempoch5d6hLRiTh8Cjcjb")

    @Test func entriesBelongToOneKeyAndExpire() {
        let cache = PassphraseCache()
        let now = Date()
        cache.store("pw", for: Self.address, encryptedKey: "edeskA", minutes: 5, now: now)
        #expect(cache.passphrase(for: Self.address, encryptedKey: "edeskA", now: now) == "pw")
        #expect(cache.expiry(for: Self.address, now: now) == now.addingTimeInterval(300))
        // Five minutes on, it is gone.
        #expect(cache.passphrase(for: Self.address, encryptedKey: "edeskA", now: now.addingTimeInterval(301)) == nil)
        #expect(cache.isEmpty)
        // Another key under the same account drops the entry rather than answering with it.
        cache.store("pw", for: Self.address, encryptedKey: "edeskA", minutes: 5, now: now)
        #expect(cache.passphrase(for: Self.address, encryptedKey: "edeskB", now: now) == nil && cache.isEmpty)
        // Zero minutes or an empty password: nothing kept.
        cache.store("pw", for: Self.address, encryptedKey: "edeskA", minutes: 0, now: now)
        cache.store("", for: Self.address, encryptedKey: "edeskA", minutes: 5, now: now)
        #expect(cache.isEmpty)
        cache.store("pw", for: Self.address, encryptedKey: "edeskA", minutes: 5, now: now)
        cache.forgetAll()
        #expect(cache.isEmpty)
    }

    func makeModel(minutes: Int) throws -> (WalletViewModel, Wallet) {
        let store = InMemoryWalletStore()
        let wallet = Wallet(alias: "Vault", address: Self.address, keyKind: .encrypted)
        try store.add(wallet, secretKey: "edeskSAMPLE")
        let model = WalletViewModel(chain: MockChainService(), walletStore: store, stateStore: InMemoryAppStateStore(), passwordCacheMinutes: { minutes })
        return (model, try #require(model.wallets.first))
    }

    /// The check runs in the background (the bridge decrypts); wait for it a little.
    func settle(_ model: WalletViewModel, _ wallet: Wallet) async {
        for _ in 0..<100 where model.needsPassphrase(for: wallet) { try? await Task.sleep(for: .milliseconds(10)) }
    }

    @Test func aRightPasswordIsRememberedAndUsedByTheNextOperation() async throws {
        let (model, wallet) = try makeModel(minutes: 10)
        #expect(model.needsPassphrase(for: wallet))
        _ = try model.signingKey(for: wallet, passphrase: "correct horse")
        await settle(model, wallet)
        #expect(!model.needsPassphrase(for: wallet) && model.rememberedPassphraseExpiry(for: wallet) != nil)
        guard case .secret(_, let used, _)? = try model.signingKey(for: wallet, passphrase: nil) else { Issue.record("no key"); return }
        #expect(used == "correct horse")
        // A real operation with no password typed (the mock refuses any other password).
        let request = TokenTransferRequest(to: Address("tz1dCaMnnMJk76UodjewCK67ABiXWjcKj73N"), transfers: [TokenTransfer(contract: "KT1RJ6PbjHpwc3M5rw5s2Nbmefwbuwbdxton", tokenId: "1", amount: "1")])
        let approved = try await model.estimateTokenTransfer(request, on: 1)
        _ = try await model.transferTokens(request, on: 1, approved: approved, passphrase: nil)
        // Forget brings the question back.
        model.forgetRememberedPassphrases()
        #expect(model.needsPassphrase(for: wallet))
    }

    @Test func aWrongPasswordOrZeroMinutesKeepsNothing() async throws {
        let (model, wallet) = try makeModel(minutes: 10)
        _ = try model.signingKey(for: wallet, passphrase: "wrong")
        try await Task.sleep(for: .milliseconds(200))
        #expect(model.needsPassphrase(for: wallet))
        let (off, offWallet) = try makeModel(minutes: 0)
        _ = try off.signingKey(for: offWallet, passphrase: "correct horse")
        try await Task.sleep(for: .milliseconds(200))
        #expect(off.needsPassphrase(for: offWallet))
        // A clear key never needs one.
        #expect(!model.needsPassphrase(for: Wallet(alias: "c", address: Self.address, keyKind: .unencrypted)))
    }
}
