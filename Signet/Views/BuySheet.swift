import AppKit
import SwiftUI

/// Buy tez through the on-ramp chosen in Settings. Signet pre-fills (and, when it can sign,
/// pre-validates) the account's address, then shows the provider's widget right here; the purchase,
/// identity checks and payment are all the provider's, and the tez land in the account.
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

            switch step {
            case .prepare: prepare
            case .widget(let url): widget(url)
            }

            if let errorMessage { Text(errorMessage).font(.callout).foregroundStyle(.red) }
            buttons
        }
        .padding(20)
        .frame(width: 560)
    }

    // MARK: Step 1

    private var prepare: some View {
        Form {
            LabeledContent("Provider") {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(provider.title)
                    Text("Change in Settings").font(.caption).foregroundStyle(.secondary)
                }
            }
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
            BuyWebView(url: url, provider: provider, isLoading: $isLoading, loadError: $loadError)
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
