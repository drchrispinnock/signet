import SwiftUI

/// The Etherlink tab of Governance: the current period of the slow or fast kernel-upgrade
/// process, the proposals to upvote (or a new kernel hash to propose) in a Proposal period,
/// and Yea / Nay / Pass on the candidate in a Promotion period. Every call is a layer 1
/// transaction with a fee, so the confirm step shows the estimate and sends with exactly it.
struct EtherlinkGovernanceView: View {
    @Bindable var model: WalletViewModel
    let dismiss: () -> Void

    enum Mode: Equatable {
        case overview
        case confirm(EtherlinkGovernance.Operation)
        case working(EtherlinkGovernance.Operation)
        case done(hash: String, level: Int, EtherlinkGovernance.Operation)
    }

    @State private var process: EtherlinkGovernance.Process = .slow
    @State private var mode: Mode = .overview
    @State private var state: EtherlinkGovernance.State?
    @State private var loadError: String?
    @State private var newHash = ""
    @State private var passphrase = ""
    @State private var errorMessage: String?
    @State private var estimate: WalletViewModel.EtherlinkGovernanceEstimate?
    @State private var estimateError: String?
    @State private var loadTask: Task<Void, Never>?

    private var wallet: Wallet? { model.selectedWallet }
    private var needsPassphrase: Bool { wallet?.keyKind == .encrypted }
    private var signsOnLedger: Bool { wallet?.keyKind == .ledger }
    private var processes: [EtherlinkGovernance.Process] { model.network.etherlinkGovernanceProcesses }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if case .overview = mode {
                Picker("Process", selection: $process) {
                    ForEach(processes) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
            } else {
                Text(title).font(.headline)
            }
            content
            if let errorMessage { Text(errorMessage).font(.callout).foregroundStyle(.red) }
            buttons
        }
        .onAppear { if !processes.contains(process), let first = processes.first { process = first } }
        .task(id: process) { await load() }
    }

    private var title: String {
        switch mode {
        case .overview: process.title
        case .confirm(let op), .working(let op): "\(op.title) (\(process.title.lowercased()))"
        case .done(_, _, let op): "\(op.title): done"
        }
    }

    @ViewBuilder
    private var content: some View {
        switch mode {
        case .overview: overview
        case .confirm(let op): confirmation(op)
        case .working(let op):
            if signsOnLedger { LedgerPromptLabel(text: "\(op.title): confirm on your Ledger, then we wait for the next block…") }
            else { HStack(spacing: 8) { ProgressView().controlSize(.small); Text("\(op.title)… waiting for the next block").foregroundStyle(.secondary) } }
        case .done(let hash, let level, _):
            VStack(alignment: .leading, spacing: 8) {
                Label("Included in block \(level.formatted())", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                HStack(spacing: 8) {
                    Text(hash).font(.callout.monospaced()).textSelection(.enabled).lineLimit(1).truncationMode(.middle)
                    if let url = model.network.explorerURL(operation: hash) { Link("View in explorer", destination: url).font(.callout) }
                }
            }
        }
    }

    // MARK: Overview

    @ViewBuilder
    private var overview: some View {
        if let loadError {
            Label(loadError, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
        } else if let state {
            Form {
                periodSection(state)
                if !state.canVote {
                    Section {
                        Label("This account has no voting power on Etherlink: it is neither a baker in this period's listings nor a voting key that a baker has delegated to and that has claimed its rights.", systemImage: "info.circle")
                            .foregroundStyle(.secondary)
                    }
                } else if state.periodKind == .proposal {
                    proposalSection(state)
                } else {
                    promotionSection(state)
                }
            }
            .formStyle(.grouped)
            .frame(height: 420)
        } else {
            HStack(spacing: 8) { ProgressView().controlSize(.small); Text("Reading the governance contract…").foregroundStyle(.secondary) }
        }
    }

    private func periodSection(_ state: EtherlinkGovernance.State) -> some View {
        Section("Current period") {
            LabeledContent("Period", value: "\(state.periodKind.title) (#\(state.periodIndex))")
            LabeledContent("Remaining", value: "\(state.remainingBlocks.formatted()) blocks of \(state.config.periodLength.formatted())")
            LabeledContent("Your voting power") {
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(AssetBalance.format(state.votingPower / 1_000_000, symbol: "tz")) · \(percent(state.share(of: state.votingPower)))")
                    if !state.votesFor.isEmpty {
                        Text(state.votesFor.count == 1 ? "voting key of \(model.displayName(for: state.votesFor[0], indexerAlias: nil).name)" : "voting key of \(state.votesFor.count) bakers")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            LabeledContent("Contract") {
                HStack(spacing: 6) {
                    Text(state.contract.value).font(.callout.monospaced()).lineLimit(1).truncationMode(.middle).textSelection(.enabled)
                    if let url = model.network.explorerURL(contract: state.contract.value) { Link("Explorer", destination: url).font(.callout) }
                }
            }
            Link("Proposals are described at governance.etherlink.com", destination: EtherlinkGovernance.siteURL).font(.callout)
        }
    }

    private func proposalSection(_ state: EtherlinkGovernance.State) -> some View {
        Section("Proposals") {
            if !state.proposalsKnown {
                Label("The proposals cannot be listed without a TzKT API for this network; paste a kernel hash to upvote it.", systemImage: "info.circle")
                    .font(.callout).foregroundStyle(.secondary)
            } else if state.proposals.isEmpty {
                Text("No kernels have been proposed yet in this period.").foregroundStyle(.secondary)
            }
            ForEach(state.proposals) { proposal in
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(proposal.hash).font(.callout.monospaced()).lineLimit(1).truncationMode(.middle).textSelection(.enabled)
                        Text("\(percent(state.share(of: proposal.upvotes))) of voting power, needs \(percent(state.config.fraction(state.config.proposalQuorum))) · proposed by \(proposers(proposal))")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if proposal.upvoted {
                        Label("Upvoted", systemImage: "checkmark.seal.fill").font(.callout).foregroundStyle(.green)
                    } else {
                        Button("Upvote…") { startConfirm(.upvote(hash: proposal.hash)) }
                            .disabled(state.upvotesUsed >= state.config.upvotingLimit)
                    }
                }
            }
            TextField("Propose or upvote a kernel hash", text: $newHash, prompt: Text("0x…"))
                .font(.callout.monospaced()).autocorrectionDisabled()
            if !newHash.trimmingCharacters(in: .whitespaces).isEmpty, typedHash == nil {
                Text("A kernel hash is 0x followed by 66 hexadecimal digits.").font(.callout).foregroundStyle(.orange)
            }
            Text("You have used \(state.upvotesUsed) of \(state.config.upvotingLimit) upvotes this period; proposing counts as one. Upvoting cannot be undone.")
                .font(.callout).foregroundStyle(.secondary)
            HStack {
                Button("Upvote…") { if let hash = typedHash { startConfirm(.upvote(hash: hash)) } }
                    .disabled(typedHash == nil || typedHashIsListed || state.upvotesUsed >= state.config.upvotingLimit)
                Button("Propose…") { if let hash = typedHash { startConfirm(.newProposal(hash: hash)) } }
                    .disabled(typedHash == nil || typedHashIsListed || state.upvotesUsed >= state.config.upvotingLimit)
            }
        }
    }

    private var typedHash: String? { EtherlinkGovernance.kernelHash(from: newHash) }
    /// A listed kernel has its own Upvote button and cannot be proposed again.
    private var typedHashIsListed: Bool { typedHash.map { hash in state?.proposals.contains { $0.hash == hash } ?? false } ?? false }

    private func proposers(_ proposal: EtherlinkGovernance.Proposal) -> String {
        guard let first = proposal.proposers.first else { return "unknown" }
        let name = model.displayName(for: first, indexerAlias: nil).name
        return proposal.proposers.count > 1 ? "\(name) and \(proposal.proposers.count - 1) more" : name
    }

    private func promotionSection(_ state: EtherlinkGovernance.State) -> some View {
        Section("Promotion vote") {
            if let candidate = state.candidate {
                LabeledContent("Kernel") { Text(candidate).font(.callout.monospaced()).lineLimit(1).truncationMode(.middle).textSelection(.enabled) }
            }
            LabeledContent("So far") {
                Text("Yea \(percent(share(state.tallies.yea, of: state.tallies.total))) · Nay \(percent(share(state.tallies.nay, of: state.tallies.total))) · Pass \(percent(share(state.tallies.pass, of: state.tallies.total)))")
            }
            LabeledContent("Turnout", value: "\(percent(state.share(of: state.tallies.total))) of \(percent(state.config.fraction(state.config.promotionQuorum))) quorum")
            LabeledContent("Supermajority", value: "\(percent(share(state.tallies.yea, of: state.tallies.yea + state.tallies.nay))) Yea of \(percent(state.config.fraction(state.config.promotionSupermajority))) needed")
            if let mine = state.myVote {
                Label("You voted \(mine.title) in this period. A vote cannot be changed.", systemImage: "checkmark.seal.fill").foregroundStyle(.green)
            } else if state.candidate != nil {
                HStack(spacing: 10) {
                    ForEach(EtherlinkGovernance.Vote.allCases) { vote in
                        Button(vote.title) { startConfirm(.vote(vote)) }
                    }
                }
                Text("Yea supports the kernel, Nay opposes it, Pass counts towards the quorum without taking a side.")
                    .font(.callout).foregroundStyle(.secondary)
            }
        }
    }

    private func share(_ part: Decimal, of whole: Decimal) -> Double {
        guard whole > 0 else { return 0 }
        return (part / whole as NSDecimalNumber).doubleValue
    }

    private func percent(_ fraction: Double) -> String {
        fraction.formatted(.percent.precision(.fractionLength(0...2)))
    }

    // MARK: Confirm

    private func confirmation(_ op: EtherlinkGovernance.Operation) -> some View {
        Form {
            LabeledContent("Operation", value: op.title)
            if let hash = op.kernelHash {
                LabeledContent("Kernel") { Text(hash).font(.callout.monospaced()).lineLimit(1).truncationMode(.middle) }
            }
            if case .vote(let vote) = op, let candidate = state?.candidate {
                LabeledContent("Kernel") { Text(candidate).font(.callout.monospaced()).lineLimit(1).truncationMode(.middle) }
                LabeledContent("Vote", value: vote.title)
            }
            if let contract = model.etherlinkGovernanceContract(for: process) {
                LabeledContent("Contract") { Text(contract.value).font(.callout.monospaced()).lineLimit(1).truncationMode(.middle) }
            }
            LabeledContent("Fee") {
                if let estimate {
                    Text(AssetBalance.format(estimate.estimate.fee, symbol: "tz"))
                } else if let estimateError {
                    Text(estimateError).foregroundStyle(.orange)
                } else {
                    HStack(spacing: 6) { ProgressView().controlSize(.small); Text("Estimating…").foregroundStyle(.secondary) }
                }
            }
            if needsPassphrase, let wallet { SecureField("Password for “\(wallet.alias)”", text: $passphrase) }
            if signsOnLedger { Text("Your Ledger will show this operation for approval.").font(.callout).foregroundStyle(.secondary) }
        }
        .formStyle(.grouped).scrollDisabled(true)
        .task(id: op) { await estimate(op) }
    }

    // MARK: Buttons

    private var buttons: some View {
        HStack {
            Spacer()
            switch mode {
            case .overview:
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
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

    private func load() async {
        loadError = nil
        state = nil
        do { state = try await model.etherlinkGovernanceState(for: process) } catch { loadError = "Could not read the governance contract: \(error.localizedDescription)" }
    }

    private func startConfirm(_ op: EtherlinkGovernance.Operation) {
        errorMessage = nil
        estimate = nil
        estimateError = nil
        mode = .confirm(op)
    }

    private func estimate(_ op: EtherlinkGovernance.Operation) async {
        estimate = nil
        estimateError = nil
        do { estimate = try await model.estimateEtherlinkGovernance(op, process: process) } catch { estimateError = error.localizedDescription }
    }

    private func perform(_ op: EtherlinkGovernance.Operation) async {
        errorMessage = nil
        mode = .working(op)
        do {
            let result = try await model.performEtherlinkGovernance(op, process: process, approved: estimate, passphrase: needsPassphrase ? passphrase : nil)
            mode = .done(hash: result.hash, level: result.level, op)
            newHash = ""
            await load()
        } catch {
            errorMessage = error.localizedDescription
            mode = .confirm(op)
        }
    }
}
