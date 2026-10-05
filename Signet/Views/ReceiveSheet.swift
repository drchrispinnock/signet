import SwiftUI

/// Shows the selected wallet's address as a QR code and text so someone can send tez to it.
struct ReceiveSheet: View {
    let wallet: Wallet
    let domains: [String]
    @Environment(\.dismiss) private var dismiss
    @State private var copied = false

    private var qrImage: NSImage? { QRCode.image(for: wallet.address.value, size: 220) }

    var body: some View {
        VStack(spacing: 16) {
            Text("Receive")
                .font(.title2.weight(.semibold))

            VStack(spacing: 4) {
                Text(wallet.alias)
                    .font(.headline)
                ForEach(domains, id: \.self) { domain in
                    Text(domain)
                        .font(.callout)
                        .foregroundStyle(.secondary)
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
            .accessibilityLabel("QR code for \(wallet.address.value)")

            Text(wallet.address.value)
                .font(.body.monospaced())
                .textSelection(.enabled)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .frame(maxWidth: 360)

            Text("Only send tez and Tezos tokens to this address\(domains.isEmpty ? "." : ", or to \(domains[0]).")")
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
    }

    private func copyAddress() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(wallet.address.value, forType: .string)
        copied = true
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            copied = false
        }
    }
}

#Preview {
    ReceiveSheet(wallet: WalletViewModel.sampleWallets[0], domains: ["mytez.tez"])
}
