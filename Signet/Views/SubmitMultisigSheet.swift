import SwiftUI

/// Gathers the other signers' signatures on a proposal and submits it from one of our accounts.
struct SubmitMultisigSheet: View {
    @Bindable var model: WalletViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var proposalID: MultisigProposal.ID?
    @State private var pasted = ""
    @State private var submitter: Wallet?
    @State private var estimate: MultisigEstimate?
    @State private var passphrase = ""
    @State private var errorMessage: String?
    @State private var isWorking = false
    @State private var sentHash: String?

    private var proposals: [MultisigProposal] { model.currentMultisigProposals }
    private var proposal: MultisigProposal? { proposals.first { $0.id == proposalID } }
    private var submitters: [Wallet] { model.wallets.filter { $0.keyKind.canSign && $0.publicKey != nil } }
    private var needsPassphrase: Bool { submitter?.keyKind == .encrypted }
    private var signsOnLedger: Bool { submitter?.keyKind == .ledger }
    private var canSubmit: Bool {
        proposal?.isReady == true && submitter != nil && estimate != nil && !isWorking && !(needsPassphrase && passphrase.isEmpty)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Submit multisig transaction").font(.title2.weight(.semibold))
            if let sentHash {
                doneView(sentHash)
            } else if proposals.isEmpty {
                Text("No pending multisig transaction on \(model.network.name). Propose one with Sign multisig transaction… first.").foregroundStyle(.secondary)
                HStack { Spacer(); Button("Close") { dismiss() }.keyboardShortcut(.cancelAction) }
            } else {
                form
                buttons
            }
        }
        .padding(20)
        .frame(width: 580)
        .onAppear { proposalID = proposals.first?.id; submitter = submitters.first }
        .task(id: "\(proposalID?.uuidString ?? "")-\(proposal?.signatures.count ?? 0)-\(submitter?.id ?? "")") { await refreshEstimate() }
    }

    private var form: some View {
        Form {
            Picker("Transaction", selection: $proposalID) {
                ForEach(proposals) { p in
                    Text("\(p.summary) from \(p.contractAlias) · counter \(p.counter)").tag(Optional(p.id))
                }
            }
            if let proposal {
                LabeledContent("Signatures", value: "\(proposal.signatures.count) of \(proposal.threshold) needed")
                ForEach(proposal.signatures, id: \.signature) { sig in
                    HStack {
                        if let pk = sig.publicKey, let mine = model.wallets.first(where: { $0.publicKey == pk }) {
                            Label(mine.alias, systemImage: "checkmark.seal").font(.callout)
                        } else {
                            Text("pasted").font(.callout).foregroundStyle(.secondary)
                        }
                        Text(sig.signature.prefix(16) + "…").font(.callout.monospaced()).foregroundStyle(.secondary)
                        Spacer()
                    }
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("Paste the other signers' signatures (one per line or separated by spaces)").font(.callout)
                    TextEditor(text: $pasted).font(.callout.monospaced()).frame(height: 60)
                    HStack { Spacer(); Button("Add signatures", action: addPasted).disabled(pasted.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
                }
                Picker("Submit from", selection: $submitter) {
                    ForEach(submitters) { w in Text("\(w.alias)  \(w.address.shortened())").tag(Optional(w)) }
                }
                if proposal.isReady {
                    if let estimate { LabeledContent("Fee", value: AssetBalance.format(estimate.fee, symbol: "tz")) } else { LabeledContent("Fee") { ProgressView().controlSize(.small) } }
                } else {
                    Text("\(proposal.missing) more signature\(proposal.missing == 1 ? "" : "s") needed before this can be submitted.").font(.callout).foregroundStyle(.secondary)
                }
                if needsPassphrase, let submitter { SecureField("Password for “\(submitter.alias)”", text: $passphrase) }
                if signsOnLedger, isWorking { LedgerPromptLabel(text: "Confirm on your Ledger…") }
                Text("The submitting account pays the fee; the multisig does the rest. Signatures are checked against the multisig's keys before anything is sent.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            if let errorMessage { Text(errorMessage).font(.callout).foregroundStyle(.red) }
        }
        .formStyle(.grouped)
    }

    private var buttons: some View {
        HStack {
            if let proposal, !isWorking {
                Button("Discard proposal", role: .destructive) { try? model.removeMultisigProposal(proposal); proposalID = proposals.first?.id }
            }
            if isWorking { ProgressView().controlSize(.small); Text("Submitting…").font(.callout).foregroundStyle(.secondary) }
            Spacer()
            Button("Cancel", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction).disabled(isWorking)
            Button("Submit") { Task { await submit() } }.keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent).disabled(!canSubmit)
        }
    }

    private func doneView(_ hash: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Submitted and included in a block", systemImage: "checkmark.seal.fill").foregroundStyle(.green)
            HStack {
                Text(hash).font(.callout.monospaced()).textSelection(.enabled)
                if let url = model.network.explorerURL(operation: hash) { Link("View", destination: url) }
            }
            HStack { Spacer(); Button("Done") { dismiss() }.keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent) }
        }
    }

    private func addPasted() {
        guard let proposal else { return }
        errorMessage = nil
        for token in pasted.split(whereSeparator: { $0.isWhitespace || $0 == "," }) {
            do { try model.addMultisigSignature(String(token), to: proposal) } catch { errorMessage = error.localizedDescription }
        }
        pasted = ""
    }

    private func refreshEstimate() async {
        estimate = nil
        guard let proposal, proposal.isReady, let submitter else { return }
        errorMessage = nil
        do { estimate = try await model.estimateSubmitMultisig(proposal, from: submitter) } catch { errorMessage = error.localizedDescription }
    }

    private func submit() async {
        guard let proposal, let submitter else { return }
        errorMessage = nil
        isWorking = true
        defer { isWorking = false }
        do { sentHash = try await model.submitMultisig(proposal, from: submitter, passphrase: needsPassphrase ? passphrase : nil) } catch { errorMessage = error.localizedDescription }
    }
}
