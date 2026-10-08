import SwiftUI

/// Delegation and staking for the selected wallet: delegate, change or remove the delegate;
/// stake, unstake, finalize. Each action confirms with a fee estimate (and password if needed).
struct StakingSheet: View {
    @Bindable var model: WalletViewModel
    @Environment(\.dismiss) private var dismiss

    enum Mode: Equatable { case overview, chooseDelegate, amount(StakingOperationKind), confirm(StakingOperation), working(StakingOperation), done(hash: String, level: Int, StakingOperation) }
    enum StakingOperationKind { case stake, unstake }

    @State private var mode: Mode = .overview
    @State private var bakers: [BakerCandidate] = []
    @State private var bakerFilter = ""
    @State private var amountText = ""
    @State private var estimate: TransferEstimate?
    @State private var passphrase = ""
    @State private var errorMessage: String?
    @State private var delegateName: String?
    @State private var workingOnDevice = false

    private var wallet: Wallet? { model.selectedWallet }
    private var info: DelegateInfo? { model.delegateInfo }
    private var balance: TezBalance? { model.tezBalance }
    private var needsPassphrase: Bool { wallet?.keyKind == .encrypted }
    private var canOperate: Bool { wallet?.keyKind.canSign == true }
    private var signsOnLedger: Bool { wallet?.keyKind == .ledger }
    private var watchOnlyNote: String {
        switch wallet?.keyKind {
        case .remote: "Signet cannot sign for this wallet: it uses a remote signer."
        default: "Signet holds only this address's public key, so it can show but not change its delegation."
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            content
            if let errorMessage { Text(errorMessage).font(.callout).foregroundStyle(.red) }
            buttons
        }
        .padding(20)
        .frame(width: 520)
        .task { bakers = await model.bakers() }
        .task(id: model.delegateInfo?.delegate) {
            delegateName = nil
            guard let delegate = model.delegateInfo?.delegate else { return }
            let known = model.displayName(for: delegate, indexerAlias: bakers.first { $0.address == delegate }?.alias)
            delegateName = known.isOurs || known.name != delegate.shortened() ? known.name : (await model.profileName(for: delegate) ?? delegate.shortened())
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 12) {
            if let wallet { AccountAvatarView(address: wallet.address, size: 40) }
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.title2.weight(.semibold))
                if let wallet { Text("\(wallet.alias)  \(wallet.address.shortened())").font(.callout).foregroundStyle(.secondary) }
            }
        }
    }

    private var title: String {
        switch mode {
        case .overview: "Staking"
        case .chooseDelegate: "Choose a baker"
        case .amount(.stake): "Stake tez"
        case .amount(.unstake): "Unstake tez"
        case .confirm(let op), .working(let op): op.title
        case .done(_, _, let op): "\(op.title): done"
        }
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        switch mode {
        case .overview: overview
        case .chooseDelegate: bakerPicker
        case .amount(let kind): amountForm(kind)
        case .confirm(let op): confirmation(op)
        case .working(let op): workingRow(op)
        case .done(let hash, let level, _): doneView(hash: hash, level: level)
        }
    }

    private var overview: some View {
        Form {
            if !canOperate {
                Section { Label(watchOnlyNote, systemImage: "eye").foregroundStyle(.secondary) }
            }
            Section("Delegation") {
                if let info {
                    if info.isBaker {
                        Label(canOperate ? "This wallet is a baker (self-delegated). Manage it under Baking in the menu." : "This address is a baker (self-delegated).", systemImage: "server.rack")
                    } else if let delegate = info.delegate {
                        LabeledContent("Delegate") {
                            HStack(spacing: 8) {
                                AccountAvatarView(address: delegate, size: 22)
                                Text(delegateName ?? delegate.shortened())
                                Text(delegate.shortened()).font(.callout.monospaced()).foregroundStyle(.secondary)
                            }
                        }
                        LabeledContent("Accepts staking", value: info.delegateAcceptsStaking.map { $0 ? "Yes" : "No" } ?? "Unknown")
                        HStack {
                            Button("Change delegate…") { mode = .chooseDelegate }
                            Button("Remove delegation", role: .destructive) { startConfirm(.delegate(to: nil)) }
                        }
                        .disabled(!canOperate)
                    } else {
                        Text("Not delegated. Delegating lets a baker earn rewards with your balance; the tez never leave your wallet.")
                            .foregroundStyle(.secondary)
                        Button("Delegate…") { mode = .chooseDelegate }.disabled(!canOperate)
                    }
                } else {
                    ProgressView().controlSize(.small)
                }
            }
            Section("Staking") {
                if let balance {
                    LabeledContent("Spendable", value: AssetBalance.format(balance.spendable, symbol: "tz"))
                    LabeledContent("Staked", value: AssetBalance.format(balance.staked, symbol: "tz"))
                    if balance.unstakedFrozen > 0 { LabeledContent("Unstaking", value: AssetBalance.format(balance.unstakedFrozen, symbol: "tz")) }
                    if balance.unstakedFinalizable > 0 { LabeledContent("Ready to finalize", value: AssetBalance.format(balance.unstakedFinalizable, symbol: "tz")) }
                }
                let canStake = info?.delegate != nil && info?.delegateAcceptsStaking != false
                HStack {
                    Button("Stake…") { amountText = ""; mode = .amount(.stake) }.disabled(!canStake || (balance?.spendable ?? 0) <= 0)
                    Button("Unstake…") { amountText = ""; mode = .amount(.unstake) }.disabled((balance?.staked ?? 0) <= 0)
                    Button("Finalize") { startConfirm(.finalizeUnstake) }.disabled((balance?.unstakedFinalizable ?? 0) <= 0)
                }
                .disabled(!canOperate)
                Text(canStake
                     ? "Staked tez earn more than delegated tez but are frozen and can be slashed if your baker misbehaves. Unstaking takes a few cycles, then needs finalizing."
                     : "Staking needs a delegate that accepts stakers.")
                    .font(.callout).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(height: canOperate ? 380 : 430)
    }

    private var bakerPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("Search bakers or paste an address", text: $bakerFilter)
                .textFieldStyle(.roundedBorder)
                .font(.callout)
            if Address(bakerFilter.trimmingCharacters(in: .whitespaces)).isValidAccount {
                let address = Address(bakerFilter.trimmingCharacters(in: .whitespaces))
                Button { startConfirm(.delegate(to: address)) } label: {
                    HStack(spacing: 8) { AccountAvatarView(address: address, size: 24); Text("Use \(address.shortened())") }
                }
            }
            List(filteredBakers) { baker in
                Button { startConfirm(.delegate(to: baker.address)) } label: {
                    HStack(spacing: 10) {
                        AccountAvatarView(address: baker.address, size: 28)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(baker.alias ?? baker.address.shortened()).font(.body)
                            Text("\(baker.delegators) delegators · \(baker.stakers) stakers · \(baker.acceptsStaking == true ? "accepts staking" : baker.acceptsStaking == false ? "no staking" : "")")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(AssetBalance.format(baker.stakingBalance, symbol: "tz")).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .frame(height: 300)
            if bakers.isEmpty { Text("No baker list for this network; paste an address above.").font(.callout).foregroundStyle(.secondary) }
        }
    }

    private var filteredBakers: [BakerCandidate] {
        let needle = bakerFilter.trimmingCharacters(in: .whitespaces).lowercased()
        guard !needle.isEmpty else { return bakers }
        return bakers.filter { ($0.alias?.lowercased().contains(needle) ?? false) || $0.address.value.lowercased().hasPrefix(needle) }
    }

    private func amountForm(_ kind: StakingOperationKind) -> some View {
        Form {
            HStack {
                TextField("Amount", text: $amountText, prompt: Text("0.0")).font(.body.monospacedDigit())
                Text("tz").foregroundStyle(.secondary)
                Button("Max") {
                    let max = kind == .stake ? max(0, (balance?.spendable ?? 0) - Decimal(string: "0.01")!) : (balance?.staked ?? 0)
                    amountText = NSDecimalNumber(decimal: max).stringValue
                }
            }
            LabeledContent(kind == .stake ? "Spendable" : "Staked", value: AssetBalance.format(kind == .stake ? (balance?.spendable ?? 0) : (balance?.staked ?? 0), symbol: "tz"))
            Text(kind == .stake ? "Staked tez stay in your wallet but are frozen and shared in your baker's risk." : "Unstaked tez become spendable after a few cycles; come back to finalize them.")
                .font(.callout).foregroundStyle(.secondary)
        }
        .formStyle(.grouped).scrollDisabled(true)
    }

    @ViewBuilder
    private func workingRow(_ op: StakingOperation) -> some View {
        if signsOnLedger, estimate != nil, workingOnDevice {
            LedgerPromptLabel(text: "\(op.title): confirm on your Ledger…")
        } else {
            HStack(spacing: 8) { ProgressView().controlSize(.small); Text("\(op.title)… waiting for the next block").foregroundStyle(.secondary) }
        }
    }

    private func confirmation(_ op: StakingOperation) -> some View {
        Form {
            LabeledContent("Operation", value: op.title)
            if case .delegate(let to) = op, let to {
                LabeledContent("Baker") { HStack(spacing: 8) { AccountAvatarView(address: to, size: 22); Text(bakers.first { $0.address == to }?.alias ?? model.displayName(for: to, indexerAlias: nil).name); Text(to.shortened()).font(.callout.monospaced()).foregroundStyle(.secondary) } }
            }
            if case .stake(let a) = op { LabeledContent("Amount", value: AssetBalance.format(a, symbol: "tz")) }
            if case .unstake(let a) = op { LabeledContent("Amount", value: AssetBalance.format(a, symbol: "tz")) }
            if let estimate { LabeledContent("Fee", value: AssetBalance.format(estimate.fee, symbol: "tz")) } else { LabeledContent("Fee") { ProgressView().controlSize(.small) } }
            if needsPassphrase, let wallet { SecureField("Password for “\(wallet.alias)”", text: $passphrase) }
            if signsOnLedger { Text("Your Ledger will show this operation for approval.").font(.callout).foregroundStyle(.secondary) }
        }
        .formStyle(.grouped).scrollDisabled(true)
    }

    private func doneView(hash: String, level: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Included in block \(level.formatted())", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
            HStack(spacing: 8) {
                Text(hash).font(.callout.monospaced()).textSelection(.enabled).lineLimit(1).truncationMode(.middle)
                if let url = model.network.explorerURL(operation: hash) { Link("View in explorer", destination: url).font(.callout) }
            }
        }
    }

    // MARK: Buttons

    private var buttons: some View {
        HStack {
            Spacer()
            switch mode {
            case .overview:
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            case .chooseDelegate:
                Button("Back") { mode = .overview }.keyboardShortcut(.cancelAction)
            case .amount(let kind):
                Button("Back") { mode = .overview }.keyboardShortcut(.cancelAction)
                Button("Continue") {
                    if let amount = parsedAmount { startConfirm(kind == .stake ? .stake(amount) : .unstake(amount)) }
                }
                .keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent).disabled(parsedAmount == nil)
            case .confirm(let op):
                Button("Back") { mode = .overview; errorMessage = nil }.keyboardShortcut(.cancelAction)
                Button("Confirm") { Task { await perform(op) } }
                    .keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent)
                    .disabled(estimate == nil || (needsPassphrase && passphrase.isEmpty))
            case .working:
                EmptyView()
            case .done:
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent)
            }
        }
    }

    private var parsedAmount: Decimal? {
        guard let value = Decimal(string: amountText.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: "."), locale: Locale(identifier: "en_US_POSIX")), value > 0 else { return nil }
        if case .amount(.stake) = mode, value > (balance?.spendable ?? 0) { return nil }
        if case .amount(.unstake) = mode, value > (balance?.staked ?? 0) { return nil }
        return value
    }

    private func startConfirm(_ op: StakingOperation) {
        errorMessage = nil
        estimate = nil
        mode = .confirm(op)
        Task {
            do { estimate = try await model.estimateStaking(op) } catch { errorMessage = error.localizedDescription }
        }
    }

    private func perform(_ op: StakingOperation) async {
        errorMessage = nil
        mode = .working(op)
        workingOnDevice = true
        defer { workingOnDevice = false }
        do {
            let result = try await model.performStaking(op, passphrase: needsPassphrase ? passphrase : nil)
            mode = .done(hash: result.hash, level: result.level, op)
        } catch {
            errorMessage = error.localizedDescription
            mode = .confirm(op)
        }
    }
}
