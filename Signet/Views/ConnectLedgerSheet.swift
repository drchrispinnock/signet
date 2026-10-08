import SwiftUI

/// Adds a key that lives on a Ledger: finds the device, checks the Tezos app is open, derives
/// the address for the chosen curve and account, and has the user approve it on the device.
struct ConnectLedgerSheet: View {
    @Bindable var model: WalletViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var devices: [LedgerDevice] = []
    @State private var appInfo: LedgerAppInfo?
    @State private var appProblem: String?
    @State private var alias: String
    @State private var curve: LedgerCurve = .ed25519
    @State private var account = 0
    @State private var preview: Address?
    @State private var previewTask: Task<Void, Never>?
    @State private var errorMessage: String?
    @State private var isAdding = false
    @FocusState private var aliasFocused: Bool

    init(model: WalletViewModel) {
        self.model = model
        _alias = State(initialValue: model.suggestedAlias(base: "Ledger"))
    }

    private var device: LedgerDevice? { devices.first }
    private var ready: Bool { device != nil && appInfo?.isWallet == true }
    private var trimmedAlias: String { alias.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var key: LedgerKey { LedgerKey(rootID: "", curve: curve, account: account) }
    private var existing: Wallet? { preview.flatMap { address in model.wallets.first { $0.address == address } } }
    private var canAdd: Bool { ready && !trimmedAlias.isEmpty && !isAdding && existing == nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Connect Ledger")
                .font(.title2.weight(.semibold))

            Form {
                LabeledContent("Device") { deviceStatus }

                TextField("Name", text: $alias, prompt: Text("Ledger"))
                    .focused($aliasFocused)

                Picker("Key type", selection: $curve) {
                    ForEach(LedgerCurve.allCases) { c in Text(c.displayName).tag(c) }
                }
                Stepper("Account \(account)", value: $account, in: 0...100)
                LabeledContent("Path", value: key.fullPath)
                    .font(.callout.monospaced())
                LabeledContent("Address") {
                    if let preview {
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(preview.value).font(.callout.monospaced()).textSelection(.enabled)
                            if let existing {
                                Label("Already in your list as “\(existing.alias)”", systemImage: "exclamationmark.triangle")
                                    .font(.caption).foregroundStyle(.orange)
                            }
                        }
                    } else if ready {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("—").foregroundStyle(.secondary)
                    }
                }
                Text("Press Add and the Ledger will show this address; approve it there to finish. The key stays on the device, which asks you to approve every operation. The entry is written to ~/.signet as a ledger:// alias octez-client can use too.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .formStyle(.grouped)
            .scrollDisabled(true)

            if let errorMessage {
                Text(errorMessage).font(.callout).foregroundStyle(.red)
            }

            HStack {
                if isAdding { LedgerPromptLabel(text: "Approve the address on your Ledger…") }
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .disabled(isAdding)
                Button("Add", action: add)
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(!canAdd)
            }
        }
        .padding(20)
        .frame(width: 520)
        .onAppear { aliasFocused = true }
        .task { await pollDevices() }
        .onChange(of: curve) { refreshPreview() }
        .onChange(of: account) { refreshPreview() }
    }

    @ViewBuilder
    private var deviceStatus: some View {
        HStack(spacing: 8) {
            if let device {
                Circle().fill(ready ? Color.green : Color.orange).frame(width: 9, height: 9)
                VStack(alignment: .trailing, spacing: 2) {
                    Text(device.model)
                    if let appInfo {
                        Text(appInfo.isWallet ? "Tezos Wallet \(appInfo.version)" : "Tezos Baking app \(appInfo.version): open the Tezos Wallet app instead")
                            .font(.caption).foregroundStyle(appInfo.isWallet ? AnyShapeStyle(.secondary) : AnyShapeStyle(.orange))
                    } else if let appProblem {
                        Text(appProblem).font(.caption).foregroundStyle(.orange)
                    } else {
                        Text("Checking…").font(.caption).foregroundStyle(.secondary)
                    }
                }
            } else {
                Circle().fill(Color.red).frame(width: 9, height: 9)
                Text("No Ledger found. Plug it in, unlock it and open the Tezos app.")
                    .foregroundStyle(.secondary)
            }
        }
        .multilineTextAlignment(.trailing)
    }

    /// Watches for the device and the app while the sheet is up.
    private func pollDevices() async {
        while !Task.isCancelled {
            let found = await model.ledger.devices()
            let changed = found != devices
            devices = found
            if let device {
                if changed || appInfo == nil {
                    do {
                        let info = try await model.ledger.appInfo(deviceID: device.id)
                        let becameReady = info != appInfo
                        appInfo = info
                        appProblem = nil
                        if becameReady { refreshPreview() }
                    } catch {
                        appInfo = nil
                        appProblem = (error as? ChainError)?.localizedDescription ?? "Open the Tezos app on the Ledger."
                        preview = nil
                    }
                }
            } else {
                appInfo = nil
                appProblem = nil
                preview = nil
            }
            try? await Task.sleep(for: .seconds(1.5))
        }
    }

    private func refreshPreview() {
        previewTask?.cancel()
        preview = nil
        guard let device, ready, !isAdding else { return }
        let key = key
        previewTask = Task {
            let result = try? await model.ledger.address(deviceID: device.id, key: key, prompt: false)
            guard !Task.isCancelled else { return }
            preview = result?.address
        }
    }

    private func add() {
        guard let device else { return }
        errorMessage = nil
        isAdding = true
        Task {
            defer { isAdding = false }
            do {
                try await model.connectLedger(alias: trimmedAlias, deviceID: device.id, curve: curve, account: account)
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

/// "Confirm on your Ledger" with a spinner, shown wherever an operation waits on the device.
struct LedgerPromptLabel: View {
    var text = "Confirm on your Ledger…"

    var body: some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.small)
            Label(text, systemImage: "lock.rectangle.stack").font(.callout).foregroundStyle(.secondary)
        }
    }
}

#Preview {
    ConnectLedgerSheet(model: WalletViewModel(wallets: WalletViewModel.sampleWallets, chain: MockChainService(), ledger: MockLedgerService(connected: [MockLedgerService.sampleDevice])))
}
