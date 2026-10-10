import SwiftUI

/// Account identity. Receive contains the address, QR code and domains.
struct WalletIdentityView: View {
    @Bindable var model: WalletViewModel
    let wallet: Wallet
    let showAccounts: () -> Void

    var body: some View {
        Button(action: showAccounts) {
            HStack(spacing: 12) {
                AccountAvatarView(address: wallet.address, network: model.network, size: 44)
                Text(wallet.alias)
                    .font(.title3.weight(.semibold))
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                if wallet.keyKind == .none {
                    Text("Watch only").font(.caption).foregroundStyle(.secondary)
                }
                if wallet.keyKind == .ledger {
                    Image(systemName: "lock.rectangle.stack").foregroundStyle(.secondary)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Accounts and hardware")
        .accessibilityLabel("Account \(wallet.alias). Open accounts and hardware")
    }
}

struct AppMenuButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "ellipsis")
                .font(.system(size: 18, weight: .semibold))
                .frame(width: 36, height: 36)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .help("Quick actions")
        .accessibilityLabel("Open quick actions")
    }
}

/// One native sheet hosts navigation; operation sheets open only after it dismisses.
enum WalletNavigationPage: String, Identifiable {
    case accounts, actions, more, addressBook, manageAccount, conversion, about
    var id: String { rawValue }
    var title: String {
        switch self {
        case .accounts: "Accounts & Hardware"
        case .actions: "Quick actions"
        case .more: "More"
        case .addressBook: "Address book"
        case .manageAccount: "Manage account"
        case .conversion: "Currency conversion"
        case .about: "About Signet"
        }
    }
}

enum WalletNavigationAction {
    case create, importAccount, ledger, rename, exportKey, addAddress, forget
    case connectDApp, baking, governance, swap, refresh
}

struct WalletNavigationSheet: View {
    @Bindable var model: WalletViewModel
    @State var page: WalletNavigationPage
    let onAction: (WalletNavigationAction) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var history: [WalletNavigationPage] = []

    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Development build"
    }

    var body: some View {
        VStack(spacing: 0) {
            Capsule().fill(.secondary.opacity(0.35)).frame(width: 38, height: 4)
                .padding(.top, 12).padding(.bottom, 20)
                .accessibilityHidden(true)
            HStack {
                Button {
                    if let previous = history.popLast() { page = previous }
                    else { dismiss() }
                } label: {
                    Image(systemName: history.isEmpty ? "xmark" : "arrow.left")
                        .font(.system(size: 16, weight: .medium))
                        .frame(width: 36, height: 36)
                        .background(Color.primary.opacity(0.05), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(history.isEmpty ? "Close" : "Back")
                Spacer()
                Text(page.title).font(.title3.weight(.semibold))
                Spacer()
                Color.clear.frame(width: 36, height: 36)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 20)

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    switch page {
                    case .accounts: accounts
                    case .actions: quickActions
                    case .more: more
                    case .addressBook: addressBook
                    case .manageAccount: manageAccount
                    case .conversion: CurrencyConversionView()
                    case .about: about
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }
            if page == .more || page == .about {
                VStack(spacing: 8) {
                    Image(systemName: "seal").font(.system(size: 32, weight: .light))
                    Text("SIGNET").font(.caption.weight(.semibold)).tracking(4)
                    Text("Version \(version)").font(.caption).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(24)
            }
        }
        .frame(width: 500, height: 680)
        .background(Theme.canvas)
        .tint(Theme.violet)
    }

    private func navigate(_ destination: WalletNavigationPage) {
        history.append(page)
        page = destination
    }

    private func row(_ title: String, detail: String? = nil, symbol: String,
                     enabled: Bool = true, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            NavigationRow(title: title, detail: detail, symbol: symbol)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.45)
    }

    private var accounts: some View {
        VStack(alignment: .leading, spacing: 18) {
            let accounts = model.wallets.filter { $0.keyKind != .none }
            if accounts.isEmpty {
                Text("No accounts yet").foregroundStyle(.secondary).padding(.vertical, 16)
            }
            ForEach(accounts) { account in
                accountRow(account)
            }
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 14) {
                    Image(systemName: "lock.rectangle.stack")
                        .font(.system(size: 32, weight: .light))
                        .foregroundStyle(Theme.violet)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Ledger hardware wallet").font(.title3.weight(.semibold))
                        Text("Keep your keys on your device.")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                }
                LedgerIllustration()
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                Text("Connect your Ledger to manage Tezos in Signet. Approve outgoing operations on the device.")
                    .font(.callout).foregroundStyle(.secondary)
                Button { onAction(.ledger) } label: {
                    Text("Connect hardware wallet").font(.body.weight(.semibold))
                        .frame(maxWidth: .infinity).padding(.vertical, 14)
                }
                .buttonStyle(.plain)
                .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.secondary.opacity(0.18)))
            }
            .padding(20)
            .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 22))
            row("Create account", symbol: "plus.circle") { onAction(.create) }
            row("Import account", symbol: "key.horizontal") { onAction(.importAccount) }
        }
    }

    private func accountRow(_ account: Wallet) -> some View {
        Button {
            model.select(account)
            dismiss()
        } label: {
            HStack(spacing: 14) {
                AccountAvatarView(address: account.address, size: 44)
                VStack(alignment: .leading, spacing: 4) {
                    Text(account.alias).font(.body.weight(.semibold))
                    Text(account.address.shortened()).font(.caption.monospaced()).foregroundStyle(.secondary)
                }
                Spacer()
                if account.keyKind == .ledger {
                    Image(systemName: "lock.rectangle.stack").foregroundStyle(.secondary)
                }
                if account.id == model.selectedWallet?.id {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.violet)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: 18))
            .contentShape(RoundedRectangle(cornerRadius: 18))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(account.alias), \(account.address.shortened())")
        .accessibilityAddTraits(account.id == model.selectedWallet?.id ? .isSelected : [])
    }

    private var quickActions: some View {
        VStack(spacing: 0) {
            row("Swap", detail: "Exchange Tezos assets through 3Route.", symbol: "arrow.up.arrow.down",
                enabled: model.network.isMainnet && model.selectedWallet != nil) { onAction(.swap) }
            Divider()
            row("Connect Ledger", detail: "Use a key held on your hardware wallet.", symbol: "lock.rectangle.stack") { onAction(.ledger) }
            Divider()
            row("Connect to a dApp", detail: "Pair with a Tezos application.", symbol: "square.stack.3d.up") { onAction(.connectDApp) }
            Divider()
            row("Import account", detail: "Use a secret key or recovery phrase.", symbol: "key.horizontal") { onAction(.importAccount) }
            Divider()
            row("More", symbol: "gearshape") { navigate(.more) }
            Label("Review requests before signing. Your keys stay in your account or on your Ledger.", systemImage: "info.circle")
                .font(.caption).foregroundStyle(.secondary)
                .padding(.top, 24)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var more: some View {
        VStack(spacing: 0) {
            row("Address book", symbol: "person.crop.circle") { navigate(.addressBook) }
            Divider()
            row("Currency conversion", symbol: "dollarsign") { navigate(.conversion) }
            Divider()
            row("Governance", detail: model.canGovern ? nil : "Available for baker accounts.", symbol: "checkmark.seal",
                enabled: model.canGovern) { onAction(.governance) }
            Divider()
            row("Manage account", symbol: "person.crop.circle.badge.checkmark") { navigate(.manageAccount) }
            Divider()
            SettingsLink {
                NavigationRow(title: "Advanced settings", symbol: "gearshape")
            }
            .buttonStyle(.plain)
            Divider()
            Link(destination: URL(string: "https://github.com/drchrispinnock/signet/releases")!) {
                NavigationRow(title: "What’s new", symbol: "sparkles")
            }.buttonStyle(.plain)
            Divider()
            row("About", symbol: "info.circle") { navigate(.about) }
            Divider()
            Link(destination: URL(string: "https://github.com/drchrispinnock/signet/issues/new")!) {
                NavigationRow(title: "Send feedback", symbol: "bubble.left")
            }.buttonStyle(.plain)
        }
    }

    private var addressBook: some View {
        VStack(alignment: .leading, spacing: 14) {
            let entries = model.wallets.filter { $0.keyKind == .none }
            if entries.isEmpty {
                Text("Save Tezos addresses you send to often.")
                    .font(.callout).foregroundStyle(.secondary).padding(.vertical, 20)
            }
            ForEach(entries) { account in accountRow(account) }
            row("Add address", symbol: "person.badge.plus") { onAction(.addAddress) }
        }
    }

    private var manageAccount: some View {
        VStack(spacing: 0) {
            row("Create account", symbol: "plus.circle") { onAction(.create) }
            Divider()
            row("Import account", symbol: "key.horizontal") { onAction(.importAccount) }
            Divider()
            row("Rename account", symbol: "pencil", enabled: model.selectedWallet != nil) { onAction(.rename) }
            Divider()
            row("Export secret key", symbol: "key", enabled: model.canExportSelectedKey) { onAction(.exportKey) }
            Divider()
            row("Baking", symbol: "flame", enabled: model.selectedWallet != nil) { onAction(.baking) }
            Divider()
            row("Refresh", symbol: "arrow.clockwise", enabled: model.selectedWallet != nil) { onAction(.refresh) }
            Divider()
            row("Forget account", detail: "Review the warning before removing an account.", symbol: "minus.circle",
                enabled: model.selectedWallet != nil) { onAction(.forget) }
        }
    }

    private var about: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Your Tezos. Your Mac.").font(.title2.weight(.semibold))
            Text("Signet is a native macOS wallet for Tezos. Manage accounts, receive tez, connect a Ledger, and take part in staking and governance.")
                .font(.body).foregroundStyle(.secondary)
            Text("Open source · MIT license").font(.callout)
            Link("View source on GitHub", destination: URL(string: "https://github.com/drchrispinnock/signet")!)
            Text(Disclaimer.message).font(.caption).foregroundStyle(.secondary)
        }
        .padding(.vertical, 16)
    }
}

private struct NavigationRow: View {
    let title: String
    var detail: String? = nil
    let symbol: String

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: symbol)
                .font(.system(size: 21, weight: .regular))
                .frame(width: 46, height: 46)
                .background(Color.primary.opacity(0.07), in: Circle())
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.body.weight(.semibold))
                if let detail {
                    Text(detail).font(.callout).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 12)
            Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
        }
        .padding(.vertical, 17)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }
}

private struct CurrencyConversionView: View {
    @State private var amount = ""
    @State private var rate = ""
    @State private var currency = "CHF"

    private var converted: Decimal? {
        guard let amount = Decimal(string: amount, locale: .current), amount >= 0,
              let rate = Decimal(string: rate, locale: .current), rate > 0 else { return nil }
        return amount * rate
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Estimate a conversion").font(.title3.weight(.semibold))
            Text("Enter your own exchange rate. This is an estimate, not a live quote or a swap.")
                .font(.callout).foregroundStyle(.secondary)
            TextField("Amount in tez", text: $amount).textFieldStyle(.roundedBorder)
            Picker("Currency", selection: $currency) {
                ForEach(["CHF", "EUR", "USD", "GBP"], id: \.self) { Text($0).tag($0) }
            }
            TextField("\(currency) per tez", text: $rate).textFieldStyle(.roundedBorder)
            if let converted {
                Text(converted.formatted(.number.precision(.fractionLength(2))) + " " + currency)
                    .font(.system(size: 32, weight: .medium, design: .rounded))
                    .textSelection(.enabled)
            }
        }
        .padding(.vertical, 16)
    }
}

private struct LedgerIllustration: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18)
                .fill(LinearGradient(colors: [Color(white: 0.78), Color(white: 0.46)], startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 236, height: 80)
            HStack(spacing: 18) {
                Circle().fill(Color(white: 0.32)).frame(width: 16, height: 16)
                Text("ꜩ  Tezos")
                    .font(.system(size: 18, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color(white: 0.92))
                    .frame(width: 140, height: 44)
                    .background(Color(white: 0.12), in: RoundedRectangle(cornerRadius: 7))
                Circle().fill(Color(white: 0.32)).frame(width: 16, height: 16)
            }
        }
        .rotationEffect(.degrees(-8))
        .frame(height: 110)
        .accessibilityLabel("Illustration of a Ledger hardware wallet")
    }
}
