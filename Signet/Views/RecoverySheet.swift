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

    /// Whether a sheet can be made: without the QR code there is nothing to scan back in.
    var canBePrinted: Bool { qrImage(size: 200) != nil }
}

/// The page itself, drawn at the paper's size in black on white whatever the app's appearance.
struct RecoverySheetPage: View {
    let sheet: RecoverySheet
    let paperSize: CGSize

    private static let margin: CGFloat = 54

    var body: some View {
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

            VStack(alignment: .leading, spacing: 14) {
                row("Address", sheet.address.value)
                if let publicKey = sheet.publicKey { row("Public key", publicKey) }
                row(sheet.isEncrypted ? "Secret key (encrypted)" : "Secret key", sheet.secretKey)
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

            Text("To recover the account, open Signet, choose Scan QR code… and hold this sheet up to the camera, or choose Import account… and type the secret key\(sheet.isEncrypted ? ", then enter the password" : ""). octez-client accepts the same key. Keep this sheet offline and out of sight, and do not photograph or photocopy it.")
                .font(.system(size: 10))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Self.margin)
        .frame(width: paperSize.width, height: paperSize.height, alignment: .topLeading)
        .foregroundStyle(.black)
        .background(.white)
        .environment(\.colorScheme, .light)
    }

    private func row(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.system(size: 10, weight: .semibold))
            Text(value)
                .font(.system(size: 12, design: .monospaced))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Turns a recovery sheet into a one-page PDF in memory and sends it to the system print
/// panel. Signet writes the sheet nowhere itself; what the panel does with it (a printer, or
/// a PDF the user asks for) is the user's choice.
@MainActor
enum RecoverySheetPrinter {
    /// The page as PDF data, drawn as vectors so the QR code and text print sharply.
    static func pdfData(for sheet: RecoverySheet, paperSize: CGSize = CGSize(width: 595, height: 842)) -> Data {
        let data = NSMutableData()
        let renderer = ImageRenderer(content: RecoverySheetPage(sheet: sheet, paperSize: paperSize))
        renderer.proposedSize = ProposedViewSize(paperSize)
        renderer.render { _, draw in
            var box = CGRect(origin: .zero, size: paperSize)
            guard let consumer = CGDataConsumer(data: data as CFMutableData),
                  let context = CGContext(consumer: consumer, mediaBox: &box, nil)
            else { return }
            context.beginPDFPage(nil)
            draw(context)
            context.endPDFPage()
            context.closePDF()
        }
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
