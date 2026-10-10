import Foundation

/// A named multisig contract: an octez-client `contracts` alias pointing at a KT1 address.
struct MultisigContract: Identifiable, Hashable, Sendable {
    var alias: String
    let address: Address
    var id: String { alias }
}

/// What the chain says about a multisig contract right now.
struct MultisigInfo: Hashable, Sendable {
    let address: Address
    /// The contract's code is octez-client's generic multisig; nothing below is meaningful otherwise.
    let isGenericMultisig: Bool
    let scriptHash: String
    let counter: Int
    let threshold: Int
    /// Base58 public keys in storage order; signatures are placed by that order.
    let keys: [String]
    let balance: Decimal

    /// Our wallets that can sign for this multisig.
    func signers(among wallets: [Wallet]) -> [Wallet] {
        wallets.filter { wallet in wallet.keyKind.canSign && wallet.publicKey.map(keys.contains) == true }
    }

    /// Any of our wallets whose key is listed, signing or not (watch-only Ledger entries etc.).
    func members(among wallets: [Wallet]) -> [Wallet] {
        wallets.filter { wallet in wallet.publicKey.map(keys.contains) == true }
    }
}

/// One signer's signature over a proposal's bytes.
struct MultisigSignature: Codable, Hashable, Sendable {
    let publicKey: String?
    let signature: String
}

/// What a multisig is asked to do: the lambda the signers sign. Both are what octez-client's
/// `prepare multisig transaction … transferring` / `setting delegate to` / `withdrawing delegate` make.
enum MultisigAction: Codable, Hashable, Sendable {
    /// Amount in mutez, as a string so nothing rounds.
    case transfer(amountMutez: String, destination: String)
    /// `nil` withdraws the delegate.
    case setDelegate(delegate: String?)

    var amount: Decimal {
        if case .transfer(let mutez, _) = self { return Mutez.toTez(mutez) ?? 0 }
        return 0
    }

    /// One line for pickers and confirmations.
    var summary: String {
        switch self {
        case .transfer(_, let destination): "\(AssetBalance.format(amount, symbol: "tz")) to \(Address(destination).shortened())"
        case .setDelegate(let delegate?): "Delegate to \(Address(delegate).shortened())"
        case .setDelegate(nil): "Remove delegate"
        }
    }
}

/// An action proposed from a multisig, with the signatures gathered so far. Kept on disk so the
/// user can pick it up again when the other signers send theirs.
struct MultisigProposal: Codable, Identifiable, Hashable, Sendable {
    var id: UUID = UUID()
    var contractAlias: String
    var contractAddress: String
    var networkName: String
    var chainID: String
    var counter: Int
    var threshold: Int
    var keys: [String]
    var action: MultisigAction
    /// The packed payload every signer signs (hex, `05…`).
    var bytes: String
    var signatures: [MultisigSignature] = []
    var created: Date = Date()

    var amount: Decimal { action.amount }
    var summary: String { action.summary }
    var contract: MultisigContract { MultisigContract(alias: contractAlias, address: Address(contractAddress)) }

    /// Signatures still needed before the proposal can be submitted.
    var missing: Int { max(0, threshold - signatures.count) }
    var isReady: Bool { signatures.count >= threshold }

    func hasSignature(from publicKey: String) -> Bool { signatures.contains { $0.publicKey == publicKey } }
}

/// What a proposed transfer costs the account that submits it. Same shape as a transfer estimate.
typealias MultisigEstimate = TransferEstimate
