import SwiftUI

/// Pair with a dApp by pasting its Octez Connect code, and manage existing connections.
struct ConnectDAppSheet: View {
    @Bindable var model: WalletViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var code = ""
    @State private var isPairing = false
    @State private var message: String?
    @State private var isError = false

    private var dapps: DAppConnectionManager { model.dapps }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Connect to a dApp")
                    .font(.title2.weight(.semibold))
                Spacer()
                HStack(spacing: 6) {
                    Circle().fill(dapps.isStarted ? .green : (dapps.lastError == nil ? .gray : .red)).frame(width: 8, height: 8)
                    Text(dapps.isStarted ? "Octez Connect running" : (dapps.lastError == nil ? "Starting…" : "Octez Connect failed"))
                        .font(.caption).foregroundStyle(.secondary)
                }
                .help(dapps.lastError ?? "Connected to the Tezos relay")
            }
            if let error = dapps.lastError, !dapps.isStarted {
                Text(error).font(.callout).foregroundStyle(.red)
                Button("Try again") { Task { await dapps.restart() } }
            }

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
                            .disabled(code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isPairing)
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
            .frame(height: 360)

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
        .task { await dapps.reloadPermissions() }
    }

    private func walletName(for address: String) -> String {
        model.wallets.first { $0.address.value == address }?.alias ?? Address(address).shortened()
    }

    private func pair() {
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
