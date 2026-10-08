import Foundation
import Testing
@testable import Signet

struct DAppPairingLinkTests {
    @Test func parsesTheBeaconDesktopLinkShape() throws {
        // What the dApp's wallet list opens: deepLink + "?type=tzip10&data=" + payload.
        #expect(DAppPairingLink.code(from: URL(string: "signet://?type=tzip10&data=3NDiBB3dPSCeiHnjoaHprF")!) == "3NDiBB3dPSCeiHnjoaHprF")
        #expect(DAppPairingLink.code(from: URL(string: "signet://pair?data=abc&type=TZIP10")!) == "abc")
        #expect(DAppPairingLink.code(from: URL(string: "signet://?type=tzip10&data=a%2Bb%3D")!) == "a+b=")
        #expect(DAppPairingLink.code(from: URL(string: "signet://?type=other&data=abc")!) == nil)
        #expect(DAppPairingLink.code(from: URL(string: "signet://?type=tzip10")!) == nil)
        #expect(DAppPairingLink.code(from: URL(string: "https://example.com/?type=tzip10&data=abc")!) == nil)
        let roundTrip = DAppPairingLink.url(for: "xyz+1")
        #expect(roundTrip.scheme == "signet")
        #expect(DAppPairingLink.code(from: roundTrip) == "xyz+1")
    }

    @Test @MainActor func incomingLinkOpensTheConnectSheetWithTheCode() {
        let model = WalletViewModel(wallets: WalletViewModel.sampleWallets, chain: MockChainService())
        model.handleIncomingURL(URL(string: "signet://?type=tzip10&data=CODE123")!)
        #expect(model.isPresentingConnectDApp)
        #expect(model.pendingPairingCode == "CODE123")
        model.handleIncomingURL(URL(string: "signet://?nope=1")!)
        #expect(model.errorMessage?.contains("understand") == true)
    }
}
