import Foundation
import Testing
@testable import Signet

/// Starts the SDK from a copy of the real on-disk state (peers, rooms, preserved sync state),
/// which is what the app does on launch. Skips if there is no state file on this machine.
struct DAppStartupTests {
    @Test(.tags(.network), .timeLimit(.minutes(1)))
    func startsFromPersistedState() async throws {
        let url = TezosClientStore.defaultDirectory.appendingPathComponent("octez-connect.json")
        guard let data = try? Data(contentsOf: url), let saved = try? JSONDecoder().decode([String: String].self, from: data) else {
            print("no persisted Octez Connect state; skipping"); return
        }
        let storage = InMemoryBridgeStorage()
        for (k, v) in saved { storage.set(k, v) }

        _ = try? await TaquitoBridge.shared.call("octezConnectStop")
        TaquitoBridge.shared.storage = storage
        do {
            let result = try await TaquitoBridge.shared.call("octezConnectStart", ["Signet state test", "", true])
            #expect(result["started"] == .bool(true))
        } catch {
            let tail = TaquitoBridge.shared.consoleLines.suffix(25).joined(separator: "\n")
            Issue.record(Comment(rawValue: "start from persisted state failed: \(error.localizedDescription)\nconsole:\n\(tail)"))
        }
        try? await Task.sleep(for: .seconds(3))
        let lines = TaquitoBridge.shared.consoleLines
        #expect(lines.contains { $0.contains("/_matrix/client/r0/sync") }, Comment(rawValue: "no sync after start; console:\n" + lines.suffix(25).joined(separator: "\n")))
        _ = try? await TaquitoBridge.shared.call("octezConnectStop")
    }
}

@MainActor
struct DemoModeTests {
    @Test func demoKeepsAccountsInMemoryAndHasNoSigningSecrets() async throws {
        let model = WalletViewModel.demo()
        #expect(model.walletDirectory == nil)
        #expect(model.backupDirectory == nil)
        #expect(model.importableWalletCount == 0)
        let account = try #require(model.selectedWallet)
        #expect(try model.signingKey(for: account, passphrase: nil) == nil)
        await model.refresh()
        #expect(model.tezBalance?.spendable == Decimal(string: "1361.43"))
        #expect(model.tezBalance?.staked == 3000)
        try model.renameSelectedWallet(to: "Demo renamed")
        #expect(model.selectedWallet?.alias == "Demo renamed")
        #expect(WalletViewModel.demo().selectedWallet?.alias == "My Account")
    }
}
