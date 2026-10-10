import SwiftUI

/// Deploys an octez-client generic multisig: a name, a threshold and the signers, paid for by
/// the selected account. Signers are our accounts, address-book entries, or pasted public keys
/// or tz addresses; an address is resolved to the key it has revealed on chain.
struct CreateMultisigSheet: View {
    @Bindable var model: WalletViewModel
    @Environment(\.dismiss) private var dismiss

    /// One line of the signer list: where it came from and the key it resolved to.
    struct Signer: Identifiable, Equatable {
        enum Source: Equatable { case wallet(Wallet), pasted(String) }
        let source: Source
        var key: String?
        var error: String?
        var id: String {
            switch source {
            case .wallet(let w): "wallet:\(w.id)"
            case .pasted(let text): "pasted:\(text)"
            }
        }
        var title: String {
            switch source {
            case .wallet(let w): w.alias
            case .pasted(let text): WalletViewModel.isPublicKey(text) ? "Public key" : Address(text).shortened()
            }
        }
        var detail: String {
            switch source {
            case .wallet(let w): w.address.shortened()
            case .pasted(let text): String(text.prefix(14)) + "…" + String(text.suffix(6))
            }
        }
    }

    @State private var alias = ""
    @State private var threshold = 2
    @State private var signers: [Signer] = []
    @State private var pasteText = ""
    @State private var estimate: MultisigEstimate?
    @State private var passphrase = ""
    @State private var errorMessage: String?
    @State private var isWorking = false
    @State private var created: MultisigContract?

    private var payer: Wallet? { model.selectedWallet }
    private var needsPassphrase: Bool { payer?.keyKind == .encrypted }
    private var signsOnLedger: Bool { payer?.keyKind == .ledger }
    private var keys: [String] { signers.compactMap(\.key) }
    private var allResolved: Bool { !signers.isEmpty && signers.allSatisfy { $0.key != nil } }
    private var canCreate: Bool {
        !alias.trimmingCharacters(in: .whitespaces).isEmpty && allResolved && threshold >= 1 && threshold <= keys.count
            && payer?.keyKind.canSign == true && estimate != nil && !(needsPassphrase && passphrase.isEmpty) && !isWorking
    }
    private var mine: [Wallet] { model.wallets.filter { $0.keyKind != KeyKind.none } }
    private var addressBook: [Wallet] { model.wallets.filter { $0.keyKind == KeyKind.none && !$0.address.isContract } }
    private var pasteLooksUsable: Bool {
        let t = pasteText.trimmingCharacters(in: .whitespacesAndNewlines)
        return WalletViewModel.isPublicKey(t) || (Address(t).isValidAccount && !Address(t).isContract)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Create multisig").font(.title2.weight(.semibold))
            if let created {
                doneView(created)
            } else {
                form
                buttons
            }
        }
        .padding(20)
        .frame(width: 600)
        .task(id: "\(threshold)-\(keys.joined())-\(allResolved)") { await refreshEstimate() }
    }

    private var form: some View {
        Form {
            TextField("Name", text: $alias, prompt: Text("e.g. treasury"))
            Section("Signers") {
                ForEach(signers) { signer in
                    HStack(spacing: 8) {
                        if case .wallet(let w) = signer.source { AccountAvatarView(address: w.address, size: 20) }
                        Text(signer.title)
                        Text(signer.detail).font(.callout.monospaced()).foregroundStyle(.secondary)
                        Spacer()
                        if let error = signer.error {
                            Label(error, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange).lineLimit(2)
                        } else if let key = signer.key {
                            // The key that will go into the contract, checked to hash to the address shown.
                            Text(String(key.prefix(10)) + "…").font(.caption.monospaced()).foregroundStyle(.tertiary).help(key)
                        } else {
                            ProgressView().controlSize(.small)
                        }
                        Button { signers.removeAll { $0.id == signer.id } } label: { Image(systemName: "minus.circle") }
                            .buttonStyle(.borderless).help("Remove")
                    }
                }
                HStack {
                    Menu("Add account…") {
                        if !mine.isEmpty {
                            Section("My accounts") { ForEach(mine) { w in Button("\(w.alias)  \(w.address.shortened())") { add(.wallet(w)) }.disabled(isListed(w)) } }
                        }
                        if !addressBook.isEmpty {
                            Section("Address book") { ForEach(addressBook) { w in Button("\(w.alias)  \(w.address.shortened())") { add(.wallet(w)) }.disabled(isListed(w)) } }
                        }
                    }
                    .fixedSize()
                    TextField("Public key or tz address", text: $pasteText, prompt: Text("edpk…, sppk…, p2pk…, BLpk… or tz1…"))
                        .font(.callout.monospaced()).autocorrectionDisabled()
                        .onSubmit(addPasted)
                    Button("Add", action: addPasted).disabled(!pasteLooksUsable)
                }
                Text("An address must have revealed its public key (sent at least one operation on this network); otherwise paste the public key.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Stepper(value: $threshold, in: 1...max(1, signers.count)) {
                LabeledContent("Signatures required", value: "\(threshold) of \(signers.count)")
            }
            if let payer {
                LabeledContent("Paid by") {
                    HStack(spacing: 8) {
                        AccountAvatarView(address: payer.address, size: 20)
                        Text(payer.alias)
                        if !payer.keyKind.canSign { Text("cannot sign").font(.caption).foregroundStyle(.red) }
                    }
                }
            }
            if let estimate {
                LabeledContent("Fee", value: AssetBalance.format(estimate.fee, symbol: "tz"))
                LabeledContent("Storage", value: AssetBalance.format(estimate.burn, symbol: "tz"))
            } else if allResolved, threshold <= keys.count {
                LabeledContent("Fee") { ProgressView().controlSize(.small) }
            }
            if needsPassphrase, let payer { SecureField("Password for “\(payer.alias)”", text: $passphrase) }
            if signsOnLedger, isWorking { LedgerPromptLabel(text: "Confirm the origination on your Ledger…") }
            Text("The contract holds tez; spending needs \(threshold) of the \(signers.count) signers. octez-client recognises it as a multisig too.")
                .font(.callout).foregroundStyle(.secondary)
            if let errorMessage { Text(errorMessage).font(.callout).foregroundStyle(.red) }
        }
        .formStyle(.grouped)
    }

    private var buttons: some View {
        HStack {
            if isWorking { ProgressView().controlSize(.small); Text("Deploying…").font(.callout).foregroundStyle(.secondary) }
            Spacer()
            Button("Cancel", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction).disabled(isWorking)
            Button("Create") { Task { await create() } }
                .keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent).disabled(!canCreate)
        }
    }

    private func doneView(_ contract: MultisigContract) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("“\(contract.alias)” is deployed", systemImage: "checkmark.seal.fill").foregroundStyle(.green)
            HStack {
                Text(contract.address.value).font(.callout.monospaced()).textSelection(.enabled)
                Button { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(contract.address.value, forType: .string) } label: { Image(systemName: "doc.on.doc") }
                    .buttonStyle(.borderless).help("Copy address")
            }
            Text("Send tez to that address to fund it. Give the other signers the address so they can add it on their side.")
                .font(.callout).foregroundStyle(.secondary)
            HStack { Spacer(); Button("Done") { dismiss() }.keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent) }
        }
    }

    private func isListed(_ wallet: Wallet) -> Bool {
        signers.contains { if case .wallet(let w) = $0.source { return w.id == wallet.id } else { return false } }
    }

    private func addPasted() {
        let text = pasteText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard pasteLooksUsable, !signers.contains(where: { $0.id == "pasted:\(text)" }) else { return }
        add(.pasted(text))
        pasteText = ""
    }

    private func add(_ source: Signer.Source) {
        let signer = Signer(source: source)
        signers.append(signer)
        Task { await resolve(signer.id) }
    }

    /// Fills in the key for one signer line: our own key, or the one the address revealed on chain.
    private func resolve(_ id: Signer.ID) async {
        guard let index = signers.firstIndex(where: { $0.id == id }) else { return }
        let text: String
        switch signers[index].source {
        case .wallet(let w): text = w.publicKey ?? w.address.value
        case .pasted(let t): text = t
        }
        do {
            let key = try await model.multisigSignerKey(from: text)
            guard let i = signers.firstIndex(where: { $0.id == id }) else { return }
            if signers.contains(where: { $0.id != id && $0.key == key }) {
                signers[i].error = "Already listed"
            } else {
                signers[i].key = key
            }
        } catch {
            guard let i = signers.firstIndex(where: { $0.id == id }) else { return }
            signers[i].error = error.localizedDescription
        }
    }

    private func refreshEstimate() async {
        estimate = nil
        errorMessage = nil
        guard allResolved, threshold <= keys.count, payer?.publicKey != nil else { return }
        do { estimate = try await model.estimateCreateMultisig(threshold: threshold, keys: keys) } catch { errorMessage = error.localizedDescription }
    }

    private func create() async {
        errorMessage = nil
        isWorking = true
        defer { isWorking = false }
        do {
            created = try await model.createMultisig(alias: alias, threshold: threshold, keys: keys, passphrase: needsPassphrase ? passphrase : nil)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
