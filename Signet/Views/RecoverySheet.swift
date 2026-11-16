import AppKit
import PDFKit
import SwiftUI

/// What goes on a printed recovery sheet for one account: enough to bring the account back
/// with Scan QR code or Import account, and nothing that is not already in the Export sheet.
/// The secret is printed as it is stored, so a password-protected key stays protected on
/// paper and the sheet leaves a box for the password to be written in by hand.
struct RecoverySheet: Equatable, Sendable {
    let alias: String
    let address: Address
    let publicKey: String?
    /// The key the QR code carries: the octez-encrypted form when there is one, else the clear key.
    let secretKey: String
    let isEncrypted: Bool
    let date: Date
    let version: String

    init(wallet: Wallet, key: WalletViewModel.ExportedKey, date: Date = Date(), version: String = RecoverySheet.appVersion) {
        alias = wallet.alias
        address = wallet.address
        publicKey = wallet.publicKey
        secretKey = key.encrypted ?? key.clear
        isEncrypted = key.encrypted != nil
        self.date = date
        self.version = version
    }

    static var appVersion: String { Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "" }

    /// The QR code of the secret key, or `nil` when the key is too long for one (a tz5 key is).
    func qrImage(size: CGFloat = 1000) -> NSImage? { QRCode.image(for: secretKey, size: size) }

    /// False when the key is too long for one QR code (a tz5 key). The sheet then carries the
    /// key as several codes on following pages (`keyParts`), which Scan QR code puts back
    /// together, and after them as numbered lines of text for when a code cannot be read.
    var hasQRCode: Bool { qrImage(size: 200) != nil }

    /// The codes of a key too long for one; empty when one code carries it.
    var keyParts: [KeyPart] { hasQRCode ? [] : KeyPart.split(secretKey) }

    static let codesPerPage = 4

    /// The pages of codes, four to a page so each prints large enough for a webcam.
    var codePages: [[KeyPart]] {
        let parts = keyParts
        return stride(from: 0, to: parts.count, by: Self.codesPerPage).map { Array(parts[$0..<min($0 + Self.codesPerPage, parts.count)]) }
    }

    static let lineLength = 90
    static let linesPerPage = 60

    /// A long key cut into lines short enough to keep one's place in.
    static func lines(of key: String) -> [String] {
        var lines: [String] = []
        var rest = Substring(key)
        while !rest.isEmpty {
            lines.append(String(rest.prefix(lineLength)))
            rest = rest.dropFirst(lineLength)
        }
        return lines
    }

    /// One page of the secret key's text.
    struct KeyPage: Equatable, Sendable {
        let lines: [String]
        /// The number of the first line, counting from 1 across all pages.
        let firstLine: Int
        let part: Int
        let parts: Int
    }

    /// The pages of key text at the end: none when one QR code carries the key.
    var secretKeyPages: [KeyPage] {
        guard !hasQRCode else { return [] }
        let lines = Self.lines(of: secretKey)
        let starts = Array(stride(from: 0, to: lines.count, by: Self.linesPerPage))
        return starts.enumerated().map { index, start in
            KeyPage(lines: Array(lines[start..<min(start + Self.linesPerPage, lines.count)]), firstLine: start + 1, part: index + 1, parts: starts.count)
        }
    }

    var pageCount: Int { 1 + codePages.count + secretKeyPages.count }
}

/// The page itself, drawn at the paper's size in black on white whatever the app's appearance.
struct RecoverySheetPage: View {
    let sheet: RecoverySheet
    let paperSize: CGSize

    fileprivate static let margin: CGFloat = 54

    var body: some View {
        let hasQRCode = sheet.hasQRCode
        let partCount = sheet.keyParts.count
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 18) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 64, height: 64)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Signet Tezos Wallet Recovery Sheet")
                        .font(.system(size: 22, weight: .semibold))
                    Rectangle().frame(height: 1.5)
                }
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(sheet.alias).font(.system(size: 17, weight: .semibold))
                Text("Printed \(sheet.date.formatted(date: .long, time: .omitted))\(sheet.version.isEmpty ? "" : " by Signet \(sheet.version)")")
                    .font(.system(size: 10))
            }
            .padding(.top, 22)

            if hasQRCode {
            HStack {
                Spacer()
                VStack(spacing: 8) {
                    if let image = sheet.qrImage() {
                        Image(nsImage: image)
                            .interpolation(.none)
                            .resizable()
                            .frame(width: 250, height: 250)
                    }
                    Text(sheet.isEncrypted ? "Secret key, protected by its password" : "Secret key")
                        .font(.system(size: 10))
                }
                Spacer()
            }
            .padding(.top, 26)
            }

            VStack(alignment: .leading, spacing: 14) {
                row("Address", sheet.address.value)
                if let publicKey = sheet.publicKey {
                    if publicKey.count > RecoverySheet.lineLength {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Public key").font(.system(size: 10, weight: .semibold))
                            NumberedKeyLines(lines: RecoverySheet.lines(of: publicKey), firstLine: 1)
                        }
                    } else {
                        row("Public key", publicKey)
                    }
                }
                if hasQRCode {
                    row(sheet.isEncrypted ? "Secret key (encrypted)" : "Secret key", sheet.secretKey)
                } else {
                    row(sheet.isEncrypted ? "Secret key (encrypted)" : "Secret key",
                        partCount > 0
                            ? "Too long for one QR code. It follows as \(partCount) codes, then in full as text; keep all \(sheet.pageCount) pages together."
                            : "Too long for QR codes. It follows in full as text; keep all \(sheet.pageCount) pages together.",
                        monospaced: false)
                }
            }
            .padding(.top, 26)

            if sheet.isEncrypted {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .center, spacing: 14) {
                        Text("Password").font(.system(size: 13, weight: .semibold))
                        Rectangle().strokeBorder(lineWidth: 1.5).frame(height: 44)
                    }
                    Text("Write the password in by hand; it is not printed and cannot be recovered from this sheet. For more safety keep it somewhere else.")
                        .font(.system(size: 10))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 30)
            } else {
                Text("This key has no password. Anyone who sees this sheet or a copy of it controls the account.")
                    .font(.system(size: 12, weight: .semibold))
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .overlay(Rectangle().strokeBorder(lineWidth: 1.5))
                    .padding(.top, 30)
            }

            Spacer(minLength: 20)

            Text(hasQRCode
                 ? "To recover the account, open Signet, choose Scan QR code… and hold this sheet up to the camera, or choose Import account… and type the secret key\(sheet.isEncrypted ? ", then enter the password" : ""). octez-client accepts the same key. Keep this sheet offline and out of sight, and do not photograph or photocopy it."
                 : "To recover the account, open Signet, choose Scan QR code… and hold up each of the \(partCount) codes on the following pages, in any order; Signet says which it still needs. Or choose Import account… and type the secret key from the last pages as one unbroken line, without the line numbers or spaces\(sheet.isEncrypted ? ". Then enter the password" : ""). octez-client accepts the typed key. Keep these pages offline and out of sight, and do not photograph or photocopy them.")
                .font(.system(size: 10))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Self.margin)
        .frame(width: paperSize.width, height: paperSize.height, alignment: .topLeading)
        .foregroundStyle(.black)
        .background(.white)
        .environment(\.colorScheme, .light)
    }

    private func row(_ title: String, _ value: String, monospaced: Bool = true) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.system(size: 10, weight: .semibold))
            Text(value)
                .font(.system(size: 12, design: monospaced ? .monospaced : .default))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Key text as numbered lines, so a reader typing it back can keep their place.
private struct NumberedKeyLines: View {
    let lines: [String]
    let firstLine: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 1.5) {
            ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(String(format: "%02d", firstLine + index))
                        .font(.system(size: 6.5, design: .monospaced))
                        .frame(width: 14, alignment: .trailing)
                    Text(line)
                        .font(.system(size: 8, design: .monospaced))
                        .lineLimit(1)
                        .fixedSize()
                }
            }
        }
    }
}

/// A following page of a sheet whose key is too long for a QR code: part of the secret key as text.
struct RecoverySheetKeyPage: View {
    let sheet: RecoverySheet
    let page: RecoverySheet.KeyPage
    let paperSize: CGSize

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Signet Tezos Wallet Recovery Sheet")
                .font(.system(size: 14, weight: .semibold))
            Text("\(sheet.alias)  ·  \(sheet.address.value)  ·  page \(1 + sheet.codePages.count + page.part) of \(sheet.pageCount)")
                .font(.system(size: 9))
                .padding(.top, 3)
            Rectangle().frame(height: 1).padding(.top, 6)
            Text("\(sheet.isEncrypted ? "Secret key (encrypted)" : "Secret key"), lines \(page.firstLine) to \(page.firstLine + page.lines.count - 1)")
                .font(.system(size: 10, weight: .semibold))
                .padding(.top, 14)
                .padding(.bottom, 6)
            NumberedKeyLines(lines: page.lines, firstLine: page.firstLine)
            Spacer(minLength: 0)
        }
        .padding(RecoverySheetPage.margin)
        .frame(width: paperSize.width, height: paperSize.height, alignment: .topLeading)
        .foregroundStyle(.black)
        .background(.white)
        .environment(\.colorScheme, .light)
    }
}

/// A page of the codes that together carry a key too long for one.
struct RecoverySheetCodesPage: View {
    let sheet: RecoverySheet
    let parts: [KeyPart]
    /// Which of the code pages this is, from 1.
    let number: Int
    let paperSize: CGSize

    private static let codeSize: CGFloat = 230

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Signet Tezos Wallet Recovery Sheet")
                .font(.system(size: 14, weight: .semibold))
            Text("\(sheet.alias)  ·  \(sheet.address.value)  ·  page \(1 + number) of \(sheet.pageCount)")
                .font(.system(size: 9))
                .padding(.top, 3)
            Rectangle().frame(height: 1).padding(.top, 6)
            Text("\(sheet.isEncrypted ? "Secret key (encrypted)" : "Secret key") as QR codes. Scan every part with Signet's Scan QR code, in any order.")
                .font(.system(size: 10, weight: .semibold))
                .padding(.top, 14)
                .padding(.bottom, 18)
            Grid(horizontalSpacing: 27, verticalSpacing: 26) {
                ForEach(Array(stride(from: 0, to: parts.count, by: 2)), id: \.self) { start in
                    GridRow {
                        ForEach(parts[start..<min(start + 2, parts.count)], id: \.index) { part in
                            VStack(spacing: 6) {
                                if let image = QRCode.image(for: part.text, size: 1000, correction: "L") {
                                    Image(nsImage: image)
                                        .interpolation(.none)
                                        .resizable()
                                        .frame(width: Self.codeSize, height: Self.codeSize)
                                }
                                Text("Part \(part.index) of \(part.count)").font(.system(size: 11, weight: .semibold))
                            }
                        }
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(RecoverySheetPage.margin)
        .frame(width: paperSize.width, height: paperSize.height, alignment: .topLeading)
        .foregroundStyle(.black)
        .background(.white)
        .environment(\.colorScheme, .light)
    }
}

/// Turns a recovery sheet into a one-page PDF in memory and sends it to the system print
/// panel. Signet writes the sheet nowhere itself; what the panel does with it (a printer, or
/// a PDF the user asks for) is the user's choice.
@MainActor
enum RecoverySheetPrinter {
    /// The sheet as PDF data, drawn as vectors so the QR code and text print sharply: one page,
    /// or more when the key has to be printed as text.
    static func pdfData(for sheet: RecoverySheet, paperSize: CGSize = CGSize(width: 595, height: 842)) -> Data {
        let data = NSMutableData()
        var box = CGRect(origin: .zero, size: paperSize)
        guard let consumer = CGDataConsumer(data: data as CFMutableData),
              let context = CGContext(consumer: consumer, mediaBox: &box, nil)
        else { return Data() }
        func draw(_ page: some View) {
            let renderer = ImageRenderer(content: page)
            renderer.proposedSize = ProposedViewSize(paperSize)
            renderer.render { _, draw in
                context.beginPDFPage(nil)
                draw(context)
                context.endPDFPage()
            }
        }
        draw(RecoverySheetPage(sheet: sheet, paperSize: paperSize))
        for (index, parts) in sheet.codePages.enumerated() { draw(RecoverySheetCodesPage(sheet: sheet, parts: parts, number: index + 1, paperSize: paperSize)) }
        for page in sheet.secretKeyPages { draw(RecoverySheetKeyPage(sheet: sheet, page: page, paperSize: paperSize)) }
        context.closePDF()
        return data as Data
    }

    /// Shows the print panel for the sheet, attached to `window` when there is one.
    static func print(_ sheet: RecoverySheet, from window: NSWindow? = NSApp.keyWindow) {
        let info = NSPrintInfo.shared.copy() as! NSPrintInfo
        info.topMargin = 0
        info.bottomMargin = 0
        info.leftMargin = 0
        info.rightMargin = 0
        guard let document = PDFDocument(data: pdfData(for: sheet, paperSize: info.paperSize)),
              let operation = document.printOperation(for: info, scalingMode: .pageScaleDownToFit, autoRotate: false)
        else { return }
        operation.jobTitle = "Signet recovery sheet"
        if let window {
            operation.runModal(for: window, delegate: nil, didRun: nil, contextInfo: nil)
        } else {
            operation.run()
        }
    }
}
