import AppKit
import SwiftUI

/// Buy tez through an on-ramp picked from the dropdown at the top of the sheet (the choice is
/// remembered). With a widget provider Signet pre-fills (and, when it can sign, pre-validates)
/// the account's address, then shows the provider's widget right here; the purchase, identity
/// checks and payment are all the provider's, and the tez land in the account. With an exchange
/// (Coinbase, Kraken) or Transak's site it shows the address to paste and opens the page in the
/// browser.
struct BuySheet: View {
    @Bindable var model: WalletViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    enum Step: Equatable { case prepare, widget(URL) }

    @AppStorage(BuyProvider.key) private var providerID = BuyProvider.default.rawValue
    private var provider: BuyProvider { BuyProvider(rawValue: providerID) ?? .default }

    @State private var step: Step = .prepare
    @State private var fiat = BuyProvider.current.defaultFiat()
    @State private var passphrase = ""
    @State private var isWorking = false
    @State private var isLoading = false
    @State private var loadError: String?
    @State private var errorMessage: String?
    /// What the embedded page is showing, so the user can see whose site they are on.
    @State private var currentURL: URL?

    private var wallet: Wallet? { model.selectedWallet }
    private var canSign: Bool { wallet?.keyKind.canSign == true }
    private var needsPassphrase: Bool { wallet?.keyKind == .encrypted }
    private var signsOnLedger: Bool { wallet?.keyKind == .ledger }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                if let wallet { AccountAvatarView(address: wallet.address, size: 40) }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Buy tez").font(.title2.weight(.semibold))
                    if let wallet { Text("\(wallet.alias)  \(wallet.address.shortened())").font(.callout).foregroundStyle(.secondary) }
                }
                Spacer()
                if case .widget = step {
                    if isLoading { ProgressView().controlSize(.small) }
                    Text(provider.title).font(.callout).foregroundStyle(.secondary)
                }
            }

            if provider.usesWidget {
                switch step {
                case .prepare: prepare
                case .widget(let url): widget(url)
                }
            } else {
                exchange
            }

            if let errorMessage { Text(errorMessage).font(.callout).foregroundStyle(.red) }
            buttons
        }
        .padding(20)
        .frame(width: 560)
        .onChange(of: providerID) { _, _ in
            // A new provider starts over: its own currencies, no widget, no stale error.
            step = .prepare
            fiat = provider.defaultFiat()
            errorMessage = nil
            loadError = nil
            currentURL = nil
        }
    }

    /// The dropdown that switches providers; the choice is kept for next time.
    private var providerPicker: some View {
        Picker("Provider", selection: $providerID) {
            ForEach(BuyProvider.allCases) { Text($0.title).tag($0.rawValue) }
        }
    }

    // MARK: Exchange (no widget)

    @State private var copied = false

    /// The address to paste as the withdrawal destination, and the exchange's page in the browser.
    private var exchange: some View {
        Form {
            providerPicker
            if let wallet {
                LabeledContent("Send to") {
                    HStack(spacing: 8) {
                        Text(wallet.address.value).font(.callout.monospaced()).textSelection(.enabled)
                        Button(action: { copy(wallet.address.value) }) {
                            Image(systemName: copied ? "checkmark" : "doc.on.doc")
                        }
                        .buttonStyle(.borderless)
                        .help("Copy address")
                    }
                }
                HStack {
                    Spacer()
                    if let image = QRCode.image(for: wallet.address.value, size: 160) {
                        Image(nsImage: image).interpolation(.none).frame(width: 160, height: 160)
                            .padding(8).background(.white).clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    Spacer()
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("1. Open \(provider.title) and buy tez (XTZ).")
                Text("2. \(provider.deliveryStep)")
                Text("3. The balance here refreshes once the transfer is in a block.")
            }
            .font(.callout).foregroundStyle(.secondary)
            Text("\(provider.summary) Send tez only; tokens on other networks cannot reach a Tezos address.")
                .font(.callout).foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
        .scrollDisabled(true)
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        copied = true
        Task { try? await Task.sleep(for: .seconds(1.5)); copied = false }
    }

    // MARK: Step 1

    private var prepare: some View {
        Form {
            providerPicker
            Picker("Pay in", selection: $fiat) {
                ForEach(provider.fiatCurrencies, id: \.self) { Text($0).tag($0) }
            }
            if let wallet {
                LabeledContent("Deliver to") { Text(wallet.address.value).font(.callout.monospaced()).textSelection(.enabled) }
            }
            if needsPassphrase, let wallet {
                SecureField("Password for “\(wallet.alias)”", text: $passphrase)
                Text("Signet signs a short message with this key so \(provider.title) knows the address is yours.").font(.callout).foregroundStyle(.secondary)
            } else if signsOnLedger {
                Text("Your Ledger will ask you to sign a short message proving the address is yours.").font(.callout).foregroundStyle(.secondary)
            } else if !canSign {
                Text("Signet holds no key for this address, so \(provider.title) will ask you to confirm it in the widget.").font(.callout).foregroundStyle(.secondary)
            }
            Text("\(provider.summary) Everything in the next step runs on \(provider.title)'s site, shown inside Signet.")
                .font(.callout).foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
        .scrollDisabled(true)
    }

    // MARK: Step 2

    private func widget(_ url: URL) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                let host = (currentURL ?? url).host() ?? ""
                let trusted = BuyWebView.isTrusted(currentURL ?? url, provider: provider)
                Image(systemName: trusted ? "lock.fill" : "lock.open")
                    .foregroundStyle(trusted ? Color.secondary : Color.orange)
                Text(host).font(.callout.monospaced()).foregroundStyle(.secondary)
                Spacer()
            }
            .help("Only \(provider.title)'s own HTTPS pages can show here; other sites open in your browser.")
            BuyWebView(url: url, provider: provider, isLoading: $isLoading, loadError: $loadError, currentURL: $currentURL)
                .frame(height: 620)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.secondary.opacity(0.25)))
            if let loadError {
                Label("The widget could not load: \(loadError)", systemImage: "exclamationmark.triangle").font(.callout).foregroundStyle(.orange)
            }
            Text("When the purchase is done the balance refreshes on the next block.").font(.caption).foregroundStyle(.secondary)
        }
    }

    // MARK: Buttons

    private var buttons: some View {
        HStack {
            if isWorking {
                if signsOnLedger { LedgerPromptLabel(text: "Sign the message on your Ledger…") }
                else { ProgressView().controlSize(.small); Text("Preparing…").font(.callout).foregroundStyle(.secondary) }
            }
            Spacer()
            if !provider.usesWidget {
                Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Open \(provider.title)") { if let page = provider.browserPage { NSWorkspace.shared.open(page) } }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
            } else {
            switch step {
            case .prepare:
                Button("Cancel", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Continue", action: start)
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(isWorking || (needsPassphrase && passphrase.isEmpty))
            case .widget:
                Button("Open in browser instead") { openInBrowser() }
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
            }
        }
    }

    private func start() {
        errorMessage = nil
        isWorking = true
        Task {
            defer { isWorking = false }
            do {
                let url = try await model.buyURL(provider: provider, fiat: fiat, passphrase: needsPassphrase ? passphrase : nil, embedded: true, dark: colorScheme == .dark)
                step = .widget(url)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    /// The same session as a direct link; the signed proof is reused so nothing is asked twice.
    private func openInBrowser() {
        guard case .widget(let url) = step else { return }
        NSWorkspace.shared.open(provider.browserURL(from: url))
    }
}

#Preview {
    BuySheet(model: .preview())
}
