import SwiftUI

/// Connect Remote Signer: an account whose key octez-signer holds. The user picks how the
/// signer listens (HTTP, HTTPS or TCP, with octez-signer's default ports), where, and which of
/// its keys; Signet asks the signer for that key's public key, derives the address from it and
/// adds the account only when the two agree.
struct ConnectRemoteSignerSheet: View {
    @Bindable var model: WalletViewModel
    @Environment(\.dismiss) private var dismiss

    static let transports: [RemoteSignerLocator.Transport] = [.http, .https, .tcp]

    @State private var transport: RemoteSignerLocator.Transport = .tcp
    @State private var host = "localhost"
    @State private var portText = String(RemoteSignerLocator.Transport.tcp.defaultPort!)
    @State private var addressText = ""
    @State private var alias = ""
    @State private var listedKeys: [Address]?
    @State private var isListing = false
    @State private var listNote: String?
    @State private var check: WalletViewModel.RemoteSignerCheck?
    @State private var checkError: String?
    @State private var isChecking = false
    @State private var errorMessage: String?
    @State private var isAdding = false

    private var trimmedHost: String { host.trimmingCharacters(in: .whitespaces) }
    private var port: Int? { Int(portText.trimmingCharacters(in: .whitespaces)).flatMap { (1...65535).contains($0) ? $0 : nil } }
    private var address: Address { Address(addressText.trimmingCharacters(in: .whitespacesAndNewlines)) }

    /// Why the host cannot be used this way, if it cannot.
    private var hostProblem: String? {
        guard !trimmedHost.isEmpty else { return nil }
        if trimmedHost.contains("/") || trimmedHost.contains("@") || trimmedHost.contains(" ") { return "Enter only the host name or IP address." }
        if transport == .http, !EndpointPolicy.isLocalOrPrivateHost(trimmedHost) {
            return "Plain HTTP is only for a signer on this Mac or your local network. Use HTTPS or TCP for one elsewhere."
        }
        return nil
    }

    /// The signer as entered, for any key; `nil` until host and port make sense.
    private var endpoint: RemoteSignerLocator? {
        guard !trimmedHost.isEmpty, hostProblem == nil, let port else { return nil }
        return RemoteSignerLocator(transport: transport, host: trimmedHost, port: port, address: address)
    }

    private var signer: RemoteSignerLocator? { address.isImplicitAccount ? endpoint : nil }
    private var existing: Wallet? { model.wallets.first { $0.address == address } }
    private var aliasTaken: Bool { model.wallets.contains { $0.alias == alias.trimmingCharacters(in: .whitespaces) } }
    private var canAdd: Bool {
        guard let signer, let check, check.signer == signer, existing == nil, !isAdding else { return false }
        return !alias.trimmingCharacters(in: .whitespaces).isEmpty && !aliasTaken
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Connect Remote Signer", systemImage: "server.rack")
                .font(.title2.weight(.semibold))

            Form {
                Section {
                    Picker("Connection", selection: $transport) {
                        ForEach(Self.transports) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    TextField("Host", text: $host, prompt: Text("localhost"))
                    TextField("Port", text: $portText, prompt: Text(transport.defaultPort.map(String.init) ?? ""))
                    if let hostProblem {
                        Label(hostProblem, systemImage: "exclamationmark.triangle").font(.callout).foregroundStyle(.orange)
                    } else if port == nil, !portText.isEmpty {
                        Label("The port is a number from 1 to 65535.", systemImage: "exclamationmark.triangle").font(.callout).foregroundStyle(.orange)
                    }
                } footer: {
                    Text("octez-signer listens on port \(RemoteSignerLocator.Transport.http.defaultPort!) for HTTP, \(RemoteSignerLocator.Transport.https.defaultPort!) for HTTPS and \(RemoteSignerLocator.Transport.tcp.defaultPort!) for TCP unless started with --port.")
                        .font(.caption).foregroundStyle(.secondary)
                }

                Section {
                    HStack {
                        TextField("Key", text: $addressText, prompt: Text("tz1…, tz2…, tz3… or tz4…"))
                            .font(.body.monospaced())
                        if let listedKeys, !listedKeys.isEmpty {
                            Menu("Keys") {
                                ForEach(listedKeys, id: \.self) { key in
                                    Button(key.value) { addressText = key.value }
                                }
                            }
                            .fixedSize()
                        } else {
                            Button("List Keys", action: listKeys)
                                .disabled(endpoint == nil || isListing)
                        }
                    }
                    if let listNote {
                        Text(listNote).font(.caption).foregroundStyle(.secondary)
                    }
                    if !addressText.isEmpty, !address.isImplicitAccount {
                        Label("That is not a tz1 to tz5 address.", systemImage: "exclamationmark.triangle").font(.callout).foregroundStyle(.orange)
                    }
                    checkRow
                    TextField("Name", text: $alias, prompt: Text("e.g. Baker"))
                        .onSubmit { if canAdd { add() } }
                    if aliasTaken {
                        Text("An account or address is already called that.").font(.caption).foregroundStyle(.red)
                    }
                }
            }
            .formStyle(.grouped)

            if transport == .tcp, let endpoint, !EndpointPolicy.isLocalOrPrivateHost(endpoint.host) {
                Label("TCP is not encrypted. What Signet sends to sign is public anyway and every signature is checked against the key, but a signer reachable from the internet without authentication will sign for anyone who asks.", systemImage: "lock.open")
                    .font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text("Signet keeps only the address and public key. Every operation is sent to the signer to sign, and its signature is checked against the account's key before anything is sent to the network. octez-client can use the account too.")
                .font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle")
                    .font(.callout).foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Add Account", action: add)
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(!canAdd)
            }
        }
        .padding(20)
        .frame(width: 560)
        .onChange(of: transport) { old, new in
            // Keep a port the user typed; follow the defaults otherwise.
            if portText.isEmpty || Int(portText) == old.defaultPort { portText = new.defaultPort.map(String.init) ?? "" }
            listedKeys = nil
            listNote = nil
        }
        .onChange(of: host) { listedKeys = nil; listNote = nil }
        .onChange(of: portText) { listedKeys = nil; listNote = nil }
        .task(id: signer) { await checkSigner() }
    }

    @ViewBuilder private var checkRow: some View {
        if let existing, address.isImplicitAccount {
            Label("Already in your list as “\(existing.alias)”.", systemImage: "checkmark.seal")
                .font(.callout).foregroundStyle(.secondary)
        } else if isChecking {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Asking the signer…").font(.callout).foregroundStyle(.secondary)
            }
        } else if let check, check.signer == signer {
            HStack(spacing: 10) {
                AccountAvatarView(address: check.signer.address, network: model.network, size: 32)
                VStack(alignment: .leading, spacing: 2) {
                    Text(check.signer.address.value).font(.callout.monospaced()).textSelection(.enabled)
                    Label("The signer holds this key (\(check.signer.address.scheme?.displayName ?? "")).", systemImage: "checkmark.circle")
                        .font(.caption).foregroundStyle(.green)
                }
            }
            if !check.acceptsUnauthenticated {
                Label("This signer requires authenticated requests (--require-authentication), which Signet cannot make yet, so it will refuse to sign. Restart it without that option or put it behind a tunnel only you can reach.", systemImage: "exclamationmark.triangle")
                    .font(.callout).foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } else if let checkError {
            Label(checkError, systemImage: "xmark.octagon")
                .font(.callout).foregroundStyle(.red)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func checkSigner() async {
        check = nil
        checkError = nil
        guard let signer, existing == nil else { return }
        // Wait for typing to settle before asking.
        try? await Task.sleep(for: .milliseconds(500))
        guard !Task.isCancelled else { return }
        isChecking = true
        defer { isChecking = false }
        do {
            let result = try await model.checkRemoteSigner(signer)
            guard !Task.isCancelled else { return }
            check = result
            if alias.isEmpty { alias = "Remote \(signer.address.shortened(prefix: 6, suffix: 4))" }
        } catch is CancellationError {
        } catch {
            guard !Task.isCancelled else { return }
            checkError = error.localizedDescription
        }
    }

    private func listKeys() {
        guard let endpoint else { return }
        isListing = true
        listNote = nil
        Task {
            defer { isListing = false }
            do {
                let keys = try await model.remoteSignerKeys(at: endpoint)
                listedKeys = keys
                if keys.isEmpty { listNote = "The signer lists no keys." }
                else if keys.count == 1, addressText.isEmpty { addressText = keys[0].value }
            } catch RemoteSignerError.notFound, RemoteSignerError.closed {
                listNote = "This signer does not list its keys (octez-signer 21 and earlier). Enter the key's address; `octez-signer list known addresses` shows it."
            } catch {
                listNote = error.localizedDescription
            }
        }
    }

    private func add() {
        guard canAdd, let signer else { return }
        isAdding = true
        errorMessage = nil
        Task {
            defer { isAdding = false }
            do {
                try await model.connectRemoteSigner(alias: alias, signer: signer)
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

#Preview {
    ConnectRemoteSignerSheet(model: .preview())
}
