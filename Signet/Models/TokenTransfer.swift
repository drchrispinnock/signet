import Foundation

/// One token movement: `amount` (in the token's smallest unit, or editions of an NFT) of
/// `tokenId` at `contract`, both as the decimal text of a nat, as the bridge's
/// `tokenTransferParams` reads them. `standard` is `nil` for FA2 and `"fa1.2"` for an FA1.2
/// token, which has a `transfer` of its own and no token ids (its id is 0).
struct TokenTransfer: Hashable, Sendable, Codable {
    let contract: String
    let tokenId: String
    let amount: String
    var standard: String? = nil

    init(contract: String, tokenId: String, amount: String, standard: String? = nil) {
        self.contract = contract; self.tokenId = tokenId; self.amount = amount; self.standard = standard
    }

    init(nft: NFT, amount: Int) {
        self.init(contract: nft.contract, tokenId: nft.tokenId, amount: String(max(0, amount)))
    }

    /// `rawAmount` of a fungible token from the Assets tab (`AssetBalance.rawAmount` for all of it).
    init?(token: AssetBalance, rawAmount: String) {
        guard case .token(let contract, let tokenId) = token.kind else { return nil }
        self.init(contract: contract, tokenId: tokenId, amount: rawAmount, standard: token.isFA12 ? "fa1.2" : nil)
    }

    var isFA12: Bool { standard == "fa1.2" }

    static func isNat(_ text: String) -> Bool {
        !text.isEmpty && text.count <= 40 && text.allSatisfy(\.isNumber) && (text == "0" || !text.hasPrefix("0"))
    }
    var isValid: Bool {
        Address(contract).isContract && Address(contract).isValidAccount && Self.isNat(tokenId) && Self.isNat(amount) && amount != "0"
            && (standard == nil || (standard == "fa1.2" && tokenId == "0"))
    }

    /// The smallest-unit amount for `text` typed in whole units of a token with `decimals`
    /// places (`"1.5"` with 6 decimals is `"1500000"`): digits only, no more decimal places
    /// than the token has, not zero. `nil` otherwise. Exact: no floating point.
    static func rawAmount(from text: String, decimals: Int) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        let parts = trimmed.split(separator: ".", omittingEmptySubsequences: false)
        guard (1...2).contains(parts.count), decimals >= 0 else { return nil }
        let whole = String(parts[0]), fraction = parts.count == 2 ? String(parts[1]) : ""
        guard !(whole.isEmpty && fraction.isEmpty), whole.allSatisfy(\.isASCIIDigit), fraction.allSatisfy(\.isASCIIDigit), fraction.count <= decimals else { return nil }
        let digits = (whole + fraction + String(repeating: "0", count: decimals - fraction.count)).drop { $0 == "0" }
        guard !digits.isEmpty, digits.count <= 40 else { return nil }
        return String(digits)
    }

    /// Whether the nat `a` is at most the nat `b` (both canonical decimal text).
    static func nat(_ a: String, isAtMost b: String) -> Bool {
        a.count != b.count ? a.count < b.count : a <= b
    }
}

private extension Character {
    var isASCIIDigit: Bool { ("0"..."9").contains(self) }
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
    /// Move Assets: a tez transfer of this many mutez to `to`, sent last in the same group, so
    /// the tokens and the account's tez go under one signature. `nil` for a plain token transfer.
    var tezMutez: String? = nil
    /// Tezos Domains `update_record` calls, sent first (only the current owner may make them).
    var records: [DomainRecordUpdate] = []

    init(to: Address, transfers: [TokenTransfer], tezMutez: String? = nil, records: [DomainRecordUpdate] = []) {
        self.to = to; self.transfers = transfers; self.tezMutez = tezMutez; self.records = records
    }

    /// As the bridge's `tokenTransferParams` reads the records.
    var recordsJSON: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return String(data: (try? encoder.encode(records)) ?? Data("[]".utf8), encoding: .utf8) ?? "[]"
    }
    /// The arguments after the transfers that the bridge's estimate and send take: the tez (""
    /// for none) and the records, each only when needed.
    var extraBridgeArguments: [String] {
        records.isEmpty ? (tezMutez.map { [$0] } ?? []) : [tezMutez ?? "", recordsJSON]
    }

    var isBurn: Bool { to == Self.burnAddress }
    /// Operations in the group, as the approved limits must list them: one per FA2 contract and
    /// one per FA1.2 transfer, in the order they first appear, then the tez.
    var operationCount: Int { records.count + contracts.count + (tezMutez == nil ? 0 : 1) }
    var count: Int { transfers.count }
    /// The contract of each token call, as the bridge builds them: an FA2 contract once, at its
    /// first transfer; an FA1.2 contract once per transfer (its `transfer` moves one amount).
    var contracts: [String] {
        var calls: [String] = []
        for transfer in transfers where transfer.isFA12 || !calls.contains(transfer.contract) { calls.append(transfer.contract) }
        return calls
    }
    /// A contract named both as FA2 and as FA1.2 in one request cannot be right.
    private var standardsAgree: Bool {
        Dictionary(grouping: transfers, by: \.contract).values.allSatisfy { Set($0.map(\.isFA12)).count == 1 }
    }
    var isValid: Bool {
        guard standardsAgree else { return false }
        if let tezMutez, !(Mutez.isValid(tezMutez) && tezMutez != "0" && !tezMutez.hasPrefix("0") && (Int64(tezMutez) ?? .max) <= 9_007_199_254_740_991) { return false }
        if tezMutez != nil, isBurn { return false }
        return to.isValidAccount && (!transfers.isEmpty || tezMutez != nil || !records.isEmpty) && transfers.count <= Self.maxTokens
            && transfers.allSatisfy(\.isValid) && records.allSatisfy(\.isValid)
    }

    /// As the bridge's `tokenTransferParams` reads the transfers.
    var transfersJSON: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return String(data: (try? encoder.encode(transfers)) ?? Data("[]".utf8), encoding: .utf8) ?? "[]"
    }
}

/// A Tezos Domains record change: `update_record` on the UpdateRecord proxy, as the bridge's
/// `domainRecordCall` builds it. `data` (key to hex bytes) replaces the record's data as a
/// whole, so it carries the existing entries.
struct DomainRecordUpdate: Hashable, Sendable, Codable {
    let proxy: String
    let name: String
    let address: String?
    let owner: String
    var data: [String: String] = [:]

    var isValid: Bool {
        Address(proxy).isContract && !name.isEmpty && name.count <= 255 && name == name.lowercased()
            && Address(owner).isValidAccount && (address.map { Address($0).isValidAccount } ?? true)
            && data.values.allSatisfy { $0.count.isMultiple(of: 2) && $0.allSatisfy(\.isHexDigit) && $0 == $0.lowercased() }
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
