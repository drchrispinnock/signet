import SwiftUI

/// Names a new address and picks its key type, then generates and stores the key.
struct CreateWalletSheet: View {
    @Bindable var model: WalletViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var alias = ""
    @State private var scheme: AddressScheme = .tz1
    @State private var errorMessage: String?
    @FocusState private var aliasFocused: Bool

    private var trimmedAlias: String { alias.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var canCreate: Bool { !trimmedAlias.isEmpty && scheme.isSupported && !model.isCreatingWallet }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Create address")
                .font(.title2.weight(.semibold))

            Form {
                TextField("Name", text: $alias, prompt: Text("e.g. Savings"))
                    .focused($aliasFocused)
                    .onSubmit { if canCreate { create() } }

                Picker("Key type", selection: $scheme) {
                    ForEach(AddressScheme.allCases, id: \.self) { candidate in
                        Text(candidate.isSupported ? "\(candidate.rawValue)  \(candidate.displayName)"
                                                   : "\(candidate.rawValue)  \(candidate.displayName)  (not available)")
                            .tag(candidate)
                    }
                }

                if let reason = scheme.unavailableReason {
                    Label(reason, systemImage: "exclamationmark.triangle")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else {
                    Text("The secret key is generated on this Mac and stored in your keychain. It never leaves this device.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
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
        .frame(width: 460)
        .onAppear { aliasFocused = true }
    }

    private func create() {
        errorMessage = nil
        Task {
            do {
                try await model.createWallet(alias: trimmedAlias, scheme: scheme)
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
