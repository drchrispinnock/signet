import AppKit
import SwiftUI

/// Shows the selected account's secret key, masked until revealed, with a copy button and a
/// warning. Encrypted keys are opened with their password first.
struct ExportKeySheet: View {
    @Bindable var model: WalletViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var passphrase = ""
    @State private var exported: WalletViewModel.ExportedKey?
    @State private var revealed = false
    @State private var copied: String?
    @State private var isWorking = false
    @State private var errorMessage: String?

    private var wallet: Wallet? { model.selectedWallet }
    private var needsPassphrase: Bool { wallet?.keyKind == .encrypted }
    /// The printable sheet for the key now on show.
    private var recoverySheet: RecoverySheet? {
        guard let wallet, let exported else { return nil }
        return RecoverySheet(wallet: wallet, key: exported)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                if let wallet { AccountAvatarView(address: wallet.address, size: 40) }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Export secret key").font(.title2.weight(.semibold))
                    if let wallet { Text("\(wallet.alias)  \(wallet.address.shortened())").font(.callout).foregroundStyle(.secondary) }
                }
            }

            Label {
                Text("Anyone who has this secret key controls the account and everything in it. Never share it, never type it into a website or a chat, and keep any copy offline. Signet shows it only here and puts it on the clipboard only when you press Copy.")
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill")
            }
            .font(.callout)
            .foregroundStyle(.orange)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 8).fill(.orange.opacity(0.12)))

            Form {
                if let exported {
                    keyRow(title: "Secret key", value: exported.clear, maskable: true)
                    if let recoverySheet, !recoverySheet.hasQRCode {
                        Text("A recovery sheet for this key is \(recoverySheet.pageCount) pages: it is too long for one QR code, so it is printed as \(recoverySheet.keyParts.count) codes that Scan QR code reads back in any order, then in full as text.")
                            .font(.callout).foregroundStyle(.secondary)
                    } else if recoverySheet != nil {
                        Text(exported.encrypted == nil
                             ? "A recovery sheet is a printed page with this key as a QR code, which Scan QR code reads back in. This key has no password, so the sheet alone controls the account."
                             : "A recovery sheet is a printed page with the encrypted key as a QR code, which Scan QR code reads back in, and a box to write the password in by hand.")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                    if let encrypted = exported.encrypted {
                        keyRow(title: "Encrypted form", value: encrypted, maskable: false)
                        Text("The encrypted form is what ~/.signet holds; it still needs this account's password. octez-client accepts both.")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                } else if needsPassphrase, let wallet {
                    SecureField("Password for “\(wallet.alias)”", text: $passphrase)
                        .onSubmit { if !passphrase.isEmpty { unlock() } }
                    Text("The key is stored encrypted. Enter its password to decrypt and show it.").font(.callout).foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            .scrollDisabled(true)

            if let errorMessage { Text(errorMessage).font(.callout).foregroundStyle(.red) }

            HStack {
                if isWorking { ProgressView().controlSize(.small); Text("Decrypting…").font(.callout).foregroundStyle(.secondary) }
                Spacer()
                if exported == nil {
                    Button("Cancel", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                    Button(needsPassphrase ? "Unlock" : "Show key", action: unlock)
                        .keyboardShortcut(.defaultAction)
                        .buttonStyle(.borderedProminent)
                        .disabled(isWorking || (needsPassphrase && passphrase.isEmpty))
                } else {
                    if let recoverySheet {
                        Button("Recovery Sheet…") { RecoverySheetPrinter.print(recoverySheet) }
                            .help(recoverySheet.hasQRCode
                                  ? "Print a sheet with this key as a QR code, to recover the account later with Scan QR code"
                                  : "Print this key over \(recoverySheet.pageCount) pages; it is too long for one QR code")
                    }
                    Button("Done") { close() }.keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent)
                }
            }
        }
        .padding(20)
        .frame(width: 560)
        .onAppear { if !needsPassphrase { unlock() } }
        .onDisappear { exported = nil; passphrase = "" }
    }

    private func keyRow(title: String, value: String, maskable: Bool) -> some View {
        LabeledContent(title) {
            HStack(spacing: 8) {
                Text(maskable && !revealed ? String(repeating: "•", count: 24) : value)
                    .font(.callout.monospaced())
                    .lineLimit(2)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                    .frame(maxWidth: 300, alignment: .trailing)
                if maskable {
                    Button { revealed.toggle() } label: { Image(systemName: revealed ? "eye.slash" : "eye") }
                        .buttonStyle(.borderless)
                        .help(revealed ? "Hide" : "Reveal")
                }
                Button { copy(value) } label: { Image(systemName: copied == value ? "checkmark" : "doc.on.doc") }
                    .buttonStyle(.borderless)
                    .help("Copy to clipboard")
            }
        }
    }

    private func unlock() {
        errorMessage = nil
        isWorking = true
        Task {
            defer { isWorking = false }
            do {
                exported = try await model.exportSecretKey(passphrase: needsPassphrase ? passphrase : nil)
                passphrase = ""
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func copy(_ value: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(value, forType: .string)
        copied = value
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            if copied == value { copied = nil }
        }
    }

    private func close() {
        exported = nil
        revealed = false
        dismiss()
    }
}

#Preview {
    ExportKeySheet(model: .preview())
}
