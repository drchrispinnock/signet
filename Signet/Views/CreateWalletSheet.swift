import SwiftUI

/// Names a new wallet and picks its key type, then generates and stores the key.
struct CreateWalletSheet: View {
    @Bindable var model: WalletViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var alias: String
    @State private var scheme: AddressScheme = .tz1
    /// tz3 made inside the Secure Enclave rather than as a key on disk.
    @State private var inEnclave = false
    @State private var understandsEnclave = false
    @State private var encrypt: Bool
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var errorMessage: String?
    @FocusState private var aliasFocused: Bool

    init(model: WalletViewModel) {
        self.model = model
        // Real money defaults to encrypted; testnets default to convenience.
        _encrypt = State(initialValue: model.network.isMainnet)
        _alias = State(initialValue: model.suggestedAlias())
    }

    private var trimmedAlias: String { alias.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var passwordProblem: String? {
        guard encrypt, !inEnclave else { return nil }
        if password.count < WalletViewModel.minimumPassphraseLength { return "Use at least \(WalletViewModel.minimumPassphraseLength) characters." }
        if password != confirmPassword { return "The passwords do not match." }
        return nil
    }
    private var canCreate: Bool { !trimmedAlias.isEmpty && scheme.isSupported && !model.isCreatingWallet && passwordProblem == nil && (!inEnclave || understandsEnclave) }

    /// The picker's choices: every supported scheme, then the Enclave's tz3 where there is one.
    private enum KeyChoice: Hashable { case scheme(AddressScheme), enclave }
    private var choice: Binding<KeyChoice> {
        Binding(
            get: { inEnclave ? .enclave : .scheme(scheme) },
            set: { new in
                switch new {
                case .scheme(let option): scheme = option; inEnclave = false
                case .enclave: scheme = .tz3; inEnclave = true
                }
            }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Create account")
                .font(.title2.weight(.semibold))

            Form {
                TextField("Name", text: $alias, prompt: Text("My Account"))
                    .focused($aliasFocused)
                    .onSubmit { if canCreate { create() } }

                Picker("Key type", selection: choice) {
                    ForEach(AddressScheme.allCases.filter(\.isSupported), id: \.self) { option in
                        Text(option == .tz1 ? "\(option.rawValue) · \(option.displayName) (recommended)" : "\(option.rawValue) · \(option.displayName)").tag(KeyChoice.scheme(option))
                    }
                    if model.canCreateEnclaveKey {
                        Divider()
                        Text("tz3 · in this Mac's Secure Enclave").tag(KeyChoice.enclave)
                    }
                }
                if inEnclave {
                    enclaveNotes
                } else {
                    softwareKeyNotes
                }
            }
            .formStyle(.grouped)
            .scrollDisabled(true)

            if let errorMessage {
                Text(errorMessage)
                    .font(.callout)
                    .foregroundStyle(.red)
            }

            HStack {
                if model.isCreatingWallet {
                    ProgressView().controlSize(.small)
                    Text("Generating key…").font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Create", action: create)
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(!canCreate)
            }
        }
        .padding(20)
        .frame(width: 480)
        .onAppear { aliasFocused = true }
    }

    @ViewBuilder private var enclaveNotes: some View {
        Label("The key is made inside the Secure Enclave and never leaves it. Every signature asks for Touch ID or your password.", systemImage: "touchid")
            .font(.callout)
            .foregroundStyle(.secondary)
        Label("It cannot be exported, backed up or recovered, and there is no recovery phrase. If this Mac is lost, erased or repaired, the account and everything in it are lost.", systemImage: "exclamationmark.triangle")
            .font(.callout)
            .foregroundStyle(.orange)
        Text("Use it for spending money, or as one signer of a multisig whose other signers can be recovered. octez-client can watch the account but cannot sign for it.")
            .font(.callout)
            .foregroundStyle(.secondary)
        Toggle("I understand that this key exists only on this Mac", isOn: $understandsEnclave)
    }

    @ViewBuilder private var softwareKeyNotes: some View {
                if let caveat = scheme.caveat {
                    Label(caveat, systemImage: "info.circle")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                Toggle("Encrypt with a password", isOn: $encrypt)
                if encrypt {
                    SecureField("Password", text: $password)
                    SecureField("Confirm password", text: $confirmPassword)
                    if let passwordProblem, !password.isEmpty {
                        Text(passwordProblem).font(.callout).foregroundStyle(.secondary)
                    }
                    Text("You will be asked for this password every time the key signs. It cannot be recovered; if you lose it the key is lost.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else {
                    Label("Unencrypted keys are stored on disk unprotected. Anyone who can read ~/.signet can spend from this account.", systemImage: "exclamationmark.triangle")
                        .font(.callout)
                        .foregroundStyle(.orange)
                }
                Text("The key is saved to ~/.signet in octez-client's format, so octez-client can use it too.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
    }

    private func create() {
        errorMessage = nil
        Task {
            do {
                if inEnclave {
                    try await model.createEnclaveWallet(alias: trimmedAlias)
                } else {
                    try await model.createWallet(alias: trimmedAlias, scheme: scheme, passphrase: encrypt ? password : nil)
                }
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

#Preview {
    CreateWalletSheet(model: .preview())
}
