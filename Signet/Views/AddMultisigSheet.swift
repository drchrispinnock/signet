import SwiftUI

/// Records an existing multisig by address, once the chain confirms it is the generic multisig
/// and one of our accounts is a signer.
struct AddMultisigSheet: View {
    @Bindable var model: WalletViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var alias = ""
    @State private var address = ""
    @State private var info: MultisigInfo?
    @State private var lookupError: String?
    @State private var errorMessage: String?
    @State private var isAdding = false

    private var trimmedAddress: Address { Address(address.trimmingCharacters(in: .whitespacesAndNewlines)) }
    private var addressLooksValid: Bool { trimmedAddress.isContract && trimmedAddress.isValidAccount }
    private var members: [Wallet] { info?.members(among: model.wallets) ?? [] }
    private var canAdd: Bool {
        !alias.trimmingCharacters(in: .whitespaces).isEmpty && info?.isGenericMultisig == true && !members.isEmpty && !isAdding
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Add multisig").font(.title2.weight(.semibold))
            Form {
                TextField("Name", text: $alias, prompt: Text("e.g. treasury"))
                TextField("Contract address", text: $address, prompt: Text("KT1…"))
                    .font(.body.monospaced()).autocorrectionDisabled()
                LabeledContent("Contract") {
                    if let info {
                        if info.isGenericMultisig {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("\(info.threshold) of \(info.keys.count) signatures · \(AssetBalance.format(info.balance, symbol: "tz"))")
                                ForEach(info.keys, id: \.self) { key in
                                    if let mine = model.wallets.first(where: { $0.publicKey == key }) {
                                        Label("\(mine.alias) (yours)", systemImage: "checkmark.seal").font(.callout)
                                    } else {
                                        Text(key.prefix(14) + "…").font(.callout.monospaced()).foregroundStyle(.secondary)
                                    }
                                }
                                if members.isEmpty {
                                    Label("None of your accounts is a signer", systemImage: "exclamationmark.triangle").font(.callout).foregroundStyle(.orange)
                                }
                            }
                        } else {
                            Label("Not an octez-client multisig", systemImage: "exclamationmark.triangle").font(.callout).foregroundStyle(.orange)
                        }
                    } else if let lookupError {
                        Text(lookupError).font(.callout).foregroundStyle(.secondary)
                    } else if addressLooksValid {
                        ProgressView().controlSize(.small)
                    } else {
                        Text(address.isEmpty ? "Paste the multisig's address" : "Not a contract address").foregroundStyle(.tertiary)
                    }
                }
                Text("Only multisigs that one of your accounts can sign for can be added.").font(.callout).foregroundStyle(.secondary)
                if let errorMessage { Text(errorMessage).font(.callout).foregroundStyle(.red) }
            }
            .formStyle(.grouped).scrollDisabled(true)
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Add") { Task { await add() } }.keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent).disabled(!canAdd)
            }
        }
        .padding(20)
        .frame(width: 520)
        .task(id: address) {
            info = nil; lookupError = nil
            guard addressLooksValid else { return }
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            do { info = try await model.multisigInfo(MultisigContract(alias: "", address: trimmedAddress)) } catch { lookupError = error.localizedDescription }
        }
    }

    private func add() async {
        errorMessage = nil
        isAdding = true
        defer { isAdding = false }
        do { _ = try await model.addMultisig(alias: alias, address: address); dismiss() } catch { errorMessage = error.localizedDescription }
    }
}
