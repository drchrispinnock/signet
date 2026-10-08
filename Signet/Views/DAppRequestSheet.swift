import SwiftUI

/// Approves or rejects the dApp request at the front of the queue.
struct DAppRequestSheet: View {
    @Bindable var model: WalletViewModel
    let request: DAppRequest

    @State private var chosenWallet: Wallet?
    @State private var passphrase = ""
    @State private var summaries: [DAppOperationSummary] = []
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
            if case .operation(_, _, _, _, _, let json) = request { summaries = await dapps.summaries(for: json) }
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
                if summaries.isEmpty {
                    LabeledContent("Operations") { ProgressView().controlSize(.small) }
                } else {
                    ForEach(Array(summaries.enumerated()), id: \.offset) { _, op in
                        LabeledContent(op.kind.capitalized) {
                            VStack(alignment: .trailing, spacing: 2) {
                                if let amount = op.amount, amount > 0 { Text(AssetBalance.format(amount, symbol: "tz")).monospacedDigit() }
                                if let destination = op.destination { Text(destination).font(.callout.monospaced()).foregroundStyle(.secondary) }
                                if let entrypoint = op.entrypoint { Text("entrypoint \(entrypoint)").font(.caption).foregroundStyle(.secondary) }
                                if let delegate = op.delegate { Text("to \(delegate)").font(.callout.monospaced()).foregroundStyle(.secondary) }
                            }
                        }
                    }
                }
                passphraseField(for: source)
                Text("Fees are estimated by the node when you approve. Check the destination and amount carefully: this will be signed with your key and sent.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            .formStyle(.grouped).scrollDisabled(true)

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
                Text("Signing proves you control this account. Only sign messages you understand from dApps you trust.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            .formStyle(.grouped).scrollDisabled(true)

        case .unsupported(_, _, let type):
            Text("Signet cannot handle “\(type)” requests yet.").foregroundStyle(.secondary)
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
                .disabled(isWorking || (request.isPermission && chosenWallet == nil) || (needsPassphrase && passphrase.isEmpty))
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
                await dapps.approveOperation(request, passphrase: needsPassphrase ? passphrase : nil)
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
           let bytes = Base58Hex.bytes(fromHex: String(payload.dropFirst(12))),
           let text = String(bytes: bytes, encoding: .utf8) {
            return text
        }
        return payload
    }
}

enum Base58Hex {
    static func bytes(fromHex hex: String) -> [UInt8]? {
        guard hex.count % 2 == 0 else { return nil }
        var out: [UInt8] = []
        var index = hex.startIndex
        while index < hex.endIndex {
            let next = hex.index(index, offsetBy: 2)
            guard let byte = UInt8(hex[index..<next], radix: 16) else { return nil }
            out.append(byte)
            index = next
        }
        return out
    }
}
