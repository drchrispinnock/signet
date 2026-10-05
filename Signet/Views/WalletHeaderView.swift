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
            walletPicker
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
            let book = model.wallets.filter { $0.keyKind == .none }
            if !mine.isEmpty {
                Section("My wallets") { ForEach(mine) { pickerItem($0) } }
            }
            if !book.isEmpty {
                Section("Address book") { ForEach(book) { pickerItem($0) } }
            }
        } label: {
            HStack(spacing: 6) {
                Text(wallet.alias)
                    .font(.title2.weight(.semibold))
                Image(systemName: "chevron.down")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                if wallet.keyKind == .none { watchOnlyTag }
            }
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Switch wallet")
        .accessibilityLabel("Wallet \(wallet.alias). Switch wallet")
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
            Button("Create wallet…") { model.isPresentingCreateWallet = true }
                .keyboardShortcut("n", modifiers: .command)
            Button("Add address…") { model.isPresentingAddAddress = true }
                .keyboardShortcut("n", modifiers: [.command, .shift])
            Button("Rename wallet…") { model.isPresentingRenameWallet = true }
                .disabled(model.selectedWallet == nil)
            Button("Reload wallets") { model.reloadWallets() }
            Divider()
            SettingsLink { Text("Settings…") }
                .keyboardShortcut(",", modifiers: .command)
            Button("Refresh") { Task { await model.refresh() } }
                .keyboardShortcut("r", modifiers: .command)
                .disabled(model.selectedWallet == nil)
        } label: {
            Image(systemName: "line.3.horizontal")
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityLabel("Menu")
    }
}
