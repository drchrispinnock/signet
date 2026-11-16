#if canImport(AppKit)
import AppKit
#endif
import Foundation
import Testing
@testable import Signet

/// Scan QR code: what a scanned text is taken for, and where the model sends it.
struct QRScanTests {
    private static let address = "tz1VSUr8wwNhLAzempoch5d6hLRiTh8Cjcjb"
    private static let secretKey = Base58.checkEncode(prefix: TezosPrefix.edsk, payload: [UInt8](repeating: 7, count: 32))
    private static let publicKey = Base58.checkEncode(prefix: TezosPrefix.edpk, payload: [UInt8](repeating: 9, count: 32))
    private static let pairingCode = Base58.checkEncode(prefix: [], payload: Array(#"{"type":"p2p-pairing-request","name":"dApp"}"#.utf8))
    private static let phrase = Array(repeating: "abandon", count: 11).joined(separator: " ") + " about"

    @Test func classifiesAddresses() {
        #expect(QRPayload.classify(Self.address) == .address(Address(Self.address)))
        #expect(QRPayload.classify("  \(Self.address)\n") == .address(Address(Self.address)))
        #expect(QRPayload.classify("tezos:\(Self.address)") == .address(Address(Self.address)))
        #expect(QRPayload.classify("tezos://\(Self.address)") == .address(Address(Self.address)))
        #expect(QRPayload.classify("KT1AXRU3wLc87WNhLhVGrgqDGubLACUMUgPb") == .address(Address("KT1AXRU3wLc87WNhLhVGrgqDGubLACUMUgPb")))
        // One wrong character breaks the checksum.
        #expect(QRPayload.classify("tz1VSUr8wwNhLAzempoch5d6hLRiTh8Cjcjc") == .unknown)
    }

    @Test func classifiesKeys() {
        #expect(Self.secretKey.hasPrefix("edsk"))
        #expect(Self.publicKey.hasPrefix("edpk"))
        #expect(QRPayload.classify(Self.secretKey) == .secretKey(Self.secretKey))
        #expect(QRPayload.classify(Self.publicKey) == .publicKey(Self.publicKey))
        #expect(QRPayload.classify(Self.secretKey).isSecret)
        #expect(!QRPayload.classify(Self.publicKey).isSecret)
        // The right letters without a valid checksum are nothing.
        #expect(QRPayload.classify("edsk" + String(repeating: "a", count: 50)) == .unknown)
        #expect(QRPayload.classify("edpk" + String(repeating: "a", count: 50)) == .unknown)
    }

    @Test func classifiesRecoveryPhrases() {
        #expect(QRPayload.classify(Self.phrase) == .recoveryPhrase(Self.phrase))
        #expect(QRPayload.classify(Self.phrase.replacingOccurrences(of: " ", with: "\n  ")) == .recoveryPhrase(Self.phrase))
        #expect(QRPayload.classify(Self.phrase).isSecret)
        #expect(QRPayload.classify("abandon abandon abandon") == .unknown)
        #expect(QRPayload.classify(Self.phrase.replacingOccurrences(of: "about", with: "About1")) == .unknown)
    }

    @Test func classifiesPairingCodes() {
        #expect(QRPayload.classify(Self.pairingCode) == .pairing(code: Self.pairingCode))
        #expect(QRPayload.classify("tezos://?type=tzip10&data=\(Self.pairingCode)") == .pairing(code: Self.pairingCode))
        #expect(QRPayload.classify("signet://?type=tzip10&data=CODE") == .pairing(code: "CODE"))
        #expect(QRPayload.classify("https://wallet.example/?type=tzip10&data=CODE") == .pairing(code: "CODE"))
        #expect(QRPayload.classify("https://example.com/?type=other&data=CODE") == .unknown)
        // The signet:// handler itself still takes its own scheme only.
        #expect(DAppPairingLink.code(from: URL(string: "tezos://?type=tzip10&data=CODE")!) == nil)
    }

    @Test func collectsThePartsOfALongKey() {
        // A tz5 secret key: the mdsk prefix and 3872 bytes.
        let key = Base58.checkEncode(prefix: [9, 57, 116, 57], payload: (0..<3872).map { UInt8(truncatingIfNeeded: $0 &* 13) })
        #expect(key.hasPrefix("mdsk"))
        let parts = KeyPart.split(key, chunkLength: 1400)
        #expect(parts.count == 4)
        #expect(Set(parts.map(\.id)).count == 1)
        #expect(parts.allSatisfy { QRPayload.classify($0.text) == .keyPart($0) && QRPayload.classify($0.text).isSecret })
        #expect(KeyPart.split("short").isEmpty)

        var collector = KeyPartCollector()
        #expect(collector.isEmpty)
        #expect(collector.add(parts[2]) == .needMore)
        #expect(collector.add(parts[2]) == .needMore)
        #expect(collector.missing == [1, 2, 4] && collector.received == 1 && collector.count == 4)
        #expect(collector.add(parts[0]) == .needMore)
        #expect(collector.add(parts[3]) == .needMore)
        #expect(collector.add(parts[1]) == .complete(key))
        #expect(collector.isEmpty)

        // A part of another key starts over rather than mixing the two.
        let other = KeyPart.split(Base58.checkEncode(prefix: [9, 57, 116, 57], payload: [UInt8](repeating: 9, count: 3872)), chunkLength: 1400)
        #expect(collector.add(parts[0]) == .needMore)
        #expect(collector.add(other[1]) == .needMore)
        #expect(collector.missing == [1, 3, 4])

        // Parts that claim one id but do not make that key are refused.
        var forged = KeyPartCollector()
        let swapped = [parts[0], KeyPart(index: 2, count: 4, id: parts[0].id, chunk: parts[2].chunk), parts[2], parts[3]]
        #expect(swapped.map { forged.add($0) }.last == .invalid)
        #expect(forged.isEmpty)
    }

    @Test func refusesMalformedKeyParts() {
        for text in ["signet-key:", "signet-key:1/1:abcdef12:abc", "signet-key:0/3:abcdef12:abc", "signet-key:4/3:abcdef12:abc",
                     "signet-key:1/99:abcdef12:abc", "signet-key:1/3:xyz:abc", "signet-key:1/3:abcdef12:", "signet-key:1/3:abcdef12:a b",
                     "signet-key:1/3:abcdef12:abc:def", "signet-key:one/3:abcdef12:abc"] {
            #expect(QRPayload.classify(text) == .unknown, "\(text)")
        }
        #expect(QRPayload.classify("signet-key:2/3:abcdef12:abc") == .keyPart(KeyPart(index: 2, count: 3, id: "abcdef12", chunk: "abc")))
    }

    @Test func refusesEverythingElse() {
        #expect(QRPayload.classify("") == .unknown)
        #expect(QRPayload.classify("https://example.com") == .unknown)
        #expect(QRPayload.classify("hello world") == .unknown)
        #expect(QRPayload.classify(String(repeating: "1", count: QRPayload.maximumLength + 1)) == .unknown)
        // Valid base58check that is neither a key nor a pairing request.
        #expect(QRPayload.classify(Base58.checkEncode(prefix: [], payload: Array("plain text".utf8))) == .unknown)
    }

    @Test func readsAScannedImageBackToItsPayload() throws {
        let image = try #require(QRCode.image(for: Self.secretKey, size: 300))
        #expect(QRCode.decode(image).map(QRPayload.classify) == .secretKey(Self.secretKey))
    }

    #if canImport(AppKit)
    @Test @MainActor func readsTheClipboardAsImageOrText() throws {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("signet-qr-test-\(UUID().uuidString)"))
        defer { pasteboard.releaseGlobally() }
        pasteboard.clearContents()
        #expect(QRCamera.textFromPasteboard(pasteboard) == nil)
        pasteboard.setString(Self.address, forType: .string)
        #expect(QRCamera.textFromPasteboard(pasteboard) == Self.address)
        pasteboard.clearContents()
        pasteboard.writeObjects([try #require(QRCode.image(for: Self.address, size: 300))])
        #expect(QRCamera.textFromPasteboard(pasteboard) == Self.address)
    }
    #endif

    @Test @MainActor func routesAScanToTheSheetThatHandlesIt() {
        let model = WalletViewModel(wallets: WalletViewModel.sampleWallets, chain: MockChainService())
        #expect(!model.hasCamera)
        model.routePendingScan()
        #expect(!model.isPresentingConnectDApp && !model.isPresentingImportAccount && !model.isPresentingAddAddress && !model.isPresentingSend)

        model.pendingScan = .pair(code: "CODE")
        model.routePendingScan()
        #expect(model.pendingScan == nil)
        #expect(model.isPresentingConnectDApp && model.pendingPairingCode == "CODE")

        model.pendingScan = .importKey(.secretKey(Self.secretKey))
        model.routePendingScan()
        #expect(model.isPresentingImportAccount && model.importPrefill == .secretKey(Self.secretKey))

        model.pendingScan = .importKey(.recoveryPhrase(Self.phrase))
        model.routePendingScan()
        #expect(model.importPrefill == .recoveryPhrase(Self.phrase))

        model.pendingScan = .addAddress(Address(Self.address))
        model.routePendingScan()
        #expect(model.isPresentingAddAddress && model.addAddressPrefill == Address(Self.address))

        model.pendingScan = .send(Address(Self.address))
        model.routePendingScan()
        #expect(model.isPresentingSend && model.sendPrefill == Address(Self.address))
    }

    @Test @MainActor func doesNotOpenSendWithoutAnAccount() {
        let model = WalletViewModel(wallets: [], chain: MockChainService())
        model.pendingScan = .send(Address(Self.address))
        model.routePendingScan()
        #expect(!model.isPresentingSend && model.sendPrefill == nil)
        #expect(!model.canSendFromSelected)
    }

    @Test @MainActor func derivesTheAddressOfAScannedPublicKey() async throws {
        let multisig = MockMultisigService()
        multisig.keyAddresses[Self.publicKey] = Self.address
        let model = WalletViewModel(wallets: WalletViewModel.sampleWallets, chain: MockChainService(), multisig: multisig)
        #expect(try await model.address(forScannedPublicKey: Self.publicKey) == Address(Self.address))
        await #expect(throws: (any Error).self) { try await model.address(forScannedPublicKey: "edpkUnknown") }
    }
}
