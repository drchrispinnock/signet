import SwiftUI

/// Proposes an action from a multisig (a transfer, or a change of delegate) and signs it with one
/// of our keys. The signature is shown for handing to whoever submits; the proposal is kept so more
/// signatures can be gathered.
struct SignMultisigSheet: View {
    @Bindable var model: WalletViewModel
    @Environment(\.dismiss) private var dismiss

    enum Kind: String, CaseIterable, Identifiable {
        case transfer = "Transfer", delegate = "Set delegate", undelegate = "Remove delegate"
        var id: String { rawValue }
    }

    @State private var contract: MultisigContract?
    @State private var info: MultisigInfo?
    @State private var infoError: String?
    @State private var existing: MultisigProposal?
    @State private var kind: Kind = .transfer
    @State private var amountText = ""
    @State private var destination = ""
    @State private var baker = ""
    @State private var bakers: [BakerCandidate] = []
    @State private var signer: Wallet?
    @State private var passphrase = ""
    @State private var errorMessage: String?
    @State private var isWorking = false
    @State private var result: (proposal: MultisigProposal, signature: MultisigSignature)?

    private var amount: Decimal? {
        let text = amountText.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        guard let value = Decimal(string: text, locale: Locale(identifier: "en_US_POSIX")), value > 0 else { return nil }
        return value
    }
    private var destinationAddress: Address { Address(destination.trimmingCharacters(in: .whitespacesAndNewlines)) }
    private var bakerAddress: Address { Address(baker.trimmingCharacters(in: .whitespacesAndNewlines)) }
    private var signers: [Wallet] { info?.signers(among: model.wallets) ?? [] }
    private var needsPassphrase: Bool { signer?.keyKind == .encrypted }
    private var signsOnLedger: Bool { signer?.keyKind == .ledger }
    private var pending: [MultisigProposal] { model.currentMultisigProposals.filter { $0.contractAddress == contract?.address.value } }
    /// What the form describes, when it is complete.
    private var action: MultisigAction? {
        switch kind {
        case .transfer:
            guard let amount, destinationAddress.isValidAccount else { return nil }
            return .transfer(amountMutez: Mutez.fromTez(amount), destination: destinationAddress.value)
        case .delegate:
            guard bakerAddress.isValidAccount, !bakerAddress.isContract else { return nil }
            return .setDelegate(delegate: bakerAddress.value)
        case .undelegate:
            return .setDelegate(delegate: nil)
        }
    }
    private var canSign: Bool {
        contract != nil && info?.isGenericMultisig == true && signer != nil && !isWorking && !(needsPassphrase && passphrase.isEmpty)
            && (existing != nil || action != nil)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Sign multisig transaction").font(.title2.weight(.semibold))
            if let result {
                doneView(result.proposal, result.signature)
            } else if model.multisigContracts.isEmpty {
                Text("No multisig yet. Use Create multisig… or Add multisig… first.").foregroundStyle(.secondary)
                HStack { Spacer(); Button("Close") { dismiss() }.keyboardShortcut(.cancelAction) }
            } else {
                form
                buttons
            }
        }
        .padding(20)
        .frame(width: 560)
        .onAppear {
            if let preset = model.signMultisigPreset {
                contract = preset.contract
                kind = preset.delegating ? .delegate : .transfer
            } else if let selected = model.selectedWallet, selected.address.isContract {
                contract = model.multisigContracts.first { $0.address == selected.address }
            }
            if contract == nil { contract = model.multisigContracts.first }
        }
        .task(id: contract) { await loadInfo() }
        .task { bakers = await model.bakers() }
    }

    private var form: some View {
        Form {
            Picker("Multisig", selection: $contract) {
                ForEach(model.multisigContracts) { c in Text("\(c.alias)  \(c.address.shortened())").tag(Optional(c)) }
            }
            LabeledContent("State") {
                if let info {
                    if info.isGenericMultisig {
                        Text("\(info.threshold) of \(info.keys.count) signatures · \(AssetBalance.format(info.balance, symbol: "tz")) · counter \(info.counter)")
                    } else {
                        Label("Not an octez-client multisig", systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                    }
                } else if let infoError { Text(infoError).foregroundStyle(.secondary) } else { ProgressView().controlSize(.small) }
            }
            if !pending.isEmpty {
                Picker("Transaction", selection: $existing) {
                    Text("New").tag(Optional<MultisigProposal>.none)
                    ForEach(pending) { p in
                        Text("\(p.summary) · \(p.signatures.count)/\(p.threshold) signed").tag(Optional(p))
                    }
                }
            }
            if existing == nil {
                Picker("Action", selection: $kind) { ForEach(Kind.allCases) { Text($0.rawValue).tag($0) } }
                    .pickerStyle(.segmented)
                switch kind {
                case .transfer:
                    TextField("Amount (tez)", text: $amountText, prompt: Text("0.0")).monospacedDigit()
                    HStack {
                        TextField("To", text: $destination, prompt: Text("tz1… or KT1…")).font(.body.monospaced()).autocorrectionDisabled()
                        Menu("Choose…") {
                            let candidates = model.wallets.filter { $0.address != contract?.address }
                            let mine = candidates.filter { $0.keyKind != KeyKind.none }
                            let book = candidates.filter { $0.keyKind == KeyKind.none }
                            if !mine.isEmpty { Section("My accounts") { ForEach(mine) { w in Button("\(w.alias)  \(w.address.shortened())") { destination = w.address.value } } } }
                            if !book.isEmpty { Section("Address book") { ForEach(book) { w in Button("\(w.alias)  \(w.address.shortened())") { destination = w.address.value } } } }
                        }
                        .fixedSize()
                    }
                case .delegate:
                    HStack {
                        TextField("Baker", text: $baker, prompt: Text("tz1…")).font(.body.monospaced()).autocorrectionDisabled()
                        Menu("Choose…") {
                            let mine = model.wallets.filter { $0.keyKind != KeyKind.none && !$0.address.isContract }
                            if !mine.isEmpty { Section("My accounts") { ForEach(mine) { w in Button("\(w.alias)  \(w.address.shortened())") { baker = w.address.value } } } }
                            if !bakers.isEmpty {
                                Section("Bakers") {
                                    ForEach(bakers.prefix(40)) { b in Button("\(b.alias ?? b.address.shortened())  \(b.address.shortened())") { baker = b.address.value } }
                                }
                            }
                        }
                        .fixedSize()
                    }
                    if bakerAddress.isValidAccount, let known = bakers.first(where: { $0.address == bakerAddress }) {
                        LabeledContent("Baker") { HStack(spacing: 8) { AccountAvatarView(address: known.address, size: 22); Text(known.alias ?? known.address.shortened()) } }
                    }
                case .undelegate:
                    Text("The multisig's tez will no longer be delegated.").font(.callout).foregroundStyle(.secondary)
                }
            }
            Picker("Sign with", selection: $signer) {
                if signers.isEmpty { Text("None of your accounts is a signer").tag(Optional<Wallet>.none) }
                ForEach(signers) { w in Text("\(w.alias)  \(w.address.shortened())").tag(Optional(w)) }
            }
            .onChange(of: signers) { _, new in if signer.map({ !new.contains($0) }) ?? true { signer = new.first } }
            if needsPassphrase, let signer { SecureField("Password for “\(signer.alias)”", text: $passphrase) }
            if signsOnLedger, isWorking { LedgerPromptLabel(text: "Sign on your Ledger…") }
            Text("Nothing is sent yet. Your signature goes to whoever submits the transaction, together with the other signers' signatures.")
                .font(.callout).foregroundStyle(.secondary)
            if let errorMessage { Text(errorMessage).font(.callout).foregroundStyle(.red) }
        }
        .formStyle(.grouped)
    }

    private var buttons: some View {
        HStack {
            if isWorking { ProgressView().controlSize(.small); Text("Signing…").font(.callout).foregroundStyle(.secondary) }
            Spacer()
            Button("Cancel", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction).disabled(isWorking)
            Button("Sign") { Task { await sign() } }.keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent).disabled(!canSign)
        }
    }

    private func doneView(_ proposal: MultisigProposal, _ signature: MultisigSignature) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Signed: \(proposal.summary) from “\(proposal.contractAlias)”", systemImage: "checkmark.seal.fill").foregroundStyle(.green)
            Text("\(proposal.signatures.count) of \(proposal.threshold) signatures gathered (counter \(proposal.counter)).").font(.callout).foregroundStyle(.secondary)
            GroupBox("Your signature") {
                HStack(alignment: .top) {
                    Text(signature.signature).font(.callout.monospaced()).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                    Button { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(signature.signature, forType: .string) } label: { Image(systemName: "doc.on.doc") }
                        .buttonStyle(.borderless).help("Copy signature")
                }
            }
            Text(proposal.isReady
                 ? "Enough signatures: use Submit multisig transaction… to send it."
                 : "Give this signature to whoever will submit, or collect the others' and submit it yourself from Submit multisig transaction….")
                .font(.callout).foregroundStyle(.secondary)
            HStack { Spacer(); Button("Done") { dismiss() }.keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent) }
        }
    }

    private func loadInfo() async {
        info = nil; infoError = nil; existing = nil
        guard let contract else { return }
        do { info = try await model.multisigInfo(contract) } catch { infoError = error.localizedDescription }
        signer = signers.first
    }

    private func sign() async {
        guard let contract, let signer else { return }
        errorMessage = nil
        isWorking = true
        defer { isWorking = false }
        do {
            let proposal: MultisigProposal
            if let existing {
                proposal = existing
            } else {
                guard let action else { return }
                proposal = try await model.proposeMultisig(action, from: contract)
            }
            let signature = try await model.signMultisigProposal(proposal, with: signer, passphrase: needsPassphrase ? passphrase : nil)
            let updated = model.multisigProposals.first { $0.id == proposal.id } ?? proposal
            result = (updated, signature)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
