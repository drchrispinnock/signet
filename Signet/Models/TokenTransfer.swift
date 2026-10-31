import Foundation

/// One FA2 token movement: `amount` editions of `tokenId` at `contract`, both as the decimal
/// text of a nat, as the bridge's `tokenTransferParams` reads them.
struct TokenTransfer: Hashable, Sendable, Codable {
    let contract: String
    let tokenId: String
    let amount: String

    init(contract: String, tokenId: String, amount: String) {
        self.contract = contract; self.tokenId = tokenId; self.amount = amount
    }

    init(nft: NFT, amount: Int) {
        self.init(contract: nft.contract, tokenId: nft.tokenId, amount: String(max(0, amount)))
    }

    static func isNat(_ text: String) -> Bool {
        !text.isEmpty && text.count <= 40 && text.allSatisfy(\.isNumber) && (text == "0" || !text.hasPrefix("0"))
    }
    var isValid: Bool { Address(contract).isContract && Address(contract).isValidAccount && Self.isNat(tokenId) && Self.isNat(amount) && amount != "0" }
}

/// Tokens going from the selected account to one recipient in one operation group: the bridge
/// makes one FA2 `transfer` call per contract (`TokenTransferRequest.contracts`, in order of
/// first appearance). A burn is the same request to `burnAddress`.
struct TokenTransferRequest: Hashable, Sendable {
    /// The address marketplaces burn to: no key hashes to it, so tokens sent there never move again.
    static let burnAddress = Address("tz1burnburnburnburnburnburnburjAYjjX")
    /// At most this many tokens in one transfer (the bridge refuses more).
    static let maxTokens = 100

    let to: Address
    let transfers: [TokenTransfer]

    var isBurn: Bool { to == Self.burnAddress }
    var count: Int { transfers.count }
    /// The contracts called, one operation each, in the order they first appear.
    var contracts: [String] {
        var seen: [String] = []
        for transfer in transfers where !seen.contains(transfer.contract) { seen.append(transfer.contract) }
        return seen
    }
    var isValid: Bool {
        to.isValidAccount && !transfers.isEmpty && transfers.count <= Self.maxTokens && transfers.allSatisfy(\.isValid)
    }

    /// As the bridge's `tokenTransferParams` reads the transfers.
    var transfersJSON: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return String(data: (try? encoder.encode(transfers)) ?? Data("[]".utf8), encoding: .utf8) ?? "[]"
    }
}

/// The fee, gas and storage each operation of a batch was approved with, in order, plus the
/// reveal the node will prepend for an unrevealed account: `OperationLimits` for an operation
/// group (S14). The bridge's `parseBatchLimits` / `checkApprovedBatch` enforce them.
struct BatchLimits: Hashable, Sendable, Codable {
    struct Operation: Hashable, Sendable, Codable {
        var feeMutez: String
        var gasLimit: Int
        var storageLimit: Int
    }
    var operations: [Operation]
    var revealFeeMutez: String? = nil
    var revealGasLimit: Int? = nil
    var revealStorageLimit: Int? = nil

    init(operations: [Operation], revealFeeMutez: String? = nil, revealGasLimit: Int? = nil, revealStorageLimit: Int? = nil) {
        self.operations = operations; self.revealFeeMutez = revealFeeMutez; self.revealGasLimit = revealGasLimit; self.revealStorageLimit = revealStorageLimit
    }

    /// As the bridge's `parseBatchLimits` reads them.
    var json: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return String(data: (try? encoder.encode(self)) ?? Data("{}".utf8), encoding: .utf8) ?? "{}"
    }

    /// From a bridge estimate's `limits` object; `nil` when any figure is missing or malformed.
    init?(_ value: JSONValue?) {
        guard let rows = value?["operations"]?.arrayValue, !rows.isEmpty else { return nil }
        var operations: [Operation] = []
        for row in rows {
            guard let fee = row["feeMutez"]?.stringValue, Mutez.isValid(fee),
                  let gas = row["gasLimit"]?.intValue, let storage = row["storageLimit"]?.intValue else { return nil }
            operations.append(Operation(feeMutez: fee, gasLimit: gas, storageLimit: storage))
        }
        self.init(operations: operations, revealFeeMutez: value?["revealFeeMutez"]?.stringValue,
                  revealGasLimit: value?["revealGasLimit"]?.intValue, revealStorageLimit: value?["revealStorageLimit"]?.intValue)
        if let reveal = revealFeeMutez, !Mutez.isValid(reveal) { return nil }
    }
}

/// What a token transfer will cost, in tez, and the exact limits it must be sent with.
struct TokenTransferEstimate: Hashable, Sendable {
    /// The whole fee, the reveal included when the account needs one.
    let fee: Decimal
    /// Storage burn: the contract's ledger grows when the recipient has never held the token.
    let burn: Decimal
    var total: Decimal { fee + burn }
    let limits: BatchLimits
}

/// An operation the NFT grid's context menu starts on one or more tokens; what the sheet opens with.
struct NFTOperation: Identifiable, Hashable, Sendable {
    enum Kind: Hashable, Sendable { case transfer, burn }
    let kind: Kind
    let nfts: [NFT]
    var id: String { "\(kind):" + nfts.map(\.id).joined(separator: ",") }
    /// Every token sits on the same layer (the menu refuses a selection spanning both).
    var layer: Int { nfts.first?.layer ?? 1 }
}
