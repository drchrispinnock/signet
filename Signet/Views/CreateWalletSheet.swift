import SwiftUI

/// Names a new wallet and picks its key type, then generates and stores the key.
struct CreateWalletSheet: View {
    @Bindable var model: WalletViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var alias = "My Wallet"
    @State private var scheme: AddressScheme = .tz1
    @State private var encrypt: Bool
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var errorMessage: String?
    @FocusState private var aliasFocused: Bool

    init(model: WalletViewModel) {
        self.model = model
        // Real money defaults to encrypted; testnets default to convenience.
        _encrypt = State(initialValue: model.network.isMainnet)
    }

    private var trimmedAlias: String { alias.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var passwordProblem: String? {
        guard encrypt else { return nil }
        if password.count < WalletViewModel.minimumPassphraseLength { return "Use at least \(WalletViewModel.minimumPassphraseLength) characters." }
        if password != confirmPassword { return "The passwords do not match." }
        return nil
    }
    private var canCreate: Bool { !trimmedAlias.isEmpty && scheme.isSupported && !model.isCreatingWallet && passwordProblem == nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Create wallet")
                .font(.title2.weight(.semibold))

            Form {
                TextField("Name", text: $alias, prompt: Text("My Wallet"))
                    .focused($aliasFocused)
                    .onSubmit { if canCreate { create() } }

                LabeledContent("Key type") {
                    SchemePicker(selection: $scheme)
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
                    Label("Unencrypted keys are stored on disk unprotected. Anyone who can read ~/.signet can spend from this wallet.", systemImage: "exclamationmark.triangle")
                        .font(.callout)
                        .foregroundStyle(.orange)
                }
                Text("The key is saved to ~/.signet in octez-client's format, so octez-client can use it too.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
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

    private func create() {
        errorMessage = nil
        Task {
            do {
                try await model.createWallet(alias: trimmedAlias, scheme: scheme, passphrase: encrypt ? password : nil)
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

/// Radio list of address schemes. Unsupported schemes are shown greyed out and cannot be chosen;
/// a macOS pop-up picker cannot disable individual items reliably, hence the custom control.
struct SchemePicker: View {
    @Binding var selection: AddressScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(AddressScheme.allCases, id: \.self) { scheme in
                Button {
                    selection = scheme
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: selection == scheme ? "largecircle.fill.circle" : "circle")
                            .foregroundStyle(selection == scheme && scheme.isSupported ? Color.accentColor : .secondary)
                        Text(scheme.rawValue)
                            .font(.body.monospaced())
                            .frame(width: 32, alignment: .leading)
                        Text(scheme.displayName)
                        if !scheme.isSupported {
                            Text("not available")
                                .font(.caption)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(.quaternary))
                        }
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(!scheme.isSupported)
                .foregroundStyle(scheme.isSupported ? AnyShapeStyle(.primary) : AnyShapeStyle(.tertiary))
                .help(scheme.unavailableReason ?? scheme.displayName)
                .accessibilityLabel("\(scheme.rawValue) \(scheme.displayName)\(scheme.isSupported ? "" : ", not available")")
                .accessibilityAddTraits(selection == scheme ? .isSelected : [])
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#Preview {
    CreateWalletSheet(model: .preview())
}
