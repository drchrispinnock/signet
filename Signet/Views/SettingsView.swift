import AppKit
import SwiftUI

/// App settings: which node to talk to, where the wallet files live, and how they are backed up.
struct SettingsView: View {
    @Bindable var model: WalletViewModel

    var body: some View {
        Form {
            appearanceSection
            nodeSection
            if let directory = model.walletDirectory {
                walletDirectorySection(directory)
            }
            if let backupDirectory = model.backupDirectory {
                backupSection(backupDirectory)
            }
        }
        .formStyle(.grouped)
        .frame(width: 480, height: 780)
        .navigationTitle("Settings")
        .appliesStoredAppearance()
    }

    // MARK: Sections

    @AppStorage(Appearance.key) private var appearance: Appearance = .system

    private var appearanceSection: some View {
        Section {
            Picker("Appearance", selection: $appearance) {
                ForEach(Appearance.allCases) { option in
                    Text(option.title).tag(option)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    private var nodeSection: some View {
        Section {
            Picker("Node", selection: $model.network) {
                ForEach(Network.all) { network in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(network.name)
                        Text(network.rpcURL.absoluteString)
                            .font(.callout.monospaced())
                            .foregroundStyle(.secondary)
                    }
                    .tag(network)
                }
            }
            .pickerStyle(.radioGroup)
        } footer: {
            Text("Balances and names are fetched from the selected network. More networks will be added later.")
                .font(.callout)
                .foregroundStyle(.secondary)
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
    SettingsView(model: .preview())
}
