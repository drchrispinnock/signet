import AppKit
import SwiftUI

/// Makes the selected tz4 account's BLS proof of possession, as `octez-client create bls proof
/// for <alias>` does: the key's signature over its own public key, which a baker needs when the
/// key becomes its consensus or companion key. The proof is public; the secret key never leaves
/// the signer. Encrypted keys are opened with their password first.
struct ProofOfPossessionSheet: View {
    @Bindable var model: WalletViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var passphrase = ""
    @State private var proof: String?
    @State private var copied: String?
    @State private var isWorking = false
    @State private var errorMessage: String?

    private var wallet: Wallet? { model.selectedWallet }
    private var needsPassphrase: Bool { wallet?.keyKind == .encrypted }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                if let wallet { AccountAvatarView(address: wallet.address, size: 40) }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Create proof of possession").font(.title2.weight(.semibold))
                    if let wallet { Text("\(wallet.alias)  \(wallet.address.shortened())").font(.callout).foregroundStyle(.secondary) }
                }
            }

            Text("A BLS proof of possession is this account's signature over its own public key. A baker needs it to make this key its consensus or companion key, and an unrevealed tz4 account's first operation carries one. It is the same proof octez-client's “create bls proof for” prints, and it can be shared freely: it proves the key is held without exposing it.")
                .font(.callout).foregroundStyle(.secondary)

            Form {
                if let publicKey = wallet?.publicKey {
                    valueRow(title: "Public key", value: publicKey)
                }
                if let proof {
                    valueRow(title: "Proof of possession", value: proof)
                } else if needsPassphrase, let wallet {
                    SecureField("Password for “\(wallet.alias)”", text: $passphrase)
                        .onSubmit { if !passphrase.isEmpty { prove() } }
                    Text("The key is stored encrypted. Enter its password to sign the proof.").font(.callout).foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            .scrollDisabled(true)

            if let errorMessage { Text(errorMessage).font(.callout).foregroundStyle(.red) }

            HStack {
                if isWorking { ProgressView().controlSize(.small); Text("Signing…").font(.callout).foregroundStyle(.secondary) }
                Spacer()
                if proof == nil {
                    Button("Cancel", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                    Button(needsPassphrase ? "Unlock and create" : "Create", action: prove)
                        .keyboardShortcut(.defaultAction)
                        .buttonStyle(.borderedProminent)
                        .disabled(isWorking || (needsPassphrase && passphrase.isEmpty))
                } else {
                    Button("Done") { close() }.keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent)
                }
            }
        }
        .padding(20)
        .frame(width: 560)
        .onAppear { if !needsPassphrase { prove() } }
        .onDisappear { proof = nil; passphrase = "" }
    }

    private func valueRow(title: String, value: String) -> some View {
        LabeledContent(title) {
            HStack(spacing: 8) {
                Text(value)
                    .font(.callout.monospaced())
                    .lineLimit(2)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                    .frame(maxWidth: 300, alignment: .trailing)
                Button { copy(value) } label: { Image(systemName: copied == value ? "checkmark" : "doc.on.doc") }
                    .buttonStyle(.borderless)
                    .help("Copy to clipboard")
            }
        }
    }

    private func prove() {
        guard let wallet, !isWorking else { return }
        errorMessage = nil
        isWorking = true
        Task {
            defer { isWorking = false }
            do {
                proof = try await model.proofOfPossession(for: wallet, passphrase: needsPassphrase ? passphrase : nil)
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
        proof = nil
        dismiss()
    }
}

#Preview {
    ProofOfPossessionSheet(model: .preview())
}
