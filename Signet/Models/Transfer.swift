import Foundation

/// What a transfer will cost, in tez.
struct TransferEstimate: Hashable, Sendable {
    /// The whole fee, the reveal included when the account needs one.
    let fee: Decimal
    /// Storage burn, e.g. the allocation cost when the destination has never held tez.
    let burn: Decimal
    let total: Decimal
    let gasLimit: Int
    let storageLimit: Int
    /// The exact limits the operation must be sent with; `nil` for estimates no operation can be sent from.
    var limits: OperationLimits? = nil
}

/// The fee, gas and storage an operation was approved with, in mutez and units, plus the reveal
/// the node will prepend for an unrevealed account. The bridge sends with exactly these and
/// refuses anything that would cost more; nothing is re-estimated after approval (S14).
struct OperationLimits: Hashable, Sendable, Codable {
    var feeMutez: String
    var gasLimit: Int
    var storageLimit: Int
    var revealFeeMutez: String? = nil
    var revealGasLimit: Int? = nil
    var revealStorageLimit: Int? = nil

    /// As the bridge's `parseLimits` reads them.
    var json: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return String(data: (try? encoder.encode(self)) ?? Data("{}".utf8), encoding: .utf8) ?? "{}"
    }

    init(feeMutez: String, gasLimit: Int, storageLimit: Int, revealFeeMutez: String? = nil, revealGasLimit: Int? = nil, revealStorageLimit: Int? = nil) {
        self.feeMutez = feeMutez; self.gasLimit = gasLimit; self.storageLimit = storageLimit
        self.revealFeeMutez = revealFeeMutez; self.revealGasLimit = revealGasLimit; self.revealStorageLimit = revealStorageLimit
    }

    /// From a bridge estimate's `limits` object; `nil` when any figure is missing or malformed.
    init?(_ value: JSONValue?) {
        guard let fee = value?["feeMutez"]?.stringValue, Mutez.isValid(fee),
              let gas = value?["gasLimit"]?.intValue, let storage = value?["storageLimit"]?.intValue else { return nil }
        self.init(feeMutez: fee, gasLimit: gas, storageLimit: storage,
                  revealFeeMutez: value?["revealFeeMutez"]?.stringValue, revealGasLimit: value?["revealGasLimit"]?.intValue, revealStorageLimit: value?["revealStorageLimit"]?.intValue)
        if let reveal = revealFeeMutez, !Mutez.isValid(reveal) { return nil }
    }
}

/// An operation that was signed and handed to the node. `injected` is false when the node's
/// answer was lost: the operation may or may not be in its mempool, so the right move is to
/// watch the chain for `hash` or send `signedBytes` again, never to make a new operation (S15).
struct SentOperation: Hashable, Sendable {
    let hash: String
    let injected: Bool
    let signedBytes: String?
    let originatedAddress: String?

    init(hash: String, injected: Bool = true, signedBytes: String? = nil, originatedAddress: String? = nil) {
        self.hash = hash; self.injected = injected; self.signedBytes = signedBytes; self.originatedAddress = originatedAddress
    }

    /// From the bridge's `{ hash, injected, signedBytes }`.
    init?(_ value: JSONValue) {
        guard let hash = value["hash"]?.stringValue, !hash.isEmpty else { return nil }
        self.init(hash: hash, injected: value["injected"]?.boolValue ?? true, signedBytes: value["signedBytes"]?.stringValue, originatedAddress: value["address"]?.stringValue)
    }
}

/// Public identity an indexer knows for an address: the TzProfiles data TzKT carries.
struct AccountProfile: Hashable, Sendable {
    let name: String?
    let twitter: String?
    let description: String?
}

/// 1 tez = 1,000,000 mutez.
enum Mutez {
    /// A non-negative whole number of mutez as a decimal string, as the bridge reports fees.
    static func isValid(_ text: String) -> Bool {
        !text.isEmpty && text.count <= 20 && text.allSatisfy(\.isNumber)
    }

    static let perTez = Decimal(1_000_000)

    static func fromTez(_ tez: Decimal) -> String {
        var scaled = tez * perTez
        var rounded = Decimal()
        NSDecimalRound(&rounded, &scaled, 0, .down)
        return NSDecimalNumber(decimal: rounded).stringValue
    }

    static func toTez(_ mutez: String?) -> Decimal? {
        mutez.flatMap { Decimal(string: $0) }.map { $0 / perTez }
    }
}
