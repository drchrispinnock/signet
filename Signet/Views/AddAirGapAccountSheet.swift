import SwiftUI

/// Adds an account whose key is in AirGap Vault, from the Vault's "Pair Account" code that Scan
/// QR code read. Like a Ledger account, Signet keeps only the address and public key; the
/// secret never leaves the phone, and operations are signed there (`AirGapSigning`).
struct AddAirGapAccountSheet: View {
    @Bindable var model: WalletViewModel
    let accounts: [AirGap.Account]
    @Environment(\.dismiss) private var dismiss

    @State private var chosen: AirGap.Account
    @State private var alias: String
    @State private var addresses: [AirGap.Account: Address] = [:]
    @State private var errorMessage: String?
    @State private var isAdding = false

    init(model: WalletViewModel, accounts: [AirGap.Account]) {
        self.model = model
        self.accounts = accounts
        _chosen = State(initialValue: accounts[0])
        let label = accounts[0].groupLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        _alias = State(initialValue: label.isEmpty ? "AirGap Vault" : label)
    }

    private var address: Address? { addresses[chosen] }
    private var existing: Wallet? { address.flatMap { a in model.wallets.first { $0.address == a } } }
    private var canAdd: Bool { !alias.trimmingCharacters(in: .whitespaces).isEmpty && address != nil && existing == nil && !isAdding }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Add AirGap Vault account", systemImage: "iphone.and.arrow.forward")
                .font(.title2.weight(.semibold))

            Form {
                if accounts.count > 1 {
                    Picker("Account", selection: $chosen) {
                        ForEach(accounts, id: \.self) { account in
                            Text("\(account.groupLabel.isEmpty ? "Account" : account.groupLabel) (\(account.derivationPath))").tag(account)
                        }
                    }
                }
                TextField("Name", text: $alias, prompt: Text("e.g. Savings"))
                    .onSubmit { if canAdd { add() } }

                LabeledContent("Address") {
                    HStack(spacing: 10) {
                        if let address {
                            AccountAvatarView(address: address, network: model.network, size: 32)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(address.value).font(.callout.monospaced()).textSelection(.enabled)
                                if let existing {
                                    Label("Already in your list as “\(existing.alias)”", systemImage: "checkmark.seal")
                                        .font(.caption).foregroundStyle(.secondary)
                                } else {
                                    Text(AddressScheme.tz1.displayName).font(.caption).foregroundStyle(.tertiary)
                                }
                            }
                        } else {
                            ProgressView().controlSize(.small)
                        }
                        Spacer()
                    }
                }
                LabeledContent("Derivation path") { Text(chosen.derivationPath).font(.callout.monospaced()) }
                if !chosen.masterFingerprint.isEmpty {
                    LabeledContent("Vault fingerprint") { Text(chosen.masterFingerprint).font(.callout.monospaced()) }
                }
            }

            Text("The secret key stays in AirGap Vault on your phone. Signet keeps only the address and public key, as it does for a Ledger. Check the address against the one the Vault shows before you use it.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Label("To send, Signet shows each operation as a QR code for the Vault to scan; you approve it on the phone and hold its signed reply up to this Mac's camera. Signing messages for dApps or multisig proposals is not available with the Vault.", systemImage: "info.circle")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle")
                    .font(.callout)
                    .foregroundStyle(.red)
            }

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Add Account", action: add)
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(!canAdd)
            }
        }
        .padding(20)
        .frame(width: 520)
        .task {
            for account in accounts {
                do {
                    addresses[account] = try await model.address(forScannedPublicKey: account.publicKey)
                } catch {
                    errorMessage = "Signet could not read the public key in the Vault's code."
                }
            }
        }
    }

    private func add() {
        guard canAdd else { return }
        isAdding = true
        errorMessage = nil
        Task {
            defer { isAdding = false }
            do {
                try await model.addAirGapAccount(alias: alias, account: chosen)
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
