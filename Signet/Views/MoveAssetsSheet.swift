import SwiftUI

/// Move assets (under Bridge in both menus): everything one account holds goes to another
/// account in the list or address book: tez and NFTs, on Tezos and, with Layer 2 on, on
/// Etherlink (fungible tokens and domains later). Choose the two accounts, accept that the
/// move may be one way (and, when Signet holds no key for the destination, that it is out of
/// reach from here), review what the plan found, then each layer goes out as one operation
/// group. Staked or unstaking tez, or a baker, stop it at the review (`planMoveAssets`).
struct MoveAssetsSheet: View {
    @Bindable var model: WalletViewModel
    @Environment(\.dismiss) private var dismiss

    enum Step: Hashable { case choose, warn, review, working, done }

    @State private var step: Step = .choose
    @State private var sourceID: Wallet.ID?
    @State private var destinationID: Wallet.ID?
    @State private var understoodOneWay = false
    @State private var understoodNoKey = false
    @State private var plan: WalletViewModel.MoveAssetsPlan?
    @State private var planError: String?
    @State private var isPlanning = false
    @State private var passphrase = ""
    @State private var errorMessage: String?
    @State private var completed: [WalletViewModel.MoveAssetsStep] = []

    init(model: WalletViewModel) {
        self.model = model
        let selected = model.selectedWallet
        _sourceID = State(initialValue: model.moveSources.contains { $0.id == selected?.id } ? selected?.id : model.moveSources.first?.id)
    }

    private var source: Wallet? { plan?.source ?? model.moveSources.first { $0.id == sourceID } }
    private var destination: Wallet? { plan?.destination ?? model.moveDestinations(from: source).first { $0.id == destinationID } }
    private var destinationHoldsKey: Bool { destination.map(WalletViewModel.holdsKey(of:)) ?? true }
    private var needsPassphrase: Bool { source?.keyKind == .encrypted }
    private var signsOnLedger: Bool { source?.keyKind == .ledger }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Move assets").font(.title2.weight(.semibold))
            switch step {
            case .choose: chooser
            case .warn: warnings
            case .review: review
            case .working, .done: progressView
            }
            if let errorMessage { Text(errorMessage).font(.callout).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true) }
            buttons
        }
        .padding(20)
        .frame(width: 560)
    }

    // MARK: Steps

    private var chooser: some View {
        Form {
            Picker("From", selection: $sourceID) {
                ForEach(model.moveSources) { wallet in Text(title(wallet)).tag(Optional(wallet.id)) }
            }
            Picker("To", selection: $destinationID) {
                Text("Choose an account").tag(Wallet.ID?.none)
                let destinations = model.moveDestinations(from: source)
                let mine = destinations.filter(WalletViewModel.holdsKey(of:))
                let others = destinations.filter { !WalletViewModel.holdsKey(of: $0) }
                if !mine.isEmpty {
                    Section("My accounts") { ForEach(mine) { wallet in Text(title(wallet)).tag(Optional(wallet.id)) } }
                }
                if !others.isEmpty {
                    Section("Address book") { ForEach(others) { wallet in Text(title(wallet)).tag(Optional(wallet.id)) } }
                }
            }
            Text("Everything in the first account moves to the second: its tez, tokens and NFTs on \(model.network.name)\(model.network.hasL2 ? " and on \(model.network.l2Name)" : "")\(model.network.tezosDomainsURL != nil ? ", and the Tezos Domains names it owns, pointed at the new account" : "").")
                .font(.callout).foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
        .scrollDisabled(true)
        .onChange(of: sourceID) { if destinationID == sourceID { destinationID = nil } }
    }

    private var warnings: some View {
        VStack(alignment: .leading, spacing: 14) {
            pair
            VStack(alignment: .leading, spacing: 6) {
                Label("Moving assets may be one way.", systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange).font(.headline)
                Text("Signet cannot undo the move. Getting anything back means sending it back from “\(destination?.alias ?? "")”, which only whoever holds that account's key can do, and costs fees again.")
                    .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Toggle("I understand that the move cannot be undone from here", isOn: $understoodOneWay)
            }
            if !destinationHoldsKey, let destination {
                VStack(alignment: .leading, spacing: 6) {
                    Label("Signet does not hold the key for “\(destination.alias)”.", systemImage: "key.slash").foregroundStyle(.red).font(.headline)
                    Text("It is \(destination.keyKind == .none ? "an address book entry" : "an account Signet cannot sign for"). Unless you hold its key somewhere else, everything moved there is out of your reach for good.")
                        .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    Toggle("I hold the key to “\(destination.alias)” elsewhere, or I mean to give these assets away", isOn: $understoodNoKey)
                }
            }
        }
    }

    private var review: some View {
        VStack(alignment: .leading, spacing: 12) {
            pair
            if isPlanning {
                HStack(spacing: 8) { ProgressView().controlSize(.small); Text("Reading balances and NFTs, and estimating fees…").font(.callout).foregroundStyle(.secondary) }
            } else if let planError {
                Label(planError, systemImage: "xmark.octagon.fill").foregroundStyle(.red).font(.callout).fixedSize(horizontal: false, vertical: true)
            } else if let plan {
                Form {
                    ForEach(plan.layers, id: \.layer) { layer in
                        Section(layer.name) {
                            LabeledContent("Tez", value: AssetBalance.format(layer.tez, symbol: "tz"))
                            LabeledContent("Tokens", value: layer.tokens.isEmpty ? "None" : layer.tokens.count <= 3 ? layer.tokens.map(\.formattedAmount).joined(separator: ", ") : "\(layer.tokens.count) tokens")
                            LabeledContent("NFTs", value: layer.nfts.isEmpty ? "None" : "\(layer.nfts.count) (\(layer.editions) edition\(layer.editions == 1 ? "" : "s"))")
                            if !layer.domains.isEmpty || !layer.domainsLeftBehind.isEmpty {
                                LabeledContent("Domains", value: layer.domains.isEmpty ? "None" : layer.domains.count <= 3 ? layer.domains.map(\.name).joined(separator: ", ") : "\(layer.domains.count) names")
                                    .help("Each name moves to the new account and is pointed at it.")
                            }
                            LabeledContent("Fees and storage", value: AssetBalance.format(layer.cost, symbol: "tz"))
                            if layer.batches.count > 1 {
                                Text("\(layer.batches.count) operations, one after another (at most \(TokenTransferRequest.maxTokens) tokens and NFTs each).").font(.caption).foregroundStyle(.secondary)
                            }
                            if !layer.domainsLeftBehind.isEmpty {
                                Text("\(layer.domainsLeftBehind.count) name\(layer.domainsLeftBehind.count == 1 ? "" : "s") stay\(layer.domainsLeftBehind.count == 1 ? "s" : ""): expired, or owned by someone else and only pointing here.").font(.caption).foregroundStyle(.secondary)
                            }
                            if !layer.tokensLeftBehind.isEmpty {
                                Text("\(layer.tokensLeftBehind.count) token\(layer.tokensLeftBehind.count == 1 ? "'s" : "s'") exact balance is unknown, so \(layer.tokensLeftBehind.count == 1 ? "it stays" : "they stay").").font(.caption).foregroundStyle(.orange)
                            }
                            if !layer.leftBehind.isEmpty {
                                Text("\(layer.leftBehind.count) NFT\(layer.leftBehind.count == 1 ? " is" : "s are") marked as not transferable and stay\(layer.leftBehind.count == 1 ? "s" : "").").font(.caption).foregroundStyle(.orange)
                            }
                        }
                    }
                    if !plan.notes.isEmpty {
                        Section { ForEach(plan.notes, id: \.self) { Text($0).font(.callout).foregroundStyle(.orange) } }
                    }
                    if needsPassphrase, let source { SecureField("Password for “\(source.alias)”", text: $passphrase) }
                }
                .formStyle(.grouped)
                .frame(maxHeight: 360)
                Text("“\(plan.source.alias)” is left empty, apart from a little tez the fee estimate may have kept back.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .task(id: step) { if step == .review, plan == nil { await makePlan() } }
    }

    private var progressView: some View {
        VStack(alignment: .leading, spacing: 10) {
            pair
            ForEach(completed) { done in
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    Text("\(plan?.layers.first { $0.layer == done.layer }?.name ?? "") · block \(done.level.formatted())").font(.callout)
                    Text(done.hash).font(.callout.monospaced()).textSelection(.enabled).lineLimit(1).truncationMode(.middle)
                    if let url = done.explorerURL { Link("Explorer", destination: url).font(.callout) }
                }
            }
            if step == .working {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Moving… operation \(completed.count + 1) of \(plan?.batchCount ?? 1)").font(.callout).foregroundStyle(.secondary)
                }
                if signsOnLedger { LedgerPromptLabel(text: "Confirm the move on your Ledger…") }
            } else if errorMessage == nil, let plan {
                Label("Moved to “\(plan.destination.alias)”.", systemImage: "checkmark.seal.fill").foregroundStyle(.green)
            }
        }
    }

    /// Both accounts, side by side.
    private var pair: some View {
        HStack(spacing: 10) {
            accountLabel(source)
            Image(systemName: "arrow.right").foregroundStyle(.secondary)
            accountLabel(destination)
            Spacer()
        }
    }

    @ViewBuilder
    private func accountLabel(_ wallet: Wallet?) -> some View {
        if let wallet {
            HStack(spacing: 6) {
                AccountAvatarView(address: wallet.address, size: 28)
                VStack(alignment: .leading, spacing: 0) {
                    Text(wallet.alias).font(.callout.weight(.medium))
                    Text(wallet.address.shortened()).font(.caption.monospaced()).foregroundStyle(.secondary)
                }
            }
        }
    }

    private var buttons: some View {
        HStack {
            if step == .warn || (step == .review && !isPlanning) {
                Button("Back") { back() }
            }
            Spacer()
            switch step {
            case .choose:
                Button("Cancel", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Continue") { errorMessage = nil; step = .warn }
                    .keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent).disabled(source == nil || destination == nil)
            case .warn:
                Button("Cancel", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Continue") { step = .review }
                    .keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent)
                    .disabled(!understoodOneWay || (!destinationHoldsKey && !understoodNoKey))
            case .review:
                Button("Cancel", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Move") { Task { await move() } }
                    .keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent).tint(.orange)
                    .disabled(plan == nil || isPlanning || (needsPassphrase && passphrase.isEmpty))
            case .working:
                Button("Cancel", role: .cancel) { dismiss() }.disabled(true)
            case .done:
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent)
            }
        }
    }

    // MARK: Actions

    private func title(_ wallet: Wallet) -> String { "\(wallet.alias)  \(wallet.address.shortened())" }

    private func back() {
        errorMessage = nil
        if step == .review { plan = nil; planError = nil; step = .warn } else { step = .choose }
    }

    private func makePlan() async {
        guard let source, let destination else { return }
        isPlanning = true
        planError = nil
        defer { isPlanning = false }
        do {
            plan = try await model.planMoveAssets(from: source, to: destination)
        } catch {
            if !Task.isCancelled { planError = error.localizedDescription }
        }
    }

    private func move() async {
        guard let plan else { return }
        errorMessage = nil
        completed = []
        step = .working
        do {
            try await model.moveAssets(plan, passphrase: needsPassphrase ? passphrase : nil) { completed.append($0) }
            step = .done
        } catch {
            errorMessage = error.localizedDescription
            if completed.isEmpty {
                // Nothing went out (a wrong password, a Ledger that was not ready…): plan again.
                self.plan = nil
                step = .review
                if case ChainError.wrongPassphrase = error { } else { await makePlan() }
            } else {
                errorMessage = (errorMessage ?? "") + " The operations listed above went through; the rest did not. Start Move assets again for what is left."
                step = .done
            }
        }
    }
}

#Preview {
    MoveAssetsSheet(model: .preview())
}
