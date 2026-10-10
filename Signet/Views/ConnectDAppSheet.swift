import AppKit
import SwiftUI

/// Pair with a dApp by pasting its Octez Connect code, and manage existing connections.
struct ConnectDAppSheet: View {
    @Bindable var model: WalletViewModel
    var isSwapFlow = false
    @Environment(\.dismiss) private var dismiss
    @State private var code = ""
    @State private var isPairing = false
    @State private var message: String?
    @State private var isError = false

    private var dapps: DAppConnectionManager { model.dapps }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(isSwapFlow ? "Swap" : "Connect to a dApp")
                    .font(.title2.weight(.semibold))
                Spacer()
                HStack(spacing: 6) {
                    Circle().fill(dapps.isStarted ? .green : (dapps.lastError == nil ? .gray : .red)).frame(width: 8, height: 8)
                    Text(AppRuntime.isDemo ? "Demo" : (dapps.isStarted ? "Octez Connect running" : (dapps.lastError == nil ? "Starting…" : "Octez Connect failed")))
                        .font(.caption).foregroundStyle(.secondary)
                }
                .help(AppRuntime.isDemo ? "Sample accounts cannot connect" : (dapps.lastError ?? "Octez Connect relay status"))
            }
            if let error = dapps.lastError, !dapps.isStarted {
                Text(error).font(.callout).foregroundStyle(.red)
                Button("Try again") { Task { await dapps.restart() } }
            }

            if isSwapFlow { swapIntroduction }

            Form {
                Section {
                    TextField("Pairing code", text: $code, prompt: Text("Paste the code from the dApp"), axis: .vertical)
                        .lineLimit(3...5)
                        .font(.callout.monospaced())
                        .autocorrectionDisabled()
                    Text("In the dApp choose Octez Connect (or Beacon), then “Pair wallet on another device” and copy the code. Signet connects over the Tezos relay; the dApp can be in any browser.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    HStack {
                        if isPairing { ProgressView().controlSize(.small) }
                        Spacer()
                        Button("Pair") { pair() }
                            .buttonStyle(.borderedProminent)
                            .disabled(code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isPairing || !canPair)
                    }
                }

                Section("Connected dApps") {
                    if dapps.permissions.isEmpty {
                        Text("None yet.").foregroundStyle(.secondary)
                    } else {
                        ForEach(dapps.permissions) { permission in
                            HStack(spacing: 10) {
                                DAppIconView(url: permission.appIcon, size: 28)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(permission.appName)
                                    Text("\(walletName(for: permission.address)) · \(permission.networkType) · \(permission.scopes.joined(separator: ", "))")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button("Disconnect") { Task { await dapps.disconnect(permission) } }
                            }
                        }
                        Button("Disconnect all", role: .destructive) { Task { await dapps.disconnectAll() } }
                    }
                }
            }
            .formStyle(.grouped)
            .frame(height: isSwapFlow ? 260 : 360)

            if let message {
                Text(message).font(.callout).foregroundStyle(isError ? .red : .green)
            }

            HStack {
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 520)
        .task { if !AppRuntime.isDemo { await dapps.reloadPermissions() } }
        .onAppear { takePendingCode() }
        .onChange(of: model.pendingPairingCode) { takePendingCode() }
        // Only one sheet can be up at a time: step aside as soon as the dApp's first request arrives,
        // so the approval sheet can show without the user having to close this one.
        .onChange(of: dapps.current?.id) { if dapps.current != nil { dismiss() } }
    }

    private var canPair: Bool {
        !AppRuntime.isDemo && (!isSwapFlow || (model.network.isMainnet && model.selectedWallet?.keyKind.canSign == true))
    }

    private var swapIntroduction: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: "arrow.up.arrow.down")
                    .font(.title2).foregroundStyle(Theme.violet)
                    .frame(width: 48, height: 48)
                    .background(Theme.violet.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
                VStack(alignment: .leading, spacing: 3) {
                    Text("Swap with 3Route").font(.title3.weight(.semibold))
                    Text("Tezos assets · Mainnet").font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
            }
            Text("Choose the assets and amount on 3Route, review the live quote, then approve the transaction in Signet.")
                .font(.callout).foregroundStyle(.secondary)
            Button {
                if !NSWorkspace.shared.open(ThreeRoute.url) {
                    isError = true
                    message = "Could not open 3Route. Visit https://3route.io/swap in your browser."
                }
            } label: {
                HStack { Text("Open 3Route"); Spacer(); Image(systemName: "arrow.up.right") }
                    .padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
            Text("To connect: Connect Wallet → Show more → Show QR code → octez.connect → Copy to clipboard. Paste the pairing code below.")
                .font(.caption).foregroundStyle(.secondary)
            if AppRuntime.isDemo {
                Label("Sample accounts cannot pair or sign. You can explore 3Route in your browser.", systemImage: "info.circle")
                    .font(.caption).foregroundStyle(.secondary)
            } else if !canPair {
                Label("Select a signing account on Mainnet to connect with 3Route.", systemImage: "info.circle")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(18)
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 20))
    }

    private func walletName(for address: String) -> String {
        model.wallets.first { $0.address.value == address }?.alias ?? Address(address).shortened()
    }

    /// A code that arrived through a signet:// link is pasted and paired automatically.
    private func takePendingCode() {
        guard let pending = model.pendingPairingCode else { return }
        model.pendingPairingCode = nil
        code = pending
        pair()
    }

    private func pair() {
        guard canPair else { return }
        isPairing = true
        message = nil
        Task {
            defer { isPairing = false }
            do {
                let name = try await dapps.pair(code: code)
                isError = false
                message = "Paired with \(name). It will now ask for permission; approve it in the next window."
                code = ""
            } catch {
                isError = true
                message = error.localizedDescription
            }
        }
    }
}

/// dApp icon or a generic placeholder.
struct DAppIconView: View {
    let url: URL?
    var size: CGFloat = 44

    var body: some View {
        Group {
            if let url {
                RemoteImage(urls: [url]) { image in
                    Image(nsImage: image).resizable().scaledToFit()
                } placeholder: { _ in placeholder }
            } else {
                placeholder
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.22))
    }

    private var placeholder: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.22).fill(.quaternary)
            Image(systemName: "globe").font(.system(size: size * 0.5)).foregroundStyle(.secondary)
        }
    }
}

/// A fixed provider entry point; account addresses and secrets are never included in this URL.
enum ThreeRoute {
    static let url = URL(string: "https://3route.io/swap")!
}
