import AppKit
import SwiftUI

/// App settings: appearance, where the wallet files live, how they are backed up, updates and
/// developer switches. Nodes are edited in `NetworksSheet`; the on-ramp is picked in `BuySheet`.
struct SettingsView: View {
    @Bindable var model: WalletViewModel
    @Bindable var updater: UpdaterService

    var body: some View {
        Form {
            appearanceSection
            if let directory = model.walletDirectory {
                walletDirectorySection(directory)
            }
            if let backupDirectory = model.backupDirectory {
                backupSection(backupDirectory)
            }
            updatesSection
            developerSection
        }
        .formStyle(.grouped)
        .frame(width: 480, height: 720)
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

    @AppStorage(DeveloperSettings.dappDiagnosticsKey) private var dappDiagnosticsArmed = false

    private var developerSection: some View {
        Section {
            Toggle("Verbose dApp log on the next launch", isOn: $dappDiagnosticsArmed)
            if model.dapps.diagnostics {
                Text("Verbose dApp logging is on for this run; it switches itself off at the next launch.").font(.callout).foregroundStyle(.orange)
            }
        } header: {
            Text("Developer")
        } footer: {
            Text("The bridge log (~/Library/Logs/Signet/bridge.log) never contains keys, signatures or message contents. The verbose dApp log adds the relay SDK's own debugging output, which includes decrypted dApp traffic; it is armed for one launch only.")
                .font(.callout).foregroundStyle(.secondary)
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
