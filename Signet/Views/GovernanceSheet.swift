import SwiftUI

/// On-chain voting for a baker we can sign for: upvote proposals in a proposal period, cast a
/// ballot in the exploration and promotion votes, and otherwise say what the chain is doing.
struct GovernanceSheet: View {
    @Bindable var model: WalletViewModel
    @Environment(\.dismiss) private var dismiss

    enum Mode: Equatable { case overview, confirm(GovernanceOperation), working(GovernanceOperation), done(hash: String, level: Int, GovernanceOperation) }

    @State private var mode: Mode = .overview
    @State private var info: GovernanceInfo?
    @State private var loadError: String?
    @State private var selected: Set<String> = []
    @State private var newProposal = ""
    @State private var passphrase = ""
    @State private var errorMessage: String?

    private var wallet: Wallet? { model.selectedWallet }
    private var needsPassphrase: Bool { wallet?.keyKind == .encrypted }
    private var signsOnLedger: Bool { wallet?.keyKind == .ledger }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                if let wallet { AccountAvatarView(address: wallet.address, size: 40) }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.title2.weight(.semibold))
                    if let wallet { Text("\(wallet.alias)  \(wallet.address.shortened())").font(.callout).foregroundStyle(.secondary) }
                }
            }
            content
            if let errorMessage { Text(errorMessage).font(.callout).foregroundStyle(.red) }
            buttons
        }
        .padding(20)
        .frame(width: 560)
        .task { await load() }
    }

    private var title: String {
        switch mode {
        case .overview: "Governance"
        case .confirm(let op), .working(let op): op.title
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
        } else if let info {
            Form {
                periodSection(info)
                if let kind = info.kind {
                    if !info.canVote {
                        Section {
                            Label("This baker is not in the voting listings for this period, so it cannot vote until the next period starts. Bakers need baking rights (enough stake) when the period opens.", systemImage: "info.circle")
                                .foregroundStyle(.secondary)
                        }
                    } else if kind.acceptsUpvotes {
                        proposalSection(info)
                    } else if kind.acceptsBallots {
                        ballotSection(info)
                    } else {
                        Section {
                            Text(kind == .cooldown
                                 ? "Nothing to vote on: the cooldown period gives everyone time between the exploration and promotion votes."
                                 : "Nothing to vote on: the adoption period waits for the new protocol to activate.")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .frame(height: 420)
        } else {
            HStack(spacing: 8) { ProgressView().controlSize(.small); Text("Reading the voting period…").foregroundStyle(.secondary) }
        }
    }

    private func periodSection(_ info: GovernanceInfo) -> some View {
        Section("Current period") {
            LabeledContent("Period", value: info.kind.map { "\($0.title)\(info.index.map { " (#\($0))" } ?? "")" } ?? "No governance period")
            if let remaining = info.remaining {
                LabeledContent("Remaining", value: "\(remaining.formatted()) blocks")
            }
            if let power = info.votingPower {
                LabeledContent("Your voting power", value: "\(AssetBalance.format(power / 1_000_000, symbol: "tz")) · \(percent(info.share(of: power)))")
            }
        }
    }

    private func proposalSection(_ info: GovernanceInfo) -> some View {
        Section("Proposals") {
            if info.proposals.isEmpty {
                Text("No proposals have been submitted yet in this period.").foregroundStyle(.secondary)
            }
            ForEach(info.proposals) { proposal in
                Toggle(isOn: Binding(
                    get: { selected.contains(proposal.hash) },
                    set: { on in if on { selected.insert(proposal.hash) } else { selected.remove(proposal.hash) } }
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(proposal.hash).font(.callout.monospaced()).lineLimit(1).truncationMode(.middle)
                        Text("\(percent(info.share(of: proposal.votingPower))) of voting power").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            TextField("Or a new proposal hash", text: $newProposal, prompt: Text("P…"))
                .font(.callout.monospaced()).autocorrectionDisabled()
            if !newProposal.trimmingCharacters(in: .whitespaces).isEmpty, !GovernanceOperation.isProposalHash(newProposal.trimmingCharacters(in: .whitespaces)) {
                Text("That is not a protocol hash (51 characters starting with P).").font(.callout).foregroundStyle(.orange)
            }
            Text("A baker may upvote up to \(GovernanceInfo.maximumUpvotesPerPeriod) proposals per period; you have used \(info.proposalCount). Upvoting cannot be undone.")
                .font(.callout).foregroundStyle(.secondary)
            Button("Upvote…") { startConfirm(.upvote(upvoteHashes)) }
                .disabled(upvoteHashes.isEmpty || info.proposalCount + upvoteHashes.count > GovernanceInfo.maximumUpvotesPerPeriod)
        }
    }

    private var upvoteHashes: [String] {
        var hashes = Array(selected).sorted()
        let typed = newProposal.trimmingCharacters(in: .whitespaces)
        if GovernanceOperation.isProposalHash(typed), !hashes.contains(typed) { hashes.append(typed) }
        return hashes
    }

    private func ballotSection(_ info: GovernanceInfo) -> some View {
        Section(info.kind == .exploration ? "Exploration vote" : "Promotion vote") {
            if let proposal = info.currentProposal {
                LabeledContent("Proposal") { Text(proposal).font(.callout.monospaced()).lineLimit(1).truncationMode(.middle).textSelection(.enabled) }
            }
            LabeledContent("So far") {
                Text("Yay \(percent(share(info.ballots.yay, of: info.ballots.total))) · Nay \(percent(share(info.ballots.nay, of: info.ballots.total))) · Pass \(percent(share(info.ballots.pass, of: info.ballots.total)))")
            }
            if let quorum = info.quorumPerTenThousand {
                LabeledContent("Turnout", value: "\(percent(info.share(of: info.ballots.total))) of \(percent(Double(quorum) / 10_000)) quorum")
            }
            if let mine = info.myBallot {
                Label("You voted \(mine.title) in this period. A ballot cannot be changed.", systemImage: "checkmark.seal.fill").foregroundStyle(.green)
            } else if let proposal = info.currentProposal {
                HStack(spacing: 10) {
                    ForEach(BallotVote.allCases) { vote in
                        Button(vote.title) { startConfirm(.ballot(proposal: proposal, vote: vote)) }
                    }
                }
                Text("Yay supports the proposal, Nay opposes it, Pass counts towards the quorum without taking a side.")
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

    private func confirmation(_ op: GovernanceOperation) -> some View {
        Form {
            LabeledContent("Operation", value: op.title)
            switch op {
            case .upvote(let hashes):
                ForEach(hashes, id: \.self) { hash in
                    LabeledContent("Proposal") { Text(hash).font(.callout.monospaced()).lineLimit(1).truncationMode(.middle) }
                }
            case .ballot(let proposal, let vote):
                LabeledContent("Proposal") { Text(proposal).font(.callout.monospaced()).lineLimit(1).truncationMode(.middle) }
                LabeledContent("Ballot", value: vote.title)
            }
            LabeledContent("Fee", value: "None (voting operations are free)")
            if needsPassphrase, let wallet { SecureField("Password for “\(wallet.alias)”", text: $passphrase) }
            if signsOnLedger { Text("Your Ledger will show this operation for approval.").font(.callout).foregroundStyle(.secondary) }
        }
        .formStyle(.grouped).scrollDisabled(true)
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
                    .disabled(needsPassphrase && passphrase.isEmpty)
            case .working:
                EmptyView()
            case .done:
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent)
            }
        }
    }

    private func load() async {
        loadError = nil
        do { info = try await model.governanceInfo() } catch { loadError = "Could not read the voting period: \(error.localizedDescription)" }
    }

    private func startConfirm(_ op: GovernanceOperation) {
        errorMessage = nil
        mode = .confirm(op)
    }

    private func perform(_ op: GovernanceOperation) async {
        errorMessage = nil
        mode = .working(op)
        do {
            let result = try await model.performGovernance(op, passphrase: needsPassphrase ? passphrase : nil)
            mode = .done(hash: result.hash, level: result.level, op)
            selected = []
            newProposal = ""
            await load()
        } catch {
            errorMessage = error.localizedDescription
            mode = .confirm(op)
        }
    }
}

#Preview {
    GovernanceSheet(model: .preview())
}
