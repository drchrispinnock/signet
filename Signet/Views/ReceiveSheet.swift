import SwiftUI

/// Shows the selected wallet's address as a QR code and text so someone can send tez to it.
/// With Layer 2 on, the logo at the top left has a pop-up beside it (`ChainSidePicker`) that
/// switches between the account's Tezos address and its address on Etherlink's EVM side
/// (`EtherlinkAlias`).
struct ReceiveSheet: View {
    let wallet: Wallet
    let domains: [String]
    /// Offer the Etherlink address too: Layer 2 is on and the key is usable on the rollup.
    var showsEtherlink = false
    @Environment(\.dismiss) private var dismiss
    @State private var copied = false
    @State private var side: ChainSide = .tezos

    private var address: String {
        switch side {
        case .tezos: wallet.address.value
        case .etherlink: EtherlinkAlias.address(for: wallet.address)
        }
    }
    private var qrImage: NSImage? { QRCode.image(for: address, size: 220) }

    var body: some View {
        VStack(spacing: 16) {
            ZStack {
                Text("Receive")
                    .font(.title2.weight(.semibold))
                HStack {
                    chainPicker
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
                    Text("on Etherlink").font(.callout).foregroundStyle(.secondary)
                }
            }

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

            HStack {
                Button(copied ? "Copied" : "Copy address", systemImage: copied ? "checkmark" : "doc.on.doc", action: copyAddress)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut("c", modifiers: [.command, .shift])
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.top, 4)
        }
        .padding(24)
        .frame(width: 420)
        .onChange(of: side) { copied = false }
    }

    private var chainPicker: some View {
        ChainSidePicker(side: $side, canSwitch: showsEtherlink)
    }

    private var note: String {
        switch side {
        case .tezos:
            "Only send tez and Tezos tokens to this address\(domains.isEmpty ? "." : ", or to \(domains[0]).")"
        case .etherlink:
            "This account's address on Etherlink's EVM side. Tez sent to it on Etherlink are forwarded to this account; its own address on Etherlink's Michelson side is the Tezos one."
        }
    }

    private func copyAddress() {
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
    ReceiveSheet(wallet: WalletViewModel.sampleWallets[0], domains: ["mytez.tez"], showsEtherlink: true)
}
