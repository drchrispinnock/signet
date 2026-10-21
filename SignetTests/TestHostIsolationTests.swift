import Foundation
import Testing
@testable import Signet

/// S24: the app that hosts these tests opens no real wallet, backup or dApp state.
@MainActor
struct TestHostIsolationTests {
    @Test func theTestHostModelTouchesNoRealState() {
        #expect(SignetApp.isTestHost)
        let model = SignetApp.makeModel(isTestHost: true)
        #expect(model.walletDirectory == nil)
        #expect(model.backupDirectory == nil)
        #expect(model.wallets.isEmpty)
        #expect(!model.dapps.isStarted)
        #expect(model.lastBackup == nil && model.lastBackupError == nil)
        // The artwork cache under ~/Library/Caches is a real path too.
        #expect(ArtworkCache.standard == nil)
    }
}
