import SwiftUI

/// Approves or rejects the dApp request at the front of the queue.
struct DAppRequestSheet: View {
    @Bindable var model: WalletViewModel
    let request: DAppRequest

    @State private var chosenWallet: Wallet?
    @State private var passphrase = ""
    @State private var summaries: [DAppOperationSummary] = []
    @State private var prepared: DAppPreparedBatch?
    @State private var prepareError: String?
    @State private var showsParameters: Set<Int> = []
    @State private var isWorking = false

    private var dapps: DAppConnectionManager { model.dapps }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            content
            if let error = dapps.lastError {
                Text(error).font(.callout).foregroundStyle(.red)
            }
            buttons
        }
        .padding(20)
        .frame(width: 520)
        .onAppear {
            dapps.clearMessages()
            chosenWallet = model.selectedWallet.flatMap { $0.publicKey != nil && $0.keyKind.canSign ? $0 : nil }
                ?? model.wallets.first { $0.publicKey != nil && $0.keyKind.canSign }
        }
        .task(id: request.id) {
            guard case .operation(_, _, _, _, _, let json) = request else { return }
            prepared = nil; prepareError = nil
            summaries = await dapps.summaries(for: json)
            // Simulate the batch so the exact fee, burn and totals are known; approval waits for this.
            do { prepared = try await dapps.prepare(request) } catch { prepareError = error.localizedDescription }
        }
    }

    // MARK: Pieces

    private var header: some View {
        HStack(spacing: 12) {
            DAppIconView(url: request.app.icon, size: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.title2.weight(.semibold))
                HStack(spacing: 6) {
                    Text(request.app.name).font(.callout)
                    if let url = request.app.url { Text(url.host() ?? url.absoluteString).font(.callout).foregroundStyle(.secondary) }
                }
            }
        }
    }

    private var title: String {
        switch request {
        case .permission: "Connection request"
        case .operation: "Approve operation"
        case .signPayload: "Sign message"
        case .unsupported: "Unsupported request"
        }
    }

    @ViewBuilder
    private var content: some View {
        switch request {
        case .permission(_, _, let networkType, let rpcURL, let scopes):
            Form {
                Picker("Share account", selection: $chosenWallet) {
                    ForEach(model.wallets.filter { $0.publicKey != nil && $0.keyKind.canSign }) { wallet in
                        Text("\(wallet.alias)  \(wallet.address.shortened())").tag(Optional(wallet))
                    }
                }
                LabeledContent("Network", value: networkType + (rpcURL.map { " (\($0.host() ?? ""))" } ?? ""))
                LabeledContent("Permissions", value: scopes.map(scopeName).joined(separator: ", "))
                if DAppRequest.network(forType: networkType, rpcURL: rpcURL) == nil {
                    Label("Signet has no node for this network; operations from this dApp will fail.", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                }
                Text("The dApp will see this account's address and public key, and can ask you to approve operations and signatures. Nothing happens without your approval here.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            .formStyle(.grouped).scrollDisabled(true)

        case .operation(_, _, let networkType, let rpcURL, let source, _):
            Form {
                sourceRow(source)
                LabeledContent("Network", value: DAppRequest.network(forType: networkType, rpcURL: rpcURL)?.name ?? networkType)
                let shown = prepared?.operations ?? summaries
                if shown.isEmpty {
                    LabeledContent("Operations") { ProgressView().controlSize(.small) }
                } else {
                    ForEach(Array(shown.enumerated()), id: \.offset) { index, op in operationRow(index, op) }
                }
                costRows
                passphraseField(for: source)
                if let prepareError {
                    Label(prepareError, systemImage: "xmark.octagon").font(.callout).foregroundStyle(.red)
                    Text("The node could not simulate this batch, so it cannot be approved.").font(.callout).foregroundStyle(.secondary)
                } else if prepared == nil {
                    Text("Simulating on the node to get the exact fee and effects…").font(.callout).foregroundStyle(.secondary)
                } else {
                    Text("Fee and storage are what the node's simulation says this exact batch costs. Approving signs the batch exactly as shown; the dApp's own fee, gas and storage figures are not used.")
                        .font(.callout).foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            .frame(minHeight: 320, maxHeight: 560)

        case .signPayload(_, _, let source, let signingType, let payload):
            Form {
                sourceRow(source)
                LabeledContent("Type", value: signingType)
                LabeledContent("Message") {
                    ScrollView {
                        Text(decodedPayload(payload, signingType: signingType))
                            .font(.callout.monospaced())
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 140)
                }
                passphraseField(for: source)
                Text("Signing proves you control this account. Only sign messages you understand from dApps you trust. Signet signs packed Michelson messages only, never operations.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            .formStyle(.grouped).scrollDisabled(true)

        case .unsupported(_, _, let type):
            Text("Signet cannot handle “\(type)” requests yet.").foregroundStyle(.secondary)
        }
    }

    private func operationRow(_ index: Int, _ op: DAppOperationSummary) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            LabeledContent(op.kind.capitalized) {
                VStack(alignment: .trailing, spacing: 2) {
                    if let amount = op.amount, amount > 0 { Text(AssetBalance.format(amount, symbol: "tz")).monospacedDigit() }
                    if let destination = op.destination { Text(destination).font(.callout.monospaced()).foregroundStyle(.secondary) }
                    if let entrypoint = op.entrypoint { Text("entrypoint \(entrypoint)").font(.caption).foregroundStyle(.secondary) }
                    if let delegate = op.delegate { Text("to \(delegate)").font(.callout.monospaced()).foregroundStyle(.secondary) }
                    if let fee = op.fee { Text("fee \(AssetBalance.format(fee, symbol: "tz"))\(op.burn.map { $0 > 0 ? " · storage \(AssetBalance.format($0, symbol: "tz"))" : "" } ?? "")").font(.caption).foregroundStyle(.secondary) }
                }
            }
            ForEach(op.effects, id: \.self) { effect in
                Label(effect.text, systemImage: effect.warning ? "exclamationmark.triangle.fill" : "info.circle")
                    .font(.callout).foregroundStyle(effect.warning ? .orange : .secondary)
            }
            if op.opaque {
                Label("Signet cannot tell what this contract call does. Approve it only if you trust the dApp; the parameters are below.", systemImage: "exclamationmark.triangle.fill")
                    .font(.callout).foregroundStyle(.orange)
            }
            if let requested = op.requestedFee {
                Label("The dApp asked for a \(AssetBalance.format(requested, symbol: "tz")) fee; Signet pays the node's estimate instead.", systemImage: "info.circle")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let parameters = op.parameters {
                DisclosureGroup(isExpanded: Binding(get: { showsParameters.contains(index) }, set: { if $0 { showsParameters.insert(index) } else { showsParameters.remove(index) } })) {
                    ScrollView {
                        Text(parameters).font(.caption.monospaced()).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 160)
                } label: { Text("Parameters").font(.caption) }
            }
        }
    }

    @ViewBuilder
    private var costRows: some View {
        if let prepared {
            if let revealFee = prepared.revealFee {
                LabeledContent("Reveal", value: "fee \(AssetBalance.format(revealFee, symbol: "tz")) (first operation from this account)")
            }
            LabeledContent("Fee", value: AssetBalance.format(prepared.totalFee, symbol: "tz")).monospacedDigit()
            if prepared.totalBurn > 0 { LabeledContent("Storage", value: AssetBalance.format(prepared.totalBurn, symbol: "tz")).monospacedDigit() }
            LabeledContent("Total leaving the account", value: AssetBalance.format(prepared.totalDebit, symbol: "tz")).monospacedDigit().fontWeight(.semibold)
        } else if prepareError == nil {
            LabeledContent("Fee") { ProgressView().controlSize(.small) }
        }
    }

    private func sourceRow(_ source: Address) -> some View {
        LabeledContent("Account") {
            HStack(spacing: 8) {
                AccountAvatarView(address: source, size: 22)
                if let wallet = dapps.wallet(for: source) {
                    Text(wallet.alias)
                    Text(source.shortened()).font(.callout.monospaced()).foregroundStyle(.secondary)
                } else {
                    Label("\(source.shortened()) is not one of your accounts", systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                }
            }
        }
    }

    @ViewBuilder
    private func passphraseField(for source: Address) -> some View {
        if let wallet = dapps.wallet(for: source), wallet.keyKind == .encrypted {
            SecureField("Password for “\(wallet.alias)”", text: $passphrase)
        }
    }

    private var needsPassphrase: Bool {
        switch request {
        case .operation(_, _, _, _, let source, _), .signPayload(_, _, let source, _, _):
            return dapps.wallet(for: source)?.keyKind == .encrypted
        default:
            return false
        }
    }

    private var buttons: some View {
        HStack {
            if isWorking { ProgressView().controlSize(.small); Text(workingText).font(.callout).foregroundStyle(.secondary) }
            Spacer()
            Button("Reject", role: .cancel) { Task { await dapps.reject(request) } }
                .keyboardShortcut(.cancelAction)
                .disabled(isWorking)
            Button(approveTitle) { approve() }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(isWorking || (request.isPermission && chosenWallet == nil) || (needsPassphrase && passphrase.isEmpty) || (request.isOperation && prepared?.requestID != request.id))
        }
    }

    private var approveTitle: String {
        switch request {
        case .permission: "Connect"
        case .operation: "Approve and Send"
        case .signPayload: "Sign"
        case .unsupported: "Dismiss"
        }
    }

    private var workingText: String {
        let onLedger = sourceWallet?.keyKind == .ledger
        switch request {
        case .operation: return onLedger ? "Confirm on your Ledger…" : "Signing and sending…"
        case .signPayload: return onLedger ? "Sign on your Ledger…" : "Signing…"
        default: return "Working…"
        }
    }

    private var sourceWallet: Wallet? {
        switch request {
        case .operation(_, _, _, _, let source, _), .signPayload(_, _, let source, _, _): dapps.wallet(for: source)
        default: nil
        }
    }

    private func approve() {
        isWorking = true
        Task {
            defer { isWorking = false }
            switch request {
            case .permission:
                if let chosenWallet { await dapps.approvePermission(request, with: chosenWallet) }
            case .operation:
                guard let prepared, prepared.requestID == request.id else { return }
                await dapps.approveOperation(request, prepared: prepared, passphrase: needsPassphrase ? passphrase : nil)
            case .signPayload:
                await dapps.approveSignature(request, passphrase: needsPassphrase ? passphrase : nil)
            case .unsupported:
                await dapps.reject(request)
            }
        }
    }

    private func scopeName(_ scope: String) -> String {
        switch scope {
        case "sign": "sign messages"
        case "operation_request": "request operations"
        default: scope
        }
    }

    /// Micheline string payloads (0x0501 + length + UTF-8) are shown as text; anything else as hex.
    private func decodedPayload(_ payload: String, signingType: String) -> String {
        if signingType == "micheline", payload.hasPrefix("0501"), payload.count > 12,
           let bytes = Hex.bytes(fromHex: String(payload.dropFirst(12))),
           let text = String(bytes: bytes, encoding: .utf8) {
            return text
        }
        return payload
    }
}
