import SwiftUI

/// Send shielded: a private transfer from the account's shielded wallet to someone else's
/// shielded address, with an optional memo only they can read. The recipient is a payment
/// address, a JSON record another wallet printed (Signet's "Shielded address…" or the tzel
/// CLI's `receive`), pasted here or picked from the address book; the fingerprint shown is
/// what the two of you compare. The rollup applies the transfer within minutes; the recipient
/// sees the note on their next scan.
struct SendShieldedSheet: View {
    @Bindable var model: WalletViewModel
    @Environment(\.dismiss) private var dismiss

    enum Step: Hashable { case compose, working, done(SendShieldedReceipt) }
    private static let pasted = "pasted"

    @State private var amountText = ""
    @State private var memo = ""
    @State private var contacts: [ShieldedContact] = []
    @State private var chosen = SendShieldedSheet.pasted
    @State private var pastedJSON = ""
    @State private var parsed: ShieldedContact?
    @State private var parseError: String?
    @State private var saveName = ""
    @State private var estimate: SendShieldedEstimate?
    @State private var estimateError: String?
    @State private var errorMessage: String?
    @State private var step: Step = .compose
    @State private var submitted: SendShieldedEstimate?

    private var wallet: Wallet? { submitted?.context.wallet ?? model.selectedWallet }
    private var shielded: AssetBalance? { model.assets.first { $0.kind == .shielded } }
    private var available: Decimal? { model.shieldedWallet.map { Decimal($0.availableMutez) / Mutez.perTez } }
    private var tokenIsSet: Bool { model.shieldedOperatorTokenIsSet(for: model.network) }
    private var amount: Decimal? {
        if let submitted { return submitted.amount }
        let text = amountText.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        guard let value = Decimal(string: text, locale: Locale(identifier: "en_US_POSIX")), value > 0, value.isFinite else { return nil }
        return value
    }
    /// The recipient in use: a contact, or what was pasted once it parses.
    private var recipient: ShieldedContact? {
        if chosen == Self.pasted { return parsed }
        return contacts.first { $0.fingerprint == chosen }
    }
    private var canConfirm: Bool {
        guard let estimate, let amount, let recipient else { return false }
        return estimate.amount == amount && estimate.recipient.fingerprint == recipient.fingerprint && estimate.memo == memo && estimate.context == model.bridgeContext
            && model.canShield && tokenIsSet && step == .compose
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            switch step {
            case .compose:
                form
                sent
            case .working:
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(model.shieldProgress?.text ?? "Sending \(AssetBalance.format(amount ?? 0, symbol: "tz"))…").font(.callout).foregroundStyle(.secondary)
                }
            case .done(let receipt):
                doneView(receipt)
            }
            if let errorMessage { Text(errorMessage).font(.callout).foregroundStyle(.red) }
            buttons
        }
        .padding(20)
        .frame(width: 620)
        .onAppear { contacts = (try? model.shieldedContacts()) ?? []; if let first = contacts.first { chosen = first.fingerprint } }
        .task(id: pastedJSON) { await parsePasted() }
        .task(id: EstimateKey(amount: amountText, recipient: recipient?.fingerprint, memo: memo, context: model.bridgeContext, step: step)) { await refreshEstimate() }
    }

    // MARK: Pieces

    private var header: some View {
        HStack(spacing: 12) {
            if let wallet { AccountAvatarView(address: wallet.address, size: 40) }
            VStack(alignment: .leading, spacing: 2) {
                Text("Send shielded").font(.title2.weight(.semibold))
                HStack(spacing: 6) {
                    if let wallet { Text("\(wallet.alias)  \(wallet.address.shortened())").font(.callout).foregroundStyle(.secondary) }
                    if let shielded, shielded.unavailable == nil {
                        Text("·").foregroundStyle(.secondary)
                        Text("\(shielded.formattedAmount) shielded\(available.map { ", \(AssetBalance.format($0, symbol: "tz")) available" } ?? "")").font(.callout).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var form: some View {
        Form {
            Picker("To", selection: $chosen) {
                ForEach(contacts) { contact in Text("\(contact.name)  \(Self.short(contact.fingerprint))").tag(contact.fingerprint) }
                Text("A pasted shielded address…").tag(Self.pasted)
            }
            if chosen == Self.pasted {
                TextEditor(text: $pastedJSON)
                    .font(.caption.monospaced()).frame(height: 90)
                    .overlay(alignment: .topLeading) {
                        if pastedJSON.isEmpty { Text("Paste the recipient's shielded address (the JSON their wallet printed)").font(.caption).foregroundStyle(.tertiary).padding(6).allowsHitTesting(false) }
                    }
                if let parseError, !pastedJSON.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(parseError).font(.caption).foregroundStyle(.orange)
                } else if let parsed {
                    LabeledContent("Fingerprint") { Text(Self.short(parsed.fingerprint)).font(.callout.monospaced()).textSelection(.enabled) }
                    if parsed.name.isEmpty {
                        HStack {
                            TextField("Name", text: $saveName, prompt: Text("Name for the address book")).frame(width: 240)
                            Button("Save") { save(parsed) }.disabled(saveName.trimmingCharacters(in: .whitespaces).isEmpty)
                        }
                    } else {
                        Text("Already in the address book as “\(parsed.name)”.").font(.caption).foregroundStyle(.secondary)
                    }
                }
            } else if let recipient {
                LabeledContent("Fingerprint") { Text(Self.short(recipient.fingerprint)).font(.callout.monospaced()).textSelection(.enabled) }
            }
            LabeledContent("Amount") {
                HStack(spacing: 4) {
                    TextField("", text: $amountText, prompt: Text("0")).multilineTextAlignment(.trailing).frame(width: 140)
                    Text("tz").foregroundStyle(.secondary)
                }
            }
            TextField("Memo", text: $memo, prompt: Text("Optional, only the recipient can read it"))
            if let estimate {
                LabeledContent("Rollup and producer fees", value: AssetBalance.format(estimate.fees, symbol: "tz"))
                LabeledContent("Spent from notes") {
                    Text("\(AssetBalance.format(Decimal(estimate.inputMutez) / Mutez.perTez, symbol: "tz")) in \(estimate.inputs.count) note\(estimate.inputs.count == 1 ? "" : "s"), \(AssetBalance.format(estimate.change, symbol: "tz")) back as change")
                }
            } else if amount != nil, recipient != nil {
                LabeledContent("Rollup and producer fees") {
                    if let estimateError { Text(estimateError).font(.callout).foregroundStyle(.orange).multilineTextAlignment(.trailing) }
                    else { ProgressView().controlSize(.small) }
                }
            }
            Text("Nothing on the rollup names the recipient: only their viewing keys find the note. Compare the fingerprint with them before sending; a note sent to the wrong address cannot be recovered. The change comes back as a new note of yours.")
                .font(.callout).foregroundStyle(.secondary)
            if !model.canShield {
                Text("Sending needs Shielded Transactions on for this network and an account Signet can sign for.").font(.callout).foregroundStyle(.orange)
            } else if !tokenIsSet {
                Label("Sending needs the TzEL operator's access token. Enter it in Networks under Shielded Transactions.", systemImage: "key").font(.callout).foregroundStyle(.orange)
            }
        }
        .formStyle(.grouped)
        .scrollDisabled(true)
    }

    /// Transfers of this account the rollup has not applied yet, and recent ones.
    @ViewBuilder
    private var sent: some View {
        let list = model.shieldedTransfers
        if !list.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("Sent").font(.headline)
                ForEach(list) { transfer in
                    HStack {
                        Text(AssetBalance.format(Decimal(transfer.amount) / Mutez.perTez, symbol: "tz")).font(.callout.monospacedDigit())
                        Text("to \(transfer.recipientName ?? Self.short(transfer.recipientFingerprint))").font(.callout).foregroundStyle(.secondary)
                        Spacer()
                        Text(transfer.applied ? "Applied by the rollup" : "With the operator").font(.caption).foregroundStyle(.secondary)
                        if !transfer.applied, transfer.created < Date().addingTimeInterval(-1800) {
                            Button("Forget") { errorMessage = nil; do { try model.forgetTransfer(transfer.id) } catch { errorMessage = error.localizedDescription } }.controlSize(.small)
                                .help("Drops the record and frees its notes. Only for a transfer the operator never delivered; if it lands after all, the notes show as spent on the next refresh.")
                        }
                    }
                }
            }
        }
    }

    private func doneView(_ receipt: SendShieldedReceipt) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Sent \(AssetBalance.format(receipt.amount, symbol: "tz")) to \(receipt.transfer.recipientName ?? Self.short(receipt.transfer.recipientFingerprint))", systemImage: "checkmark.seal.fill").foregroundStyle(.green)
            Text("The operator has the transfer (submission \(receipt.transfer.submissionID)). The rollup spends your notes once it applies it, and the recipient finds theirs on their next scan.")
                .font(.callout).foregroundStyle(.secondary)
            if let hash = receipt.transfer.operationHash {
                HStack(spacing: 8) {
                    Text("Delivered in").font(.callout).foregroundStyle(.secondary)
                    Text(hash).font(.callout.monospaced()).textSelection(.enabled).lineLimit(1).truncationMode(.middle)
                    if let url = model.network.explorerURL(operation: hash) { Link("View in explorer", destination: url) }
                }
            }
        }
    }

    private var buttons: some View {
        HStack {
            Spacer()
            switch step {
            case .compose:
                Button("Cancel", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Send") { Task { await send() } }
                    .keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent).disabled(!canConfirm)
            case .working:
                Button("Cancel", role: .cancel) { dismiss() }.disabled(true)
            case .done:
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent)
            }
        }
    }

    static func short(_ fingerprint: String) -> String {
        fingerprint.count > 20 ? "\(fingerprint.prefix(12))…\(fingerprint.suffix(6))" : fingerprint
    }

    // MARK: Actions

    private struct EstimateKey: Hashable {
        let amount: String
        let recipient: String?
        let memo: String
        let context: WalletViewModel.BridgeContext?
        let step: Step
    }

    private func parsePasted() async {
        parsed = nil
        parseError = nil
        guard !pastedJSON.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        try? await Task.sleep(for: .milliseconds(300))
        guard !Task.isCancelled else { return }
        do {
            let contact = try await model.shieldedRecipient(from: pastedJSON)
            if !Task.isCancelled { parsed = contact }
        } catch {
            if !Task.isCancelled { parseError = error.localizedDescription }
        }
    }

    private func save(_ contact: ShieldedContact) {
        errorMessage = nil
        do {
            try model.addShieldedContact(contact, name: saveName)
            contacts = (try? model.shieldedContacts()) ?? []
            chosen = contact.fingerprint
            saveName = ""
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func refreshEstimate() async {
        estimate = nil
        estimateError = nil
        guard step == .compose, let amount, let recipient, model.canShield else { return }
        try? await Task.sleep(for: .milliseconds(300))
        guard !Task.isCancelled else { return }
        do {
            let result = try await model.estimateSendShielded(amount: amount, recipient: recipient, memo: memo)
            if !Task.isCancelled { estimate = result }
        } catch {
            if !Task.isCancelled { estimateError = error.localizedDescription }
        }
    }

    private func send() async {
        guard let estimate, canConfirm else { return }
        errorMessage = nil
        submitted = estimate
        step = .working
        do {
            let receipt = try await model.sendShielded(approved: estimate)
            step = .done(receipt)
        } catch {
            errorMessage = error.localizedDescription
            submitted = nil
            step = .compose
        }
    }
}
