#if canImport(AppKit)
import AppKit
#endif
import Foundation
#if canImport(PDFKit)
import PDFKit
#endif
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
            #expect(sheet.hasQRCode)
            #expect(sheet.pageCount == 1)
            let image = try #require(sheet.qrImage())
            #expect(QRCode.decode(image).map(QRPayload.classify) == .secretKey(sheet.secretKey))
        }
    }

    /// A tz5 (ML-DSA-44) secret is 3872 bytes and its public key 1312, more than a QR code holds.
    private static let longSecret = Base58.checkEncode(prefix: [9, 57, 116, 57], payload: (0..<3872).map { UInt8(truncatingIfNeeded: $0 &* 31) })
    private static let longPublic = Base58.checkEncode(prefix: TezosPrefix.edpk, payload: (0..<1312).map { UInt8(truncatingIfNeeded: $0 &* 17) })

    @Test func aKeyTooLongForAQRCodeIsPrintedAsText() {
        let wallet = Wallet(alias: "Quantum", address: Self.wallet.address, publicKey: Self.longPublic, keyKind: .unencrypted)
        let sheet = RecoverySheet(wallet: wallet, key: .init(clear: Self.longSecret, encrypted: nil), version: "1.0")
        #expect(Self.longSecret.hasPrefix("mdsk"))
        #expect(!sheet.hasQRCode)
        let pages = sheet.secretKeyPages
        #expect(!pages.isEmpty)
        #expect(sheet.pageCount == 1 + sheet.codePages.count + pages.count)
        // Every character is there once, in order, in lines of the stated length.
        #expect(pages.flatMap(\.lines).joined() == Self.longSecret)
        #expect(pages.allSatisfy { $0.lines.count <= RecoverySheet.linesPerPage && $0.lines.allSatisfy { $0.count <= RecoverySheet.lineLength } })
        #expect(pages.map(\.firstLine) == pages.indices.map { $0 * RecoverySheet.linesPerPage + 1 })
        #expect(RecoverySheet.lines(of: "") == [])
    }

    @Test func aLongKeyIsSplitAcrossCodesThatScanBackTogether() throws {
        let sheet = RecoverySheet(wallet: Self.wallet, key: .init(clear: Self.longSecret, encrypted: nil), version: "1.0")
        let parts = sheet.keyParts
        #expect(parts.count >= 2 && parts.count <= 12)
        #expect(sheet.codePages.flatMap { $0 } == parts)
        #expect(sheet.codePages.allSatisfy { $0.count <= RecoverySheet.codesPerPage })
        #expect(parts.map(\.chunk).joined() == Self.longSecret)
        // Each part is a real QR code that reads back, and the parts, scanned out of order and
        // with one repeated, make the key again.
        var collector = KeyPartCollector()
        var result: KeyPartCollector.Outcome = .needMore
        for part in [parts[parts.count - 1]] + parts.reversed() {
            let image = try #require(QRCode.image(for: part.text, size: 600, correction: "L"))
            guard case .keyPart(let scanned) = QRPayload.classify(try #require(QRCode.decode(image))) else {
                Issue.record("part \(part.index) did not scan back as a key part")
                return
            }
            #expect(scanned == part)
            result = collector.add(scanned)
        }
        #expect(result == .complete(Self.longSecret))
        // A short key needs no parts.
        #expect(RecoverySheet(wallet: Self.wallet, key: .init(clear: Self.clear, encrypted: nil), version: "1.0").keyParts.isEmpty)
    }

    #if canImport(PDFKit)
    @Test @MainActor func rendersALongKeyOverSeveralPages() throws {
        let wallet = Wallet(alias: "Quantum", address: Self.wallet.address, publicKey: Self.longPublic, keyKind: .unencrypted)
        let sheet = RecoverySheet(wallet: wallet, key: .init(clear: Self.longSecret, encrypted: nil), version: "1.0")
        let data = RecoverySheetPrinter.pdfData(for: sheet)
        if let path = ProcessInfo.processInfo.environment["SIGNET_RECOVERY_SHEET_LONG_OUTPUT"] { try data.write(to: URL(fileURLWithPath: path)) }
        #expect(try #require(PDFDocument(data: data)).pageCount == sheet.pageCount)
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
    #endif
}
