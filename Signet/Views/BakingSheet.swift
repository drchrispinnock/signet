import SwiftUI

/// Baking: register this wallet as a baker (self-delegate), set its consensus and companion keys,
/// and its staking parameters. Read-only when Signet holds no usable key for the wallet.
struct BakingSheet: View {
    @Bindable var model: WalletViewModel
    @Environment(\.dismiss) private var dismiss

    enum KeyRole { case consensus, companion }
    enum Mode: Equatable { case overview, pickKey(KeyRole), parameters, confirm(StakingOperation), working(StakingOperation), done(hash: String, level: Int, StakingOperation) }

    @State private var mode: Mode = .overview
    @State private var estimate: TransferEstimate?
    @State private var passphrase = ""
    @State private var keyPassphrase = ""
    @State private var chosenKeyWallet: Wallet?
    @State private var pastedPublicKey = ""
    @State private var pastedProof = ""
    @State private var limitText = ""
    @State private var edgeText = ""
    @State private var errorMessage: String?

    private var wallet: Wallet? { model.selectedWallet }
    private var baker: DelegateInfo.Baker? { model.delegateInfo?.baker }
    private var needsPassphrase: Bool { wallet?.keyKind == .encrypted }
    private var canOperate: Bool { wallet?.keyKind.canSign == true }
    /// Quantumnet has no companion keys; consensus keys there may be tz6 (XMSS).
    private var hasCompanionKeys: Bool { model.network.chain != "quantumnet" }

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
    }

    private var title: String {
        switch mode {
        case .overview: "Baking"
        case .pickKey(.consensus): "Set consensus key"
        case .pickKey(.companion): "Set companion key"
        case .parameters: "Staking parameters"
        case .confirm(let op), .working(let op): op.title
        case .done(_, _, let op): "\(op.title): done"
        }
    }

    @ViewBuilder
    private var content: some View {
        switch mode {
        case .overview: overview
        case .pickKey(let role): keyPicker(role)
        case .parameters: parametersForm
        case .confirm(let op): confirmation(op)
        case .working(let op): HStack(spacing: 8) { ProgressView().controlSize(.small); Text("\(op.title)… waiting for the next block").foregroundStyle(.secondary) }
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

    private var overview: some View {
        Form {
            if !canOperate {
                Section {
                    Label(watchOnlyNote, systemImage: "eye").foregroundStyle(.secondary)
                }
            }
            Section("Baker") {
                if model.delegateInfo == nil {
                    ProgressView().controlSize(.small)
                } else if let baker {
                    LabeledContent("Status", value: baker.deactivated ? "Registered, deactivated" : "Registered, active")
                    if let grace = baker.gracePeriod { LabeledContent("Grace period until cycle", value: "\(grace)") }
                } else {
                    Text(canOperate
                         ? "This wallet is not a baker. Registering self-delegates it; baking rights need at least the protocol's minimum stake and a running baker daemon."
                         : "This address is not a baker.")
                        .foregroundStyle(.secondary)
                    if canOperate { Button("Register as a baker…") { startConfirm(.registerAsBaker) } }
                }
            }
            if let baker {
                Section("Consensus key") {
                    keyRow(current: baker.consensusKey, pending: baker.pendingConsensusKeys, fallback: "Baker's own key")
                    if canOperate { Button("Set consensus key…") { resetKeyPicker(); mode = .pickKey(.consensus) } }
                    Text(hasCompanionKeys
                         ? "The key the baker daemon signs blocks and attestations with. A tz4 (BLS) key needs its proof of possession."
                         : "The key the baker daemon signs with. On Quantumnet this can be a post-quantum tz6 (XMSS) key.")
                        .font(.callout).foregroundStyle(.secondary)
                }
                if hasCompanionKeys {
                    Section("Companion key") {
                        keyRow(current: baker.companionKey, pending: baker.pendingCompanionKeys, fallback: "None")
                        if canOperate { Button("Set companion key…") { resetKeyPicker(); mode = .pickKey(.companion) } }
                        Text("A tz4 (BLS) key used for DAL attestations alongside a non-BLS consensus key.")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                }
                Section("Staking parameters") {
                    if let p = baker.stakingParameters {
                        LabeledContent("Limit of staking over baking", value: "\(formatted(p.limitMultiplier))×")
                        LabeledContent("Edge of baking over staking", value: "\(formatted(p.edgePercent)) %")
                    } else {
                        LabeledContent("Active", value: "Defaults (no staking accepted)")
                    }
                    ForEach(Array(baker.pendingStakingParameters.enumerated()), id: \.offset) { _, p in
                        LabeledContent("Pending from cycle \(p.cycle.map(String.init) ?? "?")", value: "\(formatted(p.limitMultiplier))× · \(formatted(p.edgePercent)) %")
                    }
                    if canOperate {
                        Button("Change…") {
                            limitText = formatted(baker.stakingParameters?.limitMultiplier ?? 0)
                            edgeText = formatted(baker.stakingParameters?.edgePercent ?? 0)
                            mode = .parameters
                        }
                    }
                    Text("The limit caps how much stake you accept from others, as a multiple of your own (0 = none, up to 9×). The edge is the share of stakers' rewards you keep (0 to 100 %). Changes apply after a few cycles.")
                        .font(.callout).foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .frame(height: baker == nil ? (canOperate ? 190 : 240) : 520)
    }

    private var watchOnlyNote: String {
        switch wallet?.keyKind {
        case .ledger: "Watch only: this baker's key is on a Ledger, which Signet cannot drive yet. Its keys and parameters are shown but cannot be changed here."
        case .remote: "Watch only: this baker signs through a remote signer. Its keys and parameters are shown but cannot be changed here."
        default: "Watch only: Signet holds just this baker's public key. Its keys and parameters are shown but cannot be changed here."
        }
    }

    private func keyRow(current: Address?, pending: [Address], fallback: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            LabeledContent("Active") {
                if let current {
                    HStack(spacing: 6) { AccountAvatarView(address: current, size: 20); Text(model.displayName(for: current, indexerAlias: nil).name); Text(current.shortened()).font(.callout.monospaced()).foregroundStyle(.secondary) }
                } else { Text(fallback).foregroundStyle(.secondary) }
            }
            ForEach(pending, id: \.value) { key in
                LabeledContent("Pending") { Text(key.shortened()).font(.callout.monospaced()).foregroundStyle(.secondary) }
            }
        }
    }

    // MARK: Key picker

    private func resetKeyPicker() {
        chosenKeyWallet = nil; pastedPublicKey = ""; pastedProof = ""; keyPassphrase = ""
    }

    private func eligibleWallets(_ role: KeyRole) -> [Wallet] {
        model.wallets.filter { w in
            guard w.publicKey != nil, w.address != wallet?.address else { return false }
            return role == .companion ? w.scheme == .tz4 : true   // consensus: any scheme the network allows
        }
    }

    private var pickedPublicKey: String? {
        if let pk = chosenKeyWallet?.publicKey { return pk }
        let pasted = pastedPublicKey.trimmingCharacters(in: .whitespacesAndNewlines)
        return pasted.isEmpty ? nil : pasted
    }
    private var pickedIsBLS: Bool { pickedPublicKey?.hasPrefix("BLpk") == true }
    private var proofNeeded: Bool { pickedIsBLS }
    private var proofAvailable: Bool {
        guard proofNeeded else { return true }
        if let w = chosenKeyWallet, w.scheme == .tz4, w.keyKind.canSign { return w.keyKind != .encrypted || !keyPassphrase.isEmpty }
        return !pastedProof.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private func keyPicker(_ role: KeyRole) -> some View {
        Form {
            Picker("From your wallets", selection: $chosenKeyWallet) {
                Text("Choose…").tag(Optional<Wallet>.none)
                ForEach(eligibleWallets(role)) { w in
                    Text("\(w.alias)  \(w.address.shortened())  (\(w.scheme.rawValue)\(w.keyKind.canSign ? "" : ", public key only"))").tag(Optional(w))
                }
            }
            TextField("Or paste a public key", text: $pastedPublicKey,
                      prompt: Text(role == .companion ? "BLpk…" : "edpk… / sppk… / p2pk… / BLpk… / mdpk… / xmpk…"))
                .font(.callout.monospaced()).autocorrectionDisabled()
                .onChange(of: pastedPublicKey) { if !pastedPublicKey.isEmpty { chosenKeyWallet = nil } }
            if proofNeeded {
                if let w = chosenKeyWallet, w.scheme == .tz4, w.keyKind.canSign {
                    if w.keyKind == .encrypted { SecureField("Password for “\(w.alias)” (to prove possession)", text: $keyPassphrase) }
                    else { Text("Signet will produce the BLS proof of possession from this wallet's key.").font(.callout).foregroundStyle(.secondary) }
                } else {
                    TextField("Proof of possession (BLsig…)", text: $pastedProof).font(.callout.monospaced()).autocorrectionDisabled()
                    Text("BLS keys must prove possession. Paste the proof made where the key lives, e.g. octez-client's BLS proof for that key.")
                        .font(.callout).foregroundStyle(.secondary)
                }
            }
            Text(role == .consensus ? "Takes effect after the consensus-rights delay (a few cycles)." : "Companion keys must be tz4 (BLS).")
                .font(.callout).foregroundStyle(.secondary)
        }
        .formStyle(.grouped).scrollDisabled(true)
    }

    // MARK: Parameters

    private var parametersForm: some View {
        Form {
            HStack { TextField("Limit of staking over baking", text: $limitText).font(.body.monospacedDigit()); Text("× your own stake (0–9)").foregroundStyle(.secondary) }
            HStack { TextField("Edge of baking over staking", text: $edgeText).font(.body.monospacedDigit()); Text("% of stakers' rewards you keep (0–100)").foregroundStyle(.secondary) }
            if parsedParameters == nil, !limitText.isEmpty, !edgeText.isEmpty {
                Text("The limit must be between 0 and 9 and the edge between 0 and 100.").font(.callout).foregroundStyle(.secondary)
            }
            Text("Set the limit to 0 to stop accepting new stake. Changes take effect after a few cycles.")
                .font(.callout).foregroundStyle(.secondary)
        }
        .formStyle(.grouped).scrollDisabled(true)
    }

    private var parsedParameters: StakingParameters? {
        func decimal(_ s: String) -> Decimal? { Decimal(string: s.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: "."), locale: Locale(identifier: "en_US_POSIX")) }
        guard let limit = decimal(limitText), let edge = decimal(edgeText) else { return nil }
        return StakingParameters(limitMultiplier: limit, edgePercent: edge)
    }

    private func formatted(_ d: Decimal) -> String {
        let f = NumberFormatter(); f.minimumFractionDigits = 0; f.maximumFractionDigits = 2
        return f.string(from: d as NSDecimalNumber) ?? "\(d)"
    }

    // MARK: Confirm

    private func confirmation(_ op: StakingOperation) -> some View {
        Form {
            LabeledContent("Operation", value: op.title)
            switch op {
            case .updateConsensusKey(let pk, _), .updateCompanionKey(let pk, _):
                LabeledContent("Public key") { Text(pk).font(.callout.monospaced()).lineLimit(1).truncationMode(.middle) }
            case .setStakingParameters(let p, _):
                LabeledContent("Limit", value: "\(formatted(p.limitMultiplier))×")
                LabeledContent("Edge", value: "\(formatted(p.edgePercent)) %")
            default: EmptyView()
            }
            if let estimate { LabeledContent("Fee", value: AssetBalance.format(estimate.fee, symbol: "tz")) } else { LabeledContent("Fee") { ProgressView().controlSize(.small) } }
            if needsPassphrase, let wallet { SecureField("Password for “\(wallet.alias)”", text: $passphrase) }
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
            case .pickKey(let role):
                Button("Back") { mode = .overview }.keyboardShortcut(.cancelAction)
                Button("Continue") { Task { await prepareKeyUpdate(role) } }
                    .keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent)
                    .disabled(pickedPublicKey == nil || !proofAvailable || (role == .companion && !pickedIsBLS))
            case .parameters:
                Button("Back") { mode = .overview }.keyboardShortcut(.cancelAction)
                Button("Continue") { if let p = parsedParameters, let wallet { startConfirm(.setStakingParameters(p, source: wallet.address)) } }
                    .keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent)
                    .disabled(parsedParameters == nil)
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

    private func prepareKeyUpdate(_ role: KeyRole) async {
        errorMessage = nil
        guard let publicKey = pickedPublicKey else { return }
        do {
            var proof: String?
            if pickedIsBLS {
                if let keyWallet = chosenKeyWallet, keyWallet.scheme == .tz4, keyWallet.keyKind.canSign {
                    proof = try await model.proofOfPossession(for: keyWallet, passphrase: keyWallet.keyKind == .encrypted ? keyPassphrase : nil)
                } else {
                    proof = pastedProof.trimmingCharacters(in: .whitespaces)
                }
            }
            startConfirm(role == .consensus ? .updateConsensusKey(publicKey: publicKey, proof: proof) : .updateCompanionKey(publicKey: publicKey, proof: proof))
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func startConfirm(_ op: StakingOperation) {
        errorMessage = nil
        estimate = nil
        mode = .confirm(op)
        Task { do { estimate = try await model.estimateStaking(op) } catch { errorMessage = error.localizedDescription } }
    }

    private func perform(_ op: StakingOperation) async {
        errorMessage = nil
        mode = .working(op)
        do {
            let result = try await model.performStaking(op, passphrase: needsPassphrase ? passphrase : nil)
            mode = .done(hash: result.hash, level: result.level, op)
        } catch {
            errorMessage = error.localizedDescription
            mode = .confirm(op)
        }
    }
}
