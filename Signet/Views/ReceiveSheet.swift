import SwiftUI

/// Shows the selected wallet's address as a QR code and text so someone can send tez to it.
/// The Etherlink side uses Etherlink 8.0's alias (`EtherlinkAlias`); a network still on the old
/// kernel shows a note instead of an address (`EtherlinkAliasStatus.awaitingUpgrade`).
/// With Layer 2 on, the logo at the top left has a pop-up beside it (`ChainSidePicker`) that
/// switches to the account's address on Etherlink's EVM side (`EtherlinkAlias`). That address
/// is only shown once it exists on chain (`EtherlinkAliasStatus.linked`): until the account has
/// made its first cross-interface call, tez sent to it would sit at an address nobody controls,
/// so the sheet offers to link the account first (a no-op gateway call paid on Etherlink).
struct ReceiveSheet: View {
    let wallet: Wallet
    let domains: [String]
    /// Offer the Etherlink address too: Layer 2 is on and the key is usable on the rollup.
    var showsEtherlink = false
    /// The model that checks and links the alias; `nil` (previews) shows the Tezos side only.
    var model: WalletViewModel? = nil
    @Environment(\.dismiss) private var dismiss
    @State private var copied = false
    @State private var side: ChainSide = .tezos
    @State private var alias: AliasState = .checking
    @State private var passphrase = ""

    enum AliasState: Equatable {
        case checking
        case linked(String)
        /// `unfunded`: the account holds no tez on Etherlink, so the link (paid there) cannot be
        /// estimated or sent until some are bridged across; the node's refusal is not shown.
        case unlinked(fee: Decimal?, problem: String?, unfunded: Bool = false)
        case linking
        /// The network still runs a kernel older than Etherlink 8.0, whose alias is not the account's for long.
        case awaitingUpgrade
        case failed(String)
    }

    private var address: String? {
        switch side {
        case .tezos: wallet.address.value
        case .etherlink: if case .linked(let evm) = alias { evm } else { nil }
        }
    }
    private var qrImage: NSImage? { address.flatMap { QRCode.image(for: $0, size: 220) } }
    private var needsPassphrase: Bool { model?.needsPassphrase(for: wallet) ?? (wallet.keyKind == .encrypted) }

    var body: some View {
        VStack(spacing: 16) {
            ZStack {
                Text("Receive")
                    .font(.title2.weight(.semibold))
                HStack {
                    ChainSidePicker(side: $side, canSwitch: showsEtherlink && model != nil, layer2Name: "EVM")
                    Spacer()
                }
            }

            VStack(spacing: 4) {
                Text(wallet.alias)
                    .font(.headline)
                if side == .tezos {
                    ForEach(domains, id: \.self) { domain in
                        Text(domain)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text("on \(Brand.l2)").font(.callout).foregroundStyle(.secondary)
                }
            }

            if let address {
                addressViews(address)
            } else {
                linkViews
            }

            HStack {
                if let address {
                    Button(copied ? "Copied" : "Copy address", systemImage: copied ? "checkmark" : "doc.on.doc") { copy(address) }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut("c", modifiers: [.command, .shift])
                }
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(alias == .linking)
            }
            .padding(.top, 4)
        }
        .padding(24)
        .frame(width: 420)
        .onChange(of: side) { copied = false }
        .task(id: side) { if side == .etherlink { await checkAlias() } }
    }

    @ViewBuilder
    private func addressViews(_ address: String) -> some View {
        Group {
            if let qrImage {
                Image(nsImage: qrImage)
                    .interpolation(.none)
                    .resizable()
                    .frame(width: 220, height: 220)
            } else {
                Text("Could not draw QR code")
                    .foregroundStyle(.secondary)
                    .frame(width: 220, height: 220)
            }
        }
        .padding(12)
        .background(.white, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.secondary.opacity(0.25)))
        .accessibilityLabel("QR code for \(address)")

        Text(address)
            .font(.body.monospaced())
            .textSelection(.enabled)
            .multilineTextAlignment(.center)
            .lineLimit(2)
            .frame(maxWidth: 360)

        Text(note)
            .font(.callout)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: 360)
    }

    /// The Etherlink side before the alias exists: what is going on, and the way to link.
    @ViewBuilder
    private var linkViews: some View {
        VStack(spacing: 12) {
            switch alias {
            case .checking:
                ProgressView().controlSize(.small)
                Text("Checking whether this account is known on \(Brand.l2)…").font(.callout).foregroundStyle(.secondary)
            case .linking:
                ProgressView().controlSize(.small)
                Text("Linking to \(Brand.l2)…").font(.callout).foregroundStyle(.secondary)
                if wallet.keyKind == .ledger { LedgerPromptLabel(text: "Confirm the link on your Ledger…") }
            case .awaitingUpgrade:
                Text("This account's address on \(Brand.l2)'s EVM side is not available until this network upgrades to \(Brand.l2) 8.0, which changes how that address is made. Until then, receive on \(Brand.l2) with the account's Tezos address.")
                    .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                Button("Check again") { Task { await checkAlias() } }
            case .failed(let message):
                Text(message).font(.callout).foregroundStyle(.red).multilineTextAlignment(.center)
                Button("Try again") { Task { await checkAlias() } }
            case .unlinked(let fee, let problem, let unfunded):
                Text("This account has no address on \(Brand.l2)'s EVM side yet. \(Brand.l2) creates one the first time the account calls across from its Tezos side; tez sent there before that would be stuck at an address nobody controls.")
                    .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                if unfunded {
                    Text("Linking sends a small no-op call from this account on \(Brand.l2), paid there, and this account holds no tez on \(Brand.l2) yet. Use Bridge… in the menu to move a little across, then come back here.")
                        .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    Button("Check again") { Task { await checkAlias() } }
                } else if wallet.keyKind.canSign {
                    Text("Linking sends a small no-op call from this account on \(Brand.l2). It needs a little tez there to pay the fee (use Bridge… first).")
                        .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    if wallet.keyKind == .encrypted, let model {
                        PasswordField(model: model, wallet: wallet, text: $passphrase).frame(maxWidth: 320)
                    }
                    if let problem { Text(problem).font(.callout).foregroundStyle(.orange).multilineTextAlignment(.center) }
                    Button(fee.map { "Link to \(Brand.l2) (fee \(AssetBalance.format($0, symbol: "tz")))" } ?? "Link to \(Brand.l2)") { Task { await link(limits: nil) } }
                        .buttonStyle(.borderedProminent)
                        .disabled(fee == nil || (needsPassphrase && passphrase.isEmpty))
                } else {
                    Text("Link it from a wallet that holds this account's key.").font(.callout).foregroundStyle(.secondary)
                }
            case .linked:
                EmptyView()
            }
        }
        .frame(maxWidth: 360, minHeight: 244)
    }

    private var note: String {
        switch side {
        case .tezos:
            "Only send tez and Tezos tokens to this address\(domains.isEmpty ? "." : ", or to \(domains[0]).")"
        case .etherlink:
            "This account's address on \(Brand.l2)'s EVM side. Tez sent to it on \(Brand.l2) are forwarded to this account; its own address on \(Brand.l2)'s Michelson side is the Tezos one."
        }
    }

    @State private var estimate: TransferEstimate?

    private func checkAlias() async {
        guard let model else { return }
        alias = .checking
        do {
            guard let status = try await model.etherlinkAliasStatus() else { alias = .failed("Layer 2 is off for this network."); return }
            if case .linked(let evm) = status { alias = .linked(evm); return }
            if status == .awaitingUpgrade { alias = .awaitingUpgrade; return }
            guard wallet.keyKind.canSign else { alias = .unlinked(fee: nil, problem: nil); return }
            // A fresh account has nothing on Etherlink to pay the link with: say so instead of
            // asking the node, whose refusal (an empty implicit contract) would read as a fault.
            if model.etherlinkSpendable == 0 { alias = .unlinked(fee: nil, problem: nil, unfunded: true); return }
            do {
                let fee = try await model.estimateEtherlinkLink()
                estimate = fee
                alias = .unlinked(fee: fee.fee, problem: nil)
            } catch ChainError.cannotPayFee {
                alias = .unlinked(fee: nil, problem: nil, unfunded: true)
            } catch {
                alias = .unlinked(fee: nil, problem: "The link cannot be estimated: \(error.localizedDescription)")
            }
        } catch {
            alias = .failed(error.localizedDescription)
        }
    }

    private func link(limits: OperationLimits?) async {
        guard let model else { return }
        let fee = estimate?.fee
        alias = .linking
        do {
            _ = try await model.linkToEtherlink(limits: limits ?? estimate?.limits, passphrase: needsPassphrase ? passphrase : nil)
            passphrase = ""
            await checkAlias()
        } catch ChainError.cannotPayFee {
            alias = .unlinked(fee: nil, problem: nil, unfunded: true)
        } catch {
            alias = .unlinked(fee: fee, problem: error.localizedDescription)
        }
    }

    private func copy(_ address: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(address, forType: .string)
        copied = true
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            copied = false
        }
    }
}

#Preview {
    ReceiveSheet(wallet: WalletViewModel.sampleWallets[0], domains: ["mytez.tez"], showsEtherlink: true, model: .preview())
}
