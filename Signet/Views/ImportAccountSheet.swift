import SwiftUI

/// Brings in an existing account from a recovery phrase or a pasted secret key. The secret is
/// derived or checked through the bridge, previewed, then written to the key store (clear, or
/// encrypted with a password like Create account).
struct ImportAccountSheet: View {
    @Bindable var model: WalletViewModel
    @Environment(\.dismiss) private var dismiss

    enum Source: String, CaseIterable, Identifiable {
        case secretKey = "Secret key"
        case phrase = "Recovery phrase"
        var id: String { rawValue }
    }

    @State private var source: Source = .secretKey
    @State private var alias: String
    // Phrase
    @State private var phrase = ""
    @State private var phrasePassphrase = ""
    @State private var curve: MnemonicCurve = .ed25519
    @State private var account = 0
    @State private var legacy = false
    @State private var fundraiserEmail = ""
    @State private var fundraiserPassword = ""
    @State private var phraseCheck: MnemonicCheck?
    // Secret key
    @State private var secretKeyText = ""
    @State private var keyPassphrase = ""
    @State private var inspected: InspectedSecretKey?
    // Storage
    @State private var encrypt: Bool
    @State private var password = ""
    @State private var confirmPassword = ""

    @State private var preview: KeyMaterial?
    @State private var previewTask: Task<Void, Never>?
    @State private var previewError: String?
    @State private var errorMessage: String?
    @State private var isImporting = false

    init(model: WalletViewModel) {
        self.model = model
        _alias = State(initialValue: model.suggestedAlias(base: "Imported"))
        _encrypt = State(initialValue: model.network.isMainnet)
    }

    private var trimmedAlias: String { alias.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var derivationPath: String { "44'/1729'/\(account)'/0'" }
    private var existing: Wallet? { preview.flatMap { m in model.wallets.first { $0.address.value == m.address } } }
    /// An encrypted key pasted in is stored as it is; the storage password question does not apply.
    private var keepsOwnEncryption: Bool { source == .secretKey && inspected?.isEncrypted == true }
    private var passwordProblem: String? {
        guard encrypt, !keepsOwnEncryption else { return nil }
        if password.count < WalletViewModel.minimumPassphraseLength { return "Use at least \(WalletViewModel.minimumPassphraseLength) characters." }
        if password != confirmPassword { return "The passwords do not match." }
        return nil
    }
    private var canImport: Bool { preview != nil && existing == nil && !trimmedAlias.isEmpty && passwordProblem == nil && !isImporting }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Import account").font(.title2.weight(.semibold))

            Picker("Source", selection: $source) {
                ForEach(Source.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented).labelsHidden()

            Form {
                TextField("Name", text: $alias, prompt: Text("Imported"))
                switch source {
                case .secretKey: secretKeyFields
                case .phrase: phraseFields
                }
                previewRow
                storageFields
            }
            .formStyle(.grouped)
            .scrollDisabled(true)

            if let errorMessage { Text(errorMessage).font(.callout).foregroundStyle(.red) }

            HStack {
                if isImporting { ProgressView().controlSize(.small); Text("Importing…").font(.callout).foregroundStyle(.secondary) }
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction).disabled(isImporting)
                Button("Import", action: importAccount).keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent).disabled(!canImport)
            }
        }
        .padding(20)
        .frame(width: 560)
        .onChange(of: source) { refreshPreview() }
        .onChange(of: phrase) { refreshPreview() }
        .onChange(of: phrasePassphrase) { refreshPreview() }
        .onChange(of: curve) { refreshPreview() }
        .onChange(of: account) { refreshPreview() }
        .onChange(of: legacy) { refreshPreview() }
        .onChange(of: fundraiserEmail) { refreshPreview() }
        .onChange(of: fundraiserPassword) { refreshPreview() }
        .onChange(of: secretKeyText) { refreshPreview() }
        .onChange(of: keyPassphrase) { refreshPreview() }
    }

    // MARK: Phrase

    @ViewBuilder
    private var phraseFields: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Recovery phrase")
            TextEditor(text: $phrase)
                .font(.body.monospaced())
                .frame(height: 72)
                .autocorrectionDisabled()
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.secondary.opacity(0.3)))
            if let phraseCheck, phraseCheck.wordCount > 0 {
                if !phraseCheck.unknownWords.isEmpty {
                    Text("Not in the word list: \(phraseCheck.unknownWords.joined(separator: ", "))").font(.caption).foregroundStyle(.orange)
                } else if !phraseCheck.isValid {
                    Text("\(phraseCheck.wordCount) words; a phrase has 12, 15, 18, 21 or 24 words and a valid checksum.").font(.caption).foregroundStyle(.orange)
                } else {
                    Text("\(phraseCheck.wordCount)-word phrase").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        Toggle("Legacy fundraiser derivation (email and password)", isOn: $legacy)
        if legacy {
            TextField("Email", text: $fundraiserEmail).autocorrectionDisabled()
            SecureField("Fundraiser password", text: $fundraiserPassword)
            Text("For keys from the 2017 fundraiser and some very old wallets. Everything else uses the standard derivation below.").font(.callout).foregroundStyle(.secondary)
        } else {
            SecureField("Phrase passphrase (optional)", text: $phrasePassphrase)
            Picker("Key type", selection: $curve) {
                ForEach(MnemonicCurve.allCases) { Text($0.title).tag($0) }
            }
            Stepper("Account \(account)  (\(derivationPath))", value: $account, in: 0...100)
            Text("Temple, Kukai, Umami and most wallets use Ed25519 at account 0. If the address shown is not the one you expect, try another account or key type.").font(.callout).foregroundStyle(.secondary)
        }
    }

    // MARK: Secret key

    @ViewBuilder
    private var secretKeyFields: some View {
        SecureField("Secret key", text: $secretKeyText, prompt: Text("edsk… / spsk… / p2sk… / BLsk… / mdsk… / edesk…"))
            .font(.body.monospaced()).autocorrectionDisabled()
        if inspected?.isEncrypted == true || secretKeyText.hasPrefix("edesk") || secretKeyText.hasPrefix("spesk") || secretKeyText.hasPrefix("p2esk") || secretKeyText.hasPrefix("BLesk") || secretKeyText.hasPrefix("mdesk") {
            SecureField("Password for this key", text: $keyPassphrase)
            Text("An octez-client encrypted key. It is stored as it is and keeps this password.").font(.callout).foregroundStyle(.secondary)
        }
    }

    // MARK: Preview and storage

    private var previewRow: some View {
        LabeledContent("Address") {
            if let preview {
                VStack(alignment: .trailing, spacing: 2) {
                    HStack(spacing: 6) {
                        AccountAvatarView(address: Address(preview.address), size: 20)
                        Text(preview.address).font(.callout.monospaced()).textSelection(.enabled)
                    }
                    if let existing {
                        Label("Already in your list as “\(existing.alias)”", systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange)
                    }
                }
            } else if let previewError {
                Text(previewError).font(.callout).foregroundStyle(.orange).multilineTextAlignment(.trailing)
            } else {
                Text("—").foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var storageFields: some View {
        if !keepsOwnEncryption {
            Toggle("Encrypt with a password", isOn: $encrypt)
            if encrypt {
                SecureField("Password", text: $password)
                SecureField("Confirm password", text: $confirmPassword)
                if let passwordProblem, !password.isEmpty { Text(passwordProblem).font(.callout).foregroundStyle(.secondary) }
            } else {
                Label("Unencrypted keys are stored on disk unprotected. Anyone who can read ~/.signet can spend from this account.", systemImage: "exclamationmark.triangle")
                    .font(.callout).foregroundStyle(.orange)
            }
        }
    }

    private func refreshPreview() {
        previewTask?.cancel()
        preview = nil
        previewError = nil
        inspected = nil
        let importer = model.keyImporter
        switch source {
        case .phrase:
            let words = phrase.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !words.isEmpty else { phraseCheck = nil; return }
            let (passphrase, path, curve, legacy, email, password) = (phrasePassphrase, derivationPath, curve, legacy, fundraiserEmail, fundraiserPassword)
            previewTask = Task {
                try? await Task.sleep(for: .milliseconds(400))
                guard !Task.isCancelled else { return }
                do {
                    let check = try await importer.check(mnemonic: words)
                    guard !Task.isCancelled else { return }
                    phraseCheck = check
                    guard check.isValid else { return }
                    let material = legacy
                        ? try await importer.key(fromFundraiserEmail: email, password: password, mnemonic: words)
                        : try await importer.key(fromMnemonic: words, passphrase: passphrase.isEmpty ? nil : passphrase, derivationPath: path, curve: curve)
                    guard !Task.isCancelled else { return }
                    preview = material
                } catch {
                    if !Task.isCancelled { previewError = error.localizedDescription }
                }
            }
        case .secretKey:
            let key = secretKeyText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty else { return }
            let passphrase = keyPassphrase
            previewTask = Task {
                try? await Task.sleep(for: .milliseconds(400))
                guard !Task.isCancelled else { return }
                do {
                    let result = try await importer.inspect(secretKey: key, passphrase: passphrase.isEmpty ? nil : passphrase)
                    guard !Task.isCancelled else { return }
                    inspected = result
                    if result.needsPassphrase {
                        previewError = "Enter the key's password."
                    } else if let pk = result.publicKey, let address = result.address, let sk = result.secretKey {
                        preview = KeyMaterial(scheme: address.scheme ?? .tz1, publicKey: pk, address: address.value, secretKey: sk)
                    }
                } catch {
                    if !Task.isCancelled { previewError = error.localizedDescription }
                }
            }
        }
    }

    private func importAccount() {
        guard let preview else { return }
        errorMessage = nil
        isImporting = true
        Task {
            defer { isImporting = false }
            do {
                try await model.importAccount(alias: trimmedAlias, material: preview, alreadyEncrypted: keepsOwnEncryption,
                                              storePassphrase: (!keepsOwnEncryption && encrypt) ? password : nil)
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

#Preview {
    ImportAccountSheet(model: .preview())
}
