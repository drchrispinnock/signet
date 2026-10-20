import SwiftUI

/// Left side of the header: alias (a dropdown that switches wallets), shortened address with a
/// copy button, then any Tezos Domains names.
struct WalletIdentityView: View {
    @Bindable var model: WalletViewModel
    let wallet: Wallet
    @State private var copied = false

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            AccountAvatarView(address: wallet.address, network: model.network, size: 48)
            identity
        }
    }

    private var identity: some View {
        VStack(alignment: .leading, spacing: 4) {
            // The tags sit beside the menu, not in its label: AppKit draws that label and drops
            // backgrounds and overlays.
            HStack(spacing: 8) {
                walletPicker
                if wallet.address.isContract { contractTag } else if wallet.keyKind == .none { watchOnlyTag }
                if wallet.keyKind == .ledger { ledgerTag }
                if wallet.isSessionOnly { sessionTag }
            }
            HStack(spacing: 6) {
                Text(wallet.address.shortened())
                    .font(.body.monospaced())
                    .foregroundStyle(.secondary)
                    .help(wallet.address.value)
                Button(action: copyAddress) {
                    Image(systemName: copied ? "checkmark" : "doc.on.doc")
                }
                .buttonStyle(.borderless)
                .help("Copy address")
                .accessibilityLabel("Copy address")
            }
            ForEach(model.domains, id: \.self) { domain in
                Text(domain)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// The alias doubles as the wallet switcher.
    private var walletPicker: some View {
        Menu {
            let mine = model.wallets.filter { $0.keyKind != .none }
            let book = model.wallets.filter { $0.keyKind == .none && !$0.address.isContract }
            let contracts = model.wallets.filter { $0.address.isContract }
            if !mine.isEmpty {
                Section("My accounts") { ForEach(mine) { pickerItem($0) } }
            }
            if !book.isEmpty {
                Section("Address book") { ForEach(book) { pickerItem($0) } }
            }
            if !contracts.isEmpty {
                Section("Contracts") { ForEach(contracts) { pickerItem($0) } }
            }
        } label: {
            HStack(spacing: 6) {
                Text(wallet.alias)
                    .font(.title2.weight(.semibold))
                Image(systemName: "chevron.down")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Switch account")
        .accessibilityLabel("Account \(wallet.alias). Switch account")
    }

    private var contractTag: some View {
        Label("Contract", systemImage: "doc.text")
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(.quaternary))
            .foregroundStyle(.secondary)
    }

    private var watchOnlyTag: some View {
        Label("Watch only", systemImage: "eye")
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(.quaternary))
            .foregroundStyle(.secondary)
            .help("Signet has no key for this address; you can watch it and send to it.")
    }

    /// Orange, unlike the other tags: this key is lost at quit unless Remember key is used.
    private var sessionTag: some View {
        Label("Session only", systemImage: "clock.badge.exclamationmark")
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(.orange.opacity(0.2)))
            .overlay(Capsule().strokeBorder(.orange.opacity(0.5), lineWidth: 1))
            .foregroundStyle(.orange)
            .help("A paper key held in memory only. It is not in the wallet directory or any backup and is forgotten when Signet quits. Use Remember key… in the menu to keep it.")
    }

    private var ledgerTag: some View {
        Label("Ledger", systemImage: "lock.rectangle.stack")
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(.quaternary))
            .foregroundStyle(.secondary)
            .help("This key lives on a Ledger\(wallet.ledgerKey.map { " (\($0.fullPath))" } ?? ""). Operations are approved on the device.")
    }

    private func pickerItem(_ candidate: Wallet) -> some View {
        Button {
            model.select(candidate)
        } label: {
            if candidate.id == wallet.id {
                Label(walletTitle(candidate), systemImage: "checkmark")
            } else {
                Text(walletTitle(candidate))
            }
        }
    }

    private func walletTitle(_ wallet: Wallet) -> String {
        "\(wallet.alias)  \(wallet.address.shortened())"
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

/// The hamburger menu in the top-right corner: app-level actions, not wallet switching.
struct AppMenuButton: View {
    @Bindable var model: WalletViewModel

    var body: some View {
        Menu {
            OperationsMenuItems(model: model, settingsShortcut: true)
        } label: {
            Image(systemName: "line.3.horizontal")
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityLabel("Menu")
    }
}

/// The one list of account actions, shared by the burger menu and the menu bar's Operations
/// menu so the two can never drift: order, dividers, visibility, enabling and shortcuts.
/// Only the Settings item differs: the burger menu carries Cmd-comma, the menu bar leaves it
/// to the app menu's own Settings item.
struct OperationsMenuItems: View {
    @Bindable var model: WalletViewModel
    var settingsShortcut = false

    var body: some View {
        Group {
            Button("Create account…") { model.isPresentingCreateWallet = true }
                .keyboardShortcut("n", modifiers: .command)
            Button("Import account…") { model.isPresentingImportAccount = true }
                .keyboardShortcut("i", modifiers: [.command, .shift])
            Button("Connect Ledger…") { model.isPresentingConnectLedger = true }
                .keyboardShortcut("l", modifiers: [.command, .shift])
            Button("Rename account…") { model.isPresentingRenameWallet = true }
                .disabled(model.selectedWallet == nil)
            Button("Export secret key…") { model.isPresentingExportKey = true }
                .disabled(!model.canExportSelectedKey)
            Divider()
            Button("Add address…") { model.isPresentingAddAddress = true }
                .keyboardShortcut("n", modifiers: [.command, .shift])
            if model.canRememberSelectedKey {
                Button("Remember key…") { model.isPresentingRememberKey = true }
            }
            Button("Forget account…") { model.isPresentingForget = true }
                .disabled(model.selectedWallet == nil)
            Divider()
            Button("dApps…") { model.isPresentingConnectDApp = true }
                .keyboardShortcut("d", modifiers: [.command, .shift])
            if model.canBridge {
                Button("Bridge…") { model.isPresentingBridge = true }
            }
            if model.canShield {
                Button("Shield tez…") { model.isPresentingShield = true }
                Button("Unshield tez…") { model.isPresentingUnshield = true }
                Button("Send shielded…") { model.isPresentingSendShielded = true }
                Button("Shielded address…") { model.isPresentingShieldedAddress = true }
            }
            Divider()
            Button("Create multisig…") { model.isPresentingCreateMultisig = true }
            Button("Add multisig…") { model.isPresentingAddMultisig = true }
            Button("Sign multisig transaction…") { model.isPresentingSignMultisig = true }
            Button("Submit multisig transaction…") { model.isPresentingSubmitMultisig = true }
            Divider()
            Button("Baking…") { model.isPresentingBaking = true }
                .disabled(model.selectedWallet == nil)
            if model.canGovern {
                Button("Governance…") { model.isPresentingGovernance = true }
            }
            Divider()
            Button("Networks…") { model.isPresentingNetworks = true }
            Button("Shielded settings…") { model.isPresentingShieldSettings = true }
            if settingsShortcut {
                SettingsLink { Text("Settings…") }
                    .keyboardShortcut(",", modifiers: .command)
            } else {
                SettingsLink { Text("Settings…") }
            }
            Button("Refresh") { Task { await model.refresh() } }
                .keyboardShortcut("r", modifiers: .command)
                .disabled(model.selectedWallet == nil)
        }
    }
}
