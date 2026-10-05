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
        case confirmed(hash: String, level: Int)
    }

    enum SendError: LocalizedError, Equatable {
        case noRecipient
        case invalidAmount
        case insufficientFunds(available: Decimal)
        case noSecretKey
        case sendingToSelf

        var errorDescription: String? {
            switch self {
            case .noRecipient: "Enter a valid address or pick one from your list."
            case .invalidAmount: "Enter an amount in tez."
            case .insufficientFunds(let available): "Not enough spendable tez. Available: \(AssetBalance.format(available, symbol: "tz"))."
            case .noSecretKey: "Signet has no usable secret key for this wallet."
            case .sendingToSelf: "That is this wallet's own address."
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

    let sender: Wallet
    private let wallets: [Wallet]
    private let chain: any ChainService
    private let secretKeyProvider: @Sendable (Wallet) throws -> String?
    private(set) var spendable: Decimal?

    var recipientText = "" { didSet { if recipientText != oldValue { recipientChanged() } } }
    var amountText = ""
    private(set) var recipient: Recipient?
    private(set) var isResolving = false
    private(set) var suggestions: [Wallet] = []
    private(set) var estimate: TransferEstimate?
    private(set) var step: Step = .compose
    private(set) var errorMessage: String?
    private(set) var isBusy = false

    private var resolveTask: Task<Void, Never>?

    init(sender: Wallet, wallets: [Wallet], chain: any ChainService, spendable: Decimal?,
         secretKeyProvider: @escaping @Sendable (Wallet) throws -> String?) {
        self.sender = sender
        self.wallets = wallets
        self.chain = chain
        self.spendable = spendable
        self.secretKeyProvider = secretKeyProvider
        self.suggestions = candidates(matching: "")
    }

    // MARK: Compose

    var amount: Decimal? {
        let text = amountText.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        guard let value = Decimal(string: text, locale: Locale(identifier: "en_US_POSIX")), value > 0 else { return nil }
        return value
    }

    var canProceed: Bool { recipient != nil && amount != nil && !isBusy && !isResolving }

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
            .filter { $0.address != sender.address }
            .filter { needle.isEmpty || $0.alias.lowercased().contains(needle) || $0.address.value.lowercased().hasPrefix(needle) }
    }

    private func recipientChanged() {
        resolveTask?.cancel()
        recipient = nil
        errorMessage = nil
        let text = recipientText.trimmingCharacters(in: .whitespacesAndNewlines)
        suggestions = candidates(matching: text)

        let typed = Address(text)
        if typed.isValidAccount {
            resolve(typed)
        } else if text.lowercased().hasSuffix(".tez"), text.count > 4 {
            isResolving = true
            resolveTask = Task { [chain] in
                try? await Task.sleep(for: .milliseconds(350))
                guard !Task.isCancelled else { return }
                let address = try? await chain.resolveDomain(text)
                guard !Task.isCancelled else { return }
                if let address { resolve(address, via: text) } else { isResolving = false }
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
        errorMessage = nil
        guard let recipient else { errorMessage = SendError.noRecipient.localizedDescription; return }
        guard let amount else { errorMessage = SendError.invalidAmount.localizedDescription; return }
        guard recipient.address != sender.address else { errorMessage = SendError.sendingToSelf.localizedDescription; return }
        if let spendable, amount > spendable { errorMessage = SendError.insufficientFunds(available: spendable).localizedDescription; return }

        isBusy = true
        defer { isBusy = false }
        do {
            let estimate = try await chain.estimateTransfer(from: sender, to: recipient.address, amount: amount)
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

    func backToCompose() {
        step = .compose
        estimate = nil
        errorMessage = nil
    }

    // MARK: Send

    func send() async {
        guard step == .confirm, let recipient, let amount else { return }
        errorMessage = nil
        isBusy = true
        defer { isBusy = false }
        do {
            guard let secretKey = try secretKeyProvider(sender) else { throw SendError.noSecretKey }
            step = .sending
            let hash = try await chain.sendTransfer(from: sender, secretKey: secretKey, to: recipient.address, amount: amount)
            step = .sent(hash: hash)
            let level = try await chain.waitForConfirmation(of: hash)
            step = .confirmed(hash: hash, level: level)
        } catch {
            errorMessage = error.localizedDescription
            if case .sending = step { step = .confirm }
        }
    }
}
