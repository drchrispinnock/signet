import AppKit
import SwiftUI

/// App settings: which node to talk to, where the wallet files live, and how they are backed up.
struct SettingsView: View {
    @Bindable var model: WalletViewModel
    @Bindable var updater: UpdaterService
    @State private var editingNetworkName = ""

    var body: some View {
        Form {
            appearanceSection
            networkSection
            nodeSection
            buySection
            if let directory = model.walletDirectory {
                walletDirectorySection(directory)
            }
            if let backupDirectory = model.backupDirectory {
                backupSection(backupDirectory)
            }
            updatesSection
        }
        .formStyle(.grouped)
        .frame(width: 480, height: 900)
        .navigationTitle("Settings")
        .appliesStoredAppearance()
    }

    // MARK: Sections

    @AppStorage(Appearance.key) private var appearance: Appearance = .system
    @AppStorage(Disclaimer.key) private var showsDisclaimer = true

    private var appearanceSection: some View {
        Section {
            Picker("Appearance", selection: $appearance) {
                ForEach(Appearance.allCases) { option in
                    Text(option.title).tag(option)
                }
            }
            .pickerStyle(.segmented)
            Toggle("Show the disclaimer at launch", isOn: $showsDisclaimer)
        }
    }

    private var updatesSection: some View {
        Section {
            Toggle("Check for updates automatically", isOn: $updater.automaticallyChecksForUpdates)
            Toggle("Download and install them automatically", isOn: $updater.automaticallyDownloadsUpdates)
                .disabled(!updater.automaticallyChecksForUpdates)
            LabeledContent("Last checked") {
                HStack {
                    Text(updater.lastUpdateCheckDate.map { $0.formatted(date: .abbreviated, time: .shortened) } ?? "Never")
                        .foregroundStyle(.secondary)
                    Button("Check Now") { updater.checkForUpdates() }
                        .disabled(!updater.canCheckForUpdates)
                }
            }
        } header: {
            Text("Updates")
        } footer: {
            Text("New releases are fetched from GitHub and verified against the key built into the app before they are installed. Only Signet itself is replaced; your accounts stay in the wallet folder.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    @AppStorage(BuyProvider.key) private var buyProviderID = BuyProvider.default.rawValue

    private var buySection: some View {
        Section {
            Picker("Buy tez with", selection: $buyProviderID) {
                ForEach(BuyProvider.allCases) { Text($0.title).tag($0.rawValue) }
            }
            Text((BuyProvider(rawValue: buyProviderID) ?? .default).summary)
                .font(.callout).foregroundStyle(.secondary)
        }
    }

    private var networkSection: some View {
        Section("Connection") {
            Picker("Active network", selection: Binding(
                get: { model.network.name },
                set: { name in
                    guard let network = Network.named(name) else { return }
                    model.switchNetwork(to: network)
                }
            )) {
                ForEach(Network.all) { network in
                    Text(network.name).tag(network.name)
                }
            }
            NodeStatusBar(monitor: model.nodeMonitor)
        }
    }

    /// The network is a dropdown; the node beneath it is free text so any RPC endpoint can
    /// replace the default for that network. The text is applied on Return or with Apply.
    @State private var nodeText = ""
    @State private var nodeError: String?

    private var nodeSection: some View {
        Section {
            Picker("Configure network", selection: $editingNetworkName) {
                ForEach(Network.all) { network in
                    Text(network.name + (network.name == model.network.name ? "  (in use)" : "")).tag(network.name)
                }
            }
            LabeledContent("Node") {
                VStack(alignment: .trailing, spacing: 8) {
                    TextField("Node", text: $nodeText)
                        .font(.callout.monospaced())
                        .textFieldStyle(.roundedBorder)
                        .autocorrectionDisabled()
                        .onSubmit(applyNode)
                        .frame(minWidth: 280)
                    if let nodeError {
                        Text(nodeError)
                            .font(.callout)
                            .foregroundStyle(.red)
                    }
                    HStack {
                        Button("Use Default") {
                            if let base = editingNetwork { model.useDefaultNode(for: base); syncNodeText() }
                        }
                        .disabled(editingNetwork.map { model.nodeURL(for: $0) == $0.defaultRPCURL } ?? true)
                        Button("Apply", action: applyNode)
                            .disabled(!nodeIsDirty)
                    }
                }
            }
        } footer: {
            Text(nodeFooter)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .onAppear { editingNetworkName = model.network.name; syncNodeText() }
        .onChange(of: editingNetworkName) { syncNodeText() }
        .onChange(of: model.network) { if editingNetworkName == model.network.name { syncNodeText() } }
    }

    private var editingNetwork: Network? { Network.named(editingNetworkName) }

    private var nodeIsDirty: Bool {
        guard let base = editingNetwork else { return false }
        return Network.nodeURL(from: nodeText) != model.nodeURL(for: base)
    }

    private var nodeFooter: String {
        guard let base = editingNetwork else { return "" }
        var text = "The node Signet uses for \(base.name). Each network keeps its own; choose the active network under Connection above."
        if base.chain == "custom" {
            text += " Custom is yours to point anywhere, for example a node you run yourself."
        } else {
            text += " The default is \(base.defaultRPCURL.absoluteString)."
        }
        if base.chain == "weeklynet" {
            text += " Weeklynet restarts every Wednesday and its address carries that date, so the default follows the calendar."
        }
        return text
    }

    private func syncNodeText() {
        if let base = editingNetwork {
            nodeText = model.nodeURL(for: base).nodeDisplayTextStandalone
        }
        nodeError = nil
    }

    private func applyNode() {
        guard let base = editingNetwork else { return }
        if model.setNode(nodeText, for: base) {
            nodeError = nil
            syncNodeText()
        } else {
            nodeError = "Enter a host name such as rpc.tzbeta.net."
        }
    }

    private func walletDirectorySection(_ directory: URL) -> some View {
        Section {
            LabeledContent("Wallet directory") {
                VStack(alignment: .trailing, spacing: 8) {
                    pathLabel(directory)
                    HStack {
                        Button("Show in Finder") { reveal(directory) }
                        Button("Use Default") {
                            if let fallback = model.defaultWalletDirectory { model.changeWalletDirectory(to: fallback) }
                        }
                        .disabled(model.isUsingDefaultWalletDirectory)
                        Button("Choose…") {
                            chooseFolder(title: "Choose Wallet Directory",
                                         message: "Pick the folder that holds (or will hold) the wallet files.",
                                         from: directory) { model.changeWalletDirectory(to: $0) }
                        }
                    }
                }
            }
        } footer: {
            Text("Wallet files are kept here in octez-client's format (public_key_hashs, public_keys, secret_keys). Choosing another directory switches to the wallets in it; nothing is moved or copied.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private func backupSection(_ backupDirectory: URL) -> some View {
        Section {
            LabeledContent("Backup folder") {
                VStack(alignment: .trailing, spacing: 8) {
                    pathLabel(backupDirectory)
                    HStack {
                        Button("Show in Finder") { reveal(backupDirectory) }
                        Button("Use Default") {
                            if let fallback = model.defaultBackupDirectory { model.setBackupDirectory(fallback) }
                        }
                        .disabled(model.isUsingDefaultBackupDirectory)
                        Button("Choose…") {
                            chooseFolder(title: "Choose Backup Folder",
                                         message: "Generations of the wallet files will be kept in this folder.",
                                         from: backupDirectory) { model.setBackupDirectory($0) }
                        }
                    }
                }
            }
            Stepper(value: Binding(get: { model.backupGenerations }, set: { model.setBackupGenerations($0) }),
                    in: BackupSettings.generationRange) {
                LabeledContent("Generations to keep", value: "\(model.backupGenerations)")
            }
            LabeledContent("Last backup") {
                HStack {
                    Text(lastBackupDescription)
                        .foregroundStyle(.secondary)
                    Button("Back Up Now") { Task { await model.backUp(force: true) } }
                }
            }
        } footer: {
            Text("The wallet files are copied here on every launch and after any key is created or renamed. Automatic copies are skipped when nothing has changed; Back Up Now always writes one. Only the newest generations are kept.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: Helpers

    private var lastBackupDescription: String {
        if let error = model.lastBackupError { return "Failed: \(error)" }
        guard let last = model.lastBackup else { return "Not yet" }
        let when = last.date.formatted(date: .abbreviated, time: .shortened)
        switch last.outcome {
        case .created: return "Saved \(when)"
        case .unchanged: return "Up to date (\(when))"
        case .nothingToBackUp: return "No wallet files yet"
        }
    }

    private func pathLabel(_ url: URL) -> some View {
        Text((url.path as NSString).abbreviatingWithTildeInPath)
            .font(.callout.monospaced())
            .textSelection(.enabled)
            .multilineTextAlignment(.trailing)
            .help(url.path)
    }

    private func reveal(_ url: URL) {
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    private func chooseFolder(title: String, message: String, from current: URL, onChoose: (URL) -> Void) {
        let panel = NSOpenPanel()
        panel.title = title
        panel.message = message
        panel.prompt = "Use This Folder"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.showsHiddenFiles = true
        panel.directoryURL = FileManager.default.fileExists(atPath: current.path) ? current : current.deletingLastPathComponent()
        if panel.runModal() == .OK, let url = panel.url {
            onChoose(url)
        }
    }
}

#Preview {
    SettingsView(model: .preview(), updater: UpdaterService(starting: false))
}
