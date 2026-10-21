import Foundation
import Observation

/// Drives the Send sheet: pick a recipient, enter an amount, confirm, send, watch for inclusion.
@MainActor
@Observable
final class SendViewModel {
    enum Step: Equatable {
        case compose
        case confirm
        case sending
        case sent(hash: String)
        /// The node's answer to the injection was lost: the operation may be on its way (S15).
        case unknown(hash: String)
        case confirmed(hash: String, level: Int)
    }

    enum SendError: LocalizedError, Equatable {
        case noRecipient
        case invalidAmount
        case insufficientFunds(available: Decimal)
        case noSecretKey
        case sendingToSelf
        case passphraseRequired
        case proofNeedsPassphrase
        case notEstimated
        case notSeenYet(String)

        var errorDescription: String? {
            switch self {
            case .noRecipient: "Enter a valid address or pick one from your list."
            case .invalidAmount: "Enter an amount in tez."
            case .insufficientFunds(let available): "Not enough spendable tez. Available: \(AssetBalance.format(available, symbol: "tz"))."
            case .noSecretKey: "Signet has no usable secret key for this account."
            case .sendingToSelf: "That is this account's own address."
            case .passphraseRequired: "Enter the password for this account's key."
            case .proofNeedsPassphrase: "This account's first operation reveals its key with a proof of possession, which the key must sign. Enter the account's password to continue."
            case .notEstimated: "The fee has not been estimated yet; go back and try again."
            case .notSeenYet(let hash): "Operation \(hash.prefix(12))… has not appeared in a block yet. The node may still have it; wait, or send the same signed operation again. It cannot be paid twice."
            }
        }
    }

    /// Who the recipient is, once resolved.
    struct Recipient: Equatable {
        let address: Address
        /// Set when the address is one of our wallets or address-book entries.
        let wallet: Wallet?
        var profile: AccountProfile?
        var domains: [String] = []

        var isVerified: Bool { wallet != nil }
        /// Best display name: our alias, else the TzProfiles name, else the `.tez` name, else the short address.
        var displayName: String {
            wallet?.alias ?? profile?.name ?? domains.first ?? address.shortened()
        }
    }

    /// The sender as given, plus its BLS proof of possession once one had to be made (tz4).
    private(set) var sender: Wallet
    private let wallets: [Wallet]
    private let chain: any ChainService
    /// Etherlink's Michelson interface: only tz1, tz2 and tz3 accounts can be sent to there.
    let implicitAccountsOnly: Bool
    private let signerProvider: @Sendable (Wallet, String?) throws -> SigningKey?
    /// Makes the sender's BLS proof of possession from its key (`WalletViewModel.proofOfPossession`),
    /// needed to estimate the first operation of a tz4 account; `nil` where none can be made.
    private let proofProvider: (@MainActor @Sendable (Wallet, String?) async throws -> String)?
    private(set) var spendable: Decimal?

    var recipientText = "" { didSet { if recipientText != oldValue { recipientChanged() } } }
    var amountText = ""
    /// Password for an encrypted sender key; asked for on the confirm step.
    var passphrase = ""
    var needsPassphrase: Bool { sender.keyKind == .encrypted }
    /// The estimate needs the sender's proof of possession (an unrevealed tz4 account) and the
    /// key is encrypted, so the password is asked for on the compose step already.
    private(set) var needsPassphraseForProof = false
    /// The sender's key is on a Ledger: the user approves on the device while we wait.
    var signsOnLedger: Bool { sender.keyKind == .ledger }
    private(set) var recipient: Recipient?
    private(set) var isResolving = false
    private(set) var suggestions: [Wallet] = []
    private(set) var estimate: TransferEstimate?
    private(set) var step: Step = .compose
    private(set) var errorMessage: String?
    private(set) var isBusy = false
    /// What was signed and handed to the node; kept so an unknown outcome can be watched or resent, never redone.
    private(set) var sent: SentOperation?

    private var resolveTask: Task<Void, Never>?

    init(sender: Wallet, wallets: [Wallet], chain: any ChainService, spendable: Decimal?,
         implicitAccountsOnly: Bool = false,
         signerProvider: @escaping @Sendable (Wallet, String?) throws -> SigningKey?,
         proofProvider: (@MainActor @Sendable (Wallet, String?) async throws -> String)? = nil) {
        self.sender = sender
        self.wallets = wallets
        self.chain = chain
        self.spendable = spendable
        self.implicitAccountsOnly = implicitAccountsOnly
        self.signerProvider = signerProvider
        self.proofProvider = proofProvider
        self.suggestions = candidates(matching: "")
    }

    /// Whether `address` can receive here: anything on Tezos, tz1 to tz3 on Etherlink.
    func accepts(_ address: Address) -> Bool {
        address.isValidAccount && (!implicitAccountsOnly || address.isUsableOnEtherlink)
    }

    /// Recovery is checked before composing a replacement, including after restarting the app.
    func recoverPending() async {
        guard step == .compose else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            if let recovered = try await chain.pendingOperation(for: sender.address) {
                sent = recovered
                await follow(recovered)
            }
        } catch { errorMessage = error.localizedDescription }
    }

    // MARK: Compose

    var amount: Decimal? {
        let text = amountText.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        guard let value = Decimal(string: text, locale: Locale(identifier: "en_US_POSIX")), value > 0 else { return nil }
        return value
    }

    var canProceed: Bool { recipient != nil && amount != nil && !isBusy && !isResolving && !(needsPassphraseForProof && passphrase.isEmpty) }

    /// Everything except a small reserve for the fee.
    func useMaximum() {
        guard let spendable, spendable > 0 else { return }
        let reserve = Decimal(string: "0.001")!
        let value = max(0, spendable - reserve)
        amountText = NSDecimalNumber(decimal: value).stringValue
    }

    func choose(_ wallet: Wallet) {
        recipientText = wallet.address.value
    }

    private func candidates(matching text: String) -> [Wallet] {
        let needle = text.trimmingCharacters(in: .whitespaces).lowercased()
        return wallets
            .filter { $0.address != sender.address && accepts($0.address) }
            .filter { needle.isEmpty || $0.alias.lowercased().contains(needle) || $0.address.value.lowercased().hasPrefix(needle) }
    }

    private func recipientChanged() {
        resolveTask?.cancel()
        recipient = nil
        errorMessage = nil
        let text = recipientText.trimmingCharacters(in: .whitespacesAndNewlines)
        suggestions = candidates(matching: text)

        let typed = Address(text)
        if typed.isValidAccount, !accepts(typed) {
            errorMessage = "On Etherlink, send only to tz1, tz2 or tz3 accounts."
        } else if typed.isValidAccount {
            resolve(typed)
        } else if text.lowercased().hasSuffix(".tez"), text.count > 4 {
            isResolving = true
            resolveTask = Task { [chain] in
                try? await Task.sleep(for: .milliseconds(350))
                guard !Task.isCancelled else { return }
                let address = try? await chain.resolveDomain(text)
                guard !Task.isCancelled else { return }
                if let address, accepts(address) { resolve(address, via: text) } else { isResolving = false }
            }
        } else {
            isResolving = false
        }
    }

    private func resolve(_ address: Address, via domain: String? = nil) {
        let known = wallets.first { $0.address == address }
        var resolved = Recipient(address: address, wallet: known)
        if let domain { resolved.domains = [domain.lowercased()] }
        recipient = resolved
        isResolving = false
        resolveTask?.cancel()
        resolveTask = Task { [chain] in
            async let profile = try? chain.accountProfile(for: address)
            async let domains = try? chain.domains(for: address)
            let (p, d) = await (profile, domains)
            guard !Task.isCancelled, recipient?.address == address else { return }
            recipient?.profile = p ?? nil
            if let d, !d.isEmpty { recipient?.domains = d }
        }
    }

    // MARK: Confirm

    func proceedToConfirm() async {
        await recoverPending()
        guard step == .compose else { return }
        errorMessage = nil
        guard let recipient else { errorMessage = SendError.noRecipient.localizedDescription; return }
        guard let amount else { errorMessage = SendError.invalidAmount.localizedDescription; return }
        guard recipient.address != sender.address else { errorMessage = SendError.sendingToSelf.localizedDescription; return }
        if let spendable, amount > spendable { errorMessage = SendError.insufficientFunds(available: spendable).localizedDescription; return }

        isBusy = true
        defer { isBusy = false }
        do {
            let estimate = try await estimateTransfer(to: recipient.address, amount: amount)
            if let spendable, estimate.total > spendable {
                errorMessage = SendError.insufficientFunds(available: spendable).localizedDescription
                return
            }
            self.estimate = estimate
            step = .confirm
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// The estimate, made again with the sender's proof of possession when the node needs one:
    /// an unrevealed tz4 account's reveal carries a BLS proof only its key can sign, so the key is
    /// used once here, with the password for an encrypted key, which the compose step then asks for.
    private func estimateTransfer(to destination: Address, amount: Decimal) async throws -> TransferEstimate {
        do {
            return try await chain.estimateTransfer(from: sender, to: destination, amount: amount)
        } catch ChainError.proofOfPossessionRequired {
            guard let proofProvider else { throw ChainError.proofOfPossessionRequired }
            if needsPassphrase, passphrase.isEmpty {
                needsPassphraseForProof = true
                throw SendError.proofNeedsPassphrase
            }
            sender.proofOfPossession = try await proofProvider(sender, needsPassphrase ? passphrase : nil)
            needsPassphraseForProof = false
            return try await chain.estimateTransfer(from: sender, to: destination, amount: amount)
        }
    }

    func backToCompose() {
        step = .compose
        estimate = nil
        errorMessage = nil
    }

    // MARK: Send

    /// Signs and sends exactly what the confirm step showed: the approved estimate's limits are
    /// the operation's limits (S14). A lost reply leaves the sheet on the unknown-outcome step,
    /// where only watching the chain or resending the same bytes is possible (S15).
    func send() async {
        guard step == .confirm, let recipient, let amount else { return }
        errorMessage = nil
        isBusy = true
        defer { isBusy = false }
        do {
            if needsPassphrase, passphrase.isEmpty { throw SendError.passphraseRequired }
            guard let limits = estimate?.limits else { throw SendError.notEstimated }
            guard let signer = try signerProvider(sender, needsPassphrase ? passphrase : nil) else { throw SendError.noSecretKey }
            step = .sending
            let sent = try await chain.sendTransfer(from: sender, signer: signer, to: recipient.address, amount: amount, limits: limits)
            self.sent = sent
            await follow(sent)
        } catch {
            errorMessage = error.localizedDescription
            if case .sending = step { step = .confirm }
        }
    }

    /// Watches the chain for the sent operation; an unknown outcome stays visible until it is seen.
    private func follow(_ sent: SentOperation) async {
        step = sent.injected ? .sent(hash: sent.hash) : .unknown(hash: sent.hash)
        do {
            let level = try await chain.waitForConfirmation(of: sent.hash)
            step = .confirmed(hash: sent.hash, level: level)
        } catch {
            errorMessage = sent.injected ? error.localizedDescription : SendError.notSeenYet(sent.hash).localizedDescription
        }
    }

    /// Sends the same signed bytes again after an unknown outcome. Nothing new is signed.
    func rebroadcast() async {
        guard case .unknown = step, let sent, !isBusy else { return }
        errorMessage = nil
        isBusy = true
        defer { isBusy = false }
        do {
            let again = try await chain.rebroadcast(sent)
            self.sent = again
            await follow(again)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
