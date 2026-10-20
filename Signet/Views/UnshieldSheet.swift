import SwiftUI

/// Unshield tez: moves tez from the account's shielded wallet on the TzEL rollup to an account
/// on Tezos. The rollup proves and applies it within minutes, but the tez only reach Tezos
/// through the rollup's outbox, which the account executes here once the commitment covering
/// it is cemented (about 14 days on Shadownet). The sheet lists every withdrawal under way with
/// where it stands and an Execute button when its time has come.
struct UnshieldSheet: View {
    @Bindable var model: WalletViewModel
    @Environment(\.dismiss) private var dismiss

    enum Step: Hashable { case compose, working, done(UnshieldReceipt) }

    @State private var amountText = ""
    @State private var recipient = ""
    @State private var estimate: UnshieldEstimate?
    @State private var estimateError: String?
    @State private var errorMessage: String?
    @State private var step: Step = .compose
    @State private var submitted: UnshieldEstimate?
    @State private var execution: WithdrawalExecutionEstimate?
    @State private var executing: String?
    @State private var executionPassphrase = ""
    @State private var executedHash: String?

    private var wallet: Wallet? { submitted?.context.wallet ?? model.selectedWallet }
    private var network: Network { submitted?.context.network ?? model.network }
    private var shielded: AssetBalance? { model.assets.first { $0.kind == .shielded } }
    private var available: Decimal? { model.shieldedWallet.map { Decimal($0.availableMutez) / Mutez.perTez } }
    private var tokenIsSet: Bool { model.shieldedOperatorTokenIsSet(for: model.network) }
    private var needsPassphrase: Bool { wallet?.keyKind == .encrypted }
    private var signsOnLedger: Bool { wallet?.keyKind == .ledger }
    private var amount: Decimal? {
        if let submitted { return submitted.amount }
        let text = amountText.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        guard let value = Decimal(string: text, locale: Locale(identifier: "en_US_POSIX")), value > 0, value.isFinite else { return nil }
        return value
    }
    private var trimmedRecipient: String { recipient.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var canConfirm: Bool {
        guard let estimate, let amount else { return false }
        return estimate.amount == amount && estimate.recipient == trimmedRecipient && estimate.context == model.bridgeContext
            && model.canShield && tokenIsSet && step == .compose && executing == nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            switch step {
            case .compose:
                sides
                form
                withdrawals
            case .working:
                sides
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(model.shieldProgress?.text ?? "Unshielding \(AssetBalance.format(amount ?? 0, symbol: "tz"))…").font(.callout).foregroundStyle(.secondary)
                }
            case .done(let receipt):
                doneView(receipt)
            }
            if let errorMessage { Text(errorMessage).font(.callout).foregroundStyle(.red) }
            buttons
        }
        .padding(20)
        .frame(width: 600)
        .onAppear { if recipient.isEmpty, let wallet { recipient = wallet.address.value } }
        .task(id: EstimateKey(amount: amountText, recipient: recipient, context: model.bridgeContext, step: step)) { await refreshEstimate() }
    }

    // MARK: Pieces

    private var header: some View {
        HStack(spacing: 12) {
            if let wallet { AccountAvatarView(address: wallet.address, size: 40) }
            VStack(alignment: .leading, spacing: 2) {
                Text("Unshield tez").font(.title2.weight(.semibold))
                if let wallet { Text("\(wallet.alias)  \(wallet.address.shortened())").font(.callout).foregroundStyle(.secondary) }
            }
        }
    }

    private var sides: some View {
        HStack(spacing: 12) {
            side(image: "ShieldLogo", title: "Shielded", balance: shielded.map { $0.unavailable == nil ? $0.formattedAmount : "—" }, note: available.map { "\(AssetBalance.format($0, symbol: "tz")) available" } ?? "on the TzEL rollup")
            Image(systemName: "arrow.right.circle.fill").font(.system(size: 32)).foregroundStyle(.tint)
                .accessibilityLabel("Direction: Shielded to Tezos")
            side(image: "TezosToken", title: "Tezos", balance: model.tezBalance.map { AssetBalance.format($0.spendable, symbol: "tz") }, note: "spendable")
        }
        .frame(maxWidth: .infinity)
    }

    private func side(image: String, title: String, balance: String?, note: String) -> some View {
        VStack(spacing: 6) {
            Image(image).resizable().scaledToFit().frame(width: 56, height: 56)
            Text(title).font(.headline)
            Text(balance ?? "—").font(.callout.monospacedDigit())
            Text(note).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(.quaternary.opacity(0.5)))
    }

    private var form: some View {
        Form {
            LabeledContent("Amount") {
                HStack(spacing: 4) {
                    TextField("", text: $amountText, prompt: Text("0"))
                        .multilineTextAlignment(.trailing).frame(width: 140)
                    Text("tz").foregroundStyle(.secondary)
                }
            }
            LabeledContent("To") {
                HStack(spacing: 6) {
                    TextField("", text: $recipient, prompt: Text("tz1… or KT1…"))
                        .font(.callout.monospaced()).frame(width: 330)
                    if let wallet, recipient != wallet.address.value {
                        Button("This account") { recipient = wallet.address.value }.controlSize(.small)
                    }
                }
            }
            if let estimate {
                LabeledContent("Rollup and producer fees", value: AssetBalance.format(estimate.fees, symbol: "tz"))
                LabeledContent("Spent from notes") {
                    Text("\(AssetBalance.format(Decimal(estimate.inputMutez) / Mutez.perTez, symbol: "tz")) in \(estimate.inputs.count) note\(estimate.inputs.count == 1 ? "" : "s"), \(AssetBalance.format(estimate.change, symbol: "tz")) back as change")
                }
                LabeledContent("Received on Tezos", value: AssetBalance.format(estimate.amount, symbol: "tz"))
            } else if amount != nil, !trimmedRecipient.isEmpty {
                LabeledContent("Rollup and producer fees") {
                    if let estimateError { Text(estimateError).font(.callout).foregroundStyle(.orange).multilineTextAlignment(.trailing) }
                    else { ProgressView().controlSize(.small) }
                }
            }
            Text("The notes are spent on the rollup within minutes; the tez reach the Tezos account only when the rollup's outbox message is executed, which is possible about 14 days later. The withdrawal stays listed here until then, with an Execute button when its time comes. The change comes back as a new note of yours.")
                .font(.callout).foregroundStyle(.secondary)
            if !model.canShield {
                Text("Unshielding needs Shielded Transactions on for this network and an account Signet can sign for.").font(.callout).foregroundStyle(.orange)
            } else if !tokenIsSet {
                Label("Unshielding needs the TzEL operator's access token. Enter it in Networks under Shielded Transactions.", systemImage: "key").font(.callout).foregroundStyle(.orange)
            }
        }
        .formStyle(.grouped)
        .scrollDisabled(true)
    }

    /// Every unshield of this account that is not done on Tezos yet.
    @ViewBuilder
    private var withdrawals: some View {
        let list = model.shieldedWithdrawals
        if !list.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Withdrawals").font(.headline)
                ForEach(list) { status in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(AssetBalance.format(Decimal(status.withdrawal.amount) / Mutez.perTez, symbol: "tz")).font(.callout.monospacedDigit())
                            Text("to \(Address(status.withdrawal.recipient).shortened())").font(.callout).foregroundStyle(.secondary)
                            Spacer()
                            trailing(for: status)
                        }
                        Text(status.text).font(.caption).foregroundStyle(.secondary)
                        if case .executed(let hash) = status.state, let url = network.explorerURL(operation: hash) {
                            Link("View in explorer", destination: url).font(.caption)
                        }
                        if execution?.withdrawal.id == status.id, let execution, executing == nil {
                            HStack(spacing: 8) {
                                Text("Tezos fee \(AssetBalance.format(execution.estimate.fee, symbol: "tz"))").font(.caption)
                                if needsPassphrase, let wallet { SecureField("Password for “\(wallet.alias)”", text: $executionPassphrase).frame(width: 200) }
                                Button("Confirm") { Task { await execute(execution) } }
                                    .controlSize(.small).buttonStyle(.borderedProminent)
                                    .disabled(needsPassphrase && executionPassphrase.isEmpty)
                                Button("Cancel") { self.execution = nil }.controlSize(.small)
                            }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func trailing(for status: ShieldedWithdrawalStatus) -> some View {
        if executing == status.id {
            ProgressView().controlSize(.small)
            Text(model.shieldProgress?.text ?? "Executing…").font(.caption).foregroundStyle(.secondary)
            if signsOnLedger, model.shieldProgress == .executing { LedgerPromptLabel(text: "Confirm on your Ledger…") }
        } else {
            switch status.state {
            case .ready:
                if execution?.withdrawal.id != status.id {
                    Button("Execute…") { Task { await prepareExecution(status.id) } }
                        .controlSize(.small).disabled(executing != nil || !model.canShield)
                }
            case .submitted where status.withdrawal.created < Date().addingTimeInterval(-1800):
                Button("Forget") { forget(status.id) }.controlSize(.small)
                    .help("Drops the record and frees its notes. Only for an unshield the operator never delivered; if it lands after all, the notes show as spent on the next refresh.")
            default:
                EmptyView()
            }
        }
    }

    private func doneView(_ receipt: UnshieldReceipt) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Unshielding \(AssetBalance.format(receipt.amount, symbol: "tz")) to \(Address(receipt.withdrawal.recipient).shortened())", systemImage: "checkmark.seal.fill").foregroundStyle(.green)
            Text("The operator has the unshield (submission \(receipt.withdrawal.submissionID)). The rollup spends the notes once it applies it; \(AssetBalance.format(Decimal(receipt.changeMutez) / Mutez.perTez, symbol: "tz")) comes back as change. The tez reach Tezos when the outbox message is executed, about 14 days from now: open Unshield tez again then and press Execute.")
                .font(.callout).foregroundStyle(.secondary)
            if let hash = receipt.withdrawal.operationHash {
                HStack(spacing: 8) {
                    Text("Delivered in").font(.callout).foregroundStyle(.secondary)
                    Text(hash).font(.callout.monospaced()).textSelection(.enabled).lineLimit(1).truncationMode(.middle)
                    if let url = network.explorerURL(operation: hash) { Link("View in explorer", destination: url) }
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
                Button("Unshield") { Task { await unshield() } }
                    .keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent).disabled(!canConfirm)
            case .working:
                Button("Cancel", role: .cancel) { dismiss() }.disabled(true)
            case .done:
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent)
            }
        }
    }

    // MARK: Actions

    private struct EstimateKey: Hashable {
        let amount: String
        let recipient: String
        let context: WalletViewModel.BridgeContext?
        let step: Step
    }

    private func refreshEstimate() async {
        estimate = nil
        estimateError = nil
        guard step == .compose, let amount, !trimmedRecipient.isEmpty, model.canShield else { return }
        try? await Task.sleep(for: .milliseconds(300))
        guard !Task.isCancelled else { return }
        do {
            let result = try await model.estimateUnshield(amount: amount, recipient: trimmedRecipient)
            if !Task.isCancelled { estimate = result }
        } catch {
            if !Task.isCancelled { estimateError = error.localizedDescription }
        }
    }

    private func unshield() async {
        guard let estimate, canConfirm else { return }
        errorMessage = nil
        submitted = estimate
        step = .working
        do {
            let receipt = try await model.unshieldTez(approved: estimate)
            step = .done(receipt)
        } catch {
            errorMessage = error.localizedDescription
            submitted = nil
            step = .compose
        }
    }

    private func prepareExecution(_ id: String) async {
        errorMessage = nil
        executing = id
        defer { executing = nil }
        do {
            execution = try await model.estimateWithdrawalExecution(id)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func execute(_ approved: WithdrawalExecutionEstimate) async {
        errorMessage = nil
        executing = approved.withdrawal.id
        defer { executing = nil; executionPassphrase = "" }
        do {
            executedHash = try await model.executeWithdrawal(approved: approved, passphrase: needsPassphrase ? executionPassphrase : nil)
            execution = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func forget(_ id: String) {
        errorMessage = nil
        do { try model.forgetWithdrawal(id) } catch { errorMessage = error.localizedDescription }
    }
}
