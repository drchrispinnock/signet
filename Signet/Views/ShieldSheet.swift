import SwiftUI

/// Shield tez: moves tez from the selected account on Tezos into the account's shielded wallet
/// on the TzEL rollup. Two steps run back to back: a layer 1 deposit to the bridge ticketer
/// (an ordinary approved, signed transaction into a deposit pool only this wallet can claim),
/// then the shield itself (a note to ourselves, proved by the proving service and relayed by
/// the operator, which takes a minute or two). A deposit whose shield did not finish stays
/// listed as a pool to shield again.
struct ShieldSheet: View {
    @Bindable var model: WalletViewModel
    @Environment(\.dismiss) private var dismiss

    enum Step: Hashable { case compose, working, done(ShieldReceipt) }

    @State private var amountText = ""
    @State private var pool: DepositPool?
    @State private var prepareError: String?
    @State private var estimate: ShieldEstimate?
    @State private var estimateError: String?
    @State private var passphrase = ""
    @State private var errorMessage: String?
    @State private var step: Step = .compose
    @State private var submitted: ShieldEstimate?
    @State private var shieldingPool: String?

    private var wallet: Wallet? { submitted?.context.wallet ?? model.selectedWallet }
    private var network: Network { submitted?.context.network ?? model.network }
    private var needsPassphrase: Bool { wallet?.keyKind == .encrypted }
    private var signsOnLedger: Bool { wallet?.keyKind == .ledger }
    private var spendable: Decimal? { model.tezBalance?.spendable }
    private var shielded: AssetBalance? { model.assets.first { $0.kind == .shielded } }
    private var tokenIsSet: Bool { model.shieldedOperatorTokenIsSet(for: model.network) }
    private var amount: Decimal? {
        if let submitted { return submitted.amount }
        let text = amountText.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        guard let value = Decimal(string: text, locale: Locale(identifier: "en_US_POSIX")), value > 0, value.isFinite else { return nil }
        return value
    }
    private var exceedsBalance: Bool {
        guard let amount, let spendable else { return false }
        return amount + (estimate?.estimate.fee ?? 0) > spendable
    }
    /// The deposit must cover the rollup's and the producer's fees with something left over.
    private var tooSmall: Bool {
        guard let estimate else { return false }
        return estimate.shieldedAmount <= 0
    }
    private var canConfirm: Bool {
        amount != nil && estimate?.amount == amount && estimate?.context == model.bridgeContext && pool != nil
            && !exceedsBalance && !tooSmall && model.canShield && tokenIsSet
            && !(needsPassphrase && passphrase.isEmpty) && step == .compose && shieldingPool == nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            switch step {
            case .compose:
                sides
                form
                pending
            case .working:
                sides
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(model.shieldProgress?.text ?? "Shielding \(AssetBalance.format(amount ?? 0, symbol: "tz"))…").font(.callout).foregroundStyle(.secondary)
                }
                if signsOnLedger, model.shieldProgress == .depositing { LedgerPromptLabel(text: "Confirm the deposit on your Ledger…") }
            case .done(let receipt):
                doneView(receipt)
            }
            if let errorMessage { Text(errorMessage).font(.callout).foregroundStyle(.red) }
            buttons
        }
        .padding(20)
        .frame(width: 560)
        .task(id: PrepareKey(context: model.bridgeContext, step: step)) { await prepare() }
        .task(id: EstimateKey(amount: amountText, pool: pool?.pubkeyHash, context: model.bridgeContext, step: step)) { await refreshEstimate() }
    }

    // MARK: Pieces

    private var header: some View {
        HStack(spacing: 12) {
            if let wallet { AccountAvatarView(address: wallet.address, size: 40) }
            VStack(alignment: .leading, spacing: 2) {
                Text("Shield tez").font(.title2.weight(.semibold))
                if let wallet { Text("\(wallet.alias)  \(wallet.address.shortened())").font(.callout).foregroundStyle(.secondary) }
            }
        }
    }

    private var sides: some View {
        HStack(spacing: 12) {
            side(image: "TezosToken", title: "Tezos", balance: spendable.map { AssetBalance.format($0, symbol: "tz") }, note: "spendable")
            Image(systemName: "arrow.right.circle.fill").font(.system(size: 32)).foregroundStyle(.tint)
                .accessibilityLabel("Direction: Tezos to Shielded")
            side(image: "ShieldLogo", title: "Shielded", balance: shielded.map { $0.unavailable == nil ? $0.formattedAmount : "—" }, note: "on the TzEL rollup")
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
            if exceedsBalance {
                Text("More than the spendable balance, fee included.").font(.caption).foregroundStyle(.orange)
            }
            if let estimate {
                LabeledContent("Tezos fee", value: AssetBalance.format(estimate.estimate.fee, symbol: "tz"))
                LabeledContent("Rollup and producer fees", value: AssetBalance.format(Decimal(estimate.rollupFeeMutez + estimate.producerFeeMutez) / Mutez.perTez, symbol: "tz"))
                LabeledContent("Shielded", value: AssetBalance.format(estimate.shieldedAmount, symbol: "tz"))
                if tooSmall { Text("The deposit must be more than the rollup's and the producer's fees.").font(.caption).foregroundStyle(.orange) }
            } else if amount != nil, pool != nil {
                LabeledContent("Tezos fee") {
                    if let estimateError { Text(estimateError).font(.callout).foregroundStyle(.orange).multilineTextAlignment(.trailing) }
                    else { ProgressView().controlSize(.small) }
                }
            }
            if let prepareError {
                Text(prepareError).font(.callout).foregroundStyle(.orange)
            } else if pool == nil, model.canShield {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text(model.shieldProgress?.text ?? "Preparing…").font(.callout).foregroundStyle(.secondary)
                }
            }
            Text("The tez leave this account on Tezos into a deposit pool on the TzEL rollup that only this wallet can claim, and are then shielded into a note of yours. The rollup's fee is set at shield time; the shielded amount can differ slightly if it changes.")
                .font(.callout).foregroundStyle(.secondary)
            if needsPassphrase, let wallet { SecureField("Password for “\(wallet.alias)”", text: $passphrase) }
            if !model.canShield {
                Text("Shielding needs Shielded Transactions on for this network and an account Signet can sign for.").font(.callout).foregroundStyle(.orange)
            } else if !tokenIsSet {
                Label("Shielding needs the TzEL operator's access token. Enter it in Networks under Shielded Transactions.", systemImage: "key").font(.callout).foregroundStyle(.orange)
            }
        }
        .formStyle(.grouped)
        .scrollDisabled(true)
    }

    /// Deposits already on the rollup whose shield has not happened yet.
    @ViewBuilder
    private var pending: some View {
        let pools = model.shieldedPools.filter { $0.pool.operationHash != nil && $0.pool.shieldedCm == nil }
        if !pools.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("Deposits waiting to be shielded").font(.headline)
                ForEach(pools) { status in
                    HStack {
                        Text(status.balance.map { AssetBalance.format($0, symbol: "tz") } ?? "not credited yet").font(.callout.monospacedDigit())
                        Text(status.pool.pubkeyHash.prefix(12) + "…").font(.caption.monospaced()).foregroundStyle(.secondary)
                        Spacer()
                        if shieldingPool == status.id {
                            ProgressView().controlSize(.small)
                            Text(model.shieldProgress?.text ?? "Shielding…").font(.caption).foregroundStyle(.secondary)
                        } else {
                            Button("Shield") { Task { await shield(pool: status.id) } }
                                .disabled(shieldingPool != nil || !tokenIsSet || (status.balanceMutez ?? 0) == 0)
                        }
                    }
                }
            }
        }
    }

    private func doneView(_ receipt: ShieldReceipt) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Shielded \(AssetBalance.format(receipt.shielded, symbol: "tz"))", systemImage: "checkmark.seal.fill").foregroundStyle(.green)
            Text("The operator has delivered the shield to the rollup (fees: \(AssetBalance.format(Decimal(receipt.rollupFeeMutez) / Mutez.perTez, symbol: "tz")) rollup, \(AssetBalance.format(Decimal(receipt.producerFeeMutez) / Mutez.perTez, symbol: "tz")) producer). The Shielded balance shows the note once the rollup has applied it, on the next refresh.")
                .font(.callout).foregroundStyle(.secondary)
            if let hash = receipt.depositHash {
                HStack(spacing: 8) {
                    Text("Deposit").font(.callout).foregroundStyle(.secondary)
                    Text(hash).font(.callout.monospaced()).textSelection(.enabled).lineLimit(1).truncationMode(.middle)
                    if let url = network.explorerURL(operation: hash) { Link("View in explorer", destination: url) }
                }
            }
            if let hash = receipt.operationHash {
                HStack(spacing: 8) {
                    Text("Shield").font(.callout).foregroundStyle(.secondary)
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
                Button("Shield") { Task { await shield() } }
                    .keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent).disabled(!canConfirm)
            case .working:
                Button("Cancel", role: .cancel) { dismiss() }.disabled(true)
            case .done:
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent)
            }
        }
    }

    // MARK: Actions

    private struct PrepareKey: Hashable {
        let context: WalletViewModel.BridgeContext?
        let step: Step
    }

    private struct EstimateKey: Hashable {
        let amount: String
        let pool: String?
        let context: WalletViewModel.BridgeContext?
        let step: Step
    }

    /// Checks the rollup and reserves the pool the deposit will go to, once per context.
    private func prepare() async {
        pool = nil
        prepareError = nil
        guard step == .compose, model.canShield else { return }
        do {
            let reserved = try await model.prepareShield()
            if !Task.isCancelled { pool = reserved }
        } catch {
            if !Task.isCancelled { prepareError = error.localizedDescription }
        }
    }

    private func refreshEstimate() async {
        estimate = nil
        estimateError = nil
        guard step == .compose, let amount, let pool, model.canShield else { return }
        try? await Task.sleep(for: .milliseconds(300))
        guard !Task.isCancelled else { return }
        do {
            let result = try await model.estimateShield(amount: amount, pool: pool)
            if !Task.isCancelled { estimate = result }
        } catch {
            if !Task.isCancelled { estimateError = error.localizedDescription }
        }
    }

    private func shield() async {
        guard let estimate, canConfirm else { return }
        errorMessage = nil
        submitted = estimate
        step = .working
        do {
            let receipt = try await model.shieldTez(approved: estimate, passphrase: needsPassphrase ? passphrase : nil)
            step = .done(receipt)
        } catch {
            errorMessage = error.localizedDescription
            submitted = nil
            step = .compose
        }
        passphrase = ""
    }

    /// Shields a deposit that is already on the rollup.
    private func shield(pool pubkeyHash: String) async {
        errorMessage = nil
        shieldingPool = pubkeyHash
        defer { shieldingPool = nil }
        do {
            let receipt = try await model.shieldPool(pubkeyHash)
            step = .done(receipt)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
