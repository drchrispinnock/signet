import SwiftUI

/// Moves tez between Tezos layer 1 and the selected account on Etherlink (0.9.1): Tezos on the
/// left, Etherlink on the right, the arrow between them sets the direction. Only layer 1 →
/// Etherlink can be carried out today: Etherlink does not yet offer withdrawals from
/// Michelson-interface (tz) accounts, so that direction, with its Fast / Slow choice, is shown
/// but cannot be confirmed.
struct BridgeSheet: View {
    @Bindable var model: WalletViewModel
    @Environment(\.dismiss) private var dismiss

    enum Direction: Equatable { case toEtherlink, toTezos }
    enum Speed: String, CaseIterable, Identifiable {
        case fast = "Fast", slow = "Slow"
        var id: String { rawValue }
    }
    enum Step: Equatable { case compose, working, done(hash: String, level: Int) }

    @State private var direction: Direction = .toEtherlink
    @State private var speed: Speed = .fast
    @State private var amountText = ""
    @State private var estimate: TransferEstimate?
    @State private var estimateError: String?
    @State private var passphrase = ""
    @State private var errorMessage: String?
    @State private var step: Step = .compose

    private var wallet: Wallet? { model.selectedWallet }
    private var network: Network { model.network }
    private var needsPassphrase: Bool { wallet?.keyKind == .encrypted }
    private var signsOnLedger: Bool { wallet?.keyKind == .ledger }
    private var spendable: Decimal? { model.tezBalance?.spendable }
    private var etherlink: AssetBalance? { model.assets.first { $0.kind == .etherlink } }
    private var amount: Decimal? {
        let text = amountText.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        guard let value = Decimal(string: text, locale: Locale(identifier: "en_US_POSIX")), value > 0, value.isFinite else { return nil }
        return value
    }
    private var exceedsBalance: Bool {
        guard let amount, let spendable else { return false }
        return amount + (estimate?.fee ?? 0) > spendable
    }
    private var canConfirm: Bool {
        direction == .toEtherlink && amount != nil && estimate != nil && !exceedsBalance && model.canBridge
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
                    Text("Bridging \(AssetBalance.format(amount ?? 0, symbol: "tz")) to Etherlink…").font(.callout).foregroundStyle(.secondary)
                }
                if signsOnLedger { LedgerPromptLabel(text: "Confirm the deposit on your Ledger…") }
            case .done(let hash, let level):
                doneView(hash: hash, level: level)
            }
            if let errorMessage { Text(errorMessage).font(.callout).foregroundStyle(.red) }
            buttons
        }
        .padding(20)
        .frame(width: 560)
        .task(id: "\(direction)-\(amountText)") { await refreshEstimate() }
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
            side(image: "EtherlinkLogo", title: "Etherlink", balance: etherlink.map { $0.unavailable == nil ? $0.formattedAmount : "—" }, note: "on the rollup")
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
                if let estimate {
                    LabeledContent("Fee", value: AssetBalance.format(estimate.fee, symbol: "tz"))
                    LabeledContent("Total", value: AssetBalance.format(estimate.total, symbol: "tz"))
                } else if amount != nil {
                    LabeledContent("Fee") {
                        if let estimateError { Text(estimateError).font(.callout).foregroundStyle(.orange).multilineTextAlignment(.trailing) }
                        else { ProgressView().controlSize(.small) }
                    }
                }
                Text("The tez leave this account on Tezos through Etherlink's bridge and arrive on Etherlink under the same address within about a minute.")
                    .font(.callout).foregroundStyle(.secondary)
            case .toTezos:
                Picker("Speed", selection: $speed) {
                    ForEach(Speed.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                Text(speed == .fast
                     ? "Fast: a liquidity provider pays out on Tezos within about a minute for a small fee."
                     : "Slow: the tez arrive on Tezos after the rollup's 15-day withdrawal period, with no fee.")
                    .font(.callout).foregroundStyle(.secondary)
                Label("Etherlink does not yet offer withdrawals from accounts on its Michelson interface (tz addresses). This direction will work once it does.", systemImage: "clock.badge.exclamationmark")
                    .font(.callout).foregroundStyle(.orange)
            }
            if direction == .toEtherlink, needsPassphrase, let wallet { SecureField("Password for “\(wallet.alias)”", text: $passphrase) }
            if !model.canBridge {
                Text("Bridging needs Layer 2 on for this network and a tz1, tz2 or tz3 account Signet can sign for.").font(.callout).foregroundStyle(.orange)
            }
        }
        .formStyle(.grouped)
        .scrollDisabled(true)
    }

    private func doneView(hash: String, level: Int) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Sent \(AssetBalance.format(amount ?? 0, symbol: "tz")) to the bridge", systemImage: "checkmark.seal.fill").foregroundStyle(.green)
            Text("Included in block \(level.formatted()). Etherlink credits \(wallet?.alias ?? "the account") within about a minute; the Etherlink balance updates on the next refresh.")
                .font(.callout).foregroundStyle(.secondary)
            HStack(spacing: 8) {
                Text(hash).font(.callout.monospaced()).textSelection(.enabled).lineLimit(1).truncationMode(.middle)
                if let url = network.explorerURL(operation: hash) { Link("View in explorer", destination: url) }
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

    private func refreshEstimate() async {
        estimate = nil
        estimateError = nil
        guard direction == .toEtherlink, let amount, model.canBridge else { return }
        try? await Task.sleep(for: .milliseconds(300))
        guard !Task.isCancelled else { return }
        do {
            let result = try await model.estimateBridgeDeposit(amount: amount)
            if !Task.isCancelled { estimate = result }
        } catch {
            if !Task.isCancelled { estimateError = error.localizedDescription }
        }
    }

    private func bridge() async {
        guard let amount, direction == .toEtherlink else { return }
        errorMessage = nil
        step = .working
        do {
            let (hash, level) = try await model.bridgeToEtherlink(amount: amount, limits: estimate?.limits, passphrase: needsPassphrase ? passphrase : nil)
            step = .done(hash: hash, level: level)
        } catch {
            errorMessage = error.localizedDescription
            step = .compose
        }
    }
}

#Preview {
    BridgeSheet(model: .preview())
}
