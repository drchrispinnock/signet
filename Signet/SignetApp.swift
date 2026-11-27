import SwiftUI

@main
struct SignetApp: App {
    /// True when this process is the host for `SignetTests`.
    /// The Getting Started chapter of the Signet book online, for when the bundled copy is missing.
    static let gettingStartedURL = URL(string: "https://leanpub.com/read/tezossignet/ID110-starting_1_Getting")!
    /// Signet's website, opened from the Help menu.
    static let websiteURL = URL(string: "https://signetwallet.org")!
    static var isTestHost: Bool { ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil }

    init() {
        // Session-only keys live in memory (`SessionKeyStore`); a core dump would write that
        // memory to disk. macOS crash reports carry no heap, and this makes sure no core file is
        // ever produced either.
        var none = rlimit(rlim_cur: 0, rlim_max: 0)
        setrlimit(RLIMIT_CORE, &none)
    }

    /// The app's model. Under the test host it is built on in-memory stores only (S24): no wallet
    /// directory is read, no backup is scheduled, no dApp storage or client is touched, so tests
    /// never see or change the developer's real wallet state. Tests construct their own models.
    @MainActor
    static func makeModel(isTestHost: Bool = isTestHost) -> WalletViewModel {
        if isTestHost {
            return WalletViewModel(wallets: [], chain: MockChainService(), multisig: MockMultisigService(), walletStore: InMemoryWalletStore(), nodeProbe: { _ in throw URLError(.notConnectedToInternet) })
        }
        TaquitoBridge.shared.configureLog(at: TaquitoBridge.logFileURL)
        TaquitoBridge.shared.operationJournal = OperationJournal(directory: TezosClientStore.defaultDirectory)
        return WalletViewModel(
            chainFactory: { network in TaquitoChainService(network: network) },
            keyGenerator: KeyGenerator(),
            ledger: BridgeLedgerService(),
            keyImporter: BridgeKeyImporter(),
            multisig: BridgeMultisigService(),
            importSource: TezosClientStore.octezClientDirectory,
            directorySettings: WalletDirectorySettings(),
            storeFactory: { directory in
                (wallets: TezosClientStore(directory: directory), state: FileAppStateStore(directory: directory))
            },
            backupSettings: BackupSettings(),
            dappStorageFactory: { directory in OctezConnectStorage(directory: directory) },
            dappDiagnostics: DeveloperSettings.dappDiagnostics,
            startDApps: true,
            shieldedStoreFactory: { directory, chain -> any ShieldedWalletStore in
                guard let directory else { return InMemoryShieldedWalletStore() }
                return FileShieldedWalletStore(directory: directory, chain: chain)
            }
        )
    }

    @State private var model = SignetApp.makeModel()
    // Sparkle: checks the GitHub release appcast daily and on "Check for Updates…". Not started
    // under the test host, which would otherwise reach the network and may put up a dialog.
    // Shows the Scan QR code items while a camera is attached. Not under the test host.
    @State private var cameraWatcher: CameraWatcher?
    @State private var updater = UpdaterService(starting: !SignetApp.isTestHost)
    // Tezos Domains expiry reminders (Settings > Notifications). Not under the test host.
    @AppStorage(DomainReminderSettings.key) private var domainRemindersOn = true

    /// Looks up the names the user's accounts own, lists those due soon on the dashboard and
    /// shows any reminder now due.
    @MainActor private func checkDomainReminders() async {
        let service = DomainReminderService.shared
        guard domainRemindersOn else { model.expiringDomains = []; return }
        guard let names = await model.ownedDomainNamesForReminders() else { return }
        let now = Date()
        model.expiringDomains = names.filter { DomainReminders.isDueSoon($0.expires, now: now) }.sorted { $0.expires < $1.expires }
        await service.deliverDue(names, now: now)
    }

    var body: some Scene {
        // A single window: a WindowGroup would open a second one when a signet:// link arrives.
        Window("Signet", id: "main") {
            WalletHomeView(model: model)
                // signet://?type=tzip10&data=<pairing code>: what a dApp's wallet list opens for desktop wallets.
                .onOpenURL { url in model.handleIncomingURL(url) }
                .task {
                    guard !Self.isTestHost, cameraWatcher == nil else { return }
                    cameraWatcher = CameraWatcher { [model] hasCamera in model.hasCamera = hasCamera }
                }
                // Domain expiry reminders: at launch, then once a day while Signet runs. What is due
                // goes up as an alert in the app; nothing is scheduled (as on Windows and GTK).
                .task {
                    guard !Self.isTestHost else { return }
                    while !Task.isCancelled {
                        await checkDomainReminders()
                        try? await Task.sleep(for: .seconds(24 * 3600))
                    }
                }
                .onChange(of: domainRemindersOn) { Task { await checkDomainReminders() } }
                // Remembered passwords go when the Mac sleeps, its screens sleep or it locks.
                .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.willSleepNotification)) { _ in model.forgetRememberedPassphrases() }
                .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.screensDidSleepNotification)) { _ in model.forgetRememberedPassphrases() }
                .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.sessionDidResignActiveNotification)) { _ in model.forgetRememberedPassphrases() }
                .onReceive(DistributedNotificationCenter.default().publisher(for: Notification.Name("com.apple.screenIsLocked"))) { _ in model.forgetRememberedPassphrases() }
        }
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Check for Updates…") { updater.checkForUpdates() }
                    .disabled(!updater.canCheckForUpdates)
            }
            CommandGroup(replacing: .newItem) {
                Button("Create Backup") { Task { await model.backUp(force: true) } }
                    .disabled(model.backupDirectory == nil)
            }
            // Help: the book's Getting Started chapter in a window of its own, and the website
            // (replacing the default item, which only says no help is available).
            CommandGroup(replacing: .help) {
                HelpMenuItems()
            }
            // The same actions as the burger menu, in the menu bar.
            CommandMenu("Operations") {
                OperationsMenuItems(model: model)
            }
        }

        Window("Getting Started", id: GettingStartedView.windowID) {
            GettingStartedView()
                .appliesStoredAppearance()
        }
        .defaultSize(width: 860, height: 780)

        Settings {
            SettingsView(model: model, updater: updater)
        }
    }
}
