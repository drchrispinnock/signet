import SwiftUI

/// Adds an address book entry: a named address Signet holds no key for.
struct AddAddressSheet: View {
    @Bindable var model: WalletViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var alias = ""
    @State private var address = ""
    @State private var previewDomains: [String] = []
    @State private var errorMessage: String?
    @State private var isAdding = false
    @FocusState private var focus: Field?

    private enum Field { case alias, address }

    private var trimmedAddress: Address { Address(address.trimmingCharacters(in: .whitespacesAndNewlines)) }
    private var addressLooksValid: Bool { trimmedAddress.isValidAccount }
    private var canAdd: Bool { !alias.trimmingCharacters(in: .whitespaces).isEmpty && addressLooksValid && !isAdding }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Add address")
                .font(.title2.weight(.semibold))

            Form {
                TextField("Name", text: $alias, prompt: Text("e.g. Alice"))
                    .focused($focus, equals: .alias)
                TextField("Address", text: $address, prompt: Text("tz1… or KT1…"))
                    .font(.body.monospaced())
                    .focused($focus, equals: .address)
                    .autocorrectionDisabled()
                    .onSubmit { if canAdd { add() } }

                LabeledContent("Preview") {
                    HStack(spacing: 10) {
                        if addressLooksValid {
                            AccountAvatarView(address: trimmedAddress, network: model.network, size: 32)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(trimmedAddress.shortened())
                                    .font(.callout.monospaced())
                                ForEach(previewDomains, id: \.self) { domain in
                                    Text(domain).font(.callout).foregroundStyle(.secondary)
                                }
                                if let scheme = trimmedAddress.scheme {
                                    Text(scheme.displayName).font(.caption).foregroundStyle(.tertiary)
                                } else if trimmedAddress.isContract {
                                    Text("Smart contract").font(.caption).foregroundStyle(.tertiary)
                                }
                            }
                        } else if address.isEmpty {
                            Text("Paste or type an address").foregroundStyle(.tertiary)
                        } else {
                            Label("Not a valid Tezos address", systemImage: "exclamationmark.triangle")
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                }

                Text("This only records the address. You can watch its balance and send to it, but not spend from it.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .formStyle(.grouped)
            .scrollDisabled(true)

            if let errorMessage {
                Text(errorMessage).font(.callout).foregroundStyle(.red)
            }

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Add", action: add)
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(!canAdd)
            }
        }
        .padding(20)
        .frame(width: 480)
        .onAppear { focus = .alias }
        .task(id: address) {
            previewDomains = []
            guard addressLooksValid else { return }
            try? await Task.sleep(for: .milliseconds(300))  // debounce typing
            guard !Task.isCancelled else { return }
            previewDomains = await model.domainNames(for: trimmedAddress)
        }
    }

    private func add() {
        errorMessage = nil
        isAdding = true
        Task {
            defer { isAdding = false }
            do {
                try await model.addWatchOnlyWallet(alias: alias, address: address)
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

#Preview {
    AddAddressSheet(model: .preview())
}
