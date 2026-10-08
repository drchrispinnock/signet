import SwiftUI

/// Removes an account from Signet's list and key store. Everyone gets one warning; accounts whose
/// secret key Signet holds get a second, plus the password for encrypted keys.
struct ForgetAccountSheet: View {
    @Bindable var model: WalletViewModel
    @Environment(\.dismiss) private var dismiss

    enum Step { case first, second }

    @State private var step: Step = .first
    @State private var passphrase = ""
    @State private var isWorking = false
    @State private var errorMessage: String?

    private var wallet: Wallet? { model.selectedWallet }
    private var holdsSecret: Bool { [.unencrypted, .encrypted].contains(wallet?.keyKind) }
    private var needsPassphrase: Bool { wallet?.keyKind == .encrypted }
    private var backupFolder: String { model.backupDirectory?.path(percentEncoded: false).replacingOccurrences(of: FileManager.default.homeDirectoryForCurrentUser.path, with: "~") ?? "the backup folder" }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                if let wallet { AccountAvatarView(address: wallet.address, size: 40) }
                VStack(alignment: .leading, spacing: 2) {
                    Text(step == .first ? "Forget account" : "Are you sure?").font(.title2.weight(.semibold))
                    if let wallet { Text("\(wallet.alias)  \(wallet.address.shortened())").font(.callout).foregroundStyle(.secondary) }
                }
            }

            switch step {
            case .first: firstWarning
            case .second: secondWarning
            }

            if let errorMessage { Text(errorMessage).font(.callout).foregroundStyle(.red) }

            HStack {
                if isWorking { ProgressView().controlSize(.small) }
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction).disabled(isWorking)
                switch step {
                case .first:
                    if holdsSecret {
                        Button("Continue…") { step = .second }.keyboardShortcut(.defaultAction)
                    } else {
                        Button("Forget", role: .destructive, action: forget).keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent)
                    }
                case .second:
                    Button("Forget for good", role: .destructive, action: forget)
                        .keyboardShortcut(.defaultAction)
                        .buttonStyle(.borderedProminent)
                        .disabled(isWorking || (needsPassphrase && passphrase.isEmpty))
                }
            }
        }
        .padding(20)
        .frame(width: 520)
    }

    private var firstWarning: some View {
        Form {
            Label {
                Text(firstText)
            } icon: { Image(systemName: "exclamationmark.triangle.fill") }
                .foregroundStyle(.orange)
            Text("The account itself stays on the chain with everything in it; forgetting only changes what this Mac knows.")
                .font(.callout).foregroundStyle(.secondary)
        }
        .formStyle(.grouped).scrollDisabled(true)
    }

    private var firstText: String {
        switch wallet?.keyKind {
        case .unencrypted, .encrypted: "Signet holds this account's secret key. Forgetting deletes that key from ~/.signet. Without another copy of the key or its recovery phrase, the account and its tez are lost."
        case .ledger: "This account's key stays on your Ledger; Signet will only forget how to reach it. You can connect it again later."
        case .remote, .unknown: "Signet will forget this account's signer entry. The key itself lives elsewhere and is not touched."
        default: "This is an address-book entry. Signet will forget the name and address; nothing else changes."
        }
    }

    private var secondWarning: some View {
        Form {
            Label {
                Text("Last chance. The secret key will be deleted from this Mac's wallet directory. Make sure you have exported it or have the recovery phrase first.")
            } icon: { Image(systemName: "exclamationmark.octagon.fill") }
                .foregroundStyle(.red)
            Label {
                Text("Earlier backups in \(backupFolder) may still contain this key. Delete those too if you need the key gone from this Mac entirely.")
            } icon: { Image(systemName: "externaldrive.badge.exclamationmark") }
                .font(.callout).foregroundStyle(.secondary)
            if needsPassphrase, let wallet {
                SecureField("Password for “\(wallet.alias)”", text: $passphrase)
                    .onSubmit { if !passphrase.isEmpty { forget() } }
                Text("The key is encrypted; its password is needed before it can be thrown away.").font(.callout).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped).scrollDisabled(true)
    }

    private func forget() {
        errorMessage = nil
        isWorking = true
        Task {
            defer { isWorking = false }
            do {
                try await model.forgetSelectedWallet(passphrase: needsPassphrase ? passphrase : nil)
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

#Preview {
    ForgetAccountSheet(model: .preview())
}
