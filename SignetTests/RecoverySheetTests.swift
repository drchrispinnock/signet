import AppKit
import Foundation
import PDFKit
import Testing
@testable import Signet

/// The printed recovery sheet: what it carries and that Scan QR code can read it back.
struct RecoverySheetTests {
    private static let clear = Base58.checkEncode(prefix: TezosPrefix.edsk, payload: [UInt8](repeating: 7, count: 32))
    /// edesk: the octez prefix for an encrypted ed25519 seed (8-byte salt and 48 bytes of box).
    private static let encrypted = Base58.checkEncode(prefix: [7, 90, 60, 179, 41], payload: [UInt8](repeating: 3, count: 56))
    private static let wallet = Wallet(alias: "Savings", address: Address("tz1VSUr8wwNhLAzempoch5d6hLRiTh8Cjcjb"), keyKind: .encrypted)

    @Test func carriesTheEncryptedKeyWhenThereIsOne() {
        #expect(Self.encrypted.hasPrefix("edesk"))
        let sheet = RecoverySheet(wallet: Self.wallet, key: .init(clear: Self.clear, encrypted: Self.encrypted), version: "1.0")
        #expect(sheet.secretKey == Self.encrypted)
        #expect(sheet.isEncrypted)
        #expect(sheet.alias == "Savings")
        let plain = RecoverySheet(wallet: Self.wallet, key: .init(clear: Self.clear, encrypted: nil), version: "1.0")
        #expect(plain.secretKey == Self.clear)
        #expect(!plain.isEncrypted)
    }

    @Test func theQRCodeScansBackAsASecretKey() throws {
        for key in [WalletViewModel.ExportedKey(clear: Self.clear, encrypted: Self.encrypted), .init(clear: Self.clear, encrypted: nil)] {
            let sheet = RecoverySheet(wallet: Self.wallet, key: key, version: "1.0")
            #expect(sheet.canBePrinted)
            let image = try #require(sheet.qrImage())
            #expect(QRCode.decode(image).map(QRPayload.classify) == .secretKey(sheet.secretKey))
        }
    }

    @Test func aKeyTooLongForAQRCodeHasNoSheet() {
        // A tz5 (ML-DSA-44) secret is 3872 bytes, more than a QR code holds.
        let long = Base58.checkEncode(prefix: TezosPrefix.edsk, payload: [UInt8](repeating: 5, count: 3872))
        #expect(!RecoverySheet(wallet: Self.wallet, key: .init(clear: long, encrypted: nil), version: "1.0").canBePrinted)
    }

    @Test @MainActor func rendersOnePageWithTheAccountOnIt() throws {
        let sheet = RecoverySheet(wallet: Self.wallet, key: .init(clear: Self.clear, encrypted: Self.encrypted), version: "1.0")
        let data = RecoverySheetPrinter.pdfData(for: sheet)
        if let path = ProcessInfo.processInfo.environment["SIGNET_RECOVERY_SHEET_OUTPUT"] { try data.write(to: URL(fileURLWithPath: path)) }
        let document = try #require(PDFDocument(data: data))
        #expect(document.pageCount == 1)
        let text = document.string ?? ""
        #expect(text.contains("Recovery Sheet"))
        #expect(text.contains("Savings"))
        #expect(text.contains("Password"))
    }
}
