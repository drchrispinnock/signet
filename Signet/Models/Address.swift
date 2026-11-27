import Foundation

/// A Tezos address with helpers for display. Validation of the base58 payload lives in the
/// chain service; this type only understands the textual shape.
struct Address: Hashable, Codable, Sendable {
    let value: String

    init(_ value: String) {
        self.value = value
    }

    var scheme: AddressScheme? { AddressScheme(address: value) }

    /// Prefixes that denote an account something can be sent to: implicit (tz1–tz6) or contract (KT1).
    static let accountPrefixes: Set<String> = Set(AddressScheme.allCases.map(\.rawValue)).union(["KT1"])

    /// True when this is a well-formed Tezos account address: known prefix, 20-byte hash, valid checksum.
    /// Works for every scheme including tz5/tz6, which Taquito does not yet know.
    var isValidAccount: Bool {
        guard Self.accountPrefixes.contains(String(value.prefix(3))), value.count == 36,
              let body = Base58.checkDecode(value)
        else { return false }
        return body.count == 3 + 20
    }

    var isContract: Bool { value.hasPrefix("KT1") }

    /// Whether the Etherlink rollup accepts this key through its Tezos-style RPC: a scheme check
    /// only (tz1 to tz3 for now), not validity or anything about the account on chain.
    var isUsableOnEtherlink: Bool {
        scheme.map { [.tz1, .tz2, .tz3].contains($0) } ?? false
    }

    /// Shortened form for headers, e.g. `tz1VSUr8wwN...Th8Cjcjb`. Keeps the full prefix so the
    /// scheme stays visible and enough of each end to tell similar addresses apart.
    func shortened(prefix: Int = 11, suffix: Int = 8) -> String {
        guard value.count > prefix + suffix + 3 else { return value }
        return "\(value.prefix(prefix))...\(value.suffix(suffix))"
    }
}

/// A Tezos Domains name tied to an account: one it owns, one that points at it, or both.
struct TezosDomain: Identifiable, Equatable, Sendable {
    var id: String { name }
    let name: String
    /// Where the name points; `nil` when it points nowhere.
    let address: Address?
    let owner: Address?
    /// `nil` for a subdomain, which lives as long as its parent.
    let expires: Date?
    /// The name this account publishes as its own (reverse record).
    let isReverseRecord: Bool
    /// The name's FA2 token in the Tezos Domains registry: second-level names only (`nil` for a
    /// subdomain, which changes hands through `update_record` instead).
    var tokenId: Int? = nil
    /// The record's data (key to hex bytes), which `update_record` replaces as a whole, so a
    /// transfer sends it back unchanged.
    var data: [String: String] = [:]

    func isExpired(at now: Date = Date()) -> Bool { expires.map { $0 <= now } ?? false }

    /// Tezos Domains' mainnet contracts: the NameRegistry, whose FA2 `transfer` moves a
    /// second-level name's token (and with it the ownership), and the UpdateRecord proxy.
    static let registry = "KT1GBZmSxmnKJXGMdMLbugPfLyUPmuLSMwKS"
    static let updateRecordProxy = "KT1H1MqmUM4aK9i1833EBmYCCEfkbt6ZdSBc"

    /// What hands this name from `owner` to `recipient`, or `nil` when `owner` does not hold it
    /// or it has expired. A second-level name moves as its FA2 token, which changes the owner
    /// but not where the name points; with `pointAtRecipient` an `update_record` setting the
    /// address to the recipient goes first (only the owner may make it). A subdomain has no
    /// token and changes owner through `update_record` alone. The record's data is kept.
    func transferParts(from owner: Address, to recipient: Address, pointAtRecipient: Bool, now: Date = Date())
        -> (records: [DomainRecordUpdate], transfers: [TokenTransfer])? {
        guard isOwned(by: owner), !isExpired(at: now), owner != recipient else { return nil }
        if let tokenId {
            let record = DomainRecordUpdate(proxy: Self.updateRecordProxy, name: name, address: recipient.value, owner: owner.value, data: data)
            return (pointAtRecipient ? [record] : [], [TokenTransfer(contract: Self.registry, tokenId: String(tokenId), amount: "1")])
        }
        let target = pointAtRecipient ? recipient.value : address?.value
        return ([DomainRecordUpdate(proxy: Self.updateRecordProxy, name: name, address: target, owner: recipient.value, data: data)], [])
    }

    func isOwned(by account: Address) -> Bool { owner == account }
    func pointsAt(_ account: Address) -> Bool { address == account }

    /// The name's page on the Tezos Domains app (mainnet).
    var appURL: URL? { URL(string: "https://app.tezos.domains/domain/\(name)") }
}
