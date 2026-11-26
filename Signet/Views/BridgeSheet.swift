import SwiftUI

/// Moves tez between Tezos layer 1 and the selected account on Etherlink (0.9.1): Tezos on the
/// left, Etherlink on the right, the arrow between them sets the direction. Etherlink → Tezos
/// (slow) pays out to the same account on Tezos after the rollup's challenge window. Fast
/// withdrawals are shown but not offered yet.
struct BridgeSheet: View {
    @Bindable var model: WalletViewModel
    @Environment(\.dismiss) private var dismiss

    enum Direction: Hashable { case toEtherlink, toTezos }
    enum Speed: String, CaseIterable, Identifiable {
        case fast = "Fast", slow = "Slow"
        var id: String { rawValue }
    }
    enum Step: Hashable { case compose, working, done(hash: String, level: Int) }

    @State private var direction: Direction = .toEtherlink
    @State private var speed: Speed = .slow
    @State private var amountText = ""
    /// The estimate and the context it was made in (S31); refreshed whenever that context moves.
    @State private var estimate: WalletViewModel.BridgeEstimate?
    @State private var estimateError: String?
    @State private var passphrase = ""
    @State private var errorMessage: String?
    @State private var step: Step = .compose
    @State private var submitted: WalletViewModel.BridgeEstimate?

    private var wallet: Wallet? { submitted?.context.wallet ?? model.selectedWallet }
    private var network: Network { submitted?.context.network ?? model.network }
    private var needsPassphrase: Bool { wallet?.keyKind == .encrypted }
    private var signsOnLedger: Bool { wallet?.keyKind == .ledger }
    private var spendable: Decimal? { model.tezBalance?.spendable }
    private var etherlink: AssetBalance? { model.assets.first { $0.kind == .etherlink } }
    private var amount: Decimal? {
        if let submitted { return submitted.amount }
        let text = amountText.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        guard let value = Decimal(string: text, locale: Locale(identifier: "en_US_POSIX")), value > 0, value.isFinite else { return nil }
        return value
    }
    /// What the tez leave from: Tezos for a deposit, Etherlink for a withdrawal.
    private var sourceSpendable: Decimal? { direction == .toEtherlink ? spendable : model.etherlinkSpendable }
    private var exceedsBalance: Bool {
        guard let amount, let sourceSpendable else { return false }
        return amount + (estimate?.estimate.fee ?? 0) > sourceSpendable
    }
    private var directionAvailable: Bool {
        direction == .toEtherlink || (speed == .slow && model.canWithdrawFromEtherlink)
    }
    private var canConfirm: Bool {
        directionAvailable && amount != nil && estimate?.amount == amount && estimate?.isWithdrawal == (direction == .toTezos)
            && estimate?.context == model.bridgeContext && !exceedsBalance && model.canBridge
            && !(needsPassphrase && passphrase.isEmpty) && step == .compose
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            switch step {
            case .compose:
                sides
                form
            case .working:
                sides
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Bridging \(AssetBalance.format(amount ?? 0, symbol: "tz")) to \(direction == .toEtherlink ? network.l2Name : "Tezos")…").font(.callout).foregroundStyle(.secondary)
                }
                if signsOnLedger { LedgerPromptLabel(text: direction == .toEtherlink ? "Confirm the deposit on your Ledger…" : "Confirm the withdrawal on your Ledger…") }
            case .done(let hash, let level):
                doneView(hash: hash, level: level)
            }
            if let errorMessage { Text(errorMessage).font(.callout).foregroundStyle(.red) }
            buttons
        }
        .padding(20)
        .frame(width: 560)
        .task(id: EstimateKey(direction: direction, speed: speed, amount: amountText, context: model.bridgeContext, step: step)) { await refreshEstimate() }
    }

    // MARK: Pieces

    private var header: some View {
        HStack(spacing: 12) {
            if let wallet { AccountAvatarView(address: wallet.address, size: 40) }
            VStack(alignment: .leading, spacing: 2) {
                Text("Bridge").font(.title2.weight(.semibold))
                if let wallet { Text("\(wallet.alias)  \(wallet.address.shortened())").font(.callout).foregroundStyle(.secondary) }
            }
        }
    }

    /// Tezos on the left, Etherlink on the right; the arrow between them is the direction.
    private var sides: some View {
        HStack(spacing: 12) {
            side(image: "TezosToken", title: "Tezos", balance: spendable.map { AssetBalance.format($0, symbol: "tz") }, note: "spendable")
            Button {
                direction = direction == .toEtherlink ? .toTezos : .toEtherlink
                estimate = nil
            } label: {
                Image(systemName: direction == .toEtherlink ? "arrow.right.circle.fill" : "arrow.left.circle.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(.tint)
            }
            .buttonStyle(.borderless)
            .disabled(step != .compose)
            .help(direction == .toEtherlink ? "Tezos to Etherlink. Click to reverse." : "Etherlink to Tezos. Click to reverse.")
            .accessibilityLabel(direction == .toEtherlink ? "Direction: Tezos to Etherlink" : "Direction: Etherlink to Tezos")
            side(image: "EtherlinkLogo", title: network.l2Name, balance: etherlink.map { $0.unavailable == nil ? $0.formattedAmount : "—" }, note: "on the rollup")
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
            switch direction {
            case .toEtherlink:
                fee
                Text("The tez leave this account on Tezos through \(network.l2Name)'s bridge and arrive on \(network.l2Name) under the same address within about a minute.")
                    .font(.callout).foregroundStyle(.secondary)
            case .toTezos:
                Picker("Speed", selection: $speed) {
                    ForEach(Speed.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                switch speed {
                case .fast:
                    Text("Fast: a liquidity provider pays out on Tezos within about a minute for a small fee.")
                        .font(.callout).foregroundStyle(.secondary)
                    Label("Fast withdrawals from tz accounts are not offered yet. Choose Slow.", systemImage: "clock.badge.exclamationmark")
                        .font(.callout).foregroundStyle(.orange)
                case .slow:
                    fee
                    Text("Slow: the tez leave this account on \(network.l2Name) now and arrive on Tezos under the same address once the rollup's commitment is final, about two weeks from now.")
                        .font(.callout).foregroundStyle(.secondary)
                }
            }
            if directionAvailable, needsPassphrase, let wallet { SecureField("Password for “\(wallet.alias)”", text: $passphrase) }
            if !model.canBridge {
                Text("Bridging needs Layer 2 on for this network and a tz1, tz2 or tz3 account Signet can sign for.").font(.callout).foregroundStyle(.orange)
            }
        }
        .formStyle(.grouped)
        .scrollDisabled(true)
    }

    /// The estimate's fee and total, or why there is none yet.
    @ViewBuilder
    private var fee: some View {
        if let estimate = estimate?.estimate {
            LabeledContent("Fee", value: AssetBalance.format(estimate.fee, symbol: "tz"))
            LabeledContent("Total", value: AssetBalance.format(estimate.total, symbol: "tz"))
        } else if amount != nil {
            LabeledContent("Fee") {
                if let estimateError { Text(estimateError).font(.callout).foregroundStyle(.orange).multilineTextAlignment(.trailing) }
                else { ProgressView().controlSize(.small) }
            }
        }
    }

    private func doneView(hash: String, level: Int) -> some View {
        let withdrawal = submitted?.isWithdrawal ?? (direction == .toTezos)
        let explorerNetwork = withdrawal ? (network.layer2 ?? network) : network
        return VStack(alignment: .leading, spacing: 10) {
            Label(withdrawal ? "Withdrew \(AssetBalance.format(amount ?? 0, symbol: "tz")) from \(network.l2Name)" : "Sent \(AssetBalance.format(amount ?? 0, symbol: "tz")) to the bridge", systemImage: "checkmark.seal.fill").foregroundStyle(.green)
            Text(withdrawal
                 ? "Included in \(network.l2Name) block \(level.formatted()). The tez arrive in \(wallet?.alias ?? "the account") on Tezos once the rollup's commitment is final, about two weeks from now."
                 : "Included in block \(level.formatted()). \(network.l2Name) credits \(wallet?.alias ?? "the account") within about a minute; the \(network.l2Name) balance updates on the next refresh.")
                .font(.callout).foregroundStyle(.secondary)
            HStack(spacing: 8) {
                Text(hash).font(.callout.monospaced()).textSelection(.enabled).lineLimit(1).truncationMode(.middle)
                if let url = explorerNetwork.explorerURL(operation: hash) { Link("View in explorer", destination: url) }
            }
        }
    }

    private var buttons: some View {
        HStack {
            Spacer()
            switch step {
            case .compose:
                Button("Cancel", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Bridge") { Task { await bridge() } }
                    .keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent).disabled(!canConfirm)
            case .working:
                Button("Cancel", role: .cancel) { dismiss() }.disabled(true)
            case .done:
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent)
            }
        }
    }

    // MARK: Actions

    /// Everything the estimate depends on: a change of account, network, node, Layer 2 settings
    /// or wallet directory drops the old estimate and asks again (S31).
    private struct EstimateKey: Hashable {
        let direction: Direction
        let speed: Speed
        let amount: String
        let context: WalletViewModel.BridgeContext?
        let step: Step
    }

    private func refreshEstimate() async {
        estimate = nil
        estimateError = nil
        guard step == .compose, directionAvailable, let amount, model.canBridge else { return }
        try? await Task.sleep(for: .milliseconds(300))
        guard !Task.isCancelled else { return }
        do {
            let result = direction == .toEtherlink ? try await model.estimateBridgeDeposit(amount: amount) : try await model.estimateBridgeWithdrawal(amount: amount)
            if !Task.isCancelled { estimate = result }
        } catch {
            if !Task.isCancelled { estimateError = error.localizedDescription }
        }
    }

    private func bridge() async {
        guard let amount, let approved = estimate, directionAvailable else { return }
        errorMessage = nil
        submitted = approved
        step = .working
        do {
            let passphrase = needsPassphrase ? passphrase : nil
            let (hash, level) = approved.isWithdrawal
                ? try await model.bridgeToTezos(amount: amount, approved: approved, passphrase: passphrase)
                : try await model.bridgeToEtherlink(amount: amount, approved: approved, passphrase: passphrase)
            step = .done(hash: hash, level: level)
        } catch {
            errorMessage = error.localizedDescription
            submitted = nil
            step = .compose
        }
    }
}

#Preview {
    BridgeSheet(model: .preview())
}
