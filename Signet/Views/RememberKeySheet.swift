import SwiftUI

/// Keeps a session-only key: writes it into the wallet directory like any other account. Offered
/// only while the selected account's key would otherwise be forgotten at quit.
struct RememberKeySheet: View {
    @Bindable var model: WalletViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var protects = false
    @State private var passphrase = ""
    @State private var confirmation = ""
    @State private var isWorking = false
    @State private var errorMessage: String?

    private var wallet: Wallet? { model.selectedWallet }
    private var isClear: Bool { wallet?.keyKind == .unencrypted }
    private var directory: String { model.walletDirectory.map { ($0.path as NSString).abbreviatingWithTildeInPath } ?? "the wallet directory" }

    private var passphraseProblem: String? {
        guard isClear, protects else { return nil }
        if passphrase.isEmpty { return "Enter a password." }
        if passphrase.count < WalletViewModel.minimumPassphraseLength { return "Use at least \(WalletViewModel.minimumPassphraseLength) characters." }
        if confirmation != passphrase { return "The passwords do not match." }
        return nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                if let wallet { AccountAvatarView(address: wallet.address, size: 40) }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Remember key").font(.title2.weight(.semibold))
                    if let wallet { Text("\(wallet.alias)  \(wallet.address.shortened())").font(.callout).foregroundStyle(.secondary) }
                }
            }

            Form {
                Label {
                    Text("This key is held in memory for this session only and would be forgotten when Signet quits. Remembering it writes it into \(directory), where it is kept like any other account and included in backups.")
                } icon: { Image(systemName: "clock.badge.exclamationmark") }
                    .foregroundStyle(.orange)
                if isClear {
                    Toggle("Protect it with a password", isOn: $protects)
                    if protects {
                        SecureField("Password", text: $passphrase)
                        SecureField("Confirm password", text: $confirmation)
                        Text("The key is encrypted in octez-client's format; the password is asked for whenever the account signs.")
                            .font(.callout).foregroundStyle(.secondary)
                    } else {
                        Text("Without a password the key is written unencrypted and anyone with access to this Mac's files can use it.")
                            .font(.callout).foregroundStyle(.orange)
                    }
                } else {
                    Text("The key is encrypted and will be stored as it is; its password stays the same.")
                        .font(.callout).foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped).scrollDisabled(true)

            if let errorMessage { Text(errorMessage).font(.callout).foregroundStyle(.red) }

            HStack {
                if isWorking { ProgressView().controlSize(.small) }
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction).disabled(isWorking)
                Button("Remember", action: remember)
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(isWorking || passphraseProblem != nil || wallet?.isSessionOnly != true)
            }
        }
        .padding(20)
        .frame(width: 520)
        .onAppear { protects = model.network.isMainnet }
    }

    private func remember() {
        errorMessage = nil
        isWorking = true
        Task {
            defer { isWorking = false }
            do {
                try await model.rememberSelectedWallet(storePassphrase: isClear && protects ? passphrase : nil)
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

#Preview {
    RememberKeySheet(model: .preview())
}
