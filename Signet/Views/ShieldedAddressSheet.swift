import SwiftUI

/// The account's shielded address, to give to whoever will send to it, and the network's
/// shielded address book. A shielded address is the payment address record itself (there is
/// no short form in the protocol), so it is shown as the JSON other wallets take, with a
/// fingerprint to read out to the sender. "New address" makes a fresh one so that two payers
/// cannot tell they paid the same wallet.
struct ShieldedAddressSheet: View {
    @Bindable var model: WalletViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var address: ShieldedReceiveAddress?
    @State private var loading = false
    @State private var copied = false
    @State private var contacts: [ShieldedContact] = []
    @State private var newName = ""
    @State private var newJSON = ""
    @State private var parsed: ShieldedContact?
    @State private var parseError: String?
    @State private var errorMessage: String?

    private var wallet: Wallet? { model.selectedWallet }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                if let wallet { AccountAvatarView(address: wallet.address, size: 40) }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Shielded address").font(.title2.weight(.semibold))
                    if let wallet { Text("\(wallet.alias)  \(wallet.address.shortened())").font(.callout).foregroundStyle(.secondary) }
                }
            }
            own
            book
            if let errorMessage { Text(errorMessage).font(.callout).foregroundStyle(.red) }
            HStack {
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(width: 620)
        .task { await load() }
        .task(id: newJSON) { await parseNew() }
    }

    private var own: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Your address").font(.headline)
            if let address {
                HStack {
                    Text("Address #\(address.index)").font(.callout).foregroundStyle(.secondary)
                    Text("fingerprint \(SendShieldedSheet.short(address.fingerprint))").font(.callout.monospaced()).textSelection(.enabled)
                    Spacer()
                    Button(copied ? "Copied" : "Copy") { copy(address.json) }.controlSize(.small)
                    Button("New address") { Task { await makeNew() } }.controlSize(.small).disabled(loading)
                }
                ScrollView {
                    Text(address.json).font(.caption.monospaced()).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding(6)
                }
                .frame(height: 110)
                .background(RoundedRectangle(cornerRadius: 6).fill(.quaternary.opacity(0.5)))
                Text("Give the sender this JSON (Copy puts all of it on the clipboard) and read them the fingerprint so they can check what they pasted. Anything sent to it shows in your Shielded balance; nothing on the rollup links it to you.")
                    .font(.callout).foregroundStyle(.secondary)
            } else if loading {
                HStack(spacing: 6) { ProgressView().controlSize(.small); Text(model.shieldProgress?.text ?? "Preparing…").font(.callout).foregroundStyle(.secondary) }
            } else if !model.canShield {
                Text("Shielded addresses need Shielded Transactions on for this network and an account Signet can sign for.").font(.callout).foregroundStyle(.orange)
            }
        }
    }

    private var book: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Address book").font(.headline)
            if contacts.isEmpty { Text("No shielded addresses saved yet.").font(.callout).foregroundStyle(.secondary) }
            ForEach(contacts) { contact in
                HStack {
                    Text(contact.name).font(.callout)
                    Text(SendShieldedSheet.short(contact.fingerprint)).font(.callout.monospaced()).foregroundStyle(.secondary).textSelection(.enabled)
                    Spacer()
                    Button("Remove") { remove(contact) }.controlSize(.small)
                }
            }
            HStack(alignment: .top) {
                TextField("Name", text: $newName).frame(width: 160)
                TextEditor(text: $newJSON).font(.caption.monospaced()).frame(height: 60)
                    .overlay(alignment: .topLeading) {
                        if newJSON.isEmpty { Text("Paste a shielded address").font(.caption).foregroundStyle(.tertiary).padding(6).allowsHitTesting(false) }
                    }
                Button("Add") { add() }.disabled(parsed == nil || newName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            if let parseError, !newJSON.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { Text(parseError).font(.caption).foregroundStyle(.orange) }
            else if let parsed { Text("Fingerprint \(SendShieldedSheet.short(parsed.fingerprint))").font(.caption.monospaced()).foregroundStyle(.secondary) }
        }
    }

    // MARK: Actions

    private func load() async {
        contacts = (try? model.shieldedContacts()) ?? []
        guard model.canShield else { return }
        loading = true
        defer { loading = false }
        do { address = try await model.shieldedReceiveAddress() } catch { errorMessage = error.localizedDescription }
    }

    private func makeNew() async {
        errorMessage = nil
        loading = true
        defer { loading = false }
        do { address = try await model.makeShieldedAddress(); copied = false } catch { errorMessage = error.localizedDescription }
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        copied = true
    }

    private func parseNew() async {
        parsed = nil
        parseError = nil
        guard !newJSON.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        try? await Task.sleep(for: .milliseconds(300))
        guard !Task.isCancelled else { return }
        do {
            let contact = try await model.shieldedRecipient(from: newJSON)
            if !Task.isCancelled { parsed = contact }
        } catch {
            if !Task.isCancelled { parseError = error.localizedDescription }
        }
    }

    private func add() {
        guard let parsed else { return }
        errorMessage = nil
        do {
            try model.addShieldedContact(parsed, name: newName)
            contacts = (try? model.shieldedContacts()) ?? []
            newName = ""
            newJSON = ""
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func remove(_ contact: ShieldedContact) {
        errorMessage = nil
        do { try model.removeShieldedContact(contact.fingerprint); contacts = (try? model.shieldedContacts()) ?? [] } catch { errorMessage = error.localizedDescription }
    }
}
