import SwiftUI

/// The password field of a sheet that signs with an encrypted key: a `SecureField`, or, while
/// a password for this key is remembered (Settings > Passwords), a line saying until when, with
/// a Forget button that brings the field back.
struct PasswordField: View {
    let model: WalletViewModel
    let wallet: Wallet
    @Binding var text: String
    var label: String? = nil

    var body: some View {
        if let expires = model.rememberedPassphraseExpiry(for: wallet) {
            LabeledContent(label ?? "Password for “\(wallet.alias)”") {
                HStack(spacing: 8) {
                    Label("Remembered until \(expires.formatted(date: .omitted, time: .shortened))", systemImage: "key.fill")
                        .font(.callout).foregroundStyle(.secondary)
                    Button("Forget") { model.forgetRememberedPassphrase(for: wallet) }.controlSize(.small)
                }
            }
        } else {
            SecureField(label ?? "Password for “\(wallet.alias)”", text: $text)
        }
    }
}
