import Foundation
import Testing
@testable import Signet

@Suite("Ledger keys")
struct LedgerKeyTests {
    @Test("parses octez-client locators")
    func parsesLocators() throws {
        let key = try #require(LedgerKey(locator: "ledger://masculine-pig-stupendous-coyote/ed25519/0h/0h"))
        #expect(key.rootID == "masculine-pig-stupendous-coyote")
        #expect(key.curve == .ed25519)
        #expect(key.relativePath == ["0'", "0'"])
        #expect(key.fullPath == "44'/1729'/0'/0'")
        #expect(key.account == 0)
        #expect(key.locator == "ledger://masculine-pig-stupendous-coyote/ed25519/0h/0h")

        let explicit = try #require(LedgerKey(locator: "ledger://tz1abc/P-256/44'/1729'/3'/0'"))
        #expect(explicit.curve == .p256)
        #expect(explicit.fullPath == "44'/1729'/3'/0'")
        #expect(explicit.account == 3)
        #expect(explicit.locator == "ledger://tz1abc/P-256/3h/0h")

        #expect(LedgerKey(locator: "ledger://x/bip32-ed25519/1h/0h")?.curve == .bip25519)
        #expect(LedgerKey(locator: "ledger://x/secp256k1/0h/0h")?.curve.scheme == .tz2)
        #expect(LedgerKey(locator: "ledger://x/secp256k1/0h/1h")?.account == nil)
        #expect(LedgerKey(locator: "unencrypted:edsk") == nil)
        #expect(LedgerKey(locator: "ledger://x/weird/0h") == nil)
        #expect(LedgerKey(locator: "ledger://x/ed25519/0h/zz") == nil)
    }

    @Test("curves map to Taquito derivation types and schemes")
    func curves() {
        #expect(LedgerCurve.allCases.map(\.derivationType) == [0, 1, 2, 3])
        #expect(LedgerCurve(octezName: "secp256r1") == .p256)
        #expect(LedgerCurve.bip25519.scheme == .tz1)
    }

    @Test("signing key specs for the bridge")
    func specs() throws {
        let ledger = SigningKey.ledger(LedgerKey(rootID: "tz1root", curve: .secp256k1, account: 2), address: Address("tz2abc"))
        let spec = try #require(try JSONSerialization.jsonObject(with: Data(ledger.bridgeSpec.utf8)) as? [String: Any])
        #expect(spec["kind"] as? String == "ledger")
        #expect(spec["path"] as? String == "44'/1729'/2'/0'")
        #expect(spec["derivationType"] as? Int == 1)
        #expect(spec["address"] as? String == "tz2abc")
        #expect(ledger.isLedger)

        let secret = SigningKey.secret("edskX", passphrase: "pw", address: Address("tz1abc"))
        let s2 = try #require(try JSONSerialization.jsonObject(with: Data(secret.bridgeSpec.utf8)) as? [String: Any])
        #expect(s2["kind"] as? String == "secret")
        #expect(s2["secretKey"] as? String == "edskX")
        #expect(s2["passphrase"] as? String == "pw")
        #expect(s2["address"] as? String == "tz1abc")
        #expect(!secret.isLedger)
    }

    @Test("ledger aliases load with their key and can sign")
    func loadsLedgerAliases() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("signet-ledger-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try """
        [{"name":"nano","value":"tz1VSUr8wwNhLAzempoch5d6hLRiTh8Cjcjb"}]
        """.write(to: dir.appendingPathComponent("public_key_hashs"), atomically: true, encoding: .utf8)
        try """
        [{"name":"nano","value":{"locator":"ledger://tz1root/ed25519/0h/0h","key":"edpkuBknW28nW72KG6RoHtYW7p12T6GKc7nAbwYX5m8Wd9sDVC9yav"}}]
        """.write(to: dir.appendingPathComponent("public_keys"), atomically: true, encoding: .utf8)
        try """
        [{"name":"nano","value":"ledger://tz1root/ed25519/0h/0h"}]
        """.write(to: dir.appendingPathComponent("secret_keys"), atomically: true, encoding: .utf8)

        let store = TezosClientStore(directory: dir)
        let wallet = try #require(try store.load().first)
        #expect(wallet.keyKind == .ledger)
        #expect(wallet.keyKind.canSign)
        #expect(wallet.ledgerKey?.fullPath == "44'/1729'/0'/0'")
        #expect(try store.secretKey(for: wallet) == nil)
    }

    @Test("connecting a Ledger writes an octez ledger:// alias and selects it")
    @MainActor
    func connectWritesLocator() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("signet-ledger-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = TezosClientStore(directory: dir)
        let model = WalletViewModel(chain: MockChainService(), ledger: MockLedgerService(connected: [MockLedgerService.sampleDevice]), walletStore: store)

        try await model.connectLedger(alias: "Nano", deviceID: MockLedgerService.sampleDevice.id, curve: .p256, account: 1)
        let wallet = try #require(model.selectedWallet)
        #expect(wallet.alias == "Nano")
        #expect(wallet.keyKind == .ledger)
        #expect(wallet.scheme == .tz3)
        #expect(wallet.ledgerKey == LedgerKey(rootID: MockLedgerService.rootAddress.value, curve: .p256, account: 1))
        #expect(wallet.publicKey == "p2pkMockLedger1")

        let secrets = try JSONSerialization.jsonObject(with: Data(contentsOf: dir.appendingPathComponent("secret_keys"))) as? [[String: Any]]
        #expect(secrets?.first?["value"] as? String == "ledger://\(MockLedgerService.rootAddress.value)/P-256/1h/0h")
        let publics = try JSONSerialization.jsonObject(with: Data(contentsOf: dir.appendingPathComponent("public_keys"))) as? [[String: Any]]
        #expect((publics?.first?["value"] as? [String: Any])?["locator"] as? String == "ledger://\(MockLedgerService.rootAddress.value)/P-256/1h/0h")

        let signer = try model.signingKey(for: wallet, passphrase: nil)
        #expect(signer == .ledger(wallet.ledgerKey!, address: wallet.address))

        await #expect(throws: WalletViewModel.WalletError.self) {
            try await model.connectLedger(alias: "Again", deviceID: MockLedgerService.sampleDevice.id, curve: .p256, account: 1)
        }
    }
}

@Suite("Ledger HID framing")
struct LedgerFramingTests {
    @Test("short APDUs fit one 64-byte report")
    func singlePacket() throws {
        let apdu: [UInt8] = [0x80, 0x02, 0x00, 0x00, 0x00]
        let packets = LedgerFraming.packets(for: apdu)
        #expect(packets.count == 1)
        #expect(packets[0].count == 64)
        #expect(Array(packets[0][0..<7]) == [0x01, 0x01, 0x05, 0x00, 0x00, 0x00, 0x05])
        #expect(Array(packets[0][7..<12]) == apdu)
        #expect(packets[0][12...].allSatisfy { $0 == 0 })
    }

    @Test("long APDUs span reports with sequence numbers and reassemble")
    func multiPacket() throws {
        let apdu = (0..<150).map { UInt8($0 & 0xff) }
        let packets = LedgerFraming.packets(for: apdu)
        #expect(packets.count == 3)   // 57 + 59 + 34
        #expect(Array(packets[1][0..<5]) == [0x01, 0x01, 0x05, 0x00, 0x01])
        #expect(Array(packets[2][0..<5]) == [0x01, 0x01, 0x05, 0x00, 0x02])

        var assembler = LedgerFraming.Reassembler()
        #expect(try assembler.add(packets[0]) == nil)
        #expect(try assembler.add(packets[1]) == nil)
        #expect(try assembler.add(packets[2]) == apdu)
    }

    @Test("reassembler rejects bad headers and out-of-order reports")
    func rejects() throws {
        var assembler = LedgerFraming.Reassembler()
        #expect(throws: LedgerFraming.Reassembler.FramingError.self) { try assembler.add([0x00, 0x00, 0x05, 0, 0, 0, 1, 0x90]) }
        let packets = LedgerFraming.packets(for: (0..<100).map { UInt8($0) })
        #expect(throws: LedgerFraming.Reassembler.FramingError.self) { try assembler.add(packets[1]) }
    }
}

@Suite("Ledger bridge")
struct LedgerBridgeTests {
    @Test("lists devices without crashing when none is plugged in")
    func devices() async throws {
        let list = try await TaquitoBridge.shared.call("ledgerDevices")
        #expect(list.arrayValue != nil)
    }

    @Test("signing with no Ledger connected fails cleanly")
    func noDevice() async throws {
        let devices = await BridgeLedgerService().devices()
        guard devices.isEmpty else { return }   // a real Ledger is plugged in; the HID path is exercised by hand
        await #expect(throws: ChainError.ledgerNotConnected) {
            _ = try await BridgeLedgerService().appInfo(deviceID: "")
        }
    }
}
