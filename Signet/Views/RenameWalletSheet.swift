import SwiftUI

/// Changes the alias of the selected wallet.
struct RenameWalletSheet: View {
    @Bindable var model: WalletViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var alias: String
    @State private var errorMessage: String?
    @State private var isSyncing = false
    @FocusState private var aliasFocused: Bool

    init(model: WalletViewModel) {
        self.model = model
        _alias = State(initialValue: model.selectedWallet?.alias ?? "")
    }

    private var trimmedAlias: String { alias.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var canRename: Bool { !trimmedAlias.isEmpty && trimmedAlias != model.selectedWallet?.alias }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Rename account")
                .font(.title2.weight(.semibold))

            Form {
                HStack {
                    TextField("Name", text: $alias)
                        .focused($aliasFocused)
                        .onSubmit { if canRename { rename() } }
                    Button(action: syncWithProfile) {
                        if isSyncing {
                            ProgressView().controlSize(.small)
                        } else {
                            Label("Sync with TzProfile", systemImage: "person.crop.circle.badge.checkmark")
                        }
                    }
                    .disabled(isSyncing)
                    .help("Fetch the name this address publishes in its TzProfile")
                }
                if let wallet = model.selectedWallet {
                    LabeledContent("Address", value: wallet.address.shortened())
                        .font(.body.monospaced())
                }
                Text("The alias is renamed in ~/.signet.")
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
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Rename", action: rename)
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(!canRename)
            }
        }
        .padding(20)
        .frame(width: 440)
        .onAppear { aliasFocused = true }
    }

    private func syncWithProfile() {
        guard let wallet = model.selectedWallet else { return }
        errorMessage = nil
        isSyncing = true
        Task {
            defer { isSyncing = false }
            if let name = await model.profileName(for: wallet.address) {
                alias = name
            } else {
                errorMessage = "This address has no TzProfile name."
            }
        }
    }

    private func rename() {
        errorMessage = nil
        do {
            try model.renameSelectedWallet(to: trimmedAlias)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

#Preview {
    RenameWalletSheet(model: .preview())
}
